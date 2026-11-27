// -------------------------------------------------------------------------------------------------
// Project      : AES-GCM Accelerator - acceptance simulation testbench
// File         : tb_param_check_top.sv
// Description  : Elaboration tests TEST-025 and TEST-032 (REQ-PARAM-001, spec 8.3, DEC-019). Each
//                define selects one illegal parameter set of section 8.3 given to the
//                verification-only checker m_aesgcm_param_check; elaboration must stop with the
//                message of that rule. PC_LEGAL must elaborate without a message.
//                Example (one run per set, expected result in the comment):
//                  verilator --lint-only +define+PC_LANE5 m_aesgcm_param_check.sv \
//                            tb_param_check_top.sv --top-module tb_param_check_top   (error)
//   Sets: PC_LEGAL (no error) | PC_LANE5 | PC_POLICY3 | PC_ARCH3 | PC_DIGIT12 | PC_PIPE_ARCH0 |
//         PC_CTX5 | PC_DEPTH12 | PC_DEPTH512 | PC_DW48 | PC_ID9 | PC_AW11 | PC_CTXMODE_NOGCM
// -------------------------------------------------------------------------------------------------
`timescale 1ps/1ps

module tb_param_check_top;
`ifdef PC_LANE5
  localparam int L = 5, G = 1, P = 0, A = 1, D = 16, PI = 0, CM = 0, CN = 2, F = 16, W = 32, I = 4, AD = 16;
`elsif PC_POLICY3
  localparam int L = 1, G = 1, P = 3, A = 1, D = 16, PI = 0, CM = 0, CN = 2, F = 16, W = 32, I = 4, AD = 16;
`elsif PC_ARCH3
  localparam int L = 1, G = 1, P = 0, A = 3, D = 16, PI = 0, CM = 0, CN = 2, F = 16, W = 32, I = 4, AD = 16;
`elsif PC_DIGIT12
  localparam int L = 1, G = 1, P = 0, A = 0, D = 12, PI = 0, CM = 0, CN = 2, F = 16, W = 32, I = 4, AD = 16;
`elsif PC_PIPE_ARCH0
  localparam int L = 1, G = 1, P = 0, A = 0, D = 16, PI = 1, CM = 0, CN = 2, F = 16, W = 32, I = 4, AD = 16;
`elsif PC_CTX5
  localparam int L = 1, G = 1, P = 0, A = 1, D = 16, PI = 0, CM = 0, CN = 5, F = 16, W = 32, I = 4, AD = 16;
`elsif PC_DEPTH12
  localparam int L = 1, G = 1, P = 0, A = 1, D = 16, PI = 0, CM = 0, CN = 2, F = 12, W = 32, I = 4, AD = 16;
`elsif PC_DEPTH512
  localparam int L = 1, G = 1, P = 0, A = 1, D = 16, PI = 0, CM = 0, CN = 2, F = 512, W = 32, I = 4, AD = 16;
`elsif PC_DW48
  localparam int L = 1, G = 1, P = 0, A = 1, D = 16, PI = 0, CM = 0, CN = 2, F = 16, W = 48, I = 4, AD = 16;
`elsif PC_ID9
  localparam int L = 1, G = 1, P = 0, A = 1, D = 16, PI = 0, CM = 0, CN = 2, F = 16, W = 32, I = 9, AD = 16;
`elsif PC_AW11
  localparam int L = 1, G = 1, P = 0, A = 1, D = 16, PI = 0, CM = 0, CN = 2, F = 16, W = 32, I = 4, AD = 11;
`elsif PC_CTXMODE_NOGCM
  localparam int L = 1, G = 0, P = 0, A = 1, D = 16, PI = 0, CM = 1, CN = 2, F = 16, W = 32, I = 4, AD = 16;
`else
  localparam int L = 4, G = 1, P = 2, A = 2, D = 16, PI = 1, CM = 0, CN = 2, F = 16, W = 64, I = 4, AD = 16;
`endif

  m_aesgcm_param_check #(
    .PARA_AES_LANE_NUM   (L),
    .PARA_AES_GCM_EN     (G),
    .PARA_GCM_REL_POLICY (P),
    .PARA_GHASH_ARCH     (A),
    .PARA_GHASH_DIGIT_W  (D),
    .PARA_GHASH_PIPE     (PI),
    .PARA_GCM_CTX_MODE   (CM),
    .PARA_GCM_CTX_NUM    (CN),
    .PARA_KEY_SIDE_EN    (1),
    .PARA_CLK_ASYNC      (1),
    .PARA_FIFO_DEPTH     (F),
    .PARA_AXI_DATA_W     (W),
    .PARA_AXI_ID_W       (I),
    .PARA_AXI_ADDR_W     (AD)
  ) u_param_check ();

  initial begin
    $display("PARAM-CHECK: elaborated without error (expected only for PC_LEGAL)");
    $finish;
  end
endmodule
