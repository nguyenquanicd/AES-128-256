# FSM: AXI4 write window

Initial state: `ENUM_ST_AXW_IDLE`

Reset entry: `i_rst_n_bus` active-low.

![FSM: AXI4 write window](<aesgcm_fsm_axw.svg>)

Sources: [aesgcm_fsm_axw.drawio](<aesgcm_fsm_axw.drawio>) | [aesgcm_fsm_axw.json](<aesgcm_fsm_axw.json>) | [aesgcm_fsm_axw_layout_report.txt](<aesgcm_fsm_axw_layout_report.txt>)

## Transition and global state control mapping

| Kind | Label / effect | Boolean expression |
|---|---|---|
| Transition | address accepted | `i_axi_awvalid && o_axi_awready` |
| Transition | last beat | `i_axi_wvalid && o_axi_wready && i_axi_wlast` |
| Transition | response accepted | `i_axi_bready` |
