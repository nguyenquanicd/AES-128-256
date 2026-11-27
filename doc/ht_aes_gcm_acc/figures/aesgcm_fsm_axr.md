# FSM: AXI4 read window

Initial state: `ENUM_ST_AXR_IDLE`

Reset entry: `i_rst_n_bus` active-low.

![FSM: AXI4 read window](<aesgcm_fsm_axr.svg>)

Sources: [aesgcm_fsm_axr.drawio](<aesgcm_fsm_axr.drawio>) | [aesgcm_fsm_axr.json](<aesgcm_fsm_axr.json>) | [aesgcm_fsm_axr_layout_report.txt](<aesgcm_fsm_axr_layout_report.txt>)

## Transition and global state control mapping

| Kind | Label / effect | Boolean expression |
|---|---|---|
| Transition | address accepted | `i_axi_arvalid && o_axi_arready` |
| Transition | legal burst | `w_araddr_bit11 && w_burst_ok && w_size_ok` |
| Transition | illegal burst | `!(w_araddr_bit11 && w_burst_ok && w_size_ok)` |
| Transition | last beat accepted | `o_axi_rvalid && i_axi_rready && o_axi_rlast` |
| Transition | burst closed | `1'b1` |
