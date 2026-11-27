/*
 * Project      : AES-GCM Accelerator
 * Author       : Nguyen Hung Quan and Claude (user)
 * AI Flow      : VLSIT RTL Generator AI Automation Flow
 * AI Flow Page : https://github.com/nguyenquanicd/VLSIT_RTL_Generator_AI_Model
 * Date         : 2026-11-25
 * Description  : Crossing structure (spec 7.2, 14.2): bundle crossings CDC-001 (u_xing_cfg),
 *                CDC-002 (u_xing_sts), CDC-005 (u_xing_cmd), CDC-007 (u_xing_wreq, u_xing_wrsp),
 *                data FIFOs CDC-003 (u_fifo_in) and CDC-004 (u_fifo_out), and the CDC-006
 *                synchronizers of i_gcm_secure_only. Structural module.
 * Decisions    : DEC-016, DEC-022, DEC-024 (spec section 20).
 */
`timescale 1ns/1ps

module m_aesgcm_xing #(
  // Parameter Description: number of 128-bit AES block lanes of the AES core.
  // Parameter values: 1 to 4; default is 1.
  // Parameter unit: lane
  parameter logic [31:0] PARA_AES_LANE_NUM = 1,
  // Parameter Description: crossing structure; 1 asynchronous clocks, 0 related clocks.
  // Parameter values: 0 or 1; default is 1.
  // Parameter unit: none
  parameter logic [31:0] PARA_CLK_ASYNC = 1,
  // Parameter Description: depth of each data FIFO in entries of up to PARA_AES_LANE_NUM blocks.
  // Parameter values: 8, 16, 32, 64, 128 or 256; default is 16.
  // Parameter unit: entry
  parameter logic [31:0] PARA_FIFO_DEPTH = 16,
  localparam logic [31:0] LPARA_BLK_W = 128,
  localparam logic [31:0] LPARA_CFG_W = 611,
  localparam logic [31:0] LPARA_CMD_W = 6,
  localparam logic [31:0] LPARA_STS_W = 322,
  localparam logic [31:0] LPARA_WREQ_W = 38,
  localparam logic [31:0] LPARA_WRSP_W = 37,
  localparam logic [31:0] LPARA_THR_W = $clog2(PARA_FIFO_DEPTH) + 1,
  localparam logic [31:0] LPARA_ENT_IN_W = PARA_AES_LANE_NUM * LPARA_BLK_W + PARA_AES_LANE_NUM + 2,
  localparam logic [31:0] LPARA_ENT_OUT_W = PARA_AES_LANE_NUM * LPARA_BLK_W + PARA_AES_LANE_NUM + 1,
  // Synchronizer cell type of i_gcm_secure_only (two flops) and its safe reset value 1.
  localparam logic [31:0] LPARA_CELL_TYPE = 2,
  localparam logic [31:0] LPARA_SEC_RST_VAL = 1
) (
  // BUS clock, reset and bundles
  input  wire                        i_clk_bus,
  input  wire                        i_rst_n_bus,
  input  wire                        i_cfg_send,
  input  wire  [LPARA_CFG_W-1:0]     i_cfg,
  output logic                       o_cfg_idle,
  output logic                       o_cfg_done,
  input  wire                        i_cmd_send,
  input  wire  [LPARA_CMD_W-1:0]     i_cmd,
  output logic                       o_cmd_idle,
  output logic                       o_cmd_done,
  output logic                       o_sts_valid,
  output logic [LPARA_STS_W-1:0]     o_sts,
  input  wire                        i_wreq_send,
  input  wire  [LPARA_WREQ_W-1:0]    i_wreq,
  output logic                       o_wreq_idle,
  output logic                       o_wreq_done,
  output logic                       o_wrsp_valid,
  output logic [LPARA_WRSP_W-1:0]    o_wrsp,
  output logic                       o_sec_only_bus,

  // BUS side of the data FIFOs
  input  wire                        i_in_flush,
  input  wire                        i_in_load,
  input  wire  [31:0]                i_in_aad_len,
  input  wire  [31:0]                i_in_data_len,
  input  wire  [4:0]                 i_bpb,
  input  wire  [2:0]                 i_bpe,
  input  wire  [4:0]                 i_beat_bytes,
  input  wire  [LPARA_THR_W-1:0]     i_in_full_thr,
  output logic                       o_in_active,
  output logic                       o_in_drop,
  output logic                       o_in_full,
  output logic                       o_in_full_thr,
  input  wire                        i_beat_valid,
  output logic                       o_beat_ready,
  input  wire  [LPARA_BLK_W-1:0]     i_beat_data,
  input  wire                        i_out_flush_bus,
  input  wire                        i_out_load,
  input  wire  [31:0]                i_out_data_len,
  input  wire  [8:0]                 i_out_burst_bytes,
  output logic                       o_out_empty,
  output logic                       o_out_dma_cond,
  output logic                       o_obeat_valid,
  input  wire                        i_obeat_ready,
  output logic [LPARA_BLK_W-1:0]     o_obeat_data,

  // CORE clock, reset, bundles and data FIFO side
  input  wire                        i_clk_core,
  input  wire                        i_rst_n_core,
  output logic                       o_cfg_valid,
  output logic [LPARA_CFG_W-1:0]     o_cfg,
  input  wire                        i_cfg_clr,
  output logic                       o_cmd_valid,
  output logic [LPARA_CMD_W-1:0]     o_cmd,
  input  wire                        i_sts_send,
  input  wire  [LPARA_STS_W-1:0]     i_sts,
  output logic                       o_sts_idle,
  output logic                       o_wreq_valid,
  output logic [LPARA_WREQ_W-1:0]    o_wreq,
  input  wire                        i_wrsp_send,
  input  wire  [LPARA_WRSP_W-1:0]    i_wrsp,
  output logic                       o_wrsp_idle,
  output logic                       o_sec_only_core,
  output logic                       o_in_empty,
  output logic [LPARA_ENT_IN_W-1:0]  o_in_ent,
  input  wire                        i_in_rd_en,
  input  wire                        i_out_wr_en,
  input  wire  [LPARA_ENT_OUT_W-1:0] i_out_ent,
  output logic                       o_out_full,
  input  wire                        i_out_flush_core,
  output logic                       o_out_flush_busy,

  // Static pin (IF-006)
  input  wire                        i_gcm_secure_only
);

  // Internal signal declarations
  logic [31:0] w_out_unread_unused;
  logic        w_sts_done_unused;
  logic        w_wrsp_done_unused;

  // CDC-001: configuration bundle, BUS to CORE.
  m_aesgcm_xing_bdl #(
    .PARA_DATA_W    (LPARA_CFG_W),
    .PARA_CLK_ASYNC (PARA_CLK_ASYNC)
  ) u_xing_cfg (
    .i_clk_src   (i_clk_bus),
    .i_rst_n_src (i_rst_n_bus),
    .i_send      (i_cfg_send),
    .i_data      (i_cfg),
    .i_clr       (1'b0),
    .o_idle      (o_cfg_idle),
    .o_done      (o_cfg_done),
    .i_clk_dst   (i_clk_core),
    .i_rst_n_dst (i_rst_n_core),
    .i_dst_clr   (i_cfg_clr),
    .o_valid     (o_cfg_valid),
    .o_data      (o_cfg)
  );


  // CDC-005: command bundle, BUS to CORE.
  m_aesgcm_xing_bdl #(
    .PARA_DATA_W    (LPARA_CMD_W),
    .PARA_CLK_ASYNC (PARA_CLK_ASYNC)
  ) u_xing_cmd (
    .i_clk_src   (i_clk_bus),
    .i_rst_n_src (i_rst_n_bus),
    .i_send      (i_cmd_send),
    .i_data      (i_cmd),
    .i_clr       (1'b0),
    .o_idle      (o_cmd_idle),
    .o_done      (o_cmd_done),
    .i_clk_dst   (i_clk_core),
    .i_rst_n_dst (i_rst_n_core),
    .i_dst_clr   (1'b0),
    .o_valid     (o_cmd_valid),
    .o_data      (o_cmd)
  );


  // CDC-002: status report, CORE to BUS.
  m_aesgcm_xing_bdl #(
    .PARA_DATA_W    (LPARA_STS_W),
    .PARA_CLK_ASYNC (PARA_CLK_ASYNC)
  ) u_xing_sts (
    .i_clk_src   (i_clk_core),
    .i_rst_n_src (i_rst_n_core),
    .i_send      (i_sts_send),
    .i_data      (i_sts),
    .i_clr       (1'b0),
    .o_idle      (o_sts_idle),
    .o_done      (w_sts_done_unused),
    .i_clk_dst   (i_clk_bus),
    .i_rst_n_dst (i_rst_n_bus),
    .i_dst_clr   (1'b0),
    .o_valid     (o_sts_valid),
    .o_data      (o_sts)
  );


  // CDC-007: context word request, BUS to CORE.
  m_aesgcm_xing_bdl #(
    .PARA_DATA_W    (LPARA_WREQ_W),
    .PARA_CLK_ASYNC (PARA_CLK_ASYNC)
  ) u_xing_wreq (
    .i_clk_src   (i_clk_bus),
    .i_rst_n_src (i_rst_n_bus),
    .i_send      (i_wreq_send),
    .i_data      (i_wreq),
    .i_clr       (1'b0),
    .o_idle      (o_wreq_idle),
    .o_done      (o_wreq_done),
    .i_clk_dst   (i_clk_core),
    .i_rst_n_dst (i_rst_n_core),
    .i_dst_clr   (1'b0),
    .o_valid     (o_wreq_valid),
    .o_data      (o_wreq)
  );


  // CDC-007: context word response, CORE to BUS.
  m_aesgcm_xing_bdl #(
    .PARA_DATA_W    (LPARA_WRSP_W),
    .PARA_CLK_ASYNC (PARA_CLK_ASYNC)
  ) u_xing_wrsp (
    .i_clk_src   (i_clk_core),
    .i_rst_n_src (i_rst_n_core),
    .i_send      (i_wrsp_send),
    .i_data      (i_wrsp),
    .i_clr       (1'b0),
    .o_idle      (o_wrsp_idle),
    .o_done      (w_wrsp_done_unused),
    .i_clk_dst   (i_clk_bus),
    .i_rst_n_dst (i_rst_n_bus),
    .i_dst_clr   (1'b0),
    .o_valid     (o_wrsp_valid),
    .o_data      (o_wrsp)
  );


  // CDC-003: input data FIFO.
  m_aesgcm_fifo_in #(
    .PARA_LANE_NUM   (PARA_AES_LANE_NUM),
    .PARA_FIFO_DEPTH (PARA_FIFO_DEPTH),
    .PARA_CLK_ASYNC  (PARA_CLK_ASYNC)
  ) u_fifo_in (
    .i_clk_bus    (i_clk_bus),
    .i_rst_n_bus  (i_rst_n_bus),
    .i_flush      (i_in_flush),
    .i_load       (i_in_load),
    .i_aad_len    (i_in_aad_len),
    .i_data_len   (i_in_data_len),
    .i_bpb        (i_bpb),
    .i_bpe        (i_bpe),
    .i_beat_bytes (i_beat_bytes),
    .i_full_thr   (i_in_full_thr),
    .o_active     (o_in_active),
    .o_drop       (o_in_drop),
    .o_full       (o_in_full),
    .o_full_thr   (o_in_full_thr),
    .i_beat_valid (i_beat_valid),
    .o_beat_ready (o_beat_ready),
    .i_beat_data  (i_beat_data),
    .i_clk_core   (i_clk_core),
    .i_rst_n_core (i_rst_n_core),
    .i_rd_en      (i_in_rd_en),
    .o_rd_data    (o_in_ent),
    .o_empty      (o_in_empty)
  );


  // CDC-004: output data FIFO.
  m_aesgcm_fifo_out #(
    .PARA_LANE_NUM   (PARA_AES_LANE_NUM),
    .PARA_FIFO_DEPTH (PARA_FIFO_DEPTH),
    .PARA_CLK_ASYNC  (PARA_CLK_ASYNC)
  ) u_fifo_out (
    .i_clk_core    (i_clk_core),
    .i_rst_n_core  (i_rst_n_core),
    .i_flush_core  (i_out_flush_core),
    .i_wr_en       (i_out_wr_en),
    .i_wr_data     (i_out_ent),
    .o_full        (o_out_full),
    .o_flush_busy  (o_out_flush_busy),
    .i_clk_bus     (i_clk_bus),
    .i_rst_n_bus   (i_rst_n_bus),
    .i_flush_bus   (i_out_flush_bus),
    .i_load        (i_out_load),
    .i_data_len    (i_out_data_len),
    .i_bpb         (i_bpb),
    .i_bpe         (i_bpe),
    .i_beat_bytes  (i_beat_bytes),
    .i_burst_bytes (i_out_burst_bytes),
    .o_empty       (o_out_empty),
    .o_dma_cond    (o_out_dma_cond),
    .o_unread      (w_out_unread_unused),
    .o_beat_valid  (o_obeat_valid),
    .i_beat_ready  (i_obeat_ready),
    .o_beat_data   (o_obeat_data)
  );


  // CDC-006: i_gcm_secure_only resynchronized into the BUS domain (reset value 1, safe).
  m_vlsit_afifo_cell_sync #(
    .PARA_AFIFO_CELL_RST_VAL (LPARA_SEC_RST_VAL),
    .PARA_AFIFO_CELL_TYPE    (LPARA_CELL_TYPE)
  ) u_sync_sec_bus (
    .i_clk_dst   (i_clk_bus),
    .i_rst_n_dst (i_rst_n_bus),
    .i_d         (i_gcm_secure_only),
    .o_q         (o_sec_only_bus)
  );


  // CDC-006: i_gcm_secure_only resynchronized into the CORE domain (reset value 1, safe).
  m_vlsit_afifo_cell_sync #(
    .PARA_AFIFO_CELL_RST_VAL (LPARA_SEC_RST_VAL),
    .PARA_AFIFO_CELL_TYPE    (LPARA_CELL_TYPE)
  ) u_sync_sec_core (
    .i_clk_dst   (i_clk_core),
    .i_rst_n_dst (i_rst_n_core),
    .i_d         (i_gcm_secure_only),
    .o_q         (o_sec_only_core)
  );

endmodule
