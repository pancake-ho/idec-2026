#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import json
import re
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any


CLOCK_PERIOD_NS = 0.750


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
    cycles: float | None
    latency_ns: float | None
    energy_nj_per_image: float | None


def metric(data: dict[str, Any], *names: str) -> Any:
    for name in names:
        if name in data:
            return data[name]
    raise KeyError(f"none of these metrics are present: {', '.join(names)}")


def read_cycles(package_root: Path) -> tuple[float | None, float | None]:
    cycle_log = package_root / "build/vivado/cycle_ab/xsim.log"
    if not cycle_log.exists():
        return None, None

    text = cycle_log.read_text(encoding="utf-8", errors="replace")
    v18 = re.search(r"V18A cycles\s*:\s*avg=([0-9.]+)", text)
    v19 = re.search(r"PFDW FAR cycles\s*:\s*avg=([0-9.]+)", text)
    return (
        float(v18.group(1)) if v18 else None,
        float(v19.group(1)) if v19 else None,
    )


def load_row(
    design: str,
    metadata_path: Path,
    cycles: float | None,
) -> Row:
    data = json.loads(metadata_path.read_text(encoding="utf-8"))

    area = float(
        metric(
            data,
            "finish__design__instance__area__stdcell",
            "finish__design__instance__area",
        )
    )
    cells = int(
        round(
            float(
                metric(
                    data,
                    "finish__design__instance__count__stdcell",
                    "finish__design__instance__count",
                )
            )
        )
    )
    sequential = int(
        round(
            float(
                metric(
                    data,
                    "finish__design__instance__count__class__sequential_cell",
                    "finish__design__instance__count__class:sequential_cell",
                    "finish__design__instance__count__sequential",
                )
            )
        )
    )

    # Pinned ASAP7 ORFS metadata uses W for power and ps for timing.
    power_raw_w = float(metric(data, "finish__power__total"))
    power_mw = power_raw_w * 1e3

    wns_ps = float(metric(data, "finish__timing__setup__ws"))
    tns_ps = float(metric(data, "finish__timing__setup__tns"))

    latency_ns = cycles * CLOCK_PERIOD_NS if cycles is not None else None
    energy_nj = (
        power_mw * latency_ns / 1000.0 if latency_ns is not None else None
    )

    return Row(
        design=design,
        area_um2=area,
        cells=cells,
        sequential_cells=sequential,
        power_mw=power_mw,
        setup_wns_ps=wns_ps,
        setup_tns_ps=tns_ps,
        timing_met="YES" if wns_ps >= 0.0 and abs(tns_ps) < 1e-9 else "NO",
        cycles=cycles,
        latency_ns=latency_ns,
        energy_nj_per_image=energy_nj,
    )


def show(value: float | int | None, digits: int = 3) -> str:
    if value is None:
        return "N/A"
    if isinstance(value, int):
        return str(value)
    return f"{value:.{digits}f}"


def percent_delta(new: float, old: float) -> float:
    return (new - old) * 100.0 / old


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--package-root", type=Path, required=True)
    parser.add_argument("--csv", type=Path, required=True)
    parser.add_argument("--markdown", type=Path, required=True)
    args = parser.parse_args()

    package_root = args.package_root.resolve()
    paths = {
        "V18A": package_root
        / "reports/asap7/chip_v18a_far_ab/base/metadata.json",
        "V19 FAR": package_root
        / "reports/asap7/chip_v19_far/base/metadata.json",
    }

    missing = [str(path) for path in paths.values() if not path.is_file()]
    if missing:
        details = "\n".join(f"  - {path}" for path in missing)
        raise SystemExit(
            "ERROR: ORFS metadata is missing. Run scripts/run_orfs_ab.sh first.\n"
            + details
        )

    v18_cycles, v19_cycles = read_cycles(package_root)
    rows = [
        load_row("V18A", paths["V18A"], v18_cycles),
        load_row("V19 FAR", paths["V19 FAR"], v19_cycles),
    ]

    args.csv.parent.mkdir(parents=True, exist_ok=True)
    with args.csv.open("w", encoding="utf-8", newline="") as csv_file:
        writer = csv.DictWriter(csv_file, fieldnames=list(asdict(rows[0]).keys()))
        writer.writeheader()
        writer.writerows(asdict(row) for row in rows)

    v18, v19 = rows
    lines = [
        "# FAR-PFDW V19 PPA A/B",
        "",
        f"Clock period: {CLOCK_PERIOD_NS * 1000:.0f} ps",
        "",
        "| Metric | V18A | V19 FAR | V19 delta |",
        "|---|---:|---:|---:|",
        f"| Area (um^2) | {show(v18.area_um2)} | {show(v19.area_um2)} | "
        f"{percent_delta(v19.area_um2, v18.area_um2):+.2f}% |",
        f"| Cells | {v18.cells} | {v19.cells} | {v19.cells - v18.cells:+d} |",
        f"| Sequential cells | {v18.sequential_cells} | "
        f"{v19.sequential_cells} | "
        f"{v19.sequential_cells - v18.sequential_cells:+d} |",
        f"| Power (mW) | {show(v18.power_mw)} | {show(v19.power_mw)} | "
        f"{percent_delta(v19.power_mw, v18.power_mw):+.2f}% |",
        f"| Setup WNS (ps) | {show(v18.setup_wns_ps)} | "
        f"{show(v19.setup_wns_ps)} | - |",
        f"| Setup TNS (ps) | {show(v18.setup_tns_ps)} | "
        f"{show(v19.setup_tns_ps)} | - |",
        f"| Timing met | {v18.timing_met} | {v19.timing_met} | - |",
        f"| Cycles/image | {show(v18.cycles, 2)} | {show(v19.cycles, 2)} | "
        + (
            f"{v19.cycles - v18.cycles:+.2f} |"
            if v18.cycles is not None and v19.cycles is not None
            else "N/A |"
        ),
        f"| Latency (ns/image) | {show(v18.latency_ns)} | "
        f"{show(v19.latency_ns)} | "
        + (
            f"{percent_delta(v19.latency_ns, v18.latency_ns):+.2f}% |"
            if v18.latency_ns is not None and v19.latency_ns is not None
            else "N/A |"
        ),
        f"| Energy (nJ/image) | {show(v18.energy_nj_per_image)} | "
        f"{show(v19.energy_nj_per_image)} | "
        + (
            f"{percent_delta(v19.energy_nj_per_image, v18.energy_nj_per_image):+.2f}% |"
            if v18.energy_nj_per_image is not None
            and v19.energy_nj_per_image is not None
            else "N/A |"
        ),
        "",
    ]

    if v18.timing_met != "YES" or v19.timing_met != "YES":
        lines.append(
            "WARNING: at least one run violates timing; do not use its power as "
            "the final comparison."
        )
    if v18_cycles is None or v19_cycles is None:
        lines.append(
            "NOTE: cycle_ab/xsim.log was not found or did not contain cycle "
            "summaries, so latency and energy are N/A."
        )

    args.markdown.parent.mkdir(parents=True, exist_ok=True)
    args.markdown.write_text("\n".join(lines) + "\n", encoding="utf-8")

    print("\n".join(lines))
    print(f"CSV      : {args.csv}")
    print(f"Markdown : {args.markdown}")


if __name__ == "__main__":
    main()
