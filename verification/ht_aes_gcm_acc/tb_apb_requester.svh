// -------------------------------------------------------------------------------------------------
// Project      : AES-GCM Accelerator - acceptance simulation testbench
// File         : tb_apb_requester.svh (included inside module tb_aesgcm_top)
// Description  : APB4 requester model written from Arm IHI 0024D chapters 3 and 4 and spec 11.4.
//                - SETUP for one cycle, ACCESS until PREADY (any number of completer wait states).
//                - Address, control, write data, strobes and protection held stable until the
//                  transfer completes; PSTRB is 0 in reads (IHI0024D 3.2).
//                - Random idle gap of 0..apb_gap_max cycles before each transfer (+APB_GAP=<n>);
//                  a gap of 0 keeps PSEL high from ACCESS into the next SETUP (IHI0024D 4.1).
//                - PPROT per transfer (default apb_prot_dflt, +APB_PROT=<n>); PSLVERR returned to the
//                  caller and an unexpected PSLVERR is counted as a testcase failure.
//                - Bounded: a transfer without PREADY for apb_timeout cycles is reported and ended.
//                - A lock serializes the main test thread, the DMA model and the pollers.
//                Software-visible shadows used by the assertions (aesgcm_irq_en, aesgcm_dmacfg) are
//                updated from the completed writes.
// -------------------------------------------------------------------------------------------------

// Signals and settings are declared in tb_aesgcm_decl.svh.

task automatic apb_idle();
  apb_psel    <= 1'b0;
  apb_penable <= 1'b0;
  apb_pwrite  <= 1'b0;
  apb_paddr   <= 16'h0;
  apb_pwdata  <= 32'h0;
  apb_pstrb   <= 4'h0;
  apb_pprot   <= 3'b000;
endtask

// One APB transfer. Must be called just after a rising edge of i_clk_bus (all tasks stay aligned).
task automatic apb_xfer(input bit wr, input logic [15:0] addr, input logic [31:0] wdata,
                        input logic [3:0] strb, input logic [2:0] prot,
                        output logic [31:0] rdata, output logic slverr);
  int n;
  int gap;
  while (apb_lock != 0) @(posedge clk_bus);
  apb_lock = 1;
  gap = (apb_gap_max > 0) ? int'(rnd_range(0, apb_gap_max)) : 0;
  repeat (gap) @(posedge clk_bus);
  // SETUP phase
  apb_psel    <= 1'b1;
  apb_penable <= 1'b0;
  apb_pwrite  <= wr;
  apb_paddr   <= addr;
  apb_pwdata  <= wr ? wdata : 32'h0;
  apb_pstrb   <= wr ? strb : 4'h0;
  apb_pprot   <= prot;
  @(posedge clk_bus);
  // ACCESS phase
  apb_penable <= 1'b1;
  @(posedge clk_bus);
  n = 0;
  while ((o_apb_pready !== 1'b1) && (n < apb_timeout)) begin
    @(posedge clk_bus);
    n++;
  end
  if (n >= apb_timeout) begin
    apb_hang++;
    $display("TB-ERROR @%0t: APB transfer to 0x%04h without PREADY for %0d cycles", $time, addr, n);
    rdata  = 32'hDEAD_BEEF;
    slverr = 1'b1;
  end else begin
    rdata  = o_apb_prdata;
    slverr = o_apb_pslverr;
  end
  // Completion: the next call in the same time step overrides these and keeps PSEL high.
  apb_psel    <= 1'b0;
  apb_penable <= 1'b0;
  apb_pstrb   <= 4'h0;
  if (wr && !slverr && (strb == 4'hF)) apb_shadow_update(addr, wdata);
  apb_lock = 0;
endtask

// Shadows of software-visible control written by the testbench (inputs of the assertion module).
task automatic apb_shadow_update(input logic [15:0] addr, input logic [31:0] wdata);
  case (addr)
    A_IRQ_EN: sh_irq_en  = wdata[9:0];
    A_DMACFG: sh_dmacfg  = wdata[7:0];
    A_CFG:    sh_cfg     = wdata;
    A_DATALEN: sh_datalen = wdata;
    default: ;
  endcase
endtask

task automatic apb_wr(input logic [15:0] addr, input logic [31:0] wdata);
  logic [31:0] rd;
  logic        err;
  apb_xfer(1'b1, addr, wdata, 4'hF, apb_prot_dflt, rd, err);
  if (err) begin
    apb_unexp_err++;
    $display("TB-ERROR @%0t: unexpected PSLVERR on write 0x%04h", $time, addr);
  end
endtask

task automatic apb_rd(input logic [15:0] addr, output logic [31:0] rdata);
  logic err;
  apb_xfer(1'b0, addr, 32'h0, 4'h0, apb_prot_dflt, rdata, err);
  if (err) begin
    apb_unexp_err++;
    $display("TB-ERROR @%0t: unexpected PSLVERR on read 0x%04h", $time, addr);
  end
endtask

// Poll a register until (value & mask) == want, bounded by max_polls reads.
task automatic apb_poll(input logic [15:0] addr, input logic [31:0] mask, input logic [31:0] want,
                        input int max_polls, output logic [31:0] last, output bit ok);
  ok = 1'b0;
  for (int i = 0; i < max_polls; i++) begin
    apb_rd(addr, last);
    if ((last & mask) == want) begin
      ok = 1'b1;
      break;
    end
  end
endtask
