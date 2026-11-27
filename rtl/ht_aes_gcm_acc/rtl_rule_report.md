# RTL rule-ID report (vlsit-rtl-generator, R-016)

Run of 2026-11-25 and 2026-11-26, generate mode, specification `doc/ht_aes_gcm_acc/VLSIT_AES_GCM_ACCELERATOR_HDS.md` (original tagged `aes-gcm-hds-v0.1`), rule file `VLSIT_RTL_Design_Rule.md` v2.

## Commands to repeat the checks

```powershell
python "%USERPROFILE%\.claude\skills\vlsit-rtl-generator\scripts\vlsit_rtl_check.py" check rtl\ht_aes_gcm_acc --report rtl\ht_aes_gcm_acc\rtl_check_report.md
python "%USERPROFILE%\.claude\skills\vlsit-rtl-generator\scripts\vlsit_lint_rtl.py" lint rtl\ht_aes_gcm_acc\filelist.f --top m_aesgcm_acc_apb_top
python "%USERPROFILE%\.claude\skills\vlsit-rtl-generator\scripts\vlsit_lint_rtl.py" lint rtl\ht_aes_gcm_acc\filelist.f --top m_aesgcm_acc_axi_top
python "%USERPROFILE%\.claude\skills\vlsit-rtl-generator\scripts\vlsit_csr_generate.py" verify rtl\ht_aes_gcm_acc\csr
```

## Results by rule ID

| Group | Rule IDs | Result |
|---|---|---|
| Failed | none | - |
| Clean by script (`vlsit_rtl_check.py`, 27 files, 0 ERROR) | 71 script-checked rules, including NAM-TBL, NAM-07, NAM-08, NAM-09, TYP-02, PAR-01, PAR-02, ENM-01, ENM-03 to ENM-06, COM-02 to COM-11, SEQ-01, HIE-01, HIE-03, HIE-05, FIL-01 to FIL-06, CMT-05, P1 to P33 (script part), R-019, R-027, R-032, R-035, R-036, R-038, R-071, R-072 | PASS, see `rtl_check_report.md` |
| Warnings, justified (R-013) | HIE-02 (modules with instances and logic: deviation recorded in each header), PAR-03 (bit widths and fixed field positions of the bundles), CMT-01 (short assign groups) | 69 warnings, no ERROR |
| Lint (R-014) | Verilator 5.053 `--lint-only -Wall` | PASS, 0 errors on both tops (`lint_apb_top.log`, `lint_axi_top.log`: unused-signal warnings of tie-offs and library branches only); also clean on CFG-LINK, CFG-BOOT, CFG-FULL, CFG-LEGACY, CFG-MIN, export mode, and 4 lanes with pipeline and related clocks |
| Generated CSR (R-039 to R-043, R-073 to R-087) | `m_vlsit_csr_aesgcm` from `aesgcm_CSR.xlsx` with generator 3.7, Register Event Sideband = 1, `PARA_ASYNCHRONOUS` = 0, ports connected by name | `verify` PASS; rule check 0 ERROR (generated warnings not edited, R-073); the workbook row "Register Event Sideband" was added by hand because `vlsit_csr_tool.py fill` does not write it |
| Inspected by hand | R-001 to R-007 (only verified results reported, protected files, rule file read, specification scanned, questions asked with options, header data from the designer), R-010 (no testbench code in design RTL), R-011 (deviations in headers), R-017, R-018 (`filelist.f`, output folder), R-020 (FSM structure of the examples), R-037, R-049 to R-053 (library reuse offered, approved as DEC-016, instantiated), R-044, R-045 | Met |
| Implementation decisions (R-046, R-054 to R-061) | DEC-019 to DEC-024 recorded with options and reason, examples in section 10.4 items 7 to 9, WF-023, TEST-032 to TEST-036, decision IDs in the RTL headers; the original specification is tagged and was edited in place with the designer's approval | Met. R-054: the decisions of 2026-11-25 were taken after the RTL modules existed and were written to the specification before the next RTL change |
| Not applicable | R-008, R-009 (modify mode), R-028, R-062, R-032 cell models (no new technology cells), R-079 to R-081 (synchronous CSR) | - |
| Not run | R-022 to R-026, R-033, R-034, R-047, R-048, R-090 to R-098 (simulation testbench deliverable, assertions, waveform evidence, CDC branch runs with three seeds, coverage, fault detection) | Not requested yet (R-022). Scratch smoke simulations against an independent GCM model passed in 5 configurations, but they are not the deliverable |

## Notes

- `m_aesgcm_bus_dom`, `m_aesgcm_xing`, `m_aesgcm_acc_apb_top` and `m_aesgcm_acc_axi_top` were produced by scratch generator scripts; their `Decisions` header lines were added after generation.
- Illegal parameter values are reported by `verification/ht_aes_gcm_acc/m_aesgcm_param_check.sv` (DEC-019); synthesis alone does not check them.
