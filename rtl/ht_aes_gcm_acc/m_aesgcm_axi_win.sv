/*
 * Project      : AES-GCM Accelerator
 * Author       : Nguyen Hung Quan and Claude (user)
 * AI Flow      : VLSIT RTL Generator AI Automation Flow
 * AI Flow Page : https://github.com/nguyenquanicd/VLSIT_RTL_Generator_AI_Model
 * Date         : 2026-11-25
 * Description  : AXI4 data window (spec 6.3.2, OP-013, ERR-008), subordinate of the Memory
 *                Subordinate profile (REF-006 Tables A9-2, A9-4). FSM axw accepts one write burst
 *                at a time: a legal burst (address bit 11 = 0, FIXED or INCR, size equal to the
 *                bus width, message source = AXI window) pushes its beats to the input stream,
 *                an illegal one is consumed without push; the response is SLVERR (0b10) for an
 *                illegal burst or a WLAST at another beat than AWLEN. FSM axr serves one read
 *                burst at a time from the output stream (address bit 11 = 1), or returns zero
 *                beats with SLVERR for an illegal burst. IDs are returned unchanged. AWREADY and
 *                ARREADY are low during reset and the first clock after it (DEC-025).
 * Decisions    : DEC-025 (spec section 20).
 */
`timescale 1ns/1ps

module m_aesgcm_axi_win #(
  // Parameter Description: AXI4 data width.
  // Parameter values: 32, 64 or 128; default is 32.
  // Parameter unit: bit
  parameter logic [31:0] PARA_AXI_DATA_W = 32,
  // Parameter Description: AXI4 ID width.
  // Parameter values: 1 to 8; default is 4.
  // Parameter unit: bit
  parameter logic [31:0] PARA_AXI_ID_W = 4,
  // Parameter Description: AXI4 address width.
  // Parameter values: 12 to 32; default is 16.
  // Parameter unit: bit
  parameter logic [31:0] PARA_AXI_ADDR_W = 16,
  localparam logic [31:0] LPARA_BLK_W = 128,
  localparam logic [31:0] LPARA_STRB_W = PARA_AXI_DATA_W / 8,
  localparam logic [31:0] LPARA_SIZE = $clog2(PARA_AXI_DATA_W / 8),
  localparam logic [31:0] LPARA_WIN_BIT = 11,
  // Response codes of REF-006 Table A3-5 (FIXED 0b00 and INCR 0b01 have burst bit 1 = 0).
  localparam logic [31:0] LPARA_RESP_OKAY = 0,
  localparam logic [31:0] LPARA_RESP_SLVERR = 2
) (
  // Clock and reset (BUS domain)
  input  wire                        i_clk_bus,
  input  wire                        i_rst_n_bus,

  // Message data source selects the window
  input  wire                        i_sel,

  // Write address channel
  input  wire  [PARA_AXI_ID_W-1:0]   i_axi_awid,
  input  wire  [PARA_AXI_ADDR_W-1:0] i_axi_awaddr,
  input  wire  [7:0]                 i_axi_awlen,
  input  wire  [2:0]                 i_axi_awsize,
  input  wire  [1:0]                 i_axi_awburst,
  input  wire                        i_axi_awvalid,
  output logic                       o_axi_awready,

  // Write data channel
  input  wire  [PARA_AXI_DATA_W-1:0] i_axi_wdata,
  input  wire  [LPARA_STRB_W-1:0]    i_axi_wstrb,
  input  wire                        i_axi_wlast,
  input  wire                        i_axi_wvalid,
  output logic                       o_axi_wready,

  // Write response channel
  output logic [PARA_AXI_ID_W-1:0]   o_axi_bid,
  output logic [1:0]                 o_axi_bresp,
  output logic                       o_axi_bvalid,
  input  wire                        i_axi_bready,

  // Read address channel
  input  wire  [PARA_AXI_ID_W-1:0]   i_axi_arid,
  input  wire  [PARA_AXI_ADDR_W-1:0] i_axi_araddr,
  input  wire  [7:0]                 i_axi_arlen,
  input  wire  [2:0]                 i_axi_arsize,
  input  wire  [1:0]                 i_axi_arburst,
  input  wire                        i_axi_arvalid,
  output logic                       o_axi_arready,

  // Read data channel
  output logic [PARA_AXI_ID_W-1:0]   o_axi_rid,
  output logic [PARA_AXI_DATA_W-1:0] o_axi_rdata,
  output logic [1:0]                 o_axi_rresp,
  output logic                       o_axi_rlast,
  output logic                       o_axi_rvalid,
  input  wire                        i_axi_rready,

  // Input beat stream
  output logic                       o_beat_valid,
  input  wire                        i_beat_ready,
  output logic [LPARA_BLK_W-1:0]     o_beat_data,

  // Output beat stream
  input  wire                        i_obeat_valid,
  output logic                       o_obeat_ready,
  input  wire  [LPARA_BLK_W-1:0]     i_obeat_data
);

  // FSM axw states.
  typedef enum logic [1:0] {
    ENUM_ST_AXW_IDLE = 2'b00,
    ENUM_ST_AXW_DATA = 2'b01,
    ENUM_ST_AXW_RESP = 2'b10
  } axw_state_type_def;

  // FSM axr states.
  typedef enum logic [2:0] {
    ENUM_ST_AXR_IDLE = 3'b000,
    ENUM_ST_AXR_CHK  = 3'b001,
    ENUM_ST_AXR_DATA = 3'b010,
    ENUM_ST_AXR_DROP = 3'b011,
    ENUM_ST_AXR_END  = 3'b100
  } axr_state_type_def;

  // Internal signal declarations
  axw_state_type_def      reg_fsm_axw_current_state;
  axw_state_type_def      w_fsm_axw_nxt_state;
  axr_state_type_def      reg_fsm_axr_current_state;
  axr_state_type_def      w_fsm_axr_nxt_state;
  logic [PARA_AXI_ID_W-1:0] reg_awid;
  logic [7:0]             reg_awlen;
  logic [7:0]             reg_wcnt;
  logic                   reg_drop;
  logic                   reg_wmis;
  logic [PARA_AXI_ID_W-1:0] reg_arid;
  logic [7:0]             reg_arlen;
  logic [7:0]             reg_rcnt;
  logic                   reg_ar_ok;
  logic                   w_aw_fire;
  logic                   w_w_fire;
  logic                   w_ar_fire;
  logic                   w_r_fire;
  logic                   w_aw_legal;
  logic                   w_ar_legal;
  logic                   w_r_last;
  logic                   w_wstrb_unused;
  logic                   reg_run;

  // AWREADY and ARREADY stay low while the BUS reset is asserted and for the first clock after its
  // release (port reset value 0, spec 7.3, DEC-025): the flag is the registered "reset released".
  always_ff @(posedge i_clk_bus, negedge i_rst_n_bus) begin : p_ff_run
    if (!i_rst_n_bus)
      reg_run <= 1'b0;
    else
      reg_run <= 1'b1;
  end

  // ------------------------------------------------------------------- write window

  // Legality of the write burst, latched as the drop flag when the address is accepted.
  assign w_aw_legal = i_sel & ~i_axi_awaddr[LPARA_WIN_BIT] & ~i_axi_awburst[1] &
                      (i_axi_awsize == 3'(LPARA_SIZE));
  assign w_aw_fire  = i_axi_awvalid & o_axi_awready;
  assign w_w_fire   = i_axi_wvalid & o_axi_wready;
  // Write strobes are ignored: the data is counted by the length registers (spec 6.2).
  assign w_wstrb_unused = |i_axi_wstrb;

  // Part 1, sequential: FSM axw current state.
  always_ff @(posedge i_clk_bus, negedge i_rst_n_bus) begin : p_ff_fsm_axw
    if (!i_rst_n_bus)
      reg_fsm_axw_current_state <= ENUM_ST_AXW_IDLE;
    else
      reg_fsm_axw_current_state <= w_fsm_axw_nxt_state;
  end

  // Part 2, combinational: IDLE -> DATA on the address, DATA -> RESP on the last beat,
  // RESP -> IDLE on BREADY; an invalid encoding returns to IDLE.
  always_comb begin : p_com_fsm_axw_nxt
    w_fsm_axw_nxt_state = reg_fsm_axw_current_state;
    case (reg_fsm_axw_current_state)
      ENUM_ST_AXW_IDLE: begin
        if (i_axi_awvalid)
          w_fsm_axw_nxt_state = ENUM_ST_AXW_DATA;
      end
      ENUM_ST_AXW_DATA: begin
        if (w_w_fire && i_axi_wlast)
          w_fsm_axw_nxt_state = ENUM_ST_AXW_RESP;
      end
      ENUM_ST_AXW_RESP: begin
        if (i_axi_bready)
          w_fsm_axw_nxt_state = ENUM_ST_AXW_IDLE;
      end
      default: w_fsm_axw_nxt_state = ENUM_ST_AXW_IDLE;
    endcase
  end

  // Part 3, combinational: Moore outputs of FSM axw (WREADY also follows the input path).
  always_comb begin : p_com_fsm_axw_out
    o_axi_awready = 1'b0;
    o_axi_wready  = 1'b0;
    o_axi_bvalid  = 1'b0;
    case (reg_fsm_axw_current_state)
      ENUM_ST_AXW_IDLE: o_axi_awready = reg_run;
      ENUM_ST_AXW_DATA: o_axi_wready  = reg_drop | i_beat_ready;
      ENUM_ST_AXW_RESP: o_axi_bvalid  = 1'b1;
      default:          o_axi_awready = 1'b0;
    endcase
  end

  // Beats of a legal burst go to the input stream, byte lane 0 first.
  assign o_beat_valid = (reg_fsm_axw_current_state == ENUM_ST_AXW_DATA) & ~reg_drop & i_axi_wvalid;
  assign o_beat_data  = {{(LPARA_BLK_W-PARA_AXI_DATA_W){1'b0}}, i_axi_wdata};
  assign o_axi_bid    = reg_awid;
  assign o_axi_bresp  = (reg_drop | reg_wmis) ? 2'(LPARA_RESP_SLVERR) : 2'(LPARA_RESP_OKAY);

  // Burst registers: ID, length, beat count, drop flag and WLAST mismatch.
  always_ff @(posedge i_clk_bus, negedge i_rst_n_bus) begin : p_ff_wburst
    if (!i_rst_n_bus) begin
      reg_awid  <= '0;
      reg_awlen <= '0;
      reg_wcnt  <= '0;
      reg_drop  <= 1'b0;
      reg_wmis  <= 1'b0;
    end else if (w_aw_fire) begin
      reg_awid  <= i_axi_awid;
      reg_awlen <= i_axi_awlen;
      reg_wcnt  <= '0;
      reg_drop  <= ~w_aw_legal;
      reg_wmis  <= 1'b0;
    end else if (w_w_fire) begin
      reg_wcnt <= reg_wcnt + 8'd1;
      if (i_axi_wlast != (reg_wcnt == reg_awlen))
        reg_wmis <= 1'b1;
    end
  end

  // ------------------------------------------------------------------- read window

  // Legality of the read burst, decoded in CHK.
  assign w_ar_legal = i_sel & i_axi_araddr[LPARA_WIN_BIT] & ~i_axi_arburst[1] &
                      (i_axi_arsize == 3'(LPARA_SIZE));
  assign w_ar_fire  = i_axi_arvalid & o_axi_arready;
  assign w_r_fire   = o_axi_rvalid & i_axi_rready;
  assign w_r_last   = (reg_rcnt == reg_arlen);

  // Part 1, sequential: FSM axr current state.
  always_ff @(posedge i_clk_bus, negedge i_rst_n_bus) begin : p_ff_fsm_axr
    if (!i_rst_n_bus)
      reg_fsm_axr_current_state <= ENUM_ST_AXR_IDLE;
    else
      reg_fsm_axr_current_state <= w_fsm_axr_nxt_state;
  end

  // Part 2, combinational: IDLE -> CHK on the address, CHK -> DATA or DROP, DATA and DROP ->
  // END on the last accepted beat, END -> IDLE; an invalid encoding returns to IDLE.
  always_comb begin : p_com_fsm_axr_nxt
    w_fsm_axr_nxt_state = reg_fsm_axr_current_state;
    case (reg_fsm_axr_current_state)
      ENUM_ST_AXR_IDLE: begin
        if (i_axi_arvalid)
          w_fsm_axr_nxt_state = ENUM_ST_AXR_CHK;
      end
      ENUM_ST_AXR_CHK: begin
        if (reg_ar_ok)
          w_fsm_axr_nxt_state = ENUM_ST_AXR_DATA;
        else
          w_fsm_axr_nxt_state = ENUM_ST_AXR_DROP;
      end
      ENUM_ST_AXR_DATA, ENUM_ST_AXR_DROP: begin
        if (w_r_fire && w_r_last)
          w_fsm_axr_nxt_state = ENUM_ST_AXR_END;
      end
      ENUM_ST_AXR_END: w_fsm_axr_nxt_state = ENUM_ST_AXR_IDLE;
      default:         w_fsm_axr_nxt_state = ENUM_ST_AXR_IDLE;
    endcase
  end

  // Part 3, combinational: Moore outputs of FSM axr (RVALID in DATA follows the stream).
  always_comb begin : p_com_fsm_axr_out
    o_axi_arready = 1'b0;
    o_axi_rvalid  = 1'b0;
    o_axi_rresp   = 2'(LPARA_RESP_OKAY);
    o_axi_rdata   = '0;
    case (reg_fsm_axr_current_state)
      ENUM_ST_AXR_IDLE: o_axi_arready = reg_run;
      ENUM_ST_AXR_DATA: begin
        o_axi_rvalid = i_obeat_valid;
        o_axi_rdata  = i_obeat_data[PARA_AXI_DATA_W-1:0];
      end
      ENUM_ST_AXR_DROP: begin
        o_axi_rvalid = 1'b1;
        o_axi_rresp  = 2'(LPARA_RESP_SLVERR);
      end
      default: o_axi_arready = 1'b0;
    endcase
  end

  // Read beat outputs.
  assign o_axi_rid     = reg_arid;
  assign o_axi_rlast   = w_r_last;
  assign o_obeat_ready = (reg_fsm_axr_current_state == ENUM_ST_AXR_DATA) & i_axi_rready;

  // Read burst registers.
  always_ff @(posedge i_clk_bus, negedge i_rst_n_bus) begin : p_ff_rburst
    if (!i_rst_n_bus) begin
      reg_arid  <= '0;
      reg_arlen <= '0;
      reg_rcnt  <= '0;
      reg_ar_ok <= 1'b0;
    end else if (w_ar_fire) begin
      reg_arid  <= i_axi_arid;
      reg_arlen <= i_axi_arlen;
      reg_rcnt  <= '0;
      reg_ar_ok <= w_ar_legal;
    end else if (w_r_fire) begin
      reg_rcnt <= reg_rcnt + 8'd1;
    end
  end

endmodule
