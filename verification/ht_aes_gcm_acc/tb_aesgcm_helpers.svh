// -------------------------------------------------------------------------------------------------
// Project      : AES-GCM Accelerator - acceptance simulation testbench
// File         : tb_aesgcm_helpers.svh (included inside module tb_aesgcm_top)
// Description  : Helpers shared by the testcases: commands, event polling, partial data movement for
//                suspend/resume, policy-dependent decryption, latency bounds of spec 13.2.
// -------------------------------------------------------------------------------------------------

task automatic cmd(input logic [31:0] bits);
  apb_wr(A_CTRL, CTRL_EN | bits);
endtask

task automatic set_pin(input bit v);
  sec_pin = v;                       // static pin, changed only while no message is active
  repeat (8) @(posedge clk_core);
  repeat (8) @(posedge clk_bus);
endtask

// Clear every raw cause (S13) and arm INT-03 (line low within 2 bus clocks) when no new event is
// expected (DMA channels disabled, no message active).
task automatic irq_clear_armed();
  apb_wr(A_IRQ_RAW, {22'h0, EV_ALL});
  sh_int_clear_arm <= 1'b1;
  @(posedge clk_bus);
  sh_int_clear_arm <= 1'b0;
endtask

function automatic bit raw(input int ev);
  return r_raw[ev];
endfunction

// Crossing budget X_c of spec 13.2 expressed in bus clocks (8 core + 8 bus when asynchronous,
// 4 core + 4 bus when synchronous).
function automatic int xc_bus();
  int n;
  n = (C_ASYNC == 1) ? 8 : 4;
  return n + int'((n * t_core_per + t_bus_per - 1) / t_bus_per);
endfunction

function automatic int core_to_bus(input int ncore);
  return int'((ncore * t_core_per + t_bus_per - 1) / t_bus_per);
endfunction

// Bus clocks allowed for an abort or zeroize observed by software: 64 core clocks (PERF-004) plus
// the command and status crossings (2 x X_c) plus the APB polling granularity.
function automatic int cmd_bound_bus();
  return core_to_bus(64) + 2 * xc_bus() + 8 * (apb_gap_max + 4);
endfunction

// PERF-001 bound in core clocks (spec 13.2) without the two crossings.
function automatic int perf001_core(input int ksz, input int aad, input int dlen);
  int l, a, p, n, d, ph, g_a, g_p, g_1, maxp;
  l = (ksz == 1) ? 14 : 10;
  a = ceil_div(aad, 16);
  p = ceil_div(dlen, 16);
  n = C_LANES;
  d = C_DIGIT;
  case (C_ARCH)
    0: begin g_a = a * 128 / d; g_p = p * 128 / d; g_1 = 128 / d; ph = 128 / d; end
    1: begin g_a = a; g_p = p; g_1 = 1; ph = (C_PIPE == 1) ? 1 : 0; end
    default: begin g_a = ceil_div(a, n); g_p = ceil_div(p, n); g_1 = 1; ph = n - 1; end
  endcase
  maxp = (ceil_div(p, n) > g_p) ? ceil_div(p, n) : g_p;
  return 2 + (2 + 2 + l) + ph + g_a + (2 + l + maxp) + g_1 + 3;
endfunction

// Decryption with the policy of the build for a tag-result check: pass 1 when policy A is built
// (no output), policy C otherwise.
task automatic run_dec_check(input int path, input bit key_new);
  if (C_HAS_PA) run_msg(path, 1, 0, key_new, 0, 0);
  else run_msg(path, 0, 0, key_new, 0, 0);
endtask

// Complete authenticated decryption with output: policy C when built, otherwise pass 1 + pass 2.
// out_ok: plaintext equals the model; tag_ok_sts: aesgcm_sts.tag_ok of the last pass.
task automatic run_dec_full(input int path, input bit key_new, input int in_b, input int out_b,
                            output bit out_ok, output bit tag_ok_sts);
  if (C_HAS_PC) begin
    run_msg(path, 0, 0, key_new, in_b, out_b);
  end else begin
    run_msg(path, 1, 0, key_new, in_b, out_b);
    if (r_sts[STS_VER_OK]) run_msg(path, 2, 0, 1'b0, in_b, out_b);
  end
  out_ok = (r_out_bad == 0) && run_ok;
  tag_ok_sts = r_sts[STS_TAG_OK];
endtask

// Push the whole tx_b and pull out_beats into rx_b at beat offset out_dst (bounded).
task automatic move_part(input int path, input int out_dst, input int out_beats, output bit ok);
  int beat, in_beats;
  bit ok_w, ok_r;
  beat = path_beat(path);
  in_beats = tx_n / beat;
  ok_w = 1'b1; ok_r = 1'b1; ok = 1'b1;
  if (path_dsrc(path) == DSRC_AXI) begin
    fork
      if (in_beats > 0) axi_push(0, in_beats, 16, 1, ok_w);
      if (out_beats > 0) axi_pull(out_dst, out_beats, 16, 1, ok_r);
    join
  end else begin
    pio_move_at(in_beats, out_beats, out_dst, ok);
  end
  ok = ok && ok_w && ok_r;
endtask

// PIO move that stores the output words from word offset dst.
task automatic pio_move_at(input int in_words, input int out_words, input int dst, output bit ok);
  int pushed, popped, idle;
  logic [31:0] fs, w;
  pushed = 0; popped = 0; idle = 0;
  ok = 1'b1;
  while (((pushed < in_words) || (popped < out_words)) && (idle < 20000)) begin
    apb_rd(A_FIFOSTS, fs);
    if ((popped < out_words) && !fs[FIFO_OUT_EMPTY]) begin
      apb_rd(A_PIO_DOUT, w);
      for (int j = 0; j < 4; j++) rx_b[(dst + popped) * 4 + j] = w[8 * j +: 8];
      popped++; idle = 0;
    end else if ((pushed < in_words) && !fs[FIFO_IN_FULL]) begin
      for (int j = 0; j < 4; j++) w[8 * j +: 8] = tx_b[pushed * 4 + j];
      apb_wr(A_PIO_DIN, w);
      pushed++; idle = 0;
    end else idle++;
  end
  if (idle >= 20000) begin
    ok = 1'b0; tc_errors++;
    $display("TB-ERROR @%0t: PIO stalled (%0d/%0d pushed, %0d/%0d popped)", $time, pushed,
             in_words, popped, out_words);
  end
endtask

// Suspend the active message and wait for CTX_SWITCH_DONE (S09). Returns the consumed counts.
task automatic do_suspend(output bit ok, output logic [31:0] cons_a, output logic [31:0] cons_d);
  bit ev;
  cmd(CTRL_SUSPEND);
  wait_event(10'h1 << EV_CSWD, 400, ev);
  apb_rd(A_CONS_A, cons_a);
  apb_rd(A_CONS_D, cons_d);
  apb_rd(A_STS, r_sts);
  apb_rd(A_CTRL, r_ctrl);
  ok = ev;
endtask

// Resume slot ctx with the configuration of the current record (S09).
task automatic do_resume(input int ctx, input int path, input int gpass);
  apb_wr(A_CFG, cfg_word(m_mode, m_dec, m_ksz, 0, path_dsrc(path), gpass, m_seg, m_tlc, ctx));
  // The key is not part of the exported image (REQ-SEC-004): in export mode software supplies it
  // again through the key registers before the resume.
  if (C_CTX_MODE == 1)
    for (int k = 0; k < ((m_ksz == 1) ? 8 : 4); k++) apb_wr(A_KEY + 4 * k, m_key[k]);
  clear_events();
  sh_msg_active = 1'b1;
  cmd(CTRL_RESUME);
endtask

// Start the current record (program + start) without moving data.
task automatic start_only(input int path, input int gpass, input bit key_new, input int ctx);
  sw_program(gpass, 0, path_dsrc(path), (gpass == 2) ? 0 : -1, key_new, key_new, ctx);
  clear_events();
  sh_pass1_active = (gpass == 1);
  sw_start();
endtask

// Read the 8 key registers and return 1 when all read 0 (REQ-REG-002).
task automatic keys_read_zero(output bit z);
  logic [31:0] v;
  z = 1'b1;
  for (int k = 0; k < 8; k++) begin
    apb_rd(A_KEY + 4 * k, v);
    if (v != 32'h0) z = 1'b0;
  end
endtask

// Wait n bus clocks and return 1 when o_int_aesgcm equals want at the end.
task automatic int_after(input int n, input bit want, output bit ok);
  repeat (n) @(posedge clk_bus);
  ok = (o_int_aesgcm === want);
endtask
