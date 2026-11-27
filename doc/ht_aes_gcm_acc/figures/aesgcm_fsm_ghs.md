# FSM: digit-serial multiplier control

Initial state: `ENUM_ST_GHS_IDLE`

Reset entry: `i_rst_n_core` active-low.

![FSM: digit-serial multiplier control](<aesgcm_fsm_ghs.svg>)

Sources: [aesgcm_fsm_ghs.drawio](<aesgcm_fsm_ghs.drawio>) | [aesgcm_fsm_ghs.json](<aesgcm_fsm_ghs.json>) | [aesgcm_fsm_ghs_layout_report.txt](<aesgcm_fsm_ghs_layout_report.txt>)

## Global next-state overrides

- `G1`: `ANY STATE -> ENUM_ST_GHS_IDLE`; guard: `w_cmd_abort`
  Abort forces idle.

## Transition and global state control mapping

| Kind | Label / effect | Boolean expression |
|---|---|---|
| Transition | operands valid | `i_valid && o_ready` |
| Transition | last digit | `w_digit_cnt == LPARA_DIGIT_LAST` |
| Transition | result taken | `1'b1` |
| Global control | G1: ANY STATE -> ENUM_ST_GHS_IDLE | `w_cmd_abort` |
