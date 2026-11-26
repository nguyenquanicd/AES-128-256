/*
 * Project      : AES-GCM Accelerator
 * Author       : Nguyen Hung Quan and Claude (user)
 * AI Flow      : VLSIT RTL Generator AI Automation Flow
 * AI Flow Page : https://github.com/nguyenquanicd/VLSIT_RTL_Generator_AI_Model
 * Date         : 2026-11-25
 * Description  : Reset synchronizer of one clock domain with the test-mode override (spec 7.3,
 *                16, REQ-DFT-001, RTL rule RST-02 and RST-04). The functional reset is asserted
 *                asynchronously and released synchronously by the library synchronizer
 *                m_vlsit_rst_sync; with i_dft_scan_mode = 1 both the synchronizer reset and the
 *                output are taken from i_dft_scan_rst_n through library multiplexer cells.
 * Decisions    : DEC-016 (spec section 20).
 */
`timescale 1ns/1ps

module m_aesgcm_rst_sync (
  // Destination clock
  input  wire  i_clk_dst,

  // Functional reset (asynchronous assertion)
  input  wire  i_rst_n_src,

  // Test-mode reset control
  input  wire  i_dft_scan_mode,
  input  wire  i_dft_scan_rst_n,

  // Synchronized reset of the destination domain
  output logic o_rst_n_dst
);

  // Internal signal declarations
  logic w_rst_n_in;
  logic w_rst_n_sync;

  // Test mode replaces the reset that drives the synchronizer flops, so that they are
  // controllable during scan.
  VLSIT_CELL_MUX2 u_dont_touch_rst_in_mux (
    .I0 (i_rst_n_src),
    .I1 (i_dft_scan_rst_n),
    .S  (i_dft_scan_mode),
    .Z  (w_rst_n_in)
  );

  // Asynchronous assertion, release after two destination clock edges.
  m_vlsit_rst_sync #(
    .PARA_RST_SYNC_TYPE (32'd2)
  ) u_rst_sync (
    .i_clk_dst   (i_clk_dst),
    .i_rst_n_src (w_rst_n_in),
    .o_rst_n_dst (w_rst_n_sync)
  );

  // Test mode bypasses the synchronizer so that the domain reset is directly controllable.
  VLSIT_CELL_MUX2 u_dont_touch_rst_out_mux (
    .I0 (w_rst_n_sync),
    .I1 (i_dft_scan_rst_n),
    .S  (i_dft_scan_mode),
    .Z  (o_rst_n_dst)
  );

endmodule
