# Waveform comparison index (rule R-033)

To be filled by the integrator after the synthesis-branch runs `+TEST=WF-nnn` (one run per row; the
VCD is written to this folder with the stem of the specification figure). Convert each VCD window to
WaveJSON and SVG with the same stem (skill `vlsit-wavedrom-waveform`, `vlsit_waveform_svg.py`), then
set the result to MATCH, DIFFERENT (with the R-026 analysis and the designer decision) or
NOT-SIMULATED (with the reason). Internal rows need the probes of `../probe_list.md` to be bound.
Nothing in this table has been simulated yet.

| Waveform ID | Specification figure | Simulated waveform | Result | Note |
|---|---|---|---|---|
| WF-001 | doc/ht_aes_gcm_acc/figures/WF-001_start_bundle.svg | waveforms_sim/WF-001_start_bundle.svg | NOT-SIMULATED | not yet run |
| WF-002 | doc/ht_aes_gcm_acc/figures/WF-002_gcm_encrypt.svg | waveforms_sim/WF-002_gcm_encrypt.svg | NOT-SIMULATED | not yet run; figure is 1 lane, compare in CFG-LINK or with TB_AES_LANE_NUM=1 |
| WF-003 | doc/ht_aes_gcm_acc/figures/WF-003_pass1_fail.svg | waveforms_sim/WF-003_pass1_fail.svg | NOT-SIMULATED | not yet run; needs policy A (CFG-FULL, CFG-MIN) |
| WF-004 | doc/ht_aes_gcm_acc/figures/WF-004_pass2.svg | waveforms_sim/WF-004_pass2.svg | NOT-SIMULATED | not yet run; needs policy A |
| WF-005 | doc/ht_aes_gcm_acc/figures/WF-005_secure_only.svg | waveforms_sim/WF-005_secure_only.svg | NOT-SIMULATED | not yet run; needs policy C |
| WF-006 | doc/ht_aes_gcm_acc/figures/WF-006_axi_write.svg | waveforms_sim/WF-006_axi_write.svg | NOT-SIMULATED | not yet run; AXI wrapper |
| WF-007 | doc/ht_aes_gcm_acc/figures/WF-007_axi_wrap.svg | waveforms_sim/WF-007_axi_wrap.svg | NOT-SIMULATED | not yet run; AXI wrapper |
| WF-008 | doc/ht_aes_gcm_acc/figures/WF-008_axi_read.svg | waveforms_sim/WF-008_axi_read.svg | NOT-SIMULATED | not yet run; AXI wrapper |
| WF-009 | doc/ht_aes_gcm_acc/figures/WF-009_dma_hs.svg | waveforms_sim/WF-009_dma_hs.svg | NOT-SIMULATED | not yet run |
| WF-010 | doc/ht_aes_gcm_acc/figures/WF-010_pio_overrun.svg | waveforms_sim/WF-010_pio_overrun.svg | NOT-SIMULATED | not yet run |
| WF-011 | doc/ht_aes_gcm_acc/figures/WF-011_key_side.svg | waveforms_sim/WF-011_key_side.svg | NOT-SIMULATED | not yet run; needs PARA_KEY_SIDE_EN = 1 |
| WF-012 | doc/ht_aes_gcm_acc/figures/WF-012_suspend_resume.svg | waveforms_sim/WF-012_suspend_resume.svg | NOT-SIMULATED | not yet run; needs context slots |
| WF-013 | doc/ht_aes_gcm_acc/figures/WF-013_abort.svg | waveforms_sim/WF-013_abort.svg | NOT-SIMULATED | not yet run |
| WF-014 | doc/ht_aes_gcm_acc/figures/WF-014_zeroize.svg | waveforms_sim/WF-014_zeroize.svg | NOT-SIMULATED | not yet run |
| WF-015 | doc/ht_aes_gcm_acc/figures/WF-015_interrupt.svg | waveforms_sim/WF-015_interrupt.svg | NOT-SIMULATED | not yet run |
| WF-016 | doc/ht_aes_gcm_acc/figures/WF-016_sync_ratio.svg | waveforms_sim/WF-016_sync_ratio.svg | NOT-SIMULATED | not yet run; needs +define+TB_CLK_ASYNC=0 and +CLK_RATIO=3_2 |
| WF-017 | doc/ht_aes_gcm_acc/figures/WF-017_ghash_partial.svg | waveforms_sim/WF-017_ghash_partial.svg | NOT-SIMULATED | not yet run; ARCH 2, 4 lanes |
| WF-018 | doc/ht_aes_gcm_acc/figures/WF-018_reset.svg | waveforms_sim/WF-018_reset.svg | NOT-SIMULATED | not yet run |
| WF-019 | doc/ht_aes_gcm_acc/figures/WF-019_legacy_ctr.svg | waveforms_sim/WF-019_legacy_ctr.svg | NOT-SIMULATED | not yet run |
| WF-020 | doc/ht_aes_gcm_acc/figures/WF-020_gmac.svg | waveforms_sim/WF-020_gmac.svg | NOT-SIMULATED | not yet run |
| WF-021 | doc/ht_aes_gcm_acc/figures/WF-021_ctx_export.svg | waveforms_sim/WF-021_ctx_export.svg | NOT-SIMULATED | not yet run; needs the export build (TB_CFG_EXPORT) |
| WF-022 | doc/ht_aes_gcm_acc/figures/WF-022_ghash_pipe.svg | waveforms_sim/WF-022_ghash_pipe.svg | NOT-SIMULATED | not yet run; row ghash_y_pipe1 needs +define+TB_GHASH_PIPE=1, row ghash_y_pipe0 the default build |
| WF-023 | doc/ht_aes_gcm_acc/figures/WF-023_cmd_ack.svg | waveforms_sim/WF-023_cmd_ack.svg | NOT-SIMULATED | not yet run |
