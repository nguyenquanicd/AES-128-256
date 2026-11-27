// -------------------------------------------------------------------------------------------------
// Project      : AES-GCM Accelerator - acceptance simulation testbench
// File         : tb_aesgcm_assert.sv
// Description  : Clocked protocol and specification assertions (rules R-024, R-025), written from
//                Arm IHI 0024D (APB4), Arm IHI 0022H.c (AXI4), spec section 6.3.4 (four-phase DMA
//                handshake), spec 6.2 / 6.3.5 / 6.4 / 7.3 / 15.3 (cross-interface and spec rules).
//                No RTL was read (rule R-023). Each assertion counts hits (antecedent true) and fails
//                (consequent false) and is sampled at the active edge before the flip-flops update
//                (the `chk` pattern of section 3 of the testbench guide; no concurrent SVA because
//                the integrator uses Verilator).
//
//   Masks for deliberate illegal stimulus are explicit inputs:
//     i_mask_axi_wlast : the current write burst has a deliberate WLAST/AWLEN mismatch (spec 6.3.2,
//                        ERR-008); AXI-22 and AXI-23 are masked for exactly that burst.
//   Inapplicable assertions (no AXI4 ports on the APB wrapper, side-load not built, probes not
//   bound) are listed with their reason and excluded from the never-exercised count.
//
//   Report: raise i_report for one cycle; the module prints the assertion table and drives
//   o_fail_cnt (assertion failures) and o_never_cnt (applicable assertions never exercised).
// -------------------------------------------------------------------------------------------------
`timescale 1ps/1ps

module tb_aesgcm_assert #(
  parameter int DW         = 64,
  parameter int IW         = 4,
  parameter int AW         = 16,
  parameter int AXI_EN     = 1,
  parameter int KEY_SIDE   = 1,
  parameter bit PROBES     = 1'b0
) (
  input  logic            clk_bus,
  input  logic            clk_core,
  input  logic            rst_n_bus,
  input  logic            rst_n_core,
  // APB4 (IF-001)
  input  logic            psel,
  input  logic            penable,
  input  logic            pwrite,
  input  logic [15:0]     paddr,
  input  logic [31:0]     pwdata,
  input  logic [3:0]      pstrb,
  input  logic [2:0]      pprot,
  input  logic            pready,
  input  logic [31:0]     prdata,
  input  logic            pslverr,
  input  logic            protect_en,
  input  logic            slverr_en,
  // AXI4 data window (IF-002)
  input  logic [IW-1:0]   awid,
  input  logic [AW-1:0]   awaddr,
  input  logic [7:0]      awlen,
  input  logic [2:0]      awsize,
  input  logic [1:0]      awburst,
  input  logic            awvalid,
  input  logic            awready,
  input  logic [DW-1:0]   wdata,
  input  logic [DW/8-1:0] wstrb,
  input  logic            wlast,
  input  logic            wvalid,
  input  logic            wready,
  input  logic [IW-1:0]   bid,
  input  logic [1:0]      bresp,
  input  logic            bvalid,
  input  logic            bready,
  input  logic [IW-1:0]   arid,
  input  logic [AW-1:0]   araddr,
  input  logic [7:0]      arlen,
  input  logic [2:0]      arsize,
  input  logic [1:0]      arburst,
  input  logic            arvalid,
  input  logic            arready,
  input  logic [IW-1:0]   rid,
  input  logic [DW-1:0]   rdata,
  input  logic [1:0]      rresp,
  input  logic            rlast,
  input  logic            rvalid,
  input  logic            rready,
  // DMA four-phase (IF-003)
  input  logic            dma_in_req,
  input  logic            dma_in_ack,
  input  logic            dma_out_req,
  input  logic            dma_out_ack,
  // Key side-load (IF-005) and interrupt (IF-004)
  input  logic            ks_valid,
  input  logic            ks_size,
  input  logic [255:0]    ks_key,
  input  logic            ks_ack,
  input  logic            int_o,
  // Testbench shadows of software-visible state (written by the test, not derived from the DUT)
  input  logic            sh_msg_active,     // from the start write until the end event was read
  input  logic            sh_pass1_active,   // a policy A pass 1 message is active
  input  logic            sh_pc_blocked,     // a policy C request with i_gcm_secure_only = 1 is pending
  input  logic [7:0]      sh_dmacfg,         // last value written to aesgcm_dmacfg
  input  int              sh_in_left,        // input beats not yet moved by the DMA model
  input  int              sh_out_left,       // output beats not yet moved by the DMA model
  input  int              sh_burst_bound,    // bus clocks allowed from a request to its acknowledge
  input  logic            sh_side_window,    // a side-load message (key_src = 1) is active
  input  logic [9:0]      sh_irq_en,         // last value written to aesgcm_irq_en
  input  logic            sh_int_clear_arm,  // one-cycle pulse: software cleared the last cause
  input  int              sh_xc_bound,       // bus clocks allowed for a bundle crossing round trip
  // Masks for deliberate illegal stimulus
  input  logic            i_mask_axi_wlast,
  // Probes (valid only when PROBES = 1)
  input  logic [9:0]      pr_irq_raw,
  input  logic            pr_out_fifo_push,
  input  logic            pr_cmd_zeroize,
  input  logic            pr_cmd_abort,
  input  logic            pr_seq_idle,
  input  logic [255:0]    pr_key_store,
  input  logic [127:0]    pr_ghash_state,
  input  logic            pr_ctx_slots_nz,
  input  logic            pr_bundle_req,
  input  logic            pr_bundle_ack,
  input  logic [1023:0]   pr_bundle_data,
  // Report
  input  logic            i_report,
  input  logic            i_full_run,
  output int              o_fail_cnt,
  output int              o_never_cnt
);

  localparam int LOG2B = $clog2(DW / 8);
  localparam int NA = 107;

  // -------------------------------------------------------------------------------- IDs
  // APB4 0..26
  localparam int APB01 = 0,  APB02 = 1,  APB03 = 2,  APB04 = 3,  APB05 = 4,  APB06 = 5;
  localparam int APB07 = 6,  APB08 = 7,  APB09 = 8,  APB10 = 9,  APB11 = 10, APB12 = 11;
  localparam int APB13 = 12, APB14 = 13, APB15 = 14, APB16 = 15, APB17 = 16, APB18 = 17;
  localparam int APB19 = 18, APB20 = 19, APB21 = 20, APB22 = 21, APB23 = 22, APB24 = 23;
  localparam int APB25 = 24, APB26 = 25, APB27 = 26;
  // AXI4 27..60
  localparam int AXI01 = 27, AXI02 = 28, AXI03 = 29, AXI04 = 30, AXI05 = 31, AXI06 = 32;
  localparam int AXI07 = 33, AXI08 = 34, AXI09 = 35, AXI10 = 36, AXI11 = 37, AXI12 = 38;
  localparam int AXI13 = 39, AXI14 = 40, AXI15 = 41, AXI16 = 42, AXI17 = 43, AXI18 = 44;
  localparam int AXI19 = 45, AXI20 = 46, AXI21 = 47, AXI22 = 48, AXI23 = 49, AXI24 = 50;
  localparam int AXI25 = 51, AXI26 = 52, AXI27 = 53, AXI28 = 54, AXI29 = 55, AXI30 = 56;
  localparam int AXI31 = 57, AXI32 = 58, AXI33 = 59, AXI34 = 60;
  // DMA four-phase 61..84: channel c (0 input, 1 output) rule r (1..12) -> 61 + 12*c + (r-1)
  localparam int DMA0 = 61;
  // Specification / cross-interface 85..106
  localparam int RST01 = 85, RST02 = 86, RST03 = 87, X01 = 88, X02 = 89;
  localparam int KS01 = 90, KS02 = 91, KS03 = 92, KS04 = 93, KS05 = 94;
  localparam int INT01 = 95, INT02 = 96, INT03 = 97, INT04 = 98;
  localparam int POL01 = 99, POL02 = 100, POL03 = 101, POL04 = 102;
  localparam int SEC01 = 103, SEC02 = 104, XING01 = 105, XING02 = 106;

  int    hit [0:NA-1];
  int    bad [0:NA-1];
  string nm  [0:NA-1];
  bit    na  [0:NA-1];
  string why [0:NA-1];

  task automatic chk(input int id, input logic ante, input logic cons);
    if (ante === 1'b1) begin
      hit[id] = hit[id] + 1;
      if (cons !== 1'b1) begin
        bad[id] = bad[id] + 1;
        if (bad[id] <= 5) $display("ASSERT FAIL @%0t: %0s", $time, nm[id]);
      end
    end
  endtask

  function automatic string dma_rule(input int r);
    case (r)
      1:  dma_rule = "request not withdrawn before acknowledge (6.3.4)";
      2:  dma_rule = "request falls within 16 bus clocks after acknowledge seen (6.3.4 phase 3)";
      3:  dma_rule = "no new request while acknowledge is high (6.3.4 phase 4)";
      4:  dma_rule = "[TB] acknowledge rises only while request is high (6.3.4 phase 2, SVA-003)";
      5:  dma_rule = "[TB] acknowledge held until request falls (6.3.4 phase 4)";
      6:  dma_rule = "[TB] acknowledge falls within 16 clocks after request falls (6.3.4)";
      7:  dma_rule = "request 0 during reset and first cycle after release (6.3.4, 7.3)";
      8:  dma_rule = "request never X after reset (15.3 X policy)";
      9:  dma_rule = "request rises only when the channel is enabled (aesgcm_dmacfg)";
      10: dma_rule = "request rises only while a message is active (6.3.4 phase 1)";
      11: dma_rule = "request rises only while beats remain (6.3.4 phase 1)";
      default: dma_rule = "burst completes within bound: room/data for a full burst (6.3.4, inv. 7)";
    endcase
  endfunction

  initial begin
    for (int i = 0; i < NA; i++) begin hit[i] = 0; bad[i] = 0; na[i] = 1'b0; why[i] = ""; end
    nm[APB01] = "APB-01 PSEL known after reset (IHI0024D A.1)";
    nm[APB02] = "APB-02 PADDR/PWRITE/PENABLE/PPROT/PSTRB known while PSEL (IHI0024D A.1)";
    nm[APB03] = "APB-03 PWDATA known in a write (IHI0024D A.1)";
    nm[APB04] = "APB-04 SETUP lasts one cycle then ACCESS (IHI0024D 4.1)";
    nm[APB05] = "APB-05 PENABLE only with PSEL (IHI0024D 4.1)";
    nm[APB06] = "APB-06 PADDR stable SETUP->ACCESS and while waited (IHI0024D 4.1, 3.1.2)";
    nm[APB07] = "APB-07 PWRITE stable (IHI0024D 4.1)";
    nm[APB08] = "APB-08 PWDATA stable in a write (IHI0024D 4.1)";
    nm[APB09] = "APB-09 PSTRB stable (IHI0024D 4.1)";
    nm[APB10] = "APB-10 PPROT stable (IHI0024D 4.1)";
    nm[APB11] = "APB-11 PSEL and PENABLE held while PREADY low (IHI0024D 3.1.2)";
    nm[APB12] = "APB-12 PENABLE low after the completing cycle (IHI0024D 4.1)";
    nm[APB13] = "APB-13 PSTRB all low in a read (IHI0024D 3.2)";
    nm[APB14] = "APB-14 PREADY known in ACCESS (IHI0024D A.1)";
    nm[APB15] = "APB-15 PRDATA known at read completion (IHI0024D A.1)";
    nm[APB16] = "APB-16 PSLVERR known at completion (IHI0024D A.1)";
    nm[APB17] = "APB-17 PSLVERR low outside the completing cycle (IHI0024D 3.4, spec 6.2)";
    nm[APB18] = "APB-18 one wait state for a legal full-word access (spec 11.4)";
    nm[APB19] = "APB-19 partial PSTRB write: PSLVERR, 0 wait states when i_slverr_en=1 (spec 11.4)";
    nm[APB20] = "APB-20 unaligned address: PSLVERR when i_slverr_en=1 (spec 11.4)";
    nm[APB21] = "APB-21 PPROT[1]=1: PSLVERR when protect_en and slverr_en (spec 11.4, IHI0024D 3.5)";
    nm[APB22] = "APB-22 legal secure aligned full-word access: PSLVERR=0 (spec 11.4, DEC-009)";
    nm[APB23] = "APB-23 bounded completion: PREADY within 16 ACCESS cycles (guide 3)";
    nm[APB24] = "APB-24 no PSLVERR when i_slverr_en=0 (spec 11.4)";
    nm[APB25] = "APB-25 unmapped aligned address reads 0 (spec 11.4, DEC-009)";
    nm[APB26] = "APB-26 reserved bits read as 0 (spec 11.4)";
    nm[APB27] = "APB-27 write-only key registers read as 0 (spec 11.4, REQ-REG-002)";
    nm[AXI01] = "AXI-01 AWVALID held until AWREADY (IHI0022H A3.2.2)";
    nm[AXI02] = "AXI-02 AW payload stable while stalled (IHI0022H A3.2.1)";
    nm[AXI03] = "AXI-03 WVALID held until WREADY (IHI0022H A3.2.2)";
    nm[AXI04] = "AXI-04 W payload stable while stalled (IHI0022H A3.2.1)";
    nm[AXI05] = "AXI-05 BVALID held until BREADY (IHI0022H A3.2.2)";
    nm[AXI06] = "AXI-06 BID/BRESP stable while stalled (IHI0022H A3.2.1)";
    nm[AXI07] = "AXI-07 ARVALID held until ARREADY (IHI0022H A3.2.2)";
    nm[AXI08] = "AXI-08 AR payload stable while stalled (IHI0022H A3.2.1)";
    nm[AXI09] = "AXI-09 RVALID held until RREADY (IHI0022H A3.2.2)";
    nm[AXI10] = "AXI-10 RID/RDATA/RRESP/RLAST stable while stalled (IHI0022H A3.2.1)";
    nm[AXI11] = "AXI-11 subordinate RVALID/BVALID low in reset (IHI0022H A3.1.2)";
    nm[AXI12] = "AXI-12 manager AWVALID/WVALID/ARVALID low in reset (IHI0022H A3.1.2)";
    nm[AXI13] = "AXI-13 BVALID only after AW and the last W beat (IHI0022H A3.3.1)";
    nm[AXI14] = "AXI-14 BID equals AWID (IHI0022H A5.2, spec 6.2)";
    nm[AXI15] = "AXI-15 BRESP is OKAY or SLVERR (IHI0022H Table A3-5, spec 6.2)";
    nm[AXI16] = "AXI-16 BRESP matches burst legality (spec 6.3.2, ERR-008)";
    nm[AXI17] = "AXI-17 RVALID only inside an accepted read burst (IHI0022H A3.3.1)";
    nm[AXI18] = "AXI-18 RID equals ARID (IHI0022H A5.2.1)";
    nm[AXI19] = "AXI-19 RLAST exactly on beat ARLEN+1 (IHI0022H A3.2.2, A3.4.1)";
    nm[AXI20] = "AXI-20 RRESP is OKAY or SLVERR (IHI0022H Table A3-5)";
    nm[AXI21] = "AXI-21 RRESP/RDATA per legality: SLVERR+zero data or OKAY (spec 6.3.2)";
    nm[AXI22] = "AXI-22 write burst carries AWLEN+1 beats (IHI0022H A3.4.1) [mask: wlast]";
    nm[AXI23] = "AXI-23 WLAST only on the final beat (IHI0022H A3.2.2) [mask: wlast]";
    nm[AXI24] = "AXI-24 AWREADY low while a write burst is outstanding (spec 6.3.2)";
    nm[AXI25] = "AXI-25 ARREADY low while a read burst is outstanding (spec 6.3.2)";
    nm[AXI26] = "AXI-26 WRAP length 2/4/8/16 and aligned start (IHI0022H A3.4.1)";
    nm[AXI27] = "AXI-27 INCR burst does not cross 4KB (IHI0022H A3.4.1, REQ-IF-003)";
    nm[AXI28] = "AXI-28 FIXED/WRAP length at most 16 (IHI0022H A3.4.1)";
    nm[AXI29] = "AXI-29 AxSIZE not wider than the data bus (IHI0022H A3.4.1)";
    nm[AXI30] = "AXI-30 R channel known while RVALID (IHI0022H A3.2.2 validity)";
    nm[AXI31] = "AXI-31 B channel known while BVALID (IHI0022H A3.2.2 validity)";
    nm[AXI32] = "AXI-32 manager payload known while VALID (IHI0022H A3.2.2 validity)";
    nm[AXI33] = "AXI-33 AWREADY/WREADY/ARREADY low during reset (spec 7.3)";
    nm[AXI34] = "AXI-34 BVALID within 64 clocks after the last W beat (spec 6.3.2 RESP, bounded)";
    for (int c = 0; c < 2; c++)
      for (int r = 1; r <= 12; r++)
        nm[DMA0 + 12 * c + r - 1] = $sformatf("DMA-%0s-%02d %0s", (c == 0) ? "IN" : "OUT", r,
                                             dma_rule(r));
    nm[RST01] = "RST-01 APB outputs 0 during reset (spec 6.2)";
    nm[RST02] = "RST-02 o_int_aesgcm 0 during reset (spec 6.2, 7.3)";
    nm[RST03] = "RST-03 o_key_side_ack 0 during CORE reset (spec 6.2)";
    nm[X01]   = "X-01 BUS-domain outputs never X after reset (spec 15.3 X policy)";
    nm[X02]   = "X-02 CORE-domain outputs never X after reset (spec 15.3 X policy)";
    nm[KS01]  = "KS-01 o_key_side_ack is a one-cycle pulse (spec 6.2, REQ-FUNC-015)";
    nm[KS02]  = "KS-02 o_key_side_ack only while i_key_side_valid (spec 6.3.5)";
    nm[KS03]  = "KS-03 [TB] valid held until ack, size and key stable (spec 6.2)";
    nm[KS04]  = "KS-04 no ack outside a side-load message (spec 6.3.5, REQ-FUNC-015)";
    nm[KS05]  = "KS-05 one ack per offered key (spec 6.3.5)";
    nm[INT01] = "INT-01 o_int_aesgcm = OR(raw & en) within 2 bus clocks (REQ-IF-006, SVA-008) [probe]";
    nm[INT02] = "INT-02 irq_sts read nonzero implies o_int_aesgcm high (spec 6.4)";
    nm[INT03] = "INT-03 o_int_aesgcm falls within 2 bus clocks after the last clear (REQ-IF-006)";
    nm[INT04] = "INT-04 o_int_aesgcm low while no cause is enabled (spec 6.4, invariant 6)";
    nm[POL01] = "POL-01 no output DMA request in policy A pass 1 (REQ-SEC-002, invariant 2)";
    nm[POL02] = "POL-02 no OKAY read data in policy A pass 1 (REQ-SEC-002, REQ-FUNC-003)";
    nm[POL03] = "POL-03 output FIFO not written in policy A pass 1 (SVA-004) [probe]";
    nm[POL04] = "POL-04 no output for a policy C request with secure-only pin (REQ-SEC-003, SVA-005)";
    nm[SEC01] = "SEC-01 zeroize clears key, Y, slots within 64 core clocks (REQ-SEC-001, SVA-007) [probe]";
    nm[SEC02] = "SEC-02 abort returns FSM seq to IDLE within 64 core clocks (REQ-FUNC-013) [probe]";
    nm[XING01] = "XING-01 bundle holding register stable from request to ack (SVA-009) [probe]";
    nm[XING02] = "XING-02 bundle request to ack within 2 x X_c (spec 13.2) [probe]";
    // Scenario-inapplicable assertions (R-025) with reasons.
    if (AXI_EN == 0) begin
      for (int i = AXI01; i <= AXI34; i++) begin
        na[i] = 1'b1;
        why[i] = "m_aesgcm_acc_apb_top has no AXI4 ports (spec 6.2, FEAT-006)";
      end
      na[POL02] = 1'b1; why[POL02] = "no AXI4 read window in m_aesgcm_acc_apb_top (spec 6.2)";
    end
    if (KEY_SIDE == 0) begin
      for (int i = KS01; i <= KS03; i++) begin
        na[i] = 1'b1;
        why[i] = "PARA_KEY_SIDE_EN = 0: no side-load capture (REQ-FUNC-015); KS-04 still checks no ack";
      end
      na[KS05] = 1'b1; why[KS05] = "PARA_KEY_SIDE_EN = 0 (REQ-FUNC-015)";
    end
    if (!PROBES) begin
      na[INT01] = 1'b1; why[INT01] = "probes not bound (probe_list.md, define TB_PROBES_BOUND)";
      na[POL03] = 1'b1; why[POL03] = "probes not bound (probe_list.md, define TB_PROBES_BOUND)";
      na[SEC01] = 1'b1; why[SEC01] = "probes not bound (probe_list.md, define TB_PROBES_BOUND)";
      na[SEC02] = 1'b1; why[SEC02] = "probes not bound (probe_list.md, define TB_PROBES_BOUND)";
      na[XING01] = 1'b1; why[XING01] = "probes not bound (probe_list.md, define TB_PROBES_BOUND)";
      na[XING02] = 1'b1; why[XING02] = "probes not bound (probe_list.md, define TB_PROBES_BOUND)";
    end
  end

  // ================================================================================ BUS domain
  int rel_bus;           // bus clocks since reset release
  // APB state
  logic        psel_q, penable_q, pready_q, pwrite_q;
  logic [15:0] paddr_q;
  logic [31:0] pwdata_q;
  logic [3:0]  pstrb_q;
  logic [2:0]  pprot_q;
  int          acc_wait;
  // AXI write state
  logic          awvalid_q, awready_q, wvalid_q, wready_q, bvalid_q, bready_q;
  logic [IW-1:0] awid_q, bid_q;
  logic [AW-1:0] awaddr_q;
  logic [7:0]    awlen_q;
  logic [2:0]    awsize_q;
  logic [1:0]    awburst_q, bresp_q;
  logic [DW-1:0] wdata_q;
  logic [DW/8-1:0] wstrb_q;
  logic          wlast_q;
  logic          aw_out, w_last_seen, aw_drop, w_mism;
  logic [7:0]    aw_len_l;
  logic [IW-1:0] aw_id_l;
  int            w_cnt, b_wait;
  // AXI read state
  logic          arvalid_q, arready_q, rvalid_q, rready_q;
  logic [IW-1:0] arid_q, rid_q;
  logic [AW-1:0] araddr_q;
  logic [7:0]    arlen_q;
  logic [2:0]    arsize_q;
  logic [1:0]    arburst_q, rresp_q;
  logic [DW-1:0] rdata_q;
  logic          rlast_q;
  logic          ar_out, ar_drop;
  logic [7:0]    ar_len_l;
  logic [IW-1:0] ar_id_l;
  int            r_cnt;
  // DMA state
  logic [1:0] req_q, ack_q;
  int         req_ack_cnt [0:1];
  int         ack_hold_cnt [0:1];
  int         burst_cnt [0:1];
  logic [1:0] burst_open;
  // Interrupt state
  int   int_chk2;          // countdown for INT-02
  int   int_chk3;          // countdown for INT-03
  int   en0_cnt;           // cycles with sh_irq_en == 0
  logic exp_d1, exp_d2;
  // Crossing probe state
  logic          breq_q;
  logic [1023:0] bdata_q;
  int            breq_cnt;

  function automatic bit wr_drop(input logic [AW-1:0] a, input logic [1:0] b, input logic [2:0] s);
    return (a[11] != 1'b0) || (b > 2'd1) || (s != LOG2B[2:0]);
  endfunction
  function automatic bit rd_drop(input logic [AW-1:0] a, input logic [1:0] b, input logic [2:0] s);
    return (a[11] != 1'b1) || (b > 2'd1) || (s != LOG2B[2:0]);
  endfunction
  function automatic bit no_4k_cross(input logic [AW-1:0] a, input logic [7:0] l, input logic [2:0] s);
    int unsigned lo, bytes;
    lo = a & 32'hFFF;
    bytes = (l + 1) << s;
    return (lo + bytes) <= 32'h1000;
  endfunction
  function automatic bit wrap_ok(input logic [AW-1:0] a, input logic [7:0] l, input logic [2:0] s);
    int unsigned bytes_per;
    bytes_per = 1 << s;
    return ((l == 8'd1) || (l == 8'd3) || (l == 8'd7) || (l == 8'd15)) &&
           ((a % bytes_per) == 0);
  endfunction
  function automatic bit apb_mapped(input logic [15:0] a);
    if (a[1:0] != 2'b00) return 1'b0;
    if (a <= 16'h0018) return 1'b1;
    if ((a >= 16'h0020) && (a <= 16'h0074)) return 1'b1;
    if ((a >= 16'h0080) && (a <= 16'h00A8)) return 1'b1;
    if ((a >= 16'h0100) && (a <= 16'h015C)) return 1'b1;
    return 1'b0;
  endfunction
  function automatic logic [31:0] apb_rsv(input logic [15:0] a);
    case (a)
      16'h0004: apb_rsv = 32'hFFCC_8880;
      16'h0008: apb_rsv = 32'hFFFF_FE80;
      16'h000C: apb_rsv = 32'hFFFC_0000;
      16'h0018: apb_rsv = 32'hFFFF_0000;
      16'h0070: apb_rsv = 32'hFFF0_F0C0;
      16'h0074: apb_rsv = ~32'h0400_0200;
      16'h0080, 16'h0084, 16'h0088, 16'h008C: apb_rsv = 32'hFFFF_FC00;
      16'h0090: apb_rsv = 32'hFFFF_FF00;
      16'h0098: apb_rsv = 32'hFFFF_FF00;
      default:  apb_rsv = 32'h0;
    endcase
  endfunction

  logic apb_done, apb_err_nonsec, apb_unal, apb_partial, apb_legal;
  logic rst_b_d;
  always_comb begin
    apb_done       = psel & penable & pready;
    apb_unal       = (paddr[1:0] != 2'b00);
    apb_partial    = pwrite & (pstrb != 4'hF);
    apb_err_nonsec = pprot[1] & protect_en & slverr_en;
    apb_legal      = !apb_unal && !apb_partial && !(pprot[1] & protect_en);
  end

  always @(posedge clk_bus) begin : bus_checks
    logic aw_hs, w_hs, b_hs, ar_hs, r_hs, outs_known;
    logic [1:0] req_v, ack_v;
    logic       exp_int;
    aw_hs = awvalid & awready;
    w_hs  = wvalid & wready;
    b_hs  = bvalid & bready;
    ar_hs = arvalid & arready;
    r_hs  = rvalid & rready;
    req_v = {dma_out_req, dma_in_req};
    ack_v = {dma_out_ack, dma_in_ack};

    // ------------------------------------------------------------ reset-value assertions
    chk(RST01, !rst_n_bus, (pready === 1'b0) && (pslverr === 1'b0) && (prdata === 32'h0));
    chk(RST02, !rst_n_bus, int_o === 1'b0);
    if (AXI_EN != 0) begin
      chk(AXI11, !rst_n_bus, (rvalid === 1'b0) && (bvalid === 1'b0));
      chk(AXI12, !rst_n_bus, (awvalid === 1'b0) && (wvalid === 1'b0) && (arvalid === 1'b0));
      chk(AXI33, !rst_n_bus, (awready === 1'b0) && (wready === 1'b0) && (arready === 1'b0));
    end
    for (int c = 0; c < 2; c++)
      chk(DMA0 + 12 * c + 6, (!rst_n_bus) || (rel_bus == 0), req_v[c] === 1'b0);

    if (rst_n_bus && (rel_bus >= 2)) begin
      // ---------------------------------------------------------- X policy
      outs_known = !$isunknown({pready, pslverr, prdata, int_o, dma_in_req, dma_out_req});
      if (AXI_EN != 0)
        outs_known = outs_known && !$isunknown({awready, wready, bvalid, bid, bresp, arready,
                                                rvalid, rid, rdata, rresp, rlast});
      chk(X01, 1'b1, outs_known);

      // ---------------------------------------------------------- APB4
      chk(APB01, 1'b1, !$isunknown(psel));
      chk(APB02, psel === 1'b1, !$isunknown({paddr, pwrite, penable, pprot, pstrb}));
      chk(APB03, (psel === 1'b1) && (pwrite === 1'b1), !$isunknown(pwdata));
      chk(APB04, psel_q && !penable_q, psel && penable);
      chk(APB05, penable === 1'b1, psel === 1'b1);
      begin : apb_stable
        logic held;
        held = (psel_q && !penable_q) || (psel_q && penable_q && !pready_q);
        chk(APB06, held, paddr === paddr_q);
        chk(APB07, held, pwrite === pwrite_q);
        chk(APB08, held && pwrite_q, pwdata === pwdata_q);
        chk(APB09, held, pstrb === pstrb_q);
        chk(APB10, held, pprot === pprot_q);
      end
      chk(APB11, psel_q && penable_q && !pready_q, psel && penable);
      chk(APB12, psel_q && penable_q && pready_q, penable === 1'b0);
      chk(APB13, (psel === 1'b1) && (pwrite === 1'b0), pstrb === 4'h0);
      chk(APB14, psel && penable, !$isunknown(pready));
      chk(APB15, apb_done && !pwrite, !$isunknown(prdata));
      chk(APB16, apb_done, !$isunknown(pslverr));
      chk(APB17, !(psel && penable && pready), pslverr === 1'b0);
      chk(APB18, apb_done && apb_legal, acc_wait == 1);
      chk(APB19, apb_done && apb_partial && !apb_unal && slverr_en && !apb_err_nonsec,
          (pslverr === 1'b1) && (acc_wait == 0));
      chk(APB20, apb_done && apb_unal && slverr_en, pslverr === 1'b1);
      chk(APB21, apb_done && apb_err_nonsec, pslverr === 1'b1);
      chk(APB22, apb_done && apb_legal, pslverr === 1'b0);
      chk(APB23, psel && penable, acc_wait < 16);
      chk(APB24, apb_done && !slverr_en, pslverr === 1'b0);
      chk(APB25, apb_done && !pwrite && apb_legal && !apb_mapped(paddr), prdata === 32'h0);
      chk(APB26, apb_done && !pwrite && apb_legal && apb_mapped(paddr) && (apb_rsv(paddr) != 0),
          (prdata & apb_rsv(paddr)) === 32'h0);
      chk(APB27, apb_done && !pwrite && apb_legal && (paddr >= 16'h0020) && (paddr <= 16'h003C),
          prdata === 32'h0);

      // ---------------------------------------------------------- AXI4
      if (AXI_EN != 0) begin
        chk(AXI01, awvalid_q && !awready_q, awvalid === 1'b1);
        chk(AXI02, awvalid_q && !awready_q, {awid, awaddr, awlen, awsize, awburst} ===
                                            {awid_q, awaddr_q, awlen_q, awsize_q, awburst_q});
        chk(AXI03, wvalid_q && !wready_q, wvalid === 1'b1);
        chk(AXI04, wvalid_q && !wready_q, {wdata, wstrb, wlast} === {wdata_q, wstrb_q, wlast_q});
        chk(AXI05, bvalid_q && !bready_q, bvalid === 1'b1);
        chk(AXI06, bvalid_q && !bready_q, {bid, bresp} === {bid_q, bresp_q});
        chk(AXI07, arvalid_q && !arready_q, arvalid === 1'b1);
        chk(AXI08, arvalid_q && !arready_q, {arid, araddr, arlen, arsize, arburst} ===
                                            {arid_q, araddr_q, arlen_q, arsize_q, arburst_q});
        chk(AXI09, rvalid_q && !rready_q, rvalid === 1'b1);
        chk(AXI10, rvalid_q && !rready_q, {rid, rdata, rresp, rlast} ===
                                          {rid_q, rdata_q, rresp_q, rlast_q});
        chk(AXI13, bvalid === 1'b1, aw_out && w_last_seen);
        chk(AXI14, bvalid === 1'b1, bid === aw_id_l);
        chk(AXI15, bvalid === 1'b1, (bresp === 2'b00) || (bresp === 2'b10));
        chk(AXI16, bvalid === 1'b1, bresp === ((aw_drop || w_mism) ? 2'b10 : 2'b00));
        chk(AXI17, rvalid === 1'b1, ar_out);
        chk(AXI18, rvalid === 1'b1, rid === ar_id_l);
        chk(AXI19, r_hs, rlast === (r_cnt == int'(ar_len_l)));
        chk(AXI20, rvalid === 1'b1, (rresp === 2'b00) || (rresp === 2'b10));
        chk(AXI21, rvalid === 1'b1, ar_drop ? ((rresp === 2'b10) && (rdata === '0)) :
                                              (rresp === 2'b00));
        chk(AXI22, w_hs && wlast && !i_mask_axi_wlast, w_cnt == int'(aw_len_l));
        chk(AXI23, w_hs && aw_out && !i_mask_axi_wlast, wlast === (w_cnt == int'(aw_len_l)));
        chk(AXI24, aw_out, awready === 1'b0);
        chk(AXI25, ar_out, arready === 1'b0);
        chk(AXI26, (awvalid && (awburst == 2'b10)), wrap_ok(awaddr, awlen, awsize));
        chk(AXI26, (arvalid && (arburst == 2'b10)), wrap_ok(araddr, arlen, arsize));
        chk(AXI27, (awvalid && (awburst == 2'b01)), no_4k_cross(awaddr, awlen, awsize));
        chk(AXI27, (arvalid && (arburst == 2'b01)), no_4k_cross(araddr, arlen, arsize));
        chk(AXI28, (awvalid && (awburst != 2'b01)), awlen <= 8'd15);
        chk(AXI28, (arvalid && (arburst != 2'b01)), arlen <= 8'd15);
        chk(AXI29, awvalid === 1'b1, awsize <= LOG2B[2:0]);
        chk(AXI29, arvalid === 1'b1, arsize <= LOG2B[2:0]);
        chk(AXI30, rvalid === 1'b1, !$isunknown({rid, rdata, rresp, rlast}));
        chk(AXI31, bvalid === 1'b1, !$isunknown({bid, bresp}));
        chk(AXI32, (awvalid === 1'b1) || (wvalid === 1'b1) || (arvalid === 1'b1),
            !((awvalid && $isunknown({awid, awaddr, awlen, awsize, awburst})) ||
              (wvalid && $isunknown({wdata, wstrb, wlast})) ||
              (arvalid && $isunknown({arid, araddr, arlen, arsize, arburst}))));
        chk(AXI34, aw_out && w_last_seen && !bvalid, b_wait <= 64);
      end

      // ---------------------------------------------------------- DMA four-phase
      for (int c = 0; c < 2; c++) begin
        logic rise;
        int   left;
        rise = req_v[c] && !req_q[c];
        left = (c == 0) ? sh_in_left : sh_out_left;
        chk(DMA0 + 12 * c + 0, req_q[c] && !ack_q[c], req_v[c] === 1'b1);
        chk(DMA0 + 12 * c + 1, req_v[c] && ack_v[c], req_ack_cnt[c] <= 16);
        chk(DMA0 + 12 * c + 2, !req_q[c] && ack_q[c], req_v[c] === 1'b0);
        chk(DMA0 + 12 * c + 3, ack_v[c] && !ack_q[c], req_v[c] === 1'b1);
        chk(DMA0 + 12 * c + 4, ack_q[c] && req_q[c], ack_v[c] === 1'b1);
        chk(DMA0 + 12 * c + 5, ack_v[c] && !req_v[c], ack_hold_cnt[c] <= 16);
        chk(DMA0 + 12 * c + 7, 1'b1, !$isunknown(req_v[c]));
        chk(DMA0 + 12 * c + 8, rise, sh_dmacfg[c] === 1'b1);
        chk(DMA0 + 12 * c + 9, rise, sh_msg_active === 1'b1);
        chk(DMA0 + 12 * c + 10, rise, left > 0);
        chk(DMA0 + 12 * c + 11, burst_open[c], burst_cnt[c] <= sh_burst_bound);
      end

      // ---------------------------------------------------------- interrupt
      exp_int = |(pr_irq_raw & sh_irq_en);
      if (PROBES) chk(INT01, (exp_int == exp_d1) && (exp_d1 == exp_d2), int_o === exp_int);
      if (apb_done && !pwrite && (paddr == 16'h008C) && !pslverr && (prdata[9:0] != 10'h0))
        int_chk2 = 4;              // checked 3 samples later: 2 bus clocks of output latency
      else if (int_chk2 > 0)
        int_chk2 = int_chk2 - 1;
      chk(INT02, int_chk2 == 1, int_o === 1'b1);
      if (sh_int_clear_arm) int_chk3 = 3;
      else if (int_chk3 > 0) int_chk3 = int_chk3 - 1;
      chk(INT03, int_chk3 == 1, int_o === 1'b0);
      chk(INT04, en0_cnt >= 3, int_o === 1'b0);

      // ---------------------------------------------------------- policy gating
      chk(POL01, sh_pass1_active === 1'b1, dma_out_req === 1'b0);
      if (AXI_EN != 0)
        chk(POL02, sh_pass1_active === 1'b1, !(rvalid && (rresp == 2'b00)));
      if (PROBES) chk(POL03, sh_pass1_active === 1'b1, pr_out_fifo_push === 1'b0);
      chk(POL04, sh_pc_blocked === 1'b1, (dma_out_req === 1'b0) &&
                                          ((AXI_EN == 0) || !(rvalid && (rresp == 2'b00))));

      // ---------------------------------------------------------- crossing (probe)
      if (PROBES) begin
        chk(XING01, breq_q && pr_bundle_req && !pr_bundle_ack, pr_bundle_data === bdata_q);
        chk(XING02, pr_bundle_req && !pr_bundle_ack, breq_cnt <= 2 * sh_xc_bound);
      end
    end

    // ------------------------------------------------------------ state update
    if (!rst_n_bus) begin
      rel_bus <= 0;
      aw_out <= 1'b0; w_last_seen <= 1'b0; w_cnt <= 0; b_wait <= 0; aw_drop <= 1'b0;
      w_mism <= 1'b0; ar_out <= 1'b0; r_cnt <= 0; ar_drop <= 1'b0;
      burst_open <= 2'b00;
      for (int c = 0; c < 2; c++) begin
        req_ack_cnt[c] <= 0; ack_hold_cnt[c] <= 0; burst_cnt[c] <= 0;
      end
      acc_wait <= 0;
      int_chk2 = 0; int_chk3 = 0; en0_cnt <= 0;
      breq_cnt <= 0;
    end else begin
      if (rel_bus < 1000000) rel_bus <= rel_bus + 1;
      // APB wait counter: ACCESS cycles with PREADY low before completion
      if (psel && penable && !pready) acc_wait <= acc_wait + 1;
      else acc_wait <= 0;
      // AXI write tracking
      if (aw_hs) begin
        aw_out <= 1'b1; aw_len_l <= awlen; aw_id_l <= awid;
        aw_drop <= wr_drop(awaddr, awburst, awsize);
        w_cnt <= 0; w_last_seen <= 1'b0; w_mism <= 1'b0; b_wait <= 0;
      end
      if (w_hs && aw_out) begin
        w_cnt <= w_cnt + 1;
        if (wlast) w_last_seen <= 1'b1;
        if ((wlast && (w_cnt != int'(aw_len_l))) || (!wlast && (w_cnt == int'(aw_len_l))))
          w_mism <= 1'b1;
      end
      if (aw_out && w_last_seen && !bvalid) b_wait <= b_wait + 1;
      if (b_hs) begin aw_out <= 1'b0; w_last_seen <= 1'b0; end
      // AXI read tracking
      if (ar_hs) begin
        ar_out <= 1'b1; ar_len_l <= arlen; ar_id_l <= arid;
        ar_drop <= rd_drop(araddr, arburst, arsize); r_cnt <= 0;
      end
      if (r_hs && ar_out) begin
        r_cnt <= r_cnt + 1;
        if (r_cnt == int'(ar_len_l)) ar_out <= 1'b0;
      end
      // DMA counters
      for (int c = 0; c < 2; c++) begin
        if (req_v[c] && ack_v[c]) req_ack_cnt[c] <= req_ack_cnt[c] + 1;
        else req_ack_cnt[c] <= 0;
        if (ack_v[c] && !req_v[c]) ack_hold_cnt[c] <= ack_hold_cnt[c] + 1;
        else ack_hold_cnt[c] <= 0;
        if (req_v[c] && !req_q[c]) begin burst_open[c] <= 1'b1; burst_cnt[c] <= 0; end
        else if (ack_v[c]) begin burst_open[c] <= 1'b0; end
        else if (burst_open[c]) burst_cnt[c] <= burst_cnt[c] + 1;
      end
      if (sh_irq_en == 10'h0) begin
        if (en0_cnt < 1000) en0_cnt <= en0_cnt + 1;
      end else en0_cnt <= 0;
      if (pr_bundle_req && !pr_bundle_ack) breq_cnt <= breq_cnt + 1;
      else breq_cnt <= 0;
    end
    psel_q <= psel; penable_q <= penable; pready_q <= pready; pwrite_q <= pwrite;
    paddr_q <= paddr; pwdata_q <= pwdata; pstrb_q <= pstrb; pprot_q <= pprot;
    awvalid_q <= awvalid; awready_q <= awready; awid_q <= awid; awaddr_q <= awaddr;
    awlen_q <= awlen; awsize_q <= awsize; awburst_q <= awburst;
    wvalid_q <= wvalid; wready_q <= wready; wdata_q <= wdata; wstrb_q <= wstrb; wlast_q <= wlast;
    bvalid_q <= bvalid; bready_q <= bready; bid_q <= bid; bresp_q <= bresp;
    arvalid_q <= arvalid; arready_q <= arready; arid_q <= arid; araddr_q <= araddr;
    arlen_q <= arlen; arsize_q <= arsize; arburst_q <= arburst;
    rvalid_q <= rvalid; rready_q <= rready; rid_q <= rid; rdata_q <= rdata; rresp_q <= rresp;
    rlast_q <= rlast;
    req_q <= req_v; ack_q <= ack_v;
    exp_d2 <= exp_d1; exp_d1 <= exp_int;
    breq_q <= pr_bundle_req; bdata_q <= pr_bundle_data;
  end

  // ================================================================================ CORE domain
  int   rel_core;
  logic ks_valid_q, ks_ack_q, ks_size_q, ks_acked;
  logic [255:0] ks_key_q;
  logic zr_q, ab_q;
  int   zr_cnt, ab_cnt;
  logic zr_seen, ab_seen, zr_open, ab_open;

  always @(posedge clk_core) begin : core_checks
    chk(RST03, !rst_n_core, ks_ack === 1'b0);
    if (rst_n_core && (rel_core >= 2)) begin
      chk(X02, 1'b1, !$isunknown(ks_ack));
      if (KEY_SIDE != 0) begin
        chk(KS01, ks_ack_q === 1'b1, ks_ack === 1'b0);
        chk(KS02, ks_ack === 1'b1, ks_valid === 1'b1);
        chk(KS03, ks_valid_q && !ks_ack_q, (ks_valid === 1'b1) && (ks_size === ks_size_q) &&
                                           (ks_key === ks_key_q));
        chk(KS05, ks_ack === 1'b1, !ks_acked);
      end
      chk(KS04, !sh_side_window, ks_ack === 1'b0);
      if (PROBES) begin
        chk(SEC01, zr_open && (zr_cnt == 64), zr_seen);
        chk(SEC02, ab_open && (ab_cnt == 64), ab_seen);
      end
    end
    if (!rst_n_core) begin
      rel_core <= 0; ks_acked <= 1'b0;
      zr_open <= 1'b0; ab_open <= 1'b0; zr_cnt <= 0; ab_cnt <= 0;
      zr_seen <= 1'b0; ab_seen <= 1'b0;
    end else begin
      if (rel_core < 1000000) rel_core <= rel_core + 1;
      if (ks_ack) ks_acked <= 1'b1;
      else if (!ks_valid) ks_acked <= 1'b0;
      // zeroize / abort completion windows (probe)
      if (pr_cmd_zeroize && !zr_q) begin zr_open <= 1'b1; zr_cnt <= 0; zr_seen <= 1'b0; end
      else if (zr_open) begin
        zr_cnt <= zr_cnt + 1;
        if ((pr_key_store == '0) && (pr_ghash_state == '0) && !pr_ctx_slots_nz) zr_seen <= 1'b1;
        if (zr_cnt == 64) zr_open <= 1'b0;
      end
      if (pr_cmd_abort && !ab_q) begin ab_open <= 1'b1; ab_cnt <= 0; ab_seen <= 1'b0; end
      else if (ab_open) begin
        ab_cnt <= ab_cnt + 1;
        if (pr_seq_idle) ab_seen <= 1'b1;
        if (ab_cnt == 64) ab_open <= 1'b0;
      end
    end
    ks_valid_q <= ks_valid; ks_ack_q <= ks_ack; ks_size_q <= ks_size; ks_key_q <= ks_key;
    zr_q <= pr_cmd_zeroize; ab_q <= pr_cmd_abort;
  end

  // ================================================================================ report
  always @(posedge i_report) begin : report
    int nf, nn;
    nf = 0; nn = 0;
    $display("");
    $display("================ ASSERTION TABLE (hits / fails) ================");
    for (int i = 0; i < NA; i++) begin
      if (na[i]) begin
        $display("  %-6s %8s %6s  %0s", "N/A", "-", "-", nm[i]);
      end else begin
        $display("  %-6s %8d %6d  %0s", (bad[i] != 0) ? "FAIL" : ((hit[i] == 0) ? "NEVER" : "ok"),
                 hit[i], bad[i], nm[i]);
        nf = nf + bad[i];
        if (hit[i] == 0) nn = nn + 1;
      end
    end
    $display("---------------- scenario-inapplicable assertions ----------------");
    for (int i = 0; i < NA; i++)
      if (na[i]) $display("  %0s : %0s", nm[i], why[i]);
    $display("  per-protocol counts: APB4 27, AXI4 34, DMA four-phase 24, spec/cross 22");
    o_fail_cnt = nf;
    o_never_cnt = nn;
  end

endmodule
