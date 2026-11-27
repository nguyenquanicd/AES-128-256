// -------------------------------------------------------------------------------------------------
// Project      : AES-GCM Accelerator - acceptance simulation testbench
// File         : tb_aesgcm_decl.svh (included inside module tb_aesgcm_top, after the configuration)
// Description  : Every module-level variable and constant shared by the model and harness includes,
//                declared once before any task refers to it.
// -------------------------------------------------------------------------------------------------

// ------------------------------------------------------------------------------ clocks and resets
logic        clk_bus  = 1'b0;
logic        clk_core = 1'b0;
int unsigned t_bus_half  = 5000;
int unsigned t_core_half = 3500;
int unsigned t_bus_ph    = 0;
int unsigned t_core_ph   = 0;
int unsigned t_bus_per   = 10000;
int unsigned t_core_per  = 7000;
bit          clk_cfg_done = 1'b0;
string       clk_ratio_s  = "1_1";
int unsigned cyc_bus  = 0;
int unsigned cyc_core = 0;
logic        rst_n_bus  = 1'b0;
logic        rst_n_core = 1'b0;
logic        protect_en = 1'b1;     // static inputs (IF-007), changed only while in reset
logic        slverr_en  = 1'b1;
logic        sec_pin    = 1'b0;     // i_gcm_secure_only (IF-006), changed only while idle
logic        pend_protect_en = 1'b1; // values applied to the static inputs inside the next reset
logic        pend_slverr_en  = 1'b1;

// ------------------------------------------------------------------------------ PRNG and seed
int unsigned prng_state = 32'h1234_5678;
int unsigned seed       = 1;

// ------------------------------------------------------------------------------ APB requester
logic        apb_psel;
logic        apb_penable;
logic        apb_pwrite;
logic [15:0] apb_paddr;
logic [31:0] apb_pwdata;
logic [3:0]  apb_pstrb;
logic [2:0]  apb_pprot;
int          apb_gap_max   = 1;
int          apb_timeout   = 64;
int          apb_lock      = 0;
int          apb_unexp_err = 0;     // unexpected PSLVERR in the current testcase
int          apb_hang      = 0;     // transfers ended by the time-out in the current testcase
logic [2:0]  apb_prot_dflt = 3'b000;

// ------------------------------------------------------------------------------ AXI4 manager
logic [C_IW-1:0]   axi_awid;
logic [C_AW-1:0]   axi_awaddr;
logic [7:0]        axi_awlen;
logic [2:0]        axi_awsize;
logic [1:0]        axi_awburst;
logic              axi_awvalid;
logic [C_DW-1:0]   axi_wdata;
logic [C_DW/8-1:0] axi_wstrb;
logic              axi_wlast;
logic              axi_wvalid;
logic              axi_bready;
logic [C_IW-1:0]   axi_arid;
logic [C_AW-1:0]   axi_araddr;
logic [7:0]        axi_arlen;
logic [2:0]        axi_arsize;
logic [1:0]        axi_arburst;
logic              axi_arvalid;
logic              axi_rready;
logic              tb_mask_axi_wlast;
int axi_wgap_max       = 1;
int axi_bready_dly_max = 2;
int axi_rready_dly_max = 2;
int axi_rand_strb      = 0;
int axi_timeout        = 200000;
int axi_hang           = 0;      // handshakes ended by the time-out in the current testcase
int axi_wr_lock        = 0;
int axi_rd_lock        = 0;
localparam logic [2:0] AXI_SIZE_FULL = $clog2(C_DW / 8);
localparam logic [1:0] BURST_FIXED = 2'b00, BURST_INCR = 2'b01, BURST_WRAP = 2'b10;
localparam logic [1:0] BURST_RSVD = 2'b11;

// ------------------------------------------------------------------------------ DMA model
logic dma_in_ack;
logic dma_out_ack;
int   dma_ack_dly_max = 3;
int   dma_stop        = 0;
int   dma_bursts_in   = 0;
int   dma_bursts_out  = 0;
int   dma_err         = 0;      // failures seen by the model in the current testcase
int   dma_wait_max    = 400000; // bus clocks the model waits for a request
localparam int DMA_VIA_AXI = 0, DMA_VIA_PIO = 1;

// ------------------------------------------------------------------------------ key manager
logic         km_valid;
logic         km_size;
logic [255:0] km_key;
int           km_acks  = 0;
int           km_delay = 4;

// ------------------------------------------------------------------------------ bookkeeping
localparam int MAXT = 128;
string tc_id      = "";
int    tc_checks  = 0;
int    tc_fails   = 0;
int    tc_min     = 0;
string tc_skip    = "";
string tc_ids_seen [0:63];
int    tc_nids    = 0;
int    tc_errors  = 0;
string res_id   [0:MAXT-1];
string res_verd [0:MAXT-1];
string res_note [0:MAXT-1];
int    res_n    = 0;

// ------------------------------------------------------------------------------ vectors, message
localparam int VMEM_WORDS = 65536;
localparam int MAXB       = 8192;
localparam int MAXS       = 2 * MAXB + 64;
logic [31:0] vmem [0:VMEM_WORDS-1];
int          v_nrec = 0;
int          v_off [0:255];
string       vec_dir = "vectors";
int          m_mode, m_dec, m_ksz, m_tlc, m_seg, m_aadlen, m_dlen, m_expok, m_kind, m_action;
logic [31:0] m_key    [0:7];
logic [31:0] m_iv     [0:3];
logic [31:0] m_tagin  [0:3];
logic [31:0] m_tagexp [0:3];
logic [7:0]  m_aad [0:MAXB-1];
logic [7:0]  m_in  [0:MAXB-1];
logic [7:0]  m_exp [0:MAXB-1];
logic [7:0]  tx_b  [0:MAXS-1];
logic [7:0]  rx_b  [0:MAXS-1];
int          tx_n = 0;
int          tb_in_beats_sent = 0;
int          tb_out_beats_got = 0;

// ------------------------------------------------------------------------------ results
logic [31:0] r_raw, r_sts, r_err, r_fail, r_fifo, r_ctrl;
logic [31:0] r_tag [0:3];
int          r_out_bad = 0;
bit          r_timeout = 1'b0;
bit          run_ok    = 1'b0;
int unsigned r_t0_bus, r_t0_core, r_lat_bus, r_lat_core;

// ------------------------------------------------------------------------------ assertion shadows
logic [31:0] sh_cfg     = 32'h0;
logic [31:0] sh_datalen = 32'h0;
logic [9:0]  sh_irq_en  = 10'h0;
logic [7:0]  sh_dmacfg  = 8'h0;
logic        sh_msg_active    = 1'b0;
logic        sh_pass1_active  = 1'b0;
logic        sh_pc_blocked    = 1'b0;
logic        sh_side_window   = 1'b0;
logic        sh_int_clear_arm = 1'b0;
int          sh_in_left     = 0;
int          sh_out_left    = 0;
int          sh_burst_bound = 4000;
int          sh_xc_bound    = 32;

// ------------------------------------------------------------------------------ data paths
localparam int DSRC_AXI = 0, DSRC_PIO = 1;
localparam int PATH_AXI_INCR = 0, PATH_AXI_FIXED = 1, PATH_AXI_MIX = 2, PATH_PIO = 3;
localparam int PATH_DMA_AXI = 4, PATH_DMA_PIO = 5;

// ------------------------------------------------------------------------------ waveform dump
bit    wf_dump   = 1'b0;      // this run dumps the selected scenario window
string wf_stem   = "";
bit    dump_test = 1'b0;      // +DUMP: per-testcase waveform (R-097)
