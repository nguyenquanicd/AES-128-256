# Waveform comparison / waveform đối chiếu

Result is measured by compare_waveforms.py (signal presence, never-high signals, rising-edge order against the approved figure); data and latency are checked by the testbench, listed in Note. / Result do compare_waveforms.py đo (có tín hiệu, tín hiệu không bao giờ lên cao, thứ tự cạnh lên so với hình đã duyệt); dữ liệu và latency do testbench kiểm, ghi ở cột Note.

| WF-ID | Specification figure | Simulated VCD | Result | Note |
|---|---|---|---|---|
| WF-001 | [figure](../../../doc/ht_aes128_256/figures/waveforms/WF-001_config_key_select.svg) | WF-001_config_key_select.vcd | MATCH | Handshakes and error 1 only; no data compare. |
| WF-002 | [figure](../../../doc/ht_aes128_256/figures/waveforms/WF-002_aes128_ecb.svg) | WF-002_aes128_ecb.vcd | MATCH | Golden data, C10 latency, II=1 inputs and outputs. |
| WF-003 | [figure](../../../doc/ht_aes128_256/figures/waveforms/WF-003_aes256_ecb.svg) | WF-003_aes256_ecb.vcd | MATCH | Golden data, C14 latency, II=1 inputs and outputs. |
| WF-004 | [figure](../../../doc/ht_aes128_256/figures/waveforms/WF-004_ctr_allocate.svg) | WF-004_ctr_allocate.vcd | MATCH | Golden data and lane mask. |
| WF-005 | [figure](../../../doc/ht_aes128_256/figures/waveforms/WF-005_ctr_wrap.svg) | WF-005_ctr_wrap.vcd | MATCH | Error 3, error accepted and cleared; no data compare. |
| WF-006 | [figure](../../../doc/ht_aes128_256/figures/waveforms/WF-006a_cbc_decrypt.svg) | WF-006a_cbc_decrypt.vcd | MATCH | Golden data, lane mask, last. |
| WF-007 | [figure](../../../doc/ht_aes128_256/figures/waveforms/WF-007_cbc_encrypt_feedback.svg) | WF-007_cbc_encrypt_feedback.vcd | MATCH | Golden data, C10 latency, C11 feedback interval. |
| WF-008 | [figure](../../../doc/ht_aes128_256/figures/waveforms/WF-008_cfb_feedback.svg) | WF-008_cfb_feedback.vcd | MATCH | Golden data, C14 latency, C15 feedback interval. |
| WF-009 | [figure](../../../doc/ht_aes128_256/figures/waveforms/WF-009_ofb_feedback.svg) | WF-009_ofb_feedback.vcd | MATCH | Golden data, C14 latency, C15 feedback interval. |
| WF-010 | [figure](../../../doc/ht_aes128_256/figures/waveforms/WF-010a_backpressure.svg) | WF-010a_backpressure.vcd | MATCH | Golden data; output held for one stalled cycle. |
| WF-011 | [figure](../../../doc/ht_aes128_256/figures/waveforms/WF-011_lane_mask_error.svg) | WF-011_lane_mask_error.vcd | MATCH | Error codes 2 and 5 only. |
| WF-012 | [figure](../../../doc/ht_aes128_256/figures/waveforms/WF-012a_reset_abort.svg) | WF-012a_reset_abort.vcd | MATCH | Valid/error cleared; zeroize done pulse. |
