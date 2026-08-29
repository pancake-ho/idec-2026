#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import json
import re
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any


CLOCK_NS = 0.750


@dataclass
class Row:
    design: str
    area_um2: float
    cells: int
    sequential_cells: int
    power_mw: float
    setup_wns_ps: float
    setup_tns_ps: float
    timing_met: str
    estimated_fmax_ghz: float
    cycles: float | None
    latency_ns: float | None
    energy_nj_per_image: float | None


def metric(data: dict[str, Any], *names: str) -> Any:
    for name in names:
        if name in data:
            return data[name]
    raise KeyError(", ".join(names))


def cycles(package_root: Path) -> tuple[float | None, float | None]:
    path = package_root / "build/vivado/cycle_ab/xsim.log"
    if not path.is_file():
        return None, None
    text = path.read_text(encoding="utf-8", errors="replace")
    v18 = re.search(r"V18A cycles\s*:\s*avg=([0-9.]+)", text)
    v20 = re.search(r"PFDW V20 W5 cycles\s*:\s*avg=([0-9.]+)", text)
    return (
        float(v18.group(1)) if v18 else None,
        float(v20.group(1)) if v20 else None,
    )


def load_row(name: str, path: Path, cycle_count: float | None) -> Row:
    data = json.loads(path.read_text())
    area = float(metric(data, "finish__design__instance__area__stdcell", "finish__design__instance__area"))
    cells = int(round(float(metric(data, "finish__design__instance__count__stdcell", "finish__design__instance__count"))))
    sequential = int(round(float(metric(
        data,
        "finish__design__instance__count__class__sequential_cell",
        "finish__design__instance__count__class:sequential_cell",
        "finish__design__instance__count__sequential",
    ))))
    power_mw = float(metric(data, "finish__power__total")) * 1e3
    wns_ps = float(metric(data, "finish__timing__setup__ws"))
    tns_ps = float(metric(data, "finish__timing__setup__tns"))
    effective_period_ns = CLOCK_NS + max(0.0, -wns_ps / 1000.0)
    latency_ns = cycle_count * CLOCK_NS if cycle_count is not None else None
    energy_nj = power_mw * latency_ns / 1000.0 if latency_ns is not None else None
    return Row(
        design=name,
        area_um2=area,
        cells=cells,
        sequential_cells=sequential,
        power_mw=power_mw,
        setup_wns_ps=wns_ps,
        setup_tns_ps=tns_ps,
        timing_met="YES" if wns_ps >= 0.0 and abs(tns_ps) < 1e-9 else "NO",
        estimated_fmax_ghz=1.0 / effective_period_ns,
        cycles=cycle_count,
        latency_ns=latency_ns,
        energy_nj_per_image=energy_nj,
    )


def delta(new: float, old: float) -> float:
    return (new - old) * 100.0 / old


def show(value: float | None, digits: int = 3) -> str:
    return "N/A" if value is None else f"{value:.{digits}f}"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--package-root", type=Path, required=True)
    parser.add_argument("--csv", type=Path, required=True)
    parser.add_argument("--markdown", type=Path, required=True)
    args = parser.parse_args()
    root = args.package_root.resolve()
    paths = (
        root / "reports/asap7/chip_v18a_v20_ab/base/metadata.json",
        root / "reports/asap7/chip_v20_pow2/base/metadata.json",
    )
    missing = [str(path) for path in paths if not path.is_file()]
    if missing:
        raise SystemExit("ERROR: metadata missing:\n" + "\n".join(f"  - {x}" for x in missing))
    v18_cycles, v20_cycles = cycles(root)
    v18 = load_row("V18A", paths[0], v18_cycles)
    v20 = load_row("V20 W5", paths[1], v20_cycles)
    rows = (v18, v20)

    args.csv.parent.mkdir(parents=True, exist_ok=True)
    with args.csv.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(asdict(v18)))
        writer.writeheader()
        writer.writerows(asdict(row) for row in rows)

    lines = [
        "# PFDW V18A vs V20 W5 PPA",
        "",
        "Python bit-exact precheck: V18A 970/1000, V20 980/1000.",
        "",
        "| Metric | V18A | V20 W5 | Delta |",
        "|---|---:|---:|---:|",
        f"| Area (um^2) | {v18.area_um2:.3f} | {v20.area_um2:.3f} | {delta(v20.area_um2, v18.area_um2):+.2f}% |",
        f"| Cells | {v18.cells} | {v20.cells} | {v20.cells-v18.cells:+d} |",
        f"| Sequential cells | {v18.sequential_cells} | {v20.sequential_cells} | {v20.sequential_cells-v18.sequential_cells:+d} |",
        f"| Power (mW) | {v18.power_mw:.3f} | {v20.power_mw:.3f} | {delta(v20.power_mw, v18.power_mw):+.2f}% |",
        f"| Setup WNS (ps) | {v18.setup_wns_ps:.3f} | {v20.setup_wns_ps:.3f} | {v20.setup_wns_ps-v18.setup_wns_ps:+.3f} |",
        f"| Setup TNS (ps) | {v18.setup_tns_ps:.3f} | {v20.setup_tns_ps:.3f} | {v20.setup_tns_ps-v18.setup_tns_ps:+.3f} |",
        f"| Estimated Fmax (GHz) | {v18.estimated_fmax_ghz:.3f} | {v20.estimated_fmax_ghz:.3f} | {delta(v20.estimated_fmax_ghz, v18.estimated_fmax_ghz):+.2f}% |",
        f"| Timing met @ 750 ps | {v18.timing_met} | {v20.timing_met} | - |",
        f"| Cycles/image | {show(v18.cycles, 2)} | {show(v20.cycles, 2)} | - |",
        f"| Latency (ns/image) | {show(v18.latency_ns)} | {show(v20.latency_ns)} | - |",
        f"| Energy (nJ/image) | {show(v18.energy_nj_per_image)} | {show(v20.energy_nj_per_image)} | - |",
        "",
    ]
    if v18.timing_met != "YES" or v20.timing_met != "YES":
        lines.append("WARNING: timing is not closed; power is provisional and Fmax is the comparison metric.")
    if v18_cycles is None or v20_cycles is None:
        lines.append("NOTE: copy the Vivado cycle_ab/xsim.log before calculating latency/energy.")
    args.markdown.parent.mkdir(parents=True, exist_ok=True)
    args.markdown.write_text("\n".join(lines) + "\n")
    print("\n".join(lines))
    print(f"CSV: {args.csv}")
    print(f"Markdown: {args.markdown}")


if __name__ == "__main__":
    main()
