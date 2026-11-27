// -------------------------------------------------------------------------------------------------
// Project      : AES-GCM Accelerator - acceptance simulation testbench
// File         : tb_aesgcm_tests_ft.svh (included inside module tb_aesgcm_top)
// Description  : Focused diagnostic testcases FT-<nnn>, one per section 15.2 row that the integrated
//                cases do not isolate (the number is the TEST-nnn row). Header fields as for the
//                integrated cases; fewer checks are required (R-048 counts only TC-01..TC-15).
//                Replay: <sim> +TEST=FT-<nnn> +SEED=<n>.
// -------------------------------------------------------------------------------------------------

// FT-011  Context export/import through aesgcm_ctxx (REQ-FUNC-011, DEC-023, OP-016, TEST-011, TEST-035)
//   Config: PARA_GCM_CTX_MODE = 1 (export build). Sequence: M1 (aad 32, len 96) suspended after 48
//   payload bytes; read aesgcm_ctxx_0..23; write words 0..20 back; resume; finish; suspend again with
//   the pin at 1 and access aesgcm_ctxx_0.
//   Checks: FT011-C1 DEC-023 Ex.4 words 15..19 = 5, 0, 48, 32, 96 | FT011-C2 REQ-SEC-004 words 21..23
//   read 0 (no key or expected tag exported) | FT011-C3 REQ-FUNC-011 resumed output and tag = model |
//   FT011-C4 REQ-FUNC-011 export with the pin at 1: CFG_ERR | FT011-C5 import with the pin at 1: CFG_ERR
task automatic ft011();
  bit ok, ev, seen, first_ok;
  logic [31:0] ca, cd, w [0:23], v;
  int path, beat;
  tc_begin("FT-011", 3);
  tc_skip_if(!C_HAS_EXP, "context export not built (PARA_GCM_CTX_MODE = 0)");
  if (tc_skip != "") begin tc_end(); return; end
  load_vectors("TC-06");
  path = (C_AXI == 1) ? PATH_AXI_INCR : PATH_PIO;
  beat = path_beat(path);
  set_pin(1'b0);
  sw_enable((10'h1 << EV_DONE) | (10'h1 << EV_CSWD) | EV_ERRS);
  load_msg(0);
  start_only(path, 0, 1'b1, 0);
  build_tx(0, 32, 0, 48, beat);
  move_part(path, 0, 48 / beat, ok);
  first_ok = ok && (cmp_out(0, 0, 48, beat, 1'b0) == 0);
  repeat (100) @(posedge clk_bus);
  do_suspend(ev, ca, cd);
  sh_msg_active = 1'b0;
  for (int k = 0; k < 24; k++) apb_rd(A_CTXX + 4 * k, w[k]);
  tc_check("FT011-C1", ev && (w[15] == 32'd5) && (w[16] == 32'd0) && (w[17] == 32'd48) &&
           (w[18] == 32'd32) && (w[19] == 32'd96),
           $sformatf("exported words 15..19 = %0d %0d %0d %0d %0d", w[15], w[16], w[17], w[18], w[19]));
  tc_check("FT011-C2", (w[21] == 0) && (w[22] == 0) && (w[23] == 0), "words 21..23 not exported");
  for (int k = 0; k < 21; k++) apb_wr(A_CTXX + 4 * k, w[k]);
  do_resume(0, path, 0);
  build_tx(32, 0, 48, 48, beat);
  move_part(path, 48 / beat, 48 / beat, ok);
  wait_event(10'h1 << EV_DONE | EV_ERRS, 4000, ev);
  read_results();
  sh_msg_active = 1'b0;
  tc_check("FT011-C3", first_ok && ok && ev && (cmp_out(48, 48, 48, beat, 1'b0) == 0) &&
           tag_full_ok(), "export, import and resume give the uninterrupted output and tag");
  // The secure-only pin is static: set it while no message is active, then suspend (export) and
  // resume (import) with the pin at 1 (REQ-FUNC-011).
  set_pin(1'b1);
  start_only(path, 0, 1'b0, 0);
  build_tx(0, 32, 0, 0, beat);
  move_part(path, 0, 0, ok);
  repeat (300) @(posedge clk_bus);
  clear_events();
  do_suspend(ev, ca, cd);
  sh_msg_active = 1'b0;
  read_results();
  seen = raw(EV_CERR);
  tc_check("FT011-C4", seen, "export (suspend) with i_gcm_secure_only = 1: CFG_ERR");
  clear_events();
  apb_wr(A_CTXX, 32'h1234_5678);
  do_resume(0, path, 0);
  wait_event(10'h1 << EV_CERR, 60, seen);
  tc_check("FT011-C5", seen, "import (resume) with i_gcm_secure_only = 1: CFG_ERR");
  set_pin(1'b0);
  cmd(CTRL_ZEROIZE);
  apb_poll(A_STS, 32'h8, 32'h8, 200, v, ok);
  tc_end();
endtask

// FT-012  Abort in every reachable sequencer state (REQ-FUNC-013, PERF-004, TEST-012, TEST-034)
//   States reached from the ports: KEY (side-load not offered), AAD (starved), PAY (starved), IDLE.
//   Checks: FT012-C1 abort bit and busy 0 within 64 core clocks + 2 X_c in every state (SEC-02 with
//   probes) | FT012-C2 FIFOs empty after each abort | FT012-C3 next message correct after each abort
task automatic ft012();
  bit ok, b, z, a1, a2, a3;
  logic [31:0] v, fs;
  int path, beat, t0, lat;
  tc_begin("FT-012", 3);
  tc_skip_if(C_GCM_EN == 0, "GCM not built");
  if (tc_skip != "") begin tc_end(); return; end
  load_vectors("FT-012");
  path = (C_AXI == 1) ? PATH_AXI_INCR : PATH_PIO;
  beat = path_beat(path);
  set_pin(1'b0);
  sw_enable((10'h1 << EV_DONE) | EV_ERRS);
  a1 = 1'b1; a2 = 1'b1; a3 = 1'b1;
  for (int st = 0; st < 4; st++) begin
    if ((st == 0) && (C_KEY_SIDE == 0)) continue;
    load_msg(0);
    if (st == 0) begin
      apb_wr(A_KEYWAIT, 32'hFFFF);
      sw_program(0, 1, path_dsrc(path), -1, 1'b0, 1'b1, 0);
      clear_events(); sw_start();
      sh_side_window = 1'b1;
    end else if (st < 3) begin
      start_only(path, 0, 1'b1, 0);
      if (st == 1) build_tx(0, 32, 0, 0, beat);
      else build_tx(0, 64, 0, 64, beat);
      move_part(path, 0, 0, ok);
    end
    repeat (100) @(posedge clk_bus);
    t0 = cyc_bus;
    cmd(CTRL_ABORT);
    apb_poll(A_CTRL, CTRL_ABORT, 32'h0, 200, v, b);
    apb_poll(A_STS, 32'h1, 32'h0, 50, v, z);
    lat = cyc_bus - t0;
    sh_msg_active = 1'b0; sh_side_window = 1'b0;
    $display("  abort in state %0s: %0d bus clocks (bound %0d)",
             (st == 0) ? "KEY" : ((st == 1) ? "AAD" : ((st == 2) ? "PAY" : "IDLE")), lat,
             cmd_bound_bus());
    if (!(b && z && (lat <= cmd_bound_bus()))) a1 = 1'b0;
    apb_rd(A_FIFOSTS, fs);
    if (!(fs[FIFO_OUT_EMPTY] && !fs[FIFO_IN_FULL])) a2 = 1'b0;
    load_msg(1);
    run_msg(path, 0, 0, 1'b1, 0, 0);
    if (!(run_ok && (r_out_bad == 0) && tag_full_ok())) a3 = 1'b0;
  end
  apb_wr(A_KEYWAIT, 32'h100);
  tc_check("FT012-C1", a1, "abort completes within the bound in KEY, AAD, PAY and IDLE");
  tc_check("FT012-C2", a2, "FIFOs empty after every abort");
  tc_check("FT012-C3", a3, "next message correct after every abort");
  tc_end();
endtask

// FT-013  GCM request with PARA_AES_GCM_EN = 0 (REQ-FUNC-014, ERR-001, TEST-013)
//   Checks: FT013-C1 aesgcm_cap.gcm_en = 0 | FT013-C2 mode 5: CFG_ERR code 1 | FT013-C3 next ECB correct
task automatic ft013();
  logic [31:0] v;
  bit seen;
  tc_begin("FT-013", 3);
  tc_skip_if(C_GCM_EN == 1, "GCM built: build with +define+TB_CFG_LEGACY (CFG-LEGACY)");
  if (tc_skip != "") begin tc_end(); return; end
  load_vectors("FT-013");
  sw_enable((10'h1 << EV_DONE) | EV_ERRS);
  apb_rd(A_CAP, v);
  tc_check("FT013-C1", v[0] == 1'b0, "aesgcm_cap.gcm_en reads 0");
  load_msg(0);
  m_mode = M_GCM;
  run_expect_error(PATH_PIO, 0, 10'h1 << EV_CERR, seen);
  tc_check("FT013-C2", seen && (r_err[3:0] == ERRC_CFG), "mode 5 without GCM: CFG_ERR, code 1");
  load_msg(0);
  run_msg(PATH_PIO, 0, 0, 1'b1, 0, 0);
  tc_check("FT013-C3", run_ok && (r_out_bad == 0), "ECB after the rejection correct");
  tc_end();
endtask

// FT-014  Key side-load early, late, never; KEY_ERR; key never readable (REQ-FUNC-015, REQ-SEC-004,
//         6.3.5, ERR-004, TEST-014)
//   Checks: FT014-C1 valid before start: captured, one ack, output/tag = model | FT014-C2 valid 300
//   core clocks late: same | FT014-C3 never valid, keywait 40: KEY_ERR code 4 | FT014-C4 no register
//   returns a word of the side-loaded key | FT014-C5 128-bit side key correct | FT014-C6 (KEY_SIDE_EN = 0)
//   key_src = 1: KEY_ERR code 4
task automatic ft014();
  bit ok, ev, ka, leak;
  logic [31:0] v, kw [0:7];
  int path, a0;
  tc_begin("FT-014", 3);
  load_vectors("FT-014");
  path = dflt_path();
  set_pin(1'b0);
  sw_enable((10'h1 << EV_DONE) | EV_ERRS);
  load_msg(0);
  if (C_KEY_SIDE == 0) begin
    // REQ-FUNC-015 applies to every configuration: without GCM the message is a legacy ECB one.
    if (C_GCM_EN == 0) begin m_mode = 0; m_dec = 0; m_aadlen = 0; m_dlen = 16; end
    sw_program(0, 1, path_dsrc(path), -1, 1'b0, (C_GCM_EN == 1), 0);
    clear_events(); sw_start();
    wait_event(10'h1 << EV_KERR, 400, ev);
    read_results(); cmd(32'h0); sh_msg_active = 1'b0;
    tc_check("FT014-C6", ev && (r_err[3:0] == ERRC_KEY), "key_src = 1 without side-load: KEY_ERR");
    tc_check("FT014-C4", o_key_side_ack === 1'b0, "no side-load acknowledge in this build");
    tc_check("FT014-C3", !r_sts[STS_BUSY], "message ended after KEY_ERR");
    tc_end();
    return;
  end
  apb_wr(A_KEYWAIT, 32'd2000);
  for (int k = 0; k < 8; k++) kw[k] = m_key[k];
  // early: valid offered before the start
  a0 = km_acks;
  sw_program(0, 1, path_dsrc(path), -1, 1'b0, 1'b1, 0);
  clear_events();
  sh_side_window = 1'b1;
  fork
    km_offer(0, 6000, ka);
    begin
      repeat (20) @(posedge clk_bus);
      sw_start();
      build_tx(0, m_aadlen, 0, m_dlen, path_beat(path));
      move_data(path, ceil_div(m_dlen, path_beat(path)), 0, 0, ok);
    end
  join
  wait_event(10'h1 << EV_DONE | EV_ERRS, 4000, ev);
  read_results(); sh_msg_active = 1'b0; sh_side_window = 1'b0;
  tc_check("FT014-C1", ok && ev && (km_acks == a0 + 1) && (cmp_out(0, 0, m_dlen, path_beat(path),
           1'b1) == 0) && tag_full_ok(), "valid before start: one ack, output and tag = model");
  // late
  km_delay = 300;
  run_msg(path, 0, 1, 1'b1, 0, 0);
  km_delay = 4;
  tc_check("FT014-C2", run_ok && (r_out_bad == 0) && tag_full_ok(), "valid 300 core clocks late");
  // never: time-out
  apb_wr(A_KEYWAIT, 32'd40);
  sw_program(0, 1, path_dsrc(path), -1, 1'b0, 1'b1, 0);
  clear_events(); sh_side_window = 1'b1; sw_start();
  wait_event(10'h1 << EV_KERR, 400, ev);
  read_results(); cmd(32'h0); sh_msg_active = 1'b0; sh_side_window = 1'b0;
  tc_check("FT014-C3", ev && (r_err[3:0] == ERRC_KEY), "no valid within aesgcm_keywait: KEY_ERR, code 4");
  // no register returns a key word (pio_dout skipped: a read pops the output)
  leak = 1'b0;
  for (int a = 0; a < 16'h0160; a += 4) begin
    if (a == int'(A_PIO_DOUT)) continue;
    apb_rd(a[15:0], v);
    for (int k = 0; k < 8; k++) if ((v == kw[k]) && (v != 32'h0)) leak = 1'b1;
  end
  tc_check("FT014-C4", !leak, "no APB-readable register holds a word of the side-loaded key");
  apb_wr(A_KEYWAIT, 32'd2000);
  load_msg(1);
  run_msg(path, 0, 1, 1'b1, 0, 0);
  tc_check("FT014-C5", run_ok && (r_out_bad == 0) && tag_full_ok(), "AES-128 side-loaded key correct");
  tc_end();
endtask

// FT-015  Same random messages for every build (REQ-FUNC-016, REQ-PARAM-002, TEST-015)
//   Run in each build (ARCH 0/1/2, PIPE 0/1, lanes 1/4); the equivalence verdict is the conjunction of
//   the PASS results of all builds (each compared with the same model).
//   Checks: FT015-C1 outputs = model | FT015-C2 tags / tag_ok = model
task automatic ft015();
  bit a1, a2, oo, to;
  tc_begin("FT-015", 2);
  tc_skip_if(C_GCM_EN == 0, "GCM not built");
  if (tc_skip != "") begin tc_end(); return; end
  load_vectors("FT-015");
  set_pin(1'b0);
  sw_enable((10'h1 << EV_DONE) | EV_ERRS);
  a1 = 1'b1; a2 = 1'b1;
  for (int r = 0; r < v_nrec; r++) begin
    load_msg(r);
    if (m_dec) begin
      run_dec_full(dflt_path(), 1'b1, 0, 0, oo, to);
      if (!oo) a1 = 1'b0;
      if (!to) a2 = 1'b0;
    end else begin
      run_msg(dflt_path(), 0, 0, 1'b1, 0, 0);
      if (!(run_ok && (r_out_bad == 0))) a1 = 1'b0;
      if (!tag_full_ok()) a2 = 1'b0;
    end
  end
  tc_check("FT015-C1", a1, $sformatf("outputs = model (ARCH %0d, DIGIT %0d, PIPE %0d, lanes %0d)",
           C_ARCH, C_DIGIT, C_PIPE, C_LANES));
  tc_check("FT015-C2", a2, "tags = model");
  tc_end();
endtask

// FT-016  APB4 completer behavior of section 11.4 for every (i_protect_en, i_slverr_en) combination
//         (REQ-IF-001, REQ-REG-001, REQ-REG-002, DEC-009, TEST-016)
//   Checks: FT016-C1 version 0x00010000, cap = parameters | FT016-C2 partial PSTRB write: PSLVERR and
//   no change (slverr_en 1) or whole-word write (0) | FT016-C3 unaligned: PSLVERR and no change when
//   slverr_en | FT016-C4 PPROT[1] = 1: PSLVERR when protect_en & slverr_en | FT016-C5 unmapped: read 0,
//   write ignored, OKAY | FT016-C6 reserved bits read 0 | FT016-C7 key registers read 0
task automatic ft016();
  logic [31:0] v, rd;
  logic err;
  bit a2, a3, a4, a5, a6, a7, z;
  logic [15:0] unm [0:3];
  tc_begin("FT-016", 5);
  unm[0] = 16'h001C; unm[1] = 16'h0078; unm[2] = 16'h0200; unm[3] = 16'hFFFC;
  apb_rd(A_VERSION, v);
  apb_rd(A_CAP, rd);
  tc_check("FT016-C1", (v == 32'h0001_0000) &&
           ((rd & cap_compare_mask()) == (cap_expected() & cap_compare_mask())),
           $sformatf("version %08h, cap %08h (expected %08h)", v, rd, cap_expected()));
  a2 = 1'b1; a3 = 1'b1; a4 = 1'b1; a5 = 1'b1; a6 = 1'b1; a7 = 1'b1;
  for (int c = 0; c < 4; c++) begin
    pend_protect_en = c[1];
    pend_slverr_en  = c[0];
    do_reset(4);
    sh_irq_en = 10'h0; sh_dmacfg = 8'h0;
    // partial strobe write to aesgcm_datalen
    apb_xfer(1'b1, A_DATALEN, 32'hA5A5_5A5A, 4'b0001, 3'b000, rd, err);
    apb_rd(A_DATALEN, v);
    if (slverr_en) begin if (!(err && (v == 32'h0))) a2 = 1'b0; end
    else begin if (!(!err && (v == 32'h0000_005A))) a2 = 1'b0; end   // PSTRB selects the byte lanes (spec 11.4)
    // unaligned write and read
    apb_wr(A_AADLEN, 32'h0000_1111);
    apb_xfer(1'b1, A_AADLEN + 16'h1, 32'h2222_2222, 4'hF, 3'b000, rd, err);
    apb_rd(A_AADLEN, v);
    if (slverr_en && !(err && (v == 32'h0000_1111))) a3 = 1'b0;
    apb_xfer(1'b0, A_VERSION + 16'h2, 32'h0, 4'h0, 3'b000, rd, err);
    if (slverr_en && !err) a3 = 1'b0;
    // non-secure access
    apb_xfer(1'b1, A_AADLEN, 32'h3333_3333, 4'hF, 3'b010, rd, err);
    if ((protect_en && slverr_en) != err) a4 = 1'b0;
    apb_xfer(1'b0, A_VERSION, 32'h0, 4'h0, 3'b011, rd, err);
    if ((protect_en && slverr_en) != err) a4 = 1'b0;
    // unmapped addresses
    for (int u = 0; u < 4; u++) begin
      apb_xfer(1'b1, unm[u], 32'hFFFF_FFFF, 4'hF, 3'b000, rd, err);
      if (err) a5 = 1'b0;
      apb_xfer(1'b0, unm[u], 32'h0, 4'h0, 3'b000, rd, err);
      if (err || (rd != 32'h0)) a5 = 1'b0;
    end
    // reserved bits of rw registers
    apb_wr(A_CFG, 32'hFFFF_FFFF);     apb_rd(A_CFG, v);     if (v != 32'h0003_FFFF) a6 = 1'b0;
    apb_wr(A_KEYWAIT, 32'hFFFF_FFFF); apb_rd(A_KEYWAIT, v); if (v != 32'h0000_FFFF) a6 = 1'b0;
    apb_wr(A_IRQ_EN, 32'hFFFF_FC00);  apb_rd(A_IRQ_EN, v);  if (v != 32'h0) a6 = 1'b0;
    apb_wr(A_DMACFG, 32'hFFFF_FF00);  apb_rd(A_DMACFG, v);  if (v != 32'h0) a6 = 1'b0;
    apb_wr(A_CFG, 32'h0); apb_wr(A_KEYWAIT, 32'h100);
    for (int k = 0; k < 8; k++) apb_wr(A_KEY + 4 * k, 32'hC0DE_0000 | k);
    keys_read_zero(z);
    if (!z) a7 = 1'b0;
  end
  pend_protect_en = 1'b1; pend_slverr_en = 1'b1;
  do_reset(4);
  sh_irq_en = 10'h0; sh_dmacfg = 8'h0;
  tc_check("FT016-C2", a2, "partial PSTRB write per i_slverr_en");
  tc_check("FT016-C3", a3, "unaligned access: PSLVERR and no change when i_slverr_en = 1");
  tc_check("FT016-C4", a4, "non-secure access: PSLVERR exactly when protect_en and slverr_en");
  tc_check("FT016-C5", a5, "unmapped aligned addresses: OKAY, read 0");
  tc_check("FT016-C6", a6, "reserved bits read as 0");
  tc_check("FT016-C7", a7, "write-only key registers read as 0");
  tc_end();
endtask

// FT-018  PIO overrun and underrun (REQ-IF-004, 6.3.3, ERR-005, TEST-018)
//   Checks: FT018-C1 read of pio_dout while empty: 0 and PROTO_ERR | FT018-C2 write while in_full:
//   PROTO_ERR | FT018-C3 the dropped word was not pushed: resending it completes the message with the
//   model output and tag
task automatic ft018();
  logic [31:0] v, fs, w;
  bit ev, ok, full;
  int k, nwords, beat;
  tc_begin("FT-018", 3);
  load_vectors("FT-018");
  set_pin(1'b0);
  sw_enable((10'h1 << EV_DONE) | EV_ERRS);
  clear_events();
  apb_rd(A_PIO_DOUT, v);
  wait_event(10'h1 << EV_PERR, 40, ev);
  tc_check("FT018-C1", ev && (v == 32'h0), "PIO read while the output is empty: 0 and PROTO_ERR");
  tc_skip_if(C_GCM_EN == 0, "the overrun part uses a GCM vector (GCM not built)");
  if (tc_skip != "") begin tc_end(); return; end
  load_msg(0);
  beat = 4;
  start_only(PATH_PIO, 0, 1'b1, 0);
  build_tx(0, 0, 0, m_dlen, beat);
  nwords = tx_n / 4;
  full = 1'b0;
  k = 0;
  while ((k < nwords) && !full) begin
    apb_rd(A_FIFOSTS, fs);
    if (fs[FIFO_IN_FULL]) full = 1'b1;
    else begin
      for (int j = 0; j < 4; j++) w[8 * j +: 8] = tx_b[k * 4 + j];
      apb_wr(A_PIO_DIN, w);
      k++;
    end
  end
  clear_events();
  apb_wr(A_PIO_DIN, 32'hDEAD_BEEF);
  wait_event(10'h1 << EV_PERR, 40, ev);
  tc_check("FT018-C2", full && ev, $sformatf("write with in_full = 1 after %0d words: PROTO_ERR", k));
  // resend from word k (the dropped word must not have entered the FIFO)
  for (int i = k * 4; i < tx_n; i++) tx_b[i - k * 4] = tx_b[i];
  tx_n = tx_n - k * 4;
  pio_move_at(nwords - k, ceil_div(m_dlen, 4), 0, ok);
  wait_event(10'h1 << EV_DONE, 4000, ev);
  read_results();
  sh_msg_active = 1'b0;
  tc_check("FT018-C3", ok && ev && (cmp_out(0, 0, m_dlen, 4, 1'b1) == 0) && tag_full_ok(),
           "dropped word not pushed: message completes with the model output and tag");
  tc_end();
endtask

// FT-026  Error causes of section 12 not covered elsewhere (REQ-ERR-001, ERR-001, ERR-005, TEST-026)
//   Checks: FT026-C1 pass 2 without pass 1: PROTO_ERR code 5 | FT026-C2 gcm_pass 1 with decipher 0:
//   CFG_ERR | FT026-C3 AAD length 16 in pass 2: CFG_ERR | FT026-C4 suspend while idle: PROTO_ERR |
//   FT026-C5 start while busy: PROTO_ERR, message unaffected (abort ends it) | FT026-C6 tag_len 5:
//   CFG_ERR | FT026-C7 gcm_pass 3: CFG_ERR
task automatic ft026();
  bit seen, ok;
  logic [31:0] v;
  int path;
  tc_begin("FT-026", 4);
  tc_skip_if(C_GCM_EN == 0, "GCM not built");
  if (tc_skip != "") begin tc_end(); return; end
  load_vectors("FT-026");
  path = dflt_path();
  set_pin(1'b0);
  sw_enable((10'h1 << EV_DONE) | EV_ERRS);
  load_msg(0);
  if (C_HAS_PA) begin
    run_expect_error(path, 2, 10'h1 << EV_PERR, seen);
    tc_check("FT026-C1", seen && (r_err[3:0] == ERRC_PROTO), "pass 2 without pass 1: PROTO_ERR");
    m_dec = 0;
    run_expect_error(path, 1, 10'h1 << EV_CERR, seen);
    tc_check("FT026-C2", seen && (r_err[3:0] == ERRC_CFG), "pass 1 with decipher 0: CFG_ERR");
    load_msg(0);
    run_msg(path, 1, 0, 1'b1, 0, 0);
    sw_program(2, 0, path_dsrc(path), 16, 1'b0, 1'b0, 0);
    clear_events(); sw_start();
    wait_event(10'h1 << EV_CERR, 60, seen);
    read_results(); cmd(32'h0); sh_msg_active = 1'b0;
    tc_check("FT026-C3", seen && (r_err[3:0] == ERRC_CFG), "AAD length 16 in pass 2: CFG_ERR");
  end
  clear_events();
  cmd(CTRL_SUSPEND);
  wait_event(10'h1 << EV_PERR, 100, seen);
  cmd(32'h0);
  tc_check("FT026-C4", seen, "suspend while idle: PROTO_ERR");
  load_msg(1);
  start_only(path, 0, 1'b1, 0);
  apb_poll(A_STS, 32'h1, 32'h1, 100, v, ok);
  apb_poll(A_CTRL, CTRL_START, 32'h0, 200, v, ok);   // S07: the start bit is cleared when accepted
  clear_events();
  cmd(CTRL_START);
  wait_event(10'h1 << EV_PERR, 100, seen);
  cmd(CTRL_ABORT);
  apb_poll(A_STS, 32'h1, 32'h0, 200, v, ok);
  sh_msg_active = 1'b0;
  tc_check("FT026-C5", seen && ok, "start while busy: PROTO_ERR; abort ends the message");
  load_msg(2);
  run_expect_error(path, 0, 10'h1 << EV_CERR, seen);
  tc_check("FT026-C6", seen && (r_err[3:0] == ERRC_CFG), "tag_len 5: CFG_ERR");
  load_msg(3);
  run_expect_error(path, 0, 10'h1 << EV_CERR, seen);
  tc_check("FT026-C7", seen && (r_err[3:0] == ERRC_CFG), "gcm_pass 3: CFG_ERR");
  tc_end();
endtask

// FT-028  Zeroize in the AAD and payload phases (REQ-SEC-001, PERF-004, SVA-007, TEST-028)
//   Checks: FT028-C1 zeroized = 1, key_ld = 0, busy = 0 within bound in each phase (SEC-01 with probes)
//   | FT028-C2 FIFOs empty | FT028-C3 GCM start without key_new: CFG_ERR | FT028-C4 with key_new: correct
task automatic ft028();
  bit ok, seen, a1, a2, a3, a4;
  logic [31:0] v, fs;
  int path, beat, t0, lat;
  tc_begin("FT-028", 3);
  tc_skip_if(C_GCM_EN == 0, "GCM not built");
  if (tc_skip != "") begin tc_end(); return; end
  load_vectors("FT-028");
  path = (C_AXI == 1) ? PATH_AXI_INCR : PATH_PIO;
  beat = path_beat(path);
  set_pin(1'b0);
  sw_enable((10'h1 << EV_DONE) | EV_ERRS);
  a1 = 1'b1; a2 = 1'b1; a3 = 1'b1; a4 = 1'b1;
  for (int st = 1; st < 3; st++) begin
    load_msg(0);
    start_only(path, 0, 1'b1, 0);
    if (st == 1) build_tx(0, 32, 0, 0, beat);
    else build_tx(0, 64, 0, 64, beat);
    move_part(path, 0, 0, ok);
    repeat (100) @(posedge clk_bus);
    t0 = cyc_bus;
    cmd(CTRL_ZEROIZE);
    apb_poll(A_STS, 32'h29, 32'h08, 200, v, ok);    // zeroized 1, key_ld 0, busy 0
    lat = cyc_bus - t0;
    sh_msg_active = 1'b0;
    if (!(ok && (lat <= cmd_bound_bus()))) a1 = 1'b0;
    apb_rd(A_FIFOSTS, fs);
    if (!(fs[FIFO_OUT_EMPTY] && !fs[FIFO_IN_FULL])) a2 = 1'b0;
    load_msg(1);
    sw_program(0, 0, path_dsrc(path), -1, 1'b0, 1'b0, 0);
    clear_events(); sw_start();
    wait_event(10'h1 << EV_CERR, 60, seen);
    read_results(); cmd(32'h0); sh_msg_active = 1'b0;
    if (!(seen && (r_err[3:0] == ERRC_CFG))) a3 = 1'b0;
    run_msg(path, 0, 0, 1'b1, 0, 0);
    if (!(run_ok && (r_out_bad == 0) && tag_full_ok())) a4 = 1'b0;
  end
  tc_check("FT028-C1", a1, "zeroize in AAD and PAY: zeroized=1, key_ld=0, busy=0 within the bound");
  tc_check("FT028-C2", a2, "FIFOs empty after zeroize");
  tc_check("FT028-C3", a3, "GCM start after zeroize without key_new rejected");
  tc_check("FT028-C4", a4, "message with a new key after zeroize correct");
  tc_end();
endtask

// FT-029  Failed-tag counter (REQ-SEC-005, Appendix B, TEST-029)
//   Saturation at 0xFFFFFFFF needs 2^32 failures and is not reachable by simulation (open question).
//   Checks: FT029-C1 counter = number of failures | FT029-C2 not cleared by abort or zeroize |
//   FT029-C3 cleared by reset
task automatic ft029();
  bit ok, a1;
  logic [31:0] v;
  int path;
  tc_begin("FT-029", 3);
  tc_skip_if(C_GCM_EN == 0, "GCM not built");
  if (tc_skip != "") begin tc_end(); return; end
  load_vectors("FT-029");
  path = dflt_path();
  set_pin(1'b0);
  sw_enable((10'h1 << EV_DONE) | EV_ERRS);
  a1 = 1'b1;
  for (int r = 0; r < v_nrec; r++) begin
    load_msg(r);
    run_dec_check(path, r == 0);
    if (!(raw(EV_TAGF) && (r_fail == r + 1))) a1 = 1'b0;
  end
  tc_check("FT029-C1", a1, "failcnt counts every failed comparison");
  cmd(CTRL_ABORT);
  repeat (cmd_bound_bus()) @(posedge clk_bus);
  cmd(CTRL_ZEROIZE);
  apb_poll(A_STS, 32'h8, 32'h8, 200, v, ok);
  apb_rd(A_FAILCNT, v);
  tc_check("FT029-C2", ok && (v == v_nrec), "failcnt kept by abort and zeroize");
  do_reset(4);
  sh_irq_en = 10'h0; sh_dmacfg = 8'h0;
  apb_rd(A_FAILCNT, v);
  tc_check("FT029-C3", v == 32'h0, "failcnt cleared by reset");
  tc_end();
endtask

// FT-030  DEC-017 example: N = 4, ten blocks in batches 4, 4, 2 (REQ-FUNC-016, TEST-030, WF-022)
//   Checks: FT030-C1 output and tag = model (Algorithm 2 over 10 blocks) | FT030-C2 (probes) three
//   GHASH batches with counts 4, 4, 2
task automatic ft030();
  int nb, cnts [0:7];
  tc_begin("FT-030", 1);
  tc_skip_if(C_GCM_EN == 0, "GCM not built");
  tc_skip_if(C_LANES != 4, "the DEC-017 example needs PARA_AES_LANE_NUM = 4");
  if (tc_skip != "") begin tc_end(); return; end
  load_vectors("FT-030");
  set_pin(1'b0);
  sw_enable((10'h1 << EV_DONE) | EV_ERRS);
  load_msg(0);
  nb = 0;
  fork
    run_msg(dflt_path(), 0, 0, 1'b1, 0, 0);
    begin
      wait (sh_msg_active == 1'b1);
      repeat (20000) begin
        @(posedge clk_core);
        if (pr_ghash_in_valid && (nb < 8)) begin cnts[nb] = int'(pr_ghash_in_count); nb++; end
        if (!sh_msg_active) break;
      end
    end
  join
  tc_check("FT030-C1", run_ok && (r_out_bad == 0) && tag_full_ok(),
           $sformatf("10-block message with PARA_GHASH_PIPE = %0d: output and tag = model", C_PIPE));
  if (C_PROBES)
    tc_check("FT030-C2", (nb >= 4) && (cnts[nb - 4] == 4) && (cnts[nb - 3] == 4) && (cnts[nb - 2] == 2),
             "payload GHASH batches 4, 4, 2 (followed by the length block)");
  tc_end();
endtask

// FT-031  DEC-018 example: AAD 20 bytes, payload 70 bytes, 32-bit beats (REQ-FUNC-007, TEST-031)
//   Checks: FT031-C1 output and tag = model | FT031-C2 (probes) input FIFO entries 3 (N = 4) or 7 (N = 1)
task automatic ft031();
  int npush;
  tc_begin("FT-031", 1);
  tc_skip_if(C_GCM_EN == 0, "GCM not built");
  if (tc_skip != "") begin tc_end(); return; end
  load_vectors("FT-031");
  set_pin(1'b0);
  sw_enable((10'h1 << EV_DONE) | EV_ERRS);
  load_msg(0);
  npush = 0;
  fork
    run_msg(PATH_PIO, 0, 0, 1'b1, 0, 0);
    begin
      repeat (200000) begin
        @(posedge clk_bus);
        if (pr_fifo_push) npush++;
        if (!sh_msg_active && (npush > 0)) break;
      end
    end
  join
  tc_check("FT031-C1", run_ok && (r_out_bad == 0) && tag_full_ok(), "output and tag = model");
  if (C_PROBES && ((C_LANES == 4) || (C_LANES == 1)))
    tc_check("FT031-C2", npush == ((C_LANES == 4) ? 3 : 7),
             $sformatf("input FIFO entries %0d (DEC-018 example)", npush));
  tc_end();
endtask

// FT-033  out_empty while the unpacker holds the last beat (DEC-020, TEST-033)
//   Checks: FT033-C1 out_empty = 0 before each of the 5 reads | FT033-C2 out_empty = 1 after the last
//   | FT033-C3 data = model with zero padding
task automatic ft033();
  logic [31:0] fs, w;
  bit a1, ev;
  tc_begin("FT-033", 3);
  load_vectors("FT-033");
  set_pin(1'b0);
  sw_enable((10'h1 << EV_DONE) | EV_ERRS);
  load_msg(0);
  start_only(PATH_PIO, 0, 1'b1, 0);
  build_tx(0, 0, 0, m_dlen, 4);
  for (int k = 0; k < tx_n / 4; k++) begin
    for (int j = 0; j < 4; j++) w[8 * j +: 8] = tx_b[k * 4 + j];
    apb_wr(A_PIO_DIN, w);
  end
  wait_event(10'h1 << EV_DONE, 2000, ev);
  a1 = 1'b1;
  for (int k = 0; k < 5; k++) begin
    apb_rd(A_FIFOSTS, fs);
    if (fs[FIFO_OUT_EMPTY]) a1 = 1'b0;
    apb_rd(A_PIO_DOUT, w);
    for (int j = 0; j < 4; j++) rx_b[k * 4 + j] = w[8 * j +: 8];
  end
  apb_rd(A_FIFOSTS, fs);
  sh_msg_active = 1'b0;
  tc_check("FT033-C1", ev && a1, "out_empty = 0 until the last word is read");
  tc_check("FT033-C2", fs[FIFO_OUT_EMPTY] === 1'b1, "out_empty = 1 after the last word");
  tc_check("FT033-C3", cmp_out(0, 0, m_dlen, 4, 1'b1) == 0, "data = model, padding 0");
  tc_end();
endtask

// FT-036  DEC-024 Example 5: DMA input burst larger than the FIFO (ERR-001, TEST-036)
//   Checks: FT036-C1 start with the oversized burst: CFG_ERR code 1 | FT036-C2 a fitting burst starts
task automatic ft036();
  int need, beat, code;
  bit seen;
  tc_begin("FT-036", 2);
  beat = (C_AXI == 1) ? C_BEAT_AXI : C_BEAT_PIO;
  need = (16 * beat) / (16 * C_LANES) + 1;
  tc_skip_if(C_GCM_EN == 0, "GCM vectors used");
  tc_skip_if(need <= C_DEPTH, $sformatf("no burst exceeds the FIFO here (16 beats need %0d of %0d entries); build with +define+TB_AXI_DATA_W=128 +define+TB_AES_LANE_NUM=1", need, C_DEPTH));
  if (tc_skip != "") begin tc_end(); return; end
  load_vectors("FT-031");
  set_pin(1'b0);
  sw_enable((10'h1 << EV_DONE) | EV_ERRS);
  load_msg(0);
  apb_wr(A_DMACFG, {24'h0, 3'd0, 3'd4, 1'b0, 1'b1});
  run_expect_error(PATH_AXI_INCR, 0, 10'h1 << EV_CERR, seen);
  tc_check("FT036-C1", seen && (r_err[3:0] == ERRC_CFG), "oversized DMA input burst: CFG_ERR, code 1");
  apb_wr(A_DMACFG, 32'h0);
  run_msg(PATH_DMA_AXI, 0, 0, 1'b1, 0, 0);
  tc_check("FT036-C2", run_ok && (r_out_bad == 0), "fitting burst size starts and completes");
  tc_end();
endtask

// =================================================================================================
// FT-037  Pause of the beat stream with N > 1: the written blocks reach the core (DEC-026, TEST-037)
//   Priority     : P2
//   Objective    : when the input stream pauses for 16 or more BUS clocks after 40 of 96 payload
//                  bytes, the two complete blocks (32 bytes) are consumed and their output appears
//                  although the entry is not full and the segment is not finished; the rest of the
//                  message then completes with the output and tag of the uninterrupted message.
//   Requirements : REQ-FUNC-010, DEC-026, TEST-037
//   Config/state : PARA_AES_GCM_EN = 1, PARA_AES_LANE_NUM > 1, beat of 4 or 8 bytes; reset.
//   SW sequence  : S04/S05 message of 32 AAD bytes and 96 payload bytes, start; write the AAD and 40
//                  payload bytes; read 32 output bytes while no further byte is written; then write
//                  the other 56 bytes and read the other 64 bytes; S10, S11.
//   Method       : model compare of the whole output and the tag.
//   Checks       :
//     FT037-C1 | DEC-026 | pause after 40 bytes | 32 output bytes equal the model | tc_check | bounded read | differs or times out
//     FT037-C2 | REQ-FUNC-002 | end | 96 output bytes and tag equal the model | tc_check | 4000 polls | differs
//   Seed/replay  : +SEED=<n>; +TEST=FT-037
// =================================================================================================
task automatic ft037();
  bit ok, ev, first_ok;
  int path, beat;
  tc_begin("FT-037", 2);
  tc_skip_if(C_GCM_EN == 0, "GCM not built");
  tc_skip_if(C_LANES < 2, "PARA_AES_LANE_NUM = 1: a full entry is one block, nothing is held");
  if (tc_skip != "") begin tc_end(); return; end
  load_vectors("TC-06");
  path = (C_AXI == 1) ? PATH_AXI_INCR : PATH_PIO;
  beat = path_beat(path);
  tc_skip_if(beat > 8, "beat wider than 8 bytes: 40 bytes are not a whole number of beats");
  if (tc_skip != "") begin tc_end(); return; end
  set_pin(1'b0);
  sw_enable((10'h1 << EV_DONE) | EV_ERRS);
  load_msg(0);
  start_only(path, 0, 1'b1, 0);
  build_tx(0, 32, 0, 40, beat);
  move_part(path, 0, 32 / beat, ok);
  first_ok = ok && (cmp_out(0, 0, 32, beat, 1'b0) == 0);
  tc_check("FT037-C1", first_ok, "after the pause the two complete blocks of the 40 bytes are output");
  build_tx(32, 0, 40, 56, beat);
  move_part(path, 32 / beat, 64 / beat, ok);
  wait_event(10'h1 << EV_DONE | EV_ERRS, 4000, ev);
  read_results();
  sh_msg_active = 1'b0;
  tc_check("FT037-C2", first_ok && ok && ev && (cmp_out(32, 32, 64, beat, 1'b0) == 0) &&
           tag_full_ok(), "all 96 output bytes and the tag equal the uninterrupted model");
  tc_end();
endtask

// =================================================================================================
// FT-038  Second write address while the first response is pending (REQ-IF-002, 6.3.2, TEST-017)
//   Priority     : P2
//   Objective    : one write burst at a time: AWREADY stays low from the acceptance of a burst until
//                  its response is accepted; an AWVALID raised in that window is held with a stable
//                  payload (IHI0022H A3.2.1, A3.2.2) and the second burst is then served.
//   Requirements : REQ-IF-002, ERR-008, 6.3.2 (table of outstanding transactions)
//   Config/state : AXI wrapper; reset; no message (the bursts address the read window and are
//                  consumed without data: SLVERR).
//   SW sequence  : none (bus traffic only).
//   Stimulus     : burst 1 of 2 beats with BREADY delayed by 40 clocks; AW of burst 2 raised when
//                  BVALID of burst 1 is up; one beat for burst 2.
//   Checks       :
//     FT038-C1 | REQ-IF-002 | AW raised while the response is pending | AWREADY low at least one clock, then high | tc_check | bounded | never low
//     FT038-C2 | ERR-008 | both bursts | SLVERR and the IDs echoed | tc_check | at end | differs
//   Seed/replay  : +SEED=<n>; +TEST=FT-038
// =================================================================================================
task automatic ft038();
  logic [1:0] br1, br2;
  logic [C_IW-1:0] bid1, bid2;
  bit ok1, stalled, ok2;
  int n, saved_dly;
  tc_begin("FT-038", 2);
  tc_skip_if(C_AXI == 0, "no AXI4 window on m_aesgcm_acc_apb_top (FEAT-006)");
  if (tc_skip != "") begin tc_end(); return; end
  set_pin(1'b0);
  saved_dly = axi_bready_dly_max;
  axi_bready_dly_max = 40;
  for (int i = 0; i < 8 * C_BEAT_AXI; i++) tx_b[i] = 8'(rnd32());
  stalled = 1'b0; ok2 = 1'b1; br2 = 2'b11; bid2 = '0;
  fork
    axi_write_burst(4'h1, AXI_RD_WIN, 1, AXI_SIZE_FULL, BURST_INCR, 0, 1'b0, br1, bid1, ok1);
    begin
      // Raise the second address at the clock of the last write beat of burst 1: the window is then
      // in its response state, whatever the BREADY delay of the master.
      n = 0;
      while (!((o_axi_wready === 1'b1) && (axi_wvalid === 1'b1) && (axi_wlast === 1'b1)) &&
             (n < 5000)) begin @(posedge clk_bus); n++; end
      axi_awid <= 4'h2; axi_awaddr <= AXI_RD_WIN; axi_awlen <= 8'd0; axi_awsize <= AXI_SIZE_FULL;
      axi_awburst <= BURST_INCR; axi_awvalid <= 1'b1;
      n = 0;
      do begin
        @(posedge clk_bus);
        if (o_axi_awready !== 1'b1) stalled = 1'b1;
        n++;
      end while ((o_axi_awready !== 1'b1) && (n < 5000));
      axi_awvalid <= 1'b0;
      if (n >= 5000) ok2 = 1'b0;
      else begin
        axi_wdata <= '0; axi_wstrb <= {C_BEAT_AXI{1'b1}}; axi_wlast <= 1'b1; axi_wvalid <= 1'b1;
        n = 0;
        do begin @(posedge clk_bus); n++; end while ((o_axi_wready !== 1'b1) && (n < 5000));
        axi_wvalid <= 1'b0; axi_wlast <= 1'b0;
        axi_bready <= 1'b1;
        n = 0;
        do begin @(posedge clk_bus); n++; end while ((o_axi_bvalid !== 1'b1) && (n < 5000));
        br2 = o_axi_bresp; bid2 = o_axi_bid;
        axi_bready <= 1'b0;
        if (n >= 5000) ok2 = 1'b0;
      end
    end
  join
  axi_bready_dly_max = saved_dly;
  tc_check("FT038-C1", ok1 && ok2 && stalled, "AWREADY low while the first response is pending, high after it");
  tc_check("FT038-C2", (br1 == 2'b10) && (bid1 == 4'h1) && (br2 == 2'b10) && (bid2 == 4'h2),
           "both bursts answered with SLVERR and their IDs");
  tc_end();
endtask
