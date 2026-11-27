// -------------------------------------------------------------------------------------------------
// Project      : AES-GCM Accelerator - acceptance simulation testbench
// File         : tb_aesgcm_tests_tc.svh (included inside module tb_aesgcm_top)
// Description  : Integrated testcases TC-01 to TC-15 (rule R-048: each combines two or more specified
//                functions in one sequence and checks their interaction; rule R-095 header and at
//                least five executable checks). Specification: VLSIT_AES_GCM_ACCELERATOR_HDS.md v0.1
//                (Draft) with aesgcm_regs.json workbook 1.0; standards IHI 0024D, IHI 0022H.c,
//                SP 800-38D. Expected data and tags come from vectors/<ID>.hex (gen_tb_vectors.py,
//                independent models). Replay: <sim> +TEST=<ID> +SEED=<n> (README.md).
//                Check table columns: ID | spec ref | trigger | expected | checker | deadline |
//                failure condition. "tc_check" is the checker of every check; assertion IDs named in a
//                row are the backing assertions (counted once with the check, R-095).
// -------------------------------------------------------------------------------------------------

// =================================================================================================
// TC-01  Secure-boot image: side-load key + policy A pass 1/pass 2 + DMA over AXI4 + interrupt
//   Priority     : P1 (highest risk: plaintext of a forged image, key exposure, DMA deadlock)
//   Objective    : a side-loaded AES-256 key, policy A forced by i_gcm_secure_only = 1 and DMA bursts
//                  through the AXI4 window cooperate: pass 1 verifies without any output, pass 2
//                  releases plaintext only after ver_ok, ciphertext changed between the passes is
//                  detected, and key_new invalidates the verified context.
//   Requirements : REQ-FUNC-003, REQ-FUNC-004, REQ-FUNC-015, REQ-SEC-002, REQ-SEC-004, REQ-IF-002,
//                  REQ-IF-005, REQ-IF-006, REQ-SEC-005; TEST-004, TEST-005, TEST-014, TEST-019
//   Config/state : CFG-FULL or CFG-BOOT-like (policy A, PARA_KEY_SIDE_EN = 1, AXI wrapper); after
//                  reset, i_gcm_secure_only = 1, aesgcm_keywait = 2000.
//   SW sequence  : S02 ctrl.en, irq_en = DONE|TAG_FAIL|errors; S04 cfg.key_src = 1, keywait, key_new;
//                  S05 cfg mode 5 decipher pass 1, IV, aadlen 32, datalen 512, tagin; S06 dmacfg
//                  in_en burst 4; S07 start; S08 DMA moves AAD+ciphertext; S10 wait DONE; S11 read
//                  sts.ver_ok/tag_ok, tagout; S12 cfg.gcm_pass = 2, aadlen 0, dmacfg in/out, start,
//                  DMA moves ciphertext and plaintext; S10/S11; repeat pass 1, then pass 2 with a
//                  modified ciphertext (record 1); key_new; pass 2 without pass 1.
//   Stimulus     : key manager offers the key 50 core clocks after start; DMA ack delay 0..3.
//   Failure mode : plaintext leaks in pass 1; pass 2 accepted without verification; side-load
//                  handshake broken; changed ciphertext not detected; failcnt not counted.
//   Method       : model compare (gcm_ref) of plaintext and tag; POL-01/02/03, DMA-*, KS-* assertions.
//   Checks       :
//     TC01-C1 | REQ-FUNC-003 | pass-1 end event | ver_ok=1, tag_ok=1, DONE, err_code 0 | tc_check | 4000 polls | any differs
//     TC01-C2 | REQ-SEC-002 | pass-1 end | out_empty=1, no output beat (POL-01/02) | tc_check | at end event | out_empty=0
//     TC01-C3 | REQ-FUNC-015, 6.3.5 | each side-load start | exactly one ack per message (KS-01..05) | tc_check | 4000 core clk | count differs
//     TC01-C4 | workbook tagout | pass-1 end | tagout = model T over (A,C) | tc_check | at end | any bit differs
//     TC01-C5 | REQ-FUNC-004, OP-005 | pass-2 end | plaintext = model | tc_check | 4000 polls | any byte differs
//     TC01-C6 | REQ-FUNC-004 | pass-2 end | tag_ok=1, DONE, no TAG_FAIL, err_code 0 | tc_check | at end | differs
//     TC01-C7 | REQ-FUNC-004, ERR-006, ASM-006 | pass 2 with modified C | TAG_FAIL, tag_ok=0, failcnt+1, code 6 | tc_check | at end | differs
//     TC01-C8 | REQ-IF-006 | DONE with en.done=1 | o_int=1; falls within 2 clocks of clear (INT-02/03) | tc_check | 3 bus clk | line wrong
//     TC01-C9 | REQ-FUNC-004, ERR-005 | key_new then pass 2 | PROTO_ERR, code 5, no output | tc_check | 60 polls | no PROTO_ERR
//   Seed/replay  : +SEED=<n> (DMA ack delays, APB gaps, AXI back-pressure); +TEST=TC-01
// =================================================================================================
task automatic tc01();
  bit ok, b, seen;
  int acks0;
  logic [31:0] f0, v;
  tc_begin("TC-01", 5);
  tc_skip_if(!C_HAS_PA, "policy A not built (PARA_GCM_REL_POLICY = 1, FEAT-003)");
  tc_skip_if(C_KEY_SIDE == 0, "side-load not built (PARA_KEY_SIDE_EN = 0, FEAT-010)");
  tc_skip_if(C_AXI == 0, "no AXI4 window on m_aesgcm_acc_apb_top (FEAT-006)");
  if (tc_skip != "") begin tc_end(); return; end
  load_vectors("TC-01");
  set_pin(1'b1);
  sw_enable((10'h1 << EV_DONE) | EV_ERRS);
  apb_wr(A_KEYWAIT, 32'd2000);
  // ---- pass 1 (verify only) with side-load key and DMA input bursts through the AXI4 window
  load_msg(0);
  km_delay = 50;
  acks0 = km_acks;
  sh_burst_bound = 64 + 4 * 16 * (axi_wgap_max + 2) + 2 * (axi_bready_dly_max + 2);
  run_msg(PATH_DMA_AXI, 1, 1, 1'b1, 2, 2);
  tc_check("TC01-C3", (km_acks - acks0) == 1, $sformatf("pass 1: one side-load ack (%0d)",
           km_acks - acks0));
  acks0 = km_acks;
  tc_check("TC01-C1", run_ok && r_sts[STS_VER_OK] && r_sts[STS_TAG_OK] && raw(EV_DONE) &&
           !raw(EV_TAGF) && (r_err[3:0] == ERRC_NONE), "pass 1: ver_ok=1, tag_ok=1, DONE, code 0");
  tc_check("TC01-C2", r_fifo[FIFO_OUT_EMPTY] === 1'b1, "pass 1 wrote no output (out_empty=1)");
  tc_check("TC01-C4", tag_full_ok(), "pass 1 aesgcm_tagout equals the model tag");
  // ---- pass 2 (decrypt) after ver_ok with input and output DMA
  run_msg(PATH_DMA_AXI, 2, 1, 1'b0, 2, 3);
  tc_check("TC01-C5", run_ok && (r_out_bad == 0), "pass 2 plaintext equals the model");
  tc_check("TC01-C6", r_sts[STS_TAG_OK] && raw(EV_DONE) && !raw(EV_TAGF) &&
           (r_err[3:0] == ERRC_NONE), "pass 2: tag_ok=1, DONE, no TAG_FAIL, code 0");
  int_after(3, 1'b1, b);
  tc_check("TC01-C8", b, "o_int_aesgcm high while DONE is pending and enabled");
  irq_clear_armed();
  int_after(3, 1'b0, b);
  tc_check("TC01-C8", b, "o_int_aesgcm low within 2 bus clocks after the clear");
  // Pass 2 may reuse the verified key or capture the side-load again (open question Q-14).
  tc_check("TC01-C3", (km_acks - acks0) <= 1, $sformatf("pass 2: at most one side-load ack (%0d)",
           km_acks - acks0));
  // ---- pass 1 again, then pass 2 with a ciphertext modified between the passes (ASM-006)
  apb_rd(A_FAILCNT, f0);
  run_msg(PATH_DMA_AXI, 1, 1, 1'b0, 2, 2);
  load_msg(1);
  run_msg(PATH_DMA_AXI, 2, 1, 1'b0, 2, 3);
  tc_check("TC01-C7", raw(EV_TAGF) && !r_sts[STS_TAG_OK] && (r_fail == f0 + 1) &&
           (r_err[3:0] == ERRC_TAG), "modified ciphertext: TAG_FAIL, tag_ok=0, failcnt+1, code 6");
  tc_check("TC01-C7", r_out_bad == 0, "released plaintext equals the model of the modified input");
  // ---- key_new invalidates the verified context: pass 2 without pass 1 is rejected
  load_msg(0);
  sw_key_new();
  sh_side_window = 1'b1;
  run_expect_error(PATH_AXI_INCR, 2, 10'h1 << EV_PERR, seen);
  sh_side_window = 1'b0;
  tc_check("TC01-C9", seen && (r_err[3:0] == ERRC_PROTO) && r_fifo[FIFO_OUT_EMPTY],
           "pass 2 without a verified context: PROTO_ERR, code 5, no output");
  set_pin(1'b0);
  km_delay = 4;
  tc_end();
endtask

// =================================================================================================
// TC-02  Policy C forged packet, interrupt masking, failure counter and recovery (DEC-024 Ex. 6)
//   Priority     : P1
//   Objective    : policy C releases plaintext and flags the forgery; TAG_FAIL is masked from the
//                  interrupt until enabled; the failure leaves no input entry so the next packet with
//                  the same key is correct; err_code is cleared at the next start.
//   Requirements : REQ-FUNC-005, REQ-SEC-005, REQ-ERR-001, REQ-IF-006, REQ-INT-001; TEST-006,
//                  TEST-029, TEST-036 (Ex. 6), ERR-006
//   Config/state : any build with policy C (CFG-FULL, CFG-LINK); i_gcm_secure_only = 0; reset.
//   SW sequence  : S02 en, irq_en = DONE only; S04 key, key_new; S05 mode 5 decipher pass 0, tagin
//                  (forged); S07; S08 data; S10; S11 sts, err_code, failcnt; read irq_sts; w1c DONE;
//                  irq_en |= TAG_FAIL; w1c all; S05..S11 valid packet without key_new.
//   Stimulus     : 280-byte packets with 16-byte AAD (drone link case of section 1.4).
//   Failure mode : forgery not flagged, failcnt not incremented, masked cause drives the line,
//                  stale FIFO data corrupts the next packet, err_code sticky across messages.
//   Method       : model compare; INT-02/03/04 assertions; register reads.
//   Checks       :
//     TC02-C1 | REQ-FUNC-005 | forged end event | plaintext = model (released) | tc_check | 4000 polls | byte differs
//     TC02-C2 | ERR-006 | forged end | TAG_FAIL raw, tag_ok=0, code 6 | tc_check | at end | differs
//     TC02-C3 | REQ-SEC-005 | forged end | failcnt = 0 after reset, then 1 | tc_check | at end | differs
//     TC02-C4 | REQ-INT-001, 6.4 | after DONE cleared | irq_sts.tagf=0 while raw.tagf=1; o_int=0 (INT-03) | tc_check | 3 bus clk | line high
//     TC02-C5 | REQ-IF-006 | irq_en.tagf=1 | o_int=1 within 2 clocks (INT-02) | tc_check | 3 bus clk | line low
//     TC02-C6 | DEC-024 Ex.6, REQ-ERR-001 | valid packet end | output = model, tag_ok=1, code 0, failcnt unchanged | tc_check | 4000 polls | differs
//   Seed/replay  : +SEED=<n>; +TEST=TC-02
// =================================================================================================
task automatic tc02();
  logic [31:0] v, st;
  bit b;
  int path;
  tc_begin("TC-02", 5);
  tc_skip_if(!C_HAS_PC, "policy C not built (PARA_GCM_REL_POLICY = 0, FEAT-004)");
  if (tc_skip != "") begin tc_end(); return; end
  load_vectors("TC-02");
  path = dflt_path();
  set_pin(1'b0);
  sw_enable(10'h1 << EV_DONE);
  apb_rd(A_FAILCNT, v);
  tc_check("TC02-C3", v == 32'h0, "aesgcm_failcnt reads 0 after reset");
  load_msg(0);
  run_msg(path, 0, 0, 1'b1, 0, 0);
  tc_check("TC02-C1", run_ok && (r_out_bad == 0), "policy C releases the plaintext of the model");
  tc_check("TC02-C2", raw(EV_TAGF) && !r_sts[STS_TAG_OK] && (r_err[3:0] == ERRC_TAG),
           "forged tag: TAG_FAIL raw, tag_ok=0, err_code 6");
  tc_check("TC02-C3", r_fail == 32'd1, "aesgcm_failcnt incremented to 1");
  apb_rd(A_IRQ_STS, st);
  apb_wr(A_IRQ_RAW, 32'h1 << EV_DONE);
  sh_int_clear_arm <= 1'b1; @(posedge clk_bus); sh_int_clear_arm <= 1'b0;
  int_after(3, 1'b0, b);
  apb_rd(A_IRQ_RAW, v);
  tc_check("TC02-C4", !st[EV_TAGF] && v[EV_TAGF] && b,
           "masked TAG_FAIL: irq_sts.tagf=0, raw.tagf=1, line low after DONE is cleared");
  apb_wr(A_IRQ_EN, (32'h1 << EV_DONE) | (32'h1 << EV_TAGF));
  int_after(3, 1'b1, b);
  apb_rd(A_IRQ_STS, st);
  tc_check("TC02-C5", b && st[EV_TAGF], "enabling TAG_FAIL raises the line within 2 bus clocks");
  irq_clear_armed();
  load_msg(1);
  run_msg(path, 0, 0, 1'b0, 0, 0);
  tc_check("TC02-C6", run_ok && (r_out_bad == 0) && r_sts[STS_TAG_OK] &&
           (r_err[3:0] == ERRC_NONE) && (r_fail == 32'd1) && !raw(EV_TAGF),
           "next packet: output = model, tag_ok=1, code cleared, failcnt unchanged");
  tc_end();
endtask

// =================================================================================================
// TC-03  i_gcm_secure_only against the release policies
//   Priority     : P1
//   Objective    : with the pin at 1 a policy C request is rejected before any plaintext (CFG_ERR,
//                  nothing sent to the core) while policy A still works; with the pin at 0 policy C
//                  works; aesgcm_sts.sec_only follows the pin.
//   Requirements : REQ-FUNC-009, REQ-SEC-003, REQ-FUNC-003, REQ-FUNC-004, 6.3.6; TEST-009, ERR-001
//   Config/state : policy C built (CFG-FULL: both; CFG-LINK: pin part only); reset.
//   SW sequence  : pin=1; read sts; S04/S05 decipher pass 0; S07 -> expect CFG_ERR; [policy A: pass 1,
//                  pass 2]; pin=0; read sts; policy C message.
//   Stimulus     : 64-byte packet, AAD 8.
//   Failure mode : policy C reachable with the pin, plaintext produced before the rejection,
//                  sec_only stale.
//   Method       : POL-04 assertion window, register reads, model compare.
//   Checks       :
//     TC03-C1 | 6.3.6 | pin=1 settled | sts.sec_only=1 | tc_check | 16 clk | differs
//     TC03-C2 | REQ-FUNC-009, ERR-001 | start policy C, pin=1 | CFG_ERR, code 1, busy 0 | tc_check | 60 polls | no CFG_ERR
//     TC03-C3 | REQ-SEC-003 | after the rejection | out_empty=1, no output (POL-04) | tc_check | at end | output seen
//     TC03-C4 | REQ-FUNC-003/004 | policy A passes with pin=1 | ver_ok, plaintext = model, tag_ok | tc_check | 4000 polls | differs (policy A builds)
//     TC03-C5 | 6.3.6 | pin=0 settled | sts.sec_only=0 | tc_check | 16 clk | differs
//     TC03-C6 | REQ-FUNC-005 | policy C with pin=0 | plaintext = model, tag_ok=1 | tc_check | 4000 polls | differs
//   Seed/replay  : +SEED=<n>; +TEST=TC-03
// =================================================================================================
task automatic tc03();
  logic [31:0] v;
  bit seen, b1, b2;
  int path;
  tc_begin("TC-03", 5);
  tc_skip_if(!C_HAS_PC, "policy C not built: the pin has nothing to block (REQ-SEC-003)");
  if (tc_skip != "") begin tc_end(); return; end
  load_vectors("TC-03");
  path = dflt_path();
  sw_enable((10'h1 << EV_DONE) | EV_ERRS);
  set_pin(1'b1);
  apb_rd(A_STS, v);
  tc_check("TC03-C1", v[STS_SEC_ONLY] === 1'b1, "aesgcm_sts.sec_only = 1 with the pin at 1");
  load_msg(0);
  sh_pc_blocked = 1'b1;
  run_expect_error(path, 0, 10'h1 << EV_CERR, seen);
  repeat (50) @(posedge clk_bus);
  sh_pc_blocked = 1'b0;
  tc_check("TC03-C2", seen && (r_err[3:0] == ERRC_CFG) && !r_sts[STS_BUSY],
           "policy C with the pin: CFG_ERR, code 1, busy 0");
  tc_check("TC03-C3", r_fifo[FIFO_OUT_EMPTY] === 1'b1, "no plaintext produced (out_empty=1)");
  if (C_HAS_PA) begin
    run_msg(path, 1, 0, 1'b0, 0, 0);
    b1 = r_sts[STS_VER_OK];
    run_msg(path, 2, 0, 1'b0, 0, 0);
    tc_check("TC03-C4", b1 && (r_out_bad == 0) && r_sts[STS_TAG_OK],
             "policy A pass 1 and pass 2 work with the pin at 1");
  end
  set_pin(1'b0);
  apb_rd(A_STS, v);
  tc_check("TC03-C5", v[STS_SEC_ONLY] === 1'b0, "aesgcm_sts.sec_only = 0 with the pin at 0");
  run_msg(path, 0, 0, 1'b0, 0, 0);
  tc_check("TC03-C6", run_ok && (r_out_bad == 0) && r_sts[STS_TAG_OK],
           "policy C with the pin at 0: plaintext = model, tag_ok=1");
  tc_end();
endtask

// =================================================================================================
// TC-04  Tag length per key: truncation, latch at key_new, reserved codes
//   Priority     : P2
//   Objective    : every tag-length code gives the leading t bits of T; the code latched at key_new
//                  cannot change without a new key_new; reserved codes are rejected; a decryption
//                  compares only the leading t bits.
//   Requirements : REQ-FUNC-006, REQ-FUNC-002, REQ-FUNC-003/005, REQ-SEC-005; TEST-007, ERR-001
//   Config/state : any GCM build; reset.
//   SW sequence  : for c = 0..4: key K_c, cfg.tag_len = c, key_new, encrypt; cfg.tag_len 0 without
//                  key_new -> start; cfg.tag_len 5 + key_new -> start; for c: decrypt with a tag
//                  flipped outside and inside MSB_t (pass 1 or policy C).
//   Stimulus     : AAD 20, payload 33 bytes (tails in both segments).
//   Failure mode : wrong truncation or bit order, missing latch, bits beyond t compared.
//   Method       : model compare of tagout; status and failcnt.
//   Checks       :
//     TC04-C1 | REQ-FUNC-006 | each encryption end | leading t bits of tagout = model | tc_check | 4000 polls | differs
//     TC04-C2 | spec 5.3 step 7 | each encryption end | full 128-bit tagout = model, ciphertext = model | tc_check | at end | differs
//     TC04-C3 | REQ-FUNC-006, ERR-001 | tag_len change without key_new | CFG_ERR, code 1 | tc_check | 60 polls | none
//     TC04-C4 | 9.3, ERR-001 | tag_len 5 | CFG_ERR, code 1 | tc_check | 60 polls | none
//     TC04-C5 | REQ-FUNC-006 | tag differs only after bit t | tag_ok=1 | tc_check | 4000 polls | tag_ok=0
//     TC04-C6 | REQ-FUNC-006, REQ-SEC-005 | tag differs in bit t-1 | TAG_FAIL, failcnt+1 | tc_check | 4000 polls | not flagged
//   Seed/replay  : +SEED=<n>; +TEST=TC-04
// =================================================================================================
task automatic tc04();
  bit seen, all1, all2, all5, all6;
  int path;
  logic [31:0] f0;
  tc_begin("TC-04", 5);
  tc_skip_if(C_GCM_EN == 0, "GCM not built (PARA_AES_GCM_EN = 0)");
  if (tc_skip != "") begin tc_end(); return; end
  load_vectors("TC-04");
  path = dflt_path();
  set_pin(1'b0);
  sw_enable((10'h1 << EV_DONE) | EV_ERRS);
  all1 = 1'b1; all2 = 1'b1;
  for (int c = 0; c < 5; c++) begin
    load_msg(c);
    run_msg(path, 0, 0, 1'b1, 0, 0);
    if (!(run_ok && tag_lead_ok(tbits(c)))) all1 = 1'b0;
    if (!(tag_full_ok() && (r_out_bad == 0))) all2 = 1'b0;
  end
  tc_check("TC04-C1", all1, "leading t bits of aesgcm_tagout equal the model for t = 128..96");
  tc_check("TC04-C2", all2, "full 128-bit tagout and ciphertext equal the model");
  // tag length 128 for the key latched with code 4 (no key_new)
  load_msg(4);
  m_tlc = 0;
  sw_program(0, 0, path_dsrc(path), -1, 1'b0, 1'b0, 0);
  clear_events(); sw_start();
  wait_event(10'h1 << EV_CERR, 60, seen);
  read_results(); cmd(32'h0); sh_msg_active = 1'b0;
  tc_check("TC04-C3", seen && (r_err[3:0] == ERRC_CFG), "tag_len changed without key_new: CFG_ERR");
  load_msg(0);
  m_action = 5;
  run_expect_error(path, 0, 10'h1 << EV_CERR, seen);
  tc_check("TC04-C4", seen && (r_err[3:0] == ERRC_CFG), "reserved tag_len 5: CFG_ERR, code 1");
  all5 = 1'b1; all6 = 1'b1;
  for (int c = 0; c < 5; c++) begin
    load_msg(5 + c);
    run_dec_check(path, 1'b1);
    if (!(run_ok && r_sts[STS_TAG_OK] && !raw(EV_TAGF))) all5 = 1'b0;
    apb_rd(A_FAILCNT, f0);
    load_msg(10 + c);
    run_dec_check(path, 1'b0);
    if (!(raw(EV_TAGF) && !r_sts[STS_TAG_OK] && (r_fail == f0 + 1))) all6 = 1'b0;
  end
  tc_check("TC04-C5", all5, "a tag differing only after bit t matches (leading t bits compared)");
  tc_check("TC04-C6", all6, "a tag differing in bit t-1 fails and increments failcnt");
  tc_end();
endtask

// =================================================================================================
// TC-05  Known answers, length sweep with tails, GMAC and the empty message over every data path
//   Priority     : P1
//   Objective    : SP 800-38D results for AES-128/256, AAD 0..33 x payload 0..33 (tails 1..15 in
//                  both segments), GMAC and empty message, with the data path cycling between AXI4
//                  INCR, FIXED, mixed bursts and PIO; output padding reads 0; key words 4..7 and
//                  aesgcm_iv_3 ignored.
//   Requirements : REQ-FUNC-002, REQ-FUNC-007, REQ-FUNC-008, REQ-FUNC-012, REQ-IF-002, REQ-IF-004;
//                  TEST-002, TEST-003, TEST-008, TEST-017, TEST-018
//   Config/state : any GCM build; reset.
//   SW sequence  : per record: AES-128 records write random words to aesgcm_key_4..7; S04 key,
//                  key_new; S05; S07; S08 path; S10; S11 tagout.
//   Stimulus     : 8 NIST test cases (1-4, 13-16) + 48 sweep messages, all five tag lengths.
//   Failure mode : J0/inc32 error, partial-block masking, length block, segment padding, path bugs.
//   Method       : gcm_ref model compare.
//   Checks       :
//     TC05-C1 | REQ-FUNC-002/012 | each end | ciphertext = model (all records) | tc_check | 4000 polls | any byte
//     TC05-C2 | REQ-FUNC-002 | each end | tagout leading t and full = model | tc_check | at end | any bit
//     TC05-C3 | 9.2 | each end | output padding bytes = 0 | tc_check | at end | nonzero
//     TC05-C4 | REQ-FUNC-007, OP-006 | GMAC end | no output (out_empty=1), tag = model | tc_check | at end | output
//     TC05-C5 | REQ-FUNC-008, TEST-002 | KAT records | C and T equal the NIST values | tc_check | at end | differs
//     TC05-C6 | REQ-ERR-001 | each end | DONE, no error event, code 0 | tc_check | at end | error
//   Seed/replay  : +SEED=<n> (path choice, burst lengths, padding garbage); +TEST=TC-05
// =================================================================================================
task automatic tc05();
  int nbad1, nbad2, nbad3, nbad4, nbad5, nbad6, path, beat, nopad;
  tc_begin("TC-05", 5);
  tc_skip_if(C_GCM_EN == 0, "GCM not built (PARA_AES_GCM_EN = 0)");
  if (tc_skip != "") begin tc_end(); return; end
  load_vectors("TC-05");
  set_pin(1'b0);
  sw_enable((10'h1 << EV_DONE) | EV_ERRS);
  nbad1 = 0; nbad2 = 0; nbad3 = 0; nbad4 = 0; nbad5 = 0; nbad6 = 0;
  for (int r = 0; r < v_nrec; r++) begin
    load_msg(r);
    if (C_AXI == 1) begin
      case (r % 4)
        0: path = PATH_AXI_INCR;
        1: path = PATH_AXI_FIXED;
        2: path = PATH_AXI_MIX;
        default: path = PATH_PIO;
      endcase
    end else path = PATH_PIO;
    beat = path_beat(path);
    if (m_ksz == 0)
      for (int k = 4; k < 8; k++) apb_wr(A_KEY + 4 * k, rnd32());   // ignored for AES-128
    run_msg(path, 0, 0, 1'b1, 0, 0);
    nopad = (m_dlen > 0) ? cmp_out(0, 0, m_dlen, beat, 1'b0) : 0;
    if (!run_ok || (nopad != 0)) nbad1++;
    if (!(tag_lead_ok(tbits(m_tlc)) && tag_full_ok())) nbad2++;
    if (r_out_bad != nopad) nbad3++;
    if ((m_dlen == 0) && !(r_fifo[FIFO_OUT_EMPTY] && tag_full_ok())) nbad4++;
    if ((r < 8) && !(tag_full_ok() && (nopad == 0))) nbad5++;
    if (!raw(EV_DONE) || ((r_raw[9:0] & EV_ERRS) != 0) || (r_err[3:0] != ERRC_NONE)) nbad6++;
  end
  tc_check("TC05-C1", (nbad1 == 0) && (v_nrec == 56), $sformatf("ciphertext = model (%0d bad)", nbad1));
  tc_check("TC05-C2", nbad2 == 0, $sformatf("tag = model (%0d bad)", nbad2));
  tc_check("TC05-C3", nbad3 == 0, $sformatf("output padding reads 0 (%0d bad)", nbad3));
  tc_check("TC05-C4", nbad4 == 0, $sformatf("GMAC: no output and correct tag (%0d bad)", nbad4));
  tc_check("TC05-C5", nbad5 == 0, $sformatf("NIST test cases 1-4, 13-16 (%0d bad)", nbad5));
  tc_check("TC05-C6", nbad6 == 0, $sformatf("DONE without error event (%0d bad)", nbad6));
  tc_end();
endtask

// =================================================================================================
// TC-06  Suspend, urgent message and resume (DEC-023 Example 4) with CTX_SWITCH_DONE
//   Priority     : P1
//   Objective    : a suspend after 32 AAD and 48 payload bytes reports the consumed counts, frees the
//                  sequencer for an urgent message with another key, and the resumed message ends
//                  with the output and tag of an uninterrupted message; the slot is released.
//   Requirements : REQ-FUNC-010, OP-007, OP-008, DEC-023; TEST-010, TEST-035
//   Config/state : PARA_GCM_CTX_NUM > 0 (CFG-FULL); reset.
//   SW sequence  : S04/S05 M1 (aad 32, len 96, ctx_id 0), S07, move AAD + 48 bytes and read 48
//                  output bytes; S09 ctrl.suspend; wait cswd; read cons_a/d, sts; urgent M2 S04..S11
//                  (new key); cfg.ctx_id 0, ctrl.resume; move the remaining 48 bytes; S10, S11.
//   Stimulus     : sequencer starved in PAY when the suspend arrives (deterministic boundary).
//   Failure mode : wrong counts, context lost or corrupted by the urgent message, slot not freed.
//   Method       : model compare of the concatenated output and tag.
//   Checks       :
//     TC06-C1 | DEC-023 Ex.4 | cswd after suspend | cons_a=32, cons_d=48 | tc_check | 400 polls | differs
//     TC06-C2 | REQ-FUNC-010 | cswd | ctx_vld bit 0=1, busy=0, ctrl.suspend=0 | tc_check | at event | differs
//     TC06-C3 | REQ-FUNC-002 | urgent end | output and tag = model | tc_check | 4000 polls | differs
//     TC06-C4 | REQ-FUNC-010 | resumed end | 96 output bytes and tag = model | tc_check | 4000 polls | differs
//     TC06-C5 | DEC-023 | after resume | ctx_vld bit 0=0 | tc_check | at end | still 1
//     TC06-C6 | 6.4 CTX_SWITCH_DONE | resume finished | cswd raw set again | tc_check | at end | not set
//   Seed/replay  : +SEED=<n>; +TEST=TC-06
// =================================================================================================
task automatic tc06();
  bit ok, ev, first_ok;
  logic [31:0] ca, cd, v;
  int path, beat;
  tc_begin("TC-06", 5);
  tc_skip_if(!C_HAS_SUSP, "suspend/resume not built (PARA_GCM_CTX_NUM = 0, FEAT-013)");
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
  tc_check("TC06-C1", ok && ev && (ca == 32'd32) && (cd == 32'd48),
           $sformatf("consumed counts after suspend: cons_a %0d, cons_d %0d", ca, cd));
  tc_check("TC06-C2", r_sts[16] && !r_sts[STS_BUSY] && !r_ctrl[3],
           "slot 0 valid, busy 0, suspend bit cleared");
  // urgent message with another key
  load_msg(1);
  run_msg(path, 0, 0, 1'b1, 0, 0);
  tc_check("TC06-C3", run_ok && (r_out_bad == 0) && tag_full_ok(), "urgent message correct");
  // resume slot 0 and send the remaining 48 payload bytes
  load_msg(0);
  for (int i = 0; i < 48; i++) rx_b[i] = 8'h00;
  do_resume(0, path, 0);
  build_tx(32, 0, 48, 48, beat);
  move_part(path, 48 / beat, 48 / beat, ok);
  wait_event(10'h1 << EV_DONE | EV_ERRS, 4000, ev);
  read_results();
  sh_msg_active = 1'b0;
  tc_check("TC06-C4", first_ok && ok && ev && (cmp_out(48, 48, 48, beat, 1'b0) == 0) &&
           tag_full_ok(), "both halves of the output and the tag equal the uninterrupted model");
  tc_check("TC06-C5", !r_sts[16], "slot 0 released after resume (ctx_vld bit 0 = 0)");
  tc_check("TC06-C6", raw(EV_CSWD), "CTX_SWITCH_DONE raised for the resume");
  tc_end();
endtask

// =================================================================================================
// TC-07  Two slots: suspend in AAD and in payload, interleaved resumes, free, invalid resume, range
//   Priority     : P2
//   Objective    : two suspended contexts coexist; each resumes to the uninterrupted result; free
//                  clears a slot; resuming a free slot is PROTO_ERR; ctx_id out of range is CFG_ERR.
//   Requirements : REQ-FUNC-010, REQ-ERR-001, ERR-001, ERR-005, 9.3 (ctx id); TEST-010, TEST-026
//   Config/state : PARA_GCM_CTX_NUM >= 2; reset.
//   SW sequence  : M1 ctx 0 (aad 64, len 48): push 32 AAD, suspend; M2 ctx 1 (decrypt, aad 16,
//                  len 128): push AAD + 48, read 48, suspend; resume 1, finish; resume 0, finish;
//                  M1 again to ctx 0 and suspend; ctrl.free ctx 0; resume ctx 0; start with ctx 2.
//   Stimulus     : starved sequencer at each suspend.
//   Failure mode : slot cross-talk, AAD-phase suspend counts, free/resume validity.
//   Method       : model compare; register reads.
//   Checks       :
//     TC07-C1 | REQ-FUNC-010 | AAD suspend | cons_a=32, cons_d=0 | tc_check | 400 polls | differs
//     TC07-C2 | REQ-FUNC-010 | payload suspend | cons_a=16, cons_d=48, ctx_vld=0b11 | tc_check | 400 polls | differs
//     TC07-C3 | REQ-FUNC-010 | slot 1 resumed end | M2 plaintext and tag_ok = model | tc_check | 4000 polls | differs
//     TC07-C4 | REQ-FUNC-010 | slot 0 resumed end | M1 output and tag = model | tc_check | 4000 polls | differs
//     TC07-C5 | ERR-005, ctrl.free | free then resume | ctx_vld bit 0 = 0; PROTO_ERR code 5 | tc_check | 60 polls | differs
//     TC07-C6 | ERR-001, 9.3 | start with ctx_id 2 | CFG_ERR code 1 | tc_check | 60 polls | none
//     TC07-C7 | REQ-ERR-001 | next legal message | output and tag = model | tc_check | 4000 polls | differs
//   Seed/replay  : +SEED=<n>; +TEST=TC-07
// =================================================================================================
task automatic tc07();
  bit ok, ev, seen;
  logic [31:0] ca, cd, v;
  int path, beat, gp2;
  tc_begin("TC-07", 5);
  tc_skip_if(C_CTX_NUM < 2 || !C_HAS_SUSP, "fewer than two context slots (PARA_GCM_CTX_NUM < 2)");
  if (tc_skip != "") begin tc_end(); return; end
  load_vectors("TC-07");
  path = (C_AXI == 1) ? PATH_AXI_INCR : PATH_PIO;
  beat = path_beat(path);
  gp2 = C_HAS_PC ? 0 : 1;
  set_pin(1'b0);
  sw_enable((10'h1 << EV_DONE) | (10'h1 << EV_CSWD) | EV_ERRS);
  // M1 to slot 0, suspended in the AAD phase
  load_msg(0);
  start_only(path, 0, 1'b1, 0);
  build_tx(0, 32, 0, 0, beat);
  move_part(path, 0, 0, ok);
  repeat (300) @(posedge clk_bus);
  do_suspend(ev, ca, cd);
  sh_msg_active = 1'b0;
  tc_check("TC07-C1", ok && ev && (ca == 32'd32) && (cd == 32'd0),
           $sformatf("AAD-phase suspend: cons_a %0d cons_d %0d", ca, cd));
  // M2 to slot 1, suspended in the payload phase
  load_msg(1);
  start_only(path, gp2, 1'b1, 1);
  build_tx(0, 16, 0, 48, beat);
  move_part(path, 0, (gp2 == 0) ? 48 / beat : 0, ok);
  repeat (100) @(posedge clk_bus);
  do_suspend(ev, ca, cd);
  sh_msg_active = 1'b0; sh_pass1_active = 1'b0;
  tc_check("TC07-C2", ok && ev && (ca == 32'd16) && (cd == 32'd48) && (r_sts[17:16] == 2'b11),
           $sformatf("payload suspend: cons_a %0d cons_d %0d ctx_vld %0b", ca, cd, r_sts[19:16]));
  // resume slot 1
  do_resume(1, path, gp2);
  sh_pass1_active = (gp2 == 1);
  build_tx(16, 0, 48, 80, beat);
  move_part(path, 48 / beat, (gp2 == 0) ? 80 / beat : 0, ok);
  wait_event(10'h1 << EV_DONE | EV_ERRS, 4000, ev);
  read_results();
  sh_msg_active = 1'b0; sh_pass1_active = 1'b0;
  tc_check("TC07-C3", ok && ev && r_sts[STS_TAG_OK] &&
           ((gp2 == 1) || (cmp_out(0, 0, 128, beat, 1'b1) == 0)),
           "slot 1 resumed: plaintext = model and tag_ok = 1");
  // resume slot 0
  load_msg(0);
  do_resume(0, path, 0);
  build_tx(32, 32, 0, 48, beat);
  move_part(path, 0, 48 / beat, ok);
  wait_event(10'h1 << EV_DONE | EV_ERRS, 4000, ev);
  read_results();
  sh_msg_active = 1'b0;
  tc_check("TC07-C4", ok && ev && (cmp_out(0, 0, 48, beat, 1'b1) == 0) && tag_full_ok(),
           "slot 0 resumed from the AAD phase: output and tag = model");
  // free a valid slot, then resume it
  start_only(path, 0, 1'b0, 0);
  build_tx(0, 32, 0, 0, beat);
  move_part(path, 0, 0, ok);
  repeat (300) @(posedge clk_bus);
  do_suspend(ev, ca, cd);
  sh_msg_active = 1'b0;
  apb_wr(A_CFG, cfg_word(m_mode, m_dec, m_ksz, 0, path_dsrc(path), 0, m_seg, m_tlc, 0));
  cmd(CTRL_FREE);
  // The spec gives no latency for free (one core clock per context word plus the crossing): poll
  // aesgcm_sts.ctx_vld of the slot until it reads 0 before resuming it.
  apb_poll(A_STS, 32'h0001_0000, 32'h0, 400, v, ok);
  clear_events();
  cmd(CTRL_RESUME);
  wait_event(10'h1 << EV_PERR, 60, seen);
  read_results();
  tc_check("TC07-C5", ev && !v[16] && seen && (r_err[3:0] == ERRC_PROTO),
           "free clears slot 0; resume of the free slot gives PROTO_ERR, code 5");
  // context id out of range
  load_msg(2);
  sw_program(0, 0, path_dsrc(path), -1, 1'b1, 1'b1, 2);
  clear_events(); sw_start();
  wait_event(10'h1 << EV_CERR, 60, seen);
  read_results(); cmd(32'h0); sh_msg_active = 1'b0;
  tc_check("TC07-C6", seen && (r_err[3:0] == ERRC_CFG), "ctx_id 2 with two slots: CFG_ERR, code 1");
  run_msg(path, 0, 0, 1'b0, 0, 0);
  tc_check("TC07-C7", run_ok && (r_out_bad == 0) && tag_full_ok() && (r_err[3:0] == ERRC_NONE),
           "next legal message correct");
  tc_end();
endtask

// =================================================================================================
// TC-08  Abort during the payload, key retention, write-only keys, zeroize and the key_new rule
//   Priority     : P1
//   Objective    : abort (ctrl = 0x102, DEC-022 Ex. 3) ends the message within the bound, flushes both
//                  FIFOs and keeps the key so the next message with the same key needs no key_new;
//                  key registers read 0; zeroize clears key material and forbids a GCM start until a
//                  new key_new; zeroized is reported until the next start.
//   Requirements : REQ-FUNC-013, REQ-SEC-001, REQ-REG-002, REQ-ERR-001, PERF-004, DEC-022;
//                  TEST-012, TEST-021, TEST-028, TEST-034, ERR-001
//   Config/state : any GCM build; reset.
//   SW sequence  : M1 S04..S07, move AAD + part of the payload without reading the output; ctrl =
//                  en|abort; poll ctrl.abort and sts.busy; read fifosts, sts.key_ld; M2 (same key)
//                  without key words and key_new; read key registers; ctrl.zeroize; poll
//                  sts.zeroized; M2 start (no key_new); M3 with key_new.
//   Stimulus     : output FIFO left holding data at the abort.
//   Failure mode : abort hangs or keeps stale data, abort clears the key, key readable, zeroize
//                  incomplete, GCM start accepted with a zeroized key.
//   Method       : model compare; latency against PERF-004 + crossing budget (13.2).
//   Checks       :
//     TC08-C1 | REQ-FUNC-013, PERF-004, WF-023 | ctrl.abort written | abort bit and busy read 0 within 64 core clk + 2 X_c | tc_check | cmd_bound_bus | later
//     TC08-C2 | REQ-FUNC-013 | after abort | out_empty=1, in_full=0 | tc_check | at poll | data left
//     TC08-C3 | REQ-FUNC-013, 5.3 step 8 | M2 without key_new | key_ld=1; output and tag = model | tc_check | 4000 polls | differs
//     TC08-C4 | REQ-REG-002 | after M2 | aesgcm_key_0..7 read 0 (APB-27) | tc_check | at read | nonzero
//     TC08-C5 | REQ-SEC-001 | ctrl.zeroize | zeroized=1, key_ld=0, ctx_vld=0 within bound | tc_check | cmd_bound_bus | later
//     TC08-C6 | ERR-001 | GCM start after zeroize, no key_new | CFG_ERR code 1 | tc_check | 60 polls | accepted
//     TC08-C7 | REQ-SEC-001 | M3 with key_new | output/tag = model; zeroized=0 after start | tc_check | 4000 polls | differs
//   Seed/replay  : +SEED=<n>; +TEST=TC-08
// =================================================================================================
task automatic tc08();
  bit ok, b, z, seen;
  logic [31:0] v, fs;
  int path, beat, push_bytes, t0, lat;
  tc_begin("TC-08", 5);
  tc_skip_if(C_GCM_EN == 0, "GCM not built (PARA_AES_GCM_EN = 0)");
  if (tc_skip != "") begin tc_end(); return; end
  load_vectors("TC-08");
  path = (C_AXI == 1) ? PATH_AXI_INCR : PATH_PIO;
  beat = path_beat(path);
  set_pin(1'b0);
  sw_enable((10'h1 << EV_DONE) | EV_ERRS);
  load_msg(0);
  start_only(path, 0, 1'b1, 0);
  push_bytes = C_FIFO_BLOCKS * 16 / 2;
  if (push_bytes > 512) push_bytes = 512;
  build_tx(0, 16, 0, push_bytes, beat);
  move_part(path, 0, 0, ok);
  repeat (200) @(posedge clk_bus);
  apb_rd(A_FIFOSTS, fs);
  t0 = cyc_bus;
  cmd(CTRL_ABORT);
  apb_poll(A_CTRL, CTRL_ABORT, 32'h0, 200, v, b);
  apb_poll(A_STS, 32'h1, 32'h0, 50, v, z);
  lat = cyc_bus - t0;
  sh_msg_active = 1'b0;
  tc_check("TC08-C1", ok && b && z && (lat <= cmd_bound_bus()),
           $sformatf("abort completed in %0d bus clocks (bound %0d), data before abort %0s", lat,
                     cmd_bound_bus(), fs[FIFO_OUT_EMPTY] ? "absent" : "present"));
  apb_rd(A_FIFOSTS, fs);
  tc_check("TC08-C2", fs[FIFO_OUT_EMPTY] && !fs[FIFO_IN_FULL], "FIFOs flushed by the abort");
  apb_rd(A_STS, v);
  load_msg(1);
  run_msg(path, 0, 0, 1'b0, 0, 0);
  tc_check("TC08-C3", v[STS_KEY_LD] && run_ok && (r_out_bad == 0) && tag_full_ok(),
           "key kept by the abort: next message with the same key correct without key_new");
  keys_read_zero(z);
  tc_check("TC08-C4", z, "write-only key registers read 0");
  t0 = cyc_bus;
  cmd(CTRL_ZEROIZE);
  apb_poll(A_STS, 32'h8, 32'h8, 200, v, b);
  lat = cyc_bus - t0;
  apb_rd(A_CTRL, r_ctrl);
  tc_check("TC08-C5", b && !v[STS_KEY_LD] && (v[19:16] == 4'h0) && !r_ctrl[2] &&
           (lat <= cmd_bound_bus()), $sformatf("zeroize done in %0d bus clocks: zeroized=1, key_ld=0",
                                              lat));
  sw_program(0, 0, path_dsrc(path), -1, 1'b0, 1'b0, 0);
  clear_events(); sw_start();
  wait_event(10'h1 << EV_CERR, 60, seen);
  read_results(); cmd(32'h0); sh_msg_active = 1'b0;
  tc_check("TC08-C6", seen && (r_err[3:0] == ERRC_CFG), "GCM start after zeroize without key_new: CFG_ERR");
  load_msg(2);
  run_msg(path, 0, 0, 1'b1, 0, 0);
  tc_check("TC08-C7", run_ok && (r_out_bad == 0) && tag_full_ok() && !r_sts[STS_ZEROIZED],
           "new key after zeroize: message correct, zeroized cleared by the start");
  tc_end();
endtask
