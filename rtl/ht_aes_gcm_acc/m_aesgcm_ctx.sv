/*
 * Project      : AES-GCM Accelerator
 * Author       : Nguyen Hung Quan and Claude (user)
 * AI Flow      : VLSIT RTL Generator AI Automation Flow
 * AI Flow Page : https://github.com/nguyenquanicd/VLSIT_RTL_Generator_AI_Model
 * Date         : 2026-11-25
 * Description  : Context engine (spec 5.3 suspend and resume, 10.1 FSM ctx, MEM-003, OP-007,
 *                OP-008, OP-016). PARA_CTX_MODE = 0: PARA_CTX_NUM internal slots. PARA_CTX_MODE
 *                = 1: one internal buffer whose first LPARA_EXP_WORDS words are exported to and
 *                imported from the CSR window through the word crossing (CDC-007); the key and
 *                the expected tag are never exported. A slot image is 33 words: words 0 to 20
 *                exportable state, words 21 to 28 the key, words 29 to 32 the expected tag.
 *                Save and free write one word per clock (MOVE); a load presents the slot to the
 *                sequencer and counts the same number of clocks. Zeroize clears every slot.
 * Decisions    : DEC-023 (spec section 20).
 */
`timescale 1ns/1ps

module m_aesgcm_ctx #(
  // Parameter Description: context storage; 0 internal slots, 1 export through the CSR.
  // Parameter values: 0 or 1; default is 0.
  // Parameter unit: none
  parameter logic [31:0] PARA_CTX_MODE = 0,
  // Parameter Description: number of internal slots used when PARA_CTX_MODE = 0.
  // Parameter values: 1 to 4; default is 2.
  // Parameter unit: slot
  parameter logic [31:0] PARA_CTX_NUM = 2,
  localparam logic [31:0] LPARA_WORD_W = 32,
  localparam logic [31:0] LPARA_EXP_WORDS = 21,
  localparam logic [31:0] LPARA_SLOT_WORDS = 33,
  localparam logic [31:0] LPARA_SLOT_W = LPARA_SLOT_WORDS * LPARA_WORD_W,
  localparam logic [31:0] LPARA_SLOTS = (PARA_CTX_MODE == 1) ? 1 : PARA_CTX_NUM,
  localparam logic [31:0] LPARA_VLD_W = 4
) (
  // Clock and reset (CORE domain)
  input  wire                     i_clk_core,
  input  wire                     i_rst_n_core,

  // Requests of the sequencer and the bus
  input  wire                     i_zeroize,
  input  wire                     i_sec_only,
  input  wire                     i_save,
  input  wire                     i_load,
  input  wire                     i_free,
  input  wire  [1:0]              i_slot,
  input  wire  [LPARA_SLOT_W-1:0] i_img_live,
  output logic [LPARA_SLOT_W-1:0] o_img,
  output logic                    o_done,
  output logic                    o_idle,
  output logic [LPARA_VLD_W-1:0]  o_vld,

  // Word request from the BUS domain {import, index, word} and word response {index, word}
  input  wire                     i_wreq_valid,
  input  wire                     i_wreq_imp,
  input  wire  [4:0]              i_wreq_idx,
  input  wire  [LPARA_WORD_W-1:0] i_wreq_word,
  input  wire                     i_wrsp_idle,
  output logic                    o_wrsp_send,
  output logic [4:0]              o_wrsp_idx,
  output logic [LPARA_WORD_W-1:0] o_wrsp_word
);

  // FSM ctx states: IDLE wait, DEC decode the request, MOVE slot copy, XFER export or import
  // word, DONE completion pulse.
  typedef enum logic [2:0] {
    ENUM_ST_CTX_IDLE = 3'b000,
    ENUM_ST_CTX_DEC  = 3'b001,
    ENUM_ST_CTX_MOVE = 3'b010,
    ENUM_ST_CTX_XFER = 3'b011,
    ENUM_ST_CTX_DONE = 3'b100
  } ctx_state_type_def;

  // Request kinds latched in IDLE.
  typedef enum logic [2:0] {
    ENUM_CTX_REQ_SAVE = 3'b000,
    ENUM_CTX_REQ_LOAD = 3'b001,
    ENUM_CTX_REQ_FREE = 3'b010,
    ENUM_CTX_REQ_WORD = 3'b011
  } ctx_req_type_def;

  // Internal signal declarations
  ctx_state_type_def                    reg_fsm_ctx_current_state;
  ctx_state_type_def                    w_fsm_ctx_nxt_state;
  ctx_req_type_def                      reg_req;
  logic [1:0]                           reg_sel;
  logic                                 reg_imp;
  logic [4:0]                           reg_widx;
  logic [LPARA_WORD_W-1:0]              reg_wword;
  logic [5:0]                           reg_cnt;
  logic [LPARA_SLOTS-1:0][LPARA_SLOT_W-1:0] reg_slot;
  logic [LPARA_VLD_W-1:0]               reg_vld;
  logic                                 w_word_ok;
  logic                                 w_any_req;
  logic                                 w_last_word;
  logic [LPARA_SLOT_W-1:0]              w_slot_sel;

  // Word requests are served only for the export mode and outside secure-only operation.
  assign w_word_ok   = (PARA_CTX_MODE == 1) & ~i_sec_only & i_wreq_valid;
  assign w_any_req   = i_save | i_load | i_free | w_word_ok;
  assign w_last_word = (reg_cnt == 6'(LPARA_SLOT_WORDS - 1));

  // Slot selected by the latched slot number.
  always_comb begin : p_com_slot_sel
    w_slot_sel = reg_slot[0];
    for (int idx = 0; idx < LPARA_SLOTS; idx++) begin
      if (reg_sel == 2'(idx))
        w_slot_sel = reg_slot[idx];
    end
  end

  // Outputs: the selected slot image, the valid mask and the word response.
  assign o_img       = w_slot_sel;
  assign o_vld       = reg_vld;
  assign o_wrsp_idx  = reg_widx;
  assign o_wrsp_word = w_slot_sel[LPARA_WORD_W*reg_widx +: LPARA_WORD_W];

  // Part 1, sequential: FSM current state, reset to IDLE.
  always_ff @(posedge i_clk_core, negedge i_rst_n_core) begin : p_ff_fsm_ctx
    if (!i_rst_n_core)
      reg_fsm_ctx_current_state <= ENUM_ST_CTX_IDLE;
    else
      reg_fsm_ctx_current_state <= w_fsm_ctx_nxt_state;
  end

  // Part 2, combinational: IDLE -> DEC on a request; DEC -> MOVE for save, load and free,
  // DEC -> XFER for a word; MOVE -> DONE after the last word; XFER -> DONE when the word is
  // written (import) or handed to the response crossing (export); DONE -> IDLE. Zeroize forces
  // IDLE (global override G1); an invalid encoding returns to IDLE.
  always_comb begin : p_com_fsm_ctx_nxt
    w_fsm_ctx_nxt_state = reg_fsm_ctx_current_state;
    case (reg_fsm_ctx_current_state)
      ENUM_ST_CTX_IDLE: begin
        if (w_any_req)
          w_fsm_ctx_nxt_state = ENUM_ST_CTX_DEC;
      end
      ENUM_ST_CTX_DEC: begin
        if (reg_req == ENUM_CTX_REQ_WORD)
          w_fsm_ctx_nxt_state = ENUM_ST_CTX_XFER;
        else
          w_fsm_ctx_nxt_state = ENUM_ST_CTX_MOVE;
      end
      ENUM_ST_CTX_MOVE: begin
        if (w_last_word)
          w_fsm_ctx_nxt_state = ENUM_ST_CTX_DONE;
      end
      ENUM_ST_CTX_XFER: begin
        if (reg_imp || i_wrsp_idle)
          w_fsm_ctx_nxt_state = ENUM_ST_CTX_DONE;
      end
      ENUM_ST_CTX_DONE: w_fsm_ctx_nxt_state = ENUM_ST_CTX_IDLE;
      default:          w_fsm_ctx_nxt_state = ENUM_ST_CTX_IDLE;
    endcase
    if (i_zeroize)
      w_fsm_ctx_nxt_state = ENUM_ST_CTX_IDLE;
  end

  // Part 3, combinational: Moore outputs.
  always_comb begin : p_com_fsm_ctx_out
    o_done      = 1'b0;
    o_idle      = 1'b0;
    o_wrsp_send = 1'b0;
    case (reg_fsm_ctx_current_state)
      ENUM_ST_CTX_IDLE: o_idle      = 1'b1;
      ENUM_ST_CTX_XFER: o_wrsp_send = ~reg_imp & i_wrsp_idle;
      ENUM_ST_CTX_DONE: o_done      = (reg_req != ENUM_CTX_REQ_WORD);
      default:          o_idle      = 1'b0;
    endcase
  end

  // Request latch in IDLE: sequencer requests have priority over the word request.
  always_ff @(posedge i_clk_core, negedge i_rst_n_core) begin : p_ff_req
    if (!i_rst_n_core) begin
      reg_req   <= ENUM_CTX_REQ_SAVE;
      reg_sel   <= '0;
      reg_imp   <= 1'b0;
      reg_widx  <= '0;
      reg_wword <= '0;
    end else if ((reg_fsm_ctx_current_state == ENUM_ST_CTX_IDLE) && w_any_req) begin
      casez ({i_save, i_load, i_free})
        3'b1??:  reg_req <= ENUM_CTX_REQ_SAVE;
        3'b01?:  reg_req <= ENUM_CTX_REQ_LOAD;
        3'b001:  reg_req <= ENUM_CTX_REQ_FREE;
        default: reg_req <= ENUM_CTX_REQ_WORD;
      endcase
      reg_sel   <= (PARA_CTX_MODE == 1) ? 2'd0 : i_slot;
      reg_imp   <= i_wreq_imp;
      reg_widx  <= i_wreq_idx;
      reg_wword <= i_wreq_word;
    end
  end

  // Word counter of MOVE.
  always_ff @(posedge i_clk_core, negedge i_rst_n_core) begin : p_ff_cnt
    if (!i_rst_n_core)
      reg_cnt <= '0;
    else if (reg_fsm_ctx_current_state == ENUM_ST_CTX_MOVE)
      reg_cnt <= reg_cnt + 6'd1;
    else
      reg_cnt <= '0;
  end

  // Slot storage and valid flags. Save copies the live image word by word, free writes zeros,
  // import writes one exportable word; the valid flag is set by a save or by the import of the
  // last exportable word, and cleared by a load (the slot is consumed) or a free.
  always_ff @(posedge i_clk_core, negedge i_rst_n_core) begin : p_ff_slot
    if (!i_rst_n_core) begin
      reg_slot <= '0;
      reg_vld  <= '0;
    end else if (i_zeroize) begin
      reg_slot <= '0;
      reg_vld  <= '0;
    end else begin
      case (reg_fsm_ctx_current_state)
        ENUM_ST_CTX_MOVE: begin
          for (int idx = 0; idx < LPARA_SLOTS; idx++) begin
            if (reg_sel == 2'(idx)) begin
              if (reg_req == ENUM_CTX_REQ_SAVE)
                reg_slot[idx][LPARA_WORD_W*reg_cnt +: LPARA_WORD_W] <=
                  i_img_live[LPARA_WORD_W*reg_cnt +: LPARA_WORD_W];
              if (reg_req == ENUM_CTX_REQ_FREE)
                reg_slot[idx][LPARA_WORD_W*reg_cnt +: LPARA_WORD_W] <= '0;
            end
          end
        end
        ENUM_ST_CTX_XFER: begin
          if (reg_imp && (reg_widx < 5'(LPARA_EXP_WORDS))) begin
            reg_slot[0][LPARA_WORD_W*reg_widx +: LPARA_WORD_W] <= reg_wword;
            if (reg_widx == 5'(LPARA_EXP_WORDS - 1))
              reg_vld[0] <= 1'b1;
          end
        end
        ENUM_ST_CTX_DONE: begin
          for (int idx = 0; idx < LPARA_SLOTS; idx++) begin
            if (reg_sel == 2'(idx)) begin
              if (reg_req == ENUM_CTX_REQ_SAVE)
                reg_vld[idx] <= 1'b1;
              if ((reg_req == ENUM_CTX_REQ_LOAD) || (reg_req == ENUM_CTX_REQ_FREE))
                reg_vld[idx] <= 1'b0;
            end
          end
        end
        default: begin
          reg_vld <= reg_vld;
        end
      endcase
    end
  end

endmodule
