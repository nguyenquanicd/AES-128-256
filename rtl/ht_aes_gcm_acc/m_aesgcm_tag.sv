/*
 * Project      : AES-GCM Accelerator
 * Author       : Nguyen Hung Quan and Claude (user)
 * AI Flow      : VLSIT RTL Generator AI Automation Flow
 * AI Flow Page : https://github.com/nguyenquanicd/VLSIT_RTL_Generator_AI_Model
 * Date         : 2026-11-25
 * Description  : Tag formation T = MSB_t(E(K,J0) xor S) and full-width comparison with the expected
 *                tag (SP 800-38D 7.1 step 6, 7.2 step 8). The comparison has no early exit.
 */
`timescale 1ns/1ps

module m_aesgcm_tag #(
  localparam logic [31:0] LPARA_BLK_W = 128,
  // Largest legal tag-length code (4 = 96-bit tag, SP 800-38D 5.2.1.2).
  localparam logic [31:0] LPARA_TLEN_CODE_MAX = 4
) (
  // Tag inputs
  input  wire  [LPARA_BLK_W-1:0] i_s,
  input  wire  [LPARA_BLK_W-1:0] i_ej0,
  input  wire  [2:0]             i_tag_len,
  input  wire  [LPARA_BLK_W-1:0] i_tag_exp,

  // Tag outputs
  output logic [LPARA_BLK_W-1:0] o_tag,
  output logic                   o_match
);

  // Internal signal declarations
  logic [2:0]             w_len_code;
  logic [LPARA_BLK_W-1:0] w_mask;

  // Tag-length code 0 to 4 keeps the leftmost 128 - 8 x code bits (128, 120, 112, 104, 96);
  // reserved codes are rejected before the message starts, here they compare as code 4 (96 bits).
  assign w_len_code = (i_tag_len > LPARA_TLEN_CODE_MAX[2:0]) ? LPARA_TLEN_CODE_MAX[2:0] : i_tag_len;
  assign w_mask     = {LPARA_BLK_W{1'b1}} << {w_len_code, 3'b000};

  // The full tag is reported; the match compares only the leading t bits.
  assign o_tag   = i_s ^ i_ej0;
  assign o_match = (((o_tag ^ i_tag_exp) & w_mask) == '0);

endmodule
