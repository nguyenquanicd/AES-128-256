/*
 * Project      : AES-GCM Accelerator
 * Author       : Nguyen Hung Quan and Claude (user)
 * AI Flow      : VLSIT RTL Generator AI Automation Flow
 * AI Flow Page : https://github.com/nguyenquanicd/VLSIT_RTL_Generator_AI_Model
 * Date         : 2026-11-25
 * Description  : Four-phase bundle crossing (spec 7.2, CDC-001, CDC-002, CDC-005, CDC-007).
 *                Source half: holding register and FSM hsk (IDLE, REQ, REL); the bundle is stable
 *                from the request until the acknowledge and is cleared after it. Destination
 *                half: FSM hsr (IDLE, CAP, ACK); the bundle is captured in CAP, o_valid pulses
 *                for one clock and the captured copy is held until the next capture or until
 *                i_dst_clr (the consumer clears key material after use).
 *                The request and acknowledge cross in m_aesgcm_hs_xing.
 * Decisions    : DEC-016, DEC-022, DEC-024 (spec section 20).
 */
`timescale 1ns/1ps

module m_aesgcm_xing_bdl #(
  // Parameter Description: width of the bundle.
  // Parameter values: 1 or more; default is 32.
  // Parameter unit: bit
  parameter logic [31:0] PARA_DATA_W = 32,
  // Parameter Description: crossing structure; 1 = asynchronous clocks, 0 = related clocks.
  // Parameter values: 0 or 1; default is 1.
  // Parameter unit: none
  parameter logic [31:0] PARA_CLK_ASYNC = 1
) (
  // Source clock and reset
  input  wire                    i_clk_src,
  input  wire                    i_rst_n_src,

  // Source bundle interface
  input  wire                    i_send,
  input  wire  [PARA_DATA_W-1:0] i_data,
  input  wire                    i_clr,
  output logic                   o_idle,
  output logic                   o_done,

  // Destination clock and reset
  input  wire                    i_clk_dst,
  input  wire                    i_rst_n_dst,

  // Destination bundle interface
  input  wire                    i_dst_clr,
  output logic                   o_valid,
  output logic [PARA_DATA_W-1:0] o_data
);

  // FSM hsk states (requester): IDLE no request, REQ phases 1 and 2, REL phases 3 and 4.
  typedef enum logic [1:0] {
    ENUM_ST_HSK_IDLE = 2'b00,
    ENUM_ST_HSK_REQ  = 2'b01,
    ENUM_ST_HSK_REL  = 2'b10
  } hsk_state_type_def;

  // FSM hsr states (responder): IDLE wait, CAP capture, ACK acknowledge until release.
  typedef enum logic [1:0] {
    ENUM_ST_HSR_IDLE = 2'b00,
    ENUM_ST_HSR_CAP  = 2'b01,
    ENUM_ST_HSR_ACK  = 2'b10
  } hsr_state_type_def;

  // Internal signal declarations
  hsk_state_type_def      reg_fsm_hsk_current_state;
  hsk_state_type_def      w_fsm_hsk_nxt_state;
  hsr_state_type_def      reg_fsm_hsr_current_state;
  hsr_state_type_def      w_fsm_hsr_nxt_state;
  logic [PARA_DATA_W-1:0] reg_hold;
  logic [PARA_DATA_W-1:0] reg_cap;
  logic                   w_src_req;
  logic                   w_src_ack;
  logic                   w_dst_req;
  logic                   w_dst_ack;

  // ---------------------------------------------------------------- source half (FSM hsk)

  // Part 1, sequential: current state, reset to IDLE.
  always_ff @(posedge i_clk_src, negedge i_rst_n_src) begin : p_ff_fsm_hsk
    if (!i_rst_n_src)
      reg_fsm_hsk_current_state <= ENUM_ST_HSK_IDLE;
    else
      reg_fsm_hsk_current_state <= w_fsm_hsk_nxt_state;
  end

  // Part 2, combinational: IDLE -> REQ on a bundle to send, REQ -> REL on the acknowledge,
  // REL -> IDLE when the acknowledge has fallen; an invalid encoding returns to IDLE.
  always_comb begin : p_com_fsm_hsk_nxt
    w_fsm_hsk_nxt_state = reg_fsm_hsk_current_state;
    case (reg_fsm_hsk_current_state)
      ENUM_ST_HSK_IDLE: begin
        if (i_send)
          w_fsm_hsk_nxt_state = ENUM_ST_HSK_REQ;
      end
      ENUM_ST_HSK_REQ: begin
        if (w_src_ack)
          w_fsm_hsk_nxt_state = ENUM_ST_HSK_REL;
      end
      ENUM_ST_HSK_REL: begin
        if (!w_src_ack)
          w_fsm_hsk_nxt_state = ENUM_ST_HSK_IDLE;
      end
      default: w_fsm_hsk_nxt_state = ENUM_ST_HSK_IDLE;
    endcase
  end

  // Part 3, combinational: Moore outputs of FSM hsk.
  always_comb begin : p_com_fsm_hsk_out
    w_src_req = 1'b0;
    o_idle    = 1'b0;
    case (reg_fsm_hsk_current_state)
      ENUM_ST_HSK_IDLE: o_idle    = 1'b1;
      ENUM_ST_HSK_REQ:  w_src_req = 1'b1;
      default:          w_src_req = 1'b0;
    endcase
  end

  // Completion pulse: the acknowledge of the launched bundle has been seen.
  assign o_done = (reg_fsm_hsk_current_state == ENUM_ST_HSK_REQ) & w_src_ack;

  // Holding register: loaded at launch, cleared after the acknowledge and by i_clr while idle,
  // so that a key word never stays in it longer than one transfer.
  always_ff @(posedge i_clk_src, negedge i_rst_n_src) begin : p_ff_hold
    if (!i_rst_n_src)
      reg_hold <= '0;
    else if ((reg_fsm_hsk_current_state == ENUM_ST_HSK_IDLE) && i_send)
      reg_hold <= i_data;
    else if (o_done || ((reg_fsm_hsk_current_state == ENUM_ST_HSK_IDLE) && i_clr))
      reg_hold <= '0;
  end

  // ------------------------------------------------------------ destination half (FSM hsr)

  // Part 1, sequential: current state, reset to IDLE.
  always_ff @(posedge i_clk_dst, negedge i_rst_n_dst) begin : p_ff_fsm_hsr
    if (!i_rst_n_dst)
      reg_fsm_hsr_current_state <= ENUM_ST_HSR_IDLE;
    else
      reg_fsm_hsr_current_state <= w_fsm_hsr_nxt_state;
  end

  // Part 2, combinational: IDLE -> CAP on the request, CAP -> ACK after one clock,
  // ACK -> IDLE when the request has fallen; an invalid encoding returns to IDLE.
  always_comb begin : p_com_fsm_hsr_nxt
    w_fsm_hsr_nxt_state = reg_fsm_hsr_current_state;
    case (reg_fsm_hsr_current_state)
      ENUM_ST_HSR_IDLE: begin
        if (w_dst_req)
          w_fsm_hsr_nxt_state = ENUM_ST_HSR_CAP;
      end
      ENUM_ST_HSR_CAP: w_fsm_hsr_nxt_state = ENUM_ST_HSR_ACK;
      ENUM_ST_HSR_ACK: begin
        if (!w_dst_req)
          w_fsm_hsr_nxt_state = ENUM_ST_HSR_IDLE;
      end
      default: w_fsm_hsr_nxt_state = ENUM_ST_HSR_IDLE;
    endcase
  end

  // Part 3, combinational: Moore outputs of FSM hsr.
  always_comb begin : p_com_fsm_hsr_out
    w_dst_ack = 1'b0;
    o_valid   = 1'b0;
    case (reg_fsm_hsr_current_state)
      ENUM_ST_HSR_CAP: o_valid   = 1'b1;
      ENUM_ST_HSR_ACK: w_dst_ack = 1'b1;
      default:         w_dst_ack = 1'b0;
    endcase
  end

  // Capture register: the bundle is stable while the request is high, so it is sampled on the
  // clock that enters CAP; the copy is valid from CAP until the next capture.
  always_ff @(posedge i_clk_dst, negedge i_rst_n_dst) begin : p_ff_cap
    if (!i_rst_n_dst)
      reg_cap <= '0;
    else if ((reg_fsm_hsr_current_state == ENUM_ST_HSR_IDLE) && w_dst_req)
      reg_cap <= reg_hold;
    else if (i_dst_clr)
      reg_cap <= '0;
  end

  // Captured bundle output.
  assign o_data = reg_cap;

  // Request and acknowledge crossing.
  m_aesgcm_hs_xing #(
    .PARA_CLK_ASYNC (PARA_CLK_ASYNC)
  ) u_hs_xing (
    .i_clk_src   (i_clk_src),
    .i_rst_n_src (i_rst_n_src),
    .i_req       (w_src_req),
    .o_ack       (w_src_ack),
    .i_clk_dst   (i_clk_dst),
    .i_rst_n_dst (i_rst_n_dst),
    .o_req       (w_dst_req),
    .i_ack       (w_dst_ack)
  );

endmodule
