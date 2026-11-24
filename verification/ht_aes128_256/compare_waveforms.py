#!/usr/bin/env python3
"""Structural comparison of a simulated WaveJSON trace with its approved spec figure.

The approved figures are illustrative (short, hand-drawn cycle counts and some
reduced parameters), so cycle-exact equality is not demanded. What is compared:

  * every digital (single-bit, non-clock) signal of the spec figure exists in the
    simulated trace;
  * a signal that never goes high in the spec figure never goes high in the
    simulation (for example "no result is produced");
  * a signal that goes high in the spec figure goes high in the simulation;
  * if the spec figure shows signal A rising strictly before signal B, the
    simulation must not show B rising before A.

Anything else (data values, exact latency) is checked by the testbench, not here.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

DIGITAL = set("01hHlL.")


def flatten(items):
    for item in items:
        if isinstance(item, dict):
            if "wave" in item and "name" in item:
                yield item
        elif isinstance(item, list):
            yield from flatten(item)


def expand(wave: str) -> list[str]:
    out: list[str] = []
    for ch in wave:
        out.append(out[-1] if (ch == "." and out) else ch)
    return out


def level(ch: str):
    if ch in "1hH":
        return 1
    if ch in "0lL":
        return 0
    return None


def rises(wave: str) -> list[int]:
    # A signal drawn high from the first sample counts as rising at sample 0.
    seq = [level(c) for c in expand(wave)]
    return [i for i in range(len(seq))
            if seq[i] == 1 and (i == 0 or seq[i - 1] != 1)]


def ever_high(wave: str) -> bool:
    return any(level(c) == 1 for c in expand(wave))


def digital_signals(doc: dict) -> dict[str, str]:
    result = {}
    for sig in flatten(doc.get("signal", [])):
        wave = sig["wave"]
        if wave and set(wave) <= DIGITAL and any(c != "." for c in wave):
            result[sig["name"]] = wave
    return result


def compare(spec_path: Path, sim_path: Path) -> list[str]:
    spec = digital_signals(json.loads(spec_path.read_text(encoding="utf-8")))
    sim_doc = json.loads(sim_path.read_text(encoding="utf-8"))
    sim_all = {s["name"]: s["wave"] for s in flatten(sim_doc.get("signal", []))}
    # Samples taken while the testbench still holds reset low are not part of the
    # scenario, so start every simulated wave at the first sample after reset release.
    if "i_rst_n_core" in sim_all:
        rst = [level(c) for c in expand(sim_all["i_rst_n_core"])]
        start = next((i for i, v in enumerate(rst) if v == 1), 0)
        sim_all = {n: w if len(w) <= start else "".join(expand(w)[start:])
                   for n, w in sim_all.items()}
    findings: list[str] = []
    first: dict[str, int] = {}
    for name, wave in spec.items():
        if name == "i_clk_core":
            continue
        if name not in sim_all:
            findings.append(f"{name}: missing in simulated trace")
            continue
        sim_wave = sim_all[name]
        spec_high = ever_high(wave)
        sim_high = ever_high(sim_wave) if set(sim_wave) <= DIGITAL | set("=x") else None
        if sim_high is None:
            findings.append(f"{name}: simulated trace is not single-bit")
            continue
        if not spec_high and sim_high:
            findings.append(f"{name}: spec stays low but simulation goes high")
        if spec_high and not sim_high:
            findings.append(f"{name}: spec goes high but simulation never does")
        sr = rises(wave)
        if sr:
            mr = rises(sim_wave)
            if not mr:
                if not (level(expand(sim_wave)[0]) == 1):
                    findings.append(f"{name}: spec shows a rising edge, simulation has none")
            else:
                first[name] = mr[0]
    spec_first = {n: rises(w)[0] for n, w in spec.items() if rises(w) and n != "i_clk_core"}
    # Reset is not part of the protocol order: the figures may start a handshake
    # while reset is still drawn low, whereas the testbench releases reset first.
    names = [n for n in spec_first if n in first and "rst" not in n]
    for a in names:
        for b in names:
            if spec_first[a] < spec_first[b] and first[a] > first[b]:
                findings.append(f"order: spec has {a} rising before {b}, simulation has the opposite")
    return findings


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: compare_waveforms.py <spec.json> <sim.json>")
        return 2
    findings = compare(Path(sys.argv[1]), Path(sys.argv[2]))
    for line in findings:
        print("DIFF", line)
    print("MATCH" if not findings else "DIFF")
    return 1 if findings else 0


if __name__ == "__main__":
    raise SystemExit(main())
