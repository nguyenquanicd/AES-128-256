# AES-GCM Accelerator - acceptance simulation test plan

| Item | Value |
|---|---|
| Design specification | `doc/ht_aes_gcm_acc/VLSIT_AES_GCM_ACCELERATOR_HDS.md` v0.1 (Draft), sections 3, 5, 6, 7, 8, 9, 10, 11, 12, 13.2, 15, 19, 20 |
| Register authority | `doc/ht_aes_gcm_acc/aesgcm_regs.json` (workbook 1.0, REF-005) |
| Waveform plan | spec 10.3, figures `doc/ht_aes_gcm_acc/figures/WF-001..WF-023` (WaveJSON) |
| Standards | Arm IHI 0024D (APB4), Arm IHI 0022H.c (AXI4), NIST SP 800-38D (GCM), FIPS 197 / SP 800-38A through `verification/ht_aes128_256/aes128_256_ref.py` |
| Authoring rule | R-023: plan, stimulus, checks, assertions and expected values written from the items above only; no RTL, no RTL-derived interface fact. Facts missing in the specification are in `open_questions.md`. |
| Status | Planned and implemented. **Not executed, not verified** (no simulator was run by the author). |

## 1. Coverage intent (R-047)

The designer decided: **functional / requirement coverage only, no code coverage** (code coverage status `not_requested`). Targets:

- 100 % of the section 15.2 rows that apply to the built configurations are mapped to an executable testcase with checks (section 4 below).
- Every applicable assertion is exercised at least once over a full run (`+TEST=ALL`); the run fails when an assertion fails or, in a full run, when an applicable assertion was never exercised (R-025).
- Functional coverage, requirement coverage, assertion coverage and the fault-qualification score (fault_plan.md, R-096) are reported separately and never combined into one percentage.

## 2. Configurations

| Build | Defines | Wrapper and parameters | Purpose |
|---|---|---|---|
| (a) main | `TB_CFG_FULL` (default) | `m_aesgcm_acc_axi_top`, lanes 4, ARCH 2, policy 2, CTX_NUM 2, CTX_MODE 0, KEY_SIDE 1, DW 64, CLK_ASYNC 1, FIFO 16 | all features except export |
| (b) link | `TB_CFG_LINK` | `m_aesgcm_acc_apb_top` CFG-LINK: policy 1, ARCH 1, CTX_NUM 0, lanes 1, KEY_SIDE 0 | APB-only microcontroller case |
| (c) min | `TB_CFG_MIN` | `m_aesgcm_acc_apb_top` CFG-MIN: ARCH 0, DIGIT 8, policy 0, CTX_NUM 0, FIFO 8 | digit-serial GHASH, policy A only |
| (d) export | `TB_CFG_EXPORT` | as (a) with CTX_MODE 1 (CTX_NUM 1, see Q-17) | context export / import |
| (e) legacy | `TB_CFG_LEGACY` (optional) | `m_aesgcm_acc_apb_top`, GCM_EN 0 | TEST-013 |
| (f) sync | any + `TB_CLK_ASYNC=0`, run with `+CLK_RATIO=1_1/3_2/4_1/1_4` | related clocks | TEST-023, WF-016 |
| (g) pipe | (a) + `TB_GHASH_PIPE=1` | feed-forward GHASH | TEST-030, WF-022 row pipe1 |
| (h) dma128 | (a) + `TB_AXI_DATA_W=128 TB_AES_LANE_NUM=1` | burst larger than the FIFO | TEST-036 Ex. 5 |

A testcase that does not apply to a build reports **SKIP with the reason from the specification**, never PASS.

## 3. Primary function to requirement to testcase to check matrix

| # | Primary function (spec) | Requirements | Testcases (checks) | Interaction checked |
|---|---|---|---|---|
| F01 | GCM authenticated encryption (5.3, OP-002) | REQ-FUNC-002, 008, 012 | TC-05 (C1, C2, C5), TC-04 (C2), TC-09 (C4, C5), TC-14 (C1, C2) | data path x lengths x tag length |
| F02 | GCM decryption policy C (OP-003) | REQ-FUNC-005 | TC-02 (C1, C2, C6), TC-03 (C6), TC-10 (C1, C2) | forgery x interrupt mask x next packet |
| F03 | GMAC / empty message (OP-006) | REQ-FUNC-007 | TC-05 (C4, C5), WF-020 | no output x tag |
| F04 | Policy A pass 1 (OP-004) | REQ-FUNC-003, REQ-SEC-002 | TC-01 (C1, C2, C4), TC-03 (C4), WF-003 | side-load x DMA x no output (POL-01..03) |
| F05 | Policy A pass 2 (OP-005) | REQ-FUNC-004 | TC-01 (C5, C6, C7, C9), FT-026 (C1, C3), WF-004 | modified ciphertext; key_new invalidation |
| F06 | Secure-only pin | REQ-FUNC-009, REQ-SEC-003, 6.3.6 | TC-03 (C1..C3, C5), TC-01 (pin 1), WF-005, FT-011 (C4, C5) | pin x policy x export |
| F07 | Tag lengths 128..96 | REQ-FUNC-006 | TC-04 (C1..C6) | latch at key_new x decryption compare |
| F08 | AES-128 and AES-256 | REQ-FUNC-001, 002 | TC-05 (alternating), TC-11, TC-01 (256 side-load), FT-014 (C5, 128 side-load) | key size x mode |
| F09 | Legacy ECB/CBC/CFB/OFB/CTR (OP-001) | REQ-FUNC-001, DEC-021 | TC-11 (C1, C2, C5), TC-10, TC-14, WF-019 | mode x path x errors |
| F10 | PIO data path (OP-012) | REQ-IF-004 | TC-05 (PIO records), TC-10, FT-018 (C1..C3), FT-033, WF-010 | overrun x resend |
| F11 | AXI4 window incl. illegal bursts (OP-013) | REQ-IF-002, 003, ERR-008 | TC-09 (C1..C6), TC-05, WF-006..008 | illegal bursts inside a live message |
| F12 | DMA four-phase (OP-014) | REQ-IF-005 | TC-10 (C1..C6), TC-01 (AXI DMA), WF-009 | burst size x ack delay x path |
| F13 | Key side-load + KEY_ERR (OP-011) | REQ-FUNC-015, REQ-SEC-004 | TC-01 (C3), FT-014 (C1..C6), WF-011 | early/late/never x key visibility |
| F14 | Suspend / resume, internal slots (OP-007/008) | REQ-FUNC-010, DEC-023 | TC-06 (C1..C6), TC-07 (C1..C5), WF-012 | urgent message with other key; two slots |
| F15 | Context export / import (OP-016) | REQ-FUNC-011 | FT-011 (C1..C5), WF-021 | export x pin |
| F16 | Abort (OP-009) | REQ-FUNC-013, PERF-004, DEC-022 | TC-08 (C1..C3), FT-012, WF-013, WF-023 | abort x key retention x next message |
| F17 | Zeroize (OP-010) | REQ-SEC-001, REQ-REG-002 | TC-08 (C4..C7), FT-028, WF-014, TC-13 (C5, C6) | zeroize x key_new rule |
| F18 | Interrupts, injection, masking (OP-015) | REQ-IF-006, REQ-INT-001 | TC-12 (C1..C7), TC-02 (C4, C5), TC-01 (C8), WF-015 | real event while masked |
| F19 | Error codes and events of section 12 | REQ-ERR-001, ERR-001..009 | TC-11 (C3, C4, C7), FT-026, TC-07 (C5, C6), TC-04 (C3, C4), TC-08 (C6), FT-014 (C3, C6), FT-036 | error x recovery |
| F20 | Configuration errors at start | ERR-001 | TC-03 (C2), TC-04 (C3, C4), TC-07 (C6), TC-08 (C6), TC-11 (C4, C7), TC-13 (C3), FT-013, FT-026, FT-036 | rejected start x next start |
| F21 | Reset (both and single domain) | REQ-RESET-001, 002, ERR-009 | TC-13 (C1..C6), WF-018, FT-029 (C3) | reset in payload x recovery by zeroize |
| F22 | APB4 completer, CSR behavior | REQ-IF-001, REQ-REG-001, 002 | FT-016 (C1..C7), TC-13 (C1), APB-01..27 | protect_en x slverr_en |
| F23 | Clock crossings async / sync | REQ-CLK-001..003 | TC-14 (C1..C5), WF-016, R-034 branch runs | clock relation x data |
| F24 | Failed-tag counter | REQ-SEC-005 | TC-02 (C3), TC-04 (C6), FT-029 (C1..C3), TC-01 (C7) | counter x abort/zeroize/reset |
| F25 | GHASH architectures | REQ-FUNC-016, REQ-PARAM-002 | FT-015 (all builds), FT-030, WF-017, WF-022 | build sweep |
| F26 | Latency / rate | REQ-PERF-001, 002 | TC-15 (C1..C3) | formula x data movement |
| F27 | Parameter legality | REQ-PARAM-001 | `tb_param_check_top.sv` (TEST-025, TEST-032) + `u_param_check` in every build | elaboration |

## 4. Section 15.2 rows

| TEST row | Testcases | Builds where it applies | Notes |
|---|---|---|---|
| TEST-001 | TC-11, TC-10, TC-14, WF-019 | all | vectors from `run_stream`, not the `ht_aes128_256/vectors` replay (Q-19) |
| TEST-002 | TC-05 (KAT records 0..7) | GCM builds | NIST test cases written from knowledge (gcm_ref.py docstring) |
| TEST-003 | TC-05, FT-015, TC-14 | GCM builds | all data paths |
| TEST-004 | TC-01, TC-03, WF-003, TC-04 (C6 via pass 1) | policy A builds | flipped ciphertext, tag; AAD/IV flips via `tag_in`/`ct` records only (Q-20) |
| TEST-005 | TC-01 (C5..C7, C9), FT-026 (C1), WF-004 | policy A builds | |
| TEST-006 | TC-02 | policy C builds | |
| TEST-007 | TC-04 | GCM builds | |
| TEST-008 | TC-05 | GCM builds | AAD x payload in {0,1,15,16,17,33} x {0,1,15,16,17,31,32,33} |
| TEST-009 | TC-03, WF-005 | policy C builds | elaboration inspection of policy 0 is a review item |
| TEST-010 | TC-06, TC-07, WF-012 | CTX_NUM > 0 | suspend at every block position is sampled (AAD 2 blocks, payload 3 blocks), not exhaustive (Q-21) |
| TEST-011 | FT-011, WF-021 | export build | |
| TEST-012 | FT-012, TC-08 | GCM builds | states KEY, AAD, PAY, IDLE reachable from ports; transient states only with probes |
| TEST-013 | FT-013 | legacy build | synthesis part is out of simulation |
| TEST-014 | FT-014, TC-01, WF-011 | all (KEY_ERR part in KEY_SIDE 0 builds) | |
| TEST-015 | FT-015 in every build | GCM builds | equivalence = all builds PASS against one model |
| TEST-016 | FT-016, TC-13 (C1) | all | |
| TEST-017 | TC-09, TC-05, WF-006..008 | AXI builds | FIXED/INCR 1..256 beats |
| TEST-018 | FT-018, TC-10 (C4), WF-010 | all | |
| TEST-019 | TC-10, TC-01, WF-009 | all | bursts 1..16, ack delay 0..8 |
| TEST-020 | TC-12, TC-02, WF-015 | all | hardware set with same-cycle software clear not reachable from ports (Q-22) |
| TEST-021 | TC-08 (C4), FT-016 (C7) | all | clear-wins-over-write race not reachable from ports (Q-22) |
| TEST-022 | TC-14 in async builds + metastable branch seeds | CLK_ASYNC 1 | CDC tool part out of simulation |
| TEST-023 | TC-14 and WF-016 in the sync build, four ratio runs | CLK_ASYNC 0 | STA part out of simulation |
| TEST-024 | TC-13, WF-018 | GCM builds | reset at each sequencer state only sampled (payload) |
| TEST-025 | `tb_param_check_top.sv` | lint flow | elaboration test, not a simulation testcase |
| TEST-026 | FT-026, TC-11, TC-07, TC-04, TC-08, FT-014 | all | simultaneous causes not reachable deterministically (Q-23) |
| TEST-027 | TC-15 | GCM builds | bound includes the data-movement time (Q-09) |
| TEST-028 | TC-08, FT-028, WF-014 | GCM builds | storage inspection needs probes (SEC-01) |
| TEST-029 | FT-029, TC-02 | GCM builds | saturation at 0xFFFFFFFF not reachable (Q-24) |
| TEST-030 | FT-030, WF-022 | 4-lane builds | PIPE 1 half needs build (g) |
| TEST-031 | FT-031, TC-14 | GCM builds | entry counts need probes |
| TEST-032 | `tb_param_check_top.sv` | lint flow | sets PC_LANE5, PC_PIPE_ARCH0, PC_DEPTH12 + others |
| TEST-033 | FT-033 | all | |
| TEST-034 | TC-08, WF-023 | GCM builds | |
| TEST-035 | TC-06, FT-011 (export words) | CTX_NUM > 0 | |
| TEST-036 | TC-02 (Ex. 6), FT-036 (Ex. 5) | Ex. 5 only in build (h) | |

## 5. Integrated testcases (R-048)

Ranked by interaction risk. Each has the R-095 header in its source (`tb_aesgcm_tests_tc.svh`, `tb_aesgcm_tests_tc2.svh`) with at least five check IDs.

| ID | Functions combined | Key interaction observation |
|---|---|---|
| TC-01 | side-load key, key_new, policy A pass 1 + pass 2, DMA over AXI4, secure-only pin, interrupt, failcnt | no output before ver_ok; changed ciphertext caught in pass 2; key_new invalidates ver_ok |
| TC-02 | policy C, TAG_FAIL, interrupt masking, failcnt, err_code, FIFO flush after failure | masked cause does not drive the line; next packet correct |
| TC-03 | secure-only pin, policy C rejection, policy A, sec_only status | rejection before any plaintext; policy A unaffected |
| TC-04 | tag-length latch, key_new, encryption truncation, decryption compare, failcnt | change without key_new rejected; bits beyond t ignored |
| TC-05 | KATs, length sweep, GMAC, AES-128/256, AXI INCR/FIXED/mixed and PIO | tails x data path x padding |
| TC-06 | suspend, consumed counts, urgent message with another key, resume, CTX_SWITCH_DONE | context survives a different key; slot released |
| TC-07 | two slots, AAD-phase and payload-phase suspend, interleaved resume, free, invalid resume, ctx_id range | slot isolation; error recovery |
| TC-08 | abort, FIFO flush, key retention, write-only keys, zeroize, key_new rule | abort keeps key, zeroize forbids GCM start until key_new |
| TC-09 | AXI4 illegal bursts (5 write, 3 read), 256-beat INCR, back-pressure, GCM | illegal bursts leave the stream intact |
| TC-10 | DMA four-phase over PIO, burst sizes, ack delays, GCM/CBC/CTR, DMA events | requests only with room/data (no PIO overrun) |
| TC-11 | legacy modes, CFB segment packing, LEN_ERR/CFG_ERR, err_code clearing, recovery | errors do not leak into the next message |
| TC-12 | injection, masking, w1c, multiple causes, real DONE while masked | line = OR of masked raw |
| TC-13 | reset in payload, reset values, key store emptied, single-domain reset + zeroize | recovery path of ASM-007 |
| TC-14 | async/sync crossings, start acceptance budget, status coherence, GCM/legacy | crossing latency within 13.2 budget |
| TC-15 (focused) | PERF-001/002 latency | formula bound |

## 6. Assertions (R-024, R-025)

Implemented in `tb_aesgcm_assert.sv`, clocked `chk` pattern, hit and fail counters, table printed at the end.

| Protocol | Count | IDs | Exercised by |
|---|---:|---|---|
| APB4 (IHI0024D 3.1-3.5, 4.1, A.1; spec 11.4) | 27 | APB-01..APB-27 | every test; APB-19..24 by FT-016; APB-25/26 by FT-016, TC-13 |
| AXI4 window (IHI0022H A3.1, A3.2, A3.3.1, A3.4.1, Table A3-5, A5.2; spec 6.3.2, 7.3) | 34 | AXI-01..AXI-34 | TC-05, TC-09, TC-01, TC-15, WF-006..009; AXI-22/23 masked for the deliberate WLAST burst of TC-09 |
| DMA four-phase (spec 6.3.4) | 24 | DMA-IN-01..12, DMA-OUT-01..12 | TC-10, TC-01, WF-009; DMA-*-07 by every reset |
| Spec / cross-interface | 22 | RST-01..03, X-01, X-02, KS-01..05, INT-01..04, POL-01..04, SEC-01, SEC-02, XING-01, XING-02 | TC-01, TC-03, TC-12, TC-13, FT-012, FT-014, FT-028, WF-005 |

Scenario-inapplicable assertions (excluded from the never-exercised count, printed with the reason):
- AXI-01..AXI-34 and POL-02 in the APB wrapper builds: no AXI4 ports (spec 6.2, FEAT-006).
- KS-01..KS-03, KS-05 with `PARA_KEY_SIDE_EN = 0` (KS-04 still checks that no ack appears).
- INT-01, POL-03, SEC-01, SEC-02, XING-01, XING-02 until the probes of `probe_list.md` are bound and `TB_PROBES_BOUND` is defined.

Masks for deliberate illegal stimulus: `i_mask_axi_wlast` (early WLAST burst of TC-09 only). Partial-strobe, unaligned and non-secure APB accesses of FT-016 are legal IHI0024D transfers and need no mask.

## 7. Waveform scenarios (R-033)

`+TEST=WF-nnn` for WF-001 .. WF-023 (`tb_aesgcm_wf.svh`); each dumps its window of the view scope `u_wf` to `waveforms_sim/<figure stem>.vcd`. Build requirements: WF-003/004 policy A; WF-005 policy C; WF-006..008 AXI; WF-011 side-load; WF-012 slots; WF-016 sync build with `+CLK_RATIO=3_2`; WF-017/022 four lanes; WF-021 export build. Index template: `waveforms_sim/waveform_compare.md` (all rows NOT-SIMULATED).

## 8. CDC branch runs (R-034, R-092, R-093)

Section 7.2 lists CDC-001..007, so both branches are required:

| Run | Build | Plusargs | Expected log label |
|---|---|---|---|
| synthesis | RTL filelist as delivered (contains `+define+VLSIT_SYNTHESIS`) | `+TEST=ALL +SEED=1` | `SIM-BRANCH: synthesis` |
| metastable 1..3 | RTL filelist copy without the `VLSIT_SYNTHESIS` line | `+TEST=ALL +SEED=<n> +AFIFO_MSYNC_SEED=<n>` for three distinct n | `SIM-BRANCH: metastable seed=<n>` |

Latency-dependent checks use the bounds of the specification (X_c of 13.2, PERF-004, PERF-001), never exact cycles.

## 9. Status by level (R-048)

| Level | Status |
|---|---|
| Planned | all rows above |
| Implemented | TC-01..TC-15, FT-011/012/013/014/015/016/018/026/028/029/030/031/033/036, WF-001..WF-023, 107 assertions, models, vectors generator |
| Executed | none (no simulator run by the author) |
| Verified / fault-qualified | none; see `fault_plan.md` and `review_ledger.md` (all PENDING) |
