/*
 * Project      : AES-GCM Accelerator
 * Author       : Nguyen Hung Quan and Claude (user)
 * AI Flow      : VLSIT RTL Generator AI Automation Flow
 * AI Flow Page : https://github.com/nguyenquanicd/VLSIT_RTL_Generator_AI_Model
 * Date         : 2026-11-25
 * Description  : AES-GCM accelerator wrapper with the AXI4 data window
 *                (spec 4, 5.1, 6.2, 14.2): reset synchronizers, generated CSR u_csr, BUS-domain
 *                structure u_bus_dom, crossings u_xing and CORE-domain structure u_core_dom.
 *                Structural top. Illegal parameter values are reported by the verification
 *                checker m_aesgcm_param_check (decision of 2026-11-25, rule P14).
 * Decisions    : DEC-016, DEC-019, DEC-020, DEC-024 (spec section 20).
 */
`timescale 1ns/1ps

module m_aesgcm_acc_axi_top #(
  // Parameter Description: number of 128-bit AES block lanes of the AES core.
  // Parameter values: 1 to 4; default is 1.
  // Parameter unit: lane
  parameter logic [31:0] PARA_AES_LANE_NUM = 1,
  // Parameter Description: 1 builds GHASH, tag, J0 and policy logic (mode code 5).
  // Parameter values: 0 or 1; default is 1.
  // Parameter unit: none
  parameter logic [31:0] PARA_AES_GCM_EN = 1,
  // Parameter Description: release policy; 0 policy A only, 1 policy C only, 2 both.
  // Parameter values: 0, 1 or 2; default is 0.
  // Parameter unit: none
  parameter logic [31:0] PARA_GCM_REL_POLICY = 0,
  // Parameter Description: GHASH architecture; 0 digit-serial, 1 single, 2 aggregated.
  // Parameter values: 0, 1 or 2; default is 1.
  // Parameter unit: none
  parameter logic [31:0] PARA_GHASH_ARCH = 1,
  // Parameter Description: bits per clock of the digit-serial multiplier.
  // Parameter values: 4, 8, 16, 32 or 64; default is 16.
  // Parameter unit: bit
  parameter logic [31:0] PARA_GHASH_DIGIT_W = 16,
  // Parameter Description: feed-forward pipeline stage of the parallel GHASH.
  // Parameter values: 0 or 1; default is 0.
  // Parameter unit: none
  parameter logic [31:0] PARA_GHASH_PIPE = 0,
  // Parameter Description: context storage; 0 internal slots, 1 export through the CSR.
  // Parameter values: 0 or 1; default is 0.
  // Parameter unit: none
  parameter logic [31:0] PARA_GCM_CTX_MODE = 0,
  // Parameter Description: number of internal context slots.
  // Parameter values: 0 to 4; default is 2.
  // Parameter unit: slot
  parameter logic [31:0] PARA_GCM_CTX_NUM = 2,
  // Parameter Description: 1 builds the key side-load path.
  // Parameter values: 0 or 1; default is 0.
  // Parameter unit: none
  parameter logic [31:0] PARA_KEY_SIDE_EN = 0,
  // Parameter Description: crossing structure; 1 asynchronous clocks, 0 related clocks.
  // Parameter values: 0 or 1; default is 1.
  // Parameter unit: none
  parameter logic [31:0] PARA_CLK_ASYNC = 1,
  // Parameter Description: depth of each data FIFO in entries of up to PARA_AES_LANE_NUM blocks.
  // Parameter values: 8, 16, 32, 64, 128 or 256; default is 16.
  // Parameter unit: entry
  parameter logic [31:0] PARA_FIFO_DEPTH = 16,
  // Parameter Description: AXI4 data width of the window.
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
  localparam logic [31:0] LPARA_KEY_W = 256,
  localparam logic [31:0] LPARA_WORD_W = 32,
  localparam logic [31:0] LPARA_CFG_W = 611,
  localparam logic [31:0] LPARA_CMD_W = 6,
  localparam logic [31:0] LPARA_STS_W = 322,
  localparam logic [31:0] LPARA_WREQ_W = 38,
  localparam logic [31:0] LPARA_WRSP_W = 37,
  localparam logic [31:0] LPARA_EVT_W = 10,
  localparam logic [31:0] LPARA_CTXX_NUM = 24,
  localparam logic [31:0] LPARA_THR_W = $clog2(PARA_FIFO_DEPTH) + 1,
  localparam logic [31:0] LPARA_ADDR_W = 16,
  localparam logic [31:0] LPARA_ENT_IN_W = PARA_AES_LANE_NUM * LPARA_BLK_W + PARA_AES_LANE_NUM + 2,
  localparam logic [31:0] LPARA_ENT_OUT_W = PARA_AES_LANE_NUM * LPARA_BLK_W + PARA_AES_LANE_NUM + 1,
  localparam logic [31:0] LPARA_PROT_W = 3,
  localparam logic [31:0] LPARA_PSTRB_W = 4,
  localparam logic [31:0] LPARA_STRB_W = PARA_AXI_DATA_W / 8,
  localparam logic [31:0] LPARA_AXI_EN = 1
) (
  // Clocks and resets
  input  wire                        i_clk_bus,
  input  wire                        i_rst_n_bus,
  input  wire                        i_clk_core,
  input  wire                        i_rst_n_core,

  // APB4 completer (IF-001) and static options (IF-007)
  input  wire                        i_apb_psel,
  input  wire                        i_apb_penable,
  input  wire                        i_apb_pwrite,
  input  wire  [LPARA_ADDR_W-1:0]    i_apb_paddr,
  input  wire  [LPARA_WORD_W-1:0]    i_apb_pwdata,
  input  wire  [LPARA_PSTRB_W-1:0]   i_apb_pstrb,
  input  wire  [LPARA_PROT_W-1:0]    i_apb_pprot,
  output logic                       o_apb_pready,
  output logic [LPARA_WORD_W-1:0]    o_apb_prdata,
  output logic                       o_apb_pslverr,
  input  wire                        i_protect_en,
  input  wire                        i_slverr_en,

  // Interrupt (IF-004) and DMA handshake (IF-003)
  output logic                       o_int_aesgcm,
  output logic                       o_dma_in_req,
  input  wire                        i_dma_in_ack,
  output logic                       o_dma_out_req,
  input  wire                        i_dma_out_ack,

  // Key side-load (IF-005)
  input  wire                        i_key_side_valid,
  input  wire                        i_key_side_size,
  input  wire  [LPARA_KEY_W-1:0]     i_key_side,
  output logic                       o_key_side_ack,

  // Secure-only pin (IF-006) and DFT (IF-008)
  input  wire                        i_gcm_secure_only,
  input  wire                        i_dft_scan_mode,
  input  wire                        i_dft_scan_rst_n,

  // AXI4 data window (IF-002)
  input  wire  [PARA_AXI_ID_W-1:0]   i_axi_awid,
  input  wire  [PARA_AXI_ADDR_W-1:0] i_axi_awaddr,
  input  wire  [7:0]                 i_axi_awlen,
  input  wire  [2:0]                 i_axi_awsize,
  input  wire  [1:0]                 i_axi_awburst,
  input  wire                        i_axi_awvalid,
  output logic                       o_axi_awready,
  input  wire  [PARA_AXI_DATA_W-1:0] i_axi_wdata,
  input  wire  [LPARA_STRB_W-1:0]    i_axi_wstrb,
  input  wire                        i_axi_wlast,
  input  wire                        i_axi_wvalid,
  output logic                       o_axi_wready,
  output logic [PARA_AXI_ID_W-1:0]   o_axi_bid,
  output logic [1:0]                 o_axi_bresp,
  output logic                       o_axi_bvalid,
  input  wire                        i_axi_bready,
  input  wire  [PARA_AXI_ID_W-1:0]   i_axi_arid,
  input  wire  [PARA_AXI_ADDR_W-1:0] i_axi_araddr,
  input  wire  [7:0]                 i_axi_arlen,
  input  wire  [2:0]                 i_axi_arsize,
  input  wire  [1:0]                 i_axi_arburst,
  input  wire                        i_axi_arvalid,
  output logic                       o_axi_arready,
  output logic [PARA_AXI_ID_W-1:0]   o_axi_rid,
  output logic [PARA_AXI_DATA_W-1:0] o_axi_rdata,
  output logic [1:0]                 o_axi_rresp,
  output logic                       o_axi_rlast,
  output logic                       o_axi_rvalid,
  input  wire                        i_axi_rready
);

  // Internal signal declarations
  logic                                   w_rst_n_bus;
  logic                                   w_rst_n_core;
  logic [4:0]                             w_b_beat_bytes;
  logic [LPARA_BLK_W-1:0]                 w_b_beat_data;
  logic                                   w_b_beat_ready;
  logic                                   w_b_beat_valid;
  logic [4:0]                             w_b_bpb;
  logic [2:0]                             w_b_bpe;
  logic [LPARA_CFG_W-1:0]                 w_b_cfg;
  logic                                   w_b_cfg_done;
  logic                                   w_b_cfg_idle;
  logic                                   w_b_cfg_send;
  logic [LPARA_CMD_W-1:0]                 w_b_cmd;
  logic                                   w_b_cmd_done;
  logic                                   w_b_cmd_idle;
  logic                                   w_b_cmd_send;
  logic [31:0]                            w_b_in_aad_len;
  logic                                   w_b_in_active;
  logic [31:0]                            w_b_in_data_len;
  logic                                   w_b_in_drop;
  logic                                   w_b_in_flush;
  logic                                   w_b_in_full;
  logic [LPARA_THR_W-1:0]                 w_b_in_full_thr;
  logic                                   w_b_in_full_thr_flag;
  logic                                   w_b_in_load;
  logic [LPARA_BLK_W-1:0]                 w_b_obeat_data;
  logic                                   w_b_obeat_ready;
  logic                                   w_b_obeat_valid;
  logic [8:0]                             w_b_out_burst_bytes;
  logic [31:0]                            w_b_out_data_len;
  logic                                   w_b_out_dma_cond;
  logic                                   w_b_out_empty;
  logic                                   w_b_out_flush;
  logic                                   w_b_out_load;
  logic                                   w_b_sec_only;
  logic [LPARA_STS_W-1:0]                 w_b_sts;
  logic                                   w_b_sts_valid;
  logic [LPARA_WREQ_W-1:0]                w_b_wreq;
  logic                                   w_b_wreq_done;
  logic                                   w_b_wreq_idle;
  logic                                   w_b_wreq_send;
  logic [LPARA_WRSP_W-1:0]                w_b_wrsp;
  logic                                   w_b_wrsp_valid;
  logic [LPARA_CFG_W-1:0]                 w_c_cfg;
  logic                                   w_c_cfg_clr;
  logic                                   w_c_cfg_valid;
  logic [LPARA_CMD_W-1:0]                 w_c_cmd;
  logic                                   w_c_cmd_valid;
  logic                                   w_c_in_empty;
  logic [LPARA_ENT_IN_W-1:0]              w_c_in_ent;
  logic                                   w_c_in_rd_en;
  logic [LPARA_ENT_OUT_W-1:0]             w_c_out_ent;
  logic                                   w_c_out_flush;
  logic                                   w_c_out_flush_busy;
  logic                                   w_c_out_full;
  logic                                   w_c_out_wr_en;
  logic                                   w_c_sec_only;
  logic [LPARA_STS_W-1:0]                 w_c_sts;
  logic                                   w_c_sts_idle;
  logic                                   w_c_sts_send;
  logic [LPARA_WREQ_W-1:0]                w_c_wreq;
  logic                                   w_c_wreq_valid;
  logic [LPARA_WRSP_W-1:0]                w_c_wrsp;
  logic                                   w_c_wrsp_idle;
  logic                                   w_c_wrsp_send;
  logic [31:0]                            w_r_aad_len;
  logic                                   w_r_cap_async;
  logic [1:0]                             w_r_cap_axi_dw;
  logic                                   w_r_cap_axi_en;
  logic                                   w_r_cap_ctx_exp;
  logic [2:0]                             w_r_cap_ctx_num;
  logic                                   w_r_cap_gcm_en;
  logic [1:0]                             w_r_cap_ghash;
  logic                                   w_r_cap_key_side;
  logic [2:0]                             w_r_cap_lanes;
  logic [1:0]                             w_r_cap_policy;
  logic [3:0]                             w_r_cfg_cfb_seg;
  logic [1:0]                             w_r_cfg_ctx_id;
  logic                                   w_r_cfg_dat_src;
  logic                                   w_r_cfg_decipher;
  logic [1:0]                             w_r_cfg_gcm_pass;
  logic                                   w_r_cfg_key_size;
  logic                                   w_r_cfg_key_src;
  logic [2:0]                             w_r_cfg_mode;
  logic [2:0]                             w_r_cfg_tag_len;
  logic [31:0]                            w_r_cons_a;
  logic [31:0]                            w_r_cons_d;
  logic [6:0]                             w_r_ctrl_clr;
  logic [6:0]                             w_r_ctrl_cmd;
  logic                                   w_r_ctrl_en;
  logic [LPARA_WORD_W-1:0]                w_r_ctxx_wdata;
  logic [LPARA_CTXX_NUM-1:0]              w_r_ctxx_we;
  logic [LPARA_CTXX_NUM*LPARA_WORD_W-1:0] w_r_ctxx_words;
  logic [31:0]                            w_r_data_len;
  logic [2:0]                             w_r_dma_in_burst;
  logic                                   w_r_dma_in_en;
  logic [2:0]                             w_r_dma_out_burst;
  logic                                   w_r_dma_out_en;
  logic [3:0]                             w_r_err_code;
  logic [3:0]                             w_r_err_core;
  logic [31:0]                            w_r_failcnt;
  logic                                   w_r_fifo_in_full;
  logic                                   w_r_fifo_out_empty;
  logic [LPARA_EVT_W-1:0]                 w_r_irq_en;
  logic [LPARA_EVT_W-1:0]                 w_r_irq_inj;
  logic [LPARA_EVT_W-1:0]                 w_r_irq_raw;
  logic [LPARA_EVT_W-1:0]                 w_r_irq_set;
  logic [LPARA_EVT_W-1:0]                 w_r_irq_sts;
  logic [LPARA_BLK_W-1:0]                 w_r_iv_words;
  logic                                   w_r_key_clr;
  logic [LPARA_KEY_W-1:0]                 w_r_key_words;
  logic [15:0]                            w_r_keywait;
  logic [LPARA_WORD_W-1:0]                w_r_pio_din;
  logic [LPARA_WORD_W-1:0]                w_r_pio_dout;
  logic [LPARA_ADDR_W-1:0]                w_r_reg_rd_addr;
  logic                                   w_r_reg_rd_en;
  logic [LPARA_ADDR_W-1:0]                w_r_reg_wr_addr;
  logic                                   w_r_reg_wr_en;
  logic                                   w_r_sts_busy;
  logic [3:0]                             w_r_sts_ctx_vld;
  logic                                   w_r_sts_key_ld;
  logic [3:0]                             w_r_sts_phase;
  logic                                   w_r_sts_sec_only;
  logic                                   w_r_sts_tag_ok;
  logic                                   w_r_sts_ver_ok;
  logic                                   w_r_sts_zeroized;
  logic [LPARA_BLK_W-1:0]                 w_r_tagin_words;
  logic [LPARA_BLK_W-1:0]                 w_r_tagout_words;
  logic [15:0]                            w_r_ver_major;
  logic [15:0]                            w_r_ver_minor;

  // Reset synchronizer of the BUS domain with the test-mode override.
  m_aesgcm_rst_sync u_rst_sync_bus (
    .i_clk_dst        (i_clk_bus),
    .i_rst_n_src      (i_rst_n_bus),
    .i_dft_scan_mode  (i_dft_scan_mode),
    .i_dft_scan_rst_n (i_dft_scan_rst_n),
    .o_rst_n_dst      (w_rst_n_bus)
  );


  // Reset synchronizer of the CORE domain with the test-mode override.
  m_aesgcm_rst_sync u_rst_sync_core (
    .i_clk_dst        (i_clk_core),
    .i_rst_n_src      (i_rst_n_core),
    .i_dft_scan_mode  (i_dft_scan_mode),
    .i_dft_scan_rst_n (i_dft_scan_rst_n),
    .o_rst_n_dst      (w_rst_n_core)
  );


  // Generated APB CSR (workbook aesgcm_CSR.xlsx), register clock = APB clock.
  m_vlsit_csr_aesgcm #(
    .PARA_ASYNCHRONOUS (32'd0)
  ) u_csr (
    .i_clk_apb                      (i_clk_bus),
    .i_rst_n_apb                    (w_rst_n_bus),
    .i_clk_reg                      (i_clk_bus),
    .i_rst_n_reg                    (w_rst_n_bus),
    .i_apb_psel                     (i_apb_psel),
    .i_apb_penable                  (i_apb_penable),
    .i_apb_pwrite                   (i_apb_pwrite),
    .i_apb_paddr                    (i_apb_paddr),
    .i_apb_pwdata                   (i_apb_pwdata),
    .i_apb_pstrb                    (i_apb_pstrb),
    .i_apb_pprot                    (i_apb_pprot),
    .o_apb_pready                   (o_apb_pready),
    .o_apb_pslverr                  (o_apb_pslverr),
    .o_apb_prdata                   (o_apb_prdata),
    .i_protect_en                   (i_protect_en),
    .i_slverr_en                    (i_slverr_en),
    .o_reg_rd_en                    (w_r_reg_rd_en),
    .o_reg_rd_addr                  (w_r_reg_rd_addr),
    .o_reg_wr_en                    (w_r_reg_wr_en),
    .o_reg_wr_addr                  (w_r_reg_wr_addr),
    .i_aesgcm_version_major         (w_r_ver_major),
    .i_aesgcm_version_minor         (w_r_ver_minor),
    .i_aesgcm_cap_axi_dw            (w_r_cap_axi_dw),
    .i_aesgcm_cap_ghash             (w_r_cap_ghash),
    .i_aesgcm_cap_lanes             (w_r_cap_lanes),
    .i_aesgcm_cap_ctx_num           (w_r_cap_ctx_num),
    .i_aesgcm_cap_ctx_exp           (w_r_cap_ctx_exp),
    .i_aesgcm_cap_policy            (w_r_cap_policy),
    .i_aesgcm_cap_async             (w_r_cap_async),
    .i_aesgcm_cap_key_side          (w_r_cap_key_side),
    .i_aesgcm_cap_axi_en            (w_r_cap_axi_en),
    .i_aesgcm_cap_gcm_en            (w_r_cap_gcm_en),
    .o_aesgcm_ctrl_en               (w_r_ctrl_en),
    .o_aesgcm_ctrl_free             (w_r_ctrl_cmd[6]),
    .i_hw_wdata_aesgcm_ctrl_free    (1'b0),
    .i_hw_we_aesgcm_ctrl_free       (w_r_ctrl_clr[6]),
    .o_aesgcm_ctrl_key_new          (w_r_ctrl_cmd[5]),
    .i_hw_wdata_aesgcm_ctrl_key_new (1'b0),
    .i_hw_we_aesgcm_ctrl_key_new    (w_r_ctrl_clr[5]),
    .o_aesgcm_ctrl_resume           (w_r_ctrl_cmd[4]),
    .i_hw_wdata_aesgcm_ctrl_resume  (1'b0),
    .i_hw_we_aesgcm_ctrl_resume     (w_r_ctrl_clr[4]),
    .o_aesgcm_ctrl_suspend          (w_r_ctrl_cmd[3]),
    .i_hw_wdata_aesgcm_ctrl_suspend (1'b0),
    .i_hw_we_aesgcm_ctrl_suspend    (w_r_ctrl_clr[3]),
    .o_aesgcm_ctrl_zeroize          (w_r_ctrl_cmd[2]),
    .i_hw_wdata_aesgcm_ctrl_zeroize (1'b0),
    .i_hw_we_aesgcm_ctrl_zeroize    (w_r_ctrl_clr[2]),
    .o_aesgcm_ctrl_abort            (w_r_ctrl_cmd[1]),
    .i_hw_wdata_aesgcm_ctrl_abort   (1'b0),
    .i_hw_we_aesgcm_ctrl_abort      (w_r_ctrl_clr[1]),
    .o_aesgcm_ctrl_start            (w_r_ctrl_cmd[0]),
    .i_hw_wdata_aesgcm_ctrl_start   (1'b0),
    .i_hw_we_aesgcm_ctrl_start      (w_r_ctrl_clr[0]),
    .o_aesgcm_cfg_ctx_id            (w_r_cfg_ctx_id),
    .o_aesgcm_cfg_tag_len           (w_r_cfg_tag_len),
    .o_aesgcm_cfg_cfb_seg           (w_r_cfg_cfb_seg),
    .o_aesgcm_cfg_gcm_pass          (w_r_cfg_gcm_pass),
    .o_aesgcm_cfg_dat_src           (w_r_cfg_dat_src),
    .o_aesgcm_cfg_key_src           (w_r_cfg_key_src),
    .o_aesgcm_cfg_key_size          (w_r_cfg_key_size),
    .o_aesgcm_cfg_decipher          (w_r_cfg_decipher),
    .o_aesgcm_cfg_mode              (w_r_cfg_mode),
    .o_aesgcm_aadlen_len            (w_r_aad_len),
    .o_aesgcm_datalen_len           (w_r_data_len),
    .o_aesgcm_keywait_clks          (w_r_keywait),
    .o_aesgcm_key_0_key             (w_r_key_words[31:0]),
    .i_hw_clr_aesgcm_key_0_key      (w_r_key_clr),
    .o_aesgcm_key_1_key             (w_r_key_words[63:32]),
    .i_hw_clr_aesgcm_key_1_key      (w_r_key_clr),
    .o_aesgcm_key_2_key             (w_r_key_words[95:64]),
    .i_hw_clr_aesgcm_key_2_key      (w_r_key_clr),
    .o_aesgcm_key_3_key             (w_r_key_words[127:96]),
    .i_hw_clr_aesgcm_key_3_key      (w_r_key_clr),
    .o_aesgcm_key_4_key             (w_r_key_words[159:128]),
    .i_hw_clr_aesgcm_key_4_key      (w_r_key_clr),
    .o_aesgcm_key_5_key             (w_r_key_words[191:160]),
    .i_hw_clr_aesgcm_key_5_key      (w_r_key_clr),
    .o_aesgcm_key_6_key             (w_r_key_words[223:192]),
    .i_hw_clr_aesgcm_key_6_key      (w_r_key_clr),
    .o_aesgcm_key_7_key             (w_r_key_words[255:224]),
    .i_hw_clr_aesgcm_key_7_key      (w_r_key_clr),
    .o_aesgcm_iv_0_iv               (w_r_iv_words[31:0]),
    .o_aesgcm_iv_1_iv               (w_r_iv_words[63:32]),
    .o_aesgcm_iv_2_iv               (w_r_iv_words[95:64]),
    .o_aesgcm_iv_3_iv               (w_r_iv_words[127:96]),
    .o_aesgcm_tagin_0_tag           (w_r_tagin_words[31:0]),
    .o_aesgcm_tagin_1_tag           (w_r_tagin_words[63:32]),
    .o_aesgcm_tagin_2_tag           (w_r_tagin_words[95:64]),
    .o_aesgcm_tagin_3_tag           (w_r_tagin_words[127:96]),
    .i_aesgcm_tagout_0_tag          (w_r_tagout_words[31:0]),
    .i_aesgcm_tagout_1_tag          (w_r_tagout_words[63:32]),
    .i_aesgcm_tagout_2_tag          (w_r_tagout_words[95:64]),
    .i_aesgcm_tagout_3_tag          (w_r_tagout_words[127:96]),
    .i_aesgcm_sts_ctx_vld           (w_r_sts_ctx_vld),
    .i_aesgcm_sts_phase             (w_r_sts_phase),
    .i_aesgcm_sts_key_ld            (w_r_sts_key_ld),
    .i_aesgcm_sts_sec_only          (w_r_sts_sec_only),
    .i_aesgcm_sts_zeroized          (w_r_sts_zeroized),
    .i_aesgcm_sts_ver_ok            (w_r_sts_ver_ok),
    .i_aesgcm_sts_tag_ok            (w_r_sts_tag_ok),
    .i_aesgcm_sts_busy              (w_r_sts_busy),
    .i_aesgcm_fifosts_out_empty     (w_r_fifo_out_empty),
    .i_aesgcm_fifosts_in_full       (w_r_fifo_in_full),
    .o_aesgcm_irq_raw_perr          (w_r_irq_raw[9]),
    .i_hw_wdata_aesgcm_irq_raw_perr (1'b1),
    .i_hw_we_aesgcm_irq_raw_perr    (w_r_irq_set[9]),
    .o_aesgcm_irq_raw_kerr          (w_r_irq_raw[8]),
    .i_hw_wdata_aesgcm_irq_raw_kerr (1'b1),
    .i_hw_we_aesgcm_irq_raw_kerr    (w_r_irq_set[8]),
    .o_aesgcm_irq_raw_cswd          (w_r_irq_raw[7]),
    .i_hw_wdata_aesgcm_irq_raw_cswd (1'b1),
    .i_hw_we_aesgcm_irq_raw_cswd    (w_r_irq_set[7]),
    .o_aesgcm_irq_raw_dour          (w_r_irq_raw[6]),
    .i_hw_wdata_aesgcm_irq_raw_dour (1'b1),
    .i_hw_we_aesgcm_irq_raw_dour    (w_r_irq_set[6]),
    .o_aesgcm_irq_raw_dinr          (w_r_irq_raw[5]),
    .i_hw_wdata_aesgcm_irq_raw_dinr (1'b1),
    .i_hw_we_aesgcm_irq_raw_dinr    (w_r_irq_set[5]),
    .o_aesgcm_irq_raw_cexh          (w_r_irq_raw[4]),
    .i_hw_wdata_aesgcm_irq_raw_cexh (1'b1),
    .i_hw_we_aesgcm_irq_raw_cexh    (w_r_irq_set[4]),
    .o_aesgcm_irq_raw_lerr          (w_r_irq_raw[3]),
    .i_hw_wdata_aesgcm_irq_raw_lerr (1'b1),
    .i_hw_we_aesgcm_irq_raw_lerr    (w_r_irq_set[3]),
    .o_aesgcm_irq_raw_cerr          (w_r_irq_raw[2]),
    .i_hw_wdata_aesgcm_irq_raw_cerr (1'b1),
    .i_hw_we_aesgcm_irq_raw_cerr    (w_r_irq_set[2]),
    .o_aesgcm_irq_raw_tagf          (w_r_irq_raw[1]),
    .i_hw_wdata_aesgcm_irq_raw_tagf (1'b1),
    .i_hw_we_aesgcm_irq_raw_tagf    (w_r_irq_set[1]),
    .o_aesgcm_irq_raw_done          (w_r_irq_raw[0]),
    .i_hw_wdata_aesgcm_irq_raw_done (1'b1),
    .i_hw_we_aesgcm_irq_raw_done    (w_r_irq_set[0]),
    .o_aesgcm_irq_en_perr           (w_r_irq_en[9]),
    .o_aesgcm_irq_en_kerr           (w_r_irq_en[8]),
    .o_aesgcm_irq_en_cswd           (w_r_irq_en[7]),
    .o_aesgcm_irq_en_dour           (w_r_irq_en[6]),
    .o_aesgcm_irq_en_dinr           (w_r_irq_en[5]),
    .o_aesgcm_irq_en_cexh           (w_r_irq_en[4]),
    .o_aesgcm_irq_en_lerr           (w_r_irq_en[3]),
    .o_aesgcm_irq_en_cerr           (w_r_irq_en[2]),
    .o_aesgcm_irq_en_tagf           (w_r_irq_en[1]),
    .o_aesgcm_irq_en_done           (w_r_irq_en[0]),
    .o_aesgcm_irq_inj_perr          (w_r_irq_inj[9]),
    .o_aesgcm_irq_inj_kerr          (w_r_irq_inj[8]),
    .o_aesgcm_irq_inj_cswd          (w_r_irq_inj[7]),
    .o_aesgcm_irq_inj_dour          (w_r_irq_inj[6]),
    .o_aesgcm_irq_inj_dinr          (w_r_irq_inj[5]),
    .o_aesgcm_irq_inj_cexh          (w_r_irq_inj[4]),
    .o_aesgcm_irq_inj_lerr          (w_r_irq_inj[3]),
    .o_aesgcm_irq_inj_cerr          (w_r_irq_inj[2]),
    .o_aesgcm_irq_inj_tagf          (w_r_irq_inj[1]),
    .o_aesgcm_irq_inj_done          (w_r_irq_inj[0]),
    .i_aesgcm_irq_sts_perr          (w_r_irq_sts[9]),
    .i_aesgcm_irq_sts_kerr          (w_r_irq_sts[8]),
    .i_aesgcm_irq_sts_cswd          (w_r_irq_sts[7]),
    .i_aesgcm_irq_sts_dour          (w_r_irq_sts[6]),
    .i_aesgcm_irq_sts_dinr          (w_r_irq_sts[5]),
    .i_aesgcm_irq_sts_cexh          (w_r_irq_sts[4]),
    .i_aesgcm_irq_sts_lerr          (w_r_irq_sts[3]),
    .i_aesgcm_irq_sts_cerr          (w_r_irq_sts[2]),
    .i_aesgcm_irq_sts_tagf          (w_r_irq_sts[1]),
    .i_aesgcm_irq_sts_done          (w_r_irq_sts[0]),
    .i_aesgcm_err_code_core         (w_r_err_core),
    .i_aesgcm_err_code_code         (w_r_err_code),
    .i_aesgcm_failcnt_cnt           (w_r_failcnt),
    .o_aesgcm_dmacfg_out_burst      (w_r_dma_out_burst),
    .o_aesgcm_dmacfg_in_burst       (w_r_dma_in_burst),
    .o_aesgcm_dmacfg_out_en         (w_r_dma_out_en),
    .o_aesgcm_dmacfg_in_en          (w_r_dma_in_en),
    .o_aesgcm_pio_din_data          (w_r_pio_din),
    .i_aesgcm_pio_dout_data         (w_r_pio_dout),
    .i_aesgcm_ctx_cons_a_bytes      (w_r_cons_a),
    .i_aesgcm_ctx_cons_d_bytes      (w_r_cons_d),
    .o_aesgcm_ctxx_0_word           (w_r_ctxx_words[31:0]),
    .i_hw_wdata_aesgcm_ctxx_0_word  (w_r_ctxx_wdata),
    .i_hw_we_aesgcm_ctxx_0_word     (w_r_ctxx_we[0]),
    .o_aesgcm_ctxx_1_word           (w_r_ctxx_words[63:32]),
    .i_hw_wdata_aesgcm_ctxx_1_word  (w_r_ctxx_wdata),
    .i_hw_we_aesgcm_ctxx_1_word     (w_r_ctxx_we[1]),
    .o_aesgcm_ctxx_2_word           (w_r_ctxx_words[95:64]),
    .i_hw_wdata_aesgcm_ctxx_2_word  (w_r_ctxx_wdata),
    .i_hw_we_aesgcm_ctxx_2_word     (w_r_ctxx_we[2]),
    .o_aesgcm_ctxx_3_word           (w_r_ctxx_words[127:96]),
    .i_hw_wdata_aesgcm_ctxx_3_word  (w_r_ctxx_wdata),
    .i_hw_we_aesgcm_ctxx_3_word     (w_r_ctxx_we[3]),
    .o_aesgcm_ctxx_4_word           (w_r_ctxx_words[159:128]),
    .i_hw_wdata_aesgcm_ctxx_4_word  (w_r_ctxx_wdata),
    .i_hw_we_aesgcm_ctxx_4_word     (w_r_ctxx_we[4]),
    .o_aesgcm_ctxx_5_word           (w_r_ctxx_words[191:160]),
    .i_hw_wdata_aesgcm_ctxx_5_word  (w_r_ctxx_wdata),
    .i_hw_we_aesgcm_ctxx_5_word     (w_r_ctxx_we[5]),
    .o_aesgcm_ctxx_6_word           (w_r_ctxx_words[223:192]),
    .i_hw_wdata_aesgcm_ctxx_6_word  (w_r_ctxx_wdata),
    .i_hw_we_aesgcm_ctxx_6_word     (w_r_ctxx_we[6]),
    .o_aesgcm_ctxx_7_word           (w_r_ctxx_words[255:224]),
    .i_hw_wdata_aesgcm_ctxx_7_word  (w_r_ctxx_wdata),
    .i_hw_we_aesgcm_ctxx_7_word     (w_r_ctxx_we[7]),
    .o_aesgcm_ctxx_8_word           (w_r_ctxx_words[287:256]),
    .i_hw_wdata_aesgcm_ctxx_8_word  (w_r_ctxx_wdata),
    .i_hw_we_aesgcm_ctxx_8_word     (w_r_ctxx_we[8]),
    .o_aesgcm_ctxx_9_word           (w_r_ctxx_words[319:288]),
    .i_hw_wdata_aesgcm_ctxx_9_word  (w_r_ctxx_wdata),
    .i_hw_we_aesgcm_ctxx_9_word     (w_r_ctxx_we[9]),
    .o_aesgcm_ctxx_10_word          (w_r_ctxx_words[351:320]),
    .i_hw_wdata_aesgcm_ctxx_10_word (w_r_ctxx_wdata),
    .i_hw_we_aesgcm_ctxx_10_word    (w_r_ctxx_we[10]),
    .o_aesgcm_ctxx_11_word          (w_r_ctxx_words[383:352]),
    .i_hw_wdata_aesgcm_ctxx_11_word (w_r_ctxx_wdata),
    .i_hw_we_aesgcm_ctxx_11_word    (w_r_ctxx_we[11]),
    .o_aesgcm_ctxx_12_word          (w_r_ctxx_words[415:384]),
    .i_hw_wdata_aesgcm_ctxx_12_word (w_r_ctxx_wdata),
    .i_hw_we_aesgcm_ctxx_12_word    (w_r_ctxx_we[12]),
    .o_aesgcm_ctxx_13_word          (w_r_ctxx_words[447:416]),
    .i_hw_wdata_aesgcm_ctxx_13_word (w_r_ctxx_wdata),
    .i_hw_we_aesgcm_ctxx_13_word    (w_r_ctxx_we[13]),
    .o_aesgcm_ctxx_14_word          (w_r_ctxx_words[479:448]),
    .i_hw_wdata_aesgcm_ctxx_14_word (w_r_ctxx_wdata),
    .i_hw_we_aesgcm_ctxx_14_word    (w_r_ctxx_we[14]),
    .o_aesgcm_ctxx_15_word          (w_r_ctxx_words[511:480]),
    .i_hw_wdata_aesgcm_ctxx_15_word (w_r_ctxx_wdata),
    .i_hw_we_aesgcm_ctxx_15_word    (w_r_ctxx_we[15]),
    .o_aesgcm_ctxx_16_word          (w_r_ctxx_words[543:512]),
    .i_hw_wdata_aesgcm_ctxx_16_word (w_r_ctxx_wdata),
    .i_hw_we_aesgcm_ctxx_16_word    (w_r_ctxx_we[16]),
    .o_aesgcm_ctxx_17_word          (w_r_ctxx_words[575:544]),
    .i_hw_wdata_aesgcm_ctxx_17_word (w_r_ctxx_wdata),
    .i_hw_we_aesgcm_ctxx_17_word    (w_r_ctxx_we[17]),
    .o_aesgcm_ctxx_18_word          (w_r_ctxx_words[607:576]),
    .i_hw_wdata_aesgcm_ctxx_18_word (w_r_ctxx_wdata),
    .i_hw_we_aesgcm_ctxx_18_word    (w_r_ctxx_we[18]),
    .o_aesgcm_ctxx_19_word          (w_r_ctxx_words[639:608]),
    .i_hw_wdata_aesgcm_ctxx_19_word (w_r_ctxx_wdata),
    .i_hw_we_aesgcm_ctxx_19_word    (w_r_ctxx_we[19]),
    .o_aesgcm_ctxx_20_word          (w_r_ctxx_words[671:640]),
    .i_hw_wdata_aesgcm_ctxx_20_word (w_r_ctxx_wdata),
    .i_hw_we_aesgcm_ctxx_20_word    (w_r_ctxx_we[20]),
    .o_aesgcm_ctxx_21_word          (w_r_ctxx_words[703:672]),
    .i_hw_wdata_aesgcm_ctxx_21_word (w_r_ctxx_wdata),
    .i_hw_we_aesgcm_ctxx_21_word    (w_r_ctxx_we[21]),
    .o_aesgcm_ctxx_22_word          (w_r_ctxx_words[735:704]),
    .i_hw_wdata_aesgcm_ctxx_22_word (w_r_ctxx_wdata),
    .i_hw_we_aesgcm_ctxx_22_word    (w_r_ctxx_we[22]),
    .o_aesgcm_ctxx_23_word          (w_r_ctxx_words[767:736]),
    .i_hw_wdata_aesgcm_ctxx_23_word (w_r_ctxx_wdata),
    .i_hw_we_aesgcm_ctxx_23_word    (w_r_ctxx_we[23])
  );


  // BUS-domain structure.
  m_aesgcm_bus_dom #(
    .PARA_AES_LANE_NUM   (PARA_AES_LANE_NUM),
    .PARA_AES_GCM_EN     (PARA_AES_GCM_EN),
    .PARA_GCM_REL_POLICY (PARA_GCM_REL_POLICY),
    .PARA_GHASH_ARCH     (PARA_GHASH_ARCH),
    .PARA_GCM_CTX_MODE   (PARA_GCM_CTX_MODE),
    .PARA_GCM_CTX_NUM    (PARA_GCM_CTX_NUM),
    .PARA_KEY_SIDE_EN    (PARA_KEY_SIDE_EN),
    .PARA_CLK_ASYNC      (PARA_CLK_ASYNC),
    .PARA_FIFO_DEPTH     (PARA_FIFO_DEPTH),
    .PARA_AXI_EN         (LPARA_AXI_EN),
    .PARA_AXI_DATA_W     (PARA_AXI_DATA_W),
    .PARA_AXI_ID_W       (PARA_AXI_ID_W),
    .PARA_AXI_ADDR_W     (PARA_AXI_ADDR_W)
  ) u_bus_dom (
    .i_clk_bus         (i_clk_bus),
    .i_rst_n_bus       (w_rst_n_bus),
    .o_ver_major       (w_r_ver_major),
    .o_ver_minor       (w_r_ver_minor),
    .o_cap_axi_dw      (w_r_cap_axi_dw),
    .o_cap_ghash       (w_r_cap_ghash),
    .o_cap_lanes       (w_r_cap_lanes),
    .o_cap_ctx_num     (w_r_cap_ctx_num),
    .o_cap_ctx_exp     (w_r_cap_ctx_exp),
    .o_cap_policy      (w_r_cap_policy),
    .o_cap_async       (w_r_cap_async),
    .o_cap_key_side    (w_r_cap_key_side),
    .o_cap_axi_en      (w_r_cap_axi_en),
    .o_cap_gcm_en      (w_r_cap_gcm_en),
    .i_ctrl_en         (w_r_ctrl_en),
    .i_ctrl_cmd        (w_r_ctrl_cmd),
    .o_ctrl_clr        (w_r_ctrl_clr),
    .i_cfg_mode        (w_r_cfg_mode),
    .i_cfg_decipher    (w_r_cfg_decipher),
    .i_cfg_key_size    (w_r_cfg_key_size),
    .i_cfg_key_src     (w_r_cfg_key_src),
    .i_cfg_dat_src     (w_r_cfg_dat_src),
    .i_cfg_gcm_pass    (w_r_cfg_gcm_pass),
    .i_cfg_tag_len     (w_r_cfg_tag_len),
    .i_cfg_cfb_seg     (w_r_cfg_cfb_seg),
    .i_cfg_ctx_id      (w_r_cfg_ctx_id),
    .i_aad_len         (w_r_aad_len),
    .i_data_len        (w_r_data_len),
    .i_keywait         (w_r_keywait),
    .i_key_words       (w_r_key_words),
    .i_iv_words        (w_r_iv_words),
    .i_tagin_words     (w_r_tagin_words),
    .o_key_clr         (w_r_key_clr),
    .o_tagout_words    (w_r_tagout_words),
    .o_sts_busy        (w_r_sts_busy),
    .o_sts_tag_ok      (w_r_sts_tag_ok),
    .o_sts_ver_ok      (w_r_sts_ver_ok),
    .o_sts_zeroized    (w_r_sts_zeroized),
    .o_sts_sec_only    (w_r_sts_sec_only),
    .o_sts_key_ld      (w_r_sts_key_ld),
    .o_sts_phase       (w_r_sts_phase),
    .o_sts_ctx_vld     (w_r_sts_ctx_vld),
    .o_err_code        (w_r_err_code),
    .o_err_core        (w_r_err_core),
    .o_failcnt         (w_r_failcnt),
    .o_cons_a          (w_r_cons_a),
    .o_cons_d          (w_r_cons_d),
    .o_fifo_in_full    (w_r_fifo_in_full),
    .o_fifo_out_empty  (w_r_fifo_out_empty),
    .i_irq_raw         (w_r_irq_raw),
    .o_irq_set         (w_r_irq_set),
    .i_irq_en          (w_r_irq_en),
    .i_irq_inj         (w_r_irq_inj),
    .o_irq_sts         (w_r_irq_sts),
    .o_int             (o_int_aesgcm),
    .i_dma_in_en       (w_r_dma_in_en),
    .i_dma_out_en      (w_r_dma_out_en),
    .i_dma_in_burst    (w_r_dma_in_burst),
    .i_dma_out_burst   (w_r_dma_out_burst),
    .i_ctxx_words      (w_r_ctxx_words),
    .o_ctxx_we         (w_r_ctxx_we),
    .o_ctxx_wdata      (w_r_ctxx_wdata),
    .i_sec_only        (w_b_sec_only),
    .o_cfg_send        (w_b_cfg_send),
    .o_cfg             (w_b_cfg),
    .i_cfg_idle        (w_b_cfg_idle),
    .i_cfg_done        (w_b_cfg_done),
    .o_cmd_send        (w_b_cmd_send),
    .o_cmd             (w_b_cmd),
    .i_cmd_idle        (w_b_cmd_idle),
    .i_cmd_done        (w_b_cmd_done),
    .i_sts_valid       (w_b_sts_valid),
    .i_sts             (w_b_sts),
    .o_wreq_send       (w_b_wreq_send),
    .o_wreq            (w_b_wreq),
    .i_wreq_idle       (w_b_wreq_idle),
    .i_wreq_done       (w_b_wreq_done),
    .i_wrsp_valid      (w_b_wrsp_valid),
    .i_wrsp            (w_b_wrsp),
    .o_in_flush        (w_b_in_flush),
    .o_in_load         (w_b_in_load),
    .o_in_aad_len      (w_b_in_aad_len),
    .o_in_data_len     (w_b_in_data_len),
    .o_bpb             (w_b_bpb),
    .o_bpe             (w_b_bpe),
    .o_beat_bytes      (w_b_beat_bytes),
    .o_in_full_thr     (w_b_in_full_thr),
    .i_in_active       (w_b_in_active),
    .i_in_drop         (w_b_in_drop),
    .i_in_full         (w_b_in_full),
    .i_in_full_thr     (w_b_in_full_thr_flag),
    .o_out_flush       (w_b_out_flush),
    .o_out_load        (w_b_out_load),
    .o_out_data_len    (w_b_out_data_len),
    .o_out_burst_bytes (w_b_out_burst_bytes),
    .i_out_empty       (w_b_out_empty),
    .i_out_dma_cond    (w_b_out_dma_cond),
    .i_reg_wr_en       (w_r_reg_wr_en),
    .i_reg_wr_addr     (w_r_reg_wr_addr),
    .i_reg_rd_en       (w_r_reg_rd_en),
    .i_reg_rd_addr     (w_r_reg_rd_addr),
    .i_pio_din         (w_r_pio_din),
    .o_pio_dout        (w_r_pio_dout),
    .o_dma_in_req      (o_dma_in_req),
    .i_dma_in_ack      (i_dma_in_ack),
    .o_dma_out_req     (o_dma_out_req),
    .i_dma_out_ack     (i_dma_out_ack),
    .i_axi_awid        (i_axi_awid),
    .i_axi_awaddr      (i_axi_awaddr),
    .i_axi_awlen       (i_axi_awlen),
    .i_axi_awsize      (i_axi_awsize),
    .i_axi_awburst     (i_axi_awburst),
    .i_axi_awvalid     (i_axi_awvalid),
    .o_axi_awready     (o_axi_awready),
    .i_axi_wdata       (i_axi_wdata),
    .i_axi_wstrb       (i_axi_wstrb),
    .i_axi_wlast       (i_axi_wlast),
    .i_axi_wvalid      (i_axi_wvalid),
    .o_axi_wready      (o_axi_wready),
    .o_axi_bid         (o_axi_bid),
    .o_axi_bresp       (o_axi_bresp),
    .o_axi_bvalid      (o_axi_bvalid),
    .i_axi_bready      (i_axi_bready),
    .i_axi_arid        (i_axi_arid),
    .i_axi_araddr      (i_axi_araddr),
    .i_axi_arlen       (i_axi_arlen),
    .i_axi_arsize      (i_axi_arsize),
    .i_axi_arburst     (i_axi_arburst),
    .i_axi_arvalid     (i_axi_arvalid),
    .o_axi_arready     (o_axi_arready),
    .o_axi_rid         (o_axi_rid),
    .o_axi_rdata       (o_axi_rdata),
    .o_axi_rresp       (o_axi_rresp),
    .o_axi_rlast       (o_axi_rlast),
    .o_axi_rvalid      (o_axi_rvalid),
    .i_axi_rready      (i_axi_rready),
    .o_beat_valid      (w_b_beat_valid),
    .i_beat_ready      (w_b_beat_ready),
    .o_beat_data       (w_b_beat_data),
    .i_obeat_valid     (w_b_obeat_valid),
    .o_obeat_ready     (w_b_obeat_ready),
    .i_obeat_data      (w_b_obeat_data)
  );


  // Crossing structure.
  m_aesgcm_xing #(
    .PARA_AES_LANE_NUM (PARA_AES_LANE_NUM),
    .PARA_CLK_ASYNC    (PARA_CLK_ASYNC),
    .PARA_FIFO_DEPTH   (PARA_FIFO_DEPTH)
  ) u_xing (
    .i_clk_bus         (i_clk_bus),
    .i_rst_n_bus       (w_rst_n_bus),
    .i_cfg_send        (w_b_cfg_send),
    .i_cfg             (w_b_cfg),
    .o_cfg_idle        (w_b_cfg_idle),
    .o_cfg_done        (w_b_cfg_done),
    .i_cmd_send        (w_b_cmd_send),
    .i_cmd             (w_b_cmd),
    .o_cmd_idle        (w_b_cmd_idle),
    .o_cmd_done        (w_b_cmd_done),
    .o_sts_valid       (w_b_sts_valid),
    .o_sts             (w_b_sts),
    .i_wreq_send       (w_b_wreq_send),
    .i_wreq            (w_b_wreq),
    .o_wreq_idle       (w_b_wreq_idle),
    .o_wreq_done       (w_b_wreq_done),
    .o_wrsp_valid      (w_b_wrsp_valid),
    .o_wrsp            (w_b_wrsp),
    .o_sec_only_bus    (w_b_sec_only),
    .i_in_flush        (w_b_in_flush),
    .i_in_load         (w_b_in_load),
    .i_in_aad_len      (w_b_in_aad_len),
    .i_in_data_len     (w_b_in_data_len),
    .i_bpb             (w_b_bpb),
    .i_bpe             (w_b_bpe),
    .i_beat_bytes      (w_b_beat_bytes),
    .i_in_full_thr     (w_b_in_full_thr),
    .o_in_active       (w_b_in_active),
    .o_in_drop         (w_b_in_drop),
    .o_in_full         (w_b_in_full),
    .o_in_full_thr     (w_b_in_full_thr_flag),
    .i_beat_valid      (w_b_beat_valid),
    .o_beat_ready      (w_b_beat_ready),
    .i_beat_data       (w_b_beat_data),
    .i_out_flush_bus   (w_b_out_flush),
    .i_out_load        (w_b_out_load),
    .i_out_data_len    (w_b_out_data_len),
    .i_out_burst_bytes (w_b_out_burst_bytes),
    .o_out_empty       (w_b_out_empty),
    .o_out_dma_cond    (w_b_out_dma_cond),
    .o_obeat_valid     (w_b_obeat_valid),
    .i_obeat_ready     (w_b_obeat_ready),
    .o_obeat_data      (w_b_obeat_data),
    .i_clk_core        (i_clk_core),
    .i_rst_n_core      (w_rst_n_core),
    .o_cfg_valid       (w_c_cfg_valid),
    .o_cfg             (w_c_cfg),
    .i_cfg_clr         (w_c_cfg_clr),
    .o_cmd_valid       (w_c_cmd_valid),
    .o_cmd             (w_c_cmd),
    .i_sts_send        (w_c_sts_send),
    .i_sts             (w_c_sts),
    .o_sts_idle        (w_c_sts_idle),
    .o_wreq_valid      (w_c_wreq_valid),
    .o_wreq            (w_c_wreq),
    .i_wrsp_send       (w_c_wrsp_send),
    .i_wrsp            (w_c_wrsp),
    .o_wrsp_idle       (w_c_wrsp_idle),
    .o_sec_only_core   (w_c_sec_only),
    .o_in_empty        (w_c_in_empty),
    .o_in_ent          (w_c_in_ent),
    .i_in_rd_en        (w_c_in_rd_en),
    .i_out_wr_en       (w_c_out_wr_en),
    .i_out_ent         (w_c_out_ent),
    .o_out_full        (w_c_out_full),
    .i_out_flush_core  (w_c_out_flush),
    .o_out_flush_busy  (w_c_out_flush_busy),
    .i_gcm_secure_only (i_gcm_secure_only)
  );


  // CORE-domain structure.
  m_aesgcm_core_dom #(
    .PARA_AES_LANE_NUM  (PARA_AES_LANE_NUM),
    .PARA_AES_GCM_EN    (PARA_AES_GCM_EN),
    .PARA_GHASH_ARCH    (PARA_GHASH_ARCH),
    .PARA_GHASH_DIGIT_W (PARA_GHASH_DIGIT_W),
    .PARA_GHASH_PIPE    (PARA_GHASH_PIPE),
    .PARA_GCM_CTX_MODE  (PARA_GCM_CTX_MODE),
    .PARA_GCM_CTX_NUM   (PARA_GCM_CTX_NUM),
    .PARA_KEY_SIDE_EN   (PARA_KEY_SIDE_EN)
  ) u_core_dom (
    .i_clk_core       (i_clk_core),
    .i_rst_n_core     (w_rst_n_core),
    .i_cfg_valid      (w_c_cfg_valid),
    .i_cfg            (w_c_cfg),
    .o_cfg_clr        (w_c_cfg_clr),
    .i_cmd_valid      (w_c_cmd_valid),
    .i_cmd            (w_c_cmd),
    .o_sts_send       (w_c_sts_send),
    .o_sts            (w_c_sts),
    .i_sts_idle       (w_c_sts_idle),
    .i_wreq_valid     (w_c_wreq_valid),
    .i_wreq           (w_c_wreq),
    .o_wrsp_send      (w_c_wrsp_send),
    .o_wrsp           (w_c_wrsp),
    .i_wrsp_idle      (w_c_wrsp_idle),
    .i_sec_only       (w_c_sec_only),
    .i_in_empty       (w_c_in_empty),
    .i_in_ent         (w_c_in_ent),
    .o_in_rd_en       (w_c_in_rd_en),
    .o_out_wr_en      (w_c_out_wr_en),
    .o_out_ent        (w_c_out_ent),
    .i_out_full       (w_c_out_full),
    .o_out_flush      (w_c_out_flush),
    .i_out_flush_busy (w_c_out_flush_busy),
    .i_key_side_valid (i_key_side_valid),
    .i_key_side_size  (i_key_side_size),
    .i_key_side       (i_key_side),
    .o_key_side_ack   (o_key_side_ack)
  );

endmodule
