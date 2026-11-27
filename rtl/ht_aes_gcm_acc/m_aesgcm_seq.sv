/*
 * Project      : AES-GCM Accelerator
 * Author       : Nguyen Hung Quan and Claude (user)
 * AI Flow      : VLSIT RTL Generator AI Automation Flow
 * AI Flow Page : https://github.com/nguyenquanicd/VLSIT_RTL_Generator_AI_Model
 * Date         : 2026-11-25
 * Description  : Message sequencer, FSM seq of spec 10.1 (states IDLE to ABRT, global overrides
 *                G1 and G2), dataflow of spec 5.3 and the operations OP-001 to OP-011. It drives
 *                the AES core (ECB setup message {0^128, J0}, then the CTR payload message from
 *                inc32(J0), or a legacy message), the GHASH unit, the tag compare, the context
 *                engine and the status report (CDC-002). Status reports are sent whenever a
 *                reported value changes and the crossing is idle; FIN waits until its own report
 *                has been accepted.
 *                Configuration bundle (CDC-001), MSB first: op 1, mode 3, decipher 1, key_size 1,
 *                key_src 1, key_new 1, gcm_pass 2, tag_len 3, cfb_seg 4, ctx_id 2, keywait 16,
 *                aad_len 32, data_len 32, iv 128, tag_exp 128, key 256 (611 bits).
 *                Command bundle (CDC-005): abort, zeroize, suspend, free, ctx_id (6 bits).
 *                Status bundle (CDC-002), MSB first: msg_end, suspended, resumed, cmd_ack,
 *                tag_ok, ver_ok, zeroized, key_ld, events 10, err_code 4, err_core 4, phase 4,
 *                ctx_vld 4, failcnt 32, cons_a 32, cons_d 32, rem_a 32, rem_d 32, tag 128 (322).
 * Decisions    : DEC-015, DEC-022, DEC-023, DEC-024, DEC-030, DEC-034 (spec section 20).
 */
`timescale 1ns/1ps

module m_aesgcm_seq #(
  // Parameter Description: number of 128-bit AES block lanes of the AES core.
  // Parameter values: 1 to 4; default is 1.
  // Parameter unit: lane
  parameter logic [31:0] PARA_LANE_NUM = 1,
  // Parameter Description: 1 enables the GCM mode code 5; 0 keeps only the legacy modes.
  // Parameter values: 0 or 1; default is 1.
  // Parameter unit: none
  parameter logic [31:0] PARA_AES_GCM_EN = 1,
  // Parameter Description: 1 when suspend and resume are built (context slots or export).
  // Parameter values: 0 or 1; default is 1.
  // Parameter unit: none
  parameter logic [31:0] PARA_CTX_EN = 1,
  // Parameter Description: context storage; 0 internal slots, 1 export through the CSR.
  // Parameter values: 0 or 1; default is 0.
  // Parameter unit: none
  parameter logic [31:0] PARA_CTX_MODE = 0,
  localparam logic [31:0] LPARA_BLK_W = 128,
  localparam logic [31:0] LPARA_KEY_W = 256,
  localparam logic [31:0] LPARA_DATA_W = PARA_LANE_NUM * LPARA_BLK_W,
  localparam logic [31:0] LPARA_CFG_W = 611,
  localparam logic [31:0] LPARA_CMD_W = 6,
  localparam logic [31:0] LPARA_STS_W = 322,
  localparam logic [31:0] LPARA_SLOT_W = 1056,
  localparam logic [31:0] LPARA_EVT_W = 10,
  localparam logic [31:0] LPARA_IV_W = 96,
  localparam logic [31:0] LPARA_CTR_W = 32,
  localparam logic [31:0] LPARA_BLK_BYTES = 16,
  localparam logic [31:0] LPARA_CORE_ERR_CTR = 3,
  localparam logic [31:0] LPARA_OUTST_W = 6,
  // Event bit positions of the status report (spec 6.4, 9.3).
  localparam logic [31:0] LPARA_EVT_DONE = 0,
  localparam logic [31:0] LPARA_EVT_TAGF = 1,
  localparam logic [31:0] LPARA_EVT_LERR = 3,
  localparam logic [31:0] LPARA_EVT_CEXH = 4,
  localparam logic [31:0] LPARA_EVT_CSWD = 7,
  localparam logic [31:0] LPARA_EVT_KERR = 8,
  localparam logic [31:0] LPARA_EVT_PERR = 9
) (
  // Clock and reset (CORE domain)
  input  wire                      i_clk_core,
  input  wire                      i_rst_n_core,

  // Configuration bundle and commands from the BUS domain
  input  wire                      i_cfg_valid,
  input  wire  [LPARA_CFG_W-1:0]   i_cfg,
  output logic                     o_cfg_clr,
  input  wire                      i_cmd_valid,
  input  wire  [LPARA_CMD_W-1:0]   i_cmd,

  // Key store
  output logic                     o_key_zeroize,
  output logic                     o_key_load,
  output logic                     o_key_src,
  output logic                     o_key_restore,
  output logic [LPARA_KEY_W-1:0]   o_key_ctx,
  input  wire  [LPARA_KEY_W-1:0]   i_key,
  input  wire                      i_key_ready,
  input  wire                      i_key_err,
  input  wire                      i_key_ld,

  // AES core configuration
  output logic                     o_aes_cfg_valid,
  input  wire                      i_aes_cfg_ready,
  output logic                     o_aes_cfg_key_size,
  output logic [2:0]               o_aes_cfg_mode,
  output logic                     o_aes_cfg_decipher,
  output logic [LPARA_BLK_W-1:0]   o_aes_cfg_iv,
  output logic [3:0]               o_aes_cfg_cfb,

  // AES core input batch
  output logic                     o_aes_in_valid,
  input  wire                      i_aes_in_ready,
  output logic [LPARA_DATA_W-1:0]  o_aes_in_data,
  output logic [PARA_LANE_NUM-1:0] o_aes_in_lane,
  output logic                     o_aes_in_last,

  // AES core output batch, error and zeroize
  input  wire                      i_aes_out_valid,
  output logic                     o_aes_out_ready,
  input  wire  [LPARA_DATA_W-1:0]  i_aes_out_data,
  input  wire  [PARA_LANE_NUM-1:0] i_aes_out_lane,
  input  wire                      i_aes_err_valid,
  input  wire  [3:0]               i_aes_err_code,
  output logic                     o_aes_zeroize,
  input  wire                      i_aes_zeroize_done,

  // Input FIFO entry (decoded by m_aesgcm_fmt_in)
  input  wire                      i_in_empty,
  output logic                     o_in_rd_en,
  output logic                     o_fin_seg,
  output logic [31:0]              o_fin_rem,
  output logic [4:0]               o_bpb,
  input  wire  [LPARA_DATA_W-1:0]  i_fin_data,
  input  wire  [PARA_LANE_NUM-1:0] i_fin_mask,
  input  wire  [2:0]               i_fin_cnt,
  input  wire  [31:0]              i_fin_bytes,
  input  wire                      i_fin_seg_err,

  // Output formatter and output FIFO
  output logic [31:0]              o_fout_rem,
  input  wire  [LPARA_DATA_W-1:0]  i_fout_data,
  input  wire  [31:0]              i_fout_bytes,
  input  wire                      i_out_full,
  output logic                     o_out_wr_en,
  output logic                     o_out_flush,
  input  wire                      i_out_flush_busy,

  // GHASH unit
  output logic                     o_gh_zeroize,
  output logic                     o_gh_clr,
  output logic                     o_gh_load_y,
  output logic [LPARA_BLK_W-1:0]   o_gh_y,
  output logic [LPARA_BLK_W-1:0]   o_gh_h,
  output logic                     o_gh_pow_start,
  input  wire                      i_gh_pow_done,
  output logic                     o_gh_valid,
  input  wire                      i_gh_ready,
  output logic [LPARA_DATA_W-1:0]  o_gh_data,
  output logic [PARA_LANE_NUM-1:0] o_gh_mask,
  input  wire  [LPARA_BLK_W-1:0]   i_gh_y,
  input  wire                      i_gh_idle,

  // Tag unit
  output logic [LPARA_BLK_W-1:0]   o_tag_ej0,
  output logic [2:0]               o_tag_len,
  output logic [LPARA_BLK_W-1:0]   o_tag_exp,
  input  wire  [LPARA_BLK_W-1:0]   i_tag,
  input  wire                      i_tag_match,

  // Context engine
  output logic                     o_ctx_zeroize,
  output logic                     o_ctx_save,
  output logic                     o_ctx_load,
  output logic                     o_ctx_free,
  output logic [1:0]               o_ctx_slot,
  output logic [LPARA_SLOT_W-1:0]  o_ctx_img,
  input  wire  [LPARA_SLOT_W-1:0]  i_ctx_img,
  input  wire                      i_ctx_done,
  input  wire  [3:0]               i_ctx_vld,

  // Status report to the BUS domain
  output logic                     o_sts_send,
  output logic [LPARA_STS_W-1:0]   o_sts,
  input  wire                      i_sts_idle
);

  // FSM seq states; the encoding is the phase code of aesgcm_sts.phase (0xE aborting).
  typedef enum logic [3:0] {
    ENUM_ST_SEQ_IDLE   = 4'h0,
    ENUM_ST_SEQ_KEY    = 4'h1,
    ENUM_ST_SEQ_SU_CFG = 4'h2,
    ENUM_ST_SEQ_SU_RUN = 4'h3,
    ENUM_ST_SEQ_POW    = 4'h4,
    ENUM_ST_SEQ_AAD    = 4'h5,
    ENUM_ST_SEQ_PY_CFG = 4'h6,
    ENUM_ST_SEQ_PAY    = 4'h7,
    ENUM_ST_SEQ_LEN    = 4'h8,
    ENUM_ST_SEQ_TAG    = 4'h9,
    ENUM_ST_SEQ_FIN    = 4'hA,
    ENUM_ST_SEQ_SUSP   = 4'hB,
    ENUM_ST_SEQ_REST   = 4'hC,
    ENUM_ST_SEQ_ABRT   = 4'hE
  } seq_state_type_def;

  // AES-core and accelerator mode codes (REF-008, spec 9.3).
  typedef enum logic [2:0] {
    ENUM_MODE_ECB = 3'd0,
    ENUM_MODE_CBC = 3'd1,
    ENUM_MODE_CFB = 3'd2,
    ENUM_MODE_OFB = 3'd3,
    ENUM_MODE_CTR = 3'd4,
    ENUM_MODE_GCM = 3'd5
  } mode_type_def;

  // Error codes of aesgcm_err_code.code (spec 9.3).
  typedef enum logic [3:0] {
    ENUM_ERR_NONE  = 4'd0,
    ENUM_ERR_LEN   = 4'd2,
    ENUM_ERR_CTR   = 4'd3,
    ENUM_ERR_KEY   = 4'd4,
    ENUM_ERR_PROTO = 4'd5,
    ENUM_ERR_TAG   = 4'd6,
    ENUM_ERR_CORE  = 4'd7
  } err_type_def;


  // Internal signal declarations
  seq_state_type_def        reg_fsm_seq_current_state;
  seq_state_type_def        w_fsm_seq_nxt_state;
  logic                     w_st_chg;
  // Message configuration latched from the bundle
  mode_type_def             reg_mode;
  logic                     reg_dec;
  logic                     reg_ksize;
  logic                     reg_ksrc;
  logic [1:0]               reg_pass;
  logic [2:0]               reg_tlen;
  logic [3:0]               reg_cfb;
  logic [1:0]               reg_slot;
  logic [LPARA_BLK_W-1:0]   reg_iv;
  logic [LPARA_BLK_W-1:0]   reg_tag_exp;
  logic                     reg_cfg_clr;
  // GCM state
  logic [LPARA_BLK_W-1:0]   reg_h;
  logic [LPARA_BLK_W-1:0]   reg_ej0;
  logic [LPARA_BLK_W-1:0]   reg_y_aad;
  logic                     reg_vc_valid;
  logic                     reg_ver_ok;
  logic                     reg_tag_ok;
  logic [LPARA_BLK_W-1:0]   reg_tag;
  // Counters
  logic [31:0]              reg_aad_rem;
  logic [31:0]              reg_dat_rem;
  logic [31:0]              reg_out_rem;
  logic [31:0]              reg_aad_tot;
  logic [31:0]              reg_dat_tot;
  logic [LPARA_CTR_W-1:0]   reg_ctr;
  logic [LPARA_OUTST_W-1:0] reg_outst;
  logic [1:0]               reg_su_sent;
  logic [1:0]               reg_su_rcv;
  logic                     reg_first;
  logic                     reg_len_sent;
  logic                     reg_zdone;
  // Commands, errors and report
  logic                     reg_abort_p;
  logic                     reg_zero_p;
  logic                     reg_susp_p;
  logic                     reg_zero_act;
  logic                     reg_fatal;
  logic [LPARA_EVT_W-1:0]   reg_evt;
  err_type_def              reg_err_code;
  logic [3:0]               reg_err_core;
  logic [31:0]              reg_failcnt;
  logic                     reg_zeroized;
  logic                     reg_msg_end;
  logic                     reg_suspended;
  logic                     reg_resumed;
  logic                     reg_cmd_ack;
  logic                     reg_cmd_seen;
  logic                     reg_dirty;
  // Combinational controls
  logic                     w_gcm;
  logic                     w_feed_pass1;
  logic                     w_aes_pay;
  logic                     w_enc_gh;
  logic                     w_dec_gh;
  logic                     w_stop;
  logic                     w_g1;
  logic                     w_g2;
  logic                     w_drained;
  logic                     w_in_fire;
  logic                     w_out_fire;
  logic                     w_gh_fire;
  logic                     w_su_in_fire;
  logic                     w_su_out_fire;
  logic                     w_aad_take;
  logic                     w_p1_take;
  logic                     w_pay_send;
  logic                     w_pay_done;
  logic                     w_key_go;
  logic                     w_new_evt_any;
  logic [LPARA_EVT_W-1:0]   w_evt_new;
  err_type_def              w_err_new;
  logic [3:0]               w_err_core_new;
  logic                     w_fatal_new;
  logic                     w_cmd_abort;
  logic                     w_cmd_zero;
  logic                     w_cmd_susp;
  logic [LPARA_BLK_W-1:0]   w_j0;
  logic [LPARA_BLK_W-1:0]   w_len_blk;
  logic [LPARA_SLOT_W-1:0]  w_img;
  logic [31:0]              w_flags;
  logic [4:0]               w_bpb;
  logic                     w_idle_zero;
  logic                     w_slot_vld;
  logic                     w_idle_cmd;
  // Fields of the configuration bundle
  logic                     w_b_op;
  logic [2:0]               w_b_mode;
  logic                     w_b_dec;
  logic                     w_b_ksize;
  logic                     w_b_ksrc;
  logic                     w_b_knew;
  logic [1:0]               w_b_pass;
  logic [2:0]               w_b_tlen;
  logic [3:0]               w_b_cfb;
  logic [1:0]               w_b_slot;
  logic [31:0]              w_b_aad;
  logic [31:0]              w_b_dat;
  logic [LPARA_BLK_W-1:0]   w_b_iv;
  logic [LPARA_BLK_W-1:0]   w_b_tag;

  // ------------------------------------------------------------------- bundle field decode

  // Fields of the configuration bundle (the key and the key wait go to the key store).
  assign {w_b_op, w_b_mode, w_b_dec, w_b_ksize, w_b_ksrc, w_b_knew, w_b_pass, w_b_tlen,
          w_b_cfb, w_b_slot} = i_cfg[LPARA_CFG_W-1 -: 19];
  assign w_b_aad = i_cfg[LPARA_KEY_W + 2*LPARA_BLK_W + 32 +: 32];
  assign w_b_dat = i_cfg[LPARA_KEY_W + 2*LPARA_BLK_W +: 32];
  assign w_b_iv  = i_cfg[LPARA_KEY_W + LPARA_BLK_W +: LPARA_BLK_W];
  assign w_b_tag = i_cfg[LPARA_KEY_W +: LPARA_BLK_W];

  // Command bundle: {abort, zeroize, suspend, free, ctx_id}.
  assign w_cmd_abort = i_cmd_valid & i_cmd[5];
  assign w_cmd_zero  = i_cmd_valid & i_cmd[4];
  assign w_cmd_susp  = i_cmd_valid & i_cmd[3];
  assign o_ctx_free  = i_cmd_valid & i_cmd[2] & (PARA_CTX_EN == 1);

  // ------------------------------------------------------------------- derived values

  // GCM message, bytes per block (CFB segment bytes, at least one byte), J0 and length block.
  assign w_gcm     = (reg_mode == ENUM_MODE_GCM) & (PARA_AES_GCM_EN == 1);
  assign w_j0      = {reg_iv[LPARA_BLK_W-1 -: LPARA_IV_W], LPARA_CTR_W'(1)};
  assign w_len_blk = {29'd0, reg_aad_tot, 3'd0, 29'd0, reg_dat_tot, 3'd0};

  always_comb begin : p_com_bpb
    w_bpb = 5'(LPARA_BLK_BYTES);
    if ((reg_mode == ENUM_MODE_CFB) && (reg_cfb < 4'd4))
      w_bpb = 5'd1;
    else if (reg_mode == ENUM_MODE_CFB)
      w_bpb = 5'd1 << (reg_cfb - 4'd3);
  end

  assign o_bpb = w_bpb;

  // Data paths of the payload phase: pass 1 hashes the ciphertext only; the other passes and
  // the legacy modes use the AES core; GHASH takes the core output when encrypting and the core
  // input when decrypting.
  assign w_feed_pass1 = w_gcm & (reg_pass == 2'd1);
  assign w_aes_pay    = ~w_feed_pass1;
  assign w_enc_gh     = w_gcm & ~reg_dec;
  assign w_dec_gh     = w_gcm & reg_dec & ~w_feed_pass1;

  // Context image, word 0 first: Y, H, E(K,J0), IV (96), counter, AAD remainder, payload
  // remainder, AAD total, payload total, flags, key (8 words), expected tag (4 words).
  assign w_flags = {25'd0, reg_dec, reg_pass, reg_tlen, reg_ksize};
  assign w_img   = {reg_tag_exp, i_key, w_flags, reg_dat_tot, reg_aad_tot, reg_dat_rem,
                    reg_aad_rem, reg_ctr, reg_iv[LPARA_BLK_W-1 -: LPARA_IV_W], reg_ej0, reg_h,
                    i_gh_y};

  // ------------------------------------------------------------------- overrides

  // Pipeline drained: no batch in the AES core and GHASH holds its final value.
  assign w_drained = (reg_outst == '0) & i_gh_idle;
  // G1: abort, zeroize or a fatal error, from every state except IDLE and FIN.
  assign w_g1 = reg_abort_p | reg_zero_p | reg_fatal;
  // G2: suspend at a block boundary with the pipeline drained.
  assign w_g2 = reg_susp_p & w_drained & (PARA_CTX_EN == 1) & w_gcm;
  // New work is not started while an override is pending, so the pipeline drains.
  assign w_stop = w_g1 | reg_susp_p;

  // ------------------------------------------------------------------- data movement

  // Setup message: N >= 2 sends {J0, 0^128} as one batch, N = 1 sends 0^128 then J0.
  assign w_su_in_fire  = (reg_fsm_seq_current_state == ENUM_ST_SEQ_SU_RUN) &
                         o_aes_in_valid & i_aes_in_ready;
  assign w_su_out_fire = (reg_fsm_seq_current_state == ENUM_ST_SEQ_SU_RUN) & i_aes_out_valid;

  // AAD and pass-1 entries go to GHASH only; payload entries go to the AES core.
  assign w_aad_take = (reg_fsm_seq_current_state == ENUM_ST_SEQ_AAD) & (reg_aad_rem != '0) &
                      ~i_in_empty & i_gh_ready & ~w_stop;
  assign w_p1_take  = (reg_fsm_seq_current_state == ENUM_ST_SEQ_PAY) & w_feed_pass1 &
                      (reg_dat_rem != '0) & ~i_in_empty & i_gh_ready & ~w_stop;
  assign w_pay_send = (reg_fsm_seq_current_state == ENUM_ST_SEQ_PAY) & w_aes_pay &
                      (reg_dat_rem != '0) & ~i_in_empty & (~w_dec_gh | i_gh_ready) & ~w_stop &
                      (reg_outst != {LPARA_OUTST_W{1'b1}});
  assign w_in_fire  = w_pay_send & i_aes_in_ready;
  assign w_out_fire = (reg_fsm_seq_current_state == ENUM_ST_SEQ_PAY) & i_aes_out_valid &
                      o_aes_out_ready;
  assign w_gh_fire  = o_gh_valid & i_gh_ready;
  assign w_pay_done = (reg_dat_rem == '0) & w_drained & (w_feed_pass1 | (reg_out_rem == '0));

  // Input FIFO read and decode controls.
  assign o_in_rd_en = w_aad_take | w_p1_take | w_in_fire;
  assign o_fin_seg  = (reg_fsm_seq_current_state != ENUM_ST_SEQ_AAD);
  assign o_fin_rem  = (reg_fsm_seq_current_state == ENUM_ST_SEQ_AAD) ? reg_aad_rem : reg_dat_rem;
  assign o_fout_rem = reg_out_rem;

  // AES core input batch.
  always_comb begin : p_com_aes_in
    o_aes_in_valid = 1'b0;
    o_aes_in_data  = '0;
    o_aes_in_lane  = '0;
    o_aes_in_last  = 1'b0;
    case (reg_fsm_seq_current_state)
      ENUM_ST_SEQ_SU_RUN: begin
        if (PARA_LANE_NUM > 1) begin
          o_aes_in_valid = (reg_su_sent == 2'd0);
          for (int idx = 0; idx < PARA_LANE_NUM; idx++) begin
            if (idx == 1)
              o_aes_in_data[idx*LPARA_BLK_W +: LPARA_BLK_W] = w_j0;
            if (idx < 2)
              o_aes_in_lane[idx] = 1'b1;
          end
          o_aes_in_last  = 1'b1;
        end else begin
          o_aes_in_valid = (reg_su_sent != 2'd2);
          o_aes_in_data[LPARA_BLK_W-1:0] = (reg_su_sent == 2'd0) ? '0 : w_j0;
          o_aes_in_lane[0] = 1'b1;
          o_aes_in_last  = (reg_su_sent == 2'd1);
        end
      end
      ENUM_ST_SEQ_PAY: begin
        o_aes_in_valid = w_pay_send;
        o_aes_in_data  = i_fin_data;
        o_aes_in_lane  = i_fin_mask;
        o_aes_in_last  = (i_fin_bytes == reg_dat_rem);
      end
      default: o_aes_in_valid = 1'b0;
    endcase
  end

  // AES core output: setup results are always taken; payload results need room in the output
  // FIFO and, when encrypting, a GHASH slot.
  always_comb begin : p_com_aes_out
    o_aes_out_ready = 1'b0;
    case (reg_fsm_seq_current_state)
      ENUM_ST_SEQ_SU_RUN: o_aes_out_ready = 1'b1;
      ENUM_ST_SEQ_PAY:    o_aes_out_ready = ~i_out_full & (~w_enc_gh | i_gh_ready);
      default:            o_aes_out_ready = 1'b1;
    endcase
  end

  assign o_out_wr_en = w_out_fire;

  // GHASH input: AAD, pass-1 ciphertext, decrypt core input, encrypt core output, length.
  always_comb begin : p_com_gh_in
    o_gh_valid = 1'b0;
    o_gh_data  = i_fin_data;
    o_gh_mask  = i_fin_mask;
    case (reg_fsm_seq_current_state)
      ENUM_ST_SEQ_AAD: o_gh_valid = w_aad_take;
      ENUM_ST_SEQ_PAY: begin
        if (w_enc_gh) begin
          o_gh_valid = w_out_fire;
          o_gh_data  = i_fout_data;
          o_gh_mask  = i_aes_out_lane;
        end else begin
          o_gh_valid = w_p1_take | (w_in_fire & w_dec_gh);
        end
      end
      ENUM_ST_SEQ_LEN: begin
        o_gh_valid = ~reg_len_sent;
        o_gh_data  = '0;
        o_gh_data[LPARA_BLK_W-1:0] = w_len_blk;
        o_gh_mask  = '0;
        o_gh_mask[0] = 1'b1;
      end
      default: o_gh_valid = 1'b0;
    endcase
  end

  // AES core configuration of the setup message (ECB encrypt) and the payload message.
  always_comb begin : p_com_aes_cfg
    o_aes_cfg_valid    = 1'b0;
    o_aes_cfg_key_size = reg_ksize;
    o_aes_cfg_mode     = ENUM_MODE_ECB;
    o_aes_cfg_decipher = 1'b0;
    o_aes_cfg_iv       = '0;
    o_aes_cfg_cfb      = '0;
    case (reg_fsm_seq_current_state)
      ENUM_ST_SEQ_SU_CFG: o_aes_cfg_valid = 1'b1;
      ENUM_ST_SEQ_PY_CFG: begin
        o_aes_cfg_valid = 1'b1;
        if (w_gcm) begin
          o_aes_cfg_mode = ENUM_MODE_CTR;
          o_aes_cfg_iv   = {reg_iv[LPARA_BLK_W-1 -: LPARA_IV_W], reg_ctr};
        end else begin
          o_aes_cfg_mode     = reg_mode;
          o_aes_cfg_decipher = reg_dec;
          o_aes_cfg_iv       = reg_iv;
          o_aes_cfg_cfb      = reg_cfb;
        end
      end
      default: o_aes_cfg_valid = 1'b0;
    endcase
  end

  // ------------------------------------------------------------------- FSM seq

  // Part 1, sequential: FSM current state, reset to IDLE.
  always_ff @(posedge i_clk_core, negedge i_rst_n_core) begin : p_ff_fsm_seq
    if (!i_rst_n_core)
      reg_fsm_seq_current_state <= ENUM_ST_SEQ_IDLE;
    else
      reg_fsm_seq_current_state <= w_fsm_seq_nxt_state;
  end

  // Key ready and the setup choice of the KEY state.
  assign w_key_go = i_key_ready & ~reg_first;

  // Part 2, combinational: transitions of the state table, then G2, then G1 (highest).
  always_comb begin : p_com_fsm_seq_nxt
    w_fsm_seq_nxt_state = reg_fsm_seq_current_state;
    case (reg_fsm_seq_current_state)
      ENUM_ST_SEQ_IDLE: begin
        if (i_cfg_valid && w_b_op && (PARA_CTX_EN == 1))
          w_fsm_seq_nxt_state = ENUM_ST_SEQ_REST;
        else if (i_cfg_valid && !w_b_op)
          w_fsm_seq_nxt_state = ENUM_ST_SEQ_KEY;
      end
      ENUM_ST_SEQ_KEY: begin
        if (w_key_go && w_gcm && (reg_pass != 2'd2))
          w_fsm_seq_nxt_state = ENUM_ST_SEQ_SU_CFG;
        else if (w_key_go)
          w_fsm_seq_nxt_state = ENUM_ST_SEQ_PY_CFG;
      end
      ENUM_ST_SEQ_SU_CFG: begin
        if (i_aes_cfg_ready)
          w_fsm_seq_nxt_state = ENUM_ST_SEQ_SU_RUN;
      end
      ENUM_ST_SEQ_SU_RUN: begin
        if (reg_su_rcv == 2'd2)
          w_fsm_seq_nxt_state = ENUM_ST_SEQ_POW;
      end
      ENUM_ST_SEQ_POW: begin
        if (!reg_first && i_gh_pow_done)
          w_fsm_seq_nxt_state = ENUM_ST_SEQ_AAD;
      end
      ENUM_ST_SEQ_AAD: begin
        if ((reg_aad_rem == '0) && i_gh_idle && w_feed_pass1)
          w_fsm_seq_nxt_state = ENUM_ST_SEQ_PAY;
        else if ((reg_aad_rem == '0) && i_gh_idle)
          w_fsm_seq_nxt_state = ENUM_ST_SEQ_PY_CFG;
      end
      ENUM_ST_SEQ_PY_CFG: begin
        if (i_aes_cfg_ready)
          w_fsm_seq_nxt_state = ENUM_ST_SEQ_PAY;
      end
      ENUM_ST_SEQ_PAY: begin
        if (w_pay_done && w_gcm)
          w_fsm_seq_nxt_state = ENUM_ST_SEQ_LEN;
        else if (w_pay_done)
          w_fsm_seq_nxt_state = ENUM_ST_SEQ_FIN;
      end
      ENUM_ST_SEQ_LEN: begin
        if (reg_len_sent && i_gh_idle)
          w_fsm_seq_nxt_state = ENUM_ST_SEQ_TAG;
      end
      ENUM_ST_SEQ_TAG:  w_fsm_seq_nxt_state = ENUM_ST_SEQ_FIN;
      ENUM_ST_SEQ_FIN: begin
        if (!reg_first && !reg_dirty && i_sts_idle)
          w_fsm_seq_nxt_state = ENUM_ST_SEQ_IDLE;
      end
      ENUM_ST_SEQ_SUSP: begin
        if (i_ctx_done)
          w_fsm_seq_nxt_state = ENUM_ST_SEQ_FIN;
      end
      ENUM_ST_SEQ_REST: begin
        if (i_ctx_done)
          w_fsm_seq_nxt_state = ENUM_ST_SEQ_POW;
      end
      ENUM_ST_SEQ_ABRT: begin
        if (!reg_first && reg_zdone && !i_out_flush_busy)
          w_fsm_seq_nxt_state = ENUM_ST_SEQ_FIN;
      end
      default: w_fsm_seq_nxt_state = ENUM_ST_SEQ_ABRT;
    endcase
    if (((reg_fsm_seq_current_state == ENUM_ST_SEQ_AAD) ||
         (reg_fsm_seq_current_state == ENUM_ST_SEQ_PAY)) && w_g2 && !w_g1)
      w_fsm_seq_nxt_state = ENUM_ST_SEQ_SUSP;
    if ((reg_fsm_seq_current_state != ENUM_ST_SEQ_IDLE) &&
        (reg_fsm_seq_current_state != ENUM_ST_SEQ_FIN) &&
        (reg_fsm_seq_current_state != ENUM_ST_SEQ_ABRT) && w_g1)
      w_fsm_seq_nxt_state = ENUM_ST_SEQ_ABRT;
  end

  // State change marker: entry actions use reg_first, which is 1 in the first clock of a state.
  assign w_st_chg = (w_fsm_seq_nxt_state != reg_fsm_seq_current_state);

  // Part 3, combinational: Moore outputs and entry pulses.
  always_comb begin : p_com_fsm_seq_out
    o_key_zeroize  = 1'b0;
    o_key_load     = 1'b0;
    o_key_src      = reg_ksrc;
    o_key_restore  = 1'b0;
    o_aes_zeroize  = 1'b0;
    o_out_flush    = 1'b0;
    o_gh_zeroize   = 1'b0;
    o_gh_clr       = 1'b0;
    o_gh_pow_start = 1'b0;
    o_ctx_zeroize  = 1'b0;
    o_ctx_save     = 1'b0;
    o_ctx_load     = 1'b0;
    case (reg_fsm_seq_current_state)
      ENUM_ST_SEQ_IDLE: begin
        o_aes_zeroize = w_idle_zero;
        o_out_flush   = w_idle_zero;
        o_key_zeroize = w_idle_zero;
        o_gh_zeroize  = w_idle_zero;
        o_gh_clr      = w_idle_zero;
        o_ctx_zeroize = w_idle_zero;
      end
      ENUM_ST_SEQ_KEY: begin
        o_key_load = reg_first;
        o_gh_clr   = reg_first & (reg_pass != 2'd2);
      end
      ENUM_ST_SEQ_POW:  o_gh_pow_start = reg_first;
      ENUM_ST_SEQ_FIN:  o_aes_zeroize  = reg_first;
      ENUM_ST_SEQ_SUSP: o_ctx_save     = reg_first;
      ENUM_ST_SEQ_REST: begin
        o_ctx_load    = reg_first;
        o_key_restore = i_ctx_done & (PARA_CTX_MODE == 0);
        o_key_load    = i_ctx_done & (PARA_CTX_MODE == 1);
        o_key_src     = (PARA_CTX_MODE == 1) ? 1'b0 : reg_ksrc;
      end
      ENUM_ST_SEQ_ABRT: begin
        o_aes_zeroize = reg_first;
        o_out_flush   = reg_first;
        o_gh_clr      = reg_first;
        o_key_zeroize = reg_first & reg_zero_act;
        o_gh_zeroize  = reg_first & reg_zero_act;
        o_ctx_zeroize = reg_first & reg_zero_act;
      end
      default: o_aes_zeroize = 1'b0;
    endcase
  end

  // Zeroize command received while idle: cleared in place, reported, FSM stays in IDLE.
  assign w_idle_zero = (reg_fsm_seq_current_state == ENUM_ST_SEQ_IDLE) & reg_zero_p;
  // Abort or suspend received while idle: nothing to stop, the command is acknowledged.
  assign w_idle_cmd  = (reg_fsm_seq_current_state == ENUM_ST_SEQ_IDLE) & (reg_abort_p | reg_susp_p);

  // GHASH, tag, context and key connections that follow the registers.
  assign o_gh_load_y = ((reg_fsm_seq_current_state == ENUM_ST_SEQ_KEY) & reg_first &
                        (reg_pass == 2'd2)) |
                       ((reg_fsm_seq_current_state == ENUM_ST_SEQ_REST) & i_ctx_done);
  assign o_gh_y      = (reg_fsm_seq_current_state == ENUM_ST_SEQ_REST) ?
                       i_ctx_img[LPARA_BLK_W-1:0] : reg_y_aad;
  assign o_gh_h      = reg_h;
  assign o_tag_ej0   = reg_ej0;
  assign o_tag_len   = reg_tlen;
  assign o_tag_exp   = reg_tag_exp;
  assign o_ctx_slot  = (i_cmd_valid & i_cmd[2]) ? i_cmd[1:0] : reg_slot;
  assign o_ctx_img   = w_img;
  assign o_key_ctx   = i_ctx_img[LPARA_SLOT_W-4*32-1 -: LPARA_KEY_W];
  assign o_cfg_clr   = reg_cfg_clr;
  assign w_slot_vld  = (PARA_CTX_MODE == 1) ? i_ctx_vld[0] : i_ctx_vld[reg_slot];

  // ------------------------------------------------------------------- errors and events

  // New events and errors of this clock; the lowest error ID wins (spec 12).
  always_comb begin : p_com_err
    w_evt_new      = '0;
    w_err_new      = ENUM_ERR_NONE;
    w_err_core_new = '0;
    w_fatal_new    = 1'b0;
    if (i_aes_err_valid) begin
      w_fatal_new = 1'b1;
      if (i_aes_err_code == 4'(LPARA_CORE_ERR_CTR)) begin
        w_evt_new[LPARA_EVT_CEXH] = 1'b1;
        w_err_new = ENUM_ERR_CTR;
      end else begin
        w_evt_new[LPARA_EVT_PERR] = 1'b1;
        w_err_new      = ENUM_ERR_CORE;
        w_err_core_new = i_aes_err_code;
      end
    end
    if ((reg_fsm_seq_current_state == ENUM_ST_SEQ_KEY) && i_key_err) begin
      w_fatal_new = 1'b1;
      w_evt_new[LPARA_EVT_KERR] = 1'b1;
      if ((w_err_new == ENUM_ERR_NONE) || (w_err_new > ENUM_ERR_KEY))
        w_err_new = ENUM_ERR_KEY;
    end
    if (o_in_rd_en && i_fin_seg_err) begin
      w_fatal_new = 1'b1;
      w_evt_new[LPARA_EVT_LERR] = 1'b1;
      w_err_new = ENUM_ERR_LEN;
    end
    if (((reg_fsm_seq_current_state == ENUM_ST_SEQ_KEY) && reg_first && (reg_pass == 2'd2) &&
         w_gcm && !reg_vc_valid) ||
        ((reg_fsm_seq_current_state == ENUM_ST_SEQ_REST) && reg_first &&
         !w_slot_vld) ||
        (w_fsm_seq_nxt_state == ENUM_ST_SEQ_ABRT && !w_g1 &&
         (reg_fsm_seq_current_state != ENUM_ST_SEQ_ABRT))) begin
      w_fatal_new = 1'b1;
      w_evt_new[LPARA_EVT_PERR] = 1'b1;
      if ((w_err_new == ENUM_ERR_NONE) || (w_err_new > ENUM_ERR_PROTO))
        w_err_new = ENUM_ERR_PROTO;
    end
    if ((reg_fsm_seq_current_state == ENUM_ST_SEQ_TAG) && reg_dec && !i_tag_match) begin
      w_evt_new[LPARA_EVT_TAGF] = 1'b1;
      if (w_err_new == ENUM_ERR_NONE)
        w_err_new = ENUM_ERR_TAG;
    end
    if (((reg_fsm_seq_current_state == ENUM_ST_SEQ_TAG) ||
         ((reg_fsm_seq_current_state == ENUM_ST_SEQ_PAY) && w_pay_done && !w_gcm)))
      w_evt_new[LPARA_EVT_DONE] = 1'b1;
    if (((reg_fsm_seq_current_state == ENUM_ST_SEQ_SUSP) ||
         (reg_fsm_seq_current_state == ENUM_ST_SEQ_REST)) && i_ctx_done)
      w_evt_new[LPARA_EVT_CSWD] = 1'b1;
  end

  assign w_new_evt_any = |w_evt_new;

  // ------------------------------------------------------------------- status report

  // Status bundle of CDC-002.
  assign o_sts = {reg_msg_end, reg_suspended, reg_resumed, reg_cmd_ack, reg_tag_ok, reg_ver_ok,
                  reg_zeroized, i_key_ld, reg_evt, reg_err_code, reg_err_core,
                  reg_fsm_seq_current_state, i_ctx_vld, reg_failcnt,
                  reg_aad_tot - reg_aad_rem, reg_dat_tot - reg_dat_rem, reg_aad_rem, reg_dat_rem,
                  reg_tag};
  assign o_sts_send = reg_dirty & i_sts_idle;

  // ------------------------------------------------------------------- registers

  // Commands, the fatal flag and the entry marker.
  always_ff @(posedge i_clk_core, negedge i_rst_n_core) begin : p_ff_ctl
    if (!i_rst_n_core) begin
      reg_abort_p  <= 1'b0;
      reg_zero_p   <= 1'b0;
      reg_susp_p   <= 1'b0;
      reg_zero_act <= 1'b0;
      reg_fatal    <= 1'b0;
      reg_first    <= 1'b1;
      reg_cfg_clr  <= 1'b0;
    end else begin
      reg_first   <= w_st_chg;
      reg_cfg_clr <= w_st_chg & ((w_fsm_seq_nxt_state == ENUM_ST_SEQ_SU_CFG) |
                                 (w_fsm_seq_nxt_state == ENUM_ST_SEQ_PY_CFG) |
                                 (w_fsm_seq_nxt_state == ENUM_ST_SEQ_POW) |
                                 (w_fsm_seq_nxt_state == ENUM_ST_SEQ_ABRT) |
                                 (w_fsm_seq_nxt_state == ENUM_ST_SEQ_FIN));
      // Pending commands are consumed by ABRT, by the zeroize in IDLE, and by FIN.
      if (w_cmd_abort)
        reg_abort_p <= 1'b1;
      else if ((reg_fsm_seq_current_state == ENUM_ST_SEQ_ABRT) ||
               (reg_fsm_seq_current_state == ENUM_ST_SEQ_IDLE))
        reg_abort_p <= 1'b0;
      if (w_cmd_zero)
        reg_zero_p <= 1'b1;
      else if ((reg_fsm_seq_current_state == ENUM_ST_SEQ_ABRT) || w_idle_zero)
        reg_zero_p <= 1'b0;
      if (w_cmd_susp)
        reg_susp_p <= 1'b1;
      else if ((reg_fsm_seq_current_state == ENUM_ST_SEQ_SUSP) ||
               (reg_fsm_seq_current_state == ENUM_ST_SEQ_FIN) ||
               (reg_fsm_seq_current_state == ENUM_ST_SEQ_IDLE))
        reg_susp_p <= 1'b0;
      if ((reg_fsm_seq_current_state != ENUM_ST_SEQ_ABRT) && (w_fsm_seq_nxt_state == ENUM_ST_SEQ_ABRT))
        reg_zero_act <= reg_zero_p | w_cmd_zero;
      if ((reg_fsm_seq_current_state == ENUM_ST_SEQ_ABRT) ||
          (reg_fsm_seq_current_state == ENUM_ST_SEQ_IDLE))
        reg_fatal <= 1'b0;
      else if (w_fatal_new)
        reg_fatal <= 1'b1;
    end
  end

  // Message configuration: start bundles load everything; resume bundles keep the key and
  // expected tag for the export mode, the rest comes from the context image.
  always_ff @(posedge i_clk_core, negedge i_rst_n_core) begin : p_ff_cfg
    if (!i_rst_n_core) begin
      reg_mode    <= ENUM_MODE_ECB;
      reg_dec     <= 1'b0;
      reg_ksize   <= 1'b0;
      reg_ksrc    <= 1'b0;
      reg_pass    <= '0;
      reg_tlen    <= '0;
      reg_cfb     <= '0;
      reg_slot    <= '0;
      reg_iv      <= '0;
      reg_tag_exp <= '0;
    end else if ((reg_fsm_seq_current_state == ENUM_ST_SEQ_IDLE) && i_cfg_valid) begin
      reg_mode    <= mode_type_def'(w_b_mode);
      reg_dec     <= w_b_dec;
      reg_ksize   <= w_b_ksize;
      reg_ksrc    <= w_b_ksrc;
      reg_pass    <= w_b_pass;
      reg_tlen    <= w_b_tlen;
      reg_cfb     <= w_b_cfb;
      reg_slot    <= w_b_slot;
      reg_iv      <= w_b_iv;
      reg_tag_exp <= w_b_tag;
    end else if ((reg_fsm_seq_current_state == ENUM_ST_SEQ_REST) && i_ctx_done) begin
      reg_mode  <= ENUM_MODE_GCM;
      reg_ksize <= i_ctx_img[20*32];
      reg_tlen  <= i_ctx_img[20*32+1 +: 3];
      reg_pass  <= i_ctx_img[20*32+4 +: 2];
      reg_dec   <= i_ctx_img[20*32+6];
      reg_iv    <= {i_ctx_img[12*32 +: LPARA_IV_W], LPARA_CTR_W'(0)};
      if (PARA_CTX_MODE == 0)
        reg_tag_exp <= i_ctx_img[29*32 +: LPARA_BLK_W];
    end
  end

  // GCM values: H and E(K,J0) from the setup message or the context; the verified context of
  // policy A; tag results.
  always_ff @(posedge i_clk_core, negedge i_rst_n_core) begin : p_ff_gcm
    if (!i_rst_n_core) begin
      reg_h        <= '0;
      reg_ej0      <= '0;
      reg_y_aad    <= '0;
      reg_vc_valid <= 1'b0;
      reg_ver_ok   <= 1'b0;
      reg_tag_ok   <= 1'b0;
      reg_tag      <= '0;
      reg_failcnt  <= '0;
    end else begin
      if (w_idle_zero || ((reg_fsm_seq_current_state == ENUM_ST_SEQ_ABRT) && reg_first &&
                          reg_zero_act)) begin
        reg_h        <= '0;
        reg_ej0      <= '0;
        reg_y_aad    <= '0;
        reg_vc_valid <= 1'b0;
        reg_ver_ok   <= 1'b0;
        reg_tag      <= '0;
      end
      if ((reg_fsm_seq_current_state == ENUM_ST_SEQ_IDLE) && i_cfg_valid && !w_b_op) begin
        reg_tag_ok <= 1'b0;
        reg_ver_ok <= 1'b0;
        if (w_b_knew || (w_b_pass != 2'd2))
          reg_vc_valid <= 1'b0;
      end
      if (w_su_out_fire) begin
        if (PARA_LANE_NUM > 1) begin
          reg_h   <= i_aes_out_data[LPARA_BLK_W-1:0];
          reg_ej0 <= i_aes_out_data[(PARA_LANE_NUM > 1 ? 1 : 0)*LPARA_BLK_W +: LPARA_BLK_W];
        end else if (reg_su_rcv == 2'd0) begin
          reg_h <= i_aes_out_data[LPARA_BLK_W-1:0];
        end else begin
          reg_ej0 <= i_aes_out_data[LPARA_BLK_W-1:0];
        end
      end
      if ((reg_fsm_seq_current_state == ENUM_ST_SEQ_REST) && i_ctx_done) begin
        reg_h   <= i_ctx_img[4*32 +: LPARA_BLK_W];
        reg_ej0 <= i_ctx_img[8*32 +: LPARA_BLK_W];
      end
      if ((reg_fsm_seq_current_state == ENUM_ST_SEQ_AAD) && w_feed_pass1 &&
          (w_fsm_seq_nxt_state == ENUM_ST_SEQ_PAY))
        reg_y_aad <= i_gh_y;
      if (reg_fsm_seq_current_state == ENUM_ST_SEQ_TAG) begin
        reg_tag    <= i_tag;
        reg_tag_ok <= reg_dec & i_tag_match;
        if (reg_dec && !i_tag_match)
          reg_failcnt <= reg_failcnt + 32'd1;
        if (w_feed_pass1) begin
          reg_ver_ok   <= i_tag_match;
          reg_vc_valid <= i_tag_match;
        end else if (reg_pass == 2'd2) begin
          reg_vc_valid <= 1'b0;
        end
      end
    end
  end

  // Byte, counter and batch accounting.
  always_ff @(posedge i_clk_core, negedge i_rst_n_core) begin : p_ff_cnt
    if (!i_rst_n_core) begin
      reg_aad_rem  <= '0;
      reg_dat_rem  <= '0;
      reg_out_rem  <= '0;
      reg_aad_tot  <= '0;
      reg_dat_tot  <= '0;
      reg_ctr      <= '0;
      reg_outst    <= '0;
      reg_su_sent  <= '0;
      reg_su_rcv   <= '0;
      reg_len_sent <= 1'b0;
      reg_zdone    <= 1'b0;
    end else begin
      if ((reg_fsm_seq_current_state == ENUM_ST_SEQ_IDLE) && i_cfg_valid && !w_b_op) begin
        reg_aad_rem <= w_b_aad;
        reg_dat_rem <= w_b_dat;
        reg_out_rem <= w_b_dat;
        // Pass 2 carries no AAD; its length block uses len(A) of the verified pass 1.
        if (w_b_pass != 2'd2)
          reg_aad_tot <= w_b_aad;
        reg_dat_tot <= w_b_dat;
        reg_ctr     <= LPARA_CTR_W'(2);
      end
      if ((reg_fsm_seq_current_state == ENUM_ST_SEQ_REST) && i_ctx_done) begin
        reg_ctr     <= i_ctx_img[15*32 +: 32];
        reg_aad_rem <= i_ctx_img[16*32 +: 32];
        reg_dat_rem <= i_ctx_img[17*32 +: 32];
        reg_out_rem <= i_ctx_img[17*32 +: 32];
        reg_aad_tot <= i_ctx_img[18*32 +: 32];
        reg_dat_tot <= i_ctx_img[19*32 +: 32];
      end
      if (w_aad_take)
        reg_aad_rem <= reg_aad_rem - i_fin_bytes;
      if (w_p1_take || w_in_fire) begin
        reg_dat_rem <= reg_dat_rem - i_fin_bytes;
        reg_ctr     <= reg_ctr + LPARA_CTR_W'(i_fin_cnt);
      end
      if (w_out_fire)
        reg_out_rem <= reg_out_rem - i_fout_bytes;
      casez ({w_in_fire, w_out_fire})
        2'b10:   reg_outst <= reg_outst + LPARA_OUTST_W'(1);
        2'b01:   reg_outst <= reg_outst - LPARA_OUTST_W'(1);
        default: reg_outst <= reg_outst;
      endcase
      if (reg_fsm_seq_current_state == ENUM_ST_SEQ_ABRT)
        reg_outst <= '0;
      if (reg_fsm_seq_current_state != ENUM_ST_SEQ_SU_RUN) begin
        reg_su_sent <= '0;
        reg_su_rcv  <= '0;
      end else begin
        if (w_su_in_fire)
          reg_su_sent <= (PARA_LANE_NUM > 1) ? 2'd2 : (reg_su_sent + 2'd1);
        if (w_su_out_fire)
          reg_su_rcv <= (PARA_LANE_NUM > 1) ? 2'd2 : (reg_su_rcv + 2'd1);
      end
      if (reg_fsm_seq_current_state != ENUM_ST_SEQ_LEN)
        reg_len_sent <= 1'b0;
      else if (w_gh_fire)
        reg_len_sent <= 1'b1;
      if (reg_fsm_seq_current_state != ENUM_ST_SEQ_ABRT)
        reg_zdone <= 1'b0;
      else if (i_aes_zeroize_done)
        reg_zdone <= 1'b1;
    end
  end

  // Report values: events and one-shot flags are sticky until a report carries them; error
  // code keeps the first error of a message; the report is marked dirty on every change.
  always_ff @(posedge i_clk_core, negedge i_rst_n_core) begin : p_ff_report
    if (!i_rst_n_core) begin
      reg_evt       <= '0;
      reg_err_code  <= ENUM_ERR_NONE;
      reg_err_core  <= '0;
      reg_zeroized  <= 1'b0;
      reg_msg_end   <= 1'b0;
      reg_suspended <= 1'b0;
      reg_resumed   <= 1'b0;
      reg_cmd_ack   <= 1'b0;
      reg_cmd_seen  <= 1'b0;
      reg_dirty     <= 1'b0;
    end else begin
      if (o_sts_send) begin
        reg_evt       <= w_evt_new;
        reg_msg_end   <= 1'b0;
        reg_suspended <= 1'b0;
        reg_resumed   <= 1'b0;
        reg_cmd_ack   <= 1'b0;
      end else begin
        reg_evt <= reg_evt | w_evt_new;
      end
      if ((reg_fsm_seq_current_state == ENUM_ST_SEQ_IDLE) && i_cfg_valid) begin
        reg_err_code <= ENUM_ERR_NONE;
        reg_err_core <= '0;
        reg_zeroized <= 1'b0;
      end else if ((reg_err_code == ENUM_ERR_NONE) && (w_err_new != ENUM_ERR_NONE)) begin
        reg_err_code <= w_err_new;
        reg_err_core <= w_err_core_new;
      end
      if (w_idle_zero || ((reg_fsm_seq_current_state == ENUM_ST_SEQ_ABRT) &&
                          (w_fsm_seq_nxt_state == ENUM_ST_SEQ_FIN) && reg_zero_act))
        reg_zeroized <= 1'b1;
      if ((reg_fsm_seq_current_state == ENUM_ST_SEQ_FIN) && reg_first)
        reg_msg_end <= 1'b1;
      if ((reg_fsm_seq_current_state == ENUM_ST_SEQ_SUSP) && i_ctx_done)
        reg_suspended <= 1'b1;
      if ((reg_fsm_seq_current_state == ENUM_ST_SEQ_REST) && i_ctx_done)
        reg_resumed <= 1'b1;
      // Commands are acknowledged when they have been carried out (FIN) or found nothing to do.
      if (w_cmd_abort || w_cmd_zero || w_cmd_susp)
        reg_cmd_seen <= 1'b1;
      else if (o_sts_send && reg_cmd_ack)
        reg_cmd_seen <= 1'b0;
      if (w_idle_zero || w_idle_cmd ||
          ((reg_fsm_seq_current_state == ENUM_ST_SEQ_FIN) && reg_first && reg_cmd_seen))
        reg_cmd_ack <= 1'b1;
      // A slot operation that ends while the sequencer is idle is a free: its result (the slot
      // valid flags) is reported when it ends, after the acknowledge of the command (DEC-030).
      if (w_st_chg || w_new_evt_any || w_idle_zero || w_idle_cmd || i_cmd_valid ||
          ((reg_fsm_seq_current_state == ENUM_ST_SEQ_IDLE) && i_ctx_done))
        reg_dirty <= 1'b1;
      else if (o_sts_send)
        reg_dirty <= 1'b0;
    end
  end

endmodule
