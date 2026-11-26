# Open questions for the specification owner (rule R-005 / R-023)

Facts that `VLSIT_AES_GCM_ACCELERATOR_HDS.md` v0.1 and `aesgcm_regs.json` do not define, or define
inconsistently. Each row states what the testbench currently assumes so that a different answer can be
applied by changing the named check only. None of these was answered from the RTL.

| ID | Topic | Specification text | Testbench assumption (where) | Decision needed |
|---|---|---|---|---|
| Q-01 | `aesgcm_sts.ver_ok` after pass 2 starts | workbook: "until the next start, key_new or zeroize"; REQ-FUNC-004: pass 2 starts only when ver_ok = 1 | ver_ok is not checked after a pass-2 start (TC-01, TC-03) | Is ver_ok cleared by the pass-2 start and is pass 2 checked against an internal verified flag? |
| Q-02 | Key registers after a start | 11.3: key words cleared by "the bundle-holding-register clear"; 5.3 step 8 and `key_ld`: key reuse allowed until zeroize | key words are written only together with key_new; a message with the same key writes neither (TC-08 C3) | Are `aesgcm_key_*` fields cleared after every start, and is a later start without key words legal? |
| Q-03 | Source of the tag length latched by key_new | 11.2 order S04 (key_new) before S05 (cfg); REQ-FUNC-006 latches "when key_new was last written" | `aesgcm_cfg` (tag_len, key_size) is written before key_new (`sw_program`) | Which value of `aesgcm_cfg.tag_len` is latched: at the key_new write or at the next start? |
| Q-04 | DONE together with an error end | 6.4 DONE "message (or pass) completed"; FIN "DONE, TAG_FAIL or error event" | end of a message = DONE or any error event (`wait_event(EV_END)`) | Is DONE raised for a message that ends with TAG_FAIL, LEN_ERR, KEY_ERR? |
| Q-05 | `aesgcm_ctrl.start` after a rejected start | 11.3: cleared "when the bundle holding register accepts the snapshot" | software writes ctrl = en after a CFG_ERR (`run_expect_error`) | Does hardware clear start on a rejection? |
| Q-06 | Encoding of `aesgcm_sts.phase` | workbook: "0x1 to 0xD other states, 0xE aborting"; 10.1 lists 14 states including ABRT | only 0 after reset is checked (TC-13) | Encoding table for phase. |
| Q-07 | `aesgcm_cap` with GCM disabled / APB wrapper | spec 8: "CSR registers remain (read as 0 or ignored)"; axi_dw "code of PARA_AXI_DATA_W" | policy/ctx/ghash compared only when GCM_EN = 1; axi_dw only on the AXI wrapper (`cap_compare_mask`) | Values of these fields in CFG-LEGACY and on `m_aesgcm_acc_apb_top`. |
| Q-08 | Parameter list of `m_aesgcm_acc_apb_top` | 8: PARA_AXI_* "AXI wrapper only" | the APB wrapper is instantiated without PARA_AXI_* (`tb_aesgcm_top.sv`) | Confirm. |
| Q-09 | PERF-001 condition "data already in the FIFO" | 11.2 moves data after the start (S07 then S08) | bound = formula + 2 X_c + measured data-movement time + polling (TC-15) | May software write the input window before start? If yes, TC-15 can preload and use the formula alone. |
| Q-10 | LEN_ERR conditions | ERR-002 "idle for the data timeout (message waits, no timeout)"; ERR-002 "more beats than the lengths allow" vs 6.3.2 / ERR-005 PROTO_ERR | only ECB/CBC tails and legacy length 0 are tested for LEN_ERR (TC-11) | Is there a data time-out? Which event for excess beats? |
| Q-11 | CTR_EXHAUST trigger | ERR-003 "AES core reports error 3"; REF-008 not among the authoring inputs | covered by injection only (TC-12) | A port-reachable condition, if any. |
| Q-12 | CFB with segments of 16 bits or more and a length that is not a whole number of segments | 9.2 | vectors use whole segments (`gen_tb_vectors.py`) | Behavior of a partial final segment (LEN_ERR or truncation). |
| Q-13 | `aesgcm_keywait.clks` = 0 | workbook "0x0 means no wait" | not used | Immediate KEY_ERR or no time-out? |
| Q-14 | Pass 2 with `key_src` = 1 | 10.1 KEY state captures side-load; pass 2 reuses the verified context | pass 2 may or may not capture the key again (TC01-C3 allows 0 or 1 ack) | Does pass 2 wait for `i_key_side_valid`? |
| Q-15 | Stream after resume | S09 "consumed counts tell the driver where to restart" | remaining AAD from cons_a then remaining payload from cons_d, each padded to a beat; output already produced stays readable (TC-06, TC-07) | Confirm the resumed stream format and that output produced before the suspend is not flushed. |
| Q-16 | Export / import protocol | 11.3 "hardware load by the export after a suspend report"; WF-021 shows a word transfer per APB read; DEC-023 key not exported | read words 0..23 after CTX_SWITCH_DONE; write 0..20 before resume; the live key store supplies the key (FT-011) | Which key is used after an import, must key_new be written, and are all 21 words required? |
| Q-17 | `PARA_GCM_CTX_NUM` with `PARA_GCM_CTX_MODE` = 1 | 8: CTX_NUM "used when CTX_MODE = 0"; workbook suspend "requires PARA_GCM_CTX_NUM > 0" | export build uses CTX_NUM = 1 (`tb_aesgcm_cfg.svh`) | Legal CTX_NUM in export mode. |
| Q-18 | `o_apb_pready` during reset | 6.2 reset value 0; 7.3 "follows the generated CSR" | RST-01 requires 0 | Confirm. |
| Q-19 | TEST-001 vector replay | "replay all vectors of verification/ht_aes128_256/vectors" (format not in the authoring inputs) | legacy vectors are generated with `run_stream` of the same model | Accept, or provide the vector format. |
| Q-20 | TEST-004 AAD and IV flips | 15.2 TEST-004 | records flip the tag and the ciphertext; AAD/IV flips are not generated | Generator extension wanted? (planned gap) |
| Q-21 | TEST-010 "suspend at every block position" | 15.2 | AAD block 2 and payload block 3 positions only (TC-06/07) | Accept sampled positions or require the sweep. |
| Q-22 | Same-cycle races | 11.3 "hardware load wins", "clear wins over a same-cycle write"; TEST-020, TEST-021 | not reachable from the ports without forcing internal timing | Accept as review/formal items or provide a probe-driven method. |
| Q-23 | Simultaneous error causes | 12 "lowest error ID among simultaneous causes" | not tested (no deterministic port stimulus) | Accept as formal/review item. |
| Q-24 | `aesgcm_failcnt` saturation | REQ-SEC-005 | not reachable (2^32 failures); increments and reset only (FT-029) | Accept, or allow a force of the counter in a dedicated test. |
| Q-25 | DMA phase 3 and 4 timing | 6.3.4 gives no bound | request must fall within 16 bus clocks of the acknowledge (DMA-*-02) | Required bound. |
| Q-26 | DMA_IN_RDY / DMA_OUT_RDY | 6.4 "level-derived event, one raw set per transition" | only "raised at least once in a DMA test" is checked (TC10-C5) | Are they raised when the channel is disabled or no message is active? |
| Q-27 | gcm_pass 1/2 when policy A is not built | ERR-001 lists only decipher = 1, pass 0 with policy C absent | not tested in CFG-LINK | Expected event (CFG_ERR?). |
| Q-28 | Meaning of X_c | 13.2 "crossing latency of a bundle" | request to acknowledge-seen and start acceptance are bounded by 2 x X_c (XING-02, TC14-C3, WF001-C1) | Does X_c cover request to capture only, or the full handshake? |
| Q-29 | Partial PSTRB write with `i_slverr_en` = 0 | 11.4 row ends "PREADY in the first ACCESS cycle (0 wait states)" | 0 wait states checked only with slverr_en = 1 (APB-19) | Does the 0-wait-state statement apply to both values? |
| Q-30 | Non-secure access with protect_en = 1 and slverr_en = 0 | 11.4 | register value not checked (FT-016) | Is the access performed or ignored? |
| Q-31 | Writing `aesgcm_ctrl` while a command bit is pending | 11.3 software write wins over the hardware load | the testbench never rewrites a pending command bit except as in DEC-022 Example 3 | Does writing 0 to a pending abort/zeroize/suspend cancel it? |
| Q-32 | Start with `aesgcm_ctrl.en` = 0 | workbook "clearing it while idle holds the sequencer in idle" | not tested | Event for a start while disabled. |
| Q-33 | Key words 4..7 for AES-128 | 9.1 "ignored" | random values are written to them in TC-05 | Confirm that writing them is legal. |
| Q-34 | `aesgcm_tagout` after a legacy message | not stated | not checked | Unchanged, zero, or undefined? |
| Q-35 | Internal signals in the figures | 10.3.1 rows such as fsm_seq_state | probe macros (`probe_list.md`) | Integrator binds them. |
| Q-36 | Changing `i_gcm_secure_only` between messages | 6.2 "constant while a message is active" | changed only while idle, 8 clocks of each domain allowed for the resynchronization | Confirm. |
| Q-37 | key_new for side-loaded keys | workbook key_new "after the side-loaded key changes"; ERR-001 GCM start without key_new | key_new before every side-load message with a new key | Confirm that the first side-load message needs key_new. |
| Q-38 | Latched key size for a side-loaded key | ERR-001 "key size ... different from the latched value"; cfg.key_size ignored for side-load | cfg.key_size is set equal to `i_key_side_size` | Which size is compared? |
| Q-39 | Abort / zeroize bound as seen by software | REQ-FUNC-013, PERF-004: 64 core clocks | bound = 64 core clocks + 2 X_c + polling (TC-08, FT-012, FT-028, WF-013/014/023); exact 64 with probes (SEC-01/02) | Confirm the observable bound. |
| Q-40 | AXI read of an empty window | ASM-011 no time-out in the IP | the manager model uses bounded waits and reports a harness error | none (information) |
