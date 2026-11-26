/*
 * Project      : AES-GCM Accelerator
 * Author       : Nguyen Hung Quan and Claude (user)
 * AI Flow      : VLSIT RTL Generator AI Automation Flow
 * AI Flow Page : https://github.com/nguyenquanicd/VLSIT_RTL_Generator_AI_Model
 * Date         : 2026-11-25
 * Description  : GF(2^128) multiplier of GHASH, X * Y of NIST SP 800-38D Algorithm 1.
 *                PARA_MUL_SERIAL = 0: one product per clock, combinational.
 *                PARA_MUL_SERIAL = 1: digit-serial, PARA_DIGIT_W bits of X per clock (FSM ghs).
 *                Bit 127 of a block is the leftmost bit x0 of SP 800-38D (spec section 9.1).
 */
`timescale 1ns/1ps

module m_aesgcm_ghash_mul #(
  // Parameter Description: multiplier structure; 0 = parallel, 1 = digit-serial.
  // Parameter values: 0 or 1; default is 0.
  // Parameter unit: none
  parameter logic [31:0] PARA_MUL_SERIAL = 0,
  // Parameter Description: bits of the operand X consumed per clock when PARA_MUL_SERIAL = 1.
  // Parameter values: 4, 8, 16, 32 or 64; default is 16; unused when PARA_MUL_SERIAL = 0.
  // Parameter unit: bit
  parameter logic [31:0] PARA_DIGIT_W = 16,
  localparam logic [31:0] LPARA_BLK_W = 128,
  localparam logic [31:0] LPARA_DIGIT_NUM = LPARA_BLK_W / PARA_DIGIT_W,
  localparam logic [31:0] LPARA_DCNT_W = (LPARA_DIGIT_NUM > 1) ? $clog2(LPARA_DIGIT_NUM) : 1,
  // Leading byte of the reduction constant R = 11100001 || 0^120 of SP 800-38D 6.3 (PAR-04).
  localparam logic [31:0] LPARA_GF_R_MSB = 32'h0000_00E1
) (
  // Clock and reset (used only by the digit-serial structure)
  input  wire                    i_clk_core,
  input  wire                    i_rst_n_core,

  // Operand request
  input  wire                    i_valid,
  output logic                   o_ready,
  input  wire  [LPARA_BLK_W-1:0] i_x,
  input  wire  [LPARA_BLK_W-1:0] i_y,
  input  wire                    i_abort,

  // Product
  output logic                   o_valid,
  output logic [LPARA_BLK_W-1:0] o_p
);

  // Field multiplication of SP 800-38D Algorithm 1, written as one function because the parallel
  // structure, and the reference behavior of the serial structure, use the same bit order:
  // x0 is bit 127 of i_xv; V is shifted towards bit 0 (the >> 1 of the standard) and reduced by R
  // when the bit that leaves (LSB1, bit 0) is 1.
  function automatic logic [LPARA_BLK_W-1:0] f_gf_mul(
    input logic [LPARA_BLK_W-1:0] i_xv,
    input logic [LPARA_BLK_W-1:0] i_yv
  );
    logic [LPARA_BLK_W-1:0] w_z;
    logic [LPARA_BLK_W-1:0] w_v;
    begin
      w_z = '0;
      w_v = i_yv;
      for (int idx = 0; idx < LPARA_BLK_W; idx++) begin
        if (i_xv[LPARA_BLK_W-1-idx])
          w_z = w_z ^ w_v;
        if (w_v[0])
          w_v = (w_v >> 1) ^ {LPARA_GF_R_MSB[7:0], 120'd0};
        else
          w_v = w_v >> 1;
      end
      f_gf_mul = w_z;
    end
  endfunction

  if (PARA_MUL_SERIAL == 0) begin : gen_parallel
    // Parallel structure: the product is combinational and valid in the same clock as the request.
    assign o_ready = 1'b1;
    assign o_valid = i_valid;
    assign o_p     = f_gf_mul(i_x, i_y);
  end else begin : gen_serial
    // FSM ghs states: IDLE accepts operands, RUN consumes PARA_DIGIT_W bits of X per clock, DONE
    // presents the product for one clock. The unused encoding 2'b11 recovers to IDLE.
    typedef enum logic [1:0] {
      ENUM_ST_GHS_IDLE = 2'b00,
      ENUM_ST_GHS_RUN  = 2'b01,
      ENUM_ST_GHS_DONE = 2'b10
    } ghs_state_type_def;

    ghs_state_type_def       reg_fsm_ghs_current_state;
    ghs_state_type_def       w_fsm_ghs_nxt_state;
    logic [LPARA_BLK_W-1:0]  reg_x;
    logic [LPARA_BLK_W-1:0]  reg_v;
    logic [LPARA_BLK_W-1:0]  reg_z;
    logic [LPARA_DCNT_W-1:0] reg_dcnt;
    logic [LPARA_BLK_W-1:0]  w_x_nxt;
    logic [LPARA_BLK_W-1:0]  w_v_nxt;
    logic [LPARA_BLK_W-1:0]  w_z_nxt;
    logic [LPARA_DCNT_W-1:0] w_dcnt_nxt;
    logic                    w_last_digit;

    // The last digit is processed when the digit counter reaches LPARA_DIGIT_NUM - 1.
    assign w_last_digit = (reg_dcnt == LPARA_DCNT_W'(LPARA_DIGIT_NUM - 1));

    // Part 1, sequential: FSM current state, reset to IDLE.
    always_ff @(posedge i_clk_core, negedge i_rst_n_core) begin : p_ff_fsm_ghs
      if (!i_rst_n_core)
        reg_fsm_ghs_current_state <= ENUM_ST_GHS_IDLE;
      else
        reg_fsm_ghs_current_state <= w_fsm_ghs_nxt_state;
    end

    // Part 2, combinational: IDLE -> RUN on a request, RUN -> DONE after the last digit,
    // DONE -> IDLE after one clock; abort returns to IDLE from any state.
    always_comb begin : p_com_fsm_ghs_nxt
      w_fsm_ghs_nxt_state = reg_fsm_ghs_current_state;
      case (reg_fsm_ghs_current_state)
        ENUM_ST_GHS_IDLE: begin
          if (i_valid)
            w_fsm_ghs_nxt_state = ENUM_ST_GHS_RUN;
        end
        ENUM_ST_GHS_RUN: begin
          if (w_last_digit)
            w_fsm_ghs_nxt_state = ENUM_ST_GHS_DONE;
        end
        ENUM_ST_GHS_DONE: w_fsm_ghs_nxt_state = ENUM_ST_GHS_IDLE;
        default:          w_fsm_ghs_nxt_state = ENUM_ST_GHS_IDLE;
      endcase
      if (i_abort)
        w_fsm_ghs_nxt_state = ENUM_ST_GHS_IDLE;
    end

    // Part 3, combinational: Moore outputs from the current state.
    always_comb begin : p_com_fsm_ghs_out
      o_ready = 1'b0;
      o_valid = 1'b0;
      case (reg_fsm_ghs_current_state)
        ENUM_ST_GHS_IDLE: o_ready = 1'b1;
        ENUM_ST_GHS_DONE: o_valid = 1'b1;
        default:          o_ready = 1'b0;
      endcase
    end

    // Digit step: consume PARA_DIGIT_W bits of X from the left; each bit adds V to Z when it is 1,
    // then V is shifted and reduced exactly as one iteration of Algorithm 1.
    always_comb begin : p_com_digit
      w_x_nxt    = reg_x;
      w_v_nxt    = reg_v;
      w_z_nxt    = reg_z;
      w_dcnt_nxt = reg_dcnt;
      case (reg_fsm_ghs_current_state)
        ENUM_ST_GHS_IDLE: begin
          w_x_nxt    = i_x;
          w_v_nxt    = i_y;
          w_z_nxt    = '0;
          w_dcnt_nxt = '0;
        end
        ENUM_ST_GHS_RUN: begin
          for (int idx = 0; idx < PARA_DIGIT_W; idx++) begin
            if (w_x_nxt[LPARA_BLK_W-1])
              w_z_nxt = w_z_nxt ^ w_v_nxt;
            if (w_v_nxt[0])
              w_v_nxt = (w_v_nxt >> 1) ^ {LPARA_GF_R_MSB[7:0], 120'd0};
            else
              w_v_nxt = w_v_nxt >> 1;
            w_x_nxt = w_x_nxt << 1;
          end
          w_dcnt_nxt = LPARA_DCNT_W'(reg_dcnt + LPARA_DCNT_W'(1));
        end
        default: begin
          w_dcnt_nxt = reg_dcnt;
        end
      endcase
    end

    // Datapath registers; they hold their value outside RUN, and their content is consumed only
    // while the FSM is in DONE, so they need no reset (SEQ-04).
    always_ff @(posedge i_clk_core) begin : p_ff_digit
      reg_x    <= w_x_nxt;
      reg_v    <= w_v_nxt;
      reg_z    <= w_z_nxt;
      reg_dcnt <= w_dcnt_nxt;
    end

    // The product is the accumulated Z, valid while the FSM is in DONE.
    assign o_p = reg_z;
  end

endmodule
