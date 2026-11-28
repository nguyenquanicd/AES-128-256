"""Waveform evidence of rule R-033 for the AES-GCM accelerator.

For every WF scenario of the specification: read the simulated VCD (scope tb_aesgcm_top.u_wf), compare the
order of the first transitions of the rows of the specification figure with the simulation, write the
WaveJSON of the simulated window and its SVG, and print one row of waveform_compare.md.

Usage: python wfevidence.py <repo> <waveforms_sim> <out_md>
"""
import json
import statistics
import subprocess
import sys
from pathlib import Path

REPO = Path(sys.argv[1])
SIM = Path(sys.argv[2])
OUT_MD = Path(sys.argv[3])
FIG = REPO / "doc" / "ht_aes_gcm_acc" / "figures"
SKILL = Path.home() / ".claude" / "skills"
W2J = SKILL / "vlsit-wavedrom-waveform" / "scripts" / "vlsit_wavedrom_waveform.py"
SVG = SKILL / "vlsit-asic-ip-microspec" / "scripts" / "vlsit_waveform_svg.py"
SCOPE = "tb_aesgcm_top.u_wf."
MAXCYC = 380

ALIASES = {
    "i_axi_awlen_burst": ["i_axi_awlen", "i_axi_awburst"],
    "fifo_push": ["fifo_push", "out_fifo_push"],
}


def read_vcd(path):
    ids = {}
    scope = []
    changes = {}
    cur = 0
    header = True
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            line = line.strip()
            if header:
                if line.startswith("$scope"):
                    scope.append(line.split()[2])
                elif line.startswith("$upscope"):
                    scope.pop()
                elif line.startswith("$var"):
                    p = line.split()
                    full = ".".join(scope + [p[4]])
                    if full.startswith(SCOPE):
                        ids.setdefault(p[3], []).append(full[len(SCOPE):])
                elif line.startswith("$enddefinitions"):
                    header = False
                continue
            if not line:
                continue
            if line[0] == "#":
                cur = int(line[1:])
                continue
            if line[0] in "01xzXZ":
                val, ident = line[0], line[1:]
            elif line[0] == "b":
                a = line.split()
                val, ident = a[0][1:], a[1]
            else:
                continue
            for name in ids.get(ident, []):
                changes.setdefault(name, []).append((cur, val))
    return changes


def spec_rows(js):
    rows = []
    for item in js["signal"]:
        if isinstance(item, dict) and "name" in item:
            rows.append((item["name"], item.get("wave", "")))
    return rows


def expand(wave):
    out = []
    for ch in wave:
        out.append(out[-1] if (ch == "." and out) else ch)
    return out


def spec_first_event(wave):
    """First cycle at which the row changes: a new level, or a new data cell ('=')."""
    if not wave or wave[0] in "pPnN":
        return None
    prev = wave[0]
    for i, ch in enumerate(wave[1:], 1):
        if ch == ".":
            continue
        if ch == "=" or ch != prev:
            return i
        prev = ch
    return None


def bus_period(ch):
    clk = ch.get("i_clk_bus", [])
    rises = [t for (t, v) in clk if v == "1"]
    if len(rises) < 3:
        return None
    d = [b - a for a, b in zip(rises, rises[1:])]
    return int(statistics.median(d))


def sim_first_change(ch, names):
    best = None
    for n in names:
        lst = ch.get(n, [])
        if len(lst) < 2:
            continue
        t0 = lst[0][0]
        first = next((t for (t, v) in lst[1:] if v != lst[0][1]), None)
        if first is not None and first > t0:
            best = first if best is None else min(best, first)
    return best


def run(cmd):
    return subprocess.run([sys.executable, "-I", *map(str, cmd)], capture_output=True, text=True)


rows_md = []
for fig in sorted(FIG.glob("WF-0*_*.json")):
    stem = fig.stem
    wid = stem.split("_")[0]
    spec_svg = f"doc/ht_aes_gcm_acc/figures/{stem}.svg"
    sim_vcd = SIM / f"{stem}.vcd"
    sim_svg = f"waveforms_sim/{stem}.svg"
    if not sim_vcd.exists():
        rows_md.append(f"| {wid} | {spec_svg} | {sim_svg} | NOT-SIMULATED | no dump of this run | ")
        continue
    js = json.loads(fig.read_text(encoding="utf-8"))
    ch = read_vcd(sim_vcd)
    per = bus_period(ch)
    spec = spec_rows(js)
    spec_n = max((len(expand(w)) for _, w in spec), default=16)
    matched, unmapped, events = [], [], []
    for name, wave in spec:
        if name.startswith("i_clk") or name.startswith("clk"):
            continue
        cand = [c for c in ALIASES.get(name, [name]) if c in ch]
        ev = spec_first_event(wave)
        if not cand:
            unmapped.append(name)
            continue
        matched.append((name, cand))
        t = sim_first_change(ch, cand)
        if ev is not None and t is not None:
            events.append((name, ev, t))
    viol = []
    if per:
        for i in range(len(events)):
            for j in range(len(events)):
                a, b = events[i], events[j]
                if a[1] < b[1] and a[2] > b[2] + per:
                    viol.append(f"{a[0]} (cycle {a[1]}) after {b[0]} (cycle {b[1]})")
                elif a[1] == b[1] and i < j and abs(a[2] - b[2]) > 3 * per:
                    viol.append(f"{a[0]} and {b[0]} not together")
    # WaveJSON window
    status = ""
    if per and events:
        t_first = min(t for _, _, t in events)
        start = max(0, t_first - 2 * per)
        end = start + min(MAXCYC, max(60, 4 * spec_n)) * per
        sigs = ["tb_aesgcm_top.u_wf.i_clk_bus"] + [SCOPE + c for _, cs in matched for c in cs]
        sigs = list(dict.fromkeys(sigs))
        out_json = SIM / f"{stem}.json"
        r = run([W2J, "vcd-to-wavejson", sim_vcd, "--signals", ",".join(sigs), "--start", start, "--end", end,
                 "--period", per, "--out", out_json, "--force"])
        if r.returncode != 0:
            status = "WaveJSON error: " + (r.stderr or r.stdout).strip().splitlines()[-1][:80]
        else:
            r2 = run([SVG, "render", out_json, "--out", SIM / f"{stem}.svg", "--force"])
            if r2.returncode != 0:
                status = "SVG error: " + (r2.stderr or r2.stdout).strip().splitlines()[-1][:80]
    else:
        status = "no usable window"
    if status:
        result = "DIFFERENT"
        note = status
    elif viol:
        result = "DIFFERENT"
        note = "order of first transitions: " + "; ".join(viol[:3])
    elif len(events) >= 2:
        result = "MATCH"
        note = f"first-transition order of {len(events)} rows equals the figure"
    else:
        result = "DIFFERENT"
        note = f"only {len(events)} comparable row(s)"
    if unmapped:
        note += "; not in the view: " + ", ".join(unmapped)
    note += "; automatic screening, designer review PENDING"
    rows_md.append(f"| {wid} | {spec_svg} | {sim_svg} | {result} | {note} |")

hdr = (
    "# Waveform comparison index (rule R-033)\n\n"
    "Each row compares the figure of the specification with the window simulated by `+TEST=WF-nnn` "
    "(VCD, WaveJSON and SVG with the same stem in this folder). The result is an automatic screening "
    "(`wfevidence.py`, the order of the first transition of every row that the testbench view `u_wf` "
    "exposes, within the figure's tolerance of one bus clock); the designer's visual review of each pair "
    "is still PENDING. DIFFERENT would need the analysis of rule R-026.\n\n"
    "| Waveform ID | Specification figure | Simulated waveform | Result | Note |\n|---|---|---|---|---|\n"
)
OUT_MD.write_text(hdr + "\n".join(rows_md) + "\n", encoding="utf-8")
print("\n".join(rows_md))
