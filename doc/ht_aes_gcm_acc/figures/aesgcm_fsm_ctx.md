# FSM: context engine

Initial state: `ENUM_ST_CTX_IDLE`

Reset entry: `i_rst_n_core` active-low.

![FSM: context engine](<aesgcm_fsm_ctx.svg>)

Sources: [aesgcm_fsm_ctx.drawio](<aesgcm_fsm_ctx.drawio>) | [aesgcm_fsm_ctx.json](<aesgcm_fsm_ctx.json>) | [aesgcm_fsm_ctx_layout_report.txt](<aesgcm_fsm_ctx_layout_report.txt>)

## Global next-state overrides

- `G1`: `ANY STATE -> ENUM_ST_CTX_IDLE`; guard: `w_cmd_zeroize`
  Zeroize forces idle and clears every slot; it has priority over every other transition.

## Transition and global state control mapping

| Kind | Label / effect | Boolean expression |
|---|---|---|
| Transition | request | `w_save_req \|\| w_load_req \|\| w_cmd_free \|\| w_word_req` |
| Transition | slot request | `w_save_req \|\| (w_load_req && w_slot_valid) \|\| w_cmd_free` |
| Transition | word request | `w_ctx_mode_exp && !w_secure_only && w_word_req` |
| Transition | last word | `w_word_idx_last` |
| Transition | word done | `w_word_ack` |
| Transition | reported | `1'b1` |
| Global control | G1: ANY STATE -> ENUM_ST_CTX_IDLE | `w_cmd_zeroize` |
