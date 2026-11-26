# FSM: message sequencer, data view

Initial state: `ENUM_ST_SEQ_AAD`

Continuation entry: `FSM_SEQ_SETUP -> ENUM_ST_SEQ_AAD; FSM_SEQ_SETUP -> ENUM_ST_SEQ_PY_CFG`.

![FSM: message sequencer, data view](<aesgcm_fsm_seq_data.svg>)

Sources: [aesgcm_fsm_seq_data.drawio](<aesgcm_fsm_seq_data.drawio>) | [aesgcm_fsm_seq_data.json](<aesgcm_fsm_seq_data.json>) | [aesgcm_fsm_seq_data_layout_report.txt](<aesgcm_fsm_seq_data_layout_report.txt>)

## Transition and global state control mapping

| Kind | Label / effect | Boolean expression |
|---|---|---|
| Transition | AAD done | `w_aad_bytes_done && w_pass != 2'd1` |
| Transition | AAD done pass 1 | `w_aad_bytes_done && w_pass == 2'd1` |
| Transition | core configured | `i_core_cfg_valid && o_core_cfg_ready` |
| Transition | legacy done | `w_pay_bytes_done && w_core_drained && !w_mode_gcm` |
| Transition | length absorbed | `w_ghash_valid` |
| Transition | payload done | `w_pay_bytes_done && w_core_drained && w_mode_gcm` |
| Transition | tag compared | `w_tag_done` |
