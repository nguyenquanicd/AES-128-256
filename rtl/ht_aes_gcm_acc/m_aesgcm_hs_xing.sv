/*
 * Project      : AES-GCM Accelerator
 * Author       : Nguyen Hung Quan and Claude (user)
 * AI Flow      : VLSIT RTL Generator AI Automation Flow
 * AI Flow Page : https://github.com/nguyenquanicd/VLSIT_RTL_Generator_AI_Model
 * Date         : 2026-11-25
 * Description  : Request and acknowledge crossing of one four-phase handshake (spec 7.2,
 *                CDC-001, CDC-002, CDC-005, CDC-007). PARA_CLK_ASYNC = 1 reuses the library
 *                handshake m_vlsit_ahs4_top (two-flop synchronizers, DEC-016); the payload stays
 *                in the holding register of the user, so the library carries one dummy bit.
 *                PARA_CLK_ASYNC = 0 (related clocks of any ratio, DEC-010) registers the request in
 *                the destination clock and the acknowledge in the source clock without
 *                synchronizer; the source rules equal those of the library: i_req is held until
 *                o_ack, and a new request is launched only after the acknowledge has fallen.
 * Deviation    : HIE-02 (SHOULD) - the synchronous branch holds four flags beside the generate
 *                choice of the library instance; a separate module would only rename them.
 * Decisions    : DEC-010, DEC-016, DEC-024 (spec section 20).
 */
`timescale 1ns/1ps

module m_aesgcm_hs_xing #(
  // Parameter Description: crossing structure; 1 = asynchronous clocks, 0 = related clocks.
  // Parameter values: 0 or 1; default is 1.
  // Parameter unit: none
  parameter logic [31:0] PARA_CLK_ASYNC = 1,
  // Two-flop synchronizer selection of the library handshake (PARA_AHS4_SYNC_TYPE).
  localparam logic [31:0] LPARA_SYNC_TYPE = 2
) (
  // Source clock and reset
  input  wire  i_clk_src,
  input  wire  i_rst_n_src,

  // Source request level and completion level
  input  wire  i_req,
  output logic o_ack,

  // Destination clock and reset
  input  wire  i_clk_dst,
  input  wire  i_rst_n_dst,

  // Destination request level and acknowledge level
  output logic o_req,
  input  wire  i_ack
);

  if (PARA_CLK_ASYNC == 1) begin : gen_async
    // Library four-phase handshake with synchronizers in both directions.
    logic w_ack_data_unused;
    logic w_data_unused;

    m_vlsit_ahs4_top #(
      .PARA_AHS4_DATA_W        (32'd1),
      .PARA_AHS4_SYNC_TYPE     (LPARA_SYNC_TYPE),
      .PARA_AHS4_DST_MODE      (32'd0),
      .PARA_AHS4_ACK_DATA_MODE (32'd0)
    ) u_ahs4 (
      .i_clk_src   (i_clk_src),
      .i_rst_n_src (i_rst_n_src),
      .i_req       (i_req),
      .i_data      (1'b0),
      .o_ack       (o_ack),
      .o_ack_data  (w_ack_data_unused),
      .i_clk_dst   (i_clk_dst),
      .i_rst_n_dst (i_rst_n_dst),
      .o_req       (o_req),
      .o_data      (w_data_unused),
      .i_ack       (i_ack),
      .i_ack_data  (1'b0)
    );
  end else begin : gen_sync
    // Related clocks: the request and the acknowledge are timed paths captured by one flop.
    logic reg_req;
    logic reg_ack;
    logic reg_ack_q;
    logic reg_req_q;
    logic w_launch;

    // Launch rule of the library source: no outstanding request and the acknowledge has fallen.
    assign w_launch = i_req & ~reg_req & ~reg_ack & ~reg_ack_q;
    assign o_ack    = reg_ack;
    assign o_req    = reg_req_q;

    // Source request flag: set at launch, cleared when the acknowledge is seen.
    always_ff @(posedge i_clk_src, negedge i_rst_n_src) begin : p_ff_src
      if (!i_rst_n_src) begin
        reg_req   <= 1'b0;
        reg_ack   <= 1'b0;
        reg_ack_q <= 1'b0;
      end else begin
        reg_ack_q <= i_ack;
        if (w_launch)
          reg_req <= 1'b1;
        else if (reg_ack_q)
          reg_req <= 1'b0;
        if (reg_req && reg_ack_q)
          reg_ack <= 1'b1;
        else if (!i_req)
          reg_ack <= 1'b0;
      end
    end

    // Destination copy of the request, one capturing edge of the destination clock.
    always_ff @(posedge i_clk_dst, negedge i_rst_n_dst) begin : p_ff_dst
      if (!i_rst_n_dst)
        reg_req_q <= 1'b0;
      else
        reg_req_q <= reg_req;
    end
  end

endmodule
