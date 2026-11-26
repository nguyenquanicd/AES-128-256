# FSM: message sequencer, setup view

Initial state: `ENUM_ST_SEQ_IDLE`

Reset entry: `i_rst_n_core` active-low.

![FSM: message sequencer, setup view](<aesgcm_fsm_seq_setup.svg>)

Sources: [aesgcm_fsm_seq_setup.drawio](<aesgcm_fsm_seq_setup.drawio>) | [aesgcm_fsm_seq_setup.json](<aesgcm_fsm_seq_setup.json>) | [aesgcm_fsm_seq_setup_layout_report.txt](<aesgcm_fsm_seq_setup_layout_report.txt>)

## Transition and global state control mapping

| Kind | Label / effect | Boolean expression |
|---|---|---|
| Transition | context restored | `w_ctx_done` |
| Transition | core configured | `i_core_cfg_valid && o_core_cfg_ready` |
| Transition | key ready GCM | `w_key_ready && w_mode_gcm && (w_pass == 2'd0 \|\| w_pass == 2'd1)` |
| Transition | key ready no setup | `w_key_ready && (!w_mode_gcm \|\| w_pass == 2'd2)` |
| Transition | new message | `w_bundle_valid && !w_cmd_resume && w_cfg_legal` |
| Transition | powers ready | `w_pow_done` |
| Transition | resume | `w_cmd_resume && w_slot_valid` |
| Transition | setup results | `w_h_captured && w_ej0_captured` |
