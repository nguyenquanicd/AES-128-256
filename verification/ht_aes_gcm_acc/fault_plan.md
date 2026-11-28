# Fault qualification plan (rule R-096)

For every integrated testcase: one plausible fault, described by its observable behavior, and the named
checker expected to detect it. The integrator implements each fault on a **disposable copy** of the DUT
(the delivered RTL stays unchanged), runs the testcase with the baseline seed, and records the actual
mismatch, the run ID and the verdict. A compile failure, a crash, a watchdog time-out or an unrelated
assertion does not qualify. The campaign ran on 2026-11-28 (see `fault_results.md`: 21 of the 24 faults detected by the named checker, 3 not detected).

| Testcase | Injected fault (observable behavior) | Expected detecting checker(s) | Secondary checkers | Result |
|---|---|---|---|---|
| TC-01 | Policy A pass 1 writes the decrypted blocks to the output FIFO (output enable not gated by the pass) | POL-01 / POL-02 (and POL-03 with probes), TC01-C2 (out_empty = 0) | TC01-C5 (stream offset in pass 2) | DETECTED by TC01-C2 (see fault_results.md) |
| TC-01 (alt.) | Pass 2 accepted after key_new (verified context not invalidated) | TC01-C9 (no PROTO_ERR) | - | NOT DETECTED (see fault_results.md) |
| TC-02 | Tag bit 0 inverted in the policy C comparison (forged tag accepted) | TC02-C2 (no TAG_FAIL), TC02-C3 (failcnt stays 0) | TC02-C6 | DETECTED by TC02-C2, TC02-C3 (see fault_results.md) |
| TC-03 | `i_gcm_secure_only` ignored by the legality check | TC03-C2 (no CFG_ERR), POL-04 (plaintext output while blocked) | TC03-C3 | DETECTED by TC03-C2 (see fault_results.md) |
| TC-04 | Tag compare uses all 128 bits regardless of `tag_len` | TC04-C5 (tag differing after bit t fails) | TC04-C1 if tagout is also masked | DETECTED by TC04-C5 (see fault_results.md) |
| TC-05 | GHASH length block uses len(A) = 0 (AAD bit length omitted) | TC05-C2 (tag mismatch on every AAD > 0 record), TC05-C5 (NIST TC4/TC16) | - | DETECTED by TC05-C2, TC05-C5 (see fault_results.md) |
| TC-05 (alt.) | Last partial payload block not masked: output padding carries keystream | TC05-C3 (padding nonzero) | TC05-C1 | DETECTED by TC05-C3 (see fault_results.md) |
| TC-06 | Saved next counter not incremented for the blocks consumed before the suspend (counter restarts at inc32(J0)) | TC06-C4 (second half of the ciphertext differs) | TC06-C1 if counts are derived from it | DETECTED by TC06-C4 (see fault_results.md) |
| TC-07 | Resume loads slot 0 whatever `ctx_id` is | TC07-C3 (slot 1 message wrong), TC07-C2 | TC07-C4 | DETECTED by TC07-C3 (see fault_results.md) |
| TC-08 | Abort also clears the key store | TC08-C3 (message without key_new wrong or rejected) | TC08-C1 | DETECTED by TC08-C3 (see fault_results.md) |
| TC-08 (alt.) | Zeroize leaves `key_ld` = 1 and allows a GCM start without key_new | TC08-C5, TC08-C6 | SEC-01 with probes | DETECTED by TC08-C5, TC08-C6 (see fault_results.md) |
| TC-09 | WRAP write burst beats pushed into the input FIFO (drop flag ignored) | TC09-C4 (ciphertext differs), AXI-16 (BRESP OKAY instead of SLVERR) | TC09-C1 | DETECTED by TC09-C4, AXI-16 (see fault_results.md) |
| TC-09 (alt.) | BID returns 0 instead of AWID | AXI-14, TC09-C1/C3 | - | DETECTED by AXI-14, TC09-C1, TC09-C3 (see fault_results.md) |
| TC-10 | DMA input request withdrawn before acknowledge (request follows the room condition) | DMA-IN-01 | DMA-IN-04 (TB ack without request) | DETECTED by DMA-IN-01 (see fault_results.md) |
| TC-10 (alt.) | Output request raised with fewer beats than a burst available | DMA-OUT-12 (burst not complete within bound, AXI path) or TC10-C4 (PIO underrun PROTO_ERR) | TC10-C1 | DETECTED by TC10-C4 (see fault_results.md) |
| TC-11 | CFB-1 output byte uses bit 0 instead of bit 7 (DEC-021 justification reversed) | TC11-C2 | - | DETECTED by TC11-C2 (see fault_results.md) |
| TC-11 (alt.) | `aesgcm_err_code` not cleared at the next start | TC11-C5 | - | DETECTED by TC11-C5 (see fault_results.md) |
| TC-12 | `o_int_aesgcm` driven by the raw register (enable ignored) | TC12-C2, INT-04 | INT-01 with probes | DETECTED by TC12-C2, INT-04 (see fault_results.md) |
| TC-12 (alt.) | `aesgcm_irq_inj` bit 9 maps to raw bit 8 | TC12-C1 | - | DETECTED by TC12-C1 (see fault_results.md) |
| TC-13 | CORE key store has no reset (keeps the key over reset) | TC13-C3 (GCM start accepted without key_new) | TC13-C1 (`key_ld` = 1) | NOT DETECTED as defined (CORE-only key store); detected by TC13-C3 only if the BUS key-new latch also survives (see fault_results.md) |
| TC-13 (alt.) | DMA request output not reset (holds 1 during reset) | DMA-IN-07, TC13-C2 | - | DETECTED by DMA-IN-07 (see fault_results.md) |
| TC-14 | Bundle captured one CORE edge too early in synchronous mode (data captured before stable) - emulate by capturing the previous bundle | TC14-C1/C2 (wrong IV or length used) | XING-01 with probes | DETECTED by TC14-C1, TC14-C2 (see fault_results.md) |
| TC-14 (alt.) | Status crossing tears `aesgcm_tagout` (words from two reports) | TC14-C4 or TC14-C2 | - | DETECTED by TC14-C2 (see fault_results.md) |
| TC-15 | Sequencer inserts 64 idle core clocks before the length block | TC15-C1/C2 (latency above the PERF-001 bound) | - | NOT DETECTED (bound slack above 64 core clocks, see fault_results.md) |

Checker known-bad demonstrations (when a fault cannot be injected): drive a wrong expected value into
the vector file (for example flip one byte of the expected ciphertext of TC-05 record 8) and confirm
that TC05-C1 reports FAIL and the run exits with a non-zero status; mask removal check: run TC-09
with `i_mask_axi_wlast` tied 0 and confirm AXI-22/AXI-23 fail on the deliberate burst (R-025).
