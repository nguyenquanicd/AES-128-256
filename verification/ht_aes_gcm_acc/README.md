# AES-GCM accelerator - acceptance simulation testbench

Specification-based testbench of `m_aesgcm_acc_axi_top` / `m_aesgcm_acc_apb_top`, written from
`doc/ht_aes_gcm_acc/VLSIT_AES_GCM_ACCELERATOR_HDS.md` v0.1, the register workbook
`doc/ht_aes_gcm_acc/aesgcm_regs.json`, the WaveJSON figures WF-001..WF-023 and the standards
IHI 0024D (APB4), IHI 0022H.c (AXI4) and SP 800-38D (GCM). No RTL was read while authoring it (rule
R-023); facts the specification leaves open are in `open_questions.md`.

**Status: nothing in this folder has been compiled or simulated yet.** All results, waveforms and
reviews are pending.

## Files

| File | Content |
|---|---|
| `tb_aesgcm_top.sv` | Testbench top: DUT instance (port list of spec 6.2), parameter checker, assertion module, waveform view, test dispatcher, final report |
| `tb_aesgcm_cfg.svh` | Build configurations (`TB_CFG_FULL` default, `TB_CFG_LINK`, `TB_CFG_MIN`, `TB_CFG_EXPORT`, `TB_CFG_LEGACY`) and overrides |
| `tb_aesgcm_regs.svh` | Register offsets and fields from the workbook; expected `aesgcm_cap` |
| `tb_aesgcm_decl.svh` | Shared declarations |
| `tb_aesgcm_probes.svh` | Placeholder macros `TB_PROBE_<NAME>` for internal signals named in the figures (see `probe_list.md`) |
| `tb_apb_requester.svh` | APB4 requester model (wait states by the completer, idle gaps, PPROT, PSLVERR) |
| `tb_axi_manager.svh` | AXI4 manager model (FIXED/INCR/WRAP, AxSIZE, BREADY/RREADY back-pressure, WLAST mismatch) |
| `tb_dma_model.svh` | DMA controller of the four-phase handshake (spec 6.3.4) over the AXI4 window or PIO |
| `tb_keymgr_clk.svh` | Key manager (side-load, spec 6.3.5), clock generators (async or sync ratios), reset sequencer |
| `tb_aesgcm_lib.svh`, `tb_aesgcm_helpers.svh` | Harness: PRNG, check bookkeeping, vector loading, software sequence of spec 11.2, data movement |
| `tb_aesgcm_tests_tc.svh`, `tb_aesgcm_tests_tc2.svh` | Integrated testcases TC-01..TC-15 with R-095 headers |
| `tb_aesgcm_tests_ft.svh` | Focused testcases FT-011..FT-036 |
| `tb_aesgcm_wf.svh` | Waveform scenarios WF-001..WF-023 |
| `tb_aesgcm_assert.sv` | 107 clocked assertions (APB4 27, AXI4 34, DMA four-phase 24, spec/cross 22) |
| `tb_wf_view.sv` | Observation module whose ports are the rows of the figures (the dumped scope) |
| `tb_param_check_top.sv` | Elaboration tests TEST-025 / TEST-032 of `m_aesgcm_param_check` |
| `m_aesgcm_param_check.sv` | Existing verification-only parameter checker (unchanged) |
| `tb_files.f` | Testbench file list (paths from the repository root) |
| `gcm_ref.py` | Independent SP 800-38D model on top of `../ht_aes128_256/aes128_256_ref.py`, self-test with GCM test cases 1-4 and 13-16 |
| `gen_tb_vectors.py` | Writes `vectors/<ID>.hex` for every testcase and WF scenario |
| `vlsit_test_plan.md` | Function / requirement / testcase / check matrix, section 15.2 mapping, assertion plan |
| `fault_plan.md` | Fault per integrated testcase and its detecting checker (R-096) |
| `review_ledger.md` | Engineer review ledger, all fields PENDING (R-097) |
| `probe_list.md` | Probe macros, meaning and use |
| `open_questions.md` | Questions for the specification owner |
| `waveforms_sim/waveform_compare.md` | R-033 index, to be filled by the integrator |

## Prerequisites

```
cd verification/ht_aes_gcm_acc
python gcm_ref.py                 # model self-test (must print PASS)
python gen_tb_vectors.py          # writes vectors/*.hex (seed 1; --seed n for another vector set)
mkdir -p logs waveforms_sim waveforms_test
```

## Build with Verilator 5.053

Run from the repository root. The RTL file list `rtl/ht_aes_gcm_acc/filelist.f` already contains
`+define+VLSIT_SYNTHESIS`, so a build with it is the **synthesis branch**. The **metastable branch**
needs a copy of that file list without the `+define+VLSIT_SYNTHESIS` line (for example
`rtl/ht_aes_gcm_acc/filelist_sim.f`); never define `VLSIT_SYNTHESIS` on the command line for it.

```
# (a) main build, synthesis branch
verilator --binary --timing --trace -Wno-fatal -f rtl/ht_aes_gcm_acc/filelist.f \
  -f verification/ht_aes_gcm_acc/tb_files.f --top-module tb_aesgcm_top -Mdir obj_full_syn
# (a) main build, metastable branch
verilator --binary --timing --trace -Wno-fatal -f rtl/ht_aes_gcm_acc/filelist_sim.f \
  -f verification/ht_aes_gcm_acc/tb_files.f --top-module tb_aesgcm_top -Mdir obj_full_ms
# (b) CFG-LINK (APB wrapper)
verilator --binary --timing --trace -Wno-fatal +define+TB_CFG_LINK -f rtl/ht_aes_gcm_acc/filelist.f \
  -f verification/ht_aes_gcm_acc/tb_files.f --top-module tb_aesgcm_top -Mdir obj_link
# optional: +define+TB_CFG_MIN, +define+TB_CFG_EXPORT, +define+TB_CFG_LEGACY,
#           +define+TB_CLK_ASYNC=0 (sync), +define+TB_GHASH_PIPE=1,
#           +define+TB_AXI_DATA_W=128 +define+TB_AES_LANE_NUM=1 (TEST-036 Example 5)
```

If the RTL file list uses paths relative to its own folder, adjust the working directory or the
paths; `tb_files.f` is relative to the repository root. `--trace` is needed for the VCD files. If a
row of the view is missing in a VCD, add `--public-flat-rw`.

Probes: bind the `TB_PROBE_<NAME>` macros of `probe_list.md` with `+define+` and add
`+define+TB_PROBES_BOUND`; until then the probe-based assertions are reported as inapplicable.

## Run

Run the binary from `verification/ht_aes_gcm_acc` (vectors and waveform folders are relative), or pass
`+VEC_DIR=<path>`. Keep one log per run in `logs/`, named with the build, branch and seed.

```
cd verification/ht_aes_gcm_acc
B=../../obj_full_syn/Vtb_aesgcm_top
$B +TEST=ALL +SEED=1                         > logs/full_syn_all_s1.log      # full regression
$B +TEST=TC-01 +SEED=7                       > logs/full_syn_TC-01_s7.log    # one testcase
$B +TEST=TC +SEED=3                          > logs/full_syn_tc_s3.log       # integrated group
$B +TEST=WF-006                              > logs/full_syn_WF-006.log      # writes waveforms_sim/WF-006_axi_write.vcd
$B +TEST=TC-09 +SEED=2 +DUMP                 > logs/full_syn_TC-09_s2.log    # per-test VCD in waveforms_test/
M=../../obj_full_ms/Vtb_aesgcm_top
for n in 1 2 3; do $M +TEST=ALL +SEED=$n +AFIFO_MSYNC_SEED=$n > logs/full_ms_all_s$n.log; done
# synchronous build (+define+TB_CLK_ASYNC=0, -Mdir obj_sync): TEST-023 and WF-016
S=../../obj_sync/Vtb_aesgcm_top
for r in 1_1 3_2 4_1 1_4; do $S +TEST=TC-14 +CLK_RATIO=$r > logs/sync_TC-14_$r.log; done
$S +TEST=WF-016 +CLK_RATIO=3_2 > logs/sync_WF-016.log
```

Useful plusargs: `+APB_GAP=<n>`, `+AXI_WGAP=<n>`, `+AXI_BREADY_DLY=<n>`, `+AXI_RREADY_DLY=<n>`,
`+AXI_RAND_STRB`, `+DMA_ACK_DLY=<n>` (slow acknowledge: 8 or more), `+TBUS_PS=<n>`, `+TCORE_PS=<n>`,
`+TIMEOUT_MS=<n>`. Every random choice derives from `+SEED`; a run is replayed with the same build,
seed, plusargs and vector files.

Each log starts with `SIM-BRANCH: synthesis` or `SIM-BRANCH: metastable seed=<n>` (R-093), prints
`CHECK <id> PASS|FAIL` lines, one `==== RESULT <ID>: PASS|FAIL|SKIP` per testcase, the testcase summary,
the assertion table, and ends with `assertion failures: <n>, assertions never exercised: <m>`. The run
calls `$fatal` (non-zero exit) when a testcase fails, an assertion fails or, for `+TEST=ALL`, an
applicable assertion was never exercised. SKIP lines carry the reason from the specification.

Parameter legality (TEST-025, TEST-032): one lint run per set of `tb_param_check_top.sv`, for example
`verilator --lint-only +define+PC_LANE5 verification/ht_aes_gcm_acc/m_aesgcm_param_check.sv
verification/ht_aes_gcm_acc/tb_param_check_top.sv --top-module tb_param_check_top` must stop with the
checker message; `PC_LEGAL` (no define) must pass.

## Build notes (Windows, Verilator 5.053)

- The testbench tasks are inlined by Verilator into one very large C++ function. To keep the
  compile within memory, build from a copy of this folder in which every `task` header is followed by
  `/*verilator no_inline_task*/`, and add `-Wno-IMPURE --output-split 8000 --output-split-cfuncs 800`.
  The sources in this folder are not modified for that.
- Run the generated binary from this folder. A complete CFG-FULL run takes about 19 minutes.

## Regression results (2026-11-27, seed 1, Verilator 5.053, RTL of DEC-001 to DEC-039)

Every run is `+TEST=ALL`; a run exits with 0 only when no test fails, no assertion fails and no
applicable assertion is left unexercised (R-025). `SKIP` is a test that does not apply to the build.

| Build | Defines | PASS | FAIL | SKIP | Assertion failures | Never exercised |
|---|---|---|---|---|---|---|
| FULL (synthesis branch) | none | 49 | 0 | 5 | 0 | 0 |
| FULL, metastability model, seeds 1, 2, 3 | filelist without `VLSIT_SYNTHESIS`, `+AFIFO_MSYNC_SEED=n` | 49 each | 0 | 5 | 0 | 0 |
| LINK (APB wrapper) | `TB_CFG_LINK` | 33 | 0 | 21 | 0 | 0 |
| MIN | `TB_CFG_MIN` | 32 | 0 | 22 | 0 | 0 |
| LEGACY (no GCM) | `TB_CFG_LEGACY` | 10 | 0 | 44 | 0 | 0 |
| EXPORT (context export) | `TB_CFG_EXPORT` | 50 | 0 | 4 | 0 | 0 |
| AXI 128-bit, one lane | `TB_AXI_DATA_W=128 TB_AES_LANE_NUM=1` | 46 | 0 | 8 | 0 | 0 |
| Synchronous clocks 1:4 | `TB_CLK_ASYNC=0 +CLK_RATIO=1_4` | 49 | 0 | 5 | 0 | 0 |
| Synchronous clocks 3:2 | `TB_CLK_ASYNC=0 +CLK_RATIO=3_2` | 50 | 0 | 4 | 0 | 0 |
| TC-14 alone, ratios 1:1, 3:2, 4:1, 1:4, and WF-016 at 3:2 | `TB_CLK_ASYNC=0` | all PASS | 0 | 0 | 0 | not a full run |

`vlsit_sim_evidence.py cdc` (R-034) passes on the logs of the synthesis branch and of the three
metastability seeds. The simulations ran on a copy of this folder in which `/*verilator no_inline_task*/`
follows every task header (see Build notes); the committed sources are unchanged.

Not done yet: the waveform evidence of R-033 (dumps, WaveJSON and comparison with the specification
figure for every WF scenario: `vlsit_sim_evidence.py check` reports the missing files), the fault
detection run of `fault_plan.md` (R-096), coverage closure, the probe-based assertions (probes not
bound) and the engineer review (`review_ledger.md`, PENDING).

## Probes and waveform evidence

`tb_probe_bind.svh` binds the probe placeholders of `probe_list.md` to the RTL (build with
`+define+TB_PROBE_BIND`, plus `+define+TB_PROBE_HAS_CTX` when the build has the context engine; not for
CFG-LEGACY). Three probes are not exposed by the RTL and read 0: `OUT_FIFO_LEVEL`, `GHASH_PP_VALID`,
`GHASH_EXP_LANE`. With the binding the probe assertions run (INT-01, POL-03, SEC-01, SEC-02, XING-01, XING-02, and the
probe checks of FT-030 and FT-031): the probe-bound FULL run (seed 1) gives 49 PASS, 0 FAIL, 0 assertion
failures and no assertion left unexercised. The first probe-bound run showed 4 failures of INT-01 in TC-13;
they came from the testbench: after a BUS-domain reset the shadow of `aesgcm_irq_en` was cleared only when the
task returned, 128 ns after the DUT register was reset (fixed in `do_reset` and `do_reset_one`).

`+TEST=WF-nnn` writes `waveforms_sim/<figure stem>.vcd` (git-ignored, regenerate it). `wfevidence.py <repo>
<waveforms_sim> <waveform_compare.md>` converts each window to WaveJSON and SVG with the tools of the
skill and screens the order of the first transitions against the figure of the specification; the
rows marked DIFFERENT are the screening result and still need the analysis of rule R-026 by the designer.

## Assertion classes

An assertion failure counts in `assertion failures`. APB-17 (PSLVERR low outside the last cycle of a
transfer) is a rule that IHI0024D 3.4 only recommends; its violations are listed as `REC` in the
assertion table and in `ASSERT RECOMMENDED` lines and are not failures (decision of 2026-11-27).

## Evidence layout

| Folder / file | Content | Owner |
|---|---|---|
| `logs/` | one log per build, branch, testcase group and seed | integrator |
| `waveforms_sim/<figure stem>.vcd` | window of WF-nnn (synthesis branch), plus `.json` and `.svg` rendered with the same stem | integrator |
| `waveforms_sim/waveform_compare.md` | MATCH / DIFFERENT / NOT-SIMULATED per WF row with notes (R-033, R-090) | integrator |
| `waveforms_test/<ID>_seed<n>.vcd` | per-testcase waveform (R-097), `+DUMP` | integrator |
| `review_ledger.md` | reviewer, date, hashes, findings, disposition per testcase and waveform | verification engineer |
| `fault_plan.md` | fault-injection results on a disposable DUT copy (R-096) | integrator |

A failing check or assertion whose cause is not clear is analyzed with the table of section 5 of the
testbench guide (specification text, RTL behavior, test, candidates) and the designer decides before
the RTL or the test is changed (R-026).
