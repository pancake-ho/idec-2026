#!/usr/bin/env bash
set -euo pipefail

test_name="${1:-ab}"
package_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repo_root="$(git -C "${package_root}" rev-parse --show-toplevel)"
data_root="${PFDW_DATA_DIR:-${repo_root}/data}"
work_dir="${package_root}/build/vivado/${test_name}"

python3 "${package_root}/scripts/generate_rtl.py"
test -s "${data_root}/input_1000.txt"
mkdir -p "${work_dir}"
if [[ -e "${work_dir}/data" && ! -L "${work_dir}/data" ]]; then
  echo "ERROR: ${work_dir}/data exists and is not a symlink." >&2
  exit 2
fi
ln -sfn "${data_root}" "${work_dir}/data"

v20_sources=(
  "${package_root}/rtl/pfdw_pipe49_booth_engine_v20_w5.sv"
  "${package_root}/rtl/chip_pfdw_fc_v20_pow2.sv"
)
v18_sources=(
  "${repo_root}/far_pfdw_v19/reference_v18a/pfdw_pipe49_booth_engine_v18a.sv"
  "${repo_root}/far_pfdw_v19/reference_v18a/chip_pfdw_fc_v18a.sv"
)
baseline_sources=(
  "${repo_root}/verilog/conv1.v"
  "${repo_root}/verilog/conv2.v"
  "${repo_root}/verilog/maxpool_relu.v"
  "${repo_root}/verilog/fc.v"
  "${repo_root}/verilog/comparator.v"
  "${repo_root}/verilog/chip.v"
)

case "${test_name}" in
  v20)
    top=top_tb_v20_1000
    sources=("${v20_sources[@]}" "${package_root}/tb/top_tb_v20_1000.sv")
    ;;
  ab)
    top=top_tb_v20_vs_v18a_1000
    sources=("${v18_sources[@]}" "${v20_sources[@]}" "${package_root}/tb/top_tb_v20_vs_v18a_1000.sv")
    ;;
  cycle_ab)
    top=top_tb_cycle_v20_vs_v18a
    sources=("${v18_sources[@]}" "${v20_sources[@]}" "${package_root}/tb/top_tb_cycle_v20_vs_v18a.sv")
    ;;
  repo_baseline)
    top=top_tb_v20_vs_baseline_1000
    sources=("${baseline_sources[@]}" "${v20_sources[@]}" "${package_root}/tb/top_tb_v20_vs_baseline_1000.sv")
    ;;
  cycle_repo_baseline)
    top=top_tb_cycle_v20_vs_baseline
    sources=("${baseline_sources[@]}" "${v20_sources[@]}" "${package_root}/tb/top_tb_cycle_v20_vs_baseline.sv")
    ;;
  *)
    echo "usage: $0 {v20|ab|cycle_ab|repo_baseline|cycle_repo_baseline}" >&2
    exit 2
    ;;
esac

for tool in xvlog xelab xsim; do
  command -v "${tool}" >/dev/null || {
    echo "ERROR: ${tool} is not in PATH." >&2
    exit 127
  }
done

cd "${work_dir}"
rm -f xvlog_console.log xelab_console.log xsim_console.log xsim.log
xvlog -sv "${sources[@]}" 2>&1 | tee xvlog_console.log
xelab "${top}" -s "${top}_snapshot" --debug typical --timescale 1ps/1ps \
  2>&1 | tee xelab_console.log
xsim "${top}_snapshot" -runall 2>&1 | tee xsim_console.log
cp xsim_console.log xsim.log
