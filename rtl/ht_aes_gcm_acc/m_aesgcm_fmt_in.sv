/*
 * Project      : AES-GCM Accelerator
 * Author       : Nguyen Hung Quan and Claude (user)
 * AI Flow      : VLSIT RTL Generator AI Automation Flow
 * AI Flow Page : https://github.com/nguyenquanicd/VLSIT_RTL_Generator_AI_Model
 * Date         : 2026-11-25
 * Description  : Core-side decoder of an input FIFO entry (spec 9.2, 10.4 item 1). It splits the
 *                entry into blocks and the prefix lane mask, counts the valid blocks and the
 *                stream bytes that the entry carries for the current segment (min of the
 *                segment remainder and blocks x bytes per block), and reports a segment error when
 *                the entry tag or its end-of-segment flag disagrees with the sequencer count
 *                (LEN_ERR, ERR-002). Combinational.
 * Decisions    : DEC-018, DEC-021 (spec section 20).
 */
`timescale 1ns/1ps

module m_aesgcm_fmt_in #(
  // Parameter Description: number of 128-bit blocks of one entry (PARA_AES_LANE_NUM).
  // Parameter values: 1 to 4; default is 1.
  // Parameter unit: block
  parameter logic [31:0] PARA_LANE_NUM = 1,
  localparam logic [31:0] LPARA_BLK_W = 128,
  localparam logic [31:0] LPARA_DATA_W = PARA_LANE_NUM * LPARA_BLK_W,
  localparam logic [31:0] LPARA_ENT_W = LPARA_DATA_W + PARA_LANE_NUM + 2
) (
  // Entry and segment state
  input  wire  [LPARA_ENT_W-1:0]   i_ent,
  input  wire                      i_seg_exp,
  input  wire  [31:0]              i_rem,
  input  wire  [4:0]               i_bpb,

  // Decoded entry
  output logic [LPARA_DATA_W-1:0]  o_data,
  output logic [PARA_LANE_NUM-1:0] o_mask,
  output logic [2:0]               o_blk_cnt,
  output logic [31:0]              o_bytes,
  output logic                     o_seg_end,
  output logic                     o_seg_err
);

  // Internal signal declarations
  logic        w_seg;
  logic        w_last;
  logic [31:0] w_cap;

  // Entry fields: {segment, end of segment, lane mask, blocks}.
  assign o_data = i_ent[LPARA_DATA_W-1:0];
  assign o_mask = i_ent[LPARA_DATA_W +: PARA_LANE_NUM];
  assign w_last = i_ent[LPARA_DATA_W + PARA_LANE_NUM];
  assign w_seg  = i_ent[LPARA_DATA_W + PARA_LANE_NUM + 1];

  // Number of valid blocks of the prefix mask.
  always_comb begin : p_com_cnt
    o_blk_cnt = '0;
    for (int idx = 0; idx < PARA_LANE_NUM; idx++) begin
      if (o_mask[idx])
        o_blk_cnt = 3'(idx + 1);
    end
  end

  // Bytes carried for the segment, and the consistency check of the entry with the count.
  assign w_cap     = 32'(o_blk_cnt) * 32'(i_bpb);
  assign o_bytes   = (i_rem < w_cap) ? i_rem : w_cap;
  assign o_seg_end = (o_bytes == i_rem);
  assign o_seg_err = (w_seg != i_seg_exp) | (w_last != o_seg_end) | (o_blk_cnt == 3'd0);

endmodule
