/*
 * Project      : AES-GCM Accelerator
 * Author       : Nguyen Hung Quan and Claude (user)
 * AI Flow      : VLSIT RTL Generator AI Automation Flow
 * AI Flow Page : https://github.com/nguyenquanicd/VLSIT_RTL_Generator_AI_Model
 * Date         : 2026-11-25
 * Description  : BUS-domain structure (spec 5.1, 14.2): command and status control
 *                u_bus_ctl, PIO path u_pio, DMA channels u_dma_ch_0 (input) and u_dma_ch_1
 *                (output), and the AXI4 window u_axi_win elaborated when PARA_AXI_EN = 1.
 * Deviation    : HIE-02 (SHOULD) - the selection between the PIO beats and the AXI beats and
 *                the idle outputs of the absent window are assigned here.
 * Decisions    : DEC-016, DEC-024 (spec section 20).
 */
`timescale 1ns/1ps

module m_aesgcm_bus_dom #(
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
  // Parameter Description: 1 elaborates the AXI4 window; set by the wrapper, not by the integrator.
  // Parameter values: 0 or 1; default is 0.
  // Parameter unit: none
  parameter logic [31:0] PARA_AXI_EN = 0,
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
  localparam logic [31:0] LPARA_STRB_W = PARA_AXI_DATA_W / 8
) (
  // Clock and reset (BUS domain)
  input  wire                                    i_clk_bus,
  input  wire                                    i_rst_n_bus,

  // Control and status of the CSR, crossings and FIFO control (see m_aesgcm_bus_ctl)
  output logic [15:0]                            o_ver_major,
  output logic [15:0]                            o_ver_minor,
  output logic [1:0]                             o_cap_axi_dw,
  output logic [1:0]                             o_cap_ghash,
  output logic [2:0]                             o_cap_lanes,
  output logic [2:0]                             o_cap_ctx_num,
  output logic                                   o_cap_ctx_exp,
  output logic [1:0]                             o_cap_policy,
  output logic                                   o_cap_async,
  output logic                                   o_cap_key_side,
  output logic                                   o_cap_axi_en,
  output logic                                   o_cap_gcm_en,
  input  wire                                    i_ctrl_en,
  input  wire  [6:0]                             i_ctrl_cmd,
  output logic [6:0]                             o_ctrl_clr,
  input  wire  [2:0]                             i_cfg_mode,
  input  wire                                    i_cfg_decipher,
  input  wire                                    i_cfg_key_size,
  input  wire                                    i_cfg_key_src,
  input  wire                                    i_cfg_dat_src,
  input  wire  [1:0]                             i_cfg_gcm_pass,
  input  wire  [2:0]                             i_cfg_tag_len,
  input  wire  [3:0]                             i_cfg_cfb_seg,
  input  wire  [1:0]                             i_cfg_ctx_id,
  input  wire  [31:0]                            i_aad_len,
  input  wire  [31:0]                            i_data_len,
  input  wire  [15:0]                            i_keywait,
  input  wire  [LPARA_KEY_W-1:0]                 i_key_words,
  input  wire  [LPARA_BLK_W-1:0]                 i_iv_words,
  input  wire  [LPARA_BLK_W-1:0]                 i_tagin_words,
  output logic                                   o_key_clr,
  output logic [LPARA_BLK_W-1:0]                 o_tagout_words,
  output logic                                   o_sts_busy,
  output logic                                   o_sts_tag_ok,
  output logic                                   o_sts_ver_ok,
  output logic                                   o_sts_zeroized,
  output logic                                   o_sts_sec_only,
  output logic                                   o_sts_key_ld,
  output logic [3:0]                             o_sts_phase,
  output logic [3:0]                             o_sts_ctx_vld,
  output logic [3:0]                             o_err_code,
  output logic [3:0]                             o_err_core,
  output logic [31:0]                            o_failcnt,
  output logic [31:0]                            o_cons_a,
  output logic [31:0]                            o_cons_d,
  output logic                                   o_fifo_in_full,
  output logic                                   o_fifo_out_empty,
  input  wire  [LPARA_EVT_W-1:0]                 i_irq_raw,
  output logic [LPARA_EVT_W-1:0]                 o_irq_set,
  input  wire  [LPARA_EVT_W-1:0]                 i_irq_en,
  input  wire  [LPARA_EVT_W-1:0]                 i_irq_inj,
  output logic [LPARA_EVT_W-1:0]                 o_irq_sts,
  output logic                                   o_int,
  input  wire                                    i_dma_in_en,
  input  wire                                    i_dma_out_en,
  input  wire  [2:0]                             i_dma_in_burst,
  input  wire  [2:0]                             i_dma_out_burst,
  input  wire  [LPARA_CTXX_NUM*LPARA_WORD_W-1:0] i_ctxx_words,
  output logic [LPARA_CTXX_NUM-1:0]              o_ctxx_we,
  output logic [LPARA_WORD_W-1:0]                o_ctxx_wdata,
  input  wire                                    i_sec_only,
  output logic                                   o_cfg_send,
  output logic [LPARA_CFG_W-1:0]                 o_cfg,
  input  wire                                    i_cfg_idle,
  input  wire                                    i_cfg_done,
  output logic                                   o_cmd_send,
  output logic [LPARA_CMD_W-1:0]                 o_cmd,
  input  wire                                    i_cmd_idle,
  input  wire                                    i_cmd_done,
  input  wire                                    i_sts_valid,
  input  wire  [LPARA_STS_W-1:0]                 i_sts,
  output logic                                   o_wreq_send,
  output logic [LPARA_WREQ_W-1:0]                o_wreq,
  input  wire                                    i_wreq_idle,
  input  wire                                    i_wreq_done,
  input  wire                                    i_wrsp_valid,
  input  wire  [LPARA_WRSP_W-1:0]                i_wrsp,
  output logic                                   o_in_flush,
  output logic                                   o_in_load,
  output logic [31:0]                            o_in_aad_len,
  output logic [31:0]                            o_in_data_len,
  output logic [4:0]                             o_bpb,
  output logic [2:0]                             o_bpe,
  output logic [4:0]                             o_beat_bytes,
  output logic [LPARA_THR_W-1:0]                 o_in_full_thr,
  input  wire                                    i_in_active,
  input  wire                                    i_in_drop,
  input  wire                                    i_in_full,
  input  wire                                    i_in_full_thr,
  output logic                                   o_out_flush,
  output logic                                   o_out_load,
  output logic [31:0]                            o_out_data_len,
  output logic [8:0]                             o_out_burst_bytes,
  input  wire                                    i_out_empty,
  input  wire                                    i_out_dma_cond,

  // Register-event sideband and PIO data registers of the CSR
  input  wire                                    i_reg_wr_en,
  input  wire  [LPARA_ADDR_W-1:0]                i_reg_wr_addr,
  input  wire                                    i_reg_rd_en,
  input  wire  [LPARA_ADDR_W-1:0]                i_reg_rd_addr,
  input  wire  [LPARA_WORD_W-1:0]                i_pio_din,
  output logic [LPARA_WORD_W-1:0]                o_pio_dout,

  // DMA four-phase handshake (IF-003)
  output logic                                   o_dma_in_req,
  input  wire                                    i_dma_in_ack,
  output logic                                   o_dma_out_req,
  input  wire                                    i_dma_out_ack,

  // AXI4 data window (IF-002); tied off in the APB wrapper
  input  wire  [PARA_AXI_ID_W-1:0]               i_axi_awid,
  input  wire  [PARA_AXI_ADDR_W-1:0]             i_axi_awaddr,
  input  wire  [7:0]                             i_axi_awlen,
  input  wire  [2:0]                             i_axi_awsize,
  input  wire  [1:0]                             i_axi_awburst,
  input  wire                                    i_axi_awvalid,
  output logic                                   o_axi_awready,
  input  wire  [PARA_AXI_DATA_W-1:0]             i_axi_wdata,
  input  wire  [LPARA_STRB_W-1:0]                i_axi_wstrb,
  input  wire                                    i_axi_wlast,
  input  wire                                    i_axi_wvalid,
  output logic                                   o_axi_wready,
  output logic [PARA_AXI_ID_W-1:0]               o_axi_bid,
  output logic [1:0]                             o_axi_bresp,
  output logic                                   o_axi_bvalid,
  input  wire                                    i_axi_bready,
  input  wire  [PARA_AXI_ID_W-1:0]               i_axi_arid,
  input  wire  [PARA_AXI_ADDR_W-1:0]             i_axi_araddr,
  input  wire  [7:0]                             i_axi_arlen,
  input  wire  [2:0]                             i_axi_arsize,
  input  wire  [1:0]                             i_axi_arburst,
  input  wire                                    i_axi_arvalid,
  output logic                                   o_axi_arready,
  output logic [PARA_AXI_ID_W-1:0]               o_axi_rid,
  output logic [PARA_AXI_DATA_W-1:0]             o_axi_rdata,
  output logic [1:0]                             o_axi_rresp,
  output logic                                   o_axi_rlast,
  output logic                                   o_axi_rvalid,
  input  wire                                    i_axi_rready,

  // Beat streams of the input and output FIFO
  output logic                                   o_beat_valid,
  input  wire                                    i_beat_ready,
  output logic [LPARA_BLK_W-1:0]                 o_beat_data,
  input  wire                                    i_obeat_valid,
  output logic                                   o_obeat_ready,
  input  wire  [LPARA_BLK_W-1:0]                 i_obeat_data
);

  // Internal signal declarations
  logic                   w_dat_src;
  logic                   w_pio_perr;
  logic                   w_dma_in_cond;
  logic                   w_dma_out_cond;
  logic                   w_pio_beat_valid;
  logic [LPARA_BLK_W-1:0] w_pio_beat_data;
  logic                   w_pio_obeat_ready;
  logic                   w_axi_beat_valid;
  logic [LPARA_BLK_W-1:0] w_axi_beat_data;
  logic                   w_axi_obeat_ready;

  // Command decode, legality check, snapshot, status, events and DMA conditions.
  m_aesgcm_bus_ctl #(
    .PARA_AES_LANE_NUM   (PARA_AES_LANE_NUM),
    .PARA_AES_GCM_EN     (PARA_AES_GCM_EN),
    .PARA_GCM_REL_POLICY (PARA_GCM_REL_POLICY),
    .PARA_GHASH_ARCH     (PARA_GHASH_ARCH),
    .PARA_GCM_CTX_MODE   (PARA_GCM_CTX_MODE),
    .PARA_GCM_CTX_NUM    (PARA_GCM_CTX_NUM),
    .PARA_KEY_SIDE_EN    (PARA_KEY_SIDE_EN),
    .PARA_CLK_ASYNC      (PARA_CLK_ASYNC),
    .PARA_FIFO_DEPTH     (PARA_FIFO_DEPTH),
    .PARA_AXI_EN         (PARA_AXI_EN),
    .PARA_AXI_DATA_W     (PARA_AXI_DATA_W)
  ) u_bus_ctl (
    .i_clk_bus         (i_clk_bus),
    .i_rst_n_bus       (i_rst_n_bus),
    .o_ver_major       (o_ver_major),
    .o_ver_minor       (o_ver_minor),
    .o_cap_axi_dw      (o_cap_axi_dw),
    .o_cap_ghash       (o_cap_ghash),
    .o_cap_lanes       (o_cap_lanes),
    .o_cap_ctx_num     (o_cap_ctx_num),
    .o_cap_ctx_exp     (o_cap_ctx_exp),
    .o_cap_policy      (o_cap_policy),
    .o_cap_async       (o_cap_async),
    .o_cap_key_side    (o_cap_key_side),
    .o_cap_axi_en      (o_cap_axi_en),
    .o_cap_gcm_en      (o_cap_gcm_en),
    .i_ctrl_en         (i_ctrl_en),
    .i_ctrl_cmd        (i_ctrl_cmd),
    .o_ctrl_clr        (o_ctrl_clr),
    .i_cfg_mode        (i_cfg_mode),
    .i_cfg_decipher    (i_cfg_decipher),
    .i_cfg_key_size    (i_cfg_key_size),
    .i_cfg_key_src     (i_cfg_key_src),
    .i_cfg_dat_src     (i_cfg_dat_src),
    .i_cfg_gcm_pass    (i_cfg_gcm_pass),
    .i_cfg_tag_len     (i_cfg_tag_len),
    .i_cfg_cfb_seg     (i_cfg_cfb_seg),
    .i_cfg_ctx_id      (i_cfg_ctx_id),
    .i_aad_len         (i_aad_len),
    .i_data_len        (i_data_len),
    .i_keywait         (i_keywait),
    .i_key_words       (i_key_words),
    .i_iv_words        (i_iv_words),
    .i_tagin_words     (i_tagin_words),
    .o_key_clr         (o_key_clr),
    .o_tagout_words    (o_tagout_words),
    .o_sts_busy        (o_sts_busy),
    .o_sts_tag_ok      (o_sts_tag_ok),
    .o_sts_ver_ok      (o_sts_ver_ok),
    .o_sts_zeroized    (o_sts_zeroized),
    .o_sts_sec_only    (o_sts_sec_only),
    .o_sts_key_ld      (o_sts_key_ld),
    .o_sts_phase       (o_sts_phase),
    .o_sts_ctx_vld     (o_sts_ctx_vld),
    .o_err_code        (o_err_code),
    .o_err_core        (o_err_core),
    .o_failcnt         (o_failcnt),
    .o_cons_a          (o_cons_a),
    .o_cons_d          (o_cons_d),
    .o_fifo_in_full    (o_fifo_in_full),
    .o_fifo_out_empty  (o_fifo_out_empty),
    .i_irq_raw         (i_irq_raw),
    .o_irq_set         (o_irq_set),
    .i_irq_en          (i_irq_en),
    .i_irq_inj         (i_irq_inj),
    .o_irq_sts         (o_irq_sts),
    .o_int             (o_int),
    .i_dma_in_en       (i_dma_in_en),
    .i_dma_out_en      (i_dma_out_en),
    .i_dma_in_burst    (i_dma_in_burst),
    .i_dma_out_burst   (i_dma_out_burst),
    .o_dma_in_cond     (w_dma_in_cond),
    .o_dma_out_cond    (w_dma_out_cond),
    .i_ctxx_words      (i_ctxx_words),
    .o_ctxx_we         (o_ctxx_we),
    .o_ctxx_wdata      (o_ctxx_wdata),
    .i_sec_only        (i_sec_only),
    .o_cfg_send        (o_cfg_send),
    .o_cfg             (o_cfg),
    .i_cfg_idle        (i_cfg_idle),
    .i_cfg_done        (i_cfg_done),
    .o_cmd_send        (o_cmd_send),
    .o_cmd             (o_cmd),
    .i_cmd_idle        (i_cmd_idle),
    .i_cmd_done        (i_cmd_done),
    .i_sts_valid       (i_sts_valid),
    .i_sts             (i_sts),
    .o_wreq_send       (o_wreq_send),
    .o_wreq            (o_wreq),
    .i_wreq_idle       (i_wreq_idle),
    .i_wreq_done       (i_wreq_done),
    .i_wrsp_valid      (i_wrsp_valid),
    .i_wrsp            (i_wrsp),
    .o_dat_src         (w_dat_src),
    .o_in_flush        (o_in_flush),
    .o_in_load         (o_in_load),
    .o_in_aad_len      (o_in_aad_len),
    .o_in_data_len     (o_in_data_len),
    .o_bpb             (o_bpb),
    .o_bpe             (o_bpe),
    .o_beat_bytes      (o_beat_bytes),
    .o_in_full_thr     (o_in_full_thr),
    .i_in_active       (i_in_active),
    .i_in_drop         (i_in_drop),
    .i_in_full         (i_in_full),
    .i_in_full_thr     (i_in_full_thr),
    .o_out_flush       (o_out_flush),
    .o_out_load        (o_out_load),
    .o_out_data_len    (o_out_data_len),
    .o_out_burst_bytes (o_out_burst_bytes),
    .i_out_empty       (i_out_empty),
    .i_out_beat_valid  (i_obeat_valid),
    .i_out_dma_cond    (i_out_dma_cond),
    .i_pio_perr        (w_pio_perr)
  );


  // APB programmed-I/O data path.
  m_aesgcm_pio u_pio (
    .i_clk_bus     (i_clk_bus),
    .i_rst_n_bus   (i_rst_n_bus),
    .i_reg_wr_en   (i_reg_wr_en),
    .i_reg_wr_addr (i_reg_wr_addr),
    .i_reg_rd_en   (i_reg_rd_en),
    .i_reg_rd_addr (i_reg_rd_addr),
    .i_din         (i_pio_din),
    .o_dout        (o_pio_dout),
    .i_sel         (w_dat_src),
    .o_beat_valid  (w_pio_beat_valid),
    .i_beat_ready  (i_beat_ready),
    .o_beat_data   (w_pio_beat_data),
    .i_obeat_valid (i_obeat_valid),
    .o_obeat_ready (w_pio_obeat_ready),
    .i_obeat_data  (i_obeat_data),
    .o_perr        (w_pio_perr)
  );


  // DMA input channel (instance 0) and output channel (instance 1).
  m_aesgcm_dma_ch u_dma_ch_0 (
    .i_clk_bus   (i_clk_bus),
    .i_rst_n_bus (i_rst_n_bus),
    .i_cond      (w_dma_in_cond),
    .o_req       (o_dma_in_req),
    .i_ack       (i_dma_in_ack)
  );

  m_aesgcm_dma_ch u_dma_ch_1 (
    .i_clk_bus   (i_clk_bus),
    .i_rst_n_bus (i_rst_n_bus),
    .i_cond      (w_dma_out_cond),
    .o_req       (o_dma_out_req),
    .i_ack       (i_dma_out_ack)
  );


  if (PARA_AXI_EN == 1) begin : gen_axi
    // AXI4 data window.
    m_aesgcm_axi_win #(
      .PARA_AXI_DATA_W (PARA_AXI_DATA_W),
      .PARA_AXI_ID_W   (PARA_AXI_ID_W),
      .PARA_AXI_ADDR_W (PARA_AXI_ADDR_W)
    ) u_axi_win (
      .i_clk_bus     (i_clk_bus),
      .i_rst_n_bus   (i_rst_n_bus),
      .i_sel         (~w_dat_src),
      .i_axi_awid    (i_axi_awid),
      .i_axi_awaddr  (i_axi_awaddr),
      .i_axi_awlen   (i_axi_awlen),
      .i_axi_awsize  (i_axi_awsize),
      .i_axi_awburst (i_axi_awburst),
      .i_axi_awvalid (i_axi_awvalid),
      .o_axi_awready (o_axi_awready),
      .i_axi_wdata   (i_axi_wdata),
      .i_axi_wstrb   (i_axi_wstrb),
      .i_axi_wlast   (i_axi_wlast),
      .i_axi_wvalid  (i_axi_wvalid),
      .o_axi_wready  (o_axi_wready),
      .o_axi_bid     (o_axi_bid),
      .o_axi_bresp   (o_axi_bresp),
      .o_axi_bvalid  (o_axi_bvalid),
      .i_axi_bready  (i_axi_bready),
      .i_axi_arid    (i_axi_arid),
      .i_axi_araddr  (i_axi_araddr),
      .i_axi_arlen   (i_axi_arlen),
      .i_axi_arsize  (i_axi_arsize),
      .i_axi_arburst (i_axi_arburst),
      .i_axi_arvalid (i_axi_arvalid),
      .o_axi_arready (o_axi_arready),
      .o_axi_rid     (o_axi_rid),
      .o_axi_rdata   (o_axi_rdata),
      .o_axi_rresp   (o_axi_rresp),
      .o_axi_rlast   (o_axi_rlast),
      .o_axi_rvalid  (o_axi_rvalid),
      .i_axi_rready  (i_axi_rready),
      .o_beat_valid  (w_axi_beat_valid),
      .i_beat_ready  (i_beat_ready),
      .o_beat_data   (w_axi_beat_data),
      .i_obeat_valid (i_obeat_valid),
      .o_obeat_ready (w_axi_obeat_ready),
      .i_obeat_data  (i_obeat_data)
    );
  end else begin : gen_no_axi
    // APB wrapper: no window, AXI outputs idle.
    assign o_axi_awready = '0;
    assign o_axi_wready = '0;
    assign o_axi_bid = '0;
    assign o_axi_bresp = '0;
    assign o_axi_bvalid = '0;
    assign o_axi_arready = '0;
    assign o_axi_rid = '0;
    assign o_axi_rdata = '0;
    assign o_axi_rresp = '0;
    assign o_axi_rlast = '0;
    assign o_axi_rvalid = '0;
    assign w_axi_beat_valid  = 1'b0;
    assign w_axi_beat_data   = '0;
    assign w_axi_obeat_ready = 1'b0;
  end


  // One data source per message: the PIO path or the AXI window.
  assign o_beat_valid  = w_pio_beat_valid | w_axi_beat_valid;
  assign o_beat_data   = w_dat_src ? w_pio_beat_data : w_axi_beat_data;
  assign o_obeat_ready = w_pio_obeat_ready | w_axi_obeat_ready;

endmodule
