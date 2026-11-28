// -------------------------------------------------------------------------------------------------
// Project      : AES-GCM Accelerator - acceptance simulation testbench
// File         : tb_aesgcm_probes.svh (included inside module tb_aesgcm_top)
// Description  : Placeholders for the internal signals that the specification figures of section
//                10.3.1 name (fsm_seq_state, bundle_req, ghash_valid, ...). The testbench was
//                written without the RTL (rule R-023), so the hierarchical paths are unknown here.
//                The integrator binds each `TB_PROBE_<NAME> macro to a hierarchical path of the DUT
//                (for example +define+TB_PROBE_SEQ_IDLE=u_dut.u_core_dom.u_seq.<state>==<IDLE>)
//                and then defines TB_PROBES_BOUND. Meanings are listed in probe_list.md.
//
//                Until TB_PROBES_BOUND is defined, every probe reads 0, the probe-based assertions
//                are reported as inapplicable ("probes not bound") and the probe rows of the
//                waveform dumps are flat. Port-based checks never depend on a probe.
// -------------------------------------------------------------------------------------------------

// The integrator's binding to the delivered RTL (tb_probe_bind.svh) is used when TB_PROBE_BIND is defined.
`ifdef TB_PROBE_BIND
  `include "tb_probe_bind.svh"
`endif

`ifndef TB_PROBE_BUNDLE_REQ
  `define TB_PROBE_BUNDLE_REQ 1'b0          // u_xing_cfg request launched in BUS (WF-001/016/018)
`endif
`ifndef TB_PROBE_BUNDLE_ACK
  `define TB_PROBE_BUNDLE_ACK 1'b0          // u_xing_cfg acknowledge as seen in BUS (WF-001/016)
`endif
`ifndef TB_PROBE_BUNDLE_DATA
  `define TB_PROBE_BUNDLE_DATA 1024'h0      // u_xing_cfg holding register (SVA-009), zero-extended
`endif
`ifndef TB_PROBE_REQ_CAP_CORE
  `define TB_PROBE_REQ_CAP_CORE 1'b0        // request captured in CORE (WF-016)
`endif
`ifndef TB_PROBE_ACK_CORE
  `define TB_PROBE_ACK_CORE 1'b0            // acknowledge driven in CORE (WF-016)
`endif
`ifndef TB_PROBE_SEQ_STATE
  `define TB_PROBE_SEQ_STATE 8'h00          // FSM seq current state (any encoding, zero-extended)
`endif
`ifndef TB_PROBE_SEQ_IDLE
  `define TB_PROBE_SEQ_IDLE 1'b0            // 1 when FSM seq is ENUM_ST_SEQ_IDLE
`endif
`ifndef TB_PROBE_CTX_STATE
  `define TB_PROBE_CTX_STATE 8'h00          // FSM ctx current state (WF-012, WF-021)
`endif
`ifndef TB_PROBE_CORE_CFG_VALID
  `define TB_PROBE_CORE_CFG_VALID 1'b0      // AES core i_cfg_valid (WF-002)
`endif
`ifndef TB_PROBE_CORE_BATCH_VALID
  `define TB_PROBE_CORE_BATCH_VALID 1'b0    // AES core batch valid (WF-002, WF-020)
`endif
`ifndef TB_PROBE_CORE_OUT_VALID
  `define TB_PROBE_CORE_OUT_VALID 1'b0      // AES core output valid (WF-002/004/019)
`endif
`ifndef TB_PROBE_GHASH_VALID
  `define TB_PROBE_GHASH_VALID 1'b0         // GHASH input accepted (WF-002/003/004/020)
`endif
`ifndef TB_PROBE_TAG_VALID
  `define TB_PROBE_TAG_VALID 1'b0           // tag formed (WF-002, WF-020)
`endif
`ifndef TB_PROBE_SEQ_DONE
  `define TB_PROBE_SEQ_DONE 1'b0            // sequencer done pulse o_done (WF-002/004/020)
`endif
`ifndef TB_PROBE_OUT_FIFO_PUSH
  `define TB_PROBE_OUT_FIFO_PUSH 1'b0       // output FIFO write (core side) (WF-003/004/005, SVA-004)
`endif
`ifndef TB_PROBE_TAG_MATCH
  `define TB_PROBE_TAG_MATCH 1'b0           // tag comparison equal (WF-003, WF-004)
`endif
`ifndef TB_PROBE_VER_OK
  `define TB_PROBE_VER_OK 1'b0              // verified-context flag in CORE (WF-003, WF-004)
`endif
`ifndef TB_PROBE_IRQ_RAW
  `define TB_PROBE_IRQ_RAW 10'h000          // aesgcm_irq_raw register value (WF-003/005/010/011/015/019)
`endif
`ifndef TB_PROBE_FIFO_PUSH
  `define TB_PROBE_FIFO_PUSH 1'b0           // input FIFO push, bus side (WF-006/007/010/019)
`endif
`ifndef TB_PROBE_FIFO_POP
  `define TB_PROBE_FIFO_POP 1'b0            // output FIFO pop, bus side (WF-008)
`endif
`ifndef TB_PROBE_FIFO_IN_FULL
  `define TB_PROBE_FIFO_IN_FULL 1'b0        // input FIFO full flag (WF-010)
`endif
`ifndef TB_PROBE_REG_WR_EN
  `define TB_PROBE_REG_WR_EN 1'b0           // CSR sideband o_reg_wr_en (WF-010, WF-019)
`endif
`ifndef TB_PROBE_REG_WR_ADDR
  `define TB_PROBE_REG_WR_ADDR 16'h0000     // CSR sideband o_reg_wr_addr (WF-010)
`endif
`ifndef TB_PROBE_REG_RD_EN
  `define TB_PROBE_REG_RD_EN 1'b0           // CSR sideband o_reg_rd_en (WF-019)
`endif
`ifndef TB_PROBE_IN_ROOM_BURST
  `define TB_PROBE_IN_ROOM_BURST 1'b0       // input DMA condition: room for a burst (WF-009)
`endif
`ifndef TB_PROBE_OUT_HAS_BURST
  `define TB_PROBE_OUT_HAS_BURST 1'b0       // output DMA condition: burst available (WF-009)
`endif
`ifndef TB_PROBE_KEY_LD
  `define TB_PROBE_KEY_LD 1'b0              // key store valid in CORE (WF-011, WF-013)
`endif
`ifndef TB_PROBE_KEYWAIT_EXPIRED
  `define TB_PROBE_KEYWAIT_EXPIRED 1'b0     // side-load wait counter expired (WF-011)
`endif
`ifndef TB_PROBE_CMD_SUSPEND
  `define TB_PROBE_CMD_SUSPEND 1'b0         // suspend command delivered to CORE (WF-012)
`endif
`ifndef TB_PROBE_CMD_RESUME
  `define TB_PROBE_CMD_RESUME 1'b0          // resume bundle delivered to CORE (WF-012)
`endif
`ifndef TB_PROBE_CMD_ABORT
  `define TB_PROBE_CMD_ABORT 1'b0           // abort command delivered to CORE (WF-013, SEC-02)
`endif
`ifndef TB_PROBE_CMD_ZEROIZE
  `define TB_PROBE_CMD_ZEROIZE 1'b0         // zeroize command delivered to CORE (WF-014, SEC-01)
`endif
`ifndef TB_PROBE_SLOT_VALID
  `define TB_PROBE_SLOT_VALID 4'h0          // context slot valid flags (WF-012)
`endif
`ifndef TB_PROBE_FIFO_FLUSH
  `define TB_PROBE_FIFO_FLUSH 1'b0          // FIFO flush request (WF-013)
`endif
`ifndef TB_PROBE_OUT_FIFO_LEVEL
  `define TB_PROBE_OUT_FIFO_LEVEL 16'h0000  // output FIFO occupancy, any side (WF-013)
`endif
`ifndef TB_PROBE_KEY_STORE
  `define TB_PROBE_KEY_STORE 256'h0         // CORE key store (WF-014, WF-018, SEC-01)
`endif
`ifndef TB_PROBE_CTX_SLOTS_NZ
  `define TB_PROBE_CTX_SLOTS_NZ 1'b0        // OR-reduce of all context slot bits (WF-014, SEC-01)
`endif
`ifndef TB_PROBE_GHASH_STATE
  `define TB_PROBE_GHASH_STATE 128'h0       // GHASH accumulator Y (WF-014/017/022, SEC-01)
`endif
`ifndef TB_PROBE_AES_ZEROIZE
  `define TB_PROBE_AES_ZEROIZE 1'b0         // zeroize input of the AES core (WF-014)
`endif
`ifndef TB_PROBE_STS_ZEROIZED
  `define TB_PROBE_STS_ZEROIZED 1'b0        // CSR status input aesgcm_sts.zeroized (WF-014)
`endif
`ifndef TB_PROBE_EVENT_DONE
  `define TB_PROBE_EVENT_DONE 1'b0          // DONE hardware-load pulse into aesgcm_irq_raw (WF-015)
`endif
`ifndef TB_PROBE_GHASH_IN_VALID
  `define TB_PROBE_GHASH_IN_VALID 1'b0      // GHASH batch input valid (WF-017, WF-022)
`endif
`ifndef TB_PROBE_GHASH_IN_COUNT
  `define TB_PROBE_GHASH_IN_COUNT 3'h0      // blocks in the GHASH batch k (WF-017, WF-022)
`endif
`ifndef TB_PROBE_GHASH_PP_VALID
  `define TB_PROBE_GHASH_PP_VALID 1'b0      // registered product valid, PARA_GHASH_PIPE = 1 (WF-022)
`endif
`ifndef TB_PROBE_GHASH_EXP_LANE
  `define TB_PROBE_GHASH_EXP_LANE 12'h000   // exponent of H used by lanes 3..0, 3 bits each (WF-017)
`endif
`ifndef TB_PROBE_CDC007_REQ
  `define TB_PROBE_CDC007_REQ 1'b0          // context word request (WF-021)
`endif
`ifndef TB_PROBE_CDC007_ACK
  `define TB_PROBE_CDC007_ACK 1'b0          // context word acknowledge (WF-021)
`endif
`ifndef TB_PROBE_CMD_SEND
  `define TB_PROBE_CMD_SEND 1'b0            // u_xing_cmd send in BUS (WF-023)
`endif
`ifndef TB_PROBE_CMD_VALID
  `define TB_PROBE_CMD_VALID 1'b0           // command bundle valid in CORE (WF-023)
`endif
`ifndef TB_PROBE_STS_VALID
  `define TB_PROBE_STS_VALID 1'b0           // status report valid with cmd_ack (WF-023)
`endif
`ifndef TB_PROBE_HW_CLR_ABORT
  `define TB_PROBE_HW_CLR_ABORT 1'b0        // hardware clear of aesgcm_ctrl.abort (WF-023)
`endif
`ifndef TB_PROBE_CTRL_START
  `define TB_PROBE_CTRL_START 1'b0          // CSR field aesgcm_ctrl.start (WF-001/005/019)
`endif
`ifndef TB_PROBE_CTRL_ABORT
  `define TB_PROBE_CTRL_ABORT 1'b0          // CSR field aesgcm_ctrl.abort (WF-023)
`endif
`ifndef TB_PROBE_STS_BUSY
  `define TB_PROBE_STS_BUSY 1'b0            // CSR status input aesgcm_sts.busy (WF-023)
`endif

`ifdef TB_PROBES_BOUND
  localparam bit C_PROBES = 1'b1;
`else
  localparam bit C_PROBES = 1'b0;
`endif

// Probe wires (fixed widths; the bound expressions are zero-extended or truncated).
wire [7:0]    pr_seq_state       = `TB_PROBE_SEQ_STATE;
wire          pr_seq_idle        = `TB_PROBE_SEQ_IDLE;
wire [7:0]    pr_ctx_state       = `TB_PROBE_CTX_STATE;
wire          pr_bundle_req      = `TB_PROBE_BUNDLE_REQ;
wire          pr_bundle_ack      = `TB_PROBE_BUNDLE_ACK;
wire [1023:0] pr_bundle_data     = `TB_PROBE_BUNDLE_DATA;
wire          pr_req_cap_core    = `TB_PROBE_REQ_CAP_CORE;
wire          pr_ack_core        = `TB_PROBE_ACK_CORE;
wire          pr_core_cfg_valid  = `TB_PROBE_CORE_CFG_VALID;
wire          pr_core_batch_valid = `TB_PROBE_CORE_BATCH_VALID;
wire          pr_core_out_valid  = `TB_PROBE_CORE_OUT_VALID;
wire          pr_ghash_valid     = `TB_PROBE_GHASH_VALID;
wire          pr_tag_valid       = `TB_PROBE_TAG_VALID;
wire          pr_seq_done        = `TB_PROBE_SEQ_DONE;
wire          pr_out_fifo_push   = `TB_PROBE_OUT_FIFO_PUSH;
wire          pr_tag_match       = `TB_PROBE_TAG_MATCH;
wire          pr_ver_ok          = `TB_PROBE_VER_OK;
wire [9:0]    pr_irq_raw         = `TB_PROBE_IRQ_RAW;
wire          pr_fifo_push       = `TB_PROBE_FIFO_PUSH;
wire          pr_fifo_pop        = `TB_PROBE_FIFO_POP;
wire          pr_fifo_in_full    = `TB_PROBE_FIFO_IN_FULL;
wire          pr_reg_wr_en       = `TB_PROBE_REG_WR_EN;
wire [15:0]   pr_reg_wr_addr     = `TB_PROBE_REG_WR_ADDR;
wire          pr_reg_rd_en       = `TB_PROBE_REG_RD_EN;
wire          pr_in_room_burst   = `TB_PROBE_IN_ROOM_BURST;
wire          pr_out_has_burst   = `TB_PROBE_OUT_HAS_BURST;
wire          pr_key_ld          = `TB_PROBE_KEY_LD;
wire          pr_keywait_expired = `TB_PROBE_KEYWAIT_EXPIRED;
wire          pr_cmd_suspend     = `TB_PROBE_CMD_SUSPEND;
wire          pr_cmd_resume      = `TB_PROBE_CMD_RESUME;
wire          pr_cmd_abort       = `TB_PROBE_CMD_ABORT;
wire          pr_cmd_zeroize     = `TB_PROBE_CMD_ZEROIZE;
wire [3:0]    pr_slot_valid      = `TB_PROBE_SLOT_VALID;
wire          pr_fifo_flush      = `TB_PROBE_FIFO_FLUSH;
wire [15:0]   pr_out_fifo_level  = `TB_PROBE_OUT_FIFO_LEVEL;
wire [255:0]  pr_key_store       = `TB_PROBE_KEY_STORE;
wire          pr_ctx_slots_nz    = `TB_PROBE_CTX_SLOTS_NZ;
wire [127:0]  pr_ghash_state     = `TB_PROBE_GHASH_STATE;
wire          pr_aes_zeroize     = `TB_PROBE_AES_ZEROIZE;
wire          pr_sts_zeroized    = `TB_PROBE_STS_ZEROIZED;
wire          pr_event_done      = `TB_PROBE_EVENT_DONE;
wire          pr_ghash_in_valid  = `TB_PROBE_GHASH_IN_VALID;
wire [2:0]    pr_ghash_in_count  = `TB_PROBE_GHASH_IN_COUNT;
wire          pr_ghash_pp_valid  = `TB_PROBE_GHASH_PP_VALID;
wire [11:0]   pr_ghash_exp_lane  = `TB_PROBE_GHASH_EXP_LANE;
wire          pr_cdc007_req      = `TB_PROBE_CDC007_REQ;
wire          pr_cdc007_ack      = `TB_PROBE_CDC007_ACK;
wire          pr_cmd_send        = `TB_PROBE_CMD_SEND;
wire          pr_cmd_valid       = `TB_PROBE_CMD_VALID;
wire          pr_sts_valid       = `TB_PROBE_STS_VALID;
wire          pr_hw_clr_abort    = `TB_PROBE_HW_CLR_ABORT;
wire          pr_ctrl_start      = `TB_PROBE_CTRL_START;
wire          pr_ctrl_abort      = `TB_PROBE_CTRL_ABORT;
wire          pr_sts_busy        = `TB_PROBE_STS_BUSY;
