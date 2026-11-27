/*
 * Project      : AES-GCM Accelerator
 * Author       : Nguyen Hung Quan and Claude (user)
 * AI Flow      : VLSIT RTL Generator AI Automation Flow
 * AI Flow Page : https://github.com/nguyenquanicd/VLSIT_RTL_Generator_AI_Model
 * Date         : 2026-11-25
 * Description  : BUS-domain control (spec 5.1, 5.3 message start, 6.4, 11.3, 12): command decode
 *                of aesgcm_ctrl, legality check at start (ERR-001, the start-time part of ERR-002
 *                and ERR-005), configuration snapshot into the CDC-001 bundle, command bundle of
 *                CDC-005, capture of the CDC-002 status report into the status registers, event
 *                and interrupt logic, DMA channel conditions, capability constants, packer and
 *                unpacker control, and the context export and import sequences of CDC-007.
 *                CSR word k of a key, IV or tag holds bytes 4k to 4k+3 with byte 4k in bits [7:0]
 *                (spec 9.1); the bundle carries blocks with byte 0 in the most significant byte.
 * Decisions    : DEC-016, DEC-020, DEC-022, DEC-023, DEC-024, DEC-027, DEC-028,
 *                DEC-031, DEC-032, DEC-035, DEC-037 (spec section 20).
 */
`timescale 1ns/1ps

module m_aesgcm_bus_ctl #(
  // Parameter Description: number of 128-bit AES block lanes of the AES core.
  // Parameter values: 1 to 4; default is 1.
  // Parameter unit: lane
  parameter logic [31:0] PARA_AES_LANE_NUM = 1,
  // Parameter Description: 1 builds GHASH, tag, J0 and policy logic (mode code 5).
  // Parameter values: 0 or 1; default is 1.
  // Parameter unit: none
  parameter logic [31:0] PARA_AES_GCM_EN = 1,
  // Parameter Description: release policy; 0 policy A only, 1 policy C only, 2 both.
  // Parameter values: 0, 1 or 2; default is 0.
  // Parameter unit: none
  parameter logic [31:0] PARA_GCM_REL_POLICY = 0,
  // Parameter Description: GHASH architecture reported in aesgcm_cap.ghash.
  // Parameter values: 0, 1 or 2; default is 1.
  // Parameter unit: none
  parameter logic [31:0] PARA_GHASH_ARCH = 1,
  // Parameter Description: context storage; 0 internal slots, 1 export through the CSR.
  // Parameter values: 0 or 1; default is 0.
  // Parameter unit: none
  parameter logic [31:0] PARA_GCM_CTX_MODE = 0,
  // Parameter Description: number of internal context slots.
  // Parameter values: 0 to 4; default is 2.
  // Parameter unit: slot
  parameter logic [31:0] PARA_GCM_CTX_NUM = 2,
  // Parameter Description: 1 builds the key side-load path.
  // Parameter values: 0 or 1; default is 0.
  // Parameter unit: none
  parameter logic [31:0] PARA_KEY_SIDE_EN = 0,
  // Parameter Description: crossing structure reported in aesgcm_cap.async.
  // Parameter values: 0 or 1; default is 1.
  // Parameter unit: none
  parameter logic [31:0] PARA_CLK_ASYNC = 1,
  // Parameter Description: depth of each data FIFO in entries.
  // Parameter values: 8 to 256, power of two; default is 16.
  // Parameter unit: entry
  parameter logic [31:0] PARA_FIFO_DEPTH = 16,
  // Parameter Description: 1 when the AXI4 data window is present (AXI wrapper).
  // Parameter values: 0 or 1; default is 0.
  // Parameter unit: none
  parameter logic [31:0] PARA_AXI_EN = 0,
  // Parameter Description: AXI4 data width of the window.
  // Parameter values: 32, 64 or 128; default is 32.
  // Parameter unit: bit
  parameter logic [31:0] PARA_AXI_DATA_W = 32,
  localparam logic [31:0] LPARA_BLK_W = 128,
  localparam logic [31:0] LPARA_KEY_W = 256,
  localparam logic [31:0] LPARA_WORD_W = 32,
  localparam logic [31:0] LPARA_CFG_W = 611,
  localparam logic [31:0] LPARA_CMD_W = 6,
  localparam logic [31:0] LPARA_STS_W = 322,
  localparam logic [31:0] LPARA_WREQ_W = 38,
  localparam logic [31:0] LPARA_WRSP_W = 37,
  localparam logic [31:0] LPARA_EVT_W = 10,
  localparam logic [31:0] LPARA_CTXX_NUM = 24,
  localparam logic [31:0] LPARA_EXP_WORDS = 21,
  localparam logic [31:0] LPARA_THR_W = $clog2(PARA_FIFO_DEPTH) + 1,
  localparam logic [31:0] LPARA_PIO_BYTES = 4,
  localparam logic [31:0] LPARA_BLK_BYTES = 16,
  localparam logic [31:0] LPARA_AXI_BYTES = PARA_AXI_DATA_W / 8,
  localparam logic [31:0] LPARA_VER_MAJOR = 1,
  localparam logic [31:0] LPARA_VER_MINOR = 0,
  localparam logic [31:0] LPARA_TLEN_MAX = 4,
  localparam logic [31:0] LPARA_CFB_MAX = 7,
  // Accelerator mode codes (spec 9.3).
  localparam logic [31:0] LPARA_MODE_ECB = 0,
  localparam logic [31:0] LPARA_MODE_CBC = 1,
  localparam logic [31:0] LPARA_MODE_CFB = 2,
  localparam logic [31:0] LPARA_MODE_OFB = 3,
  localparam logic [31:0] LPARA_MODE_GCM = 5,
  // Event bit positions (spec 6.4, 9.3).
  localparam logic [31:0] LPARA_EVT_CERR = 2,
  localparam logic [31:0] LPARA_EVT_LERR = 3,
  localparam logic [31:0] LPARA_EVT_DINR = 5,
  localparam logic [31:0] LPARA_EVT_DOUR = 6,
  localparam logic [31:0] LPARA_EVT_CSWD = 7,
  localparam logic [31:0] LPARA_EVT_PERR = 9
) (
  // Clock and reset (BUS domain)
  input  wire                                    i_clk_bus,
  input  wire                                    i_rst_n_bus,

  // Version and capability constants
  output logic [15:0]                            o_ver_major,
  output logic [15:0]                            o_ver_minor,
  output logic [1:0]                             o_cap_axi_dw,
  output logic [1:0]                             o_cap_ghash,
  output logic [2:0]                             o_cap_lanes,
  output logic [2:0]                             o_cap_ctx_num,
  output logic                                   o_cap_ctx_exp,
  output logic [1:0]                             o_cap_policy,
  output logic                                   o_cap_async,
  output logic                                   o_cap_key_side,
  output logic                                   o_cap_axi_en,
  output logic                                   o_cap_gcm_en,

  // aesgcm_ctrl fields and their hardware clear {free, key_new, resume, suspend, zeroize,
  // abort, start}
  input  wire                                    i_ctrl_en,
  input  wire  [6:0]                             i_ctrl_cmd,
  output logic [6:0]                             o_ctrl_clr,

  // Message configuration registers
  input  wire  [2:0]                             i_cfg_mode,
  input  wire                                    i_cfg_decipher,
  input  wire                                    i_cfg_key_size,
  input  wire                                    i_cfg_key_src,
  input  wire                                    i_cfg_dat_src,
  input  wire  [1:0]                             i_cfg_gcm_pass,
  input  wire  [2:0]                             i_cfg_tag_len,
  input  wire  [3:0]                             i_cfg_cfb_seg,
  input  wire  [1:0]                             i_cfg_ctx_id,
  input  wire  [31:0]                            i_aad_len,
  input  wire  [31:0]                            i_data_len,
  input  wire  [15:0]                            i_keywait,
  input  wire  [LPARA_KEY_W-1:0]                 i_key_words,
  input  wire  [LPARA_BLK_W-1:0]                 i_iv_words,
  input  wire  [LPARA_BLK_W-1:0]                 i_tagin_words,
  output logic                                   o_key_clr,

  // Status registers
  output logic [LPARA_BLK_W-1:0]                 o_tagout_words,
  output logic                                   o_sts_busy,
  output logic                                   o_sts_tag_ok,
  output logic                                   o_sts_ver_ok,
  output logic                                   o_sts_zeroized,
  output logic                                   o_sts_sec_only,
  output logic                                   o_sts_key_ld,
  output logic [3:0]                             o_sts_phase,
  output logic [3:0]                             o_sts_ctx_vld,
  output logic [3:0]                             o_err_code,
  output logic [3:0]                             o_err_core,
  output logic [31:0]                            o_failcnt,
  output logic [31:0]                            o_cons_a,
  output logic [31:0]                            o_cons_d,
  output logic                                   o_fifo_in_full,
  output logic                                   o_fifo_out_empty,

  // Interrupt registers {perr, kerr, cswd, dour, dinr, cexh, lerr, cerr, tagf, done}
  input  wire  [LPARA_EVT_W-1:0]                 i_irq_raw,
  output logic [LPARA_EVT_W-1:0]                 o_irq_set,
  input  wire  [LPARA_EVT_W-1:0]                 i_irq_en,
  input  wire  [LPARA_EVT_W-1:0]                 i_irq_inj,
  output logic [LPARA_EVT_W-1:0]                 o_irq_sts,
  output logic                                   o_int,

  // DMA configuration and channel conditions
  input  wire                                    i_dma_in_en,
  input  wire                                    i_dma_out_en,
  input  wire  [2:0]                             i_dma_in_burst,
  input  wire  [2:0]                             i_dma_out_burst,
  output logic                                   o_dma_in_cond,
  output logic                                   o_dma_out_cond,

  // Context export window
  input  wire  [LPARA_CTXX_NUM*LPARA_WORD_W-1:0] i_ctxx_words,
  output logic [LPARA_CTXX_NUM-1:0]              o_ctxx_we,
  output logic [LPARA_WORD_W-1:0]                o_ctxx_wdata,

  // Crossings
  input  wire                                    i_sec_only,
  output logic                                   o_cfg_send,
  output logic [LPARA_CFG_W-1:0]                 o_cfg,
  input  wire                                    i_cfg_idle,
  input  wire                                    i_cfg_done,
  output logic                                   o_cmd_send,
  output logic [LPARA_CMD_W-1:0]                 o_cmd,
  input  wire                                    i_cmd_idle,
  input  wire                                    i_cmd_done,
  input  wire                                    i_sts_valid,
  input  wire  [LPARA_STS_W-1:0]                 i_sts,
  output logic                                   o_wreq_send,
  output logic [LPARA_WREQ_W-1:0]                o_wreq,
  input  wire                                    i_wreq_idle,
  input  wire                                    i_wreq_done,
  input  wire                                    i_wrsp_valid,
  input  wire  [LPARA_WRSP_W-1:0]                i_wrsp,

  // Data path control
  output logic                                   o_dat_src,
  output logic                                   o_in_flush,
  output logic                                   o_in_hold,
  output logic                                   o_in_load,
  output logic [31:0]                            o_in_aad_len,
  output logic [31:0]                            o_in_data_len,
  output logic [4:0]                             o_bpb,
  output logic [2:0]                             o_bpe,
  output logic [4:0]                             o_beat_bytes,
  output logic [LPARA_THR_W-1:0]                 o_in_full_thr,
  input  wire                                    i_in_active,
  input  wire                                    i_in_drop,
  input  wire                                    i_in_full,
  input  wire                                    i_beat_ready,
  input  wire                                    i_in_full_thr,
  output logic                                   o_out_flush,
  output logic                                   o_out_load,
  output logic [31:0]                            o_out_data_len,
  output logic [8:0]                             o_out_burst_bytes,
  input  wire                                    i_out_empty,
  input  wire                                    i_out_beat_valid,
  input  wire                                    i_out_dma_cond,
  input  wire                                    i_pio_perr
);

  // Error codes of aesgcm_err_code.code (spec 9.3).
  typedef enum logic [3:0] {
    ENUM_ERR_NONE  = 4'd0,
    ENUM_ERR_CFG   = 4'd1,
    ENUM_ERR_LEN   = 4'd2,
    ENUM_ERR_PROTO = 4'd5
  } err_type_def;

  // Internal signal declarations
  logic                     reg_busy;
  logic                     reg_start_sent;
  logic                     reg_res_sent;
  logic                     reg_res_wait;
  logic [3:0]               reg_cmd_sent;
  logic                     reg_klat_vld;
  logic                     reg_klat_size;
  logic [2:0]               reg_klat_tlen;
  logic                     reg_knew_p;
  logic                     reg_dat_src;
  logic [LPARA_STS_W-1:0]   reg_sts;
  err_type_def              reg_err_code;
  logic [3:0]               reg_err_core;
  logic                     reg_exp_act;
  logic                     reg_imp_act;
  logic                     reg_imp_done;
  logic                     reg_wwait;
  logic [4:0]               reg_widx;
  logic [LPARA_EVT_W-1:0]   reg_inj_q;
  logic                     reg_dma_in_q;
  logic                     reg_dma_out_q;
  logic                     reg_int;
  logic                     w_start_req;
  logic                     w_res_req;
  logic                     w_cfg_err;
  logic                     w_len_err;
  logic                     w_start_perr;
  logic                     w_res_perr;
  logic                     w_start_ok;
  logic                     w_res_ok;
  logic                     w_res_go;
  logic                     w_susp_bad;
  logic [3:0]               w_cmd_pend;
  logic                     w_cmd_fire;
  logic                     w_gcm;
  logic                     w_feedback;
  logic [4:0]               w_bpb;
  logic [2:0]               w_bpe;
  logic [4:0]               w_beat_bytes;
  logic [8:0]               w_in_burst_bytes;
  logic [8:0]               w_out_burst_bytes;
  logic [9:0]               w_in_need;
  logic [LPARA_BLK_W-1:0]   w_iv_blk;
  logic [LPARA_BLK_W-1:0]   w_tag_blk;
  logic [LPARA_KEY_W-1:0]   w_key_blk;
  logic                     w_op_res;
  logic                     w_s_msg_end;
  logic                     w_s_susp;
  logic                     w_s_res;
  logic                     w_s_ack;
  logic                     w_s_zeroized;
  logic [LPARA_EVT_W-1:0]   w_s_evt;
  logic [3:0]               w_s_err;
  logic [31:0]              w_s_rem_a;
  logic [31:0]              w_s_rem_d;
  logic [LPARA_EVT_W-1:0]   w_evt_bus;
  logic [LPARA_EVT_W-1:0]   w_s_evt_m;
  logic [LPARA_EVT_W-1:0]   w_evt_exp;
  logic                     w_exp_hold;
  logic                     w_exp_last;
  logic                     w_bus_perr;
  logic                     w_flush_cmd;

  // ------------------------------------------------------------------- constants

  // Version 1.0 and capability fields derived from the parameters.
  assign o_ver_major    = 16'(LPARA_VER_MAJOR);
  assign o_ver_minor    = 16'(LPARA_VER_MINOR);
  assign o_cap_axi_dw   = (PARA_AXI_DATA_W == 128) ? 2'd2 : ((PARA_AXI_DATA_W == 64) ? 2'd1 : 2'd0);
  assign o_cap_ghash    = 2'(PARA_GHASH_ARCH);
  assign o_cap_lanes    = 3'(PARA_AES_LANE_NUM);
  assign o_cap_ctx_num  = 3'(PARA_GCM_CTX_NUM);
  assign o_cap_ctx_exp  = (PARA_GCM_CTX_MODE == 1);
  assign o_cap_policy   = 2'(PARA_GCM_REL_POLICY);
  assign o_cap_async    = (PARA_CLK_ASYNC == 1);
  assign o_cap_key_side = (PARA_KEY_SIDE_EN == 1);
  assign o_cap_axi_en   = (PARA_AXI_EN == 1);
  assign o_cap_gcm_en   = (PARA_AES_GCM_EN == 1);

  // ------------------------------------------------------------------- byte order

  // CSR words to blocks: word k byte j (bits [8j +: 8]) is stream byte 4k + j.
  always_comb begin : p_com_blocks
    w_iv_blk  = '0;
    w_tag_blk = '0;
    w_key_blk = '0;
    for (int byt = 0; byt < LPARA_BLK_BYTES; byt++) begin
      w_iv_blk[LPARA_BLK_W-1-8*byt -: 8]  = i_iv_words[8*byt +: 8];
      w_tag_blk[LPARA_BLK_W-1-8*byt -: 8] = i_tagin_words[8*byt +: 8];
    end
    // A 256-bit key has byte 0 in bits [255:248]; a 128-bit key has byte 0 in bits [127:120].
    for (int byt = 0; byt < 2*LPARA_BLK_BYTES; byt++) begin
      if (i_cfg_key_size)
        w_key_blk[LPARA_KEY_W-1-8*byt -: 8] = i_key_words[8*byt +: 8];
      else if (byt < LPARA_BLK_BYTES)
        w_key_blk[LPARA_BLK_W-1-8*byt -: 8] = i_key_words[8*byt +: 8];
    end
  end

  // Tag block of the report to CSR words.
  always_comb begin : p_com_tagout
    o_tagout_words = '0;
    for (int byt = 0; byt < LPARA_BLK_BYTES; byt++)
      o_tagout_words[8*byt +: 8] = reg_sts[LPARA_BLK_W-1-8*byt -: 8];
  end

  // ------------------------------------------------------------------- message format

  // Bytes per block, blocks per entry, beat width and burst sizes of the configured message.
  assign w_gcm      = (i_cfg_mode == 3'(LPARA_MODE_GCM));
  assign w_feedback = ((i_cfg_mode == 3'(LPARA_MODE_CBC)) & ~i_cfg_decipher) |
                      (i_cfg_mode == 3'(LPARA_MODE_CFB)) | (i_cfg_mode == 3'(LPARA_MODE_OFB));

  always_comb begin : p_com_format
    w_bpb = 5'(LPARA_BLK_BYTES);
    if ((i_cfg_mode == 3'(LPARA_MODE_CFB)) && (i_cfg_cfb_seg < 4'd4))
      w_bpb = 5'd1;
    else if (i_cfg_mode == 3'(LPARA_MODE_CFB))
      w_bpb = 5'd1 << (i_cfg_cfb_seg - 4'd3);
    w_bpe        = w_feedback ? 3'd1 : 3'(PARA_AES_LANE_NUM);
    w_beat_bytes = i_cfg_dat_src ? 5'(LPARA_PIO_BYTES) : 5'(LPARA_AXI_BYTES);
    w_in_burst_bytes  = 9'(w_beat_bytes) << i_dma_in_burst;
    w_out_burst_bytes = 9'(w_beat_bytes) << i_dma_out_burst;
    // Entries needed for one input burst plus the entry being packed.
    // A burst is at most 256 bytes and an entry at most 64 bytes (10-bit by 7-bit divider).
    w_in_need = ((10'(w_in_burst_bytes) + 10'(7'(w_bpb) * 7'(w_bpe)) - 10'd1) /
                 10'(7'(w_bpb) * 7'(w_bpe))) + 10'd1;
  end

  // ------------------------------------------------------------------- start legality

  // Configuration errors of ERR-001 checked at start.
  always_comb begin : p_com_cfg_err
    w_cfg_err = 1'b0;
    if (i_cfg_mode > 3'(LPARA_MODE_GCM))
      w_cfg_err = 1'b1;
    if (w_gcm && (PARA_AES_GCM_EN == 0))
      w_cfg_err = 1'b1;
    if ((i_cfg_mode == 3'(LPARA_MODE_CFB)) && (i_cfg_cfb_seg > 4'(LPARA_CFB_MAX)))
      w_cfg_err = 1'b1;
    if (!i_cfg_dat_src && (PARA_AXI_EN == 0))
      w_cfg_err = 1'b1;
    if (i_dma_in_en && (w_in_need > 10'(PARA_FIFO_DEPTH)))
      w_cfg_err = 1'b1;
    if (w_gcm) begin
      if ((i_cfg_tag_len > 3'(LPARA_TLEN_MAX)) || (i_cfg_gcm_pass == 2'd3))
        w_cfg_err = 1'b1;
      if (!reg_klat_vld || (reg_klat_size != i_cfg_key_size) || (reg_klat_tlen != i_cfg_tag_len))
        w_cfg_err = 1'b1;
      if (!i_cfg_decipher && (i_cfg_gcm_pass != 2'd0))
        w_cfg_err = 1'b1;
      if (i_cfg_decipher && (i_cfg_gcm_pass == 2'd0) &&
          ((PARA_GCM_REL_POLICY == 0) || i_sec_only))
        w_cfg_err = 1'b1;
      if (i_cfg_decipher && (i_cfg_gcm_pass != 2'd0) && (PARA_GCM_REL_POLICY == 1))
        w_cfg_err = 1'b1;
      if ((i_cfg_gcm_pass == 2'd2) && (i_aad_len != '0))
        w_cfg_err = 1'b1;
      if ((PARA_GCM_CTX_MODE == 0) && (PARA_GCM_CTX_NUM > 0) &&
          (32'(i_cfg_ctx_id) >= PARA_GCM_CTX_NUM))
        w_cfg_err = 1'b1;
    end else if (i_aad_len != '0) begin
      w_cfg_err = 1'b1;
    end
  end

  // Length errors detectable at start (ERR-002) and protocol errors of a start (ERR-005).
  assign w_len_err    = ~w_gcm & ((i_data_len == '0) |
                                  (((i_cfg_mode == 3'(LPARA_MODE_ECB)) | (i_cfg_mode == 3'(LPARA_MODE_CBC))) &
                                   (i_data_len[3:0] != 4'd0)));
  assign w_start_perr = reg_busy | (w_gcm & (i_cfg_gcm_pass == 2'd2) & ~o_sts_ver_ok);

  // Start and resume requests not yet sent; abort written together with start cancels start.
  assign w_start_req = i_ctrl_en & i_ctrl_cmd[0] & ~reg_start_sent & ~i_ctrl_cmd[1] & ~i_ctrl_cmd[2];
  assign w_res_req   = i_ctrl_en & i_ctrl_cmd[4] & ~reg_res_sent & ~reg_imp_act & ~reg_imp_done &
                       ~i_ctrl_cmd[0];
  assign w_start_ok  = w_start_req & i_cfg_idle & ~w_cfg_err & ~w_len_err & ~w_start_perr;

  // Resume checks: not busy, context built, slot valid (internal slots), export not blocked.
  assign w_res_perr = reg_busy | (PARA_AES_GCM_EN == 0) |
                      ((PARA_GCM_CTX_MODE == 0) & ((PARA_GCM_CTX_NUM == 0) |
                                                   ~o_sts_ctx_vld[i_cfg_ctx_id]));
  assign w_res_ok   = w_res_req & ~w_res_perr & ~((PARA_GCM_CTX_MODE == 1) & i_sec_only);
  // The resume bundle leaves after the import of the export mode, or at once for slots.
  assign w_res_go   = i_cfg_idle & ((reg_imp_done & ~reg_res_sent) |
                                    (w_res_ok & (PARA_GCM_CTX_MODE == 0)));

  // Suspend while no message is active is a protocol error and is not sent.
  assign w_susp_bad = i_ctrl_cmd[3] & ~reg_cmd_sent[1] & ~reg_busy;

  // ------------------------------------------------------------------- bundles

  // Configuration bundle of CDC-001 (layout in m_aesgcm_seq).
  assign w_op_res   = ~w_start_ok;
  assign o_cfg_send = w_start_ok | w_res_go;
  assign o_cfg      = {w_op_res, i_cfg_mode, i_cfg_decipher, i_cfg_key_size, i_cfg_key_src,
                       reg_knew_p, i_cfg_gcm_pass, i_cfg_tag_len, i_cfg_cfb_seg, i_cfg_ctx_id,
                       i_keywait, i_aad_len, i_data_len, w_iv_blk, w_tag_blk, w_key_blk};

  // Command bundle of CDC-005: {abort, zeroize, suspend, free, ctx_id}.
  assign w_cmd_pend = {i_ctrl_cmd[1], i_ctrl_cmd[2], i_ctrl_cmd[3] & reg_busy, i_ctrl_cmd[6]} &
                      ~reg_cmd_sent;
  assign w_cmd_fire = (|w_cmd_pend) & i_cmd_idle;
  assign o_cmd_send = w_cmd_fire;
  assign o_cmd      = {w_cmd_pend, i_cfg_ctx_id};
  assign w_flush_cmd = w_cmd_fire & (w_cmd_pend[3] | w_cmd_pend[2]);

  // Word requests of CDC-007: export {0, index, 0}, import {1, index, word}.
  assign o_wreq_send = (reg_exp_act | reg_imp_act) & ~reg_wwait & i_wreq_idle;
  assign o_wreq      = {reg_imp_act, reg_widx, i_ctxx_words[LPARA_WORD_W*reg_widx +: LPARA_WORD_W]};

  // ------------------------------------------------------------------- report fields

  // Status report fields (layout in m_aesgcm_seq).
  assign w_s_msg_end  = i_sts[LPARA_STS_W-1];
  assign w_s_susp     = i_sts[LPARA_STS_W-2];
  assign w_s_res      = i_sts[LPARA_STS_W-3];
  assign w_s_ack      = i_sts[LPARA_STS_W-4];
  assign w_s_zeroized = i_sts[LPARA_STS_W-7];
  assign w_s_evt      = i_sts[LPARA_STS_W-9 -: LPARA_EVT_W];
  assign w_s_err      = i_sts[LPARA_STS_W-19 -: 4];
  assign w_s_rem_a    = i_sts[LPARA_BLK_W + 32 +: 32];
  assign w_s_rem_d    = i_sts[LPARA_BLK_W +: 32];

  // Status register outputs from the last report.
  assign o_sts_busy       = reg_busy;
  assign o_sts_tag_ok     = reg_sts[LPARA_STS_W-5];
  assign o_sts_ver_ok     = reg_sts[LPARA_STS_W-6];
  assign o_sts_zeroized   = reg_sts[LPARA_STS_W-7];
  assign o_sts_key_ld     = reg_sts[LPARA_STS_W-8];
  assign o_sts_phase      = reg_sts[LPARA_STS_W-27 -: 4];
  assign o_sts_ctx_vld    = reg_sts[LPARA_STS_W-31 -: 4];
  assign o_failcnt        = reg_sts[LPARA_STS_W-35 -: 32];
  assign o_cons_a         = reg_sts[LPARA_BLK_W + 3*32 +: 32];
  assign o_cons_d         = reg_sts[LPARA_BLK_W + 2*32 +: 32];
  assign o_sts_sec_only   = i_sec_only;
  assign o_err_code       = reg_err_code;
  assign o_err_core       = reg_err_core;
  // The flag reads 1 when the input path cannot take another word (FIFO full and the beat buffer of
  // the packer occupied, or a resume wait): a write that finds it 0 is always accepted (DEC-028).
  assign o_fifo_in_full   = ~i_beat_ready | o_in_hold;
  // The flag reads 0 only when a beat is ready, so a read that finds it 0 is always served; the
  // unpacker needs some clocks to build a beat from the FIFO entry (DEC-035).
  assign o_fifo_out_empty = ~i_out_beat_valid;

  // ------------------------------------------------------------------- data path control

  // Packer and unpacker loads at start and after a resume report; flush on abort or zeroize
  // and, for the input side, after a suspend report or a message that ended with an error.
  assign o_dat_src         = reg_dat_src;
  assign o_in_flush        = w_flush_cmd | (i_sts_valid & (w_s_susp | (w_s_msg_end & (w_s_err != 4'd0))));
  assign o_out_flush       = w_flush_cmd;
  assign o_in_load         = w_start_ok | (i_sts_valid & w_s_res);
  // Resume hold (DEC-027): from the accepted resume request until the report that carries the
  // restored lengths, the data path accepts no beat and the input FIFO reads as full.
  assign o_in_hold         = reg_res_wait | w_res_ok;
  assign o_out_load        = o_in_load;
  assign o_in_aad_len      = w_start_ok ? i_aad_len : w_s_rem_a;
  assign o_in_data_len     = w_start_ok ? i_data_len : w_s_rem_d;
  assign o_out_data_len    = (w_start_ok & w_gcm & (i_cfg_gcm_pass == 2'd1)) ? 32'd0 : o_in_data_len;
  assign o_bpb             = w_start_ok ? w_bpb : 5'(LPARA_BLK_BYTES);
  assign o_bpe             = w_start_ok ? w_bpe : 3'(PARA_AES_LANE_NUM);
  assign o_beat_bytes      = w_beat_bytes;
  assign o_out_burst_bytes = w_out_burst_bytes;
  assign o_in_full_thr     = LPARA_THR_W'(32'(PARA_FIFO_DEPTH) + 32'd1 - 32'(w_in_need));

  // DMA conditions of spec 6.3.4.
  assign o_dma_in_cond  = i_dma_in_en & i_in_active & ~i_in_full_thr;
  assign o_dma_out_cond = i_dma_out_en & i_out_dma_cond;

  // ------------------------------------------------------------------- events

  // Bus-side events: configuration and length errors at start, protocol errors, DMA ready
  // transitions, and injection rising edges.
  assign w_bus_perr = i_pio_perr | i_in_drop | (w_start_req & i_cfg_idle & ~w_cfg_err & ~w_len_err &
                                                w_start_perr) |
                      (w_res_req & w_res_perr) | w_susp_bad;

  always_comb begin : p_com_evt_bus
    w_evt_bus = i_irq_inj & ~reg_inj_q;
    w_evt_bus[LPARA_EVT_CERR] = w_evt_bus[LPARA_EVT_CERR] | (w_start_req & i_cfg_idle & w_cfg_err) |
                                (w_res_req & (PARA_GCM_CTX_MODE == 1) & i_sec_only);
    w_evt_bus[LPARA_EVT_LERR] = w_evt_bus[LPARA_EVT_LERR] | (w_start_req & i_cfg_idle & ~w_cfg_err &
                                                             w_len_err);
    w_evt_bus[LPARA_EVT_DINR] = w_evt_bus[LPARA_EVT_DINR] | (o_dma_in_cond & ~reg_dma_in_q);
    w_evt_bus[LPARA_EVT_DOUR] = w_evt_bus[LPARA_EVT_DOUR] | (o_dma_out_cond & ~reg_dma_out_q);
    w_evt_bus[LPARA_EVT_PERR] = w_evt_bus[LPARA_EVT_PERR] | w_bus_perr;
  end

  // Export mode (DEC-037, DEC-039): CTX_SWITCH_DONE of a suspend (any report that is not a resume
  // report) is replaced by the event raised when the export has loaded the last word into
  // aesgcm_ctxx, so that software reads a complete image after the event. A suspend that cannot
  // export (secure-only pin) is a configuration error and keeps the event.
  assign w_exp_hold = (PARA_GCM_CTX_MODE == 1) & ~w_s_res & ~i_sec_only;
  assign w_exp_last = reg_exp_act & i_wrsp_valid & (reg_widx == 5'(LPARA_EXP_WORDS - 1));

  always_comb begin : p_com_evt_exp
    w_s_evt_m = w_s_evt;
    w_evt_exp = '0;
    if (w_exp_hold)
      w_s_evt_m[LPARA_EVT_CSWD] = 1'b0;
    w_evt_exp[LPARA_EVT_CSWD] = w_exp_last;
    w_evt_exp[LPARA_EVT_CERR] = (PARA_GCM_CTX_MODE == 1) & i_sts_valid & w_s_susp & i_sec_only;
  end

  // Raw event loads (value 1), status = raw and enable, registered interrupt line.
  assign o_irq_set = w_evt_bus | w_evt_exp | (i_sts_valid ? w_s_evt_m : '0);
  assign o_irq_sts = i_irq_raw & i_irq_en;
  assign o_int     = reg_int;

  // Hardware clear of the command bits: start and resume when their bundle is accepted, or at
  // once when rejected; abort, zeroize and suspend when a report acknowledges the commands;
  // free when its command bundle is accepted; key_new at once.
  assign o_ctrl_clr[0] = (reg_start_sent & i_cfg_done) |
                         (w_start_req & i_cfg_idle & (w_cfg_err | w_len_err | w_start_perr)) |
                         (i_ctrl_cmd[0] & i_ctrl_cmd[1]);
  assign o_ctrl_clr[1] = i_sts_valid & w_s_ack & reg_cmd_sent[3];
  assign o_ctrl_clr[2] = i_sts_valid & w_s_ack & reg_cmd_sent[2];
  assign o_ctrl_clr[3] = (i_sts_valid & w_s_ack & reg_cmd_sent[1]) | w_susp_bad;
  assign o_ctrl_clr[4] = (reg_res_sent & i_cfg_done) | (w_res_req & ~w_res_ok);
  assign o_ctrl_clr[5] = i_ctrl_cmd[5];
  assign o_ctrl_clr[6] = i_cmd_done & reg_cmd_sent[0];

  // The APB key registers are cleared when a report confirms a completed zeroize.
  assign o_key_clr = i_sts_valid & w_s_zeroized & reg_cmd_sent[2];

  // Export words load the window registers.
  always_comb begin : p_com_ctxx_we
    o_ctxx_we = '0;
    for (int idx = 0; idx < LPARA_CTXX_NUM; idx++) begin
      if (i_wrsp_valid && reg_exp_act && (i_wrsp[32 +: 5] == 5'(idx)))
        o_ctxx_we[idx] = 1'b1;
    end
  end

  assign o_ctxx_wdata = i_wrsp[LPARA_WORD_W-1:0];

  // ------------------------------------------------------------------- registers

  // Message flags, key latch and command tracking.
  always_ff @(posedge i_clk_bus, negedge i_rst_n_bus) begin : p_ff_msg
    if (!i_rst_n_bus) begin
      reg_busy       <= 1'b0;
      reg_start_sent <= 1'b0;
      reg_res_sent   <= 1'b0;
      reg_cmd_sent   <= '0;
      reg_klat_vld   <= 1'b0;
      reg_klat_size  <= 1'b0;
      reg_klat_tlen  <= '0;
      reg_knew_p     <= 1'b0;
      reg_dat_src    <= 1'b1;
    end else begin
      if (w_start_ok || w_res_go || (w_res_ok && (PARA_GCM_CTX_MODE == 1)))
        reg_busy <= 1'b1;
      else if (i_sts_valid && (w_s_msg_end || (w_s_ack && (|reg_cmd_sent[3:2]))))
        reg_busy <= 1'b0;
      if (w_start_ok) begin
        reg_start_sent <= 1'b1;
        reg_knew_p     <= 1'b0;
        reg_dat_src    <= i_cfg_dat_src;
      end else if (i_cfg_done) begin
        reg_start_sent <= 1'b0;
      end
      if (w_res_go) begin
        reg_res_sent <= 1'b1;
        reg_dat_src  <= i_cfg_dat_src;
      end else if (i_cfg_done) begin
        reg_res_sent <= 1'b0;
      end
      if (w_cmd_fire)
        reg_cmd_sent <= reg_cmd_sent | w_cmd_pend;
      if (i_sts_valid && w_s_ack)
        reg_cmd_sent[3:1] <= '0;
      if (i_cmd_done)
        reg_cmd_sent[0] <= 1'b0;
      if (i_ctrl_cmd[5]) begin
        reg_klat_vld  <= 1'b1;
        reg_klat_size <= i_cfg_key_size;
        reg_klat_tlen <= i_cfg_tag_len;
        reg_knew_p    <= 1'b1;
      end else if (o_key_clr) begin
        reg_klat_vld <= 1'b0;
      end
    end
  end

  // Resume wait flag: set with the accepted resume request, cleared by the resume report, a message
  // end (error) or abort and zeroize.
  always_ff @(posedge i_clk_bus, negedge i_rst_n_bus) begin : p_ff_res_wait
    if (!i_rst_n_bus)
      reg_res_wait <= 1'b0;
    else if (w_flush_cmd || (i_sts_valid && (w_s_res || w_s_msg_end)))
      reg_res_wait <= 1'b0;
    else if (w_res_ok)
      reg_res_wait <= 1'b1;
  end

  // Last status report and the error code: a start clears the code, a start-time error (also the
  // protocol error of a start that is refused while no message is active, DEC-031) sets it, a
  // report with a nonzero code sets it, a runtime protocol error sets it when it is 0.
  always_ff @(posedge i_clk_bus, negedge i_rst_n_bus) begin : p_ff_sts
    if (!i_rst_n_bus) begin
      reg_sts      <= '0;
      reg_err_code <= ENUM_ERR_NONE;
      reg_err_core <= '0;
    end else begin
      if (i_sts_valid)
        reg_sts <= i_sts;
      casez ({w_start_ok, w_start_req & i_cfg_idle & w_cfg_err,
              w_start_req & i_cfg_idle & w_len_err,
              w_start_req & i_cfg_idle & ~w_cfg_err & ~w_len_err & ~reg_busy & w_start_perr,
              i_sts_valid & (w_s_err != 4'd0),
              w_bus_perr & (reg_err_code == ENUM_ERR_NONE)})
        6'b1?????: begin
          reg_err_code <= ENUM_ERR_NONE;
          reg_err_core <= '0;
        end
        6'b01????: reg_err_code <= ENUM_ERR_CFG;
        6'b001???: reg_err_code <= ENUM_ERR_LEN;
        6'b0001??: reg_err_code <= ENUM_ERR_PROTO;
        6'b00001?: begin
          reg_err_code <= err_type_def'(w_s_err);
          reg_err_core <= i_sts[LPARA_STS_W-23 -: 4];
        end
        6'b000001: reg_err_code <= ENUM_ERR_PROTO;
        default:  reg_err_code <= reg_err_code;
      endcase
    end
  end

  // Export after a suspend report (export mode, not secure-only) and import before a resume:
  // one word request at a time, indexes 0 to LPARA_EXP_WORDS - 1.
  always_ff @(posedge i_clk_bus, negedge i_rst_n_bus) begin : p_ff_xfer
    if (!i_rst_n_bus) begin
      reg_exp_act  <= 1'b0;
      reg_imp_act  <= 1'b0;
      reg_imp_done <= 1'b0;
      reg_wwait    <= 1'b0;
      reg_widx     <= '0;
    end else begin
      if (o_wreq_send)
        reg_wwait <= 1'b1;
      if ((reg_exp_act && i_wrsp_valid) || (reg_imp_act && i_wreq_done)) begin
        reg_wwait <= 1'b0;
        reg_widx  <= reg_widx + 5'd1;
        if (reg_widx == 5'(LPARA_EXP_WORDS - 1)) begin
          reg_widx     <= '0;
          reg_exp_act  <= 1'b0;
          reg_imp_done <= reg_imp_act;
          reg_imp_act  <= 1'b0;
        end
      end
      if ((PARA_GCM_CTX_MODE == 1) && i_sts_valid && w_s_susp && !i_sec_only) begin
        reg_exp_act <= 1'b1;
        reg_widx    <= '0;
      end
      if ((PARA_GCM_CTX_MODE == 1) && w_res_ok) begin
        reg_imp_act <= 1'b1;
        reg_widx    <= '0;
      end
      if (w_res_go)
        reg_imp_done <= 1'b0;
    end
  end

  // Edge detectors and the interrupt line.
  always_ff @(posedge i_clk_bus, negedge i_rst_n_bus) begin : p_ff_irq
    if (!i_rst_n_bus) begin
      reg_inj_q     <= '0;
      reg_dma_in_q  <= 1'b0;
      reg_dma_out_q <= 1'b0;
      reg_int       <= 1'b0;
    end else begin
      reg_inj_q     <= i_irq_inj;
      reg_dma_in_q  <= o_dma_in_cond;
      reg_dma_out_q <= o_dma_out_cond;
      reg_int       <= |o_irq_sts;
    end
  end

endmodule
