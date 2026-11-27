// -------------------------------------------------------------------------------------------------
// Project      : AES-GCM Accelerator - acceptance simulation testbench
// File         : tb_dma_model.svh (included inside module tb_aesgcm_top)
// Description  : External DMA controller model of the project-defined four-phase handshake of spec
//                section 6.3.4 (written from the specification, not from RTL):
//                  phase 1  the IP raises o_dma_*_req
//                  phase 2  the model moves one burst (aesgcm_dmacfg.*_burst beats, or the remaining
//                           beats if fewer) through the AXI4 window or aesgcm_pio_din/_dout and then
//                           raises i_dma_*_ack after the last beat completed (after BRESP for AXI)
//                  phase 3  the IP lowers the request
//                  phase 4  the model lowers the acknowledge after a random delay
//                The model is programmed with the byte lengths by software (spec 6.3.4), i.e. it knows
//                the number of input beats and output beats of the message. Acknowledge delays are
//                random in 0..dma_ack_dly_max bus clocks (+DMA_ACK_DLY=<n>, "slow" and "fast" ack of
//                TEST-019). Every wait is bounded; a stop flag ends both channels.
// -------------------------------------------------------------------------------------------------

// Signals and settings are declared in tb_aesgcm_decl.svh.

task automatic dma_idle();
  dma_in_ack  <= 1'b0;
  dma_out_ack <= 1'b0;
endtask

function automatic int burst_beats(input int code);
  return 1 << code;      // aesgcm_dmacfg burst code 0..4 = 1, 2, 4, 8, 16 beats (workbook)
endfunction

// Input channel: moves tx_b beats [0, total_beats) of width beat_bytes.
task automatic dma_in_channel(input int via, input int bcode, input int total_beats,
                              input int beat_bytes);
  int sent;
  int n;
  int w;
  bit ok;
  logic [31:0] word;
  sent = 0;
  sh_in_left = total_beats;
  while ((sent < total_beats) && (dma_stop == 0)) begin
    w = 0;
    while ((o_dma_in_req !== 1'b1) && (w < dma_wait_max) && (dma_stop == 0)) begin
      @(posedge clk_bus); w++;
    end
    if ((w >= dma_wait_max) || (dma_stop != 0)) begin
      if (dma_stop == 0) begin
        dma_err++;
        $display("TB-ERROR @%0t: DMA input request never came (%0d of %0d beats moved)",
                 $time, sent, total_beats);
      end
      break;
    end
    n = burst_beats(bcode);
    if (n > total_beats - sent) n = total_beats - sent;
    if (via == DMA_VIA_AXI) begin
      axi_push(sent * beat_bytes, n, n, 1, ok);
      if (!ok) dma_err++;
    end else begin
      for (int i = 0; i < n; i++) begin
        for (int j = 0; j < 4; j++) word[8 * j +: 8] = tx_b[(sent + i) * 4 + j];
        apb_wr(A_PIO_DIN, word);
        tb_in_beats_sent++;
      end
    end
    sent += n;
    sh_in_left = total_beats - sent;
    dma_bursts_in++;
    repeat (int'(rnd_range(0, dma_ack_dly_max))) @(posedge clk_bus);
    dma_in_ack <= 1'b1;
    @(posedge clk_bus);
    w = 0;
    while ((o_dma_in_req !== 1'b0) && (w < 64)) begin @(posedge clk_bus); w++; end
    if (w >= 64) begin
      dma_err++;
      $display("TB-ERROR @%0t: DMA input request not released after acknowledge", $time);
    end
    repeat (int'(rnd_range(0, dma_ack_dly_max))) @(posedge clk_bus);
    dma_in_ack <= 1'b0;
    @(posedge clk_bus);
  end
endtask

// Output channel: moves total_beats beats of width beat_bytes into rx_b.
task automatic dma_out_channel(input int via, input int bcode, input int total_beats,
                               input int beat_bytes);
  int got;
  int n;
  int w;
  bit ok;
  logic [31:0] word;
  got = 0;
  sh_out_left = total_beats;
  while ((got < total_beats) && (dma_stop == 0)) begin
    w = 0;
    while ((o_dma_out_req !== 1'b1) && (w < dma_wait_max) && (dma_stop == 0)) begin
      @(posedge clk_bus); w++;
    end
    if ((w >= dma_wait_max) || (dma_stop != 0)) begin
      if (dma_stop == 0) begin
        dma_err++;
        $display("TB-ERROR @%0t: DMA output request never came (%0d of %0d beats moved)",
                 $time, got, total_beats);
      end
      break;
    end
    n = burst_beats(bcode);
    if (n > total_beats - got) n = total_beats - got;
    if (via == DMA_VIA_AXI) begin
      axi_pull(got, n, n, 1, ok);
      if (!ok) dma_err++;
    end else begin
      for (int i = 0; i < n; i++) begin
        apb_rd(A_PIO_DOUT, word);
        for (int j = 0; j < 4; j++) rx_b[(got + i) * 4 + j] = word[8 * j +: 8];
        tb_out_beats_got++;
      end
    end
    got += n;
    sh_out_left = total_beats - got;
    dma_bursts_out++;
    repeat (int'(rnd_range(0, dma_ack_dly_max))) @(posedge clk_bus);
    dma_out_ack <= 1'b1;
    @(posedge clk_bus);
    w = 0;
    while ((o_dma_out_req !== 1'b0) && (w < 64)) begin @(posedge clk_bus); w++; end
    if (w >= 64) begin
      dma_err++;
      $display("TB-ERROR @%0t: DMA output request not released after acknowledge", $time);
    end
    repeat (int'(rnd_range(0, dma_ack_dly_max))) @(posedge clk_bus);
    dma_out_ack <= 1'b0;
    @(posedge clk_bus);
  end
endtask
