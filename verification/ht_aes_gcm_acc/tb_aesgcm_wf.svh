// -------------------------------------------------------------------------------------------------
// Project      : AES-GCM Accelerator - acceptance simulation testbench
// File         : tb_aesgcm_wf.svh (included inside module tb_aesgcm_top)
// Description  : Directed scenarios of the waveform plan of spec section 10.3 (WF-001 .. WF-023, rule
//                R-033). +TEST=WF-nnn runs one scenario and dumps only its window of the view scope
//                u_wf to waveforms_sim/<figure stem>.vcd (stem = figure file name without extension).
//                The figures are timing sketches (spec 10.3), so each scenario reproduces the operation
//                of its figure with the stimulus of the specification and adds port-level checks; the
//                cycle-level comparison is recorded by the integrator in waveforms_sim/
//                waveform_compare.md. In a +TEST=ALL run the scenarios execute without dumps.
//   Header per scenario: ID | figure | operation | config | checks (ID: expected).
// -------------------------------------------------------------------------------------------------

task automatic wf_on(input string stem);
  wf_stem = stem;
  if (wf_dump) begin
    $dumpfile({"waveforms_sim/", stem, ".vcd"});
    $dumpvars(1, u_wf);
    $dumpon;
    $display("TB-INFO: dumping %0s window to waveforms_sim/%0s.vcd", tc_id, stem);
  end
endtask

task automatic wf_off();
  if (wf_dump) begin
    repeat (4) @(posedge clk_bus);
    $dumpoff;
    $dumpflush;
  end
endtask

task automatic wf_begin(input string id);
  tc_begin(id, 1);
  set_pin(1'b0);
  sw_enable((10'h1 << EV_DONE) | EV_ERRS);
endtask

// WF-001 | WF-001_start_bundle | OP-002 start and CDC-001 bundle | any GCM | WF001-C1 start accepted
// within 2 X_c; WF001-C2 message correct
task automatic wf001();
  bit ok, ev;
  logic [31:0] v;
  int t0, lat, path;
  wf_begin("WF-001");
  tc_skip_if(C_GCM_EN == 0, "GCM not built");
  if (tc_skip != "") begin tc_end(); return; end
  load_vectors("WF-001"); load_msg(0);
  path = dflt_path();
  sw_program(0, 0, path_dsrc(path), -1, 1'b1, 1'b1, 0);
  clear_events();
  wf_on("WF-001_start_bundle");
  t0 = cyc_bus;
  sw_start();
  apb_poll(A_CTRL, CTRL_START, 32'h0, 100, v, ok);
  lat = cyc_bus - t0;
  repeat (20) @(posedge clk_bus);
  wf_off();
  tc_check("WF001-C1", ok && (lat <= 2 * xc_bus() + 8 * (apb_gap_max + 4)),
           $sformatf("start bit cleared after %0d bus clocks", lat));
  build_tx(0, m_aadlen, 0, m_dlen, path_beat(path));
  move_data(path, ceil_div(m_dlen, path_beat(path)), 0, 0, ok);
  wait_event(10'h1 << EV_DONE | EV_ERRS, 4000, ev);
  read_results(); sh_msg_active = 1'b0;
  tc_check("WF001-C2", ok && ev && (cmp_out(0, 0, m_dlen, path_beat(path), 1'b1) == 0) &&
           tag_full_ok(), "message correct");
  tc_end();
endtask

// Generic scenario: whole message of record 0 inside the window.
task automatic wf_whole_msg(input string id, input string stem, input int path, input int gpass,
                            input string cid);
  load_vectors(id); load_msg(0);
  wf_on(stem);
  run_msg(path, gpass, 0, 1'b1, 0, 0);
  wf_off();
  tc_check(cid, run_ok && (r_out_bad == 0) && ((gpass == 1) || (m_mode != M_GCM) || tag_full_ok()),
           "operation of the figure completes with the model result");
endtask

// WF-002 | WF-002_gcm_encrypt | OP-002, 1 AAD block, 2 payload blocks | any GCM | WF002-C1 output, tag
task automatic wf002();
  wf_begin("WF-002");
  tc_skip_if(C_GCM_EN == 0, "GCM not built");
  if (tc_skip != "") begin tc_end(); return; end
  wf_whole_msg("WF-002", "WF-002_gcm_encrypt", dflt_path(), 0, "WF002-C1");
  tc_end();
endtask

// WF-003 | WF-003_pass1_fail | OP-004 wrong tag | policy A | WF003-C1 TAG_FAIL, ver_ok 0, no output;
// WF003-C2 o_int high with TAG_FAIL enabled
task automatic wf003();
  bit b;
  wf_begin("WF-003");
  tc_skip_if(!C_HAS_PA, "policy A not built");
  if (tc_skip != "") begin tc_end(); return; end
  load_vectors("WF-003"); load_msg(0);
  apb_wr(A_IRQ_EN, 32'h1 << EV_TAGF);
  wf_on("WF-003_pass1_fail");
  run_msg(dflt_path(), 1, 0, 1'b1, 0, 0);
  int_after(3, 1'b1, b);
  wf_off();
  tc_check("WF003-C1", raw(EV_TAGF) && !r_sts[STS_VER_OK] && r_fifo[FIFO_OUT_EMPTY],
           "TAG_FAIL, ver_ok = 0, no output");
  tc_check("WF003-C2", b, "o_int_aesgcm high for the enabled TAG_FAIL");
  tc_end();
endtask

// WF-004 | WF-004_pass2 | OP-005 after ver_ok | policy A | WF004-C1 plaintext, tag_ok
task automatic wf004();
  wf_begin("WF-004");
  tc_skip_if(!C_HAS_PA, "policy A not built");
  if (tc_skip != "") begin tc_end(); return; end
  load_vectors("WF-004"); load_msg(0);
  run_msg(dflt_path(), 1, 0, 1'b1, 0, 0);
  wf_on("WF-004_pass2");
  run_msg(dflt_path(), 2, 0, 1'b0, 0, 0);
  wf_off();
  tc_check("WF004-C1", run_ok && (r_out_bad == 0) && r_sts[STS_TAG_OK], "pass 2 plaintext and tag_ok");
  tc_end();
endtask

// WF-005 | WF-005_secure_only | OP-003 with pin = 1 | policy C | WF005-C1 CFG_ERR, no output
task automatic wf005();
  bit seen;
  wf_begin("WF-005");
  tc_skip_if(!C_HAS_PC, "policy C not built");
  if (tc_skip != "") begin tc_end(); return; end
  load_vectors("WF-005"); load_msg(0);
  set_pin(1'b1);
  sh_pc_blocked = 1'b1;
  wf_on("WF-005_secure_only");
  run_expect_error(dflt_path(), 0, 10'h1 << EV_CERR, seen);
  wf_off();
  sh_pc_blocked = 1'b0;
  set_pin(1'b0);
  tc_check("WF005-C1", seen && r_fifo[FIFO_OUT_EMPTY], "CFG_ERR and no plaintext");
  tc_end();
endtask

// WF-006 | WF-006_axi_write | OP-013 INCR 4 beats with backpressure | AXI | WF006-C1 WREADY stalled
// at least once inside the window; WF006-C2 every BRESP OKAY and the message correct
int wf_wstall = 0;
always @(posedge clk_bus) if (axi_wvalid && (o_axi_wready === 1'b0)) wf_wstall <= wf_wstall + 1;
task automatic wf006();
  bit okw, okr, ev;
  logic [1:0] br;
  logic [C_IW-1:0] bi;
  int nb, s0, s1, done_b;
  wf_begin("WF-006");
  tc_skip_if(C_AXI == 0, "no AXI4 window"); tc_skip_if(C_GCM_EN == 0, "GCM not built");
  if (tc_skip != "") begin tc_end(); return; end
  load_vectors("WF-006"); load_msg(0);
  start_only(PATH_AXI_INCR, 0, 1'b1, 0);
  build_tx(0, 0, 0, m_dlen, C_BEAT_AXI);
  nb = tx_n / C_BEAT_AXI;
  okw = 1'b1; s0 = 0; s1 = 0;
  fork
    begin
      done_b = 0;
      while ((done_b < nb) && okw) begin
        axi_write_burst(4'h1, AXI_WR_WIN, 3, AXI_SIZE_FULL, BURST_INCR, done_b * C_BEAT_AXI, 1'b0,
                        br, bi, okw);
        if (br != 2'b00) okw = 1'b0;
        done_b += 4;
      end
    end
    begin
      repeat (3000) @(posedge clk_bus);    // FIFOs fill, WREADY drops
      s0 = wf_wstall;
      wf_on("WF-006_axi_write");
      fork
        axi_pull(0, nb, 4, 1, okr);
        begin repeat (600) @(posedge clk_bus); wf_off(); s1 = wf_wstall; end
      join
    end
  join
  wait_event(10'h1 << EV_DONE | EV_ERRS, 4000, ev);
  read_results(); sh_msg_active = 1'b0;
  tc_check("WF006-C1", s1 > s0, $sformatf("WREADY back-pressure seen in the window (%0d cycles)", s1 - s0));
  tc_check("WF006-C2", okw && okr && ev && (cmp_out(0, 0, m_dlen, C_BEAT_AXI, 1'b1) == 0),
           "all write responses OKAY; output = model");
  tc_end();
endtask

// WF-007 | WF-007_axi_wrap | OP-013 WRAP write | AXI | WF007-C1 SLVERR; WF007-C2 FIFO unchanged
task automatic wf007();
  bit ok;
  logic [1:0] br;
  logic [C_IW-1:0] bi;
  wf_begin("WF-007");
  tc_skip_if(C_AXI == 0, "no AXI4 window"); tc_skip_if(C_GCM_EN == 0, "GCM not built");
  if (tc_skip != "") begin tc_end(); return; end
  load_vectors("WF-007"); load_msg(0);
  for (int i = 0; i < 64; i++) tx_b[4096 + i] = 8'(rnd32());
  start_only(PATH_AXI_INCR, 0, 1'b1, 0);
  wf_on("WF-007_axi_wrap");
  axi_write_burst(4'h2, AXI_WR_WIN, 3, AXI_SIZE_FULL, BURST_WRAP, 4096, 1'b0, br, bi, ok);
  wf_off();
  tc_check("WF007-C1", ok && (br == 2'b10) && (bi == 4'h2), "WRAP write answered with SLVERR");
  build_tx(0, 0, 0, m_dlen, C_BEAT_AXI);
  move_data(PATH_AXI_INCR, ceil_div(m_dlen, C_BEAT_AXI), 0, 0, ok);
  wait_event(10'h1 << EV_DONE | EV_ERRS, 4000, ok);
  read_results(); sh_msg_active = 1'b0;
  tc_check("WF007-C2", (cmp_out(0, 0, m_dlen, C_BEAT_AXI, 1'b1) == 0) && tag_full_ok(),
           "the WRAP beats were not pushed: message correct");
  tc_end();
endtask

// WF-008 | WF-008_axi_read | OP-013 read burst issued before data exists | AXI | WF008-C1 OKAY beats,
// data = model
task automatic wf008();
  bit okr, okw, ev, zd;
  logic [1:0] rr;
  int nb;
  wf_begin("WF-008");
  tc_skip_if(C_AXI == 0, "no AXI4 window"); tc_skip_if(C_GCM_EN == 0, "GCM not built");
  if (tc_skip != "") begin tc_end(); return; end
  load_vectors("WF-008"); load_msg(0);
  start_only(PATH_AXI_INCR, 0, 1'b1, 0);
  build_tx(0, 0, 0, m_dlen, C_BEAT_AXI);
  nb = tx_n / C_BEAT_AXI;
  wf_on("WF-008_axi_read");
  fork
    axi_read_burst(4'h4, AXI_RD_WIN, nb - 1, AXI_SIZE_FULL, BURST_INCR, 0, 1'b1, 20000, rr, zd, okr);
    begin repeat (20) @(posedge clk_bus); axi_push(0, nb, nb, 1, okw); end
  join
  wf_off();
  wait_event(10'h1 << EV_DONE | EV_ERRS, 4000, ev);
  read_results(); sh_msg_active = 1'b0;
  tc_check("WF008-C1", okr && (rr == 2'b00) && (cmp_out(0, 0, m_dlen, C_BEAT_AXI, 1'b1) == 0),
           "RVALID waited for data; OKAY beats; data = model");
  tc_end();
endtask

// WF-009 | WF-009_dma_hs | OP-014 four-phase both channels | any (AXI or PIO) | WF009-C1 output, tag
task automatic wf009();
  int path;
  wf_begin("WF-009");
  tc_skip_if(C_GCM_EN == 0, "GCM not built");
  if (tc_skip != "") begin tc_end(); return; end
  load_vectors("WF-009"); load_msg(0);
  path = (C_AXI == 1) ? PATH_DMA_AXI : PATH_DMA_PIO;
  wf_on("WF-009_dma_hs");
  run_msg(path, 0, 0, 1'b1, 2, 2);
  wf_off();
  tc_check("WF009-C1", run_ok && (r_out_bad == 0) && tag_full_ok(), "DMA-moved message correct");
  tc_end();
endtask

// WF-010 | WF-010_pio_overrun | OP-012 write while in_full | any | WF010-C1 PROTO_ERR
task automatic wf010();
  logic [31:0] fs, w;
  bit full, ev;
  int k;
  wf_begin("WF-010");
  tc_skip_if(C_GCM_EN == 0, "GCM not built");
  if (tc_skip != "") begin tc_end(); return; end
  load_vectors("WF-010"); load_msg(0);
  start_only(PATH_PIO, 0, 1'b1, 0);
  build_tx(0, 0, 0, m_dlen, 4);
  full = 1'b0; k = 0;
  while ((k < tx_n / 4) && !full) begin
    apb_rd(A_FIFOSTS, fs);
    if (fs[FIFO_IN_FULL]) full = 1'b1;
    else begin
      for (int j = 0; j < 4; j++) w[8 * j +: 8] = tx_b[k * 4 + j];
      apb_wr(A_PIO_DIN, w); k++;
    end
  end
  clear_events();
  wf_on("WF-010_pio_overrun");
  apb_wr(A_PIO_DIN, 32'hDEAD_BEEF);
  wait_event(10'h1 << EV_PERR, 40, ev);
  wf_off();
  tc_check("WF010-C1", full && ev, "write with in_full = 1 dropped with PROTO_ERR");
  cmd(CTRL_ABORT);
  repeat (cmd_bound_bus()) @(posedge clk_bus);
  sh_msg_active = 1'b0;
  tc_end();
endtask

// WF-011 | WF-011_key_side | OP-011 success and time-out | side-load | WF011-C1 one ack, correct;
// WF011-C2 KEY_ERR
task automatic wf011();
  bit ev, ka;
  wf_begin("WF-011");
  tc_skip_if(C_KEY_SIDE == 0, "side-load not built");
  if (tc_skip != "") begin tc_end(); return; end
  load_vectors("WF-011"); load_msg(0);
  apb_wr(A_KEYWAIT, 32'd20);
  wf_on("WF-011_key_side");
  run_msg(dflt_path(), 0, 1, 1'b1, 0, 0);
  tc_check("WF011-C1", run_ok && (r_out_bad == 0) && tag_full_ok(), "side-loaded key captured");
  load_msg(1);
  sw_program(0, 1, path_dsrc(dflt_path()), -1, 1'b0, 1'b1, 0);
  clear_events(); sh_side_window = 1'b1; sw_start();
  wait_event(10'h1 << EV_KERR, 200, ev);
  wf_off();
  read_results(); cmd(32'h0); sh_msg_active = 1'b0; sh_side_window = 1'b0;
  tc_check("WF011-C2", ev && (r_err[3:0] == ERRC_KEY), "no valid within keywait: KEY_ERR");
  apb_wr(A_KEYWAIT, 32'h100);
  tc_end();
endtask

// WF-012 | WF-012_suspend_resume | OP-007, OP-008 | ctx slots | WF012-C1 counts; WF012-C2 result
task automatic wf012();
  bit ok, ev, fo;
  logic [31:0] ca, cd;
  int path, beat;
  wf_begin("WF-012");
  tc_skip_if(!C_HAS_SUSP, "suspend/resume not built");
  if (tc_skip != "") begin tc_end(); return; end
  load_vectors("WF-012"); load_msg(0);
  path = (C_AXI == 1) ? PATH_AXI_INCR : PATH_PIO;
  beat = path_beat(path);
  sw_enable((10'h1 << EV_DONE) | (10'h1 << EV_CSWD) | EV_ERRS);
  start_only(path, 0, 1'b1, 0);
  build_tx(0, 16, 0, 48, beat);
  move_part(path, 0, 48 / beat, ok);
  fo = ok && (cmp_out(0, 0, 48, beat, 1'b0) == 0);
  repeat (50) @(posedge clk_bus);
  wf_on("WF-012_suspend_resume");
  do_suspend(ev, ca, cd);
  sh_msg_active = 1'b0;
  repeat (20) @(posedge clk_bus);
  do_resume(0, path, 0);
  repeat (60) @(posedge clk_bus);
  wf_off();
  tc_check("WF012-C1", ev && (ca == 32'd16) && (cd == 32'd48), "suspend counts 16 / 48");
  build_tx(16, 0, 48, 48, beat);
  move_part(path, 48 / beat, 48 / beat, ok);
  wait_event(10'h1 << EV_DONE | EV_ERRS, 4000, ev);
  read_results(); sh_msg_active = 1'b0;
  tc_check("WF012-C2", fo && ok && ev && (cmp_out(48, 48, 48, beat, 1'b0) == 0) && tag_full_ok(),
           "resumed message = uninterrupted model");
  tc_end();
endtask

// Abort or zeroize in the payload phase (WF-013, WF-014, WF-023).
task automatic wf_abort_like(input string id, input string stem, input logic [31:0] cbit,
                             input string cid);
  bit ok, b;
  logic [31:0] v, fs;
  int path, beat, t0, lat;
  load_vectors(id); load_msg(0);
  path = (C_AXI == 1) ? PATH_AXI_INCR : PATH_PIO;
  beat = path_beat(path);
  start_only(path, 0, 1'b1, 0);
  build_tx(0, 0, 0, (C_FIFO_BLOCKS * 16 / 2 > 512) ? 512 : C_FIFO_BLOCKS * 16 / 2, beat);
  move_part(path, 0, 0, ok);
  repeat (100) @(posedge clk_bus);
  wf_on(stem);
  t0 = cyc_bus;
  cmd(cbit);
  if (cbit == CTRL_ZEROIZE) apb_poll(A_STS, 32'h8, 32'h8, 200, v, b);
  else apb_poll(A_CTRL, cbit, 32'h0, 200, v, b);
  apb_poll(A_STS, 32'h1, 32'h0, 50, v, ok);
  lat = cyc_bus - t0;
  repeat (20) @(posedge clk_bus);
  wf_off();
  sh_msg_active = 1'b0;
  apb_rd(A_FIFOSTS, fs);
  apb_rd(A_STS, v);
  tc_check(cid, b && ok && (lat <= cmd_bound_bus()) && fs[FIFO_OUT_EMPTY] &&
           ((cbit != CTRL_ZEROIZE) || !v[STS_KEY_LD]),
           $sformatf("command completed in %0d bus clocks (bound %0d), FIFOs empty", lat,
                     cmd_bound_bus()));
  load_msg(0);
  run_msg(path, 0, 0, 1'b1, 0, 0);
  tc_check({cid, "b"}, run_ok && (r_out_bad == 0) && tag_full_ok(), "next message correct");
endtask

// WF-013 | WF-013_abort | OP-009 | any GCM | WF013-C1 bound, flush; WF013-C1b next message
task automatic wf013();
  wf_begin("WF-013");
  tc_skip_if(C_GCM_EN == 0, "GCM not built");
  if (tc_skip != "") begin tc_end(); return; end
  wf_abort_like("WF-013", "WF-013_abort", CTRL_ABORT, "WF013-C1");
  tc_end();
endtask

// WF-014 | WF-014_zeroize | OP-010 | any GCM | WF014-C1 zeroized, key_ld 0; WF014-C1b next message
task automatic wf014();
  wf_begin("WF-014");
  tc_skip_if(C_GCM_EN == 0, "GCM not built");
  if (tc_skip != "") begin tc_end(); return; end
  wf_abort_like("WF-014", "WF-014_zeroize", CTRL_ZEROIZE, "WF014-C1");
  tc_end();
endtask

// WF-015 | WF-015_interrupt | OP-015 | any | WF015-C1 line high with DONE; WF015-C2 low after w1c
task automatic wf015();
  bit b1, b2;
  wf_begin("WF-015");
  load_vectors("WF-015"); load_msg(0);
  apb_wr(A_IRQ_EN, 32'h1 << EV_DONE);
  wf_on("WF-015_interrupt");
  run_msg(dflt_path(), 0, 0, 1'b1, 0, 0);
  int_after(3, 1'b1, b1);
  irq_clear_armed();
  int_after(2, 1'b0, b2);
  wf_off();
  tc_check("WF015-C1", b1 && raw(EV_DONE), "DONE raises the enabled line");
  tc_check("WF015-C2", b2, "line low within 2 bus clocks after the clear");
  tc_end();
endtask

// WF-016 | WF-016_sync_ratio | CDC-001 synchronous, Tbus:Tcore = 3:2 | PARA_CLK_ASYNC = 0 and
// +CLK_RATIO=3_2 | WF016-C1 start accepted and message correct
task automatic wf016();
  wf_begin("WF-016");
  tc_skip_if(C_ASYNC != 0, "needs PARA_CLK_ASYNC = 0 (+define+TB_CLK_ASYNC=0) and +CLK_RATIO=3_2");
  tc_skip_if(clk_ratio_s != "3_2", "needs +CLK_RATIO=3_2");
  tc_skip_if(C_GCM_EN == 0, "GCM not built");
  if (tc_skip != "") begin tc_end(); return; end
  wf_whole_msg("WF-016", "WF-016_sync_ratio", dflt_path(), 0, "WF016-C1");
  tc_end();
endtask

// WF-017 | WF-017_ghash_partial | aggregated GHASH 4 + 3 blocks | ARCH 2, lanes 4 | WF017-C1 result
task automatic wf017();
  wf_begin("WF-017");
  tc_skip_if((C_ARCH != 2) || (C_LANES != 4), "needs PARA_GHASH_ARCH = 2 and 4 lanes");
  if (tc_skip != "") begin tc_end(); return; end
  wf_whole_msg("WF-017", "WF-017_ghash_partial", dflt_path(), 0, "WF017-C1");
  tc_end();
endtask

// WF-018 | WF-018_reset | reset during a message | any GCM | WF018-C1 outputs 0 after the reset;
// WF018-C2 message after reset correct
task automatic wf018();
  bit ok, b;
  int path, beat;
  wf_begin("WF-018");
  tc_skip_if(C_GCM_EN == 0, "GCM not built");
  if (tc_skip != "") begin tc_end(); return; end
  load_vectors("WF-018"); load_msg(0);
  path = (C_AXI == 1) ? PATH_AXI_INCR : PATH_PIO;
  beat = path_beat(path);
  apb_wr(A_IRQ_EN, 32'h1);
  sh_in_left = 1000; sh_burst_bound = 1000000;   // request raised without a DMA model
  apb_wr(A_DMACFG, 32'h1);
  start_only(path, 0, 1'b1, 0);
  build_tx(0, 0, 0, 128, beat);
  move_part(path, 0, 0, ok);
  apb_wr(A_IRQ_INJ, 32'h1); apb_wr(A_IRQ_INJ, 32'h0);
  wf_on("WF-018_reset");
  repeat (10) @(posedge clk_bus);
  do_reset(4);
  b = (o_int_aesgcm === 1'b0) && (o_dma_in_req === 1'b0);
  repeat (10) @(posedge clk_bus);
  wf_off();
  sh_msg_active = 1'b0; sh_irq_en = 10'h0; sh_dmacfg = 8'h0;
  sh_in_left = 0; sh_burst_bound = 4000;
  tc_check("WF018-C1", b, "interrupt and DMA request 0 after the reset");
  sw_enable((10'h1 << EV_DONE) | EV_ERRS);
  run_msg(path, 0, 0, 1'b1, 0, 0);
  tc_check("WF018-C2", run_ok && (r_out_bad == 0) && tag_full_ok(), "message after reset correct");
  tc_end();
endtask

// WF-019 | WF-019_legacy_ctr | OP-001 CTR via PIO, one block | any | WF019-C1 output, DONE
task automatic wf019();
  wf_begin("WF-019");
  wf_whole_msg("WF-019", "WF-019_legacy_ctr", PATH_PIO, 0, "WF019-C1");
  tc_end();
endtask

// WF-020 | WF-020_gmac | OP-006 payload length 0 | any GCM | WF020-C1 tag, no output
task automatic wf020();
  wf_begin("WF-020");
  tc_skip_if(C_GCM_EN == 0, "GCM not built");
  if (tc_skip != "") begin tc_end(); return; end
  wf_whole_msg("WF-020", "WF-020_gmac", dflt_path(), 0, "WF020-C1");
  tc_check("WF020-C2", r_fifo[FIFO_OUT_EMPTY] === 1'b1, "GMAC writes no output");
  tc_end();
endtask

// WF-021 | WF-021_ctx_export | OP-016 export reads | PARA_GCM_CTX_MODE = 1 | WF021-C1 words 17..19
task automatic wf021();
  bit ok, ev;
  logic [31:0] ca, cd, w [0:23];
  int path, beat;
  wf_begin("WF-021");
  tc_skip_if(!C_HAS_EXP, "context export not built (PARA_GCM_CTX_MODE = 0)");
  if (tc_skip != "") begin tc_end(); return; end
  load_vectors("WF-021"); load_msg(0);
  path = (C_AXI == 1) ? PATH_AXI_INCR : PATH_PIO;
  beat = path_beat(path);
  sw_enable((10'h1 << EV_DONE) | (10'h1 << EV_CSWD) | EV_ERRS);
  start_only(path, 0, 1'b1, 0);
  build_tx(0, 16, 0, 48, beat);
  move_part(path, 0, 48 / beat, ok);
  repeat (50) @(posedge clk_bus);
  do_suspend(ev, ca, cd);
  sh_msg_active = 1'b0;
  wf_on("WF-021_ctx_export");
  for (int k = 0; k < 24; k++) apb_rd(A_CTXX + 4 * k, w[k]);
  wf_off();
  tc_check("WF021-C1", ev && (w[17] == 32'd48) && (w[18] == 32'd16) && (w[19] == 32'd96),
           "exported remainder and totals (DEC-023 layout)");
  cmd(CTRL_ZEROIZE);
  tc_end();
endtask

// WF-022 | WF-022_ghash_pipe | DEC-017 batches 4, 4, 2 | lanes 4 | WF022-C1 result (PIPE as built)
task automatic wf022();
  wf_begin("WF-022");
  tc_skip_if(C_LANES != 4, "needs 4 lanes");
  if (tc_skip != "") begin tc_end(); return; end
  wf_whole_msg("WF-022", "WF-022_ghash_pipe", dflt_path(), 0, "WF022-C1");
  tc_end();
endtask

// WF-023 | WF-023_cmd_ack | DEC-022 abort through the command crossing | any GCM | WF023-C1 abort bit
// and busy 0 after the acknowledging report; WF023-C1b next message
task automatic wf023();
  wf_begin("WF-023");
  tc_skip_if(C_GCM_EN == 0, "GCM not built");
  if (tc_skip != "") begin tc_end(); return; end
  wf_abort_like("WF-023", "WF-023_cmd_ack", CTRL_ABORT, "WF023-C1");
  tc_end();
endtask
