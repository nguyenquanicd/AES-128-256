# RTL rule check

Files: m_vlsit_csr_aesgcm.sv, m_vlsit_csr_sync.sv, m_aesgcm_acc_apb_top.sv, m_aesgcm_acc_axi_top.sv, m_aesgcm_axi_win.sv, m_aesgcm_bus_ctl.sv, m_aesgcm_bus_dom.sv, m_aesgcm_core_dom.sv, m_aesgcm_ctx.sv, m_aesgcm_dma_ch.sv, m_aesgcm_fifo_in.sv, m_aesgcm_fifo_out.sv, m_aesgcm_fmt_in.sv, m_aesgcm_fmt_out.sv, m_aesgcm_ghash.sv, m_aesgcm_ghash_mul.sv, m_aesgcm_hpow.sv, m_aesgcm_hs_xing.sv, m_aesgcm_key_sel.sv, m_aesgcm_pack.sv, m_aesgcm_pio.sv, m_aesgcm_rst_sync.sv, m_aesgcm_seq.sv, m_aesgcm_tag.sv, m_aesgcm_unpack.sv, m_aesgcm_xing.sv, m_aesgcm_xing_bdl.sv

| Level | Rule | File:line | Finding |
|---|---|---|---|
| WARN | CMT-01 | m_aesgcm_axi_win.sv:140 | no functional comment before this assign group |
| WARN | CMT-01 | m_aesgcm_axi_win.sv:219 | no functional comment before this assign group |
| WARN | CMT-01 | m_aesgcm_bus_ctl.sv:337 | no functional comment before this process |
| WARN | CMT-01 | m_aesgcm_bus_ctl.sv:394 | no functional comment before this assign group |
| WARN | CMT-01 | m_aesgcm_bus_ctl.sv:400 | no functional comment before this assign group |
| WARN | CMT-01 | m_aesgcm_bus_ctl.sv:406 | no functional comment before this assign group |
| WARN | CMT-01 | m_aesgcm_bus_ctl.sv:426 | no functional comment before this assign group |
| WARN | CMT-01 | m_aesgcm_bus_ctl.sv:495 | no functional comment before this process |
| WARN | CMT-01 | m_aesgcm_bus_ctl.sv:517 | no functional comment before this assign group |
| WARN | CMT-01 | m_aesgcm_bus_ctl.sv:536 | no functional comment before this assign group |
| WARN | CMT-01 | m_aesgcm_seq.sv:323 | no functional comment before this assign group |
| WARN | CMT-01 | m_aesgcm_seq.sv:341 | no functional comment before this process |
| WARN | CMT-01 | m_aesgcm_seq.sv:349 | no functional comment before this assign group |
| WARN | CMT-01 | m_aesgcm_seq.sv:382 | no functional comment before this assign group |
| WARN | CMT-01 | m_aesgcm_seq.sv:387 | no functional comment before this assign group |
| WARN | CMT-01 | m_aesgcm_seq.sv:389 | no functional comment before this assign group |
| WARN | CMT-01 | m_aesgcm_seq.sv:392 | no functional comment before this assign group |
| WARN | CMT-01 | m_aesgcm_seq.sv:395 | no functional comment before this assign group |
| WARN | CMT-01 | m_aesgcm_seq.sv:449 | no functional comment before this assign group |
| WARN | CMT-01 | m_aesgcm_seq.sv:652 | no functional comment before this assign group |
| WARN | CMT-01 | m_aesgcm_seq.sv:654 | no functional comment before this assign group |
| WARN | CMT-01 | m_aesgcm_seq.sv:718 | no functional comment before this assign group |
| WARN | CMT-01 | m_aesgcm_seq.sv:728 | no functional comment before this assign group |
| WARN | CMT-01 | m_aesgcm_unpack.sv:127 | no functional comment before this assign group |
| WARN | CMT-01 | m_aesgcm_unpack.sv:213 | no functional comment before this assign group |
| WARN | CMT-01 | m_vlsit_csr_aesgcm.sv:842 | no functional comment before this assign group |
| WARN | CMT-01 | m_vlsit_csr_aesgcm.sv:968 | no functional comment before this assign group |
| WARN | CMT-01 | m_vlsit_csr_aesgcm.sv:1006 | no functional comment before this process |
| WARN | CMT-01 | m_vlsit_csr_aesgcm.sv:1025 | no functional comment before this assign group |
| WARN | CMT-01 | m_vlsit_csr_aesgcm.sv:1027 | no functional comment before this process |
| WARN | CMT-01 | m_vlsit_csr_aesgcm.sv:1046 | no functional comment before this process |
| WARN | CMT-01 | m_vlsit_csr_aesgcm.sv:1052 | no functional comment before this assign group |
| WARN | CMT-01 | m_vlsit_csr_aesgcm.sv:1064 | no functional comment before this process |
| WARN | CMT-01 | m_vlsit_csr_aesgcm.sv:1070 | no functional comment before this assign group |
| WARN | CMT-01 | m_vlsit_csr_aesgcm.sv:1075 | no functional comment before this process |
| WARN | CMT-01 | m_vlsit_csr_aesgcm.sv:1081 | no functional comment before this assign group |
| WARN | CMT-01 | m_vlsit_csr_aesgcm.sv:1101 | no functional comment before this assign group |
| WARN | CMT-01 | m_vlsit_csr_aesgcm.sv:1107 | no functional comment before this process |
| WARN | CMT-01 | m_vlsit_csr_aesgcm.sv:1113 | no functional comment before this assign group |
| WARN | CMT-01 | m_vlsit_csr_aesgcm.sv:2744 | no functional comment before this assign group |
| WARN | CMT-01 | m_vlsit_csr_aesgcm.sv:2753 | no functional comment before this assign group |
| WARN | HIE-02 | m_aesgcm_bus_dom.sv:15 | module has instances and also logic; a structural top should contain instances only (HIE-02) |
| WARN | HIE-02 | m_aesgcm_core_dom.sv:16 | module has instances and also logic; a structural top should contain instances only (HIE-02) |
| WARN | HIE-02 | m_aesgcm_ghash.sv:24 | module has instances and also logic; a structural top should contain instances only (HIE-02) |
| WARN | HIE-02 | m_aesgcm_hpow.sv:14 | module has instances and also logic; a structural top should contain instances only (HIE-02) |
| WARN | HIE-02 | m_aesgcm_hs_xing.sv:20 | module has instances and also logic; a structural top should contain instances only (HIE-02) |
| WARN | HIE-02 | m_aesgcm_xing_bdl.sv:17 | module has instances and also logic; a structural top should contain instances only (HIE-02) |
| WARN | HIE-02 | m_vlsit_csr_aesgcm.sv:14 | module has instances and also logic; a structural top should contain instances only (HIE-02) |
| WARN | PAR-03 | m_aesgcm_bus_ctl.sv:292 | literal 128 may be a magic number (P10); name it with a parameter, localparam or enum member |
| WARN | PAR-03 | m_aesgcm_bus_ctl.sv:311 | literal 8 may be a magic number (P10); name it with a parameter, localparam or enum member |
| WARN | PAR-03 | m_aesgcm_bus_ctl.sv:312 | literal 8 may be a magic number (P10); name it with a parameter, localparam or enum member |
| WARN | PAR-03 | m_aesgcm_bus_ctl.sv:317 | literal 8 may be a magic number (P10); name it with a parameter, localparam or enum member |
| WARN | PAR-03 | m_aesgcm_bus_ctl.sv:319 | literal 8 may be a magic number (P10); name it with a parameter, localparam or enum member |
| WARN | PAR-03 | m_aesgcm_bus_ctl.sv:327 | literal 8 may be a magic number (P10); name it with a parameter, localparam or enum member |
| WARN | PAR-03 | m_aesgcm_bus_ctl.sv:339 | literal 4'd4 may be a magic number (P10); name it with a parameter, localparam or enum member |
| WARN | PAR-03 | m_aesgcm_bus_ctl.sv:342 | literal 4'd3 may be a magic number (P10); name it with a parameter, localparam or enum member |
| WARN | PAR-03 | m_aesgcm_core_dom.sv:282 | literal 16 may be a magic number (P10); name it with a parameter, localparam or enum member |
| WARN | PAR-03 | m_aesgcm_core_dom.sv:390 | literal 5 may be a magic number (P10); name it with a parameter, localparam or enum member |
| WARN | PAR-03 | m_aesgcm_core_dom.sv:394 | literal 5 may be a magic number (P10); name it with a parameter, localparam or enum member |
| WARN | PAR-03 | m_aesgcm_rst_sync.sv:46 | literal 32'd2 may be a magic number (P10); name it with a parameter, localparam or enum member |
| WARN | PAR-03 | m_aesgcm_seq.sv:322 | literal 19 may be a magic number (P10); name it with a parameter, localparam or enum member |
| WARN | PAR-03 | m_aesgcm_seq.sv:323 | literal 2 may be a magic number (P10); name it with a parameter, localparam or enum member |
| WARN | PAR-03 | m_aesgcm_seq.sv:324 | literal 2 may be a magic number (P10); name it with a parameter, localparam or enum member |
| WARN | PAR-03 | m_aesgcm_seq.sv:346 | literal 4'd3 may be a magic number (P10); name it with a parameter, localparam or enum member |
| WARN | PAR-03 | m_aesgcm_seq.sv:417 | literal 2 may be a magic number (P10); name it with a parameter, localparam or enum member |
| WARN | PAR-03 | m_aesgcm_seq.sv:422 | literal 2'd2 may be a magic number (P10); name it with a parameter, localparam or enum member |
| WARN | PAR-03 | m_aesgcm_seq.sv:528 | literal 2'd2 may be a magic number (P10); name it with a parameter, localparam or enum member |
| WARN | PAR-03 | m_aesgcm_seq.sv:538 | literal 2'd2 may be a magic number (P10); name it with a parameter, localparam or enum member |
| WARN | PAR-03 | m_vlsit_csr_aesgcm.sv:842 | literal 8 may be a magic number (P10); name it with a parameter, localparam or enum member |

Rules failed: none
Rules warned: CMT-01, HIE-02, PAR-03
Rules clean: ARI-04, CMT-05, COM-02, COM-03, COM-04, COM-06, COM-07, COM-09, COM-10, COM-11, ENM-01, ENM-03, ENM-04, ENM-05, ENM-06, FIL-01, FIL-02, FIL-03, FIL-04, FIL-05, FIL-06, HIE-01, HIE-03, HIE-05, NAM-07, NAM-08, NAM-09, NAM-TBL, P1, P11, P12, P13, P14, P17, P18, P19, P2, P20, P21, P22, P24, P25, P26, P27, P29, P3, P30, P31, P32, P33, P4, P6, P7, PAR-01, PAR-02, R-019, R-027, R-032, R-035, R-036, R-038, R-071, R-072, SCP-01, SEC-8.1, SEQ-01, TYP-02, TYP-06, TYP-07
