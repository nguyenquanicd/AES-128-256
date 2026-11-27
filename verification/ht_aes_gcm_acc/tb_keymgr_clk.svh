// -------------------------------------------------------------------------------------------------
// Project      : AES-GCM Accelerator - acceptance simulation testbench
// File         : tb_keymgr_clk.svh (included inside module tb_aesgcm_top)
// Description  : Key-manager model of the side-load contract (spec 6.3.5, 6.2), clock generators
//                and reset sequencer (spec 7.1, 7.3, REQ-CLK-001..003, REQ-RESET-001).
//
//   Key manager (CORE domain, synchronous to i_clk_core by contract, ASM-005): raises
//   i_key_side_valid with i_key_side_size and i_key_side stable, holds them until o_key_side_ack is
//   sampled high, then drops valid. Byte 0 of the key is at bits [255:248]; a 128-bit key uses
//   bits [255:128] and drives [127:0] = 0 (spec 6.2).
//
//   Clocks:
//     PARA_CLK_ASYNC = 1: no relationship. Bus period +TBUS_PS (default 10000 ps), core period
//       +TCORE_PS (default random 6000..8000 ps from the seed), random start phases (TEST-022).
//     PARA_CLK_ASYNC = 0: one common source, fixed phase, period ratio Tbus:Tcore selected by
//       +CLK_RATIO=1_1 | 3_2 | 4_1 | 1_4 (REQ-CLK-003, TEST-023; 3:2 is the WF-016 case, 4:1 is the
//       50 MHz bus / 200 MHz core example of FEAT-011). Base unit 5000 ps.
//   Resets: asserted asynchronously at any time, released synchronously to the rising edge of each
//   domain clock (REQ-RESET-001: the SoC delivers the synchronized release).
// -------------------------------------------------------------------------------------------------

// Signals are declared in tb_aesgcm_decl.svh.

task automatic km_idle();
  km_valid <= 1'b0;
  km_size  <= 1'b0;
  km_key   <= '0;
endtask

function automatic logic [255:0] side_key_from_msg();
  logic [255:0] k;
  k = '0;
  for (int i = 0; i < 32; i++) begin
    if ((m_ksz == 1) || (i < 16)) k[255 - 8 * i -: 8] = m_key[i / 4][8 * (i % 4) +: 8];
  end
  return k;
endfunction

// Offer the key of the current message after delay core clocks; wait at most hold_max clocks.
task automatic km_offer(input int delay, input int hold_max, output bit acked);
  int n;
  acked = 1'b0;
  repeat (delay) @(posedge clk_core);
  km_size  <= m_ksz[0];
  km_key   <= side_key_from_msg();
  km_valid <= 1'b1;
  @(posedge clk_core);
  n = 0;
  while ((o_key_side_ack !== 1'b1) && (n < hold_max)) begin @(posedge clk_core); n++; end
  if (o_key_side_ack === 1'b1) begin
    acked = 1'b1;
    km_acks++;
  end
  km_valid <= 1'b0;
  km_key   <= '0;
  @(posedge clk_core);
endtask

// ------------------------------------------------------------------------------ clocks
task automatic clk_configure();
  int unsigned v;
  if (C_ASYNC == 1) begin
    t_bus_per  = 10000;
    t_core_per = 6000 + 2 * (rnd32() % 1001);
    if ($value$plusargs("TBUS_PS=%d", v)) t_bus_per = v;
    if ($value$plusargs("TCORE_PS=%d", v)) t_core_per = v;
    t_bus_per  = t_bus_per & ~32'h1;
    t_core_per = t_core_per & ~32'h1;
    t_bus_ph   = rnd32() % t_bus_per;
    t_core_ph  = rnd32() % t_core_per;
  end else begin
    if (!$value$plusargs("CLK_RATIO=%s", clk_ratio_s)) clk_ratio_s = "1_1";
    if (clk_ratio_s == "3_2")      begin t_bus_per = 15000; t_core_per = 10000; end
    else if (clk_ratio_s == "4_1") begin t_bus_per = 20000; t_core_per = 5000;  end
    else if (clk_ratio_s == "1_4") begin t_bus_per = 5000;  t_core_per = 20000; end
    else begin clk_ratio_s = "1_1"; t_bus_per = 10000; t_core_per = 10000; end
    t_bus_ph  = 0;
    t_core_ph = 0;
  end
  t_bus_half  = t_bus_per / 2;
  t_core_half = t_core_per / 2;
  $display("TB-INFO: clocks %0s: Tbus %0d ps (phase %0d), Tcore %0d ps (phase %0d)%0s",
           (C_ASYNC == 1) ? "asynchronous" : "synchronous", t_bus_per, t_bus_ph, t_core_per,
           t_core_ph, (C_ASYNC == 1) ? "" : {" ratio ", clk_ratio_s});
  clk_cfg_done = 1'b1;
endtask

initial begin : gen_clk_bus
  wait (clk_cfg_done);
  #(t_bus_ph);
  forever begin
    #(t_bus_half);
    clk_bus = ~clk_bus;
  end
end

initial begin : gen_clk_core
  wait (clk_cfg_done);
  #(t_core_ph);
  forever begin
    #(t_core_half);
    clk_core = ~clk_core;
  end
end

always @(posedge clk_bus)  cyc_bus  <= cyc_bus + 1;
always @(posedge clk_core) cyc_core <= cyc_core + 1;

// ------------------------------------------------------------------------------ resets
task automatic tb_drive_idle();
  apb_idle();
  axi_idle();
  dma_idle();
  km_idle();
endtask

// Assert both resets asynchronously, release each synchronously (REQ-RESET-001).
task automatic do_reset(input int ncyc);
  #(t_bus_per / 3);
  rst_n_bus  = 1'b0;
  rst_n_core = 1'b0;
  protect_en = pend_protect_en;      // static inputs change only while the reset is asserted
  slverr_en  = pend_slverr_en;
  tb_drive_idle();
  repeat (ncyc) @(posedge clk_bus);
  repeat (ncyc) @(posedge clk_core);
  fork
    begin @(posedge clk_bus);  rst_n_bus  <= 1'b1; end
    begin @(posedge clk_core); rst_n_core <= 1'b1; end
  join
  repeat (8) @(posedge clk_core);
  repeat (8) @(posedge clk_bus);
endtask

// Reset one domain only (ERR-009, ASM-007).
task automatic do_reset_one(input bit core, input int ncyc);
  #(t_bus_per / 3);
  if (core) rst_n_core = 1'b0;
  else begin rst_n_bus = 1'b0; tb_drive_idle(); end
  if (core) begin
    repeat (ncyc) @(posedge clk_core);
    @(posedge clk_core); rst_n_core <= 1'b1;
  end else begin
    repeat (ncyc) @(posedge clk_bus);
    @(posedge clk_bus); rst_n_bus <= 1'b1;
  end
  repeat (8) @(posedge clk_core);
  repeat (8) @(posedge clk_bus);
endtask
