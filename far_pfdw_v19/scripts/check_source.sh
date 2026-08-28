#!/usr/bin/env bash
set -euo pipefail

package_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

required_files=(
  rtl/pfdw_pipe49_booth_engine_v19_far.sv
  rtl/chip_pfdw_fc_v19_far.sv
  rtl/chip_v19_far_top.v
  reference_v18a/pfdw_pipe49_booth_engine_v18a.sv
  reference_v18a/chip_pfdw_fc_v18a.sv
  reference_v18a/chip_v18a_top.v
  tb/top_tb_far_1000.sv
  tb/top_tb_far_vs_v18a_1000.sv
  tb/top_tb_cycle_far_vs_v18a.sv
  tb/top_tb_far_vs_baseline_1000.sv
  tb/top_tb_cycle_far_vs_baseline.sv
  tb/top_tb_gate_far_1000.sv
  orfs/chip_v18a/config.mk
  orfs/chip_v18a/constraint.sdc
  orfs/chip_v19_far/config.mk
  orfs/chip_v19_far/constraint.sdc
)

for relative_path in "${required_files[@]}"; do
  if [[ ! -s "$package_root/$relative_path" ]]; then
    echo "ERROR: missing or empty file: $relative_path" >&2
    exit 1
  fi
done

for shell_script in "$package_root"/scripts/*.sh; do
  bash -n "$shell_script"
done

python3 - "$package_root" <<'PY'
from __future__ import annotations

import re
import sys
from pathlib import Path

root = Path(sys.argv[1])
hdl_files = sorted(root.glob("rtl/*.[sv]*"))
hdl_files += sorted(root.glob("reference_v18a/*.[sv]*"))
hdl_files += sorted(root.glob("tb/*.sv"))

if not hdl_files:
    raise SystemExit("ERROR: no HDL source files found")


def strip_comments(text: str) -> str:
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return re.sub(r"//.*", "", text)


pairs = (
    ("module", "endmodule"),
    ("function", "endfunction"),
    ("task", "endtask"),
    ("case", "endcase"),
    ("generate", "endgenerate"),
    ("begin", "end"),
)

for path in hdl_files:
    text = strip_comments(path.read_text(encoding="utf-8"))
    for opening, closing in pairs:
        open_count = len(re.findall(rf"\b{opening}\b", text))
        close_count = len(re.findall(rf"\b{closing}\b", text))
        if open_count != close_count:
            raise SystemExit(
                f"ERROR: {path.relative_to(root)} has "
                f"{opening}/{closing}={open_count}/{close_count}"
            )

    if re.search(r"[A-Za-z]:[/\\]", text):
        raise SystemExit(
            f"ERROR: absolute Windows path remains in {path.relative_to(root)}"
        )

v19_top = (root / "rtl/chip_v19_far_top.v").read_text(encoding="utf-8")
v18_top = (root / "reference_v18a/chip_v18a_top.v").read_text(
    encoding="utf-8"
)
if not re.search(r"\bmodule\s+chip\b", v19_top):
    raise SystemExit("ERROR: V19 ORFS wrapper must expose module chip")
if not re.search(r"\bmodule\s+chip\b", v18_top):
    raise SystemExit("ERROR: V18A ORFS wrapper must expose module chip")

print(f"HDL structural checks: PASS ({len(hdl_files)} files)")
PY

echo "Shell syntax checks: PASS"
echo "NOTE: this is a structural check, not a SystemVerilog compile."
