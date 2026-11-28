# Fault qualification results (rule R-096)

Date: 2026-11-28. Design: RTL of branch feature/aes-gcm-acc (HEAD c22ff1d), testbench of the same commit, seed 1, Verilator 5.053. Result of the campaign defined by `fault_plan.md`.

## Method and setup

- Nothing in `rtl/` or in the testbench sources was edited. The mutant RTL is a disposable copy under the scratch folder
  `C:\Users\PC\AppData\Local\Temp\claude\a4837fe1d531f972\adc08dc1-8fc6-4282-9bd5-6c6e7cc32ee9\scratchpad\faults\`
  (`rtl/` = mutant sources written by `apply_patches.py`, `filelist_mut.f` = copy of `filelist_syn.f` with the 11 patched
  files re-pointed, `patches.json` = every hunk, `logs/` = full logs of this campaign, `logs_build1/` = logs of the first
  build, `obj_*` build folders were deleted after the runs).
- **One mutant build, one fault per run.** To avoid a 25-fold build, all patches were compiled into one mutant of the RTL
  and each is guarded by a run-time plusarg, `+FAULT=<n>` (`integer fsel`, read once in an `initial` block of each patched
  module with `$value$plusargs`). `+FAULT=0` (or no plusarg) is the unmodified design. The "old" and "new" lines below are
  the hunks of that mutant; with `fsel` equal to the fault number the new line is the fault, with any other value the old
  line. Each fault run uses only that fault. Control: `+FAULT=0` passes TC-01..TC-15 on the mutant build
  (`F0_TC-nn_*.log`, all `RESULT ... PASS`, exit 0) and the TC group and FT group also pass
  (`F0_TC_full_grpTC.log`: 15 PASS; `F0_FT_full_grpFT.log`: 13 PASS, 3 SKIP).
- Testbench: the committed testbench copied to `integ/tbcopyfinal` (every task has `/*verilator no_inline_task*/`,
  otherwise identical to HEAD; the uncommitted probe files of the working tree are not included, so the probe-based
  assertions are inapplicable as in the baseline runs).
- Builds (Verilator command of `run_cfg3.sh`, `-Wno-IMPURE --output-split 8000 --output-split-cfuncs 800`, compile with `pcc.py` 3 jobs):
  `full` = CFG-FULL, no defines (all faults except TC-14); `sync` = `+define+TB_CLK_ASYNC=0` (TC-14 faults, `+CLK_RATIO=3_2`).
  Build 1: generation 10 s + compile 141 s (151 s each, two in parallel). Build 2 (with faults 28 to 30 and the variable
  delay of fault 27): about 183 s. Build 2 is the one of the final logs (`logs/`); all runs of the first build were repeated on it
  with the same verdicts, except TC-07 where the first build's attempt 1 is kept as `logs_build1/F9_*` (see row 9).
- Run command (from `verification/ht_aes_gcm_acc`): `obj_<build>/tbsim.exe +TEST=<TC> +SEED=1 +FAULT=<n> +TIMEOUT_MS=5`
  (`+TIMEOUT_MS=5` shortens the testcase watchdog from 50 ms to 5 ms so that a hanging fault ends in minutes; the fault-free
  testcases take at most 0.13 ms of simulated time) and, for the sync build, `+CLK_RATIO=3_2`. No `+DUMP`, no WF test: the
  repository was not written by these runs.
- A run counts as detection only when the named checker prints its `FAIL` line (or the named assertion fails) without a crash or
  a watchdog time-out of the testcase before it; a failure that is only a consequence of a hang (TB-ERROR time-outs, watchdog)
  is recorded INVALID and the fault was refined (at most 3 attempts).
- The plan has 24 rows (12 testcases and their alternatives; the brief said 25).

## Verdict table

| # | Plan row | Fault run(s) | Testcase | Build | Named checker | Observed | Verdict | Date |
|---|---|---|---|---|---|---|---|---|
| 1 | TC-01 | F1 | TC-01 | full | POL-01 / POL-02 (POL-03 needs probes), TC01-C2 | TC01-C2 FAIL @4811927 | **DETECTED** | 2026-11-28 |
| 2 | TC-01 (alt.) | F2 | TC-01 | full | TC01-C9 (no PROTO_ERR) | TC01-C9 PASS (all TC and FT also pass) | **NOT DETECTED** | 2026-11-28 |
| 3 | TC-02 | F3 | TC-02 | full | TC02-C2, TC02-C3 | TC02-C2 FAIL, TC02-C3 FAIL | **DETECTED** | 2026-11-28 |
| 4 | TC-03 | F4 | TC-03 | full | TC03-C2, POL-04 | TC03-C2 FAIL | **DETECTED** | 2026-11-28 |
| 5 | TC-04 | F5 | TC-04 | full | TC04-C5 | TC04-C5 FAIL | **DETECTED** | 2026-11-28 |
| 6 | TC-05 | F6 | TC-05 | full | TC05-C2, TC05-C5 | TC05-C2 FAIL (42 bad), TC05-C5 FAIL | **DETECTED** | 2026-11-28 |
| 7 | TC-05 (alt.) | F7 | TC-05 | full | TC05-C3 | TC05-C3 FAIL (30 bad) | **DETECTED** | 2026-11-28 |
| 8 | TC-06 | F8 | TC-06 | full | TC06-C4 | TC06-C4 FAIL | **DETECTED** | 2026-11-28 |
| 9 | TC-07 | F9, F30 | TC-07 | full | TC07-C3, TC07-C2 | attempt 2: TC07-C3 FAIL | **DETECTED (attempt 2)** | 2026-11-28 |
| 10 | TC-08 | F10 | TC-08 | full | TC08-C3 | TC08-C3 FAIL | **DETECTED** | 2026-11-28 |
| 11 | TC-08 (alt.) | F11 | TC-08 | full | TC08-C5, TC08-C6 | TC08-C5 FAIL, TC08-C6 FAIL | **DETECTED** | 2026-11-28 |
| 12 | TC-09 | F12 | TC-09 | full | TC09-C4, AXI-16 | TC09-C4 FAIL, AXI-16 FAIL | **DETECTED** | 2026-11-28 |
| 13 | TC-09 (alt.) | F13 | TC-09 | full | AXI-14, TC09-C1/C3 | AXI-14 FAIL x5, TC09-C1/C3 FAIL | **DETECTED** | 2026-11-28 |
| 14 | TC-10 | F14 | TC-10 | full | DMA-IN-01 | DMA-IN-01 FAIL (assertion) | **DETECTED** | 2026-11-28 |
| 15 | TC-10 (alt.) | F16, F28 | TC-10 | full | DMA-OUT-12 or TC10-C4 | attempt 2: TC10-C4 FAIL | **DETECTED (attempt 2)** | 2026-11-28 |
| 16 | TC-11 | F17 | TC-11 | full | TC11-C2 | TC11-C2 FAIL | **DETECTED** | 2026-11-28 |
| 17 | TC-11 (alt.) | F18 | TC-11 | full | TC11-C5 | TC11-C5 FAIL | **DETECTED** | 2026-11-28 |
| 18 | TC-12 | F19 | TC-12 | full | TC12-C2, INT-04 | TC12-C2 FAIL, INT-04 FAIL | **DETECTED** | 2026-11-28 |
| 19 | TC-12 (alt.) | F20 | TC-12 | full | TC12-C1 | TC12-C1 FAIL | **DETECTED** | 2026-11-28 |
| 20 | TC-13 | F21, F22 | TC-13 | full | TC13-C3, TC13-C1 | F21: TC13-C3 PASS; F22: TC13-C3 FAIL | **NOT DETECTED (literal fault); DETECTED when the BUS latch also survives** | 2026-11-28 |
| 21 | TC-13 (alt.) | F23 | TC-13 | full | DMA-IN-07, TC13-C2 | DMA-IN-07 FAIL (TC13-C2 PASS) | **DETECTED** | 2026-11-28 |
| 22 | TC-14 | F24, F25 | TC-14 | sync | TC14-C1/C2 | attempt 2: TC14-C1 FAIL, TC14-C2 FAIL | **DETECTED (attempt 2)** | 2026-11-28 |
| 23 | TC-14 (alt.) | F26 | TC-14 | sync | TC14-C4 or TC14-C2 | TC14-C2 FAIL (C4 PASS) | **DETECTED** | 2026-11-28 |
| 24 | TC-15 | F27 | TC-15 | full | TC15-C1/C2 | TC15-C1 PASS (1450000 <= 1882988 ps), C2 PASS | **NOT DETECTED** | 2026-11-28 |

Summary: 24 rows. DETECTED 21 (18 on the first fault attempt, 3 after a refinement: rows 9, 15 and 22). NOT DETECTED 3 (row 2 TC-01 alt., row 20 TC-13 as defined, row 24 TC-15); row 20 is detected when the BUS key-new latch is also kept over the reset (fault 22). No row is left INVALID; no known-bad demonstration was needed because every fault could be injected.

## Per-fault records

### Row 1: TC-01 - DETECTED

- Named detecting checker(s): POL-01 / POL-02 (POL-03 needs probes), TC01-C2
- Date: 2026-11-28

**Fault 1** - pass 1 decrypts into the output FIFO (core pass-1 gating removed, bus output length not forced to 0). Attempt verdict: **DETECTED**
  - Build: `full` (no defines). Run: `obj_full/tbsim.exe +TEST=TC-01 +SEED=1 +FAULT=1 +TIMEOUT_MS=5`
  - Full log: `F1_TC-01_full.log` in the scratch folder `...\scratchpad\faults\logs\`
  - Patch (mutant hunks, file / old / new):
    - `m_aesgcm_seq.sv`
```
- old:
-     assign w_feed_pass1 = w_gcm & (reg_pass == 2'd1);
+ new:
+     assign w_pass1      = w_gcm & (reg_pass == 2'd1);
+     assign w_feed_pass1 = w_pass1 & (fsel != 1);
```
    - `m_aesgcm_seq.sv`
```
- old:
-         if ((reg_fsm_seq_current_state == ENUM_ST_SEQ_AAD) && w_feed_pass1 &&
-             (w_fsm_seq_nxt_state == ENUM_ST_SEQ_PAY))
-           reg_y_aad <= i_gh_y;
+ new:
+         if ((reg_fsm_seq_current_state == ENUM_ST_SEQ_AAD) && w_pass1 &&
+             ((w_fsm_seq_nxt_state == ENUM_ST_SEQ_PAY) || (w_fsm_seq_nxt_state == ENUM_ST_SEQ_PY_CFG)))
+           reg_y_aad <= i_gh_y;
```
    - `m_aesgcm_seq.sv`
```
- old:
-           if (w_feed_pass1) begin
-             reg_ver_ok   <= i_tag_match;
+ new:
+           if (w_pass1) begin
+             reg_ver_ok   <= i_tag_match;
```
    - `m_aesgcm_bus_ctl.sv`
```
- old:
-     assign o_out_data_len    = (w_start_ok & w_gcm & (i_cfg_gcm_pass == 2'd1)) ? 32'd0 : o_in_data_len;
+ new:
+     assign o_out_data_len    = (w_start_ok & w_gcm & (i_cfg_gcm_pass == 2'd1) & (fsel != 1)) ? 32'd0 : o_in_data_len;
```
  - Observed lines:
```
CHECK TC01-C2 FAIL @4811927: pass 1 wrote no output (out_empty=1)
ASSERT FAIL @4851927: DMA-OUT-10 request rises only while a message is active (6.3.4 phase 1)
ASSERT FAIL @4851927: DMA-OUT-11 request rises only while beats remain (6.3.4 phase 1)
==== RESULT TC-01: FAIL (2 failed checks, 0 harness errors, 9 of 5 required check IDs) ====
```

Analysis: TC01-C2 reports FAIL. POL-01 and POL-02 were exercised (775 hits each) but did not fail: in pass 1 the testbench enables no output DMA and reads no data, so neither an output request nor an OKAY read beat appears; the plaintext only sits in the output FIFO, which only TC01-C2 (out_empty) and the probe assertion POL-03 can see. The assertions that did fire are DMA-OUT-10/11 (secondary, not named in the plan).

### Row 2: TC-01 (alt.) - NOT DETECTED

- Named detecting checker(s): TC01-C9 (no PROTO_ERR)
- Date: 2026-11-28

**Fault 2** - key_new does not invalidate the verified context (reg_vc_valid kept). Attempt verdict: **NOT DETECTED**
  - Build: `full` (no defines). Run: `obj_full/tbsim.exe +TEST=TC-01 +SEED=1 +FAULT=2 +TIMEOUT_MS=5`
  - Full log: `F2_TC-01_full.log` in the scratch folder `...\scratchpad\faults\logs\`
  - Patch (mutant hunks, file / old / new):
    - `m_aesgcm_seq.sv`
```
- old:
-           if (w_b_knew || (w_b_pass != 2'd2))
-             reg_vc_valid <= 1'b0;
+ new:
+           if (((fsel != 2) && w_b_knew) || (w_b_pass != 2'd2))
+             reg_vc_valid <= 1'b0;
```
  - Observed lines:
```
CHECK TC01-C9 PASS: pass 2 without a verified context: PROTO_ERR, code 5, no output
==== RESULT TC-01: PASS (12 checks, 9 check IDs) ====
```

Analysis: TC01-C9 issues key_new and pass 2 only after the preceding pass 2 (the modified-ciphertext run, TC01-C7), and a pass 2 already clears the verified context (reg_vc_valid <= 0 in state TAG) and the status ver_ok (cleared at the start of that pass 2), so the pass-2 start is rejected (PROTO_ERR) whether or not key_new invalidates the context. The sequence pass 1 -> key_new -> pass 2 is never exercised. Running the whole TC group and the whole FT group with the fault (F2_TC_full_grpTC.log, F2_FT_full_grpFT.log) also passes: no testcase detects it. Testbench gap: add a pass 1, key_new (same key), pass 2 step before the C9 sequence.

### Row 3: TC-02 - DETECTED

- Named detecting checker(s): TC02-C2, TC02-C3
- Date: 2026-11-28

**Fault 3** - leftmost tag bit (bit 127) inverted in the tag comparison (the forged tag of the vectors flips exactly this bit). Attempt verdict: **DETECTED**
  - Build: `full` (no defines). Run: `obj_full/tbsim.exe +TEST=TC-02 +SEED=1 +FAULT=3 +TIMEOUT_MS=5`
  - Full log: `F3_TC-02_full.log` in the scratch folder `...\scratchpad\faults\logs\`
  - Patch (mutant hunks, file / old / new):
    - `m_aesgcm_tag.sv`
```
- old:
-     assign o_match = (((o_tag ^ i_tag_exp) & w_mask) == '0);
+ new:
+     assign o_match = (((o_tag ^ i_tag_exp ^ ((fsel == 3) ? {1'b1, 127'd0} : 128'd0)) & w_mask) == '0);
```
  - Observed lines:
```
CHECK TC02-C2 FAIL @2771927: forged tag: TAG_FAIL raw, tag_ok=0, err_code 6
CHECK TC02-C3 FAIL @2771927: aesgcm_failcnt incremented to 1
CHECK TC02-C6 FAIL @5161927: next packet: output = model, tag_ok=1, code cleared, failcnt unchanged
```
### Row 4: TC-03 - DETECTED

- Named detecting checker(s): TC03-C2, POL-04
- Date: 2026-11-28

**Fault 4** - i_sec_only ignored by the legality check (policy C accepted with the pin). Attempt verdict: **DETECTED**
  - Build: `full` (no defines). Run: `obj_full/tbsim.exe +TEST=TC-03 +SEED=1 +FAULT=4 +TIMEOUT_MS=5`
  - Full log: `F4_TC-03_full.log` in the scratch folder `...\scratchpad\faults\logs\`
  - Patch (mutant hunks, file / old / new):
    - `m_aesgcm_bus_ctl.sv`
```
- old:
-             ((PARA_GCM_REL_POLICY == 0) || i_sec_only))
+ new:
+             ((PARA_GCM_REL_POLICY == 0) || (i_sec_only && (fsel != 4))))
```
  - Observed lines:
```
CHECK TC03-C2 FAIL @73791927: policy C with the pin: CFG_ERR, code 1, busy 0
CHECK TC03-C3 FAIL @73791927: no plaintext produced (out_empty=1)
```

Analysis: POL-04 was exercised (7335 hits) but did not fail (the message is accepted but no output beat is read inside its window); TC03-C3 (out_empty) also fails.

### Row 5: TC-04 - DETECTED

- Named detecting checker(s): TC04-C5
- Date: 2026-11-28

**Fault 5** - tag comparison over all 128 bits whatever tag_len. Attempt verdict: **DETECTED**
  - Build: `full` (no defines). Run: `obj_full/tbsim.exe +TEST=TC-04 +SEED=1 +FAULT=5 +TIMEOUT_MS=5`
  - Full log: `F5_TC-04_full.log` in the scratch folder `...\scratchpad\faults\logs\`
  - Patch (mutant hunks, file / old / new):
    - `m_aesgcm_tag.sv`
```
- old:
-     assign w_mask     = {LPARA_BLK_W{1'b1}} << {w_len_code, 3'b000};
+ new:
+     assign w_mask     = (fsel == 5) ? {LPARA_BLK_W{1'b1}} : ({LPARA_BLK_W{1'b1}} << {w_len_code, 3'b000});
```
  - Observed lines:
```
CHECK TC04-C5 FAIL @27181927: a tag differing only after bit t matches (leading t bits compared)
```
### Row 6: TC-05 - DETECTED

- Named detecting checker(s): TC05-C2, TC05-C5
- Date: 2026-11-28

**Fault 6** - GHASH length block with len(A) = 0. Attempt verdict: **DETECTED**
  - Build: `full` (no defines). Run: `obj_full/tbsim.exe +TEST=TC-05 +SEED=1 +FAULT=6 +TIMEOUT_MS=5`
  - Full log: `F6_TC-05_full.log` in the scratch folder `...\scratchpad\faults\logs\`
  - Patch (mutant hunks, file / old / new):
    - `m_aesgcm_seq.sv`
```
- old:
-     assign w_len_blk = {29'd0, reg_aad_tot, 3'd0, 29'd0, reg_dat_tot, 3'd0};
+ new:
+     assign w_len_blk = {29'd0, ((fsel == 6) ? 32'd0 : reg_aad_tot), 3'd0, 29'd0, reg_dat_tot, 3'd0};
```
  - Observed lines:
```
CHECK TC05-C2 FAIL @124721927: tag = model (42 bad)
CHECK TC05-C5 FAIL @124721927: NIST test cases 1-4, 13-16 (2 bad)
CHECK TC05-C4 FAIL @124721927: GMAC: no output and correct tag (5 bad)
```
### Row 7: TC-05 (alt.) - DETECTED

- Named detecting checker(s): TC05-C3
- Date: 2026-11-28

**Fault 7** - output padding of the last partial block carries the keystream (fmt_out entry unmasked, unpack copies the tail bytes). Attempt verdict: **DETECTED**
  - Build: `full` (no defines). Run: `obj_full/tbsim.exe +TEST=TC-05 +SEED=1 +FAULT=7 +TIMEOUT_MS=5`
  - Full log: `F7_TC-05_full.log` in the scratch folder `...\scratchpad\faults\logs\`
  - Patch (mutant hunks, file / old / new):
    - `m_aesgcm_fmt_out.sv`
```
- old:
-     assign o_ent   = {o_last, i_mask, o_data};
+ new:
+     assign o_ent   = {o_last, i_mask, ((fsel == 7) ? i_data : o_data)};
```
    - `m_aesgcm_unpack.sv`
```
- old:
-             w_blk[{~w_src_pos[idx][3:0], 3'b111} -: LPARA_BYTE_W];
-       end
-     end
+ new:
+             w_blk[{~w_src_pos[idx][3:0], 3'b111} -: LPARA_BYTE_W];
+       end
+       if ((fsel == 7) && (reg_rem == 32'(w_take))) begin
+         for (int idx = 0; idx < LPARA_BLK_BYTES; idx++) begin
+           if ((5'(idx) >= (w_fill_base + w_take)) && (5'(idx) < reg_beat_bytes) &&
+               (w_src_pos[idx] < 5'd16))
+             w_beat_new[LPARA_BYTE_W*idx +: LPARA_BYTE_W] =
+               w_blk[{~w_src_pos[idx][3:0], 3'b111} -: LPARA_BYTE_W];
+         end
+       end
+     end
```
  - Observed lines:
```
CHECK TC05-C3 FAIL @124721927: output padding reads 0 (30 bad)
CHECK TC05-C1 PASS: ciphertext = model (0 bad)
output padding byte 1 = c1 (expected 00)
```

Analysis: TC05-C1 (secondary) passes: the ciphertext bytes of the stream are correct, only the padding differs.

### Row 8: TC-06 - DETECTED

- Named detecting checker(s): TC06-C4
- Date: 2026-11-28

**Fault 8** - saved next counter always inc32(J0) (counter not advanced for the consumed blocks). Attempt verdict: **DETECTED**
  - Build: `full` (no defines). Run: `obj_full/tbsim.exe +TEST=TC-06 +SEED=1 +FAULT=8 +TIMEOUT_MS=5`
  - Full log: `F8_TC-06_full.log` in the scratch folder `...\scratchpad\faults\logs\`
  - Patch (mutant hunks, file / old / new):
    - `m_aesgcm_seq.sv`
```
- old:
-                       reg_aad_rem, reg_ctr, reg_iv[LPARA_BLK_W-1 -: LPARA_IV_W], reg_ej0, reg_h,
+ new:
+                       reg_aad_rem, ((fsel == 8) ? LPARA_CTR_W'(2) : reg_ctr), reg_iv[LPARA_BLK_W-1 -: LPARA_IV_W], reg_ej0, reg_h,
```
  - Observed lines:
```
out byte 48: got 92 exp 0d
CHECK TC06-C4 FAIL @7191927: both halves of the output and the tag equal the uninterrupted model
```
### Row 9: TC-07 - DETECTED (attempt 2)

- Named detecting checker(s): TC07-C3, TC07-C2
- Date: 2026-11-28

**Fault 9** - resume loads the complete slot 0 image whatever ctx_id is. Attempt verdict: **INVALID**
  - INVALID reason: the slot-0 lengths and flags make the sequencer wait for the wrong stream; the AXI read burst times out (TB-ERROR RVALID time-out) and the testcase ends in the watchdog, so the C3 FAIL line is a consequence of the hang.
  - Build: `full` (no defines). Run: `obj_full/tbsim.exe +TEST=TC-07 +SEED=1 +FAULT=9 +TIMEOUT_MS=5`
  - Full log: `F9_TC-07_full.log` in the scratch folder `...\scratchpad\faults\logs\`
  - Patch (mutant hunks, file / old / new):
    - `m_aesgcm_ctx.sv`
```
- old:
-         reg_sel   <= (PARA_CTX_MODE == 1) ? 2'd0 : i_slot;
+ new:
+         reg_sel   <= (PARA_CTX_MODE == 1) ? 2'd0 : (((fsel == 9) && i_load) ? 2'd0 : i_slot);
```
  - Observed lines:
```
CHECK TC07-C3 FAIL @2009811927: slot 1 resumed: plaintext = model and tag_ok = 1
TB-ERROR @2009271927: RVALID time-out at beat 6 of 10
TB-ERROR: watchdog: TC-07 exceeded 5000000000 ps
CHECK TC07-C4 FAIL @4010461927: slot 0 resumed from the AAD phase: output and tag = model
```

**Fault 30** - resume restores the crypto words (Y, H, E(K,J0), IV, counter, key) of slot 0 and the lengths, flags and expected tag of the addressed slot. Attempt verdict: **DETECTED**
  - Build: `full` (no defines). Run: `obj_full/tbsim.exe +TEST=TC-07 +SEED=1 +FAULT=30 +TIMEOUT_MS=5`
  - Full log: `F30_TC-07_full.log` in the scratch folder `...\scratchpad\faults\logs\`
  - Patch (mutant hunks, file / old / new):
    - `m_aesgcm_ctx.sv`
```
- old:
-     assign o_img       = w_slot_sel;
+ new:
+     localparam logic [LPARA_SLOT_W-1:0] LPARA_F30_MASK = {{128{1'b0}}, {256{1'b1}}, {160{1'b0}}, {512{1'b1}}};
+     assign o_img       = ((fsel == 30) && (reg_req == ENUM_CTX_REQ_LOAD)) ?
+                          ((reg_slot[0] & LPARA_F30_MASK) | (w_slot_sel & ~LPARA_F30_MASK)) : w_slot_sel;
```
  - Observed lines:
```
CHECK TC07-C3 FAIL @9811927: slot 1 resumed: plaintext = model and tag_ok = 1
==== RESULT TC-07: FAIL (1 failed checks, 0 harness errors, 7 of 5 required check IDs) ====
```

Analysis: TC07-C2 checks the state at suspend, before any resume, so it cannot see this fault.

### Row 10: TC-08 - DETECTED

- Named detecting checker(s): TC08-C3
- Date: 2026-11-28

**Fault 10** - abort also zeroizes the key store (o_key_zeroize on every ABRT entry). Attempt verdict: **DETECTED**
  - Build: `full` (no defines). Run: `obj_full/tbsim.exe +TEST=TC-08 +SEED=1 +FAULT=10 +TIMEOUT_MS=5`
  - Full log: `F10_TC-08_full.log` in the scratch folder `...\scratchpad\faults\logs\`
  - Patch (mutant hunks, file / old / new):
    - `m_aesgcm_seq.sv`
```
- old:
-           o_key_zeroize = reg_first & reg_zero_act;
+ new:
+           o_key_zeroize = reg_first & (reg_zero_act | (fsel == 10));
```
  - Observed lines:
```
CHECK TC08-C3 FAIL @6421927: key kept by the abort: next message with the same key correct without key_new
```

Analysis: The failing term is sts.key_ld (the key is reloaded from the retained CSR key words at each start, so the following message itself is still correct; only the key_ld read-back shows the loss).

### Row 11: TC-08 (alt.) - DETECTED

- Named detecting checker(s): TC08-C5, TC08-C6
- Date: 2026-11-28

**Fault 11** - zeroize leaves key_ld = 1 (key store) and the BUS key_new latch set (GCM start without key_new allowed). Attempt verdict: **DETECTED**
  - Build: `full` (no defines). Run: `obj_full/tbsim.exe +TEST=TC-08 +SEED=1 +FAULT=11 +TIMEOUT_MS=5`
  - Full log: `F11_TC-08_full.log` in the scratch folder `...\scratchpad\faults\logs\`
  - Patch (mutant hunks, file / old / new):
    - `m_aesgcm_key_sel.sv`
```
- old:
-             reg_ready <= 1'b0;
-             reg_ld    <= 1'b0;
-             reg_wait  <= 1'b0;
-           end
-           5'b01???: begin
+ new:
+             reg_ready <= 1'b0;
+             if (fsel != 11) reg_ld <= 1'b0;
+             reg_wait  <= 1'b0;
+           end
+           5'b01???: begin
```
    - `m_aesgcm_bus_ctl.sv`
```
- old:
-         end else if (o_key_clr) begin
-           reg_klat_vld <= 1'b0;
+ new:
+         end else if (o_key_clr && (fsel != 11)) begin
+           reg_klat_vld <= 1'b0;
```
  - Observed lines:
```
CHECK TC08-C5 FAIL @6961927: zeroize done in 24 bus clocks: zeroized=1, key_ld=0
CHECK TC08-C6 FAIL @9851927: GCM start after zeroize without key_new: CFG_ERR
TB-ERROR @2011091927: RVALID time-out at beat 2 of 4
```

Analysis: After C6 the message is accepted and its stream is not consumed as the testbench expects; the following TB-ERROR lines and C7 FAIL (2 harness errors) are consequences. C5 and C6 fail first, with their own lines.

### Row 12: TC-09 - DETECTED

- Named detecting checker(s): TC09-C4, AXI-16
- Date: 2026-11-28

**Fault 12** - WRAP write bursts accepted as legal (drop flag not set for WRAP): beats pushed, BRESP OKAY. Attempt verdict: **DETECTED**
  - Build: `full` (no defines). Run: `obj_full/tbsim.exe +TEST=TC-09 +SEED=1 +FAULT=12 +TIMEOUT_MS=5`
  - Full log: `F12_TC-09_full.log` in the scratch folder `...\scratchpad\faults\logs\`
  - Patch (mutant hunks, file / old / new):
    - `m_aesgcm_axi_win.sv`
```
- old:
-         reg_drop  <= ~w_aw_legal;
+ new:
+         reg_drop  <= (fsel == 12) ? ~w_aw_legal_f : ~w_aw_legal;
```
    - `m_aesgcm_axi_win.sv`
```
- old:
-     assign w_aw_fire  = i_axi_awvalid & o_axi_awready;
+ new:
+     assign w_aw_legal_f = i_sel & ~i_axi_awaddr[LPARA_WIN_BIT] & ~(i_axi_awburst == 2'b11) &
+                           (i_axi_awsize == 3'(LPARA_SIZE));
+     assign w_aw_fire  = i_axi_awvalid & o_axi_awready;
```
  - Observed lines:
```
ASSERT FAIL @1331927: AXI-16 BRESP matches burst legality (spec 6.3.2, ERR-008)
CHECK TC09-C1 FAIL @1571927: WRAP, reserved, wrong size and read-window writes: SLVERR
CHECK TC09-C4 FAIL @8361927: ciphertext = model: illegal bursts did not change the FIFOs
```

Analysis: The patch makes the WRAP burst legal, so BRESP is OKAY as well (AXI-16 and TC09-C1 fail in addition to C4).

### Row 13: TC-09 (alt.) - DETECTED

- Named detecting checker(s): AXI-14, TC09-C1/C3
- Date: 2026-11-28

**Fault 13** - BID returns 0. Attempt verdict: **DETECTED**
  - Build: `full` (no defines). Run: `obj_full/tbsim.exe +TEST=TC-09 +SEED=1 +FAULT=13 +TIMEOUT_MS=5`
  - Full log: `F13_TC-09_full.log` in the scratch folder `...\scratchpad\faults\logs\`
  - Patch (mutant hunks, file / old / new):
    - `m_aesgcm_axi_win.sv`
```
- old:
-     assign o_axi_bid    = reg_awid;
+ new:
+     assign o_axi_bid    = (fsel == 13) ? '0 : reg_awid;
```
  - Observed lines:
```
ASSERT FAIL @1251927: AXI-14 BID equals AWID (IHI0022H A5.2, spec 6.2)
CHECK TC09-C1 FAIL @1571927: WRAP, reserved, wrong size and read-window writes: SLVERR
CHECK TC09-C3 FAIL @7901927: legal AAD and 256-beat INCR payload bursts: OKAY, BID echoed
```
### Row 14: TC-10 - DETECTED

- Named detecting checker(s): DMA-IN-01
- Date: 2026-11-28

**Fault 14** - DMA request follows the room condition (reg_req gated by i_cond while the FSM waits in REQ). Attempt verdict: **DETECTED**
  - Build: `full` (no defines). Run: `obj_full/tbsim.exe +TEST=TC-10 +SEED=1 +FAULT=14 +TIMEOUT_MS=5`
  - Full log: `F14_TC-10_full.log` in the scratch folder `...\scratchpad\faults\logs\`
  - Patch (mutant hunks, file / old / new):
    - `m_aesgcm_dma_ch.sv`
```
- old:
-         reg_req <= (w_fsm_hsk_nxt_state == ENUM_ST_HSK_REQ);
+ new:
+         reg_req <= (w_fsm_hsk_nxt_state == ENUM_ST_HSK_REQ) && ((fsel != 14) || i_cond) &&
+                    !((fsel == 15) && (reg_age >= 3'd2));
```
    - `m_aesgcm_dma_ch.sv`
```
- old:
-     // Request output.
-     assign o_req = reg_req;
+ new:
+     always_ff @(posedge i_clk_bus, negedge i_rst_n_bus) begin : p_ff_fault_age
+       if (!i_rst_n_bus) reg_age <= '0;
+       else if (reg_fsm_hsk_current_state != ENUM_ST_HSK_REQ) reg_age <= '0;
+       else if (reg_age != 3'd7) reg_age <= reg_age + 3'd1;
+     end
+   
+     // Request output.
+     assign o_req = reg_req;
```
  - Observed lines:
```
ASSERT FAIL @23481927: DMA-IN-01 request not withdrawn before acknowledge (6.3.4)
ASSERT FAIL @3961927: DMA-OUT-01 request not withdrawn before acknowledge (6.3.4)
==== RESULT TC-10: PASS (6 checks, 6 check IDs) ====
assertion failures: 46, assertions never exercised: 46
```

Analysis: No TC10-Cx check fails; the detection is by the assertions only (the run exits non-zero because of them). The patch is in the shared module m_aesgcm_dma_ch, so the output channel is affected too (DMA-OUT-01). A supplementary variant (fault 15: request withdrawn after 2 clocks in REQ) is detected by the same assertions (F15_TC-10_full.log).

### Row 15: TC-10 (alt.) - DETECTED (attempt 2)

- Named detecting checker(s): DMA-OUT-12 or TC10-C4
- Date: 2026-11-28

**Fault 16** - output request needs one beat less than the burst (need computed with one beat in hand). Attempt verdict: **INVALID**
  - INVALID reason: the fault does not manifest. The missing beat is always already in the unpacker's entry or arrives before the DMA reads it; no check or assertion fires (TC-10 PASS).
  - Build: `full` (no defines). Run: `obj_full/tbsim.exe +TEST=TC-10 +SEED=1 +FAULT=16 +TIMEOUT_MS=5`
  - Full log: `F16_TC-10_full.log` in the scratch folder `...\scratchpad\faults\logs\`
  - Patch (mutant hunks, file / old / new):
    - `m_aesgcm_unpack.sv`
```
- old:
-     assign w_need_bytes = (w_want > w_held) ? (w_want - w_held) : 32'd0;
+ new:
+     assign w_need_bytes = (fsel == 16) ?
+                           ((w_want > (w_held + 32'(reg_beat_bytes))) ? (w_want - w_held - 32'(reg_beat_bytes)) : 32'd0) :
+                           ((w_want > w_held) ? (w_want - w_held) : 32'd0);
```
  - Observed lines:
```
==== RESULT TC-10: PASS (6 checks, 6 check IDs) ====
assertion failures: 0, assertions never exercised: 46
```

**Fault 28** - output request needs only one beat (w_want limited to the beat size instead of the burst size). Attempt verdict: **DETECTED**
  - Build: `full` (no defines). Run: `obj_full/tbsim.exe +TEST=TC-10 +SEED=1 +FAULT=28 +TIMEOUT_MS=5`
  - Full log: `F28_TC-10_full.log` in the scratch folder `...\scratchpad\faults\logs\`
  - Patch (mutant hunks, file / old / new):
    - `m_aesgcm_unpack.sv`
```
- old:
-     assign w_want      = (o_unread < 32'(reg_burst_bytes)) ? o_unread : 32'(reg_burst_bytes);
+ new:
+     assign w_want      = (o_unread < ((fsel == 28) ? 32'(reg_beat_bytes) : 32'(reg_burst_bytes))) ? o_unread :
+                          ((fsel == 28) ? 32'(reg_beat_bytes) : 32'(reg_burst_bytes));
```
  - Observed lines:
```
CHECK TC10-C4 FAIL @25241927: no PROTO_ERR: no PIO overrun or underrun under DMA control
CHECK TC10-C1 FAIL @25241927: output = model for 4 messages
ASSERT FAIL @24171927: DMA-OUT-11 request rises only while beats remain (6.3.4 phase 1)
```

Analysis: DMA-OUT-12 was exercised (855 hits) and did not fail; DMA-OUT-11 (request while no beats remain) and TC10-C4 fail. Attempt 3 (fault 29, request ignoring data availability, F29_TC-10_full.log) gives the same TC10-C4 FAIL.

### Row 16: TC-11 - DETECTED

- Named detecting checker(s): TC11-C2
- Date: 2026-11-28

**Fault 17** - CFB-1 output byte uses bit 0 instead of bit 7 (AES core output stage). Attempt verdict: **DETECTED**
  - Build: `full` (no defines). Run: `obj_full/tbsim.exe +TEST=TC-11 +SEED=1 +FAULT=17 +TIMEOUT_MS=5`
  - Full log: `F17_TC-11_full.log` in the scratch folder `...\scratchpad\faults\logs\`
  - Patch (mutant hunks, file / old / new):
    - `rtl/ht_aes128_256/m_aes128_256_batch_core.sv`
```
- old:
-           w_out_data_nxt = w_result_data;
-           w_out_lane_valid_nxt = w_pipe_out_lane_valid;
+ new:
+           w_out_data_nxt = w_result_data;
+           if ((fsel == 17) && (reg_mode == ENUM_AES_MODE_CFB) && (reg_cfb_segment_size == 4'd0))
+             w_out_data_nxt[127:0] = {7'd0, w_result_data[127], 120'd0};
+           w_out_lane_valid_nxt = w_pipe_out_lane_valid;
```
  - Observed lines:
```
CHECK TC11-C2 FAIL @109141927: CFB segment sizes 1..128 equal the model (DEC-021 byte packing)
```

Analysis: The patch is in rtl/ht_aes128_256/m_aes128_256_batch_core.sv (the core output byte), because the accelerator wrappers pass the core bytes unchanged.

### Row 17: TC-11 (alt.) - DETECTED

- Named detecting checker(s): TC11-C5
- Date: 2026-11-28

**Fault 18** - aesgcm_err_code not cleared at the next start (bus-domain err_code register). Attempt verdict: **DETECTED**
  - Build: `full` (no defines). Run: `obj_full/tbsim.exe +TEST=TC-11 +SEED=1 +FAULT=18 +TIMEOUT_MS=5`
  - Full log: `F18_TC-11_full.log` in the scratch folder `...\scratchpad\faults\logs\`
  - Patch (mutant hunks, file / old / new):
    - `m_aesgcm_bus_ctl.sv`
```
- old:
-           6'b1?????: begin
-             reg_err_code <= ENUM_ERR_NONE;
-             reg_err_core <= '0;
-           end
+ new:
+           6'b1?????: begin
+             if (fsel != 18) begin
+               reg_err_code <= ENUM_ERR_NONE;
+               reg_err_core <= '0;
+             end
+           end
```
  - Observed lines:
```
CHECK TC11-C5 FAIL @109141927: recovery message after the errors correct, err_code cleared
```
### Row 18: TC-12 - DETECTED

- Named detecting checker(s): TC12-C2, INT-04
- Date: 2026-11-28

**Fault 19** - o_int_aesgcm registered from the raw register (enable ignored). Attempt verdict: **DETECTED**
  - Build: `full` (no defines). Run: `obj_full/tbsim.exe +TEST=TC-12 +SEED=1 +FAULT=19 +TIMEOUT_MS=5`
  - Full log: `F19_TC-12_full.log` in the scratch folder `...\scratchpad\faults\logs\`
  - Patch (mutant hunks, file / old / new):
    - `m_aesgcm_bus_ctl.sv`
```
- old:
-         reg_int       <= |o_irq_sts;
+ new:
+         reg_int       <= (fsel == 19) ? (|i_irq_raw) : (|o_irq_sts);
```
  - Observed lines:
```
CHECK TC12-C2 FAIL @4551927: masked causes: irq_sts = 0 and the line stays low
ASSERT FAIL @461927: INT-04 o_int_aesgcm low while no cause is enabled (spec 6.4, invariant 6)
CHECK TC12-C6 FAIL @6571927: DONE kept while masked; line rises when enabled
```
### Row 19: TC-12 (alt.) - DETECTED

- Named detecting checker(s): TC12-C1
- Date: 2026-11-28

**Fault 20** - irq_inj bit 9 sets raw bit 8 instead of bit 9. Attempt verdict: **DETECTED**
  - Build: `full` (no defines). Run: `obj_full/tbsim.exe +TEST=TC-12 +SEED=1 +FAULT=20 +TIMEOUT_MS=5`
  - Full log: `F20_TC-12_full.log` in the scratch folder `...\scratchpad\faults\logs\`
  - Patch (mutant hunks, file / old / new):
    - `m_aesgcm_bus_ctl.sv`
```
- old:
-       w_evt_bus = i_irq_inj & ~reg_inj_q;
+ new:
+       w_evt_bus = i_irq_inj & ~reg_inj_q;
+       if (fsel == 20) begin
+         w_evt_bus[8] = w_evt_bus[8] | w_evt_bus[9];
+         w_evt_bus[9] = 1'b0;
+       end
```
  - Observed lines:
```
CHECK TC12-C1 FAIL @4551927: injection sets each of the 10 raw causes
CHECK TC12-C3 FAIL @4551927: enabled cause: irq_sts bit and the line high within 2 bus clocks
```
### Row 20: TC-13 - NOT DETECTED (literal fault); DETECTED when the BUS latch also survives

- Named detecting checker(s): TC13-C3, TC13-C1
- Date: 2026-11-28

**Fault 21** - CORE key store (reg_key, reg_ld) without reset. Attempt verdict: **NOT DETECTED**
  - Build: `full` (no defines). Run: `obj_full/tbsim.exe +TEST=TC-13 +SEED=1 +FAULT=21 +TIMEOUT_MS=5`
  - Full log: `F21_TC-13_full.log` in the scratch folder `...\scratchpad\faults\logs\`
  - Patch (mutant hunks, file / old / new):
    - `m_aesgcm_key_sel.sv`
```
- old:
-         reg_key       <= '0;
-         reg_ready     <= 1'b0;
-         reg_ld        <= 1'b0;
+ new:
+         if ((fsel != 21) && (fsel != 22)) reg_key <= '0;
+         reg_ready     <= 1'b0;
+         if ((fsel != 21) && (fsel != 22)) reg_ld  <= 1'b0;
```
  - Observed lines:
```
==== RESULT TC-13: PASS (6 checks, 6 check IDs) ====
assertion failures: 0, assertions never exercised: 38
```

**Fault 22** - as 21 and the BUS key latch (reg_klat_vld/size/tlen) not reset: key retention observable at start legality. Attempt verdict: **DETECTED**
  - Build: `full` (no defines). Run: `obj_full/tbsim.exe +TEST=TC-13 +SEED=1 +FAULT=22 +TIMEOUT_MS=5`
  - Full log: `F22_TC-13_full.log` in the scratch folder `...\scratchpad\faults\logs\`
  - Patch (mutant hunks, file / old / new):
    - `m_aesgcm_bus_ctl.sv`
```
- old:
-         reg_klat_vld   <= 1'b0;
-         reg_klat_size  <= 1'b0;
-         reg_klat_tlen  <= '0;
+ new:
+         if (fsel != 22) begin
+           reg_klat_vld   <= 1'b0;
+           reg_klat_size  <= 1'b0;
+           reg_klat_tlen  <= '0;
+         end
```
  - Observed lines:
```
CHECK TC13-C3 FAIL @6001927: key store empty after reset: GCM start without key_new rejected
```

Analysis: A GCM start is legal only if the BUS-domain latch reg_klat_vld (set by key_new, cleared by a confirmed zeroize and by the BUS reset) is set; the CORE key store has no role in the legality check, and sts.key_ld is read from the BUS status register (reset to 0, refreshed only by a status report after a message). A CORE-only reset omission therefore has no observable effect through the register interface: TC13-C1 and TC13-C3 pass. The observable behaviour of the plan ('GCM start accepted without key_new') exists only if the BUS latch survives the reset as well (fault 22). The whole TC and FT groups also pass with fault 21 (F21_TC_full_grpTC.log, F21_FT_full_grpFT.log).

### Row 21: TC-13 (alt.) - DETECTED

- Named detecting checker(s): DMA-IN-07, TC13-C2
- Date: 2026-11-28

**Fault 23** - DMA request flops reset to 1 (request held 1 during reset). Attempt verdict: **DETECTED**
  - Build: `full` (no defines). Run: `obj_full/tbsim.exe +TEST=TC-13 +SEED=1 +FAULT=23 +TIMEOUT_MS=5`
  - Full log: `F23_TC-13_full.log` in the scratch folder `...\scratchpad\faults\logs\`
  - Patch (mutant hunks, file / old / new):
    - `m_aesgcm_dma_ch.sv`
```
- old:
-       if (!i_rst_n_bus)
-         reg_req <= 1'b0;
+ new:
+       if (!i_rst_n_bus)
+         reg_req <= (fsel == 23) ? 1'b1 : 1'b0;
```
  - Observed lines:
```
ASSERT FAIL @21927: DMA-IN-07 request 0 during reset and first cycle after release (6.3.4, 7.3)
ASSERT FAIL @21927: DMA-OUT-07 request 0 during reset and first cycle after release (6.3.4, 7.3)
==== RESULT TC-13: PASS (6 checks, 6 check IDs) ====
```

Analysis: TC13-C2 samples the request after the reset sequence and passes (the request has returned to 0 by then); only the assertions DMA-IN-07/DMA-OUT-07 (request 0 during reset) see the fault.

### Row 22: TC-14 - DETECTED (attempt 2)

- Named detecting checker(s): TC14-C1/C2
- Date: 2026-11-28

**Fault 24** - CFG bundle captured one edge too early = the previous bundle is captured (sync build, ratio 3:2). Attempt verdict: **INVALID**
  - INVALID reason: the first message runs with an all-zero bundle (length 0) and later ones with the wrong lengths; the data streams are not consumed, the AXI and PIO paths time out (4 TB-ERROR harness errors, 20 assertion failures of the bus protocol). C1/C2 do fail but as a consequence of the hang.
  - Build: `sync` (TB_CLK_ASYNC=0). Run: `obj_sync/tbsim.exe +TEST=TC-14 +SEED=1 +FAULT=24 +CLK_RATIO=3_2`
  - Full log: `F24_TC-14_sync.log` in the scratch folder `...\scratchpad\faults\logs\`
  - Patch (mutant hunks, file / old / new):
    - `m_aesgcm_xing_bdl.sv`
```
- old:
-       else if ((reg_fsm_hsr_current_state == ENUM_ST_HSR_IDLE) && w_dst_req)
-         reg_cap <= reg_hold;
+ new:
+       else if ((reg_fsm_hsr_current_state == ENUM_ST_HSR_IDLE) && w_dst_req) begin
+         reg_cap <= reg_hold;
+         if ((PARA_DATA_W == 611) && (PARA_CLK_ASYNC == 0) && (fsel == 24))
+           reg_cap <= reg_prev;
+         if ((PARA_CLK_ASYNC == 0) && (fsel == 25))
+           reg_cap <= (reg_hold & ~w_ivmask) | (reg_prev & w_ivmask);
+       end
```
    - `m_aesgcm_xing_bdl.sv`
```
- old:
-     assign o_data = reg_cap;
+ new:
+     if (PARA_DATA_W == 611) begin : gen_ivmask
+       assign w_ivmask = {{99{1'b0}}, {128{1'b1}}, {384{1'b0}}};
+     end else begin : gen_noivmask
+       assign w_ivmask = '0;
+     end
+   
+     always_ff @(posedge i_clk_dst, negedge i_rst_n_dst) begin : p_ff_fault_prev
+       if (!i_rst_n_dst) reg_prev <= '0;
+       else if ((reg_fsm_hsr_current_state == ENUM_ST_HSR_IDLE) && w_dst_req) reg_prev <= reg_hold;
+     end
+   
+     assign o_data = reg_cap;
```
  - Observed lines:
```
CHECK TC14-C1 FAIL @7064317500: every byte delivered across the crossings (output = model)
TB-ERROR @3003187500: RVALID time-out at beat 0 of 9
TB-ERROR @4061002500: PIO stalled: 37/37 words pushed, 20/33 popped
ASSERT FAIL @3006082500: AXI-10 RID/RDATA/RRESP/RLAST stable while stalled (IHI0022H A3.2.1)
```

**Fault 25** - as 24 but only the IV field (bits 511:384) of the previous bundle is captured. Attempt verdict: **DETECTED**
  - Build: `sync` (TB_CLK_ASYNC=0). Run: `obj_sync/tbsim.exe +TEST=TC-14 +SEED=1 +FAULT=25 +CLK_RATIO=3_2`
  - Full log: `F25_TC-14_sync.log` in the scratch folder `...\scratchpad\faults\logs\`
  - Patch (mutant hunks, file / old / new):
    - `m_aesgcm_xing_bdl.sv`
```
- old:
-       else if ((reg_fsm_hsr_current_state == ENUM_ST_HSR_IDLE) && w_dst_req)
-         reg_cap <= reg_hold;
+ new:
+       else if ((reg_fsm_hsr_current_state == ENUM_ST_HSR_IDLE) && w_dst_req) begin
+         reg_cap <= reg_hold;
+         if ((PARA_DATA_W == 611) && (PARA_CLK_ASYNC == 0) && (fsel == 24))
+           reg_cap <= reg_prev;
+         if ((PARA_CLK_ASYNC == 0) && (fsel == 25))
+           reg_cap <= (reg_hold & ~w_ivmask) | (reg_prev & w_ivmask);
+       end
```
    - `m_aesgcm_xing_bdl.sv`
```
- old:
-     assign o_data = reg_cap;
+ new:
+     if (PARA_DATA_W == 611) begin : gen_ivmask
+       assign w_ivmask = {{99{1'b0}}, {128{1'b1}}, {384{1'b0}}};
+     end else begin : gen_noivmask
+       assign w_ivmask = '0;
+     end
+   
+     always_ff @(posedge i_clk_dst, negedge i_rst_n_dst) begin : p_ff_fault_prev
+       if (!i_rst_n_dst) reg_prev <= '0;
+       else if ((reg_fsm_hsr_current_state == ENUM_ST_HSR_IDLE) && w_dst_req) reg_prev <= reg_hold;
+     end
+   
+     assign o_data = reg_cap;
```
    (fault 25 selects the `(fsel == 25)` line of the same hunk set as fault 24.)
  - Observed lines:
```
CHECK TC14-C1 FAIL @17602500: every byte delivered across the crossings (output = model)
CHECK TC14-C2 FAIL @17602500: GCM tags = model / tag_ok across the status crossing
==== RESULT TC-14: FAIL (2 failed checks, 0 harness errors, 5 of 5 required check IDs) ====
```
### Row 23: TC-14 (alt.) - DETECTED

- Named detecting checker(s): TC14-C4 or TC14-C2
- Date: 2026-11-28

**Fault 26** - tag words [127:64] of the status registers are not refreshed by reports of phase FIN or IDLE (words from two reports). Attempt verdict: **DETECTED**
  - Build: `sync` (TB_CLK_ASYNC=0). Run: `obj_sync/tbsim.exe +TEST=TC-14 +SEED=1 +FAULT=26 +CLK_RATIO=3_2`
  - Full log: `F26_TC-14_sync.log` in the scratch folder `...\scratchpad\faults\logs\`
  - Patch (mutant hunks, file / old / new):
    - `m_aesgcm_bus_ctl.sv`
```
- old:
-         if (i_sts_valid)
-           reg_sts <= i_sts;
+ new:
+         if (i_sts_valid) begin
+           reg_sts <= i_sts;
+           if ((fsel == 26) && ((i_sts[LPARA_STS_W-27 -: 4] == 4'hA) || (i_sts[LPARA_STS_W-27 -: 4] == 4'h0)))
+             reg_sts[127:64] <= reg_sts[127:64];
+         end
```
  - Observed lines:
```
CHECK TC14-C2 FAIL @17602500: GCM tags = model / tag_ok across the status crossing
==== RESULT TC-14: FAIL (1 failed checks, 0 harness errors, 5 of 5 required check IDs) ====
```

Analysis: TC14-C4 (two reads identical) passes: the torn value is stable. A transient tear that only exists during the report crossing cannot be read after DONE because DONE leaves in the last report (DEC-036); the persistent form used here is detected by C2.

### Row 24: TC-15 - NOT DETECTED

- Named detecting checker(s): TC15-C1/C2
- Date: 2026-11-28

**Fault 27** - 64 idle core clocks before the length block. Attempt verdict: **NOT DETECTED**
  - Build: `full` (no defines). Run: `obj_full/tbsim.exe +TEST=TC-15 +SEED=1 +FAULT=27 +TIMEOUT_MS=5`
  - Full log: `F27_TC-15_full.log` in the scratch folder `...\scratchpad\faults\logs\`
  - Patch (mutant hunks, file / old / new):
    - `m_aesgcm_seq.sv`
```
- old:
-           o_gh_valid = ~reg_len_sent;
+ new:
+           o_gh_valid = ~reg_len_sent & ((fsel != 27) | (reg_lat == lat_n[8:0]));
```
    - `m_aesgcm_seq.sv`
```
- old:
-   endmodule
+ new:
+     always_ff @(posedge i_clk_core, negedge i_rst_n_core) begin : p_ff_fault_lat
+       if (!i_rst_n_core) reg_lat <= '0;
+       else if (reg_fsm_seq_current_state != ENUM_ST_SEQ_LEN) reg_lat <= '0;
+       else if (reg_lat != lat_n[8:0]) reg_lat <= reg_lat + 9'd1;
+     end
+   
+   endmodule
```
  - Observed lines:
```
PERF-001: latency 1450000 ps, bound 1882988 ps (formula 49 core clocks, data 810000 ps)
CHECK TC15-C1 PASS: start-to-DONE latency within PERF-001 bound (1450000 <= 1882988 ps)
CHECK TC15-C2 PASS: start-to-DONE latency within PERF-001 bound (5480000 <= 6538212 ps)
```

Analysis: The PERF-001 bound used by the testbench adds 2 X_c, the measured data-movement time and 8 x (apb_gap_max + 4) bus clocks to the formula, so for the 280-byte message the slack over the fault-free latency is 973 ns = 128 core clocks (fault-free 910000 ps, bound 1882988 ps, Tcore 7612 ps). Re-running with a longer delay (+FAULT_LAT=n, log names F27_TC-15_full_latN.log): n = 128 -> C1 FAIL (1930000 > 1882988 ps); n = 192, 256, 384 -> C1 and C2 FAIL. The C2 bound contains the data-movement time of the 1 KB message, which varies from 1.76 us to 5.45 us between runs with the same seed, so it has very little sensitivity.

## NOT DETECTED / INVALID / demonstration cases

- Row 2 (TC-01 alt., fault 2): NOT DETECTED, testbench gap (pass 1 -> key_new -> pass 2 is never run; the C9 sequence
  follows a pass 2 that has already consumed the verified context).
- Row 20 (TC-13, fault 21): NOT DETECTED as defined (CORE key store without reset); the key_new latch of the BUS domain
  decides the start legality, so the omission is invisible through the registers. Fault 22 (latch retained too) is detected by TC13-C3.
- Row 24 (TC-15, fault 27): NOT DETECTED, the PERF-001 bound has about 128 core clocks of slack at 280 bytes (detected from 128 clocks upward).
- INVALID attempts (all resolved by a refined fault): fault 9 (hang, row 9), fault 16 (does not manifest, row 15), fault 24 (hang, row 22).
- Demonstrations of the known-bad type were not used (the two listed demonstrations in `fault_plan.md` are independent of this campaign and were not run).

