/*
 * Project      : AES-GCM Accelerator
 * Author       : Nguyen Hung Quan and Claude (user)
 * AI Flow      : VLSIT RTL Generator AI Automation Flow
 * AI Flow Page : https://github.com/nguyenquanicd/VLSIT_RTL_Generator_AI_Model
 * Date         : 2026-11-25
 * Description  : Output data FIFO (spec 10.4, 10.5 MEM-002, CDC-004, DEC-016, DEC-018): one
 *                library FIFO of PARA_FIFO_DEPTH entries written by the CORE domain, and the
 *                bus-side unpacker m_aesgcm_unpack on its show-ahead read side. The FIFO software
 *                reset (flush) is in the CORE domain, the write domain of this FIFO.
 *                Structural module.
 * Decisions    : DEC-016, DEC-018, DEC-024 (spec section 20).
 */
`timescale 1ns/1ps

module m_aesgcm_fifo_out #(
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
  localparam logic [31:0] LPARA_ENT_W = PARA_LANE_NUM * LPARA_BLK_W + PARA_LANE_NUM + 1,
  localparam logic [31:0] LPARA_THR_W = $clog2(PARA_FIFO_DEPTH) + 1,
  // Synchronizer cell type of the asynchronous library FIFO (two flops).
  localparam logic [31:0] LPARA_CELL_TYPE = 2
) (
  // CORE clock and reset
  input  wire                    i_clk_core,
  input  wire                    i_rst_n_core,

  // CORE-side entry write
  input  wire                    i_flush_core,
  input  wire                    i_wr_en,
  input  wire  [LPARA_ENT_W-1:0] i_wr_data,
  output logic                   o_full,
  output logic                   o_flush_busy,

  // BUS clock and reset
  input  wire                    i_clk_bus,
  input  wire                    i_rst_n_bus,

  // BUS-side message control
  input  wire                    i_flush_bus,
  input  wire                    i_load,
  input  wire  [31:0]            i_data_len,
  input  wire  [4:0]             i_bpb,
  input  wire  [2:0]             i_bpe,
  input  wire  [4:0]             i_beat_bytes,
  input  wire  [8:0]             i_burst_bytes,
  output logic                   o_empty,
  output logic                   o_dma_cond,
  output logic [31:0]            o_unread,

  // BUS-side beat stream
  output logic                   o_beat_valid,
  input  wire                    i_beat_ready,
  output logic [LPARA_BLK_W-1:0] o_beat_data
);

  // Internal signal declarations
  logic                   w_rd_en;
  logic [LPARA_ENT_W-1:0] w_rd_data;
  logic [LPARA_THR_W-1:0] w_empty_thr;
  logic                   w_empty_thr_flag;
  logic                   w_full_thr_unused;
  logic                   w_overflow_unused;
  logic                   w_underflow_unused;

  if (PARA_CLK_ASYNC == 1) begin : gen_async
    // Asynchronous clocks: Gray-pointer FIFO of the library.
    m_vlsit_afifo_top #(
      .PARA_AFIFO_DEPTH         (PARA_FIFO_DEPTH),
      .PARA_AFIFO_DATA_W        (LPARA_ENT_W),
      .PARA_AFIFO_CELL_TYPE     (LPARA_CELL_TYPE),
      .PARA_AFIFO_MEM_USE_MACRO (32'd0)
    ) u_afifo (
      .i_clk_wr      (i_clk_core),
      .i_rst_n_wr    (i_rst_n_core),
      .i_wr_en       (i_wr_en),
      .i_wr_data     (i_wr_data),
      .i_full_thr    ({LPARA_THR_W{1'b0}}),
      .o_full        (o_full),
      .o_full_thr    (w_full_thr_unused),
      .o_overflow    (w_overflow_unused),
      .i_rst_n_sw    (~i_flush_core),
      .o_sw_rst_busy (o_flush_busy),
      .i_clk_rd      (i_clk_bus),
      .i_rst_n_rd    (i_rst_n_bus),
      .i_rd_en       (w_rd_en),
      .i_empty_thr   (w_empty_thr),
      .o_rd_data     (w_rd_data),
      .o_empty       (o_empty),
      .o_empty_thr   (w_empty_thr_flag),
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
      .i_clk_wr      (i_clk_core),
      .i_rst_n_wr    (i_rst_n_core),
      .i_wr_en       (i_wr_en),
      .i_wr_data     (i_wr_data),
      .i_full_thr    ({LPARA_THR_W{1'b0}}),
      .o_full        (o_full),
      .o_full_thr    (w_full_thr_unused),
      .o_overflow    (w_overflow_unused),
      .i_rst_n_sw    (~i_flush_core),
      .o_sw_rst_busy (o_flush_busy),
      .i_clk_rd      (i_clk_bus),
      .i_rst_n_rd    (i_rst_n_bus),
      .i_rd_en       (w_rd_en),
      .i_empty_thr   (w_empty_thr),
      .o_rd_data     (w_rd_data),
      .o_empty       (o_empty),
      .o_empty_thr   (w_empty_thr_flag),
      .o_underflow   (w_underflow_unused)
    );
  end

  // Bus-side unpacker: entries to beats.
  m_aesgcm_unpack #(
    .PARA_LANE_NUM (PARA_LANE_NUM),
    .PARA_THR_W    (LPARA_THR_W)
  ) u_unpack (
    .i_clk_bus        (i_clk_bus),
    .i_rst_n_bus      (i_rst_n_bus),
    .i_flush          (i_flush_bus),
    .i_load           (i_load),
    .i_data_len       (i_data_len),
    .i_bpb            (i_bpb),
    .i_bpe            (i_bpe),
    .i_beat_bytes     (i_beat_bytes),
    .i_burst_bytes    (i_burst_bytes),
    .i_empty          (o_empty),
    .i_rd_data        (w_rd_data),
    .o_rd_en          (w_rd_en),
    .o_empty_thr      (w_empty_thr),
    .i_empty_thr_flag (w_empty_thr_flag),
    .o_beat_valid     (o_beat_valid),
    .i_beat_ready     (i_beat_ready),
    .o_beat_data      (o_beat_data),
    .o_dma_cond       (o_dma_cond),
    .o_unread         (o_unread)
  );

endmodule
