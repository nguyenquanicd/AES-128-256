/*
 * Project      : AES-GCM Accelerator
 * Author       : Nguyen Hung Quan and Claude (user)
 * AI Flow      : VLSIT RTL Generator AI Automation Flow
 * AI Flow Page : https://github.com/nguyenquanicd/VLSIT_RTL_Generator_AI_Model
 * Date         : 2026-11-25
 * Description  : Bus-side packer of the input FIFO (spec 9.2, 10.4 item 1, DEC-018). It splits
 *                the beat stream into the AAD segment and the payload segment, forms blocks of
 *                i_bpb bytes (16, or the CFB segment bytes; byte 0 at bits [127:120], unused
 *                bytes zero) and entries of up to i_bpe blocks with a prefix lane mask, a segment
 *                tag and an end-of-segment flag. An entry never mixes segments; the bytes of a
 *                beat after the end of a segment are beat padding and are discarded. A beat that
 *                arrives while no segment byte is outstanding is dropped and reported (ERR-005).
 *                When the beat stream is idle for LPARA_IDLE_CLK clocks while completed blocks wait
 *                in an unfinished entry, the entry is written early with the blocks it holds
 *                (the bytes of an unfinished block stay in the packer); the segment is not ended,
 *                so the end flag is 0 (DEC-026). While i_hold is 1 (a resume waits for the restored
 *                lengths) no beat is accepted, so none is lost (DEC-027).
 * Decisions    : DEC-018, DEC-021, DEC-026, DEC-027 (spec section 20).
 */
`timescale 1ns/1ps

module m_aesgcm_pack #(
  // Parameter Description: number of 128-bit blocks of one FIFO entry (PARA_AES_LANE_NUM).
  // Parameter values: 1 to 4; default is 1.
  // Parameter unit: block
  parameter logic [31:0] PARA_LANE_NUM = 1,
  localparam logic [31:0] LPARA_BLK_W = 128,
  localparam logic [31:0] LPARA_BYTE_W = 8,
  localparam logic [31:0] LPARA_BLK_BYTES = LPARA_BLK_W / LPARA_BYTE_W,
  localparam logic [31:0] LPARA_IDLE_CLK = 16,
  localparam logic [31:0] LPARA_ENT_W = PARA_LANE_NUM * LPARA_BLK_W + PARA_LANE_NUM + 2
) (
  // Clock and reset (BUS domain)
  input  wire                    i_clk_bus,
  input  wire                    i_rst_n_bus,

  // Message control
  input  wire                    i_flush,
  input  wire                    i_load,
  input  wire                    i_hold,
  input  wire  [31:0]            i_aad_len,
  input  wire  [31:0]            i_data_len,
  input  wire  [4:0]             i_bpb,
  input  wire  [2:0]             i_bpe,
  input  wire  [4:0]             i_beat_bytes,
  output logic                   o_active,
  output logic                   o_drop,

  // Beat stream, first stream byte in bits [7:0]
  input  wire                    i_beat_valid,
  output logic                   o_beat_ready,
  input  wire  [LPARA_BLK_W-1:0] i_beat_data,

  // FIFO write side
  output logic                   o_wr_en,
  output logic [LPARA_ENT_W-1:0] o_wr_data,
  input  wire                    i_full
);

  // Internal signal declarations
  logic                                 reg_active;
  logic                                 reg_seg;
  logic [31:0]                          reg_seg_rem;
  logic [31:0]                          reg_pay_len;
  logic [4:0]                           reg_bpb;
  logic [2:0]                           reg_bpe;
  logic [4:0]                           reg_beat_bytes;
  logic                                 reg_beat_vld;
  logic [LPARA_BLK_W-1:0]               reg_beat;
  logic [4:0]                           reg_beat_off;
  logic [LPARA_BLK_W-1:0]               reg_blk;
  logic [4:0]                           reg_blk_fill;
  logic [PARA_LANE_NUM*LPARA_BLK_W-1:0] reg_ent;
  logic [2:0]                           reg_ent_cnt;
  logic [4:0]                           w_avail;
  logic [4:0]                           w_room;
  logic [4:0]                           w_take;
  logic                                 w_seg_end;
  logic                                 w_blk_done;
  logic                                 w_ent_done;
  logic                                 w_stall;
  logic                                 w_proc;
  logic                                 w_beat_used;
  logic                                 w_beat_drop;
  logic                                 w_beat_take;
  logic [LPARA_BLK_W-1:0]               w_blk_new;
  logic [LPARA_BLK_BYTES-1:0][4:0]      w_src_pos;
  logic [PARA_LANE_NUM*LPARA_BLK_W-1:0] w_ent_new;
  logic [PARA_LANE_NUM-1:0]             w_mask;
  logic [4:0]                           reg_idle;
  logic                                 w_quiet;
  logic                                 w_idle_flush;
  logic [PARA_LANE_NUM-1:0]             w_idle_mask;

  // Bytes left in the beat buffer, room left in the block, and the bytes moved this clock.
  assign w_avail = reg_beat_bytes - reg_beat_off;
  assign w_room  = reg_bpb - reg_blk_fill;

  // The bytes moved are limited by the beat, the block room and the segment remainder.
  always_comb begin : p_com_take
    w_take = w_avail;
    if (w_room < w_take)
      w_take = w_room;
    if (reg_seg_rem < 32'(w_take))
      w_take = reg_seg_rem[4:0];
  end

  // Segment, block and entry completion of the bytes moved this clock.
  assign w_proc      = reg_beat_vld & reg_active;
  assign w_seg_end   = (reg_seg_rem == 32'(w_take));
  assign w_blk_done  = ((reg_blk_fill + w_take) == reg_bpb) | w_seg_end;
  assign w_ent_done  = w_blk_done & (((reg_ent_cnt + 3'd1) == reg_bpe) | w_seg_end);
  assign w_stall     = w_proc & w_ent_done & i_full;
  assign w_beat_used = w_proc & ~w_stall & (((reg_beat_off + w_take) == reg_beat_bytes) |
                                              w_seg_end);
  // A beat outside the segments is dropped whole.
  assign w_beat_drop = reg_beat_vld & ~reg_active;

  // The beat buffer is free when it is empty or when its last byte leaves in this clock.
  assign o_beat_ready = (~reg_beat_vld | w_beat_used | w_beat_drop) & ~i_hold;
  assign w_beat_take  = i_beat_valid & o_beat_ready;
  assign o_drop       = w_beat_drop;
  assign o_active     = reg_active;

  // Block insertion: block byte j (bits [127-8j -: 8]) receives beat byte off + j - fill for
  // the w_take positions that start at the block fill level.
  always_comb begin : p_com_blk_new
    w_blk_new = reg_blk;
    w_src_pos = '0;
    for (int idx = 0; idx < LPARA_BLK_BYTES; idx++)
      w_src_pos[idx] = reg_beat_off + 5'(idx) - reg_blk_fill;
    for (int idx = 0; idx < LPARA_BLK_BYTES; idx++) begin
      if ((5'(idx) >= reg_blk_fill) && (5'(idx) < (reg_blk_fill + w_take)))
        w_blk_new[LPARA_BLK_W-1-LPARA_BYTE_W*idx -: LPARA_BYTE_W] =
          reg_beat[{w_src_pos[idx][3:0], 3'b000} +: LPARA_BYTE_W];
    end
  end

  // Entry insertion: a completed block takes lane reg_ent_cnt (lane 0 is the earliest block).
  always_comb begin : p_com_ent_new
    w_ent_new = reg_ent;
    for (int idx = 0; idx < PARA_LANE_NUM; idx++) begin
      if (reg_ent_cnt == 3'(idx))
        w_ent_new[idx*LPARA_BLK_W +: LPARA_BLK_W] = w_blk_new;
    end
  end

  // Prefix lane mask of the entry written this clock: lanes 0 to reg_ent_cnt.
  always_comb begin : p_com_mask
    w_mask = '0;
    for (int idx = 0; idx < PARA_LANE_NUM; idx++) begin
      if (3'(idx) <= reg_ent_cnt)
        w_mask[idx] = 1'b1;
    end
  end

  // Idle flush (DEC-026): completed blocks wait in the entry, no beat is held or offered, and the
  // stream has been quiet for LPARA_IDLE_CLK clocks. The entry holds reg_ent_cnt blocks.
  assign w_quiet      = reg_active & ~reg_beat_vld & ~i_beat_valid & (reg_ent_cnt != 3'd0);
  assign w_idle_flush = w_quiet & (reg_idle == 5'(LPARA_IDLE_CLK)) & ~i_full;

  always_comb begin : p_com_idle_mask
    w_idle_mask = '0;
    for (int idx = 0; idx < PARA_LANE_NUM; idx++) begin
      if (3'(idx) < reg_ent_cnt)
        w_idle_mask[idx] = 1'b1;
    end
  end

  always_ff @(posedge i_clk_bus, negedge i_rst_n_bus) begin : p_ff_idle
    if (!i_rst_n_bus)
      reg_idle <= '0;
    else if (i_flush || i_load || !w_quiet || w_idle_flush)
      reg_idle <= '0;
    else if (reg_idle != 5'(LPARA_IDLE_CLK))
      reg_idle <= reg_idle + 5'd1;
  end

  // FIFO write: one entry {segment, end of segment, lane mask, blocks} when it completes, or the
  // early entry of the idle flush (end flag 0).
  assign o_wr_en   = (w_proc & w_ent_done & ~i_full) | w_idle_flush;
  assign o_wr_data = w_idle_flush ? {reg_seg, 1'b0, w_idle_mask, reg_ent} :
                                    {reg_seg, w_seg_end, w_mask, w_ent_new};

  // Message and segment state; flush and load have priority over the byte movement.
  always_ff @(posedge i_clk_bus, negedge i_rst_n_bus) begin : p_ff_seg
    if (!i_rst_n_bus) begin
      reg_active     <= 1'b0;
      reg_seg        <= 1'b0;
      reg_seg_rem    <= '0;
      reg_pay_len    <= '0;
      reg_bpb        <= 5'(LPARA_BLK_BYTES);
      reg_bpe        <= 3'd1;
      reg_beat_bytes <= 5'(LPARA_BLK_BYTES);
    end else begin
      casez ({i_flush, i_load, w_proc & ~w_stall})
        3'b1??: begin
          reg_active  <= 1'b0;
          reg_seg     <= 1'b0;
          reg_seg_rem <= '0;
          reg_pay_len <= '0;
        end
        3'b01?: begin
          reg_active     <= (i_aad_len != '0) | (i_data_len != '0);
          reg_seg        <= (i_aad_len == '0);
          reg_seg_rem    <= (i_aad_len != '0) ? i_aad_len : i_data_len;
          reg_pay_len    <= i_data_len;
          reg_bpb        <= i_bpb;
          reg_bpe        <= i_bpe;
          reg_beat_bytes <= i_beat_bytes;
        end
        3'b001: begin
          if (w_seg_end) begin
            if (!reg_seg && (reg_pay_len != '0)) begin
              reg_seg     <= 1'b1;
              reg_seg_rem <= reg_pay_len;
            end else begin
              reg_active  <= 1'b0;
              reg_seg_rem <= '0;
            end
          end else begin
            reg_seg_rem <= reg_seg_rem - 32'(w_take);
          end
        end
        default: begin
          reg_active <= reg_active;
        end
      endcase
    end
  end

  // Beat buffer, block and entry registers.
  always_ff @(posedge i_clk_bus, negedge i_rst_n_bus) begin : p_ff_data
    if (!i_rst_n_bus) begin
      reg_beat_vld <= 1'b0;
      reg_beat     <= '0;
      reg_beat_off <= '0;
      reg_blk      <= '0;
      reg_blk_fill <= '0;
      reg_ent      <= '0;
      reg_ent_cnt  <= '0;
    end else if (i_flush || i_load) begin
      reg_beat_vld <= 1'b0;
      reg_beat     <= '0;
      reg_beat_off <= '0;
      reg_blk      <= '0;
      reg_blk_fill <= '0;
      reg_ent      <= '0;
      reg_ent_cnt  <= '0;
    end else begin
      casez ({w_beat_take, w_beat_used | w_beat_drop, w_proc & ~w_stall})
        3'b1??: begin
          reg_beat_vld <= 1'b1;
          reg_beat     <= i_beat_data;
          reg_beat_off <= '0;
        end
        3'b01?: begin
          reg_beat_vld <= 1'b0;
          reg_beat     <= '0;
          reg_beat_off <= '0;
        end
        3'b001: reg_beat_off <= reg_beat_off + w_take;
        default: reg_beat_off <= reg_beat_off;
      endcase
      if (w_proc && !w_stall) begin
        if (w_blk_done) begin
          reg_blk      <= '0;
          reg_blk_fill <= '0;
        end else begin
          reg_blk      <= w_blk_new;
          reg_blk_fill <= reg_blk_fill + w_take;
        end
        if (w_ent_done) begin
          reg_ent     <= '0;
          reg_ent_cnt <= '0;
        end else if (w_blk_done) begin
          reg_ent     <= w_ent_new;
          reg_ent_cnt <= reg_ent_cnt + 3'd1;
        end
      end
      if (w_idle_flush) begin
        reg_ent     <= '0;
        reg_ent_cnt <= '0;
      end
    end
  end

endmodule
