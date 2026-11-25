# FSM: four-phase responder

Initial state: `ENUM_ST_HSR_IDLE`

Reset entry: `i_rst_n_core` active-low.

![FSM: four-phase responder](<aesgcm_fsm_hsr.svg>)

Sources: [aesgcm_fsm_hsr.drawio](<aesgcm_fsm_hsr.drawio>) | [aesgcm_fsm_hsr.json](<aesgcm_fsm_hsr.json>) | [aesgcm_fsm_hsr_layout_report.txt](<aesgcm_fsm_hsr_layout_report.txt>)

## Transition and global state control mapping

| Kind | Label / effect | Boolean expression |
|---|---|---|
| Transition | request | `w_req_sync` |
| Transition | captured | `1'b1` |
| Transition | request low | `!w_req_sync` |
