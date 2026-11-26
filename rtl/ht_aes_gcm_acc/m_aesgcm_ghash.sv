/*
 * Project      : AES-GCM Accelerator
 * Author       : Nguyen Hung Quan and Claude (user)
 * AI Flow      : VLSIT RTL Generator AI Automation Flow
 * AI Flow Page : https://github.com/nguyenquanicd/VLSIT_RTL_Generator_AI_Model
 * Date         : 2026-11-25
 * Description  : GHASH accumulator of SP 800-38D Algorithm 2 (spec 9.3, 13.1, DEC-017).
 *                PARA_GHASH_ARCH = 2: aggregated, one entry of k <= PARA_LANE_NUM blocks per
 *                clock, Y <- (Y xor X1) H^k xor X2 H^(k-1) xor ... xor Xk H.
 *                PARA_GHASH_ARCH = 1: one parallel multiplier, one block per clock; the blocks of
 *                an entry are taken in order from a serializer register.
 *                PARA_GHASH_ARCH = 0: digit-serial multiplier (FSM ghs in m_aesgcm_ghash_mul),
 *                128 / PARA_GHASH_DIGIT_W clocks per block plus two control clocks.
 *                PARA_GHASH_PIPE = 1 (ARCH 1 and 2): feed-forward pipeline, the products of the
 *                blocks P = X1 H^k xor ... xor Xk H are registered first and the loop computes
 *                Y <- Y H^k xor P one clock later.
 *                The powers of H come from m_aesgcm_hpow.
 * Deviation    : HIE-02 (SHOULD) - the accumulator register and the generate selection of the
 *                architecture sit with the multiplier instances; the accumulator is the GHASH
 *                function itself.
 * Decisions    : DEC-017 (spec section 20).
 */
`timescale 1ns/1ps

module m_aesgcm_ghash #(
  // Parameter Description: number of 128-bit blocks of one entry (PARA_AES_LANE_NUM).
  // Parameter values: 1 to 4; default is 1.
  // Parameter unit: block
  parameter logic [31:0] PARA_LANE_NUM = 1,
  // Parameter Description: GHASH architecture; 0 digit-serial, 1 single parallel multiplier,
  // 2 aggregated parallel multipliers.
  // Parameter values: 0, 1 or 2; default is 1.
  // Parameter unit: none
  parameter logic [31:0] PARA_GHASH_ARCH = 1,
  // Parameter Description: bits of the multiplicand per clock of the digit-serial multiplier.
  // Parameter values: 4, 8, 16, 32 or 64; default is 16; used only for PARA_GHASH_ARCH = 0.
  // Parameter unit: bit
  parameter logic [31:0] PARA_GHASH_DIGIT_W = 16,
  // Parameter Description: feed-forward pipeline stage; 0 none, 1 one stage.
  // Parameter values: 0 or 1; default is 0; used only for PARA_GHASH_ARCH = 1 or 2.
  // Parameter unit: none
  parameter logic [31:0] PARA_GHASH_PIPE = 0,
  localparam logic [31:0] LPARA_BLK_W = 128,
  localparam logic [31:0] LPARA_DATA_W = PARA_LANE_NUM * LPARA_BLK_W,
  localparam logic [31:0] LPARA_POW_NUM = (PARA_GHASH_ARCH == 2) ? PARA_LANE_NUM : 1,
  localparam logic [31:0] LPARA_POW_W = LPARA_POW_NUM * LPARA_BLK_W,
  localparam logic [31:0] LPARA_ARCH_AGG = 2,
  localparam logic [31:0] LPARA_ARCH_SER = 0
) (
  // Clock and reset (CORE domain)
  input  wire                      i_clk_core,
  input  wire                      i_rst_n_core,

  // Control: i_clr clears the accumulator, i_zeroize also clears the powers of H
  input  wire                      i_zeroize,
  input  wire                      i_clr,
  input  wire                      i_load_y,
  input  wire  [LPARA_BLK_W-1:0]   i_y,
  input  wire  [LPARA_BLK_W-1:0]   i_h,
  input  wire                      i_pow_start,
  output logic                     o_pow_done,

  // Block input (prefix lane mask, lane 0 is the earliest block)
  input  wire                      i_valid,
  output logic                     o_ready,
  input  wire  [LPARA_DATA_W-1:0]  i_data,
  input  wire  [PARA_LANE_NUM-1:0] i_mask,

  // Accumulator
  output logic [LPARA_BLK_W-1:0]   o_y,
  output logic                     o_idle
);

  // Internal signal declarations
  logic [LPARA_BLK_W-1:0] reg_y;
  logic [LPARA_POW_W-1:0] w_hpow;
  logic [2:0]             w_cnt;
  logic                   w_fire;

  // Number of valid blocks of the prefix mask and the accepted entry.
  always_comb begin : p_com_cnt
    w_cnt = '0;
    for (int idx = 0; idx < PARA_LANE_NUM; idx++) begin
      if (i_mask[idx])
        w_cnt = 3'(idx + 1);
    end
  end

  // Accepted entry and accumulator output.
  assign w_fire = i_valid & o_ready;
  assign o_y    = reg_y;

  // Powers H^1 .. H^LPARA_POW_NUM, recomputed after each new H.
  m_aesgcm_hpow #(
    .PARA_POW_NUM (LPARA_POW_NUM)
  ) u_hpow (
    .i_clk_core   (i_clk_core),
    .i_rst_n_core (i_rst_n_core),
    .i_clr        (i_zeroize),
    .i_start      (i_pow_start),
    .i_h          (i_h),
    .o_done       (o_pow_done),
    .o_hpow       (w_hpow)
  );

  if (PARA_GHASH_ARCH == LPARA_ARCH_AGG) begin : gen_agg
    // Aggregated architecture: lane j multiplies its operand by H^(k-j).
    logic [LPARA_DATA_W-1:0] w_opd;
    logic [LPARA_DATA_W-1:0] w_pow_sel;
    logic [LPARA_DATA_W-1:0] w_prod;
    logic [LPARA_BLK_W-1:0]  w_sum;

    // Operands: block j for j < k, zero otherwise; without pipeline, lane 0 adds Y.
    always_comb begin : p_com_opd
      w_opd     = '0;
      w_pow_sel = '0;
      for (int idx = 0; idx < PARA_LANE_NUM; idx++) begin
        if (3'(idx) < w_cnt) begin
          w_opd[idx*LPARA_BLK_W +: LPARA_BLK_W] = i_data[idx*LPARA_BLK_W +: LPARA_BLK_W];
          for (int pidx = 0; pidx < PARA_LANE_NUM; pidx++) begin
            if (3'(pidx) == (w_cnt - 3'(idx) - 3'd1))
              w_pow_sel[idx*LPARA_BLK_W +: LPARA_BLK_W] = w_hpow[pidx*LPARA_BLK_W +: LPARA_BLK_W];
          end
        end
      end
      if (PARA_GHASH_PIPE == 0)
        w_opd[LPARA_BLK_W-1:0] = w_opd[LPARA_BLK_W-1:0] ^ reg_y;
    end

    for (genvar gen_idx = 0; gen_idx < PARA_LANE_NUM; gen_idx++) begin : gen_mul
      // One parallel multiplier per lane.
      m_aesgcm_ghash_mul #(
        .PARA_MUL_SERIAL (32'd0),
        .PARA_DIGIT_W    (PARA_GHASH_DIGIT_W)
      ) u_ghash_mul (
        .i_clk_core   (i_clk_core),
        .i_rst_n_core (i_rst_n_core),
        .i_valid      (w_fire),
        .o_ready      (),
        .i_x          (w_opd[gen_idx*LPARA_BLK_W +: LPARA_BLK_W]),
        .i_y          (w_pow_sel[gen_idx*LPARA_BLK_W +: LPARA_BLK_W]),
        .i_abort      (i_clr),
        .o_valid      (),
        .o_p          (w_prod[gen_idx*LPARA_BLK_W +: LPARA_BLK_W])
      );
    end

    // XOR merge of the lane products.
    always_comb begin : p_com_sum
      w_sum = '0;
      for (int idx = 0; idx < PARA_LANE_NUM; idx++)
        w_sum = w_sum ^ w_prod[idx*LPARA_BLK_W +: LPARA_BLK_W];
    end

    // The aggregated structure accepts one entry in every clock.
    assign o_ready = 1'b1;

    if (PARA_GHASH_PIPE == 0) begin : gen_pipe0
      // Accumulator update in the clock of the entry.
      always_ff @(posedge i_clk_core, negedge i_rst_n_core) begin : p_ff_y
        if (!i_rst_n_core)
          reg_y <= '0;
        else begin
          casez ({i_clr, i_load_y, w_fire})
            3'b1??:  reg_y <= '0;
            3'b01?:  reg_y <= i_y;
            3'b001:  reg_y <= w_sum;
            default: reg_y <= reg_y;
          endcase
        end
      end

      // The accumulator is final in the clock after each entry.
      assign o_idle = 1'b1;
    end else begin : gen_pipe1
      // Stage 1 registers P and k; stage 2 computes Y H^k xor P with one more multiplier.
      logic [LPARA_BLK_W-1:0] reg_p;
      logic [2:0]             reg_k;
      logic                   reg_v1;
      logic [LPARA_BLK_W-1:0] w_pow_k;
      logic [LPARA_BLK_W-1:0] w_prod_y;

      // Stage 1 registers of the batch products and the batch size.
      always_ff @(posedge i_clk_core, negedge i_rst_n_core) begin : p_ff_stage1
        if (!i_rst_n_core) begin
          reg_p  <= '0;
          reg_k  <= '0;
          reg_v1 <= 1'b0;
        end else if (i_clr) begin
          reg_p  <= '0;
          reg_k  <= '0;
          reg_v1 <= 1'b0;
        end else begin
          reg_p  <= w_sum;
          reg_k  <= w_cnt;
          reg_v1 <= w_fire;
        end
      end

      // H^k of the registered batch.
      always_comb begin : p_com_pow_k
        w_pow_k = w_hpow[LPARA_BLK_W-1:0];
        for (int pidx = 0; pidx < PARA_LANE_NUM; pidx++) begin
          if (3'(pidx) == (reg_k - 3'd1))
            w_pow_k = w_hpow[pidx*LPARA_BLK_W +: LPARA_BLK_W];
        end
      end

      m_aesgcm_ghash_mul #(
        .PARA_MUL_SERIAL (32'd0),
        .PARA_DIGIT_W    (PARA_GHASH_DIGIT_W)
      ) u_ghash_mul_y (
        .i_clk_core   (i_clk_core),
        .i_rst_n_core (i_rst_n_core),
        .i_valid      (reg_v1),
        .o_ready      (),
        .i_x          (reg_y),
        .i_y          (w_pow_k),
        .i_abort      (i_clr),
        .o_valid      (),
        .o_p          (w_prod_y)
      );

      // Accumulator update one clock after the entry.
      always_ff @(posedge i_clk_core, negedge i_rst_n_core) begin : p_ff_y
        if (!i_rst_n_core)
          reg_y <= '0;
        else begin
          casez ({i_clr, i_load_y, reg_v1})
            3'b1??:  reg_y <= '0;
            3'b01?:  reg_y <= i_y;
            3'b001:  reg_y <= w_prod_y ^ reg_p;
            default: reg_y <= reg_y;
          endcase
        end
      end

      // Idle when no batch is in stage 1.
      assign o_idle = ~reg_v1;
    end
  end else begin : gen_ser
    // Single multiplier: the entry is held and its blocks are hashed one at a time.
    logic [LPARA_DATA_W-1:0] reg_sdata;
    logic [2:0]              reg_scnt;
    logic [2:0]              reg_sidx;
    logic                    reg_busy;
    logic [LPARA_BLK_W-1:0]  w_blk;
    logic                    w_step;
    logic                    w_step_last;

    // Current block of the held entry.
    always_comb begin : p_com_blk
      w_blk = reg_sdata[LPARA_BLK_W-1:0];
      for (int idx = 0; idx < PARA_LANE_NUM; idx++) begin
        if (reg_sidx == 3'(idx))
          w_blk = reg_sdata[idx*LPARA_BLK_W +: LPARA_BLK_W];
      end
    end

    // A new entry is taken when the serializer is empty or hashes its last block now.
    assign w_step_last = w_step & ((reg_sidx + 3'd1) == reg_scnt);
    assign o_ready     = ~reg_busy | w_step_last;

    // Serializer register.
    always_ff @(posedge i_clk_core, negedge i_rst_n_core) begin : p_ff_ser
      if (!i_rst_n_core) begin
        reg_sdata <= '0;
        reg_scnt  <= '0;
        reg_sidx  <= '0;
        reg_busy  <= 1'b0;
      end else if (i_clr) begin
        reg_sdata <= '0;
        reg_scnt  <= '0;
        reg_sidx  <= '0;
        reg_busy  <= 1'b0;
      end else begin
        casez ({w_fire, w_step})
          2'b1?: begin
            reg_sdata <= i_data;
            reg_scnt  <= w_cnt;
            reg_sidx  <= '0;
            reg_busy  <= (w_cnt != 3'd0);
          end
          2'b01: begin
            reg_sidx <= reg_sidx + 3'd1;
            if (w_step_last)
              reg_busy <= 1'b0;
          end
          default: begin
            reg_busy <= reg_busy;
          end
        endcase
      end
    end

    if (PARA_GHASH_ARCH == LPARA_ARCH_SER) begin : gen_digit
      // Digit-serial multiplier: one block per multiplication of 128 / D clocks.
      logic                   w_mul_ready;
      logic                   w_mul_valid;
      logic [LPARA_BLK_W-1:0] w_mul_p;

      // A block is complete when the multiplier presents its product.
      assign w_step = reg_busy & w_mul_valid;

      m_aesgcm_ghash_mul #(
        .PARA_MUL_SERIAL (32'd1),
        .PARA_DIGIT_W    (PARA_GHASH_DIGIT_W)
      ) u_ghash_mul_0 (
        .i_clk_core   (i_clk_core),
        .i_rst_n_core (i_rst_n_core),
        .i_valid      (reg_busy & w_mul_ready),
        .o_ready      (w_mul_ready),
        .i_x          (reg_y ^ w_blk),
        .i_y          (w_hpow[LPARA_BLK_W-1:0]),
        .i_abort      (i_clr),
        .o_valid      (w_mul_valid),
        .o_p          (w_mul_p)
      );

      // Accumulator update when the product is presented.
      always_ff @(posedge i_clk_core, negedge i_rst_n_core) begin : p_ff_y
        if (!i_rst_n_core)
          reg_y <= '0;
        else begin
          casez ({i_clr, i_load_y, w_step})
            3'b1??:  reg_y <= '0;
            3'b01?:  reg_y <= i_y;
            3'b001:  reg_y <= w_mul_p;
            default: reg_y <= reg_y;
          endcase
        end
      end

      // Idle when no block is held and the multiplier waits.
      assign o_idle = ~reg_busy & w_mul_ready;
    end else if (PARA_GHASH_PIPE == 0) begin : gen_par
      // Single parallel multiplier, Y <- (Y xor X) H in one clock.
      logic [LPARA_BLK_W-1:0] w_mul_p;

      // One block per clock while an entry is held.
      assign w_step = reg_busy;

      m_aesgcm_ghash_mul #(
        .PARA_MUL_SERIAL (32'd0),
        .PARA_DIGIT_W    (PARA_GHASH_DIGIT_W)
      ) u_ghash_mul_0 (
        .i_clk_core   (i_clk_core),
        .i_rst_n_core (i_rst_n_core),
        .i_valid      (reg_busy),
        .o_ready      (),
        .i_x          (reg_y ^ w_blk),
        .i_y          (w_hpow[LPARA_BLK_W-1:0]),
        .i_abort      (i_clr),
        .o_valid      (),
        .o_p          (w_mul_p)
      );

      // Accumulator update for every hashed block.
      always_ff @(posedge i_clk_core, negedge i_rst_n_core) begin : p_ff_y
        if (!i_rst_n_core)
          reg_y <= '0;
        else begin
          casez ({i_clr, i_load_y, w_step})
            3'b1??:  reg_y <= '0;
            3'b01?:  reg_y <= i_y;
            3'b001:  reg_y <= w_mul_p;
            default: reg_y <= reg_y;
          endcase
        end
      end

      // Idle when no block is held.
      assign o_idle = ~reg_busy;
    end else begin : gen_par_pipe
      // Single parallel multiplier with the feed-forward stage: P = X H, then Y <- Y H xor P.
      logic [LPARA_BLK_W-1:0] reg_p;
      logic                   reg_v1;
      logic [LPARA_BLK_W-1:0] w_mul_p;
      logic [LPARA_BLK_W-1:0] w_prod_y;

      // One block per clock while an entry is held.
      assign w_step = reg_busy;

      m_aesgcm_ghash_mul #(
        .PARA_MUL_SERIAL (32'd0),
        .PARA_DIGIT_W    (PARA_GHASH_DIGIT_W)
      ) u_ghash_mul_0 (
        .i_clk_core   (i_clk_core),
        .i_rst_n_core (i_rst_n_core),
        .i_valid      (reg_busy),
        .o_ready      (),
        .i_x          (w_blk),
        .i_y          (w_hpow[LPARA_BLK_W-1:0]),
        .i_abort      (i_clr),
        .o_valid      (),
        .o_p          (w_mul_p)
      );

      m_aesgcm_ghash_mul #(
        .PARA_MUL_SERIAL (32'd0),
        .PARA_DIGIT_W    (PARA_GHASH_DIGIT_W)
      ) u_ghash_mul_y (
        .i_clk_core   (i_clk_core),
        .i_rst_n_core (i_rst_n_core),
        .i_valid      (reg_v1),
        .o_ready      (),
        .i_x          (reg_y),
        .i_y          (w_hpow[LPARA_BLK_W-1:0]),
        .i_abort      (i_clr),
        .o_valid      (),
        .o_p          (w_prod_y)
      );

      // Stage 1 register of the block product.
      always_ff @(posedge i_clk_core, negedge i_rst_n_core) begin : p_ff_stage1
        if (!i_rst_n_core) begin
          reg_p  <= '0;
          reg_v1 <= 1'b0;
        end else if (i_clr) begin
          reg_p  <= '0;
          reg_v1 <= 1'b0;
        end else begin
          reg_p  <= w_mul_p;
          reg_v1 <= w_step;
        end
      end

      // Accumulator update one clock after the block.
      always_ff @(posedge i_clk_core, negedge i_rst_n_core) begin : p_ff_y
        if (!i_rst_n_core)
          reg_y <= '0;
        else begin
          casez ({i_clr, i_load_y, reg_v1})
            3'b1??:  reg_y <= '0;
            3'b01?:  reg_y <= i_y;
            3'b001:  reg_y <= w_prod_y ^ reg_p;
            default: reg_y <= reg_y;
          endcase
        end
      end

      // Idle when no block is held and stage 1 is empty.
      assign o_idle = ~reg_busy & ~reg_v1;
    end
  end

endmodule
