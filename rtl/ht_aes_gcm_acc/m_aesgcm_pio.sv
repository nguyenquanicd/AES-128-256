/*
 * Project      : AES-GCM Accelerator
 * Author       : Nguyen Hung Quan and Claude (user)
 * AI Flow      : VLSIT RTL Generator AI Automation Flow
 * AI Flow Page : https://github.com/nguyenquanicd/VLSIT_RTL_Generator_AI_Model
 * Date         : 2026-11-25
 * Description  : APB programmed-I/O data path (spec 6.3.3, OP-012). A write of aesgcm_pio_din
 *                (register-event sideband of the generated CSR) pushes the stored word as one
 *                32-bit beat in the next clock; a read of aesgcm_pio_dout pops the head beat of
 *                the output stream, whose low word is presented as the read data. A write that
 *                the input path cannot take, a read of an empty output, or any access while the
 *                message uses the AXI window, is dropped and raises PROTO_ERR (ERR-005).
 */
`timescale 1ns/1ps

module m_aesgcm_pio #(
  localparam logic [31:0] LPARA_ADDR_W = 16,
  localparam logic [31:0] LPARA_WORD_W = 32,
  localparam logic [31:0] LPARA_BLK_W = 128,
  // Offsets of aesgcm_pio_din and aesgcm_pio_dout in the CSR workbook.
  localparam logic [31:0] LPARA_DIN_OFFSET = 32'h0000_009C,
  localparam logic [31:0] LPARA_DOUT_OFFSET = 32'h0000_00A0
) (
  // Clock and reset (BUS domain)
  input  wire                     i_clk_bus,
  input  wire                     i_rst_n_bus,

  // Register-event sideband and register values of the CSR
  input  wire                     i_reg_wr_en,
  input  wire  [LPARA_ADDR_W-1:0] i_reg_wr_addr,
  input  wire                     i_reg_rd_en,
  input  wire  [LPARA_ADDR_W-1:0] i_reg_rd_addr,
  input  wire  [LPARA_WORD_W-1:0] i_din,
  output logic [LPARA_WORD_W-1:0] o_dout,
  input  wire                     i_sel,

  // Input beat stream
  output logic                    o_beat_valid,
  input  wire                     i_beat_ready,
  output logic [LPARA_BLK_W-1:0]  o_beat_data,

  // Output beat stream
  input  wire                     i_obeat_valid,
  output logic                    o_obeat_ready,
  input  wire  [LPARA_BLK_W-1:0]  i_obeat_data,

  // Protocol error pulse
  output logic                    o_perr
);

  // Internal signal declarations
  logic reg_push;
  logic w_rd_hit;

  // The pushed word is the stored register value, available one clock after the write event.
  always_ff @(posedge i_clk_bus, negedge i_rst_n_bus) begin : p_ff_push
    if (!i_rst_n_bus)
      reg_push <= 1'b0;
    else
      reg_push <= i_reg_wr_en & (i_reg_wr_addr == LPARA_DIN_OFFSET[LPARA_ADDR_W-1:0]);
  end

  // Push and pop requests.
  assign w_rd_hit      = i_reg_rd_en & (i_reg_rd_addr == LPARA_DOUT_OFFSET[LPARA_ADDR_W-1:0]);
  assign o_beat_valid  = reg_push & i_sel;
  assign o_beat_data   = {{(LPARA_BLK_W-LPARA_WORD_W){1'b0}}, i_din};
  assign o_obeat_ready = w_rd_hit & i_sel & i_obeat_valid;
  assign o_dout        = (i_sel & i_obeat_valid) ? i_obeat_data[LPARA_WORD_W-1:0] : '0;

  // Dropped write or read.
  assign o_perr = (reg_push & ~(i_sel & i_beat_ready)) | (w_rd_hit & ~(i_sel & i_obeat_valid));

endmodule
