# Probe placeholders for internal signals named in the specification figures

The testbench was written without the RTL (rule R-023), so internal signals that the figures of spec
section 10.3.1 name are reached through placeholder macros. Bind each macro on the Verilator command
line (or in a small include) to a hierarchical expression under `tb_aesgcm_top.u_dut`, then define
`TB_PROBES_BOUND`. Example:

```
+define+TB_PROBE_SEQ_IDLE="(u_dut.u_core_dom.u_seq.<state reg> == <ENUM_ST_SEQ_IDLE>)"
+define+TB_PROBES_BOUND
```

Without `TB_PROBES_BOUND` every probe reads 0, the probe rows of the VCD files are flat, and the
probe-based assertions INT-01, POL-03, SEC-01, SEC-02, XING-01, XING-02 and the probe checks FT030-C2
and FT031-C2 are reported as inapplicable / not executed. No port-level check depends on a probe.

| Macro | Width in TB | Meaning (from the specification) | Spec source | Figures | Used by |
|---|---:|---|---|---|---|
| `TB_PROBE_BUNDLE_REQ` | 1 | request of the configuration bundle crossing `u_xing_cfg` in the BUS domain (FSM hsk REQ) | 5.1, 7.2 CDC-001, 10.1 FSM hsk | WF-001, WF-016 (bundle_req_bus), WF-018 | XING-01, XING-02 |
| `TB_PROBE_BUNDLE_ACK` | 1 | acknowledge of `u_xing_cfg` as seen (synchronized) in the BUS domain | 7.2 CDC-001 | WF-001 (bundle_ack_sync), WF-016 (ack_seen_bus) | XING-01, XING-02 |
| `TB_PROBE_BUNDLE_DATA` | 1024 | holding register of `u_xing_cfg` (zero-extended) | 7.2 CDC-001, SVA-009 | - | XING-01 |
| `TB_PROBE_REQ_CAP_CORE` | 1 | request captured on the CORE side (FSM hsr CAP) | 10.1 FSM hsr | WF-016 | view |
| `TB_PROBE_ACK_CORE` | 1 | acknowledge driven by the CORE side | 10.1 FSM hsr | WF-016 | view |
| `TB_PROBE_SEQ_STATE` | 8 | FSM seq current state, any encoding | 10.1 FSM seq | WF-001/002/003/004/011/012/013/014/018/020/023 | view |
| `TB_PROBE_SEQ_IDLE` | 1 | 1 when FSM seq is `ENUM_ST_SEQ_IDLE` | 10.1 | - | SEC-02 |
| `TB_PROBE_CTX_STATE` | 8 | FSM ctx current state | 10.1 FSM ctx | WF-012, WF-021 | view |
| `TB_PROBE_CORE_CFG_VALID` | 1 | `i_cfg_valid` of the AES core | 10.3 cycle table | WF-002 | view |
| `TB_PROBE_CORE_BATCH_VALID` | 1 | batch valid of the AES core | 10.3 cycle table | WF-002, WF-020 | view |
| `TB_PROBE_CORE_OUT_VALID` | 1 | output valid of the AES core | REF-008 via 10.3 | WF-002, WF-004, WF-019 | view |
| `TB_PROBE_GHASH_VALID` | 1 | GHASH input block accepted | 5.3, 10.1 | WF-002/003/004/020 | view |
| `TB_PROBE_TAG_VALID` | 1 | tag T formed (FSM seq TAG) | 5.3 step 7 | WF-002, WF-020 | view |
| `TB_PROBE_SEQ_DONE` | 1 | sequencer completion pulse (`o_done` row) | 10.1 FIN | WF-002, WF-004, WF-020 | view |
| `TB_PROBE_OUT_FIFO_PUSH` | 1 | write of the output FIFO on the CORE side | invariant 2, SVA-004 | WF-003, WF-004, WF-005 | POL-03 |
| `TB_PROBE_TAG_MATCH` | 1 | tag comparison equal | 5.3 step 7 | WF-003, WF-004 | view |
| `TB_PROBE_VER_OK` | 1 | verified-context flag in CORE | 5.3 policy A | WF-003, WF-004 | view |
| `TB_PROBE_IRQ_RAW` | 10 | value of `aesgcm_irq_raw` (bits per spec 9.3) | 6.4, 11.3 | WF-003/005/010/011/012/015/019 | INT-01 |
| `TB_PROBE_FIFO_PUSH` | 1 | input FIFO push on the BUS side (one per entry) | 10.4 DEC-018 | WF-006, WF-007, WF-010, WF-019 | FT031-C2 |
| `TB_PROBE_FIFO_POP` | 1 | output FIFO pop on the BUS side | 6.3.2 | WF-008 | view |
| `TB_PROBE_FIFO_IN_FULL` | 1 | input FIFO full flag | 6.3.3 | WF-010 | view |
| `TB_PROBE_REG_WR_EN` | 1 | CSR sideband `o_reg_wr_en` | 11.1 | WF-010, WF-019 | view |
| `TB_PROBE_REG_WR_ADDR` | 16 | CSR sideband `o_reg_wr_addr` | 11.1 | WF-010 | view |
| `TB_PROBE_REG_RD_EN` | 1 | CSR sideband `o_reg_rd_en` | 11.1 | WF-019 | view |
| `TB_PROBE_IN_ROOM_BURST` | 1 | DMA input condition: room for a burst | 6.3.4 phase 1 | WF-009 | view |
| `TB_PROBE_OUT_HAS_BURST` | 1 | DMA output condition: a burst available | 6.3.4 phase 1 | WF-009 | view |
| `TB_PROBE_KEY_LD` | 1 | CORE key store valid | 11.3, `aesgcm_sts.key_ld` | WF-011, WF-013 | view |
| `TB_PROBE_KEYWAIT_EXPIRED` | 1 | side-load wait expired | 6.3.5 | WF-011 | view |
| `TB_PROBE_CMD_SUSPEND` | 1 | suspend delivered to CORE by `u_xing_cmd` | 7.2 CDC-005 | WF-012 | view |
| `TB_PROBE_CMD_RESUME` | 1 | resume bundle delivered to CORE | 7.2 CDC-005 | WF-012 | view |
| `TB_PROBE_CMD_ABORT` | 1 | abort delivered to CORE | 7.2 CDC-005 | WF-013 | SEC-02 |
| `TB_PROBE_CMD_ZEROIZE` | 1 | zeroize delivered to CORE | 7.2 CDC-005 | WF-014 | SEC-01 |
| `TB_PROBE_SLOT_VALID` | 4 | context slot valid flags | 10.5 MEM-003 | WF-012 | view |
| `TB_PROBE_FIFO_FLUSH` | 1 | FIFO flush request | 7.2 CDC-003 | WF-013 | view |
| `TB_PROBE_OUT_FIFO_LEVEL` | 16 | output FIFO occupancy (any side) | WF-013 | WF-013 | view |
| `TB_PROBE_KEY_STORE` | 256 | CORE key store | 10.5 MEM-004 | WF-014, WF-018 | SEC-01 |
| `TB_PROBE_CTX_SLOTS_NZ` | 1 | OR of all context slot bits | 10.5 MEM-003 | WF-014 | SEC-01 |
| `TB_PROBE_GHASH_STATE` | 128 | GHASH accumulator Y | 10.5, invariant 5 | WF-014, WF-017, WF-022 (both rows) | SEC-01 |
| `TB_PROBE_AES_ZEROIZE` | 1 | zeroize input of the AES core | 10.1 ABRT | WF-014 | view |
| `TB_PROBE_STS_ZEROIZED` | 1 | CSR status input `aesgcm_sts.zeroized` | 11.3 | WF-014 | view |
| `TB_PROBE_EVENT_DONE` | 1 | DONE hardware-load pulse into `aesgcm_irq_raw` | 11.3 | WF-015 | view |
| `TB_PROBE_GHASH_IN_VALID` | 1 | GHASH batch input valid | 13.1 | WF-017, WF-022 | FT030-C2 |
| `TB_PROBE_GHASH_IN_COUNT` | 3 | blocks k of the GHASH batch | 13.1 | WF-017, WF-022 | FT030-C2 |
| `TB_PROBE_GHASH_PP_VALID` | 1 | registered products valid (`PARA_GHASH_PIPE` = 1) | DEC-017 | WF-022 | view |
| `TB_PROBE_GHASH_EXP_LANE` | 12 | exponent of H per lane, 3 bits each (lane 0 in [2:0]) | 13.1 | WF-017 | view |
| `TB_PROBE_CDC007_REQ` | 1 | context word request | 7.2 CDC-007 | WF-021 | view |
| `TB_PROBE_CDC007_ACK` | 1 | context word acknowledge | 7.2 CDC-007 | WF-021 | view |
| `TB_PROBE_CMD_SEND` | 1 | `u_xing_cmd` send in BUS | DEC-022 | WF-023 | view |
| `TB_PROBE_CMD_VALID` | 1 | command bundle valid in CORE | DEC-022 | WF-023 | view |
| `TB_PROBE_STS_VALID` | 1 | status report valid with cmd_ack | DEC-022 | WF-023 | view |
| `TB_PROBE_HW_CLR_ABORT` | 1 | hardware clear of `aesgcm_ctrl.abort` | 11.3 | WF-023 | view |
| `TB_PROBE_CTRL_START` | 1 | CSR field `aesgcm_ctrl.start` | 11.3 | WF-001, WF-005, WF-019 | view |
| `TB_PROBE_CTRL_ABORT` | 1 | CSR field `aesgcm_ctrl.abort` | 11.3 | WF-023 | view |
| `TB_PROBE_STS_BUSY` | 1 | CSR status input `aesgcm_sts.busy` | 11.3 | WF-023 | view |

Rows derived without probes (from the APB transfers the testbench issued): `aesgcm_cfg_mode`,
`aesgcm_cfg_mode_pass`, `aesgcm_datalen`, `irq_en_done`, `irq_sts_done` (probe raw AND shadow enable),
`pio_din_word`, `pio_dout_word`, `apb_ctxx_index`, `apb_w1c_write`.
