#!/usr/bin/env bash
set -euo pipefail

package_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repo_root="$(git -C "${package_root}" rev-parse --show-toplevel)"
bundle_root="${package_root}/build/orfs/gate_bundle"
netlist="${1:-${bundle_root}/chip_v20_pow2_final.v}"
stdcell_dir="${2:-${bundle_root}/stdcell}"
data_root="${PFDW_DATA_DIR:-${repo_root}/data}"
work_dir="${package_root}/build/vivado/gate_v20"

if [[ ! -s "${netlist}" ]]; then
  echo "ERROR: post-route netlist not found: ${netlist}" >&2
  echo "Run the Seraph full flow first or pass <netlist.v> explicitly." >&2
  exit 2
fi
if [[ ! -d "${stdcell_dir}" ]]; then
  echo "ERROR: ASAP7 Verilog model directory not found: ${stdcell_dir}" >&2
  exit 2
fi
test -s "${data_root}/input_1000.txt"

mapfile -d '' stdcell_sources < <(
  # dff.v is ORFS's Verilator workaround and duplicates the official DFF
  # modules already present in asap7sc7p5t_SEQ_RVT_TT_220101.v.  Vivado
  # supports the official UDP models, so compile those exactly once.
  find "${stdcell_dir}" -type f \( -name '*.v' -o -name '*.sv' \) \
    ! -name 'dff.v' -print0 | sort -z
)
if (( ${#stdcell_sources[@]} == 0 )); then
  echo "ERROR: no Verilog cell models found under ${stdcell_dir}" >&2
  exit 2
fi

for tool in xvlog xelab xsim; do
  command -v "${tool}" >/dev/null || {
    echo "ERROR: ${tool} is not in PATH. Source Vivado 2024.1 settings64.sh." >&2
    exit 127
  }
done

mkdir -p "${work_dir}"
if [[ -e "${work_dir}/data" && ! -L "${work_dir}/data" ]]; then
  echo "ERROR: ${work_dir}/data exists and is not a symlink." >&2
  exit 2
fi
ln -sfn "${data_root}" "${work_dir}/data"

top=top_tb_gate_v20_1000
sources=(
  "${stdcell_sources[@]}"
  "$(realpath "${netlist}")"
  "${package_root}/tb/top_tb_gate_v20_1000.sv"
)

cd "${work_dir}"
rm -f xvlog_console.log xelab_console.log xsim_console.log xsim.log
xvlog -sv "${sources[@]}" 2>&1 | tee xvlog_console.log
xelab "${top}" -s "${top}_snapshot" --debug typical --timescale 1ps/1ps \
  2>&1 | tee xelab_console.log
xsim "${top}_snapshot" -runall 2>&1 | tee xsim_console.log
cp xsim_console.log xsim.log

grep -E 'Correct|Fail|Accuracy|RESULT|TIMEOUT|FATAL|ERROR' xsim.log || true
