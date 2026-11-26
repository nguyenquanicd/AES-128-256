/*
 * Project      : AES-GCM Accelerator
 * Author       : Nguyen Hung Quan and Claude (user)
 * AI Flow      : VLSIT RTL Generator AI Automation Flow
 * AI Flow Page : https://github.com/nguyenquanicd/VLSIT_RTL_Generator_AI_Model
 * Date         : 2026-11-25
 * Description  : CORE-domain structure (spec 5.1, 14.2): sequencer, key store, input and output
 *                formatters, GHASH, tag unit, context engine and the existing AES core
 *                m_aes128_256_batch_top (REF-008). With PARA_AES_GCM_EN = 0 the GHASH unit, the
 *                tag unit and the context engine are not elaborated and their sequencer inputs
 *                are tied to the idle values.
 * Deviation    : HIE-02 (SHOULD) - the tie-off values of the blocks that a configuration does
 *                not elaborate are assigned in the generate branches of this structural module.
 */
`timescale 1ns/1ps

module m_aesgcm_core_dom #(
  // Parameter Description: number of 128-bit AES block lanes of the AES core.
  // Parameter values: 1 to 4; default is 1.
  // Parameter unit: lane
  parameter logic [31:0] PARA_AES_LANE_NUM = 1,
  // Parameter Description: 1 builds GHASH, tag, J0 and policy logic (mode code 5).
  // Parameter values: 0 or 1; default is 1.
  // Parameter unit: none
  parameter logic [31:0] PARA_AES_GCM_EN = 1,
  // Parameter Description: GHASH architecture; 0 digit-serial, 1 single, 2 aggregated.
  // Parameter values: 0, 1 or 2; default is 1.
  // Parameter unit: none
  parameter logic [31:0] PARA_GHASH_ARCH = 1,
  // Parameter Description: bits per clock of the digit-serial multiplier.
  // Parameter values: 4, 8, 16, 32 or 64; default is 16.
  // Parameter unit: bit
  parameter logic [31:0] PARA_GHASH_DIGIT_W = 16,
  // Parameter Description: feed-forward pipeline stage of the parallel GHASH.
  // Parameter values: 0 or 1; default is 0.
  // Parameter unit: none
  parameter logic [31:0] PARA_GHASH_PIPE = 0,
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
  localparam logic [31:0] LPARA_BLK_W = 128,
  localparam logic [31:0] LPARA_KEY_W = 256,
  localparam logic [31:0] LPARA_DATA_W = PARA_AES_LANE_NUM * LPARA_BLK_W,
  localparam logic [31:0] LPARA_ENT_IN_W = LPARA_DATA_W + PARA_AES_LANE_NUM + 2,
  localparam logic [31:0] LPARA_ENT_OUT_W = LPARA_DATA_W + PARA_AES_LANE_NUM + 1,
  localparam logic [31:0] LPARA_CFG_W = 611,
  localparam logic [31:0] LPARA_CMD_W = 6,
  localparam logic [31:0] LPARA_STS_W = 322,
  localparam logic [31:0] LPARA_WREQ_W = 38,
  localparam logic [31:0] LPARA_WRSP_W = 37,
  localparam logic [31:0] LPARA_SLOT_W = 1056,
  localparam logic [31:0] LPARA_CTR_W = 32,
  localparam logic [31:0] LPARA_KEYWAIT_LSB = 576,
  localparam logic [31:0] LPARA_CTX_EN = ((PARA_AES_GCM_EN == 1) &&
                                          ((PARA_GCM_CTX_MODE == 1) || (PARA_GCM_CTX_NUM > 0))) ?
                                         1 : 0,
  localparam logic [31:0] LPARA_CTX_SLOTS = (PARA_GCM_CTX_NUM > 0) ? PARA_GCM_CTX_NUM : 1
) (
  // Clock and reset (CORE domain)
  input  wire                        i_clk_core,
  input  wire                        i_rst_n_core,

  // Bundles of the crossings
  input  wire                        i_cfg_valid,
  input  wire  [LPARA_CFG_W-1:0]     i_cfg,
  output logic                       o_cfg_clr,
  input  wire                        i_cmd_valid,
  input  wire  [LPARA_CMD_W-1:0]     i_cmd,
  output logic                       o_sts_send,
  output logic [LPARA_STS_W-1:0]     o_sts,
  input  wire                        i_sts_idle,
  input  wire                        i_wreq_valid,
  input  wire  [LPARA_WREQ_W-1:0]    i_wreq,
  output logic                       o_wrsp_send,
  output logic [LPARA_WRSP_W-1:0]    o_wrsp,
  input  wire                        i_wrsp_idle,
  input  wire                        i_sec_only,

  // Input FIFO read side
  input  wire                        i_in_empty,
  input  wire  [LPARA_ENT_IN_W-1:0]  i_in_ent,
  output logic                       o_in_rd_en,

  // Output FIFO write side
  output logic                       o_out_wr_en,
  output logic [LPARA_ENT_OUT_W-1:0] o_out_ent,
  input  wire                        i_out_full,
  output logic                       o_out_flush,
  input  wire                        i_out_flush_busy,

  // Key side-load (IF-005)
  input  wire                        i_key_side_valid,
  input  wire                        i_key_side_size,
  input  wire  [LPARA_KEY_W-1:0]     i_key_side,
  output logic                       o_key_side_ack
);

  // Internal signal declarations
  logic                         w_key_zeroize;
  logic                         w_key_load;
  logic                         w_key_src;
  logic                         w_key_restore;
  logic [LPARA_KEY_W-1:0]       w_key_ctx;
  logic [LPARA_KEY_W-1:0]       w_key;
  logic                         w_key_ready;
  logic                         w_key_err;
  logic                         w_key_ld;
  logic                         w_aes_cfg_valid;
  logic                         w_aes_cfg_ready;
  logic                         w_aes_cfg_key_size;
  logic [2:0]                   w_aes_cfg_mode;
  logic                         w_aes_cfg_decipher;
  logic [LPARA_BLK_W-1:0]       w_aes_cfg_iv;
  logic [3:0]                   w_aes_cfg_cfb;
  logic                         w_aes_in_valid;
  logic                         w_aes_in_ready;
  logic [LPARA_DATA_W-1:0]      w_aes_in_data;
  logic [PARA_AES_LANE_NUM-1:0] w_aes_in_lane;
  logic                         w_aes_in_last;
  logic                         w_aes_out_valid;
  logic                         w_aes_out_ready;
  logic [LPARA_DATA_W-1:0]      w_aes_out_data;
  logic [PARA_AES_LANE_NUM-1:0] w_aes_out_lane;
  logic                         w_aes_out_last_unused;
  logic                         w_aes_err_valid;
  logic [3:0]                   w_aes_err_code;
  logic                         w_aes_zeroize;
  logic                         w_aes_zeroize_done;
  logic                         w_fin_seg;
  logic [31:0]                  w_fin_rem;
  logic [4:0]                   w_bpb;
  logic [LPARA_DATA_W-1:0]      w_fin_data;
  logic [PARA_AES_LANE_NUM-1:0] w_fin_mask;
  logic [2:0]                   w_fin_cnt;
  logic [31:0]                  w_fin_bytes;
  logic                         w_fin_seg_end_unused;
  logic                         w_fin_seg_err;
  logic [31:0]                  w_fout_rem;
  logic [LPARA_DATA_W-1:0]      w_fout_data;
  logic [31:0]                  w_fout_bytes;
  logic                         w_fout_last_unused;
  logic                         w_gh_zeroize;
  logic                         w_gh_clr;
  logic                         w_gh_load_y;
  logic [LPARA_BLK_W-1:0]       w_gh_y_in;
  logic [LPARA_BLK_W-1:0]       w_gh_h;
  logic                         w_gh_pow_start;
  logic                         w_gh_pow_done;
  logic                         w_gh_valid;
  logic                         w_gh_ready;
  logic [LPARA_DATA_W-1:0]      w_gh_data;
  logic [PARA_AES_LANE_NUM-1:0] w_gh_mask;
  logic [LPARA_BLK_W-1:0]       w_gh_y;
  logic                         w_gh_idle;
  logic [LPARA_BLK_W-1:0]       w_tag_ej0;
  logic [2:0]                   w_tag_len;
  logic [LPARA_BLK_W-1:0]       w_tag_exp;
  logic [LPARA_BLK_W-1:0]       w_tag;
  logic                         w_tag_match;
  logic                         w_ctx_zeroize;
  logic                         w_ctx_save;
  logic                         w_ctx_load;
  logic                         w_ctx_free;
  logic [1:0]                   w_ctx_slot;
  logic [LPARA_SLOT_W-1:0]      w_ctx_img_live;
  logic [LPARA_SLOT_W-1:0]      w_ctx_img;
  logic                         w_ctx_done;
  logic [3:0]                   w_ctx_vld;

  // Message sequencer.
  m_aesgcm_seq #(
    .PARA_LANE_NUM   (PARA_AES_LANE_NUM),
    .PARA_AES_GCM_EN (PARA_AES_GCM_EN),
    .PARA_CTX_EN     (LPARA_CTX_EN),
    .PARA_CTX_MODE   (PARA_GCM_CTX_MODE)
  ) u_seq (
    .i_clk_core         (i_clk_core),
    .i_rst_n_core       (i_rst_n_core),
    .i_cfg_valid        (i_cfg_valid),
    .i_cfg              (i_cfg),
    .o_cfg_clr          (o_cfg_clr),
    .i_cmd_valid        (i_cmd_valid),
    .i_cmd              (i_cmd),
    .o_key_zeroize      (w_key_zeroize),
    .o_key_load         (w_key_load),
    .o_key_src          (w_key_src),
    .o_key_restore      (w_key_restore),
    .o_key_ctx          (w_key_ctx),
    .i_key              (w_key),
    .i_key_ready        (w_key_ready),
    .i_key_err          (w_key_err),
    .i_key_ld           (w_key_ld),
    .o_aes_cfg_valid    (w_aes_cfg_valid),
    .i_aes_cfg_ready    (w_aes_cfg_ready),
    .o_aes_cfg_key_size (w_aes_cfg_key_size),
    .o_aes_cfg_mode     (w_aes_cfg_mode),
    .o_aes_cfg_decipher (w_aes_cfg_decipher),
    .o_aes_cfg_iv       (w_aes_cfg_iv),
    .o_aes_cfg_cfb      (w_aes_cfg_cfb),
    .o_aes_in_valid     (w_aes_in_valid),
    .i_aes_in_ready     (w_aes_in_ready),
    .o_aes_in_data      (w_aes_in_data),
    .o_aes_in_lane      (w_aes_in_lane),
    .o_aes_in_last      (w_aes_in_last),
    .i_aes_out_valid    (w_aes_out_valid),
    .o_aes_out_ready    (w_aes_out_ready),
    .i_aes_out_data     (w_aes_out_data),
    .i_aes_out_lane     (w_aes_out_lane),
    .i_aes_err_valid    (w_aes_err_valid),
    .i_aes_err_code     (w_aes_err_code),
    .o_aes_zeroize      (w_aes_zeroize),
    .i_aes_zeroize_done (w_aes_zeroize_done),
    .i_in_empty         (i_in_empty),
    .o_in_rd_en         (o_in_rd_en),
    .o_fin_seg          (w_fin_seg),
    .o_fin_rem          (w_fin_rem),
    .o_bpb              (w_bpb),
    .i_fin_data         (w_fin_data),
    .i_fin_mask         (w_fin_mask),
    .i_fin_cnt          (w_fin_cnt),
    .i_fin_bytes        (w_fin_bytes),
    .i_fin_seg_err      (w_fin_seg_err),
    .o_fout_rem         (w_fout_rem),
    .i_fout_data        (w_fout_data),
    .i_fout_bytes       (w_fout_bytes),
    .i_out_full         (i_out_full),
    .o_out_wr_en        (o_out_wr_en),
    .o_out_flush        (o_out_flush),
    .i_out_flush_busy   (i_out_flush_busy),
    .o_gh_zeroize       (w_gh_zeroize),
    .o_gh_clr           (w_gh_clr),
    .o_gh_load_y        (w_gh_load_y),
    .o_gh_y             (w_gh_y_in),
    .o_gh_h             (w_gh_h),
    .o_gh_pow_start     (w_gh_pow_start),
    .i_gh_pow_done      (w_gh_pow_done),
    .o_gh_valid         (w_gh_valid),
    .i_gh_ready         (w_gh_ready),
    .o_gh_data          (w_gh_data),
    .o_gh_mask          (w_gh_mask),
    .i_gh_y             (w_gh_y),
    .i_gh_idle          (w_gh_idle),
    .o_tag_ej0          (w_tag_ej0),
    .o_tag_len          (w_tag_len),
    .o_tag_exp          (w_tag_exp),
    .i_tag              (w_tag),
    .i_tag_match        (w_tag_match),
    .o_ctx_zeroize      (w_ctx_zeroize),
    .o_ctx_save         (w_ctx_save),
    .o_ctx_load         (w_ctx_load),
    .o_ctx_free         (w_ctx_free),
    .o_ctx_slot         (w_ctx_slot),
    .o_ctx_img          (w_ctx_img_live),
    .i_ctx_img          (w_ctx_img),
    .i_ctx_done         (w_ctx_done),
    .i_ctx_vld          (w_ctx_vld),
    .o_sts_send         (o_sts_send),
    .o_sts              (o_sts),
    .i_sts_idle         (i_sts_idle)
  );

  // Key store; the APB key and the key wait are taken from the configuration bundle.
  m_aesgcm_key_sel #(
    .PARA_KEY_SIDE_EN (PARA_KEY_SIDE_EN)
  ) u_key_sel (
    .i_clk_core       (i_clk_core),
    .i_rst_n_core     (i_rst_n_core),
    .i_zeroize        (w_key_zeroize),
    .i_load           (w_key_load),
    .i_key_src        (w_key_src),
    .i_key_size       (w_aes_cfg_key_size),
    .i_key_cfg        (i_cfg[LPARA_KEY_W-1:0]),
    .i_keywait        (i_cfg[LPARA_KEYWAIT_LSB +: 16]),
    .i_restore        (w_key_restore),
    .i_key_ctx        (w_key_ctx),
    .i_key_side_valid (i_key_side_valid),
    .i_key_side_size  (i_key_side_size),
    .i_key_side       (i_key_side),
    .o_key_side_ack   (o_key_side_ack),
    .o_key            (w_key),
    .o_key_ready      (w_key_ready),
    .o_key_err        (w_key_err),
    .o_key_ld         (w_key_ld)
  );

  // Input entry decoder.
  m_aesgcm_fmt_in #(
    .PARA_LANE_NUM (PARA_AES_LANE_NUM)
  ) u_fmt_in (
    .i_ent     (i_in_ent),
    .i_seg_exp (w_fin_seg),
    .i_rem     (w_fin_rem),
    .i_bpb     (w_bpb),
    .o_data    (w_fin_data),
    .o_mask    (w_fin_mask),
    .o_blk_cnt (w_fin_cnt),
    .o_bytes   (w_fin_bytes),
    .o_seg_end (w_fin_seg_end_unused),
    .o_seg_err (w_fin_seg_err)
  );

  // Output batch formatter.
  m_aesgcm_fmt_out #(
    .PARA_LANE_NUM (PARA_AES_LANE_NUM)
  ) u_fmt_out (
    .i_data  (w_aes_out_data),
    .i_mask  (w_aes_out_lane),
    .i_rem   (w_fout_rem),
    .i_bpb   (w_bpb),
    .o_data  (w_fout_data),
    .o_bytes (w_fout_bytes),
    .o_last  (w_fout_last_unused),
    .o_ent   (o_out_ent)
  );

  if (PARA_AES_GCM_EN == 1) begin : gen_gcm
    // GHASH unit of the selected architecture.
    m_aesgcm_ghash #(
      .PARA_LANE_NUM      (PARA_AES_LANE_NUM),
      .PARA_GHASH_ARCH    (PARA_GHASH_ARCH),
      .PARA_GHASH_DIGIT_W (PARA_GHASH_DIGIT_W),
      .PARA_GHASH_PIPE    (PARA_GHASH_PIPE)
    ) u_ghash (
      .i_clk_core   (i_clk_core),
      .i_rst_n_core (i_rst_n_core),
      .i_zeroize    (w_gh_zeroize),
      .i_clr        (w_gh_clr),
      .i_load_y     (w_gh_load_y),
      .i_y          (w_gh_y_in),
      .i_h          (w_gh_h),
      .i_pow_start  (w_gh_pow_start),
      .o_pow_done   (w_gh_pow_done),
      .i_valid      (w_gh_valid),
      .o_ready      (w_gh_ready),
      .i_data       (w_gh_data),
      .i_mask       (w_gh_mask),
      .o_y          (w_gh_y),
      .o_idle       (w_gh_idle)
    );

    // Tag formation and compare.
    m_aesgcm_tag u_tag (
      .i_s       (w_gh_y),
      .i_ej0     (w_tag_ej0),
      .i_tag_len (w_tag_len),
      .i_tag_exp (w_tag_exp),
      .o_tag     (w_tag),
      .o_match   (w_tag_match)
    );
  end else begin : gen_no_gcm
    // Legacy-only build: GHASH and tag are absent and read as idle.
    assign w_gh_pow_done = 1'b1;
    assign w_gh_ready    = 1'b1;
    assign w_gh_y        = '0;
    assign w_gh_idle     = 1'b1;
    assign w_tag         = '0;
    assign w_tag_match   = 1'b0;
  end

  if (LPARA_CTX_EN == 1) begin : gen_ctx
    // Context engine.
    m_aesgcm_ctx #(
      .PARA_CTX_MODE (PARA_GCM_CTX_MODE),
      .PARA_CTX_NUM  (LPARA_CTX_SLOTS)
    ) u_ctx (
      .i_clk_core   (i_clk_core),
      .i_rst_n_core (i_rst_n_core),
      .i_zeroize    (w_ctx_zeroize),
      .i_sec_only   (i_sec_only),
      .i_save       (w_ctx_save),
      .i_load       (w_ctx_load),
      .i_free       (w_ctx_free),
      .i_slot       (w_ctx_slot),
      .i_img_live   (w_ctx_img_live),
      .o_img        (w_ctx_img),
      .o_done       (w_ctx_done),
      .o_idle       (),
      .o_vld        (w_ctx_vld),
      .i_wreq_valid (i_wreq_valid),
      .i_wreq_imp   (i_wreq[LPARA_WREQ_W-1]),
      .i_wreq_idx   (i_wreq[32 +: 5]),
      .i_wreq_word  (i_wreq[31:0]),
      .i_wrsp_idle  (i_wrsp_idle),
      .o_wrsp_send  (o_wrsp_send),
      .o_wrsp_idx   (o_wrsp[32 +: 5]),
      .o_wrsp_word  (o_wrsp[31:0])
    );
  end else begin : gen_no_ctx
    // Suspend and resume are not built.
    assign w_ctx_img   = '0;
    assign w_ctx_done  = 1'b0;
    assign w_ctx_vld   = '0;
    assign o_wrsp_send = 1'b0;
    assign o_wrsp      = '0;
  end

  // Existing AES core (REF-008) with a 32-bit counter field for inc32.
  m_aes128_256_batch_top #(
    .PARA_AES_LANE_NUM (PARA_AES_LANE_NUM),
    .PARA_CTR_WIDTH    (LPARA_CTR_W)
  ) u_aes_core (
    .i_clk_core             (i_clk_core),
    .i_rst_n_core           (i_rst_n_core),
    .i_cfg_valid            (w_aes_cfg_valid),
    .o_cfg_ready            (w_aes_cfg_ready),
    .i_cfg_key_size         (w_aes_cfg_key_size),
    .i_cfg_key              (w_key),
    .i_cfg_mode             (w_aes_cfg_mode),
    .i_cfg_decipher         (w_aes_cfg_decipher),
    .i_cfg_iv               (w_aes_cfg_iv),
    .i_cfg_cfb_segment_size (w_aes_cfg_cfb),
    .i_batch_valid          (w_aes_in_valid),
    .o_batch_ready          (w_aes_in_ready),
    .i_batch_data           (w_aes_in_data),
    .i_batch_lane_valid     (w_aes_in_lane),
    .i_batch_last           (w_aes_in_last),
    .o_batch_valid          (w_aes_out_valid),
    .i_batch_ready          (w_aes_out_ready),
    .o_batch_data           (w_aes_out_data),
    .o_batch_lane_valid     (w_aes_out_lane),
    .o_batch_last           (w_aes_out_last_unused),
    .o_err_valid            (w_aes_err_valid),
    .i_err_ready            (1'b1),
    .o_err_code             (w_aes_err_code),
    .i_zeroize_req          (w_aes_zeroize),
    .o_zeroize_done         (w_aes_zeroize_done)
  );

endmodule
