/*
 * Project      : AES-GCM Accelerator
 * Author       : Nguyen Hung Quan and Claude (user)
 * AI Flow      : VLSIT RTL Generator AI Automation Flow
 * AI Flow Page : https://github.com/nguyenquanicd/VLSIT_RTL_Generator_AI_Model
 * Date         : 2026-11-25
 * Description  : Four-phase DMA request channel, FSM hsk of spec 10.1 (IDLE, REQ, REL) and the
 *                protocol of spec 6.3.4: the request rises when the channel condition holds, is
 *                held until the acknowledge, falls on the acknowledge, and the condition is not
 *                evaluated again before the acknowledge has fallen. Instance 0 is the input
 *                channel, instance 1 the output channel.
 */
`timescale 1ns/1ps

module m_aesgcm_dma_ch (
  // Clock and reset (BUS domain)
  input  wire  i_clk_bus,
  input  wire  i_rst_n_bus,

  // Channel condition (enable included)
  input  wire  i_cond,

  // Four-phase handshake (IF-003)
  output logic o_req,
  input  wire  i_ack
);

  // FSM hsk states.
  typedef enum logic [1:0] {
    ENUM_ST_HSK_IDLE = 2'b00,
    ENUM_ST_HSK_REQ  = 2'b01,
    ENUM_ST_HSK_REL  = 2'b10
  } hsk_state_type_def;

  // Internal signal declarations
  hsk_state_type_def reg_fsm_hsk_current_state;
  hsk_state_type_def w_fsm_hsk_nxt_state;
  logic              reg_req;

  // Part 1, sequential: current state, reset to IDLE.
  always_ff @(posedge i_clk_bus, negedge i_rst_n_bus) begin : p_ff_fsm_hsk
    if (!i_rst_n_bus)
      reg_fsm_hsk_current_state <= ENUM_ST_HSK_IDLE;
    else
      reg_fsm_hsk_current_state <= w_fsm_hsk_nxt_state;
  end

  // Part 2, combinational: IDLE -> REQ on the condition (acknowledge low), REQ -> REL on the
  // acknowledge, REL -> IDLE when the acknowledge falls; an invalid encoding returns to IDLE.
  always_comb begin : p_com_fsm_hsk_nxt
    w_fsm_hsk_nxt_state = reg_fsm_hsk_current_state;
    case (reg_fsm_hsk_current_state)
      ENUM_ST_HSK_IDLE: begin
        if (i_cond && !i_ack)
          w_fsm_hsk_nxt_state = ENUM_ST_HSK_REQ;
      end
      ENUM_ST_HSK_REQ: begin
        if (i_ack)
          w_fsm_hsk_nxt_state = ENUM_ST_HSK_REL;
      end
      ENUM_ST_HSK_REL: begin
        if (!i_ack)
          w_fsm_hsk_nxt_state = ENUM_ST_HSK_IDLE;
      end
      default: w_fsm_hsk_nxt_state = ENUM_ST_HSK_IDLE;
    endcase
  end

  // Part 3: registered Moore output, request is 1 exactly in REQ (registered output port).
  always_ff @(posedge i_clk_bus, negedge i_rst_n_bus) begin : p_ff_req
    if (!i_rst_n_bus)
      reg_req <= 1'b0;
    else
      reg_req <= (w_fsm_hsk_nxt_state == ENUM_ST_HSK_REQ);
  end

  // Request output.
  assign o_req = reg_req;

endmodule
