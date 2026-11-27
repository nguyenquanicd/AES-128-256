/*
 * Project      : AES-GCM Accelerator
 * Author       : Nguyen Hung Quan and Claude (user)
 * AI Flow      : VLSIT RTL Generator AI Automation Flow
 * AI Flow Page : https://github.com/nguyenquanicd/VLSIT_RTL_Generator_AI_Model
 * Date         : 2026-11-25
 * Description  : Core-side formatter of an AES-core output batch (spec 5.3 step 5, 9.2). It keeps
 *                the first i_bpb bytes of every valid block (byte 0 at bits [127:120]) up to the
 *                remaining payload length and sets every other byte to zero, so the last block is
 *                truncated for the output stream and zero-padded for GHASH (SP 800-38D 7.1 step 5
 *                uses the ciphertext of exactly len(C) bits). It also forms the output FIFO entry
 *                {last, lane mask, blocks}. Combinational.
 * Decisions    : DEC-018, DEC-021 (spec section 20).
 */
`timescale 1ns/1ps

module m_aesgcm_fmt_out #(
  // Parameter Description: number of 128-bit blocks of one batch (PARA_AES_LANE_NUM).
  // Parameter values: 1 to 4; default is 1.
  // Parameter unit: block
  parameter logic [31:0] PARA_LANE_NUM = 1,
  localparam logic [31:0] LPARA_BLK_W = 128,
  localparam logic [31:0] LPARA_BYTE_W = 8,
  localparam logic [31:0] LPARA_BLK_BYTES = LPARA_BLK_W / LPARA_BYTE_W,
  localparam logic [31:0] LPARA_DATA_W = PARA_LANE_NUM * LPARA_BLK_W,
  localparam logic [31:0] LPARA_ENT_W = LPARA_DATA_W + PARA_LANE_NUM + 1
) (
  // AES-core output batch and payload state
  input  wire  [LPARA_DATA_W-1:0]  i_data,
  input  wire  [PARA_LANE_NUM-1:0] i_mask,
  input  wire  [31:0]              i_rem,
  input  wire  [4:0]               i_bpb,

  // Formatted batch
  output logic [LPARA_DATA_W-1:0]  o_data,
  output logic [31:0]              o_bytes,
  output logic                     o_last,
  output logic [LPARA_ENT_W-1:0]   o_ent
);

  // Internal signal declarations
  logic [2:0]  w_blk_cnt;
  logic [31:0] w_cap;

  // Number of valid blocks of the prefix mask.
  always_comb begin : p_com_cnt
    w_blk_cnt = '0;
    for (int idx = 0; idx < PARA_LANE_NUM; idx++) begin
      if (i_mask[idx])
        w_blk_cnt = 3'(idx + 1);
    end
  end

  // Byte k of block b is kept when it is one of the first i_bpb bytes of the block and its
  // stream position b x i_bpb + k is below the remaining payload length.
  always_comb begin : p_com_mask_bytes
    o_data = '0;
    for (int blk = 0; blk < PARA_LANE_NUM; blk++) begin
      for (int byt = 0; byt < LPARA_BLK_BYTES; byt++) begin
        if (i_mask[blk] && (5'(byt) < i_bpb) &&
            ((32'(blk) * 32'(i_bpb) + 32'(byt)) < i_rem))
          o_data[blk*LPARA_BLK_W + LPARA_BLK_W-1-LPARA_BYTE_W*byt -: LPARA_BYTE_W] =
            i_data[blk*LPARA_BLK_W + LPARA_BLK_W-1-LPARA_BYTE_W*byt -: LPARA_BYTE_W];
      end
    end
  end

  // Bytes of the batch, end of payload and the output FIFO entry.
  assign w_cap   = 32'(w_blk_cnt) * 32'(i_bpb);
  assign o_bytes = (i_rem < w_cap) ? i_rem : w_cap;
  assign o_last  = (o_bytes == i_rem);
  assign o_ent   = {o_last, i_mask, o_data};

endmodule
