// -------------------------------------------------------------------------------------------------
// Project      : AES-GCM Accelerator - acceptance simulation testbench
// File         : tb_aesgcm_tests_tc2.svh (included inside module tb_aesgcm_top)
// Description  : Integrated testcases TC-09 to TC-15 (same conventions as tb_aesgcm_tests_tc.svh).
// -------------------------------------------------------------------------------------------------

// =================================================================================================
// TC-09  AXI4 window robustness inside a live GCM message
//   Priority     : P1
//   Objective    : illegal bursts (WRAP, reserved type, wrong AxSIZE, wrong window) to
//                  both windows are answered with SLVERR, consumed completely and leave the FIFOs
//                  unchanged, while legal FIXED/INCR bursts (up to 256 beats) of the same message
//                  produce the model output and tag; IDs are echoed; no interrupt event is raised. A separate
//                  message checks the early-WLAST burst (SLVERR, abort recovers; DEC-029, ERR-010).
//   Requirements : REQ-IF-002, REQ-IF-003, ERR-008, ERR-010, 6.3.2; IHI0022H A3.2, A3.4.1, Table A3-5, A5.2;
//                  TEST-017, TEST-031
//   Config/state : AXI wrapper; reset; BREADY/RREADY back-pressure by seed.
//   SW sequence  : S04/S05 AES-256 GCM encrypt aad 40, len 2048, dat_src 0; S07; AXI traffic below;
//                  S10; S11.
//   Stimulus     : legal INCR AAD burst; WRAP/len 4, reserved/len 2, INCR with size-1, INCR to the
//                  read window; illegal reads WRAP, wrong size, write window; then the
//                  payload in INCR bursts of up to 256 beats with FIXED/INCR reads in parallel.
//   Failure mode : illegal data pushed or popped, response wrong, ID lost, deadlock, PROTO_ERR.
//   Method       : AXI-* assertions (AXI-16, AXI-21, AXI-14, AXI-18, AXI-19), model compare.
//   Checks       :
//     TC09-C1 | 6.3.2, ERR-008 | each illegal write | BRESP SLVERR, BID = AWID | tc_check | 200000 clk | OKAY or wrong ID
//     TC09-C2 | 6.3.2, A3.4.1 | each illegal read | RRESP SLVERR, zero data, all beats | tc_check | 200000 clk | OKAY/data/hang
//     TC09-C3 | REQ-IF-002 | each legal write | BRESP OKAY, BID echoed | tc_check | 200000 clk | SLVERR
//     TC09-C4 | REQ-FUNC-002 | message end | ciphertext = model (FIFOs unchanged by illegal bursts) | tc_check | 4000 polls | byte differs
//     TC09-C5 | REQ-FUNC-002 | message end | tag = model | tc_check | at end | differs
//     TC09-C6 | ERR-008 (no interrupt) | message end | no PROTO_ERR/LEN_ERR raw event | tc_check | at end | event set
//   Seed/replay  : +SEED=<n>; +TEST=TC-09
// =================================================================================================
task automatic tc09();
  bit ok, okw, okr, ev, all1, all2, all3, zd;
  logic [31:0] v;
  logic [1:0] br, rr;
  logic [C_IW-1:0] bi, id;
  int beat, aad_beats, pay_beats, junk, done_b, len;
  tc_begin("TC-09", 5);
  tc_skip_if(C_AXI == 0, "no AXI4 window on m_aesgcm_acc_apb_top (FEAT-006)");
  tc_skip_if(C_GCM_EN == 0, "GCM not built");
  if (tc_skip != "") begin tc_end(); return; end
  load_vectors("TC-09");
  set_pin(1'b0);
  sw_enable((10'h1 << EV_DONE) | EV_ERRS);
  beat = C_BEAT_AXI;
  load_msg(0);
  build_tx(0, m_aadlen, 0, m_dlen, beat);
  aad_beats = ceil_div(m_aadlen, beat);
  pay_beats = ceil_div(m_dlen, beat);
  junk = tx_n;
  for (int i = 0; i < 64 * beat; i++) tx_b[junk + i] = 8'(rnd32());
  start_only(PATH_AXI_INCR, 0, 1'b1, 0);
  all1 = 1'b1; all2 = 1'b1; all3 = 1'b1;
  // legal AAD burst
  id = 4'h3;
  axi_write_burst(id, AXI_WR_WIN, aad_beats - 1, AXI_SIZE_FULL, BURST_INCR, 0, 1'b0, br, bi, ok);
  if (!(ok && (br == 2'b00) && (bi == id))) all3 = 1'b0;
  // illegal writes
  axi_write_burst(4'h5, AXI_WR_WIN, 3, AXI_SIZE_FULL, BURST_WRAP, junk, 1'b0, br, bi, ok);
  if (!(ok && (br == 2'b10) && (bi == 4'h5))) all1 = 1'b0;
  axi_write_burst(4'h6, AXI_WR_WIN, 1, AXI_SIZE_FULL, BURST_RSVD, junk, 1'b0, br, bi, ok);
  if (!(ok && (br == 2'b10) && (bi == 4'h6))) all1 = 1'b0;
  axi_write_burst(4'h7, AXI_WR_WIN, 3, AXI_SIZE_FULL - 3'd1, BURST_INCR, junk, 1'b0, br, bi, ok);
  if (!(ok && (br == 2'b10) && (bi == 4'h7))) all1 = 1'b0;
  axi_write_burst(4'h8, AXI_RD_WIN, 1, AXI_SIZE_FULL, BURST_INCR, junk, 1'b0, br, bi, ok);
  if (!(ok && (br == 2'b10) && (bi == 4'h8))) all1 = 1'b0;
  tc_check("TC09-C1", all1, "WRAP, reserved, wrong size and read-window writes: SLVERR");
  // illegal reads
  axi_read_burst(4'hA, AXI_RD_WIN, 3, AXI_SIZE_FULL, BURST_WRAP, 0, 1'b0, 2000, rr, zd, ok);
  if (!(ok && (rr == 2'b10) && zd)) all2 = 1'b0;
  axi_read_burst(4'hB, AXI_RD_WIN, 1, AXI_SIZE_FULL - 3'd1, BURST_INCR, 0, 1'b0, 2000, rr, zd, ok);
  if (!(ok && (rr == 2'b10) && zd)) all2 = 1'b0;
  axi_read_burst(4'hC, AXI_WR_WIN, 2, AXI_SIZE_FULL, BURST_FIXED, 0, 1'b0, 2000, rr, zd, ok);
  if (!(ok && (rr == 2'b10) && zd)) all2 = 1'b0;
  tc_check("TC09-C2", all2, "WRAP, wrong size and write-window reads: SLVERR beats with zero data");
  // payload with long INCR bursts, reads in parallel
  tb_in_beats_sent = 0; tb_out_beats_got = 0;
  okw = 1'b1; okr = 1'b1;
  fork
    begin
      done_b = 0;
      while ((done_b < pay_beats) && okw) begin
        len = pay_beats - done_b;
        if (len > 256) len = 256;
        id = C_IW'(rnd32());
        axi_write_burst(id, AXI_WR_WIN, len - 1, AXI_SIZE_FULL, BURST_INCR,
                        (aad_beats + done_b) * beat, 1'b0, br, bi, ok);
        if (!(ok && (br == 2'b00) && (bi == id))) begin okw = 1'b0; all3 = 1'b0; end
        done_b += len;
      end
    end
    axi_pull(0, pay_beats, 16, 3, okr);
  join
  tc_check("TC09-C3", all3 && okw, "legal AAD and 256-beat INCR payload bursts: OKAY, BID echoed");
  wait_event(10'h1 << EV_DONE | EV_ERRS, 4000, ev);
  read_results();
  sh_msg_active = 1'b0;
  tc_check("TC09-C4", okr && ev && (cmp_out(0, 0, m_dlen, beat, 1'b1) == 0),
           "ciphertext = model: illegal bursts did not change the FIFOs");
  tc_check("TC09-C5", tag_full_ok(), "tag = model");
  tc_check("TC09-C6", !raw(EV_PERR) && !raw(EV_LERR) && raw(EV_DONE),
           "no PROTO_ERR or LEN_ERR from bus responses (ERR-008: bus response only)");
  // Early WLAST (DEC-029, ERR-010): SLVERR, the beats already accepted stay in the stream, so the
  // message is ended with abort.
  clear_events();
  load_msg(0);
  start_only(PATH_AXI_INCR, 0, 1'b1, 0);
  axi_write_burst(4'h9, AXI_WR_WIN, 3, AXI_SIZE_FULL, BURST_INCR, junk, 1'b1, br, bi, ok);
  tc_check("TC09-C7", ok && (br == 2'b10) && (bi == 4'h9),
           "write burst with an early WLAST: SLVERR after the last beat, BID echoed (ERR-010)");
  cmd(CTRL_ABORT);
  apb_poll(A_CTRL, CTRL_ABORT, 32'h0, 400, v, ok);
  sh_msg_active = 1'b0;
  tc_check("TC09-C8", ok, "abort accepted after the early-WLAST burst");
  tc_end();
endtask

// =================================================================================================
// TC-10  DMA four-phase over PIO with all burst sizes, slow and fast acknowledge, DMA events
//   Priority     : P1
//   Objective    : the DMA requests of both channels follow the four-phase rules for burst sizes 1
//                  to 16 and acknowledge delays 0 and 8, never claim room or data that does not exist
//                  (no PIO overrun/underrun), stop at the end of the message and raise DMA_IN_RDY /
//                  DMA_OUT_RDY; GCM and legacy messages are correct.
//   Requirements : REQ-IF-005, REQ-IF-004, REQ-INT-001, 6.3.4, invariant 7; TEST-019, TEST-018,
//                  TEST-001 (CBC, CTR), TEST-003
//   Config/state : every build (PIO exists in both wrappers); reset.
//   SW sequence  : per message: S06 aesgcm_dmacfg in_en/out_en, in_burst, out_burst; S04/S05;
//                  S07; DMA model moves the stream through aesgcm_pio_din/dout; S10; S11; dmacfg 0.
//   Stimulus     : (in, out) burst codes (0,1), (1,2), (2,3), (3,4); ack delay 0 or 8.
//   Failure mode : request withdrawn, early re-request, request without room/data (dropped words),
//                  request after the end, missing events.
//   Method       : DMA-IN/OUT-01..12 assertions, model compare, raw events.
//   Checks       :
//     TC10-C1 | REQ-IF-005 | each end | output = model | tc_check | 4000 polls | byte differs
//     TC10-C2 | REQ-FUNC-002/005 | GCM ends | tag = model / tag_ok=1 | tc_check | at end | differs
//     TC10-C3 | 6.3.4 phase 1 | each end | number of input bursts = ceil(beats / burst) | tc_check | at end | differs
//     TC10-C4 | ERR-005, 6.3.4 | each end | no PROTO_ERR (no overrun/underrun) | tc_check | at end | set
//     TC10-C5 | 6.4 DMA_IN_RDY/OUT_RDY | over the messages | dinr and dour raw seen | tc_check | at end | never set
//     TC10-C6 | 6.3.4 | 50 clocks after each end | both requests 0 (DMA-*-10/11) | tc_check | 50 bus clk | request high
//   Seed/replay  : +SEED=<n>; +TEST=TC-10
// =================================================================================================
task automatic tc10();
  bit okall1, okall2, okall3, okall4, okall6, seen_dinr, seen_dour, out_ok, tag_ok;
  int ib, ob, bi0, nmsg, beats;
  tc_begin("TC-10", 5);
  load_vectors("TC-10");
  set_pin(1'b0);
  sw_enable((10'h1 << EV_DONE) | EV_ERRS);
  okall1 = 1'b1; okall2 = 1'b1; okall3 = 1'b1; okall4 = 1'b1; okall6 = 1'b1;
  seen_dinr = 1'b0; seen_dour = 1'b0; nmsg = 0;
  sh_burst_bound = 200 + 16 * 2 * (apb_gap_max + 8) + 16;
  for (int r = 0; r < v_nrec; r++) begin
    load_msg(r);
    if ((m_mode == M_GCM) && (C_GCM_EN == 0)) continue;
    ib = r % 4;
    ob = (r % 4) + 1;
    dma_ack_dly_max = (r % 2 == 0) ? 0 : 8;
    bi0 = dma_bursts_in;
    beats = ceil_div(m_aadlen, 4) + ceil_div(m_dlen, 4);
    if ((m_mode == M_GCM) && m_dec) begin
      run_dec_full(PATH_DMA_PIO, 1'b1, ib, ob, out_ok, tag_ok);
      if (!out_ok) okall1 = 1'b0;
      if (!tag_ok) okall2 = 1'b0;
      if (C_HAS_PC) beats = ceil_div(m_aadlen, 4) + ceil_div(m_dlen, 4);
      else beats = beats + ceil_div(m_dlen, 4);
    end else begin
      run_msg(PATH_DMA_PIO, 0, 0, 1'b1, ib, ob);
      if (!(run_ok && (r_out_bad == 0))) okall1 = 1'b0;
      if ((m_mode == M_GCM) && !tag_full_ok()) okall2 = 1'b0;
    end
    if ((dma_bursts_in - bi0) != 0) begin
      int expb;
      expb = (C_HAS_PC || !((m_mode == M_GCM) && m_dec)) ?
             ceil_div(beats, burst_beats(ib)) :
             ceil_div(ceil_div(m_aadlen, 4) + ceil_div(m_dlen, 4), burst_beats(ib)) +
             ceil_div(ceil_div(m_dlen, 4), burst_beats(ib));
      if ((dma_bursts_in - bi0) != expb) okall3 = 1'b0;
    end else okall3 = 1'b0;
    if (raw(EV_PERR)) okall4 = 1'b0;
    if (raw(EV_DINR)) seen_dinr = 1'b1;
    if (raw(EV_DOUR)) seen_dour = 1'b1;
    repeat (50) @(posedge clk_bus);
    if ((o_dma_in_req !== 1'b0) || (o_dma_out_req !== 1'b0)) okall6 = 1'b0;
    nmsg++;
  end
  dma_ack_dly_max = 3;
  tc_check("TC10-C1", okall1 && (nmsg > 0), $sformatf("output = model for %0d messages", nmsg));
  tc_check("TC10-C2", okall2, "GCM tags = model / tag_ok = 1");
  tc_check("TC10-C3", okall3, "one input burst per request, ceil(beats/burst) requests");
  tc_check("TC10-C4", okall4, "no PROTO_ERR: no PIO overrun or underrun under DMA control");
  tc_check("TC10-C5", seen_dinr && seen_dour, "DMA_IN_RDY and DMA_OUT_RDY raw events raised");
  tc_check("TC10-C6", okall6, "both DMA requests low after the message ended");
  tc_end();
endtask

// =================================================================================================
// TC-11  Legacy modes behind the accelerator, configuration and length errors, recovery
//   Priority     : P1
//   Objective    : ECB, CBC, CFB (all 8 segment sizes, DEC-021), OFB and CTR in both directions and
//                  key sizes equal the FIPS-197 / SP 800-38A model; illegal starts are rejected with
//                  the right event and code; the first error code is cleared at the next start and
//                  the next message is correct.
//   Requirements : REQ-FUNC-001, REQ-ERR-001, ERR-001, ERR-002, 9.2 (CFB bytes); TEST-001, TEST-013
//                  (dat_src on APB wrapper), TEST-026
//   Config/state : every build (CFG-LEGACY included); reset.
//   SW sequence  : per record S04 key + key_new, S05 mode, decipher, cfb_seg, IV (4 words), datalen,
//                  aadlen 0; S07; S08; S10. Error records: ECB len 20, CTR len 0 (LEN_ERR); mode 6,
//                  aadlen 16, cfb_seg 9 (CFG_ERR); APB wrapper: dat_src = 0 (CFG_ERR).
//   Stimulus     : alternating PIO and AXI4 paths on the AXI wrapper.
//   Failure mode : wrong mode mapping, CFB byte packing, partial OFB/CTR block, missing error,
//                  sticky error code.
//   Method       : aes128_256_ref.run_stream model compare; err_code.
//   Checks       :
//     TC11-C1 | REQ-FUNC-001 | each ECB/CBC/OFB/CTR end | output = model | tc_check | 4000 polls | byte differs
//     TC11-C2 | REQ-FUNC-001, DEC-021 | each CFB end | output = model, unused bits 0 | tc_check | 4000 polls | differs
//     TC11-C3 | ERR-002 | ECB len 20, CTR len 0 | LEN_ERR, code 2 | tc_check | 2000 polls | none
//     TC11-C4 | ERR-001 | mode 6, aad 16, cfb_seg 9 | CFG_ERR, code 1 | tc_check | 60 polls | none
//     TC11-C5 | REQ-ERR-001 | recovery message | output = model, code 0 | tc_check | 4000 polls | differs
//     TC11-C6 | 6.4 | each legal end | DONE without error event | tc_check | at end | error
//     TC11-C7 | ERR-001 | APB wrapper, dat_src 0 | CFG_ERR, code 1 | tc_check | 60 polls | none (APB builds)
//   Seed/replay  : +SEED=<n>; +TEST=TC-11
// =================================================================================================
task automatic tc11();
  bit seen, a1, a2, a3, a4, a6;
  int path, last;
  tc_begin("TC-11", 5);
  load_vectors("TC-11");
  set_pin(1'b0);
  sw_enable((10'h1 << EV_DONE) | EV_ERRS);
  a1 = 1'b1; a2 = 1'b1; a3 = 1'b1; a4 = 1'b1; a6 = 1'b1;
  last = v_nrec - 1;
  for (int r = 0; r < v_nrec; r++) begin
    load_msg(r);
    path = ((C_AXI == 1) && (r % 2 == 1)) ? PATH_AXI_MIX : PATH_PIO;
    if (m_action == 1) begin
      run_expect_error(path, 0, 10'h1 << EV_LERR, seen);
      if (!(seen && (r_err[3:0] == ERRC_LEN))) a3 = 1'b0;
      cmd(CTRL_ABORT);   // ERR-002 recovery: abort, then restart
      repeat (cmd_bound_bus()) @(posedge clk_bus);
    end else if (m_action != 0) begin
      run_expect_error(path, 0, 10'h1 << EV_CERR, seen);
      if (!(seen && (r_err[3:0] == ERRC_CFG))) a4 = 1'b0;
    end else begin
      run_msg(path, 0, 0, 1'b1, 0, 0);
      if (r == last) begin
        tc_check("TC11-C5", run_ok && (r_out_bad == 0) && (r_err[3:0] == ERRC_NONE),
                 "recovery message after the errors correct, err_code cleared");
      end else if (m_mode == M_CFB) begin
        if (!(run_ok && (r_out_bad == 0))) a2 = 1'b0;
      end else begin
        if (!(run_ok && (r_out_bad == 0))) a1 = 1'b0;
      end
      if (!raw(EV_DONE) || ((r_raw[9:0] & EV_ERRS) != 0)) a6 = 1'b0;
    end
  end
  tc_check("TC11-C1", a1, "ECB, CBC, OFB, CTR outputs equal the model (both directions, key sizes)");
  tc_check("TC11-C2", a2, "CFB segment sizes 1..128 equal the model (DEC-021 byte packing)");
  tc_check("TC11-C3", a3, "ECB tail and CTR length 0: LEN_ERR, code 2");
  tc_check("TC11-C4", a4, "mode 6, AAD in a legacy mode, cfb_seg 9: CFG_ERR, code 1");
  tc_check("TC11-C6", a6, "legal legacy messages end with DONE and no error event");
  if (C_AXI == 0) begin
    load_msg(0);
    sw_program(0, 0, DSRC_AXI, -1, 1'b1, 1'b1, 0);
    clear_events(); sw_start();
    wait_event(10'h1 << EV_CERR, 60, seen);
    read_results(); cmd(32'h0); sh_msg_active = 1'b0;
    tc_check("TC11-C7", seen && (r_err[3:0] == ERRC_CFG), "dat_src = 0 on the APB wrapper: CFG_ERR");
  end
  tc_end();
endtask

// =================================================================================================
// TC-12  Interrupt plumbing: injection, masking, w1c clear, two causes, real event while masked
//   Priority     : P2
//   Objective    : every cause of the common register set can be injected, is masked by irq_en,
//                  drives o_int_aesgcm when enabled and is cleared by write-1; the line is the OR of
//                  the masked causes; a real DONE while masked is kept and raises the line on enable.
//   Requirements : REQ-IF-006, REQ-INT-001, invariant 6, 11.3 (injection on rising edge); TEST-020
//   Config/state : every build; reset; no message active during injection.
//   SW sequence  : for each bit: irq_inj = bit, irq_inj = 0; read raw/sts; irq_en = bit; read sts;
//                  w1c; irq_en = 0. Two causes; ECB message with irq_en = 0, then irq_en = DONE.
//   Stimulus     : register accesses; one 16-byte ECB message.
//   Failure mode : missing or shifted cause bit, mask ignored, line not cleared, w1c not working.
//   Method       : INT-02/03/04 assertions, register reads, port sampling.
//   Checks       :
//     TC12-C1 | 11.3 injection | inj rising edge | raw bit i = 1 for all 10 causes | tc_check | 1 read | 0
//     TC12-C2 | 6.4, workbook irq_sts | masked | irq_sts = raw & en = 0, o_int = 0 | tc_check | 3 bus clk | differs
//     TC12-C3 | REQ-IF-006 | irq_en bit set | irq_sts bit = 1, o_int = 1 | tc_check | 3 bus clk | low
//     TC12-C4 | REQ-IF-006 | w1c | raw bit 0, o_int 0 within 2 bus clocks | tc_check | 3 bus clk | high
//     TC12-C5 | invariant 6 | two causes, one cleared | line stays 1, then 0 | tc_check | 3 bus clk | differs
//     TC12-C6 | REQ-INT-001 | DONE while masked, then enable | raw.done=1, line 0, then 1 | tc_check | 3 bus clk | differs
//     TC12-C7 | REQ-FUNC-001 | ECB end | output = model | tc_check | 4000 polls | differs
//   Seed/replay  : +SEED=<n>; +TEST=TC-12
// =================================================================================================
task automatic tc12();
  logic [31:0] rv, sv;
  bit a1, a2, a3, a4, b, b2;
  tc_begin("TC-12", 5);
  load_vectors("TC-12");
  set_pin(1'b0);
  sw_enable(10'h0);
  a1 = 1'b1; a2 = 1'b1; a3 = 1'b1; a4 = 1'b1;
  for (int i = 0; i < 10; i++) begin
    apb_wr(A_IRQ_INJ, 32'h1 << i);
    apb_wr(A_IRQ_INJ, 32'h0);
    repeat (4) @(posedge clk_bus);
    apb_rd(A_IRQ_RAW, rv);
    apb_rd(A_IRQ_STS, sv);
    if (!rv[i]) a1 = 1'b0;
    if ((sv[9:0] != 10'h0) || (o_int_aesgcm !== 1'b0)) a2 = 1'b0;
    apb_wr(A_IRQ_EN, 32'h1 << i);
    int_after(3, 1'b1, b);
    apb_rd(A_IRQ_STS, sv);
    if (!(b && sv[i])) a3 = 1'b0;
    apb_wr(A_IRQ_RAW, 32'h1 << i);
    sh_int_clear_arm <= 1'b1; @(posedge clk_bus); sh_int_clear_arm <= 1'b0;
    int_after(2, 1'b0, b);
    apb_rd(A_IRQ_RAW, rv);
    if (!(b && !rv[i])) a4 = 1'b0;
    apb_wr(A_IRQ_EN, 32'h0);
  end
  tc_check("TC12-C1", a1, "injection sets each of the 10 raw causes");
  tc_check("TC12-C2", a2, "masked causes: irq_sts = 0 and the line stays low");
  tc_check("TC12-C3", a3, "enabled cause: irq_sts bit and the line high within 2 bus clocks");
  tc_check("TC12-C4", a4, "write-1-to-clear clears the cause, line low within 2 bus clocks");
  apb_wr(A_IRQ_INJ, 32'h201); apb_wr(A_IRQ_INJ, 32'h0);
  apb_wr(A_IRQ_EN, 32'h201);
  int_after(3, 1'b1, b);
  apb_wr(A_IRQ_RAW, 32'h001);
  int_after(3, 1'b1, b2);
  apb_wr(A_IRQ_RAW, 32'h200);
  sh_int_clear_arm <= 1'b1; @(posedge clk_bus); sh_int_clear_arm <= 1'b0;
  int_after(2, 1'b0, a1);
  tc_check("TC12-C5", b && b2 && a1, "two causes: line stays high until the last one is cleared");
  apb_wr(A_IRQ_EN, 32'h0);
  load_msg(0);
  run_msg(dflt_path(), 0, 0, 1'b1, 0, 0);
  int_after(3, 1'b0, b);
  apb_wr(A_IRQ_EN, 32'h1 << EV_DONE);
  int_after(3, 1'b1, b2);
  tc_check("TC12-C6", raw(EV_DONE) && b && b2, "DONE kept while masked; line rises when enabled");
  tc_check("TC12-C7", run_ok && (r_out_bad == 0), "ECB message output = model");
  apb_wr(A_IRQ_EN, 32'h0);
  irq_clear_armed();
  tc_end();
endtask

// =================================================================================================
// TC-13  Reset during an active message, reset values, single-domain reset recovery
//   Priority     : P1
//   Objective    : an asynchronous reset of both domains in the payload phase drives the outputs to
//                  their reset values, empties every key and data store (CSR reset values, CFG_ERR on
//                  a GCM start without key_new), and a new message is correct; after a reset of one
//                  domain, zeroize (ASM-007) recovers both domains.
//   Requirements : REQ-RESET-001, REQ-RESET-002, ERR-009, ASM-007, 6.2/7.3 reset values, REQ-REG-001;
//                  TEST-024, TEST-016 (reset values)
//   Config/state : every GCM build; reset; DMA input channel enabled to have o_dma_in_req high and
//                  an injected DONE to have o_int_aesgcm high before the reset.
//   SW sequence  : M1 S02 (irq_en DONE) S06 dmacfg in_en S04 S05 S07, push part of the stream, inject
//                  DONE; reset both; read every register; M2 start without key_new; M2 with key_new;
//                  M1 partial, reset CORE only, S03 zeroize, M2 with key_new; same with BUS reset.
//   Stimulus     : reset asserted at a random phase of both clocks.
//   Failure mode : outputs not reset, key survives reset, handshake stuck after a single reset.
//   Method       : RST-*, DMA-*-07, X-* assertions; register reads vs workbook reset values.
//   Checks       :
//     TC13-C1 | workbook reset values, REQ-REG-001 | after release | version 0x00010000, cap, ctrl, cfg, keywait 0x100, sts, fifosts, irq, err, failcnt, dmacfg, tagout | tc_check | first reads | differs
//     TC13-C2 | 6.2, 7.3 | during and after reset | o_int=0, DMA requests 0 (RST-02, DMA-IN-07) | tc_check | 1 bus clk | high
//     TC13-C3 | REQ-RESET-002, ERR-001 | GCM start without key_new | CFG_ERR code 1 | tc_check | 60 polls | accepted
//     TC13-C4 | REQ-RESET-001 | M2 with key_new | output/tag = model | tc_check | 4000 polls | differs
//     TC13-C5 | ERR-009, ASM-007 | CORE-only reset + zeroize | zeroized=1, busy=0; M2 correct | tc_check | cmd_bound_bus | differs
//     TC13-C6 | ERR-009, ASM-007 | BUS-only reset + zeroize | zeroized=1, busy=0; M2 correct | tc_check | cmd_bound_bus | differs
//   Seed/replay  : +SEED=<n>; +TEST=TC-13
// =================================================================================================
task automatic tc13();
  logic [31:0] v;
  bit ok, seen, rv_ok, b1, b2;
  int path, beat;
  tc_begin("TC-13", 5);
  tc_skip_if(C_GCM_EN == 0, "GCM not built: the key_new rule of ERR-001 applies to GCM only");
  if (tc_skip != "") begin tc_end(); return; end
  load_vectors("TC-13");
  path = (C_AXI == 1) ? PATH_AXI_INCR : PATH_PIO;
  beat = path_beat(path);
  set_pin(1'b0);
  sw_enable(10'h1 << EV_DONE);
  sh_in_left = 1000;              // request raised on purpose, no DMA model: beats remain (DMA-IN-11)
  sh_burst_bound = 1000000;       // the burst is never served before the reset (DMA-IN-12)
  apb_wr(A_DMACFG, 32'h1);
  load_msg(0);
  start_only(path, 0, 1'b1, 0);
  build_tx(0, 16, 0, 128, beat);
  move_part(path, 0, 0, ok);
  apb_wr(A_IRQ_INJ, 32'h1); apb_wr(A_IRQ_INJ, 32'h0);
  repeat (int'(rnd_range(5, 40))) @(posedge clk_bus);
  b1 = (o_int_aesgcm === 1'b1);
  do_reset(4);
  sh_msg_active = 1'b0; sh_irq_en = 10'h0; sh_dmacfg = 8'h0;
  sh_in_left = 0; sh_burst_bound = 4000;
  b2 = (o_int_aesgcm === 1'b0) && (o_dma_in_req === 1'b0) && (o_dma_out_req === 1'b0);
  tc_check("TC13-C2", b1 && b2, "line high before reset; line and DMA requests 0 after reset");
  rv_ok = 1'b1;
  apb_rd(A_VERSION, v); if (v != 32'h0001_0000) rv_ok = 1'b0;
  apb_rd(A_CAP, v);
  if ((v & cap_compare_mask()) != (cap_expected() & cap_compare_mask())) begin
    rv_ok = 1'b0; $display("  aesgcm_cap = %08h expected %08h (mask %08h)", v, cap_expected(),
                           cap_compare_mask());
  end
  apb_rd(A_CTRL, v);     if (v != 32'h0) rv_ok = 1'b0;
  apb_rd(A_CFG, v);      if (v != 32'h0) rv_ok = 1'b0;
  apb_rd(A_AADLEN, v);   if (v != 32'h0) rv_ok = 1'b0;
  apb_rd(A_DATALEN, v);  if (v != 32'h0) rv_ok = 1'b0;
  apb_rd(A_KEYWAIT, v);  if (v != 32'h100) rv_ok = 1'b0;
  apb_rd(A_STS, v);
  if ((v & 32'h000F_0F2F) != 32'h0) rv_ok = 1'b0;            // busy..key_ld, phase, ctx_vld = 0
  if (v[STS_SEC_ONLY] !== sec_pin) rv_ok = 1'b0;
  apb_rd(A_FIFOSTS, v);  if ((v[FIFO_IN_FULL] != 1'b0) || (v[FIFO_OUT_EMPTY] != 1'b1)) rv_ok = 1'b0;
  apb_rd(A_IRQ_RAW, v);  if (v != 32'h0) rv_ok = 1'b0;
  apb_rd(A_IRQ_EN, v);   if (v != 32'h0) rv_ok = 1'b0;
  apb_rd(A_IRQ_INJ, v);  if (v != 32'h0) rv_ok = 1'b0;
  apb_rd(A_IRQ_STS, v);  if (v != 32'h0) rv_ok = 1'b0;
  apb_rd(A_ERR_CODE, v); if (v != 32'h0) rv_ok = 1'b0;
  apb_rd(A_FAILCNT, v);  if (v != 32'h0) rv_ok = 1'b0;
  apb_rd(A_DMACFG, v);   if (v != 32'h0) rv_ok = 1'b0;
  apb_rd(A_CONS_A, v);   if (v != 32'h0) rv_ok = 1'b0;
  apb_rd(A_CONS_D, v);   if (v != 32'h0) rv_ok = 1'b0;
  for (int k = 0; k < 4; k++) begin
    apb_rd(A_TAGOUT + 4 * k, v); if (v != 32'h0) rv_ok = 1'b0;
    apb_rd(A_IV + 4 * k, v);     if (v != 32'h0) rv_ok = 1'b0;
    apb_rd(A_TAGIN + 4 * k, v);  if (v != 32'h0) rv_ok = 1'b0;
  end
  tc_check("TC13-C1", rv_ok, "register reset values of the workbook after a reset in the payload phase");
  sw_enable((10'h1 << EV_DONE) | EV_ERRS);
  load_msg(1);
  sw_program(0, 0, path_dsrc(path), -1, 1'b1, 1'b0, 0);
  clear_events(); sw_start();
  wait_event(10'h1 << EV_CERR, 60, seen);
  read_results(); cmd(32'h0); sh_msg_active = 1'b0;
  tc_check("TC13-C3", seen && (r_err[3:0] == ERRC_CFG), "key store empty after reset: GCM start without key_new rejected");
  run_msg(path, 0, 0, 1'b1, 0, 0);
  tc_check("TC13-C4", run_ok && (r_out_bad == 0) && tag_full_ok(), "message after reset correct");
  // single-domain resets
  for (int d = 0; d < 2; d++) begin
    load_msg(0);
    start_only(path, 0, 1'b1, 0);
    build_tx(0, 16, 0, 64, beat);
    move_part(path, 0, 0, ok);
    repeat (50) @(posedge clk_bus);
    do_reset_one(d == 0, 4);                      // d = 0: CORE only, d = 1: BUS only
    sh_msg_active = 1'b0;
    if (d == 1) begin sh_irq_en = 10'h0; sh_dmacfg = 8'h0; end
    sw_enable((10'h1 << EV_DONE) | EV_ERRS);
    cmd(CTRL_ZEROIZE);
    apb_poll(A_STS, 32'h9, 32'h8, 200, v, ok);   // zeroized = 1 and busy = 0
    load_msg(1);
    run_msg(path, 0, 0, 1'b1, 0, 0);
    tc_check((d == 0) ? "TC13-C5" : "TC13-C6", ok && run_ok && (r_out_bad == 0) && tag_full_ok(),
             (d == 0) ? "CORE-only reset recovered by zeroize; next message correct" :
                        "BUS-only reset recovered by zeroize; next message correct");
  end
  tc_end();
endtask

// =================================================================================================
// TC-14  Clock-domain crossing under the build's clock relation with GCM, legacy and status
//   Priority     : P1
//   Objective    : with asynchronous clocks of random period and phase (PARA_CLK_ASYNC = 1) or
//                  related clocks of the selected ratio (PARA_CLK_ASYNC = 0, +CLK_RATIO), the bundle,
//                  data FIFO and status crossings deliver every byte, the start bit is accepted within
//                  the crossing budget and status registers are coherent after DONE.
//   Requirements : REQ-CLK-001, REQ-CLK-002 (async) or REQ-CLK-003 (sync), CDC-001..004, 13.2 X_c,
//                  DEC-008, DEC-018; TEST-022 or TEST-023, TEST-031
//   Config/state : any build; clocks set by plusargs; reset.
//   SW sequence  : per record S04/S05/S07; poll ctrl.start; S08; S10; S11 twice.
//   Stimulus     : AAD 20 / payload 70 (DEC-018 Example 1), AES-256 decrypt AAD 13 / 129, CTR 48.
//   Failure mode : bundle sampled unstable, FIFO pointer crossing loses data, status torn.
//   Method       : model compare; latency of the start acceptance; repeated reads.
//   Checks       :
//     TC14-C1 | REQ-CLK-002/003 | each end | output = model | tc_check | 4000 polls | differs
//     TC14-C2 | REQ-CLK-002/003 | GCM ends | tag = model / tag_ok | tc_check | at end | differs
//     TC14-C3 | CDC-001, 13.2 | start write | ctrl.start reads 0 within 2 X_c + polling | tc_check | bound | later
//     TC14-C4 | DEC-008 | after DONE | tagout and sts identical in two reads | tc_check | at end | differ
//     TC14-C5 | 7.1, REQ-CLK-001 | test start | clock relation reported (SIM-BRANCH, ratio/phase) and two clocks toggle | tc_check | 100 clk | missing
//   Seed/replay  : +SEED=<n> (async periods/phases); +CLK_RATIO=1_1|3_2|4_1|1_4 for sync builds;
//                  +TEST=TC-14
// =================================================================================================
task automatic tc14();
  bit a1, a2, a3, a4, ok, out_ok, tag_ok;
  logic [31:0] v, t2 [0:3], s2;
  int path, t0, lat, c0b, c0c;
  tc_begin("TC-14", 5);
  load_vectors("TC-14");
  set_pin(1'b0);
  sw_enable((10'h1 << EV_DONE) | EV_ERRS);
  c0b = cyc_bus; c0c = cyc_core;
  repeat (100) @(posedge clk_bus);
  tc_check("TC14-C5", ((cyc_bus - c0b) >= 100) && ((cyc_core - c0c) > 10),
           $sformatf("%0s clocks: Tbus %0d ps, Tcore %0d ps", (C_ASYNC == 1) ? "asynchronous" :
                     {"synchronous ratio ", clk_ratio_s}, t_bus_per, t_core_per));
  a1 = 1'b1; a2 = 1'b1; a3 = 1'b1; a4 = 1'b1;
  for (int r = 0; r < v_nrec; r++) begin
    load_msg(r);
    if ((m_mode == M_GCM) && (C_GCM_EN == 0)) continue;
    path = ((C_AXI == 1) && (r != 1)) ? PATH_AXI_MIX : PATH_PIO;
    if ((m_mode == M_GCM) && m_dec) begin
      run_dec_full(path, 1'b1, 0, 0, out_ok, tag_ok);
      if (!out_ok) a1 = 1'b0;
      if (!tag_ok) a2 = 1'b0;
    end else begin
      // start acceptance latency measured on this message
      sw_program(0, 0, path_dsrc(path), -1, 1'b1, 1'b1, 0);
      clear_events();
      t0 = cyc_bus;
      sw_start();
      apb_poll(A_CTRL, CTRL_START, 32'h0, 100, v, ok);
      lat = cyc_bus - t0;
      if (!ok || (lat > 2 * xc_bus() + 8 * (apb_gap_max + 4))) a3 = 1'b0;
      $display("  start accepted after %0d bus clocks (bound %0d)", lat,
               2 * xc_bus() + 8 * (apb_gap_max + 4));
      build_tx(0, m_aadlen, 0, m_dlen, path_beat(path));
      move_data(path, ceil_div(m_dlen, path_beat(path)), 0, 0, ok);
      wait_event(10'h1 << EV_DONE | EV_ERRS, 4000, out_ok);
      read_results();
      sh_msg_active = 1'b0;
      if (!(ok && out_ok && (cmp_out(0, 0, m_dlen, path_beat(path), 1'b1) == 0))) a1 = 1'b0;
      if ((m_mode == M_GCM) && !tag_full_ok()) a2 = 1'b0;
    end
    for (int k = 0; k < 4; k++) apb_rd(A_TAGOUT + 4 * k, t2[k]);
    apb_rd(A_STS, s2);
    for (int k = 0; k < 4; k++) if (t2[k] != r_tag[k]) a4 = 1'b0;
    if (s2 != r_sts) a4 = 1'b0;
  end
  tc_check("TC14-C1", a1, "every byte delivered across the crossings (output = model)");
  tc_check("TC14-C2", a2, "GCM tags = model / tag_ok across the status crossing");
  tc_check("TC14-C3", a3, "start accepted within the crossing budget of 13.2");
  tc_check("TC14-C4", a4, "tagout and sts stable after DONE (DEC-008)");
  tc_end();
endtask

// =================================================================================================
// TC-15  Latency and rate against section 13.2 (PERF-001, PERF-002, PERF-005)
//   Priority     : P2
//   Objective    : the start-to-DONE latency of a 280-byte AES-256 packet and of a 1 KB message does
//                  not exceed the PERF-001 formula plus the crossings and the measured time of the
//                  data movement (the formula assumes data already in the FIFO, which the software
//                  sequence of 11.2 cannot provide before start); with probes the GHASH input cycles
//                  of the payload do not exceed g(p) + 8.
//   Requirements : REQ-PERF-001, REQ-PERF-002, PERF-001, PERF-005; TEST-027
//   Config/state : any GCM build; AXI4 INCR (or PIO) path; reset.
//   SW sequence  : S04/S05/S07; S08 at full bus rate; S10 poll; S11.
//   Stimulus     : AXI INCR bursts of 16 beats, no WVALID gaps, RREADY always high.
//   Failure mode : stalls or serialization above the specified latency.
//   Method       : cycle counters on both clocks; model compare.
//   Checks       :
//     TC15-C1 | PERF-001, PERF-005 | DONE observed | latency <= bound (formula + 2 X_c + data time + polling) | tc_check | at end | above
//     TC15-C2 | PERF-001 | DONE observed (1 KB) | latency <= bound | tc_check | at end | above
//     TC15-C3 | REQ-FUNC-002 | each end | output and tag = model | tc_check | 4000 polls | differs
//   Seed/replay  : +SEED=<n>; +TEST=TC-15
// =================================================================================================
task automatic tc15();
  bit ok, ev, a3;
  int path, beat, wg, rd;
  longint lat_ps, bound_ps, t_ps0, t_move;
  tc_begin("TC-15", 3);
  tc_skip_if(C_GCM_EN == 0, "GCM not built");
  if (tc_skip != "") begin tc_end(); return; end
  load_vectors("TC-15");
  path = (C_AXI == 1) ? PATH_AXI_INCR : PATH_PIO;
  beat = path_beat(path);
  set_pin(1'b0);
  sw_enable((10'h1 << EV_DONE) | EV_ERRS);
  wg = axi_wgap_max; rd = axi_rready_dly_max;
  axi_wgap_max = 0; axi_rready_dly_max = 0;
  a3 = 1'b1;
  for (int r = 0; r < 2; r++) begin
    load_msg(r);
    sw_program(0, 0, path_dsrc(path), -1, 1'b1, 1'b1, 0);
    build_tx(0, m_aadlen, 0, m_dlen, beat);
    clear_events();
    t_ps0 = $time;
    sw_start();
    move_data(path, ceil_div(m_dlen, beat), 0, 0, ok);
    t_move = $time - t_ps0;
    wait_event(10'h1 << EV_DONE | EV_ERRS, 4000, ev);
    lat_ps = longint'(r_lat_bus) * t_bus_per;
    read_results();
    sh_msg_active = 1'b0;
    bound_ps = longint'(perf001_core(m_ksz, m_aadlen, m_dlen)) * t_core_per +
               2 * longint'(xc_bus()) * t_bus_per + t_move +
               longint'(8 * (apb_gap_max + 4)) * t_bus_per;
    $display("  PERF-001: latency %0d ps, bound %0d ps (formula %0d core clocks, data %0d ps)",
             lat_ps, bound_ps, perf001_core(m_ksz, m_aadlen, m_dlen), t_move);
    tc_check((r == 0) ? "TC15-C1" : "TC15-C2", ev && (lat_ps <= bound_ps),
             $sformatf("start-to-DONE latency within PERF-001 bound (%0d <= %0d ps)", lat_ps,
                       bound_ps));
    if (!(ok && (cmp_out(0, 0, m_dlen, beat, 1'b1) == 0) && tag_full_ok())) a3 = 1'b0;
  end
  tc_check("TC15-C3", a3, "outputs and tags = model");
  axi_wgap_max = wg; axi_rready_dly_max = rd;
  tc_end();
endtask
