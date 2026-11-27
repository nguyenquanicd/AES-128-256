/*
 * Project      : AES-GCM Accelerator
 * Author       : Nguyen Hung Quan and Claude (user)
 * AI Flow      : VLSIT RTL Generator AI Automation Flow
 * AI Flow Page : https://github.com/nguyenquanicd/VLSIT_RTL_Generator_AI_Model
 * Date         : 2026-11-25
 * Description  : Bus-side unpacker of the output FIFO (spec 9.2, 10.4 item 1, DEC-018). It reads
 *                entries of up to PARA_LANE_NUM blocks from the show-ahead FIFO head, takes i_bpb
 *                bytes of every valid block (byte 0 at bits [127:120]) and forms beats of
 *                i_beat_bytes bytes with the first stream byte in bits [7:0]; the last beat of
 *                the payload is padded with zero bytes. It also evaluates the DMA output
 *                condition of spec 6.3.4: enough bytes for one burst, or all remaining bytes.
 * Decisions    : DEC-018, DEC-020, DEC-021, DEC-024 (spec section 20).
 */
`timescale 1ns/1ps

module m_aesgcm_unpack #(
  // Parameter Description: number of 128-bit blocks of one FIFO entry (PARA_AES_LANE_NUM).
  // Parameter values: 1 to 4; default is 1.
  // Parameter unit: block
  parameter logic [31:0] PARA_LANE_NUM = 1,
  // Parameter Description: width of the FIFO occupancy threshold of the library FIFO.
  // Parameter values: log2(PARA_FIFO_DEPTH) + 1; default is 5.
  // Parameter unit: bit
  parameter logic [31:0] PARA_THR_W = 5,
  localparam logic [31:0] LPARA_BLK_W = 128,
  localparam logic [31:0] LPARA_BYTE_W = 8,
  localparam logic [31:0] LPARA_BLK_BYTES = LPARA_BLK_W / LPARA_BYTE_W,
  localparam logic [31:0] LPARA_ENT_W = PARA_LANE_NUM * LPARA_BLK_W + PARA_LANE_NUM + 1
) (
  // Clock and reset (BUS domain)
  input  wire                    i_clk_bus,
  input  wire                    i_rst_n_bus,

  // Message control
  input  wire                    i_flush,
  input  wire                    i_load,
  input  wire  [31:0]            i_data_len,
  input  wire  [4:0]             i_bpb,
  input  wire  [2:0]             i_bpe,
  input  wire  [4:0]             i_beat_bytes,
  input  wire  [8:0]             i_burst_bytes,

  // FIFO read side (show-ahead)
  input  wire                    i_empty,
  input  wire  [LPARA_ENT_W-1:0] i_rd_data,
  output logic                   o_rd_en,
  output logic [PARA_THR_W-1:0]  o_empty_thr,
  input  wire                    i_empty_thr_flag,

  // Beat stream, first stream byte in bits [7:0]
  output logic                   o_beat_valid,
  input  wire                    i_beat_ready,
  output logic [LPARA_BLK_W-1:0] o_beat_data,

  // DMA output condition and unread byte count
  output logic                   o_dma_cond,
  output logic [31:0]            o_unread
);

  // Internal signal declarations
  logic [31:0]                          reg_rem;
  logic [4:0]                           reg_bpb;
  logic [2:0]                           reg_bpe;
  logic [4:0]                           reg_beat_bytes;
  logic [8:0]                           reg_burst_bytes;
  logic [1:0]                           reg_blk_idx;
  logic [4:0]                           reg_blk_off;
  logic [LPARA_BLK_W-1:0]               reg_beat;
  logic [4:0]                           reg_beat_fill;
  logic                                 reg_beat_vld;
  logic [PARA_THR_W-1:0]                reg_thr;
  logic                                 reg_thr_stable;
  logic                                 reg_dma_cond;
  logic [PARA_LANE_NUM-1:0]             w_mask;
  logic [PARA_LANE_NUM*LPARA_BLK_W-1:0] w_ent;
  logic [2:0]                           w_blk_cnt;
  logic [LPARA_BLK_W-1:0]               w_blk;
  logic                                 w_build;
  logic [4:0]                           w_fill_base;
  logic [4:0]                           w_take;
  logic                                 w_blk_end;
  logic                                 w_ent_end;
  logic [LPARA_BLK_W-1:0]               w_beat_new;
  logic [LPARA_BLK_BYTES-1:0][4:0]      w_src_pos;
  logic [9:0]                           w_need_num;
  logic [31:0]                          w_held;
  logic [31:0]                          w_want;
  logic [31:0]                          w_need_bytes;
  logic [31:0]                          w_bpe_bytes;
  logic [31:0]                          w_need_ent;
  logic [PARA_THR_W-1:0]                w_thr;

  // Head entry fields.
  assign w_ent  = i_rd_data[PARA_LANE_NUM*LPARA_BLK_W-1:0];
  assign w_mask = i_rd_data[PARA_LANE_NUM*LPARA_BLK_W +: PARA_LANE_NUM];

  // Number of valid blocks of the head entry (prefix mask) and the block being unpacked.
  always_comb begin : p_com_blk
    w_blk_cnt = '0;
    w_blk     = w_ent[LPARA_BLK_W-1:0];
    for (int idx = 0; idx < PARA_LANE_NUM; idx++) begin
      if (w_mask[idx])
        w_blk_cnt = 3'(idx + 1);
      if (reg_blk_idx == 2'(idx))
        w_blk = w_ent[idx*LPARA_BLK_W +: LPARA_BLK_W];
    end
  end

  // A beat is built when the beat register is empty or is popped in this clock.
  assign w_build     = (~reg_beat_vld | i_beat_ready) & (reg_rem != '0) & ~i_empty;
  assign w_fill_base = reg_beat_vld ? 5'd0 : reg_beat_fill;

  // The bytes moved are limited by the beat room, the block remainder and the payload.
  always_comb begin : p_com_take
    w_take = reg_beat_bytes - w_fill_base;
    if ((reg_bpb - reg_blk_off) < w_take)
      w_take = reg_bpb - reg_blk_off;
    if (reg_rem < 32'(w_take))
      w_take = reg_rem[4:0];
  end

  // Block and entry completion; the head entry is popped with its last block.
  assign w_blk_end = ((reg_blk_off + w_take) == reg_bpb) | (reg_rem == 32'(w_take));
  assign w_ent_end = w_blk_end & (((3'(reg_blk_idx) + 3'd1) >= w_blk_cnt) |
                                   (reg_rem == 32'(w_take)));
  assign o_rd_en   = w_build & w_ent_end;

  // Beat insertion: beat byte fill + k (bits [8(fill+k) +: 8]) takes block byte off + k.
  always_comb begin : p_com_beat_new
    w_beat_new = reg_beat_vld ? '0 : reg_beat;
    w_src_pos  = '0;
    for (int idx = 0; idx < LPARA_BLK_BYTES; idx++)
      w_src_pos[idx] = reg_blk_off + 5'(idx) - w_fill_base;
    for (int idx = 0; idx < LPARA_BLK_BYTES; idx++) begin
      if ((5'(idx) >= w_fill_base) && (5'(idx) < (w_fill_base + w_take)))
        w_beat_new[LPARA_BYTE_W*idx +: LPARA_BYTE_W] =
          w_blk[{~w_src_pos[idx][3:0], 3'b111} -: LPARA_BYTE_W];
    end
  end

  // Beat outputs and the payload bytes not yet read by the bus.
  assign o_beat_valid = reg_beat_vld;
  assign o_beat_data  = reg_beat;
  assign o_unread     = reg_rem + 32'(reg_beat_fill);

  // Message state and unpacking position.
  always_ff @(posedge i_clk_bus, negedge i_rst_n_bus) begin : p_ff_unpack
    if (!i_rst_n_bus) begin
      reg_rem         <= '0;
      reg_bpb         <= 5'(LPARA_BLK_BYTES);
      reg_bpe         <= 3'd1;
      reg_beat_bytes  <= 5'(LPARA_BLK_BYTES);
      reg_burst_bytes <= '0;
      reg_blk_idx     <= '0;
      reg_blk_off     <= '0;
      reg_beat        <= '0;
      reg_beat_fill   <= '0;
      reg_beat_vld    <= 1'b0;
    end else if (i_flush) begin
      reg_rem       <= '0;
      reg_blk_idx   <= '0;
      reg_blk_off   <= '0;
      reg_beat      <= '0;
      reg_beat_fill <= '0;
      reg_beat_vld  <= 1'b0;
    end else if (i_load) begin
      reg_rem         <= i_data_len;
      reg_bpb         <= i_bpb;
      reg_bpe         <= i_bpe;
      reg_beat_bytes  <= i_beat_bytes;
      reg_burst_bytes <= i_burst_bytes;
      reg_blk_idx     <= '0;
      reg_blk_off     <= '0;
      reg_beat        <= '0;
      reg_beat_fill   <= '0;
      reg_beat_vld    <= 1'b0;
    end else begin
      if (reg_beat_vld && i_beat_ready) begin
        reg_beat_vld  <= 1'b0;
        reg_beat      <= '0;
        reg_beat_fill <= '0;
      end
      if (w_build) begin
        reg_rem  <= reg_rem - 32'(w_take);
        reg_beat <= w_beat_new;
        if (((w_fill_base + w_take) == reg_beat_bytes) || (reg_rem == 32'(w_take))) begin
          reg_beat_vld  <= 1'b1;
          reg_beat_fill <= '0;
        end else begin
          reg_beat_fill <= w_fill_base + w_take;
        end
        if (w_ent_end) begin
          reg_blk_idx <= '0;
          reg_blk_off <= '0;
        end else if (w_blk_end) begin
          reg_blk_idx <= reg_blk_idx + 2'd1;
          reg_blk_off <= '0;
        end else begin
          reg_blk_off <= reg_blk_off + w_take;
        end
      end
    end
  end

  // DMA output condition: the bytes already held (beat and head entry) plus the full entries
  // behind the head must cover min(burst, unread). Entries before the last one of a message are
  // full, so occupancy >= head + needed entries proves the bytes are present.
  assign w_bpe_bytes = 32'(reg_bpb) * 32'(reg_bpe);
  assign w_held      = 32'(reg_beat_fill) + 32'(reg_beat_vld ? reg_beat_bytes : 5'd0) +
                       (i_empty ? 32'd0 :
                        (32'(w_blk_cnt - 3'(reg_blk_idx)) * 32'(reg_bpb) - 32'(reg_blk_off)));
  assign w_want      = (o_unread < 32'(reg_burst_bytes)) ? o_unread : 32'(reg_burst_bytes);
  assign w_need_bytes = (w_want > w_held) ? (w_want - w_held) : 32'd0;

  // Entries needed behind the head, as the FIFO empty threshold (occupancy <= threshold).
  always_comb begin : p_com_need
    // A burst is at most 256 bytes and an entry at most 64 bytes, so a 10-bit by 7-bit divider
    // is enough.
    w_need_num = w_need_bytes[9:0] + {3'd0, w_bpe_bytes[6:0]} - 10'd1;
    w_need_ent = '0;
    if (w_bpe_bytes[6:0] != '0)
      w_need_ent = {22'd0, w_need_num / {3'd0, w_bpe_bytes[6:0]}};
    w_thr = PARA_THR_W'(w_need_ent + (i_empty ? 32'd0 : 32'd1));
    if (w_thr != '0)
      w_thr = w_thr - PARA_THR_W'(1);
  end

  // Registered threshold to the library FIFO.
  assign o_empty_thr = reg_thr;

  // The threshold flag of the library FIFO may lag the threshold by one clock, so the condition
  // is taken only when the threshold was equal in the previous clock.
  always_ff @(posedge i_clk_bus, negedge i_rst_n_bus) begin : p_ff_dma
    if (!i_rst_n_bus) begin
      reg_thr        <= '0;
      reg_thr_stable <= 1'b0;
      reg_dma_cond   <= 1'b0;
    end else begin
      reg_thr        <= w_thr;
      reg_thr_stable <= (w_thr == reg_thr);
      reg_dma_cond   <= (o_unread != '0) & reg_thr_stable & (w_thr == reg_thr) &
                        ((w_need_bytes == '0) | ~i_empty_thr_flag);
    end
  end

  // Registered DMA output condition.
  assign o_dma_cond = reg_dma_cond;

endmodule
