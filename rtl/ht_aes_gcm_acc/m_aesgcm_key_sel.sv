/*
 * Project      : AES-GCM Accelerator
 * Author       : Nguyen Hung Quan and Claude (user)
 * AI Flow      : VLSIT RTL Generator AI Automation Flow
 * AI Flow Page : https://github.com/nguyenquanicd/VLSIT_RTL_Generator_AI_Model
 * Date         : 2026-11-25
 * Description  : Key selection and key store (spec 5.1, 6.3.5, MEM-004, OP-011). On i_load the
 *                store takes the APB key of the bundle (key source 0) or waits for the side-load
 *                key (key source 1) for at most i_keywait clocks; a side-load request without
 *                PARA_KEY_SIDE_EN, a timeout, or a side-load size different from the configured
 *                key size gives o_key_err (KEY_ERR, ERR-004). o_key_side_ack pulses one clock
 *                after the capture. A context restore loads the store directly. Zeroize and reset
 *                clear the store. The key never leaves the CORE domain.
 */
`timescale 1ns/1ps

module m_aesgcm_key_sel #(
  // Parameter Description: 1 builds the key side-load path.
  // Parameter values: 0 or 1; default is 0.
  // Parameter unit: none
  parameter logic [31:0] PARA_KEY_SIDE_EN = 0,
  localparam logic [31:0] LPARA_KEY_W = 256,
  localparam logic [31:0] LPARA_KEY128_W = 128
) (
  // Clock and reset (CORE domain)
  input  wire                    i_clk_core,
  input  wire                    i_rst_n_core,

  // Key request of the sequencer
  input  wire                    i_zeroize,
  input  wire                    i_load,
  input  wire                    i_key_src,
  input  wire                    i_key_size,
  input  wire  [LPARA_KEY_W-1:0] i_key_cfg,
  input  wire  [15:0]            i_keywait,

  // Context restore of the key store
  input  wire                    i_restore,
  input  wire  [LPARA_KEY_W-1:0] i_key_ctx,

  // Key side-load interface (IF-005)
  input  wire                    i_key_side_valid,
  input  wire                    i_key_side_size,
  input  wire  [LPARA_KEY_W-1:0] i_key_side,
  output logic                   o_key_side_ack,

  // Key store outputs
  output logic [LPARA_KEY_W-1:0] o_key,
  output logic                   o_key_ready,
  output logic                   o_key_err,
  output logic                   o_key_ld
);

  // Internal signal declarations
  logic [LPARA_KEY_W-1:0] reg_key;
  logic                   reg_ready;
  logic                   reg_ld;
  logic                   reg_wait;
  logic                   reg_wait_size;
  logic [15:0]            reg_wait_cnt;
  logic                   reg_ack;
  logic                   reg_err;
  logic [LPARA_KEY_W-1:0] w_side_key;
  logic                   w_side_ok;
  logic                   w_side_cap;
  logic                   w_timeout;
  logic                   w_side_err_now;

  // A 128-bit side-load key carries key bytes 0 to 15 in bits [255:128]; the AES core expects
  // them in bits [127:0] with bits [255:128] equal to 0 (spec 9.1).
  assign w_side_key = i_key_side_size ? i_key_side :
                      {{LPARA_KEY128_W{1'b0}}, i_key_side[LPARA_KEY_W-1 -: LPARA_KEY128_W]};

  // Side-load capture, size check and wait expiry.
  assign w_side_ok      = (PARA_KEY_SIDE_EN == 1);
  assign w_side_cap     = reg_wait & i_key_side_valid & (i_key_side_size == reg_wait_size);
  assign w_side_err_now = reg_wait & i_key_side_valid & (i_key_side_size != reg_wait_size);
  assign w_timeout      = reg_wait & ~i_key_side_valid & (reg_wait_cnt >= i_keywait);

  // Outputs of the store.
  assign o_key          = reg_key;
  assign o_key_ready    = reg_ready;
  assign o_key_err      = reg_err;
  assign o_key_ld       = reg_ld;
  assign o_key_side_ack = reg_ack;

  // Key store and side-load wait; zeroize has priority, then restore, then a new request.
  always_ff @(posedge i_clk_core, negedge i_rst_n_core) begin : p_ff_key
    if (!i_rst_n_core) begin
      reg_key       <= '0;
      reg_ready     <= 1'b0;
      reg_ld        <= 1'b0;
      reg_wait      <= 1'b0;
      reg_wait_size <= 1'b0;
      reg_wait_cnt  <= '0;
      reg_ack       <= 1'b0;
      reg_err       <= 1'b0;
    end else begin
      reg_ack <= 1'b0;
      reg_err <= 1'b0;
      casez ({i_zeroize, i_restore, i_load, w_side_cap, w_timeout | w_side_err_now})
        5'b1????: begin
          reg_key   <= '0;
          reg_ready <= 1'b0;
          reg_ld    <= 1'b0;
          reg_wait  <= 1'b0;
        end
        5'b01???: begin
          reg_key   <= i_key_ctx;
          reg_ready <= 1'b1;
          reg_ld    <= 1'b1;
          reg_wait  <= 1'b0;
        end
        5'b001??: begin
          reg_wait_cnt  <= '0;
          reg_wait_size <= i_key_size;
          if (!i_key_src) begin
            reg_key   <= i_key_cfg;
            reg_ready <= 1'b1;
            reg_ld    <= 1'b1;
          end else if (w_side_ok) begin
            reg_ready <= 1'b0;
            reg_wait  <= 1'b1;
          end else begin
            reg_ready <= 1'b0;
            reg_err   <= 1'b1;
          end
        end
        5'b0001?: begin
          reg_key   <= w_side_key;
          reg_ready <= 1'b1;
          reg_ld    <= 1'b1;
          reg_wait  <= 1'b0;
          reg_ack   <= 1'b1;
        end
        5'b00001: begin
          reg_wait <= 1'b0;
          reg_err  <= 1'b1;
        end
        default: begin
          if (reg_wait)
            reg_wait_cnt <= reg_wait_cnt + 16'd1;
        end
      endcase
    end
  end

endmodule
