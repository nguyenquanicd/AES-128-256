/*
 * Project      : AES-GCM Accelerator
 * Author       : Nguyen Hung Quan and Claude (user)
 * AI Flow      : VLSIT RTL Generator AI Automation Flow
 * AI Flow Page : https://github.com/nguyenquanicd/VLSIT_RTL_Generator_AI_Model
 * Date         : 2026-11-25
 * Description  : Input data FIFO (spec 10.4, 10.5 MEM-001, CDC-003, DEC-016, DEC-018): the
 *                bus-side packer m_aesgcm_pack and one library FIFO of PARA_FIFO_DEPTH entries;
 *                m_vlsit_afifo_top for asynchronous clocks, m_vlsit_sfifo_top for related clocks.
 *                The FIFO write side and its software reset (flush) are in the BUS domain; the
 *                show-ahead read side is in the CORE domain. Structural module.
 * Decisions    : DEC-016, DEC-018, DEC-024 (spec section 20).
 */
`timescale 1ns/1ps

module m_aesgcm_fifo_in #(
  // Parameter Description: number of 128-bit blocks of one entry (PARA_AES_LANE_NUM).
  // Parameter values: 1 to 4; default is 1.
  // Parameter unit: block
  parameter logic [31:0] PARA_LANE_NUM = 1,
  // Parameter Description: number of entries of the FIFO.
  // Parameter values: 8, 16, 32, 64, 128 or 256; default is 16.
  // Parameter unit: entry
  parameter logic [31:0] PARA_FIFO_DEPTH = 16,
  // Parameter Description: crossing structure; 1 = asynchronous clocks, 0 = related clocks.
  // Parameter values: 0 or 1; default is 1.
  // Parameter unit: none
  parameter logic [31:0] PARA_CLK_ASYNC = 1,
  localparam logic [31:0] LPARA_BLK_W = 128,
  localparam logic [31:0] LPARA_ENT_W = PARA_LANE_NUM * LPARA_BLK_W + PARA_LANE_NUM + 2,
  localparam logic [31:0] LPARA_THR_W = $clog2(PARA_FIFO_DEPTH) + 1,
  // Synchronizer cell type of the asynchronous library FIFO (two flops).
  localparam logic [31:0] LPARA_CELL_TYPE = 2
) (
  // BUS clock and reset
  input  wire                    i_clk_bus,
  input  wire                    i_rst_n_bus,

  // BUS-side message control
  input  wire                    i_flush,
  input  wire                    i_load,
  input  wire  [31:0]            i_aad_len,
  input  wire  [31:0]            i_data_len,
  input  wire  [4:0]             i_bpb,
  input  wire  [2:0]             i_bpe,
  input  wire  [4:0]             i_beat_bytes,
  input  wire  [LPARA_THR_W-1:0] i_full_thr,
  output logic                   o_active,
  output logic                   o_drop,
  output logic                   o_full,
  output logic                   o_full_thr,

  // BUS-side beat stream
  input  wire                    i_beat_valid,
  output logic                   o_beat_ready,
  input  wire  [LPARA_BLK_W-1:0] i_beat_data,

  // CORE clock and reset
  input  wire                    i_clk_core,
  input  wire                    i_rst_n_core,

  // CORE-side entry read (show-ahead)
  input  wire                    i_rd_en,
  output logic [LPARA_ENT_W-1:0] o_rd_data,
  output logic                   o_empty
);

  // Internal signal declarations
  logic                   w_wr_en;
  logic [LPARA_ENT_W-1:0] w_wr_data;
  logic                   w_overflow_unused;
  logic                   w_sw_rst_busy_unused;
  logic                   w_empty_thr_unused;
  logic                   w_underflow_unused;

  // Bus-side packer: beats to entries.
  m_aesgcm_pack #(
    .PARA_LANE_NUM (PARA_LANE_NUM)
  ) u_pack (
    .i_clk_bus    (i_clk_bus),
    .i_rst_n_bus  (i_rst_n_bus),
    .i_flush      (i_flush),
    .i_load       (i_load),
    .i_aad_len    (i_aad_len),
    .i_data_len   (i_data_len),
    .i_bpb        (i_bpb),
    .i_bpe        (i_bpe),
    .i_beat_bytes (i_beat_bytes),
    .o_active     (o_active),
    .o_drop       (o_drop),
    .i_beat_valid (i_beat_valid),
    .o_beat_ready (o_beat_ready),
    .i_beat_data  (i_beat_data),
    .o_wr_en      (w_wr_en),
    .o_wr_data    (w_wr_data),
    .i_full       (o_full)
  );

  if (PARA_CLK_ASYNC == 1) begin : gen_async
    // Asynchronous clocks: Gray-pointer FIFO of the library.
    m_vlsit_afifo_top #(
      .PARA_AFIFO_DEPTH         (PARA_FIFO_DEPTH),
      .PARA_AFIFO_DATA_W        (LPARA_ENT_W),
      .PARA_AFIFO_CELL_TYPE     (LPARA_CELL_TYPE),
      .PARA_AFIFO_MEM_USE_MACRO (32'd0)
    ) u_afifo (
      .i_clk_wr      (i_clk_bus),
      .i_rst_n_wr    (i_rst_n_bus),
      .i_wr_en       (w_wr_en),
      .i_wr_data     (w_wr_data),
      .i_full_thr    (i_full_thr),
      .o_full        (o_full),
      .o_full_thr    (o_full_thr),
      .o_overflow    (w_overflow_unused),
      .i_rst_n_sw    (~i_flush),
      .o_sw_rst_busy (w_sw_rst_busy_unused),
      .i_clk_rd      (i_clk_core),
      .i_rst_n_rd    (i_rst_n_core),
      .i_rd_en       (i_rd_en),
      .i_empty_thr   ({LPARA_THR_W{1'b0}}),
      .o_rd_data     (o_rd_data),
      .o_empty       (o_empty),
      .o_empty_thr   (w_empty_thr_unused),
      .o_underflow   (w_underflow_unused)
    );
  end else begin : gen_sync
    // Related clocks: synchronous two-clock FIFO of the library.
    m_vlsit_sfifo_top #(
      .PARA_SFIFO_DEPTH         (PARA_FIFO_DEPTH),
      .PARA_SFIFO_DATA_W        (LPARA_ENT_W),
      .PARA_SFIFO_PTR_RETIME    (32'd0),
      .PARA_SFIFO_MEM_USE_MACRO (32'd0)
    ) u_sfifo (
      .i_clk_wr      (i_clk_bus),
      .i_rst_n_wr    (i_rst_n_bus),
      .i_wr_en       (w_wr_en),
      .i_wr_data     (w_wr_data),
      .i_full_thr    (i_full_thr),
      .o_full        (o_full),
      .o_full_thr    (o_full_thr),
      .o_overflow    (w_overflow_unused),
      .i_rst_n_sw    (~i_flush),
      .o_sw_rst_busy (w_sw_rst_busy_unused),
      .i_clk_rd      (i_clk_core),
      .i_rst_n_rd    (i_rst_n_core),
      .i_rd_en       (i_rd_en),
      .i_empty_thr   ({LPARA_THR_W{1'b0}}),
      .o_rd_data     (o_rd_data),
      .o_empty       (o_empty),
      .o_empty_thr   (w_empty_thr_unused),
      .o_underflow   (w_underflow_unused)
    );
  end

endmodule
