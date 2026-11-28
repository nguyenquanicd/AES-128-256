// -------------------------------------------------------------------------------------------------
// Project      : AES-GCM Accelerator - acceptance simulation testbench
// File         : tb_probe_bind.svh (included at the top of tb_aesgcm_probes.svh when TB_PROBE_BIND is
//                defined)
// Description  : Binding of the probe placeholders of probe_list.md to the hierarchical names of the
//                delivered RTL (integrator work, rule R-023: the testbench itself was written without
//                the RTL). Paths are relative to module tb_aesgcm_top; the DUT instance is u_dut.
//                TB_PROBE_HAS_CTX adds the probes of the context engine (builds with
//                PARA_GCM_CTX_NUM > 0 or PARA_GCM_CTX_MODE = 1). Probes that the RTL does not expose
//                stay unbound and read 0: TB_PROBE_OUT_FIFO_LEVEL, TB_PROBE_GHASH_PP_VALID,
//                TB_PROBE_GHASH_EXP_LANE (view rows only). Use with a build that has GCM enabled and the
//                core, ghash and key-select modules present (not CFG-LEGACY).
// -------------------------------------------------------------------------------------------------

`define TB_PROBES_BOUND

// ---- crossing of the configuration bundle (CDC-001)
`define TB_PROBE_BUNDLE_REQ     u_dut.u_xing.u_xing_cfg.w_src_req
`define TB_PROBE_BUNDLE_ACK     u_dut.u_xing.u_xing_cfg.w_src_ack
`define TB_PROBE_BUNDLE_DATA    1024'(u_dut.u_xing.u_xing_cfg.reg_hold)
`define TB_PROBE_REQ_CAP_CORE   (u_dut.u_xing.u_xing_cfg.reg_fsm_hsr_current_state == 2'b01)
`define TB_PROBE_ACK_CORE       (u_dut.u_xing.u_xing_cfg.reg_fsm_hsr_current_state == 2'b10)

// ---- sequencer and AES core
`define TB_PROBE_SEQ_STATE       8'(u_dut.u_core_dom.u_seq.reg_fsm_seq_current_state)
`define TB_PROBE_SEQ_IDLE        (u_dut.u_core_dom.u_seq.reg_fsm_seq_current_state == 4'h0)
`define TB_PROBE_CORE_CFG_VALID  u_dut.u_core_dom.w_aes_cfg_valid
`define TB_PROBE_CORE_BATCH_VALID u_dut.u_core_dom.w_aes_in_valid
`define TB_PROBE_CORE_OUT_VALID  u_dut.u_core_dom.w_aes_out_valid
`define TB_PROBE_GHASH_VALID     (u_dut.u_core_dom.gen_gcm.u_ghash.i_valid & u_dut.u_core_dom.gen_gcm.u_ghash.o_ready)
`define TB_PROBE_TAG_VALID       (u_dut.u_core_dom.u_seq.reg_fsm_seq_current_state == 4'h9)
`define TB_PROBE_SEQ_DONE        u_dut.u_core_dom.u_seq.w_done_clr
`define TB_PROBE_OUT_FIFO_PUSH   u_dut.u_core_dom.o_out_wr_en
`define TB_PROBE_TAG_MATCH       u_dut.u_core_dom.u_seq.i_tag_match
`define TB_PROBE_VER_OK          u_dut.u_core_dom.u_seq.reg_ver_ok

// ---- events and CSR sideband
`define TB_PROBE_IRQ_RAW ({u_dut.u_csr.o_aesgcm_irq_raw_perr, u_dut.u_csr.o_aesgcm_irq_raw_kerr, u_dut.u_csr.o_aesgcm_irq_raw_cswd, u_dut.u_csr.o_aesgcm_irq_raw_dour, u_dut.u_csr.o_aesgcm_irq_raw_dinr, u_dut.u_csr.o_aesgcm_irq_raw_cexh, u_dut.u_csr.o_aesgcm_irq_raw_lerr, u_dut.u_csr.o_aesgcm_irq_raw_cerr, u_dut.u_csr.o_aesgcm_irq_raw_tagf, u_dut.u_csr.o_aesgcm_irq_raw_done})
`define TB_PROBE_EVENT_DONE      u_dut.u_bus_dom.u_bus_ctl.o_irq_set[0]
`define TB_PROBE_REG_WR_EN       u_dut.w_r_reg_wr_en
`define TB_PROBE_REG_WR_ADDR     u_dut.w_r_reg_wr_addr
`define TB_PROBE_REG_RD_EN       u_dut.w_r_reg_rd_en
`define TB_PROBE_CTRL_START      u_dut.u_bus_dom.u_bus_ctl.i_ctrl_cmd[0]
`define TB_PROBE_CTRL_ABORT      u_dut.u_bus_dom.u_bus_ctl.i_ctrl_cmd[1]
`define TB_PROBE_HW_CLR_ABORT    u_dut.u_bus_dom.u_bus_ctl.o_ctrl_clr[1]
`define TB_PROBE_STS_BUSY        u_dut.u_bus_dom.u_bus_ctl.o_sts_busy
`define TB_PROBE_STS_ZEROIZED    u_dut.u_bus_dom.u_bus_ctl.o_sts_zeroized

// ---- data FIFOs and DMA conditions
`define TB_PROBE_FIFO_PUSH       u_dut.u_xing.u_fifo_in.w_wr_en
`define TB_PROBE_FIFO_POP        u_dut.u_xing.u_fifo_out.w_rd_en
`define TB_PROBE_FIFO_IN_FULL    u_dut.w_b_in_full
`define TB_PROBE_FIFO_FLUSH      u_dut.w_b_in_flush
`define TB_PROBE_IN_ROOM_BURST   (~u_dut.u_bus_dom.u_bus_ctl.i_in_full_thr)
`define TB_PROBE_OUT_HAS_BURST   u_dut.u_bus_dom.u_bus_ctl.i_out_dma_cond

// ---- key store, commands delivered to CORE, GHASH
`define TB_PROBE_KEY_LD          u_dut.u_core_dom.u_key_sel.reg_ld
`define TB_PROBE_KEYWAIT_EXPIRED u_dut.u_core_dom.u_key_sel.o_key_err
`define TB_PROBE_KEY_STORE       u_dut.u_core_dom.u_key_sel.reg_key
`define TB_PROBE_CMD_SUSPEND     u_dut.u_core_dom.u_seq.w_cmd_susp
`define TB_PROBE_CMD_RESUME      (u_dut.u_core_dom.u_seq.i_cfg_valid & u_dut.u_core_dom.u_seq.w_b_op)
`define TB_PROBE_CMD_ABORT       u_dut.u_core_dom.u_seq.w_cmd_abort
`define TB_PROBE_CMD_ZEROIZE     u_dut.u_core_dom.u_seq.w_cmd_zero
`define TB_PROBE_AES_ZEROIZE     u_dut.u_core_dom.w_aes_zeroize
`define TB_PROBE_GHASH_STATE     u_dut.u_core_dom.gen_gcm.u_ghash.o_y
`define TB_PROBE_GHASH_IN_VALID  u_dut.u_core_dom.gen_gcm.u_ghash.i_valid
`define TB_PROBE_GHASH_IN_COUNT  3'($countones(u_dut.u_core_dom.gen_gcm.u_ghash.i_mask))

// ---- command, status and word crossings (CDC-005, CDC-002, CDC-007)
`define TB_PROBE_CMD_SEND        u_dut.u_xing.u_xing_cmd.i_send
`define TB_PROBE_CMD_VALID       u_dut.u_xing.u_xing_cmd.o_valid
`define TB_PROBE_STS_VALID       (u_dut.u_bus_dom.u_bus_ctl.i_sts_valid & u_dut.u_bus_dom.u_bus_ctl.w_s_ack)
`define TB_PROBE_CDC007_REQ      u_dut.u_xing.u_xing_wreq.w_src_req
`define TB_PROBE_CDC007_ACK      u_dut.u_xing.u_xing_wreq.w_src_ack

// ---- context engine (only when the build has it)
`ifdef TB_PROBE_HAS_CTX
`define TB_PROBE_CTX_STATE       8'(u_dut.u_core_dom.gen_ctx.u_ctx.reg_fsm_ctx_current_state)
`define TB_PROBE_SLOT_VALID      4'(u_dut.u_core_dom.gen_ctx.u_ctx.reg_vld)
`define TB_PROBE_CTX_SLOTS_NZ    (|u_dut.u_core_dom.gen_ctx.u_ctx.reg_slot)
`endif
