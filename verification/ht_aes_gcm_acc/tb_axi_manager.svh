// -------------------------------------------------------------------------------------------------
// Project      : AES-GCM Accelerator - acceptance simulation testbench
// File         : tb_axi_manager.svh (included inside module tb_aesgcm_top)
// Description  : AXI4 manager model for the data window, written from Arm IHI 0022H.c A3.1 to A3.4
//                and A5.2 and from spec 6.2 / 6.3.2 (one outstanding burst per direction).
//                - Write: AW handshake, then AWLEN+1 W beats, then the B handshake. VALID never
//                  waits for READY and is held until the handshake (A3.2.2); payload held stable.
//                - Random WVALID gaps (+AXI_WGAP=<n>), random BREADY and RREADY back-pressure
//                  (+AXI_BREADY_DLY=<n>, +AXI_RREADY_DLY=<n>), random write strobes including
//                  all-zero strobes (spec 6.2: strobes ignored for the data) with +AXI_RAND_STRB.
//                - Bursts FIXED, INCR and WRAP with the size given by the caller; addresses stay
//                  inside one 4 KB page (A3.4.1); WRAP lengths are 2, 4, 8 or 16 and aligned.
//                - Deliberate WLAST/AWLEN mismatch (early WLAST) for ERR-008, with the explicit
//                  assertion mask tb_mask_axi_wlast raised for exactly that burst.
//                - Beat byte lane 0 holds the first stream byte (spec 9.1, 9.2).
//                - Bounded waits: every handshake gives up after axi_timeout cycles.
// -------------------------------------------------------------------------------------------------

// Signals and settings are declared in tb_aesgcm_decl.svh.

task automatic axi_idle();
  axi_awvalid <= 1'b0; axi_awid <= '0; axi_awaddr <= '0; axi_awlen <= '0; axi_awsize <= '0;
  axi_awburst <= '0;
  axi_wvalid <= 1'b0; axi_wdata <= '0; axi_wstrb <= '0; axi_wlast <= 1'b0;
  axi_bready <= 1'b0;
  axi_arvalid <= 1'b0; axi_arid <= '0; axi_araddr <= '0; axi_arlen <= '0; axi_arsize <= '0;
  axi_arburst <= '0;
  axi_rready <= 1'b0;
  tb_mask_axi_wlast <= 1'b0;
endtask

// Write burst. Beat b carries tx_b[src + b*C_BEAT_AXI +: C_BEAT_AXI] (lane 0 = first byte).
// early_wlast = 1 drives WLAST on beat len-1 and ends the burst there (deliberate mismatch).
task automatic axi_write_burst(input logic [C_IW-1:0] id, input logic [C_AW-1:0] addr,
                               input int len, input logic [2:0] size, input logic [1:0] burst,
                               input int src, input bit early_wlast,
                               output logic [1:0] bresp, output logic [C_IW-1:0] bidv,
                               output bit ok);
  int n;
  int nbeats;
  logic [C_DW-1:0] beat;
  while (axi_wr_lock != 0) @(posedge clk_bus);
  axi_wr_lock = 1;
  ok = 1'b1;
  bresp = 2'b11;
  bidv = '0;
  nbeats = early_wlast ? len : (len + 1);
  if (early_wlast) tb_mask_axi_wlast <= 1'b1;
  // Address phase
  axi_awid <= id; axi_awaddr <= addr; axi_awlen <= len[7:0]; axi_awsize <= size;
  axi_awburst <= burst; axi_awvalid <= 1'b1;
  @(posedge clk_bus);
  n = 0;
  while ((o_axi_awready !== 1'b1) && (n < axi_timeout)) begin @(posedge clk_bus); n++; end
  axi_awvalid <= 1'b0;
  if (n >= axi_timeout) begin
    ok = 1'b0; axi_hang++;
    $display("TB-ERROR @%0t: AWREADY time-out", $time);
  end
  // Data phase
  for (int b = 0; (b < nbeats) && ok; b++) begin
    int gap;
    gap = (axi_wgap_max > 0) ? int'(rnd_range(0, axi_wgap_max)) : 0;
    if (gap > 0) begin
      axi_wvalid <= 1'b0;
      repeat (gap) @(posedge clk_bus);
    end
    for (int j = 0; j < C_BEAT_AXI; j++) beat[8 * j +: 8] = tx_b[src + b * C_BEAT_AXI + j];
    axi_wdata  <= beat;
    axi_wstrb  <= (axi_rand_strb != 0) ? C_BEAT_AXI'(rnd32()) : {C_BEAT_AXI{1'b1}};
    axi_wlast  <= (b == nbeats - 1);
    axi_wvalid <= 1'b1;
    @(posedge clk_bus);
    n = 0;
    while ((o_axi_wready !== 1'b1) && (n < axi_timeout)) begin @(posedge clk_bus); n++; end
    if (n >= axi_timeout) begin
      ok = 1'b0; axi_hang++;
      $display("TB-ERROR @%0t: WREADY time-out at beat %0d", $time, b);
    end
  end
  axi_wvalid <= 1'b0;
  axi_wlast  <= 1'b0;
  // Response phase with random BREADY delay
  if (ok) begin
    repeat (int'(rnd_range(0, axi_bready_dly_max))) @(posedge clk_bus);
    axi_bready <= 1'b1;
    @(posedge clk_bus);
    n = 0;
    while ((o_axi_bvalid !== 1'b1) && (n < axi_timeout)) begin @(posedge clk_bus); n++; end
    if (n >= axi_timeout) begin
      ok = 1'b0; axi_hang++;
      $display("TB-ERROR @%0t: BVALID time-out", $time);
    end else begin
      bresp = o_axi_bresp;
      bidv  = o_axi_bid;
    end
    axi_bready <= 1'b0;
  end
  tb_mask_axi_wlast <= 1'b0;
  axi_wr_lock = 0;
endtask

// Read burst. Beat b is stored in rx_b[dst + b*C_BEAT_AXI ...] when store = 1.
// Returns the OR of the responses and whether RLAST was on the final beat.
task automatic axi_read_burst(input logic [C_IW-1:0] id, input logic [C_AW-1:0] addr,
                              input int len, input logic [2:0] size, input logic [1:0] burst,
                              input int dst, input bit store, input int timeout,
                              output logic [1:0] resp_or, output bit zero_data, output bit ok);
  int n;
  logic [C_DW-1:0] beat;
  while (axi_rd_lock != 0) @(posedge clk_bus);
  axi_rd_lock = 1;
  ok = 1'b1;
  resp_or = 2'b00;
  zero_data = 1'b1;
  axi_arid <= id; axi_araddr <= addr; axi_arlen <= len[7:0]; axi_arsize <= size;
  axi_arburst <= burst; axi_arvalid <= 1'b1;
  @(posedge clk_bus);
  n = 0;
  while ((o_axi_arready !== 1'b1) && (n < axi_timeout)) begin @(posedge clk_bus); n++; end
  axi_arvalid <= 1'b0;
  if (n >= axi_timeout) begin
    ok = 1'b0; axi_hang++;
    $display("TB-ERROR @%0t: ARREADY time-out", $time);
  end
  for (int b = 0; (b <= len) && ok; b++) begin
    axi_rready <= 1'b0;
    repeat (int'(rnd_range(0, axi_rready_dly_max))) @(posedge clk_bus);
    axi_rready <= 1'b1;
    @(posedge clk_bus);
    n = 0;
    while ((o_axi_rvalid !== 1'b1) && (n < timeout)) begin @(posedge clk_bus); n++; end
    if (n >= timeout) begin
      ok = 1'b0; axi_hang++;
      $display("TB-ERROR @%0t: RVALID time-out at beat %0d of %0d", $time, b, len + 1);
    end else begin
      beat = o_axi_rdata;
      resp_or = resp_or | o_axi_rresp;
      if (beat != '0) zero_data = 1'b0;
      if (store)
        for (int j = 0; j < C_BEAT_AXI; j++) rx_b[dst + b * C_BEAT_AXI + j] = beat[8 * j +: 8];
    end
  end
  axi_rready <= 1'b0;
  axi_rd_lock = 0;
endtask

// Push nbeats of tx_b starting at byte src through the write window, in bursts of at most
// max_len+1 beats, cycling burst types when btype = 3 (FIXED/INCR mix). Returns 0 on a failure.
task automatic axi_push(input int src, input int nbeats, input int max_beats, input int btype,
                        output bit ok);
  int done_beats;
  int len;
  logic [1:0] bt, br;
  logic [C_IW-1:0] bi, id;
  bit bok;
  ok = 1'b1;
  done_beats = 0;
  while ((done_beats < nbeats) && ok) begin
    len = nbeats - done_beats;
    if (len > max_beats) len = max_beats;
    if (btype == 3) bt = rnd_range(0, 1) ? BURST_INCR : BURST_FIXED;
    else bt = (btype == 0) ? BURST_FIXED : BURST_INCR;
    if ((bt == BURST_FIXED) && (len > 16)) len = 16;
    id = C_IW'(rnd32());
    axi_write_burst(id, AXI_WR_WIN, len - 1, AXI_SIZE_FULL, bt, src + done_beats * C_BEAT_AXI,
                    1'b0, br, bi, bok);
    if (!bok || (br != 2'b00) || (bi != id)) begin
      ok = 1'b0;
      $display("TB-ERROR @%0t: legal write burst failed (ok %0d bresp %0b bid %0h/%0h)",
               $time, bok, br, bi, id);
    end
    done_beats += len;
    tb_in_beats_sent += len;
  end
endtask

// Pull nbeats from the read window into rx_b at beat offset dst_beat.
task automatic axi_pull(input int dst_beat, input int nbeats, input int max_beats, input int btype,
                        output bit ok);
  int done_beats;
  int len;
  logic [1:0] bt, rr;
  bit zd, bok;
  ok = 1'b1;
  done_beats = 0;
  while ((done_beats < nbeats) && ok) begin
    len = nbeats - done_beats;
    if (len > max_beats) len = max_beats;
    if (btype == 3) bt = rnd_range(0, 1) ? BURST_INCR : BURST_FIXED;
    else bt = (btype == 0) ? BURST_FIXED : BURST_INCR;
    if ((bt == BURST_FIXED) && (len > 16)) len = 16;
    axi_read_burst(C_IW'(rnd32()), AXI_RD_WIN, len - 1, AXI_SIZE_FULL, bt,
                   (dst_beat + done_beats) * C_BEAT_AXI, 1'b1, axi_timeout, rr, zd, bok);
    if (!bok || (rr != 2'b00)) begin
      ok = 1'b0;
      $display("TB-ERROR @%0t: legal read burst failed (ok %0d rresp %0b)", $time, bok, rr);
    end
    done_beats += len;
    tb_out_beats_got += len;
  end
endtask
