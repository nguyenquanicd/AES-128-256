# FSM: four-phase requester

Initial state: `ENUM_ST_HSK_IDLE`

Reset entry: `i_rst_n_bus` active-low.

![FSM: four-phase requester](<aesgcm_fsm_hsk.svg>)

Sources: [aesgcm_fsm_hsk.drawio](<aesgcm_fsm_hsk.drawio>) | [aesgcm_fsm_hsk.json](<aesgcm_fsm_hsk.json>) | [aesgcm_fsm_hsk_layout_report.txt](<aesgcm_fsm_hsk_layout_report.txt>)

## Transition and global state control mapping

| Kind | Label / effect | Boolean expression |
|---|---|---|
| Transition | condition true | `w_channel_cond` |
| Transition | ack seen | `w_ack_sync` |
| Transition | ack low | `!w_ack_sync` |
