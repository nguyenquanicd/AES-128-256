// -------------------------------------------------------------------------------------------------
// Project      : AES-GCM Accelerator - acceptance simulation testbench
// File         : tb_aesgcm_lib.svh (included inside module tb_aesgcm_top)
// Description  : Shared harness: deterministic PRNG, per-testcase check bookkeeping (R-095 check IDs),
//                vector loading ($readmemh of vectors/<ID>.hex written by gen_tb_vectors.py from the
//                independent models), message programming by the software sequence of spec 11.2
//                (S02 to S13), stream formatting of spec 9.2, data movement through PIO, AXI4 or the
//                DMA model, and result collection. Expected values always come from the vector file
//                (model), never from the DUT.
// -------------------------------------------------------------------------------------------------

// ------------------------------------------------------------------------------ PRNG (xorshift32)
function automatic int unsigned rnd32();
  prng_state = prng_state ^ (prng_state << 13);
  prng_state = prng_state ^ (prng_state >> 17);
  prng_state = prng_state ^ (prng_state << 5);
  return prng_state;
endfunction

function automatic int unsigned rnd_range(input int unsigned lo, input int unsigned hi);
  if (hi <= lo) return lo;
  return lo + (rnd32() % (hi - lo + 1));
endfunction

// ------------------------------------------------------------------------------ test bookkeeping
task automatic tc_begin(input string id, input int min_checks);
  tc_id = id; tc_checks = 0; tc_fails = 0; tc_min = min_checks; tc_skip = ""; tc_nids = 0;
  tc_errors = 0; apb_unexp_err = 0; apb_hang = 0; axi_hang = 0; dma_err = 0;
  $display("");
  $display("==== TEST %0s (seed %0d, %0s) ====", id, seed, `TB_CFG_NAME);
endtask

// One executable check (R-095): id, condition, description of the expected observation.
task automatic tc_check(input string cid, input bit cond, input string what);
  bit seen;
  tc_checks++;
  seen = 1'b0;
  for (int i = 0; i < tc_nids; i++) if (tc_ids_seen[i] == cid) seen = 1'b1;
  if (!seen && (tc_nids < 64)) begin tc_ids_seen[tc_nids] = cid; tc_nids++; end
  if (cond) $display("CHECK %0s PASS: %0s", cid, what);
  else begin
    tc_fails++;
    $display("CHECK %0s FAIL @%0t: %0s", cid, $time, what);
  end
endtask

task automatic tc_skip_if(input bit cond, input string reason);
  if (cond && (tc_skip == "")) tc_skip = reason;
endtask

task automatic tc_end();
  string verd, note;
  int harness;
  harness = tc_errors + apb_unexp_err + apb_hang + axi_hang + dma_err;
  if (tc_skip != "") begin
    verd = "SKIP"; note = tc_skip;
  end else if ((tc_fails == 0) && (harness == 0) && (tc_nids >= tc_min) && (tc_checks > 0)) begin
    verd = "PASS"; note = $sformatf("%0d checks, %0d check IDs", tc_checks, tc_nids);
  end else begin
    verd = "FAIL";
    note = $sformatf("%0d failed checks, %0d harness errors, %0d of %0d required check IDs",
                     tc_fails, harness, tc_nids, tc_min);
  end
  $display("==== RESULT %0s: %0s (%0s) ====", tc_id, verd, note);
  if (res_n < MAXT) begin
    res_id[res_n] = tc_id; res_verd[res_n] = verd; res_note[res_n] = note; res_n++;
  end
endtask

// ------------------------------------------------------------------------------ vectors
task automatic load_vectors(input string id);
  string fn;
  int off;
  for (int i = 0; i < VMEM_WORDS; i++) vmem[i] = 32'h0;
  fn = {vec_dir, "/", id, ".hex"};
  $readmemh(fn, vmem);
  v_nrec = int'(vmem[0]);
  off = 1;
  for (int r = 0; (r < v_nrec) && (r < 256); r++) begin
    if (vmem[off] != 32'hA5C3_0001) begin
      $display("TB-ERROR: %0s record %0d: bad magic at word %0d", fn, r, off);
      v_nrec = r;
      tc_errors++;
      break;
    end
    v_off[r] = off;
    off = off + int'(vmem[off + 1]);
  end
  if (v_nrec == 0) $display("TB-WARN: %0s holds no record", fn);
endtask

function automatic int tbits(input int code);
  case (code)
    0: return 128; 1: return 120; 2: return 112; 3: return 104; 4: return 96;
    default: return 128;
  endcase
endfunction

task automatic load_msg(input int r);
  int o, p;
  if (r >= v_nrec) begin
    $display("TB-ERROR: record %0d not present in the vector file of %0s", r, tc_id);
    tc_errors++;
    return;
  end
  o = v_off[r];
  m_mode = int'(vmem[o + 2]); m_dec = int'(vmem[o + 3]); m_ksz = int'(vmem[o + 4]);
  m_tlc = int'(vmem[o + 5]); m_seg = int'(vmem[o + 6]); m_aadlen = int'(vmem[o + 7]);
  m_dlen = int'(vmem[o + 8]); m_expok = int'(vmem[o + 9]); m_kind = int'(vmem[o + 10]);
  m_action = int'(vmem[o + 11]);
  for (int k = 0; k < 8; k++) m_key[k]    = vmem[o + 12 + k];
  for (int k = 0; k < 4; k++) m_iv[k]     = vmem[o + 20 + k];
  for (int k = 0; k < 4; k++) m_tagin[k]  = vmem[o + 24 + k];
  for (int k = 0; k < 4; k++) m_tagexp[k] = vmem[o + 28 + k];
  p = o + 32;
  for (int i = 0; i < m_aadlen; i++) m_aad[i] = vmem[p + i / 4][8 * (i % 4) +: 8];
  p = p + (m_aadlen + 3) / 4;
  for (int i = 0; i < m_dlen; i++) m_in[i] = vmem[p + i / 4][8 * (i % 4) +: 8];
  p = p + (m_dlen + 3) / 4;
  for (int i = 0; i < m_dlen; i++) m_exp[i] = vmem[p + i / 4][8 * (i % 4) +: 8];
endtask

// ------------------------------------------------------------------------------ streams
function automatic int ceil_div(input int a, input int b);
  return (a + b - 1) / b;
endfunction

// Input stream of spec 9.2: AAD [aad_from, aad_from+aad_n) padded with random (ignored) bytes to
// a whole beat, then payload [pay_from, pay_from+pay_n) padded likewise.
task automatic build_tx(input int aad_from, input int aad_n, input int pay_from, input int pay_n,
                        input int beat);
  int p;
  p = 0;
  for (int i = 0; i < aad_n; i++) begin tx_b[p] = m_aad[aad_from + i]; p++; end
  while ((p % beat) != 0) begin tx_b[p] = 8'(rnd32()); p++; end
  for (int i = 0; i < pay_n; i++) begin tx_b[p] = m_in[pay_from + i]; p++; end
  while ((p % beat) != 0) begin tx_b[p] = 8'(rnd32()); p++; end
  tx_n = p;
endtask

// Compare rx_b[rx_from ...] with m_exp[exp_from, exp_from+n); the bytes after n up to the beat end
// must read 0 (spec 9.2: output padding reads as 0). Returns the number of mismatching bytes.
function automatic int cmp_out(input int rx_from, input int exp_from, input int n, input int beat,
                               input bit check_pad);
  int bad;
  int padn;
  bad = 0;
  for (int i = 0; i < n; i++)
    if (rx_b[rx_from + i] !== m_exp[exp_from + i]) begin
      if (bad < 4) $display("  out byte %0d: got %02h exp %02h", exp_from + i, rx_b[rx_from + i],
                            m_exp[exp_from + i]);
      bad++;
    end
  if (check_pad) begin
    padn = ((n % beat) == 0) ? 0 : (beat - (n % beat));
    for (int i = 0; i < padn; i++)
      if (rx_b[rx_from + n + i] !== 8'h00) begin
        if (bad < 4) $display("  output padding byte %0d = %02h (expected 00)", n + i,
                              rx_b[rx_from + n + i]);
        bad++;
      end
  end
  return bad;
endfunction

// ------------------------------------------------------------------------------ results
// Leading t bits of aesgcm_tagout equal the model tag (tag byte 0 = bits [7:0] of word 0).
function automatic bit tag_lead_ok(input int t);
  for (int b = 0; b < t / 8; b++)
    if (r_tag[b / 4][8 * (b % 4) +: 8] !== m_tagexp[b / 4][8 * (b % 4) +: 8]) return 1'b0;
  return 1'b1;
endfunction

function automatic bit tag_full_ok();
  for (int k = 0; k < 4; k++) if (r_tag[k] !== m_tagexp[k]) return 1'b0;
  return 1'b1;
endfunction

task automatic read_results();
  apb_rd(A_IRQ_RAW, r_raw);
  apb_rd(A_STS, r_sts);
  apb_rd(A_ERR_CODE, r_err);
  apb_rd(A_FAILCNT, r_fail);
  apb_rd(A_FIFOSTS, r_fifo);
  for (int k = 0; k < 4; k++) apb_rd(A_TAGOUT + 4 * k, r_tag[k]);
endtask

// ------------------------------------------------------------------------------ programming
// Software sequence of spec 11.2. Shadows for the assertion module are set here.
function automatic int path_dsrc(input int path);
  return ((path == PATH_PIO) || (path == PATH_DMA_PIO)) ? DSRC_PIO : DSRC_AXI;
endfunction
function automatic int path_beat(input int path);
  return (path_dsrc(path) == DSRC_PIO) ? C_BEAT_PIO : C_BEAT_AXI;
endfunction
// Default data path of the build: AXI4 window when present, PIO otherwise (spec 6.3.2, 6.3.3).
function automatic int dflt_path();
  return (C_AXI == 1) ? PATH_AXI_MIX : PATH_PIO;
endfunction

task automatic sw_enable(input logic [9:0] irq_en);
  apb_wr(A_CTRL, CTRL_EN);                 // S02
  apb_wr(A_IRQ_EN, {22'h0, irq_en});
endtask

task automatic clear_events();
  apb_wr(A_IRQ_RAW, {22'h0, EV_ALL});      // S13 (w1c)
endtask

// key_new: S04 (aesgcm_cfg is written before so that the latched tag length and key size are the
// ones of the message, open question Q-03).
task automatic sw_key_new();
  logic [31:0] v;
  bit ok;
  apb_wr(A_CTRL, CTRL_EN | CTRL_KEY_NEW);
  apb_poll(A_CTRL, CTRL_KEY_NEW, 32'h0, 50, v, ok);
  if (!ok) begin tc_errors++; $display("TB-ERROR: aesgcm_ctrl.key_new not cleared by hardware"); end
endtask

// Program the current message (S04, S05). gpass: 0, 1, 2. aad_ovr < 0 keeps the record length.
task automatic sw_program(input int gpass, input int ksrc, input int dsrc, input int aad_ovr,
                          input bit write_key, input bit key_new, input int ctx);
  int mode, seg, tlc;
  mode = m_mode; seg = m_seg; tlc = m_tlc;
  if (m_action == 2) mode = 6;
  if (m_action == 4) seg = 9;
  if (m_action == 5) tlc = 5;
  if (m_action == 6) gpass = 3;
  apb_wr(A_CFG, cfg_word(mode, m_dec, m_ksz, ksrc, dsrc, gpass, seg, tlc, ctx));
  apb_wr(A_AADLEN, (aad_ovr >= 0) ? aad_ovr : ((m_action == 3) ? 16 : m_aadlen));
  apb_wr(A_DATALEN, m_dlen);
  for (int k = 0; k < 4; k++) apb_wr(A_IV + 4 * k, m_iv[k]);
  for (int k = 0; k < 4; k++) apb_wr(A_TAGIN + 4 * k, m_tagin[k]);
  if (write_key && (ksrc == 0))
    for (int k = 0; k < ((m_ksz == 1) ? 8 : 4); k++) apb_wr(A_KEY + 4 * k, m_key[k]);
  if (key_new) sw_key_new();
endtask

task automatic sw_start();
  r_t0_bus  = cyc_bus;
  r_t0_core = cyc_core;
  sh_msg_active = 1'b1;
  apb_wr(A_CTRL, CTRL_EN | CTRL_START);     // S07
endtask

// Wait until one of the bits of mask is set in aesgcm_irq_raw (S10), bounded by max_polls reads.
// Records the bus/core clocks from the start write to the first observation.
task automatic wait_event(input logic [9:0] mask, input int max_polls, output bit ok);
  logic [31:0] v;
  ok = 1'b0;
  for (int i = 0; i < max_polls; i++) begin
    apb_rd(A_IRQ_RAW, v);
    if ((v[9:0] & mask) != 10'h0) begin ok = 1'b1; break; end
  end
  r_lat_bus  = cyc_bus - r_t0_bus;
  r_lat_core = cyc_core - r_t0_core;
  if (ok) repeat (20) @(posedge clk_bus);   // let simultaneous causes of one report settle
  r_timeout = !ok;
endtask

// ------------------------------------------------------------------------------ data movement
// Move the whole input stream tx_b and collect out_beats output beats into rx_b.
task automatic move_data(input int path, input int out_beats, input int in_bcode,
                         input int out_bcode, output bit ok);
  int beat, in_beats;
  bit ok_w, ok_r;
  beat = path_beat(path);
  in_beats = tx_n / beat;
  ok = 1'b1; ok_w = 1'b1; ok_r = 1'b1;
  tb_in_beats_sent = 0; tb_out_beats_got = 0;
  for (int i = 0; i < out_beats * beat; i++) rx_b[i] = 8'hXX;
  case (path)
    PATH_AXI_INCR, PATH_AXI_FIXED, PATH_AXI_MIX: begin
      fork
        axi_push(0, in_beats, (path == PATH_AXI_FIXED) ? 16 : 1 + int'(rnd_range(0, 63)),
                 (path == PATH_AXI_INCR) ? 1 : ((path == PATH_AXI_FIXED) ? 0 : 3), ok_w);
        if (out_beats > 0)
          axi_pull(0, out_beats, (path == PATH_AXI_FIXED) ? 16 : 1 + int'(rnd_range(0, 31)),
                   (path == PATH_AXI_INCR) ? 1 : ((path == PATH_AXI_FIXED) ? 0 : 3), ok_r);
      join
    end
    PATH_PIO: pio_move(in_beats, out_beats, ok);
    PATH_DMA_AXI, PATH_DMA_PIO: begin
      dma_stop = 0;
      fork
        dma_in_channel((path == PATH_DMA_AXI) ? DMA_VIA_AXI : DMA_VIA_PIO, in_bcode, in_beats,
                       beat);
        if (out_beats > 0)
          dma_out_channel((path == PATH_DMA_AXI) ? DMA_VIA_AXI : DMA_VIA_PIO, out_bcode,
                          out_beats, beat);
      join
      ok = (dma_err == 0);
    end
    default: ok = 1'b0;
  endcase
  ok = ok && ok_w && ok_r;
endtask

// PIO transfer polled through aesgcm_fifosts (spec 6.3.3, S08): pop when output data exists,
// push when the input FIFO has room. Bounded.
task automatic pio_move(input int in_words, input int out_words, output bit ok);
  int pushed, popped, idle;
  logic [31:0] fs, w;
  pushed = 0; popped = 0; idle = 0;
  ok = 1'b1;
  while (((pushed < in_words) || (popped < out_words)) && (idle < 20000)) begin
    apb_rd(A_FIFOSTS, fs);
    if ((popped < out_words) && !fs[FIFO_OUT_EMPTY]) begin
      apb_rd(A_PIO_DOUT, w);
      for (int j = 0; j < 4; j++) rx_b[popped * 4 + j] = w[8 * j +: 8];
      popped++; tb_out_beats_got++; idle = 0;
    end else if ((pushed < in_words) && !fs[FIFO_IN_FULL]) begin
      for (int j = 0; j < 4; j++) w[8 * j +: 8] = tx_b[pushed * 4 + j];
      apb_wr(A_PIO_DIN, w);
      pushed++; tb_in_beats_sent++; idle = 0;
    end else idle++;
  end
  if (idle >= 20000) begin
    ok = 1'b0;
    tc_errors++;
    $display("TB-ERROR @%0t: PIO stalled: %0d/%0d words pushed, %0d/%0d popped", $time, pushed,
             in_words, popped, out_words);
  end
endtask

// ------------------------------------------------------------------------------ standard message
// Full message of the current record through path: program, start, move, wait, read results.
//   gpass   0 single pass, 1 policy A pass 1, 2 policy A pass 2 (stream = payload only, AAD 0)
//   ksrc    0 APB key, 1 side-load (the key manager offers the key after km_delay core clocks)
//   key_new write aesgcm_ctrl.key_new (and the key words) before the start
// After the call: r_* hold the results, r_out_bad the output byte mismatches (model compare).
task automatic run_msg(input int path, input int gpass, input int ksrc, input bit key_new,
                       input int in_bcode, input int out_bcode);
  int beat, out_beats, aad_prog;
  bit mv_ok, ev_ok, ka;
  beat = path_beat(path);
  aad_prog = (gpass == 2) ? 0 : m_aadlen;
  if (gpass == 2) build_tx(0, 0, 0, m_dlen, beat);
  else build_tx(0, m_aadlen, 0, m_dlen, beat);
  out_beats = (gpass == 1) ? 0 : ceil_div(m_dlen, beat);
  if ((path == PATH_DMA_AXI) || (path == PATH_DMA_PIO))
    apb_wr(A_DMACFG, {24'h0, out_bcode[2:0], in_bcode[2:0], (out_beats > 0), 1'b1});
  sw_program(gpass, ksrc, path_dsrc(path), aad_prog, key_new, key_new, 0);
  clear_events();
  sh_pass1_active = (gpass == 1);
  sh_side_window  = (ksrc == 1);
  sw_start();
  fork
    if (ksrc == 1) km_offer(km_delay, 4000, ka);
    move_data(path, out_beats, in_bcode, out_bcode, mv_ok);
  join
  wait_event(EV_END, 4000, ev_ok);
  read_results();
  sh_msg_active = 1'b0; sh_pass1_active = 1'b0; sh_side_window = 1'b0;
  if ((path == PATH_DMA_AXI) || (path == PATH_DMA_PIO)) apb_wr(A_DMACFG, 32'h0);
  r_out_bad = (out_beats > 0) ? cmp_out(0, 0, m_dlen, beat, 1'b1) : 0;
  run_ok = mv_ok && ev_ok;
  if (!run_ok) begin
    tc_errors++;
    $display("TB-ERROR @%0t: message did not complete (move %0d, end event %0d)", $time, mv_ok,
             ev_ok);
  end
endtask

// Start a message whose start is expected to be rejected or to end with an error before data.
// Data is offered only when the error event does not come within the first polls.
task automatic run_expect_error(input int path, input int gpass, input logic [9:0] want_ev,
                                output bit seen);
  bit ev, mv;
  int beat;
  beat = path_beat(path);
  sw_program(gpass, 0, path_dsrc(path), (gpass == 2) ? 0 : -1, 1'b1, (m_mode == M_GCM), 0);
  clear_events();
  sw_start();
  wait_event(want_ev, 60, ev);
  if (!ev) begin
    if (gpass == 2) build_tx(0, 0, 0, m_dlen, beat);
    else build_tx(0, m_aadlen, 0, m_dlen, beat);
    move_data(path, 0, 0, 0, mv);
    wait_event(want_ev, 2000, ev);
  end
  seen = ev;
  read_results();
  apb_wr(A_CTRL, CTRL_EN);   // software clears a start bit left by a rejected start (Q-05)
  sh_msg_active = 1'b0;
endtask

// Drain remaining output after an error so that the next message starts clean (bounded).
task automatic idle_cycles(input int n);
  repeat (n) @(posedge clk_bus);
endtask

// Software polls aesgcm_sts until busy = 0.
task automatic wait_not_busy(input int max_polls, output bit ok);
  logic [31:0] v;
  apb_poll(A_STS, 32'h1, 32'h0, max_polls, v, ok);
endtask
