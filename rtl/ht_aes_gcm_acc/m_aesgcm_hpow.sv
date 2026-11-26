/*
 * Project      : AES-GCM Accelerator
 * Author       : Nguyen Hung Quan and Claude (user)
 * AI Flow      : VLSIT RTL Generator AI Automation Flow
 * AI Flow Page : https://github.com/nguyenquanicd/VLSIT_RTL_Generator_AI_Model
 * Date         : 2026-11-25
 * Description  : Hash-subkey power generator: H^1 .. H^PARA_POW_NUM, one multiplication per clock
 *                (spec section 5.3 step 3, state ENUM_ST_SEQ_POW). H^1 is loaded at the start.
 * Deviation    : HIE-02 (SHOULD) - the power register and its sequencing sit beside the one
 *                multiplier instance; splitting a 30-line control into its own module adds a
 *                level without making the code clearer.
 */
`timescale 1ns/1ps

module m_aesgcm_hpow #(
  // Parameter Description: number of powers of H that the GHASH architecture needs.
  // Parameter values: 1 to 4; default is 1 (PARA_AES_LANE_NUM for the aggregated GHASH).
  // Parameter unit: count
  parameter logic [31:0] PARA_POW_NUM = 1,
  localparam logic [31:0] LPARA_BLK_W = 128,
  localparam logic [31:0] LPARA_POW_W = PARA_POW_NUM * LPARA_BLK_W,
  // Digit width handed to the multiplier; unused because the multiplier here is parallel.
  localparam logic [31:0] LPARA_DIGIT_W = 16
) (
  // Clock and reset
  input  wire                    i_clk_core,
  input  wire                    i_rst_n_core,

  // Control
  input  wire                    i_clr,
  input  wire                    i_start,
  input  wire  [LPARA_BLK_W-1:0] i_h,
  output logic                   o_done,

  // Powers, H^(i+1) in slice i
  output logic [LPARA_POW_W-1:0] o_hpow
);

  // Internal signal declarations
  logic [LPARA_POW_W-1:0] reg_hpow;
  logic [LPARA_POW_W-1:0] w_hpow_nxt;
  logic [2:0]             reg_idx;
  logic [2:0]             w_idx_nxt;
  logic                   reg_busy;
  logic                   w_busy_nxt;
  logic [LPARA_BLK_W-1:0] w_prev;
  logic [LPARA_BLK_W-1:0] w_prod;

  // Output mapping: the powers register and the completion flag.
  assign o_hpow = reg_hpow;
  assign o_done = ~reg_busy & ~i_start;

  // The previous power is the slice below the index being computed (index 1 uses H^1).
  always_comb begin : p_com_prev
    w_prev = reg_hpow[LPARA_BLK_W-1:0];
    for (int idx = 1; idx < PARA_POW_NUM; idx++) begin
      if (reg_idx == 3'(idx))
        w_prev = reg_hpow[(idx-1)*LPARA_BLK_W +: LPARA_BLK_W];
    end
  end

  // Power sequence: start loads H^1 and index 1; each busy clock stores H^(idx+1) = H^idx * H
  // and advances the index; the generator is done when the index reaches PARA_POW_NUM.
  always_comb begin : p_com_hpow_nxt
    w_hpow_nxt = reg_hpow;
    w_idx_nxt  = reg_idx;
    w_busy_nxt = reg_busy;
    casez ({i_clr, i_start, reg_busy})
      3'b1??: begin
        w_hpow_nxt = '0;
        w_idx_nxt  = '0;
        w_busy_nxt = 1'b0;
      end
      3'b01?: begin
        w_hpow_nxt[LPARA_BLK_W-1:0] = i_h;
        w_idx_nxt  = 3'd1;
        w_busy_nxt = (PARA_POW_NUM > 1);
      end
      3'b001: begin
        for (int idx = 1; idx < PARA_POW_NUM; idx++) begin
          if (reg_idx == 3'(idx))
            w_hpow_nxt[idx*LPARA_BLK_W +: LPARA_BLK_W] = w_prod;
        end
        w_idx_nxt  = 3'(reg_idx + 3'd1);
        w_busy_nxt = ((32'(reg_idx) + 32'd1) < PARA_POW_NUM);
      end
      default: begin
        w_busy_nxt = reg_busy;
      end
    endcase
  end

  // Control and key-derived powers are reset so that no hash-subkey value survives a reset.
  always_ff @(posedge i_clk_core, negedge i_rst_n_core) begin : p_ff_hpow
    if (!i_rst_n_core) begin
      reg_hpow <= '0;
      reg_idx  <= '0;
      reg_busy <= 1'b0;
    end else begin
      reg_hpow <= w_hpow_nxt;
      reg_idx  <= w_idx_nxt;
      reg_busy <= w_busy_nxt;
    end
  end

  // One parallel multiplier computes H^idx * H.
  m_aesgcm_ghash_mul #(
    .PARA_MUL_SERIAL (0),
    .PARA_DIGIT_W    (LPARA_DIGIT_W)
  ) u_ghash_mul (
    .i_clk_core   (i_clk_core),
    .i_rst_n_core (i_rst_n_core),
    .i_valid      (reg_busy),
    .o_ready      (),
    .i_x          (w_prev),
    .i_y          (reg_hpow[LPARA_BLK_W-1:0]),
    .i_abort      (i_clr),
    .o_valid      (),
    .o_p          (w_prod)
  );

endmodule
