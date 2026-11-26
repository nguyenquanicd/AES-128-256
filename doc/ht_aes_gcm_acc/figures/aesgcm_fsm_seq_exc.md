# FSM: message sequencer, completion and exception view

Initial state: `ENUM_ST_SEQ_FIN`

Continuation entry: `FSM_SEQ_DATA -> ENUM_ST_SEQ_FIN`.

![FSM: message sequencer, completion and exception view](<aesgcm_fsm_seq_exc.svg>)

Sources: [aesgcm_fsm_seq_exc.drawio](<aesgcm_fsm_seq_exc.drawio>) | [aesgcm_fsm_seq_exc.json](<aesgcm_fsm_seq_exc.json>) | [aesgcm_fsm_seq_exc_layout_report.txt](<aesgcm_fsm_seq_exc_layout_report.txt>)

## Global next-state overrides

- `G1`: `ANY STATE except IDLE, FIN -> ENUM_ST_SEQ_ABRT`; guard: `w_cmd_abort || w_cmd_zeroize || w_fatal_err || w_keywait_expired`
  Highest priority after reset. Fatal errors are LEN_ERR, CTR_EXHAUST, PROTO_ERR and KEY_ERR (side-load wait expired).
- `G2`: `AAD or PAY -> ENUM_ST_SEQ_SUSP`; guard: `w_cmd_suspend && w_block_boundary && w_core_drained && w_ctx_slots_en`
  Lower priority than G1 and higher than the normal transitions of AAD and PAY.

## Transition and global state control mapping

| Kind | Label / effect | Boolean expression |
|---|---|---|
| Transition | cleanup done | `w_zero_done` |
| Transition | context saved | `w_ctx_done` |
| Transition | status accepted | `w_status_ack` |
| Global control | G1: ANY STATE except IDLE, FIN -> ENUM_ST_SEQ_ABRT | `w_cmd_abort \|\| w_cmd_zeroize \|\| w_fatal_err \|\| w_keywait_expired` |
| Global control | G2: AAD or PAY -> ENUM_ST_SEQ_SUSP | `w_cmd_suspend && w_block_boundary && w_core_drained && w_ctx_slots_en` |
