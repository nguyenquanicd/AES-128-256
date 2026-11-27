// -------------------------------------------------------------------------------------------------
// Project      : AES-GCM Accelerator - acceptance simulation testbench
// File         : tb_aesgcm_top.sv
// Description  : Testbench top. Instantiates the DUT wrapper selected by tb_aesgcm_cfg.svh with the
//                port list of spec section 6.2, the verification-only parameter checker
//                m_aesgcm_param_check (spec 8.3, DEC-019), the assertion module, the waveform view,
//                and the interface models (APB4 requester, AXI4 manager, DMA controller, key
//                manager, clocks and resets). Testcases are selected at run time:
//                  +TEST=<ID>   one testcase or WF scenario (TC-01..TC-15, FT-nnn, WF-001..WF-023)
//                  +TEST=ALL    every testcase and scenario, clean reset between them (default)
//                  +TEST=TC | FT | WF   one group
//                  +SEED=<n>    seed of every random choice (default 1)
//                  +AFIFO_MSYNC_SEED=<n> metastability seed reported in the log (R-093)
//                  +VEC_DIR=<dir> vector directory (default vectors)
//                  +DUMP        per-testcase VCD in waveforms_test/ (single testcase runs)
//                  +APB_GAP=<n> +AXI_WGAP=<n> +AXI_BREADY_DLY=<n> +AXI_RREADY_DLY=<n>
//                  +AXI_RAND_STRB +DMA_ACK_DLY=<n> +TBUS_PS=<n> +TCORE_PS=<n> +CLK_RATIO=<r>
//                  +TIMEOUT_MS=<n> watchdog per testcase in simulated milliseconds (default 50)
//                Written from the specification only (rule R-023); see README.md.
// -------------------------------------------------------------------------------------------------
`timescale 1ps/1ps

module tb_aesgcm_top;

  `include "tb_aesgcm_cfg.svh"
  `include "tb_aesgcm_regs.svh"
  `include "tb_aesgcm_decl.svh"

  // ------------------------------------------------------------------------------ DUT outputs
  wire              o_apb_pready;
  wire [31:0]       o_apb_prdata;
  wire              o_apb_pslverr;
  wire              o_int_aesgcm;
  wire              o_dma_in_req;
  wire              o_dma_out_req;
  wire              o_key_side_ack;
  wire              o_axi_awready;
  wire              o_axi_wready;
  wire [C_IW-1:0]   o_axi_bid;
  wire [1:0]        o_axi_bresp;
  wire              o_axi_bvalid;
  wire              o_axi_arready;
  wire [C_IW-1:0]   o_axi_rid;
  wire [C_DW-1:0]   o_axi_rdata;
  wire [1:0]        o_axi_rresp;
  wire              o_axi_rlast;
  wire              o_axi_rvalid;

  `include "tb_aesgcm_probes.svh"

  // ------------------------------------------------------------------------------ DUT
`ifdef TB_APB_TOP
  `ifndef TB_DUT_APB
    `define TB_DUT_APB m_aesgcm_acc_apb_top
  `endif
  `TB_DUT_APB #(
    .PARA_AES_LANE_NUM   (C_LANES),
    .PARA_AES_GCM_EN     (C_GCM_EN),
    .PARA_GCM_REL_POLICY (C_POLICY),
    .PARA_GHASH_ARCH     (C_ARCH),
    .PARA_GHASH_DIGIT_W  (C_DIGIT),
    .PARA_GHASH_PIPE     (C_PIPE),
    .PARA_GCM_CTX_MODE   (C_CTX_MODE),
    .PARA_GCM_CTX_NUM    (C_CTX_NUM),
    .PARA_KEY_SIDE_EN    (C_KEY_SIDE),
    .PARA_CLK_ASYNC      (C_ASYNC),
    .PARA_FIFO_DEPTH     (C_DEPTH)
  ) u_dut (
    .i_clk_bus          (clk_bus),
    .i_rst_n_bus        (rst_n_bus),
    .i_clk_core         (clk_core),
    .i_rst_n_core       (rst_n_core),
    .i_apb_psel         (apb_psel),
    .i_apb_penable      (apb_penable),
    .i_apb_pwrite       (apb_pwrite),
    .i_apb_paddr        (apb_paddr),
    .i_apb_pwdata       (apb_pwdata),
    .i_apb_pstrb        (apb_pstrb),
    .i_apb_pprot        (apb_pprot),
    .o_apb_pready       (o_apb_pready),
    .o_apb_prdata       (o_apb_prdata),
    .o_apb_pslverr      (o_apb_pslverr),
    .i_protect_en       (protect_en),
    .i_slverr_en        (slverr_en),
    .o_int_aesgcm       (o_int_aesgcm),
    .o_dma_in_req       (o_dma_in_req),
    .i_dma_in_ack       (dma_in_ack),
    .o_dma_out_req      (o_dma_out_req),
    .i_dma_out_ack      (dma_out_ack),
    .i_key_side_valid   (km_valid),
    .i_key_side_size    (km_size),
    .i_key_side         (km_key),
    .o_key_side_ack     (o_key_side_ack),
    .i_gcm_secure_only  (sec_pin),
    .i_dft_scan_mode    (1'b0),
    .i_dft_scan_rst_n   (1'b1)
  );
  // No AXI4 ports on the APB wrapper (spec 6.2): the observed AXI outputs are tied low.
  assign o_axi_awready = 1'b0;
  assign o_axi_wready  = 1'b0;
  assign o_axi_bid     = '0;
  assign o_axi_bresp   = 2'b00;
  assign o_axi_bvalid  = 1'b0;
  assign o_axi_arready = 1'b0;
  assign o_axi_rid     = '0;
  assign o_axi_rdata   = '0;
  assign o_axi_rresp   = 2'b00;
  assign o_axi_rlast   = 1'b0;
  assign o_axi_rvalid  = 1'b0;
`else
  `ifndef TB_DUT_AXI
    `define TB_DUT_AXI m_aesgcm_acc_axi_top
  `endif
  `TB_DUT_AXI #(
    .PARA_AES_LANE_NUM   (C_LANES),
    .PARA_AES_GCM_EN     (C_GCM_EN),
    .PARA_GCM_REL_POLICY (C_POLICY),
    .PARA_GHASH_ARCH     (C_ARCH),
    .PARA_GHASH_DIGIT_W  (C_DIGIT),
    .PARA_GHASH_PIPE     (C_PIPE),
    .PARA_GCM_CTX_MODE   (C_CTX_MODE),
    .PARA_GCM_CTX_NUM    (C_CTX_NUM),
    .PARA_KEY_SIDE_EN    (C_KEY_SIDE),
    .PARA_CLK_ASYNC      (C_ASYNC),
    .PARA_FIFO_DEPTH     (C_DEPTH),
    .PARA_AXI_DATA_W     (C_DW),
    .PARA_AXI_ID_W       (C_IW),
    .PARA_AXI_ADDR_W     (C_AW)
  ) u_dut (
    .i_clk_bus          (clk_bus),
    .i_rst_n_bus        (rst_n_bus),
    .i_clk_core         (clk_core),
    .i_rst_n_core       (rst_n_core),
    .i_apb_psel         (apb_psel),
    .i_apb_penable      (apb_penable),
    .i_apb_pwrite       (apb_pwrite),
    .i_apb_paddr        (apb_paddr),
    .i_apb_pwdata       (apb_pwdata),
    .i_apb_pstrb        (apb_pstrb),
    .i_apb_pprot        (apb_pprot),
    .o_apb_pready       (o_apb_pready),
    .o_apb_prdata       (o_apb_prdata),
    .o_apb_pslverr      (o_apb_pslverr),
    .i_protect_en       (protect_en),
    .i_slverr_en        (slverr_en),
    .o_int_aesgcm       (o_int_aesgcm),
    .o_dma_in_req       (o_dma_in_req),
    .i_dma_in_ack       (dma_in_ack),
    .o_dma_out_req      (o_dma_out_req),
    .i_dma_out_ack      (dma_out_ack),
    .i_key_side_valid   (km_valid),
    .i_key_side_size    (km_size),
    .i_key_side         (km_key),
    .o_key_side_ack     (o_key_side_ack),
    .i_gcm_secure_only  (sec_pin),
    .i_dft_scan_mode    (1'b0),
    .i_dft_scan_rst_n   (1'b1),
    .i_axi_awid         (axi_awid),
    .i_axi_awaddr       (axi_awaddr),
    .i_axi_awlen        (axi_awlen),
    .i_axi_awsize       (axi_awsize),
    .i_axi_awburst      (axi_awburst),
    .i_axi_awvalid      (axi_awvalid),
    .o_axi_awready      (o_axi_awready),
    .i_axi_wdata        (axi_wdata),
    .i_axi_wstrb        (axi_wstrb),
    .i_axi_wlast        (axi_wlast),
    .i_axi_wvalid       (axi_wvalid),
    .o_axi_wready       (o_axi_wready),
    .o_axi_bid          (o_axi_bid),
    .o_axi_bresp        (o_axi_bresp),
    .o_axi_bvalid       (o_axi_bvalid),
    .i_axi_bready       (axi_bready),
    .i_axi_arid         (axi_arid),
    .i_axi_araddr       (axi_araddr),
    .i_axi_arlen        (axi_arlen),
    .i_axi_arsize       (axi_arsize),
    .i_axi_arburst      (axi_arburst),
    .i_axi_arvalid      (axi_arvalid),
    .o_axi_arready      (o_axi_arready),
    .o_axi_rid          (o_axi_rid),
    .o_axi_rdata        (o_axi_rdata),
    .o_axi_rresp        (o_axi_rresp),
    .o_axi_rlast        (o_axi_rlast),
    .o_axi_rvalid       (o_axi_rvalid),
    .i_axi_rready       (axi_rready)
  );
`endif

  // ------------------------------------------------------------------------------ parameter check
  m_aesgcm_param_check #(
    .PARA_AES_LANE_NUM   (C_LANES),
    .PARA_AES_GCM_EN     (C_GCM_EN),
    .PARA_GCM_REL_POLICY (C_POLICY),
    .PARA_GHASH_ARCH     (C_ARCH),
    .PARA_GHASH_DIGIT_W  (C_DIGIT),
    .PARA_GHASH_PIPE     (C_PIPE),
    .PARA_GCM_CTX_MODE   (C_CTX_MODE),
    .PARA_GCM_CTX_NUM    (C_CTX_NUM),
    .PARA_KEY_SIDE_EN    (C_KEY_SIDE),
    .PARA_CLK_ASYNC      (C_ASYNC),
    .PARA_FIFO_DEPTH     (C_DEPTH),
    .PARA_AXI_DATA_W     (C_DW),
    .PARA_AXI_ID_W       (C_IW),
    .PARA_AXI_ADDR_W     (C_AW)
  ) u_param_check ();

  // ------------------------------------------------------------------------------ assertions
  logic report_req = 1'b0;
  logic full_run   = 1'b0;
  int   a_fail, a_never;

  tb_aesgcm_assert #(
    .DW       (C_DW),
    .IW       (C_IW),
    .AW       (C_AW),
    .AXI_EN   (C_AXI),
    .KEY_SIDE (C_KEY_SIDE),
    .PROBES   (C_PROBES)
  ) u_chk (
    .clk_bus         (clk_bus),
    .clk_core        (clk_core),
    .rst_n_bus       (rst_n_bus),
    .rst_n_core      (rst_n_core),
    .psel            (apb_psel),
    .penable         (apb_penable),
    .pwrite          (apb_pwrite),
    .paddr           (apb_paddr),
    .pwdata          (apb_pwdata),
    .pstrb           (apb_pstrb),
    .pprot           (apb_pprot),
    .pready          (o_apb_pready),
    .prdata          (o_apb_prdata),
    .pslverr         (o_apb_pslverr),
    .protect_en      (protect_en),
    .slverr_en       (slverr_en),
    .awid            (axi_awid),
    .awaddr          (axi_awaddr),
    .awlen           (axi_awlen),
    .awsize          (axi_awsize),
    .awburst         (axi_awburst),
    .awvalid         (axi_awvalid),
    .awready         (o_axi_awready),
    .wdata           (axi_wdata),
    .wstrb           (axi_wstrb),
    .wlast           (axi_wlast),
    .wvalid          (axi_wvalid),
    .wready          (o_axi_wready),
    .bid             (o_axi_bid),
    .bresp           (o_axi_bresp),
    .bvalid          (o_axi_bvalid),
    .bready          (axi_bready),
    .arid            (axi_arid),
    .araddr          (axi_araddr),
    .arlen           (axi_arlen),
    .arsize          (axi_arsize),
    .arburst         (axi_arburst),
    .arvalid         (axi_arvalid),
    .arready         (o_axi_arready),
    .rid             (o_axi_rid),
    .rdata           (o_axi_rdata),
    .rresp           (o_axi_rresp),
    .rlast           (o_axi_rlast),
    .rvalid          (o_axi_rvalid),
    .rready          (axi_rready),
    .dma_in_req      (o_dma_in_req),
    .dma_in_ack      (dma_in_ack),
    .dma_out_req     (o_dma_out_req),
    .dma_out_ack     (dma_out_ack),
    .ks_valid        (km_valid),
    .ks_size         (km_size),
    .ks_key          (km_key),
    .ks_ack          (o_key_side_ack),
    .int_o           (o_int_aesgcm),
    .sh_msg_active   (sh_msg_active),
    .sh_pass1_active (sh_pass1_active),
    .sh_pc_blocked   (sh_pc_blocked),
    .sh_dmacfg       (sh_dmacfg),
    .sh_in_left      (sh_in_left),
    .sh_out_left     (sh_out_left),
    .sh_burst_bound  (sh_burst_bound),
    .sh_side_window  (sh_side_window),
    .sh_irq_en       (sh_irq_en),
    .sh_int_clear_arm(sh_int_clear_arm),
    .sh_xc_bound     (sh_xc_bound),
    .i_mask_axi_wlast(tb_mask_axi_wlast),
    .pr_irq_raw      (pr_irq_raw),
    .pr_out_fifo_push(pr_out_fifo_push),
    .pr_cmd_zeroize  (pr_cmd_zeroize),
    .pr_cmd_abort    (pr_cmd_abort),
    .pr_seq_idle     (pr_seq_idle),
    .pr_key_store    (pr_key_store),
    .pr_ghash_state  (pr_ghash_state),
    .pr_ctx_slots_nz (pr_ctx_slots_nz),
    .pr_bundle_req   (pr_bundle_req),
    .pr_bundle_ack   (pr_bundle_ack),
    .pr_bundle_data  (pr_bundle_data),
    .i_report        (report_req),
    .i_full_run      (full_run),
    .o_fail_cnt      (a_fail),
    .o_never_cnt     (a_never)
  );

  // ------------------------------------------------------------------------------ waveform view
  logic [31:0] wv_pio_din = 32'h0;
  logic [31:0] wv_pio_dout = 32'h0;
  always @(posedge clk_bus) begin
    if (apb_psel && apb_penable && o_apb_pready && apb_pwrite && (apb_paddr == A_PIO_DIN))
      wv_pio_din <= apb_pwdata;
    if (apb_psel && apb_penable && o_apb_pready && !apb_pwrite && (apb_paddr == A_PIO_DOUT))
      wv_pio_dout <= o_apb_prdata;
  end
  wire       wv_w1c   = apb_psel & apb_penable & o_apb_pready & apb_pwrite & (apb_paddr == A_IRQ_RAW);
  wire [4:0] wv_ctxx  = (apb_psel && (apb_paddr >= A_CTXX)) ? 5'((apb_paddr - A_CTXX) >> 2) : 5'h0;

  tb_wf_view #(.DW(C_DW)) u_wf (
    .i_clk_bus (clk_bus), .i_clk_core (clk_core), .i_rst_n_bus (rst_n_bus), .i_rst_n_core (rst_n_core),
    .i_apb_psel (apb_psel), .i_apb_penable (apb_penable), .o_apb_pready (o_apb_pready),
    .o_apb_prdata (o_apb_prdata), .aesgcm_ctrl_start (pr_ctrl_start),
    .aesgcm_cfg_mode_pass (sh_cfg), .aesgcm_cfg_mode (sh_cfg[2:0]), .aesgcm_datalen (sh_datalen),
    .pio_din_word (wv_pio_din), .pio_dout_word (wv_pio_dout), .apb_ctxx_index (wv_ctxx),
    .apb_w1c_write (wv_w1c), .aesgcm_ctrl_abort (pr_ctrl_abort), .aesgcm_sts_busy (pr_sts_busy),
    .i_axi_awvalid (axi_awvalid), .o_axi_awready (o_axi_awready), .i_axi_awlen (axi_awlen),
    .i_axi_awburst (axi_awburst), .i_axi_wvalid (axi_wvalid), .o_axi_wready (o_axi_wready),
    .i_axi_wlast (axi_wlast), .o_axi_bvalid (o_axi_bvalid), .i_axi_bready (axi_bready),
    .o_axi_bresp (o_axi_bresp), .i_axi_arvalid (axi_arvalid), .o_axi_arready (o_axi_arready),
    .i_axi_arlen (axi_arlen), .i_axi_arburst (axi_arburst), .o_axi_rvalid (o_axi_rvalid),
    .i_axi_rready (axi_rready), .o_axi_rdata (o_axi_rdata), .o_axi_rlast (o_axi_rlast),
    .o_dma_in_req (o_dma_in_req), .i_dma_in_ack (dma_in_ack), .o_dma_out_req (o_dma_out_req),
    .i_dma_out_ack (dma_out_ack), .i_key_side_valid (km_valid), .o_key_side_ack (o_key_side_ack),
    .o_int_aesgcm (o_int_aesgcm), .i_gcm_secure_only (sec_pin),
    .bundle_req (pr_bundle_req), .bundle_ack_sync (pr_bundle_ack), .bundle_req_bus (pr_bundle_req),
    .req_cap_core (pr_req_cap_core), .ack_core (pr_ack_core), .ack_seen_bus (pr_bundle_ack),
    .fsm_seq_state (pr_seq_state), .fsm_ctx_state (pr_ctx_state),
    .core_cfg_valid (pr_core_cfg_valid), .core_batch_valid (pr_core_batch_valid),
    .core_out_valid (pr_core_out_valid), .ghash_valid (pr_ghash_valid), .tag_valid (pr_tag_valid),
    .o_done (pr_seq_done), .out_fifo_push (pr_out_fifo_push), .tag_match (pr_tag_match),
    .ver_ok (pr_ver_ok), .irq_raw_done (pr_irq_raw[0]), .irq_raw_tagf (pr_irq_raw[1]),
    .irq_raw_cerr (pr_irq_raw[2]), .irq_raw_cswd (pr_irq_raw[7]), .irq_raw_kerr (pr_irq_raw[8]),
    .irq_raw_perr (pr_irq_raw[9]), .irq_en_done (sh_irq_en[0]),
    .irq_sts_done (pr_irq_raw[0] & sh_irq_en[0]), .event_pulse_done (pr_event_done),
    .fifo_push (pr_fifo_push), .fifo_pop (pr_fifo_pop), .fifo_in_full (pr_fifo_in_full),
    .fifo_in_room_burst (pr_in_room_burst), .fifo_out_has_burst (pr_out_has_burst),
    .o_reg_wr_en (pr_reg_wr_en), .o_reg_wr_addr (pr_reg_wr_addr), .o_reg_rd_en (pr_reg_rd_en),
    .key_ld (pr_key_ld), .keywait_expired (pr_keywait_expired), .cmd_suspend (pr_cmd_suspend),
    .cmd_resume (pr_cmd_resume), .cmd_abort (pr_cmd_abort), .cmd_zeroize (pr_cmd_zeroize),
    .slot_valid (pr_slot_valid), .fifo_flush (pr_fifo_flush), .out_fifo_level (pr_out_fifo_level),
    .key_store (pr_key_store), .ctx_slots (pr_ctx_slots_nz), .ghash_state (pr_ghash_state),
    .aes_core_zeroize (pr_aes_zeroize), .sts_zeroized (pr_sts_zeroized),
    .in_valid (pr_ghash_in_valid), .in_count (pr_ghash_in_count),
    .exp_lane0 (pr_ghash_exp_lane[2:0]), .exp_lane1 (pr_ghash_exp_lane[5:3]),
    .exp_lane2 (pr_ghash_exp_lane[8:6]), .exp_lane3 (pr_ghash_exp_lane[11:9]),
    .ghash_y (pr_ghash_state), .ghash_in_valid (pr_ghash_in_valid),
    .pp_valid_pipe1 (pr_ghash_pp_valid), .ghash_y_pipe1 (pr_ghash_state),
    .ghash_y_pipe0 (pr_ghash_state), .cdc007_req (pr_cdc007_req), .cdc007_ack (pr_cdc007_ack),
    .cmd_send (pr_cmd_send), .cmd_valid (pr_cmd_valid), .sts_valid_cmd_ack (pr_sts_valid),
    .hw_clear_abort (pr_hw_clr_abort)
  );

  // ------------------------------------------------------------------------------ models, harness
  `include "tb_aesgcm_lib.svh"
  `include "tb_apb_requester.svh"
  `include "tb_axi_manager.svh"
  `include "tb_dma_model.svh"
  `include "tb_keymgr_clk.svh"
  `include "tb_aesgcm_helpers.svh"
  `include "tb_aesgcm_tests_tc.svh"
  `include "tb_aesgcm_tests_tc2.svh"
  `include "tb_aesgcm_tests_ft.svh"
  `include "tb_aesgcm_wf.svh"

  // ------------------------------------------------------------------------------ dispatcher
  localparam int NTESTS = 53;
  string test_list [0:NTESTS-1];
  initial begin
    test_list[0]  = "TC-01"; test_list[1]  = "TC-02"; test_list[2]  = "TC-03";
    test_list[3]  = "TC-04"; test_list[4]  = "TC-05"; test_list[5]  = "TC-06";
    test_list[6]  = "TC-07"; test_list[7]  = "TC-08"; test_list[8]  = "TC-09";
    test_list[9]  = "TC-10"; test_list[10] = "TC-11"; test_list[11] = "TC-12";
    test_list[12] = "TC-13"; test_list[13] = "TC-14"; test_list[14] = "TC-15";
    test_list[15] = "FT-011"; test_list[16] = "FT-012"; test_list[17] = "FT-013";
    test_list[18] = "FT-014"; test_list[19] = "FT-015"; test_list[20] = "FT-016";
    test_list[21] = "FT-018"; test_list[22] = "FT-026"; test_list[23] = "FT-028";
    test_list[24] = "FT-029"; test_list[25] = "FT-030"; test_list[26] = "FT-031";
    test_list[27] = "FT-033"; test_list[28] = "FT-036"; test_list[29] = "FT-037";
    for (int i = 0; i < 23; i++) test_list[30 + i] = $sformatf("WF-%03d", i + 1);
  end

  time test_t0 = 0;
  string cur_test = "";
  longint timeout_ps = 64'd50_000_000_000;   // 50 ms

  task automatic run_one(input string id);
    cur_test = id;
    test_t0 = $time;
    // clean state between testcases: static inputs, model settings, shadows, reset
    sec_pin = 1'b0;
    pend_protect_en = 1'b1; pend_slverr_en = 1'b1;
    sh_msg_active = 1'b0; sh_pass1_active = 1'b0; sh_pc_blocked = 1'b0; sh_side_window = 1'b0;
    sh_irq_en = 10'h0; sh_dmacfg = 8'h0; sh_cfg = 32'h0; sh_datalen = 32'h0;
    sh_in_left = 0; sh_out_left = 0; sh_burst_bound = 4000;
    km_delay = 4; dma_stop = 0;
    do_reset(4);
    if (dump_test && !wf_dump) begin
      $dumpfile($sformatf("waveforms_test/%0s_seed%0d.vcd", id, seed));
      $dumpvars(1, u_wf);
    end
    if      (id == "TC-01") tc01();
    else if (id == "TC-02") tc02();
    else if (id == "TC-03") tc03();
    else if (id == "TC-04") tc04();
    else if (id == "TC-05") tc05();
    else if (id == "TC-06") tc06();
    else if (id == "TC-07") tc07();
    else if (id == "TC-08") tc08();
    else if (id == "TC-09") tc09();
    else if (id == "TC-10") tc10();
    else if (id == "TC-11") tc11();
    else if (id == "TC-12") tc12();
    else if (id == "TC-13") tc13();
    else if (id == "TC-14") tc14();
    else if (id == "TC-15") tc15();
    else if (id == "FT-011") ft011();
    else if (id == "FT-012") ft012();
    else if (id == "FT-013") ft013();
    else if (id == "FT-014") ft014();
    else if (id == "FT-015") ft015();
    else if (id == "FT-016") ft016();
    else if (id == "FT-018") ft018();
    else if (id == "FT-026") ft026();
    else if (id == "FT-028") ft028();
    else if (id == "FT-029") ft029();
    else if (id == "FT-030") ft030();
    else if (id == "FT-031") ft031();
    else if (id == "FT-033") ft033();
    else if (id == "FT-036") ft036();
    else if (id == "FT-037") ft037();
    else if (id == "WF-001") wf001();
    else if (id == "WF-002") wf002();
    else if (id == "WF-003") wf003();
    else if (id == "WF-004") wf004();
    else if (id == "WF-005") wf005();
    else if (id == "WF-006") wf006();
    else if (id == "WF-007") wf007();
    else if (id == "WF-008") wf008();
    else if (id == "WF-009") wf009();
    else if (id == "WF-010") wf010();
    else if (id == "WF-011") wf011();
    else if (id == "WF-012") wf012();
    else if (id == "WF-013") wf013();
    else if (id == "WF-014") wf014();
    else if (id == "WF-015") wf015();
    else if (id == "WF-016") wf016();
    else if (id == "WF-017") wf017();
    else if (id == "WF-018") wf018();
    else if (id == "WF-019") wf019();
    else if (id == "WF-020") wf020();
    else if (id == "WF-021") wf021();
    else if (id == "WF-022") wf022();
    else if (id == "WF-023") wf023();
    else begin
      tc_begin(id, 1);
      tc_errors++;
      $display("TB-ERROR: unknown testcase %0s", id);
      tc_end();
    end
    dma_stop = 1;
    repeat (10) @(posedge clk_bus);
    cur_test = "";
  endtask

  // ------------------------------------------------------------------------------ final report
  task automatic final_report(input bit full, input bit timed_out);
    int nfail, npass, nskip;
    nfail = 0; npass = 0; nskip = 0;
    $display("");
    $display("================ TESTCASE SUMMARY (%0s, seed %0d) ================", `TB_CFG_NAME, seed);
    for (int i = 0; i < res_n; i++) begin
      $display("  %-7s %-5s %0s", res_id[i], res_verd[i], res_note[i]);
      if (res_verd[i] == "PASS") npass++;
      else if (res_verd[i] == "SKIP") nskip++;
      else nfail++;
    end
    $display("  total %0d: %0d PASS, %0d FAIL, %0d SKIP", res_n, npass, nfail, nskip);
    report_req = 1'b1;
    #1;
    report_req = 1'b0;
    #1;
    $display("assertion failures: %0d, assertions never exercised: %0d", a_fail, a_never);
    if (timed_out || (nfail > 0) || (a_fail > 0) || (full && (a_never > 0)))
      $fatal(1, "SIMULATION FAILED");
    $finish;
  endtask

  // ------------------------------------------------------------------------------ main
  initial begin : main
    string targ;
    int v, ms_seed;
    if (!$value$plusargs("SEED=%d", seed)) seed = 1;
    prng_state = seed ^ 32'h9E37_79B9;
    if (prng_state == 0) prng_state = 32'h1;
    if ($value$plusargs("APB_GAP=%d", v)) apb_gap_max = v;
    if ($value$plusargs("AXI_WGAP=%d", v)) axi_wgap_max = v;
    if ($value$plusargs("AXI_BREADY_DLY=%d", v)) axi_bready_dly_max = v;
    if ($value$plusargs("AXI_RREADY_DLY=%d", v)) axi_rready_dly_max = v;
    if ($test$plusargs("AXI_RAND_STRB")) axi_rand_strb = 1;
    if ($value$plusargs("DMA_ACK_DLY=%d", v)) dma_ack_dly_max = v;
    if ($value$plusargs("TIMEOUT_MS=%d", v)) timeout_ps = longint'(v) * 64'd1_000_000_000;
    if (!$value$plusargs("VEC_DIR=%s", vec_dir)) vec_dir = "vectors";
    dump_test = $test$plusargs("DUMP");
`ifdef VLSIT_SYNTHESIS
    $display("SIM-BRANCH: synthesis");
`else
    if (!$value$plusargs("AFIFO_MSYNC_SEED=%d", ms_seed)) ms_seed = 1;
    $display("SIM-BRANCH: metastable seed=%0d", ms_seed);
`endif
    $display("TB-INFO: configuration %0s: lanes %0d, GCM %0d, policy %0d, GHASH arch %0d digit %0d pipe %0d,",
             `TB_CFG_NAME, C_LANES, C_GCM_EN, C_POLICY, C_ARCH, C_DIGIT, C_PIPE);
    $display("TB-INFO:   ctx mode %0d num %0d, key side %0d, async %0d, FIFO depth %0d, AXI %0d (DW %0d), probes %0d",
             C_CTX_MODE, C_CTX_NUM, C_KEY_SIDE, C_ASYNC, C_DEPTH, C_AXI, C_DW, C_PROBES);
    tb_drive_idle();
    clk_configure();
    sh_xc_bound = xc_bus();
    if (!$value$plusargs("TEST=%s", targ)) targ = "ALL";
    if ((targ == "ALL") || (targ == "TC") || (targ == "FT") || (targ == "WF")) begin
      full_run = (targ == "ALL");
      for (int i = 0; i < NTESTS; i++)
        if ((targ == "ALL") || (test_list[i].substr(0, 1) == targ)) run_one(test_list[i]);
    end else begin
      wf_dump = (targ.len() >= 3) && (targ.substr(0, 2) == "WF-");
      run_one(targ);
    end
    final_report(full_run, 1'b0);
  end

  // Watchdog: a testcase longer than +TIMEOUT_MS ends the run as FAIL.
  initial begin : watchdog
    forever begin
      #(64'd1_000_000);
      if ((cur_test != "") && (($time - test_t0) > timeout_ps)) begin
        $display("TB-ERROR: watchdog: %0s exceeded %0d ps", cur_test, timeout_ps);
        if (res_n < MAXT) begin
          res_id[res_n] = cur_test; res_verd[res_n] = "FAIL"; res_note[res_n] = "watchdog time-out";
          res_n++;
        end
        final_report(1'b0, 1'b1);
      end
    end
  end

endmodule
