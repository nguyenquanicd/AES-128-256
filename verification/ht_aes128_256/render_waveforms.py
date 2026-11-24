#!/usr/bin/env python3
"""Run approved waveform scenarios and render VCD -> WaveJSON -> SVG evidence."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

from compare_waveforms import compare

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parents[1]
RTL_DIR = PROJECT / "rtl" / "ht_aes128_256"
EVIDENCE = HERE / "waveforms_sim"
LOGS = HERE / "logs"
SPEC_WAVES = PROJECT / "doc" / "ht_aes128_256" / "figures" / "waveforms"

STRUCTURE: dict[str, list[str]] = {}

SCENARIOS = [
    ("WF-001_config_key_select", "WF-001_config_key_select", "WF-001_config_key_select"),
    ("WF-002_aes128_ecb", "WF-002_aes128_ecb", "WF-002_aes128_ecb"),
    ("WF-003_aes256_ecb", "WF-003_aes256_ecb", "WF-003_aes256_ecb"),
    ("WF-004_ctr_allocate", "WF-004_ctr_allocate", "WF-004_ctr_allocate"),
    ("WF-005_ctr_wrap", "WF-005_ctr_wrap", "WF-005_ctr_wrap"),
    ("WF-006a_cbc_decrypt", "WF-006a_cbc_decrypt", "WF-006a_cbc_decrypt"),
    ("WF-006b_cbc_decrypt", "WF-006b_cbc_decrypt", "WF-006b_cbc_decrypt"),
    ("WF-007_cbc_encrypt_feedback", "WF-007_cbc_encrypt_feedback", "WF-007_cbc_encrypt_feedback"),
    ("WF-008_cfb_feedback", "WF-008_cfb_feedback", "WF-008_cfb_feedback"),
    ("WF-009_ofb_feedback", "WF-009_ofb_feedback", "WF-009_ofb_feedback"),
    ("WF-010a_backpressure", "WF-010a_backpressure", "WF-010a_backpressure"),
    ("WF-010b_backpressure", "WF-010b_backpressure", "WF-010b_backpressure"),
    ("WF-011_lane_mask_error", "WF-011_lane_mask_error", "WF-011_lane_mask_error"),
    ("WF-012a_reset_abort", "WF-012a_reset_abort", "WF-012a_reset_abort"),
    ("WF-012b_zeroize_abort", "WF-012b_zeroize_abort", "WF-012b_zeroize_abort"),
]

# WF-ID, simulated trace stems of the group, what the testbench itself checks for it.
# The Result column is NOT written here: it comes from compare_waveforms.py.
COMPARE_ROWS = [
    ("WF-001", ["WF-001_config_key_select"], "Handshakes and error 1 only; no data compare."),
    ("WF-002", ["WF-002_aes128_ecb"], "Golden data, C10 latency, II=1 inputs and outputs."),
    ("WF-003", ["WF-003_aes256_ecb"], "Golden data, C14 latency, II=1 inputs and outputs."),
    ("WF-004", ["WF-004_ctr_allocate"], "Golden data and lane mask."),
    ("WF-005", ["WF-005_ctr_wrap"], "Error 3, error accepted and cleared; no data compare."),
    ("WF-006", ["WF-006a_cbc_decrypt", "WF-006b_cbc_decrypt"], "Golden data, lane mask, last."),
    ("WF-007", ["WF-007_cbc_encrypt_feedback"], "Golden data, C10 latency, C11 feedback interval."),
    ("WF-008", ["WF-008_cfb_feedback"], "Golden data, C14 latency, C15 feedback interval."),
    ("WF-009", ["WF-009_ofb_feedback"], "Golden data, C14 latency, C15 feedback interval."),
    ("WF-010", ["WF-010a_backpressure", "WF-010b_backpressure"], "Golden data; output held for one stalled cycle."),
    ("WF-011", ["WF-011_lane_mask_error"], "Error codes 2 and 5 only."),
    ("WF-012", ["WF-012a_reset_abort", "WF-012b_zeroize_abort"], "Valid/error cleared; zeroize done pulse."),
]


def run(cmd: list[str], log_path: Path | None = None, cwd: Path = RTL_DIR,
        env: dict[str, str] | None = None) -> None:
    if log_path:
        log_path.parent.mkdir(parents=True, exist_ok=True)
        with log_path.open("w", encoding="utf-8") as log:
            result = subprocess.run(cmd, cwd=cwd, env=env, stdout=log,
                                    stderr=subprocess.STDOUT, check=False)
    else:
        result = subprocess.run(cmd, cwd=cwd, env=env, check=False)
    if result.returncode:
        if log_path:
            print(log_path.read_text(encoding="utf-8", errors="replace"))
        raise SystemExit(f"Command failed ({result.returncode}): {' '.join(cmd)}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sim", required=True, help="Compiled Verilator simulation executable")
    parser.add_argument("--converter", required=True, help="vlsit_wavedrom_waveform.py path")
    parser.add_argument("--renderer", required=True, help="vlsit_waveform_svg.py path")
    args = parser.parse_args()
    simulator = Path(args.sim).resolve()
    converter = Path(args.converter).resolve()
    renderer = Path(args.renderer).resolve()
    if not simulator.exists():
        raise SystemExit(f"Simulation executable not found: {simulator}")
    for path in (converter, renderer):
        if not path.exists():
            raise SystemExit(f"Waveform tool not found: {path}")

    EVIDENCE.mkdir(parents=True, exist_ok=True)
    LOGS.mkdir(parents=True, exist_ok=True)
    for stem, wave_id, spec_stem in SCENARIOS:
        vcd = EVIDENCE / f"{stem}.vcd"
        log = LOGS / f"{stem}.log"
        env = os.environ.copy()
        suite_bin = Path(r"C:\Tools\oss-cad-suite\bin")
        if suite_bin.exists():
            env["PATH"] = str(suite_bin) + os.pathsep + env.get("PATH", "")
        run([str(simulator), "+VEC_DIR=vectors/", f"+WAVE={wave_id}",
             f"+DUMP=waveforms_sim/{stem}.vcd"], log_path=log,
            cwd=HERE, env=env)

        reference = SPEC_WAVES / f"{spec_stem}.json"
        if not reference.exists():
            raise SystemExit(f"Approved specification waveform is missing: {reference}")
        signal_names = []
        for signal in json.loads(reference.read_text(encoding="utf-8"))["signal"]:
            name = signal.get("name")
            if name and name not in signal_names:
                signal_names.append(name)
        if not signal_names:
            raise SystemExit(f"No signals found in approved waveform JSON: {reference}")
        run([sys.executable, str(converter), "vcd-to-wavejson", str(vcd),
             "--signals", ",".join(signal_names), "--period", "10ns",
             "--out", str(EVIDENCE / f"{stem}.json"), "--force"], cwd=HERE)
        run([sys.executable, str(renderer), "render", str(EVIDENCE / f"{stem}.json"),
             "--out", str(EVIDENCE / f"{stem}.svg"), "--force"], cwd=HERE)
        print(f"PASS {stem}: VCD, WaveJSON and SVG")
        findings = compare(reference, EVIDENCE / f"{stem}.json")
        STRUCTURE[stem] = findings
        print(f"{'MATCH' if not findings else 'DIFF '} {stem}: structure vs approved figure")
        for line in findings:
            print(f"      {line}")

    index = [
        "# Waveform comparison / waveform đối chiếu",
        "",
        "Result is measured by compare_waveforms.py (signal presence, never-high signals, rising-edge order against the approved figure); data and latency are checked by the testbench, listed in Note. / Result do compare_waveforms.py đo (có tín hiệu, tín hiệu không bao giờ lên cao, thứ tự cạnh lên so với hình đã duyệt); dữ liệu và latency do testbench kiểm, ghi ở cột Note.",
        "",
        "| WF-ID | Specification figure | Simulated VCD | Result | Note |",
        "|---|---|---|---|---|",
    ]
    differences = 0
    for wid, stems, note in COMPARE_ROWS:
        issues = [f"{s}: {x}" for s in stems for x in STRUCTURE.get(s, ["not simulated"])]
        result = "MATCH" if not issues else "DIFF"
        differences += bool(issues)
        detail = note if not issues else note + " Differences: " + "; ".join(issues)
        index.append(f"| {wid} | [figure](../../../doc/ht_aes128_256/figures/waveforms/{stems[0]}.svg) | "
                     f"{stems[0]}.vcd | {result} | {detail} |")
    (EVIDENCE / "waveform_compare.md").write_text("\n".join(index) + "\n", encoding="utf-8")
    print(f"Rendered {len(SCENARIOS)} traces for the 12 approved waveform scenarios; {differences} with structural differences.")
    if differences:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
