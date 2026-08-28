#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "usage: $0 <post_synth_netlist.v> <asap7_verilog_model.v> [glbl.v]" >&2
  exit 2
fi

netlist="$(realpath "$1")"
stdcell="$(realpath "$2")"
glbl="${3:-}"
package_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repo_root="$(git -C "$package_root" rev-parse --show-toplevel 2>/dev/null || true)"

if [[ -z "$repo_root" ]]; then
  echo "ERROR: far_pfdw_v19 must be placed inside the idec-2026 Git repository." >&2
  exit 2
fi

data_root="${FAR_DATA_DIR:-$repo_root/data}"
work_dir="$package_root/build/vivado/gate"
mkdir -p "$work_dir"

if [[ -e "$work_dir/data" && ! -L "$work_dir/data" ]]; then
  echo "ERROR: $work_dir/data exists and is not a symbolic link." >&2
  exit 2
fi
ln -sfn "$data_root" "$work_dir/data"
cd "$work_dir"

sources=("$stdcell" "$netlist" "$package_root/tb/top_tb_gate_far_1000.sv")
if [[ -n "$glbl" ]]; then
  sources+=("$(realpath "$glbl")")
fi

for tool_name in xvlog xelab xsim; do
  if ! command -v "$tool_name" >/dev/null 2>&1; then
    echo "ERROR: $tool_name is not in PATH. Source Vivado 2024.1 settings64.sh." >&2
    exit 127
  fi
done

xvlog -sv "${sources[@]}" 2>&1 | tee xvlog.log
xelab top_tb_gate_far_1000 -s gate_far_snapshot --debug typical 2>&1 | tee xelab.log
xsim gate_far_snapshot -runall 2>&1 | tee xsim.log
