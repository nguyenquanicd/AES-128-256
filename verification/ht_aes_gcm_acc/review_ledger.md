# Engineer review ledger (rule R-097)

One row per testcase and per waveform scenario. The AI author leaves every human field PENDING; a named hardware verification engineer records the reviewer, date, hashes, findings and disposition after reviewing the testcase source, its actual results and every generated waveform against the specification. Pending or rejected rows block human sign-off. Hashes are SHA-256 of the file at the reviewed revision; run ID = log file name in `logs/`.

## Testcases

| Test ID | Source file | Source hash | Build | Seed | Run ID | Result | Per-test waveform | Waveform hash | Checker outcomes | Fault result (fault_plan.md) | Reviewer | Date | Findings | Disposition |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| TC-01 | tb_aesgcm_tests_tc.svh | PENDING | PENDING | PENDING | PENDING | NOT-RUN | waveforms_test/TC-01_seed<n>.vcd | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING |
| TC-02 | tb_aesgcm_tests_tc.svh | PENDING | PENDING | PENDING | PENDING | NOT-RUN | waveforms_test/TC-02_seed<n>.vcd | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING |
| TC-03 | tb_aesgcm_tests_tc.svh | PENDING | PENDING | PENDING | PENDING | NOT-RUN | waveforms_test/TC-03_seed<n>.vcd | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING |
| TC-04 | tb_aesgcm_tests_tc.svh | PENDING | PENDING | PENDING | PENDING | NOT-RUN | waveforms_test/TC-04_seed<n>.vcd | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING |
| TC-05 | tb_aesgcm_tests_tc.svh | PENDING | PENDING | PENDING | PENDING | NOT-RUN | waveforms_test/TC-05_seed<n>.vcd | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING |
| TC-06 | tb_aesgcm_tests_tc.svh | PENDING | PENDING | PENDING | PENDING | NOT-RUN | waveforms_test/TC-06_seed<n>.vcd | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING |
| TC-07 | tb_aesgcm_tests_tc.svh | PENDING | PENDING | PENDING | PENDING | NOT-RUN | waveforms_test/TC-07_seed<n>.vcd | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING |
| TC-08 | tb_aesgcm_tests_tc.svh | PENDING | PENDING | PENDING | PENDING | NOT-RUN | waveforms_test/TC-08_seed<n>.vcd | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING |
| TC-09 | tb_aesgcm_tests_tc2.svh | PENDING | PENDING | PENDING | PENDING | NOT-RUN | waveforms_test/TC-09_seed<n>.vcd | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING |
| TC-10 | tb_aesgcm_tests_tc2.svh | PENDING | PENDING | PENDING | PENDING | NOT-RUN | waveforms_test/TC-10_seed<n>.vcd | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING |
| TC-11 | tb_aesgcm_tests_tc2.svh | PENDING | PENDING | PENDING | PENDING | NOT-RUN | waveforms_test/TC-11_seed<n>.vcd | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING |
| TC-12 | tb_aesgcm_tests_tc2.svh | PENDING | PENDING | PENDING | PENDING | NOT-RUN | waveforms_test/TC-12_seed<n>.vcd | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING |
| TC-13 | tb_aesgcm_tests_tc2.svh | PENDING | PENDING | PENDING | PENDING | NOT-RUN | waveforms_test/TC-13_seed<n>.vcd | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING |
| TC-14 | tb_aesgcm_tests_tc2.svh | PENDING | PENDING | PENDING | PENDING | NOT-RUN | waveforms_test/TC-14_seed<n>.vcd | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING |
| TC-15 | tb_aesgcm_tests_tc2.svh | PENDING | PENDING | PENDING | PENDING | NOT-RUN | waveforms_test/TC-15_seed<n>.vcd | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING |
| FT-011 | tb_aesgcm_tests_ft.svh | PENDING | PENDING | PENDING | PENDING | NOT-RUN | waveforms_test/FT-011_seed<n>.vcd | PENDING | PENDING | n/a (focused) | PENDING | PENDING | PENDING | PENDING |
| FT-012 | tb_aesgcm_tests_ft.svh | PENDING | PENDING | PENDING | PENDING | NOT-RUN | waveforms_test/FT-012_seed<n>.vcd | PENDING | PENDING | n/a (focused) | PENDING | PENDING | PENDING | PENDING |
| FT-013 | tb_aesgcm_tests_ft.svh | PENDING | PENDING | PENDING | PENDING | NOT-RUN | waveforms_test/FT-013_seed<n>.vcd | PENDING | PENDING | n/a (focused) | PENDING | PENDING | PENDING | PENDING |
| FT-014 | tb_aesgcm_tests_ft.svh | PENDING | PENDING | PENDING | PENDING | NOT-RUN | waveforms_test/FT-014_seed<n>.vcd | PENDING | PENDING | n/a (focused) | PENDING | PENDING | PENDING | PENDING |
| FT-015 | tb_aesgcm_tests_ft.svh | PENDING | PENDING | PENDING | PENDING | NOT-RUN | waveforms_test/FT-015_seed<n>.vcd | PENDING | PENDING | n/a (focused) | PENDING | PENDING | PENDING | PENDING |
| FT-016 | tb_aesgcm_tests_ft.svh | PENDING | PENDING | PENDING | PENDING | NOT-RUN | waveforms_test/FT-016_seed<n>.vcd | PENDING | PENDING | n/a (focused) | PENDING | PENDING | PENDING | PENDING |
| FT-018 | tb_aesgcm_tests_ft.svh | PENDING | PENDING | PENDING | PENDING | NOT-RUN | waveforms_test/FT-018_seed<n>.vcd | PENDING | PENDING | n/a (focused) | PENDING | PENDING | PENDING | PENDING |
| FT-026 | tb_aesgcm_tests_ft.svh | PENDING | PENDING | PENDING | PENDING | NOT-RUN | waveforms_test/FT-026_seed<n>.vcd | PENDING | PENDING | n/a (focused) | PENDING | PENDING | PENDING | PENDING |
| FT-028 | tb_aesgcm_tests_ft.svh | PENDING | PENDING | PENDING | PENDING | NOT-RUN | waveforms_test/FT-028_seed<n>.vcd | PENDING | PENDING | n/a (focused) | PENDING | PENDING | PENDING | PENDING |
| FT-029 | tb_aesgcm_tests_ft.svh | PENDING | PENDING | PENDING | PENDING | NOT-RUN | waveforms_test/FT-029_seed<n>.vcd | PENDING | PENDING | n/a (focused) | PENDING | PENDING | PENDING | PENDING |
| FT-030 | tb_aesgcm_tests_ft.svh | PENDING | PENDING | PENDING | PENDING | NOT-RUN | waveforms_test/FT-030_seed<n>.vcd | PENDING | PENDING | n/a (focused) | PENDING | PENDING | PENDING | PENDING |
| FT-031 | tb_aesgcm_tests_ft.svh | PENDING | PENDING | PENDING | PENDING | NOT-RUN | waveforms_test/FT-031_seed<n>.vcd | PENDING | PENDING | n/a (focused) | PENDING | PENDING | PENDING | PENDING |
| FT-033 | tb_aesgcm_tests_ft.svh | PENDING | PENDING | PENDING | PENDING | NOT-RUN | waveforms_test/FT-033_seed<n>.vcd | PENDING | PENDING | n/a (focused) | PENDING | PENDING | PENDING | PENDING |
| FT-036 | tb_aesgcm_tests_ft.svh | PENDING | PENDING | PENDING | PENDING | NOT-RUN | waveforms_test/FT-036_seed<n>.vcd | PENDING | PENDING | n/a (focused) | PENDING | PENDING | PENDING | PENDING |

## Waveform scenarios (R-033 evidence, separate from the per-test waveforms)

| WF ID | Source | Specification figure | Simulated VCD | VCD hash | WaveJSON / SVG | Compare result | Reviewer | Date | Findings | Disposition |
|---|---|---|---|---|---|---|---|---|---|---|
| WF-001 | tb_aesgcm_wf.svh | doc/ht_aes_gcm_acc/figures/WF-001_start_bundle.svg | waveforms_sim/WF-001_start_bundle.vcd | PENDING | waveforms_sim/WF-001_start_bundle.json / .svg | NOT-SIMULATED | PENDING | PENDING | PENDING | PENDING |
| WF-002 | tb_aesgcm_wf.svh | doc/ht_aes_gcm_acc/figures/WF-002_gcm_encrypt.svg | waveforms_sim/WF-002_gcm_encrypt.vcd | PENDING | waveforms_sim/WF-002_gcm_encrypt.json / .svg | NOT-SIMULATED | PENDING | PENDING | PENDING | PENDING |
| WF-003 | tb_aesgcm_wf.svh | doc/ht_aes_gcm_acc/figures/WF-003_pass1_fail.svg | waveforms_sim/WF-003_pass1_fail.vcd | PENDING | waveforms_sim/WF-003_pass1_fail.json / .svg | NOT-SIMULATED | PENDING | PENDING | PENDING | PENDING |
| WF-004 | tb_aesgcm_wf.svh | doc/ht_aes_gcm_acc/figures/WF-004_pass2.svg | waveforms_sim/WF-004_pass2.vcd | PENDING | waveforms_sim/WF-004_pass2.json / .svg | NOT-SIMULATED | PENDING | PENDING | PENDING | PENDING |
| WF-005 | tb_aesgcm_wf.svh | doc/ht_aes_gcm_acc/figures/WF-005_secure_only.svg | waveforms_sim/WF-005_secure_only.vcd | PENDING | waveforms_sim/WF-005_secure_only.json / .svg | NOT-SIMULATED | PENDING | PENDING | PENDING | PENDING |
| WF-006 | tb_aesgcm_wf.svh | doc/ht_aes_gcm_acc/figures/WF-006_axi_write.svg | waveforms_sim/WF-006_axi_write.vcd | PENDING | waveforms_sim/WF-006_axi_write.json / .svg | NOT-SIMULATED | PENDING | PENDING | PENDING | PENDING |
| WF-007 | tb_aesgcm_wf.svh | doc/ht_aes_gcm_acc/figures/WF-007_axi_wrap.svg | waveforms_sim/WF-007_axi_wrap.vcd | PENDING | waveforms_sim/WF-007_axi_wrap.json / .svg | NOT-SIMULATED | PENDING | PENDING | PENDING | PENDING |
| WF-008 | tb_aesgcm_wf.svh | doc/ht_aes_gcm_acc/figures/WF-008_axi_read.svg | waveforms_sim/WF-008_axi_read.vcd | PENDING | waveforms_sim/WF-008_axi_read.json / .svg | NOT-SIMULATED | PENDING | PENDING | PENDING | PENDING |
| WF-009 | tb_aesgcm_wf.svh | doc/ht_aes_gcm_acc/figures/WF-009_dma_hs.svg | waveforms_sim/WF-009_dma_hs.vcd | PENDING | waveforms_sim/WF-009_dma_hs.json / .svg | NOT-SIMULATED | PENDING | PENDING | PENDING | PENDING |
| WF-010 | tb_aesgcm_wf.svh | doc/ht_aes_gcm_acc/figures/WF-010_pio_overrun.svg | waveforms_sim/WF-010_pio_overrun.vcd | PENDING | waveforms_sim/WF-010_pio_overrun.json / .svg | NOT-SIMULATED | PENDING | PENDING | PENDING | PENDING |
| WF-011 | tb_aesgcm_wf.svh | doc/ht_aes_gcm_acc/figures/WF-011_key_side.svg | waveforms_sim/WF-011_key_side.vcd | PENDING | waveforms_sim/WF-011_key_side.json / .svg | NOT-SIMULATED | PENDING | PENDING | PENDING | PENDING |
| WF-012 | tb_aesgcm_wf.svh | doc/ht_aes_gcm_acc/figures/WF-012_suspend_resume.svg | waveforms_sim/WF-012_suspend_resume.vcd | PENDING | waveforms_sim/WF-012_suspend_resume.json / .svg | NOT-SIMULATED | PENDING | PENDING | PENDING | PENDING |
| WF-013 | tb_aesgcm_wf.svh | doc/ht_aes_gcm_acc/figures/WF-013_abort.svg | waveforms_sim/WF-013_abort.vcd | PENDING | waveforms_sim/WF-013_abort.json / .svg | NOT-SIMULATED | PENDING | PENDING | PENDING | PENDING |
| WF-014 | tb_aesgcm_wf.svh | doc/ht_aes_gcm_acc/figures/WF-014_zeroize.svg | waveforms_sim/WF-014_zeroize.vcd | PENDING | waveforms_sim/WF-014_zeroize.json / .svg | NOT-SIMULATED | PENDING | PENDING | PENDING | PENDING |
| WF-015 | tb_aesgcm_wf.svh | doc/ht_aes_gcm_acc/figures/WF-015_interrupt.svg | waveforms_sim/WF-015_interrupt.vcd | PENDING | waveforms_sim/WF-015_interrupt.json / .svg | NOT-SIMULATED | PENDING | PENDING | PENDING | PENDING |
| WF-016 | tb_aesgcm_wf.svh | doc/ht_aes_gcm_acc/figures/WF-016_sync_ratio.svg | waveforms_sim/WF-016_sync_ratio.vcd | PENDING | waveforms_sim/WF-016_sync_ratio.json / .svg | NOT-SIMULATED | PENDING | PENDING | PENDING | PENDING |
| WF-017 | tb_aesgcm_wf.svh | doc/ht_aes_gcm_acc/figures/WF-017_ghash_partial.svg | waveforms_sim/WF-017_ghash_partial.vcd | PENDING | waveforms_sim/WF-017_ghash_partial.json / .svg | NOT-SIMULATED | PENDING | PENDING | PENDING | PENDING |
| WF-018 | tb_aesgcm_wf.svh | doc/ht_aes_gcm_acc/figures/WF-018_reset.svg | waveforms_sim/WF-018_reset.vcd | PENDING | waveforms_sim/WF-018_reset.json / .svg | NOT-SIMULATED | PENDING | PENDING | PENDING | PENDING |
| WF-019 | tb_aesgcm_wf.svh | doc/ht_aes_gcm_acc/figures/WF-019_legacy_ctr.svg | waveforms_sim/WF-019_legacy_ctr.vcd | PENDING | waveforms_sim/WF-019_legacy_ctr.json / .svg | NOT-SIMULATED | PENDING | PENDING | PENDING | PENDING |
| WF-020 | tb_aesgcm_wf.svh | doc/ht_aes_gcm_acc/figures/WF-020_gmac.svg | waveforms_sim/WF-020_gmac.vcd | PENDING | waveforms_sim/WF-020_gmac.json / .svg | NOT-SIMULATED | PENDING | PENDING | PENDING | PENDING |
| WF-021 | tb_aesgcm_wf.svh | doc/ht_aes_gcm_acc/figures/WF-021_ctx_export.svg | waveforms_sim/WF-021_ctx_export.vcd | PENDING | waveforms_sim/WF-021_ctx_export.json / .svg | NOT-SIMULATED | PENDING | PENDING | PENDING | PENDING |
| WF-022 | tb_aesgcm_wf.svh | doc/ht_aes_gcm_acc/figures/WF-022_ghash_pipe.svg | waveforms_sim/WF-022_ghash_pipe.vcd | PENDING | waveforms_sim/WF-022_ghash_pipe.json / .svg | NOT-SIMULATED | PENDING | PENDING | PENDING | PENDING |
| WF-023 | tb_aesgcm_wf.svh | doc/ht_aes_gcm_acc/figures/WF-023_cmd_ack.svg | waveforms_sim/WF-023_cmd_ack.vcd | PENDING | waveforms_sim/WF-023_cmd_ack.json / .svg | NOT-SIMULATED | PENDING | PENDING | PENDING | PENDING |
