#!/usr/bin/env bash
set -euo pipefail

package_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repo_root="$(cd "${package_root}/.." && pwd)"

python3 "${package_root}/scripts/generate_rtl.py" --check
python3 -m py_compile \
  "${package_root}/scripts/generate_rtl.py" \
  "${package_root}/scripts/search_pow2_mp.py" \
  "${package_root}/scripts/collect_ppa.py" \
  "${package_root}/scripts/verify_booth.py" \
  "${package_root}/scripts/verify_quantizers.py"
python3 "${package_root}/scripts/verify_booth.py"
python3 "${package_root}/scripts/verify_quantizers.py"

required=(
  rtl/pfdw_pipe49_booth_engine_v20_w5.sv
  rtl/chip_pfdw_fc_v20_pow2.sv
  rtl/chip_v20_pow2_top.v
  tb/top_tb_v20_1000.sv
  tb/top_tb_v20_vs_v18a_1000.sv
  tb/top_tb_cycle_v20_vs_v18a.sv
  tb/top_tb_v20_vs_baseline_1000.sv
  tb/top_tb_cycle_v20_vs_baseline.sv
  tb/top_tb_gate_v20_1000.sv
  orfs/chip_v18a/config.mk
  orfs/chip_v18a/constraint.sdc
  orfs/chip_v20_pow2/config.mk
  orfs/chip_v20_pow2/constraint.sdc
  quantization_manifest.json
  scripts/run_vivado_gate.sh
  scripts/run_vivado_gate.ps1
  scripts/verify_quantizers.py
)

for path in "${required[@]}"; do
  test -s "${package_root}/${path}" || {
    echo "ERROR: missing or empty: ${path}" >&2
    exit 1
  }
done

for script in "${package_root}"/scripts/*.sh; do
  bash -n "${script}"
done

python3 - "${package_root}" <<'PY'
from __future__ import annotations

import re
import sys
from pathlib import Path

root = Path(sys.argv[1])
hdl = sorted(root.glob("rtl/*.[sv]*")) + sorted(root.glob("tb/*.sv"))

def strip_comments(text: str) -> str:
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return re.sub(r"//.*", "", text)

for path in hdl:
    text = strip_comments(path.read_text())
    for opening, closing in (
        ("module", "endmodule"),
        ("function", "endfunction"),
        ("case", "endcase"),
        ("generate", "endgenerate"),
        ("begin", "end"),
    ):
        left = len(re.findall(rf"\b{opening}\b", text))
        right = len(re.findall(rf"\b{closing}\b", text))
        if left != right:
            raise SystemExit(
                f"ERROR: {path.relative_to(root)} {opening}/{closing}={left}/{right}"
            )

engine = (root / "rtl/pfdw_pipe49_booth_engine_v20_w5.sv").read_text()
chip = (root / "rtl/chip_pfdw_fc_v20_pow2.sv").read_text()
standalone_tb = (root / "tb/top_tb_v20_1000.sv").read_text()
assert "input  logic signed [4:0]  conv_kernel" in engine
assert "input  logic signed [4:0]  fc_b" in engine
assert "lane_bw = 5" in engine and "lane_bw = 9" in engine
assert "lane_pw=17" in engine and "lane_pw=22" in engine
assert "quant_floor5" in chip
assert "quant_trunc5" in chip
assert "quant_even5" in chip
assert "<<< 3" in chip
assert not re.search(r"[A-Za-z]:[/\\]", engine + chip)
assert "far_group_open" not in standalone_tb
assert "FAR activation fan-out order violation" not in standalone_tb
for path in sorted(root.glob("tb/*.sv")):
    assert "V19 FAR" not in path.read_text(), path
print(f"HDL structural checks: PASS ({len(hdl)} files)")
PY

test -s "${repo_root}/data/input_1000.txt"
echo "Python/shell/generated-source checks: PASS"
echo "NOTE: Vivado RTL and ORFS gates still require their target environments."
