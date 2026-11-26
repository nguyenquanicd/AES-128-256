// -------------------------------------------------------------------------------------------------
// Project      : AES-GCM Accelerator - acceptance simulation testbench
// File         : tb_aesgcm_cfg.svh (included inside module tb_aesgcm_top)
// Description  : Build configuration of the testbench. Exactly one TB_CFG_* define selects the DUT
//                wrapper and the parameter set of spec section 8.2 / the task brief; single
//                parameters can be overridden with the TB_<NAME> defines listed below.
//                Source: VLSIT_AES_GCM_ACCELERATOR_HDS.md v0.1, sections 4, 8, 8.2 (no RTL used).
//
//   +define+TB_CFG_FULL    (default) m_aesgcm_acc_axi_top, lanes 4, GHASH ARCH 2, policy 2,
//                          CTX_NUM 2, CTX_MODE 0, KEY_SIDE 1, AXI DW 64, CLK_ASYNC 1  (build a)
//   +define+TB_CFG_LINK    m_aesgcm_acc_apb_top CFG-LINK: policy 1, ARCH 1, CTX_NUM 0, lanes 1,
//                          KEY_SIDE 0                                                  (build b)
//   +define+TB_CFG_MIN     m_aesgcm_acc_apb_top CFG-MIN: ARCH 0, DIGIT 8, policy 0, CTX_NUM 0,
//                          FIFO_DEPTH 8
//   +define+TB_CFG_EXPORT  m_aesgcm_acc_axi_top as CFG-FULL with PARA_GCM_CTX_MODE = 1
//   +define+TB_CFG_LEGACY  m_aesgcm_acc_apb_top with PARA_AES_GCM_EN = 0 (CFG-LEGACY, optional)
//   Overrides: TB_CLK_ASYNC=<0|1>, TB_GHASH_PIPE=<0|1>, TB_FIFO_DEPTH=<n>, TB_AXI_DATA_W=<32|64|128>,
//              TB_AES_LANE_NUM=<1..4>, TB_GCM_CTX_NUM=<0..4>
// -------------------------------------------------------------------------------------------------

`ifdef TB_CFG_LINK
  `define TB_APB_TOP
  `define TB_CFG_NAME "CFG-LINK"
  localparam int C_LANES0 = 1, C_GCM_EN = 1, C_POLICY = 1, C_ARCH = 1, C_DIGIT = 16, C_PIPE0 = 0;
  localparam int C_CTX_MODE = 0, C_CTX_NUM0 = 0, C_KEY_SIDE = 0, C_DEPTH0 = 16, C_DW0 = 32;
`elsif TB_CFG_MIN
  `define TB_APB_TOP
  `define TB_CFG_NAME "CFG-MIN"
  localparam int C_LANES0 = 1, C_GCM_EN = 1, C_POLICY = 0, C_ARCH = 0, C_DIGIT = 8, C_PIPE0 = 0;
  localparam int C_CTX_MODE = 0, C_CTX_NUM0 = 0, C_KEY_SIDE = 0, C_DEPTH0 = 8, C_DW0 = 32;
`elsif TB_CFG_LEGACY
  `define TB_APB_TOP
  `define TB_CFG_NAME "CFG-LEGACY"
  localparam int C_LANES0 = 1, C_GCM_EN = 0, C_POLICY = 0, C_ARCH = 1, C_DIGIT = 16, C_PIPE0 = 0;
  localparam int C_CTX_MODE = 0, C_CTX_NUM0 = 0, C_KEY_SIDE = 0, C_DEPTH0 = 16, C_DW0 = 32;
`elsif TB_CFG_EXPORT
  `define TB_CFG_NAME "CFG-EXPORT"
  localparam int C_LANES0 = 4, C_GCM_EN = 1, C_POLICY = 2, C_ARCH = 2, C_DIGIT = 16, C_PIPE0 = 0;
  localparam int C_CTX_MODE = 1, C_CTX_NUM0 = 1, C_KEY_SIDE = 1, C_DEPTH0 = 16, C_DW0 = 64;
`else
  `define TB_CFG_NAME "CFG-FULL"
  localparam int C_LANES0 = 4, C_GCM_EN = 1, C_POLICY = 2, C_ARCH = 2, C_DIGIT = 16, C_PIPE0 = 0;
  localparam int C_CTX_MODE = 0, C_CTX_NUM0 = 2, C_KEY_SIDE = 1, C_DEPTH0 = 16, C_DW0 = 64;
`endif

`ifdef TB_AES_LANE_NUM
  localparam int C_LANES = `TB_AES_LANE_NUM;
`else
  localparam int C_LANES = C_LANES0;
`endif
`ifdef TB_CLK_ASYNC
  localparam int C_ASYNC = `TB_CLK_ASYNC;
`else
  localparam int C_ASYNC = 1;
`endif
`ifdef TB_GHASH_PIPE
  localparam int C_PIPE = `TB_GHASH_PIPE;
`else
  localparam int C_PIPE = C_PIPE0;
`endif
`ifdef TB_FIFO_DEPTH
  localparam int C_DEPTH = `TB_FIFO_DEPTH;
`else
  localparam int C_DEPTH = C_DEPTH0;
`endif
`ifdef TB_AXI_DATA_W
  localparam int C_DW = `TB_AXI_DATA_W;
`else
  localparam int C_DW = C_DW0;
`endif
`ifdef TB_GCM_CTX_NUM
  localparam int C_CTX_NUM = `TB_GCM_CTX_NUM;
`else
  localparam int C_CTX_NUM = C_CTX_NUM0;
`endif

localparam int C_IW = 4;
localparam int C_AW = 16;
`ifdef TB_APB_TOP
  localparam int C_AXI = 0;
`else
  localparam int C_AXI = 1;
`endif

// Derived facts used by the tests (each from the specification).
localparam int C_BEAT_AXI = C_DW / 8;                      // bytes per AXI beat (spec 9.2)
localparam int C_BEAT_PIO = 4;                             // bytes per PIO word (spec 6.3.3)
localparam int C_HAS_PA = (C_GCM_EN == 1) && (C_POLICY != 1); // policy A built (FEAT-003)
localparam int C_HAS_PC = (C_GCM_EN == 1) && (C_POLICY != 0); // policy C built (FEAT-004)
localparam int C_HAS_SUSP = (C_GCM_EN == 1) && (C_CTX_NUM > 0); // suspend/resume (REQ-FUNC-010)
localparam int C_HAS_EXP = (C_GCM_EN == 1) && (C_CTX_MODE == 1); // export (REQ-FUNC-011)
localparam int C_DW_CODE = (C_DW == 32) ? 0 : ((C_DW == 64) ? 1 : 2);
// FIFO capacity in blocks = depth x lanes (spec 8, DEC-018).
localparam int C_FIFO_BLOCKS = C_DEPTH * C_LANES;
