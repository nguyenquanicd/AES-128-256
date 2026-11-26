/*
 * Project      : AES-GCM Accelerator
 * Author       : Nguyen Hung Quan and Claude (user)
 * AI Flow      : VLSIT RTL Generator AI Automation Flow
 * AI Flow Page : https://github.com/nguyenquanicd/VLSIT_RTL_Generator_AI_Model
 * Date         : 2026-11-25
 * Description  : Verification-only parameter checker of the AES-GCM accelerator (spec 8.3,
 *                REQ-PARAM-001). It stops elaboration with a message for every illegal parameter
 *                value or combination. Rule P14 keeps elaboration system tasks out of the design
 *                RTL, so this module is compiled only by the lint and simulation flows
 *                (filelist_check.f, testbenches), with the parameters of the wrapper under test
 *                (decision of the designer, 2026-11-25).
 */
`timescale 1ns/1ps

module m_aesgcm_param_check #(
  parameter logic [31:0] PARA_AES_LANE_NUM = 1,
  parameter logic [31:0] PARA_AES_GCM_EN = 1,
  parameter logic [31:0] PARA_GCM_REL_POLICY = 0,
  parameter logic [31:0] PARA_GHASH_ARCH = 1,
  parameter logic [31:0] PARA_GHASH_DIGIT_W = 16,
  parameter logic [31:0] PARA_GHASH_PIPE = 0,
  parameter logic [31:0] PARA_GCM_CTX_MODE = 0,
  parameter logic [31:0] PARA_GCM_CTX_NUM = 2,
  parameter logic [31:0] PARA_KEY_SIDE_EN = 0,
  parameter logic [31:0] PARA_CLK_ASYNC = 1,
  parameter logic [31:0] PARA_FIFO_DEPTH = 16,
  parameter logic [31:0] PARA_AXI_DATA_W = 32,
  parameter logic [31:0] PARA_AXI_ID_W = 4,
  parameter logic [31:0] PARA_AXI_ADDR_W = 16
) ();

  if ((PARA_AES_LANE_NUM < 1) || (PARA_AES_LANE_NUM > 4)) begin : gen_err_lane
    $error("PARA_AES_LANE_NUM must be 1 to 4");
  end
  if ((PARA_AES_GCM_EN > 1) || (PARA_KEY_SIDE_EN > 1) || (PARA_CLK_ASYNC > 1) ||
      (PARA_GHASH_PIPE > 1) || (PARA_GCM_CTX_MODE > 1)) begin : gen_err_flag
    $error("PARA_AES_GCM_EN, PARA_KEY_SIDE_EN, PARA_CLK_ASYNC, PARA_GHASH_PIPE, PARA_GCM_CTX_MODE: 0 or 1");
  end
  if (PARA_GCM_REL_POLICY > 2) begin : gen_err_policy
    $error("PARA_GCM_REL_POLICY must be 0, 1 or 2");
  end
  if (PARA_GHASH_ARCH > 2) begin : gen_err_arch
    $error("PARA_GHASH_ARCH must be 0, 1 or 2");
  end
  if ((PARA_GHASH_ARCH == 0) && (PARA_GHASH_DIGIT_W != 4) && (PARA_GHASH_DIGIT_W != 8) &&
      (PARA_GHASH_DIGIT_W != 16) && (PARA_GHASH_DIGIT_W != 32) &&
      (PARA_GHASH_DIGIT_W != 64)) begin : gen_err_digit
    $error("PARA_GHASH_DIGIT_W must be 4, 8, 16, 32 or 64 for PARA_GHASH_ARCH = 0");
  end
  if ((PARA_GHASH_PIPE == 1) && (PARA_GHASH_ARCH == 0)) begin : gen_err_pipe
    $error("PARA_GHASH_PIPE = 1 needs PARA_GHASH_ARCH = 1 or 2");
  end
  if (PARA_GCM_CTX_NUM > 4) begin : gen_err_ctx
    $error("PARA_GCM_CTX_NUM must be 0 to 4");
  end
  if ((PARA_FIFO_DEPTH < 8) || (PARA_FIFO_DEPTH > 256) ||
      ((PARA_FIFO_DEPTH & (PARA_FIFO_DEPTH - 1)) != 0)) begin : gen_err_depth
    $error("PARA_FIFO_DEPTH must be a power of two from 8 to 256");
  end
  if ((PARA_AXI_DATA_W != 32) && (PARA_AXI_DATA_W != 64) && (PARA_AXI_DATA_W != 128)) begin : gen_err_dw
    $error("PARA_AXI_DATA_W must be 32, 64 or 128");
  end
  if ((PARA_AXI_ID_W < 1) || (PARA_AXI_ID_W > 8) || (PARA_AXI_ADDR_W < 12) ||
      (PARA_AXI_ADDR_W > 32)) begin : gen_err_axi
    $error("PARA_AXI_ID_W must be 1 to 8 and PARA_AXI_ADDR_W 12 to 32");
  end
  if ((PARA_GCM_CTX_MODE == 1) && (PARA_AES_GCM_EN == 0)) begin : gen_err_ctx_mode
    $error("PARA_GCM_CTX_MODE = 1 needs PARA_AES_GCM_EN = 1");
  end

endmodule
