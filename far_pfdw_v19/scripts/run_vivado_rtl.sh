#!/usr/bin/env bash
set -euo pipefail

test_name="${1:-ab}"
package_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repo_root="$(git -C "$package_root" rev-parse --show-toplevel 2>/dev/null || true)"

if [[ -z "$repo_root" ]]; then
  echo "ERROR: far_pfdw_v19 must be placed inside the idec-2026 Git repository." >&2
  exit 2
fi

data_root="${FAR_DATA_DIR:-$repo_root/data}"
work_dir="$package_root/build/vivado/$test_name"

if [[ ! -f "$data_root/input_1000.txt" ]]; then
  echo "ERROR: dataset not found: $data_root/input_1000.txt" >&2
  exit 2
fi

mkdir -p "$work_dir"
if [[ -e "$work_dir/data" && ! -L "$work_dir/data" ]]; then
  echo "ERROR: $work_dir/data exists and is not a symbolic link." >&2
  exit 2
fi
ln -sfn "$data_root" "$work_dir/data"
cd "$work_dir"

far_sources=(
  "$package_root/rtl/pfdw_pipe49_booth_engine_v19_far.sv"
  "$package_root/rtl/chip_pfdw_fc_v19_far.sv"
)

v18a_sources=(
  "$package_root/reference_v18a/pfdw_pipe49_booth_engine_v18a.sv"
  "$package_root/reference_v18a/chip_pfdw_fc_v18a.sv"
)

repo_baseline_sources=(
  "$repo_root/verilog/conv1.v"
  "$repo_root/verilog/conv2.v"
  "$repo_root/verilog/maxpool_relu.v"
  "$repo_root/verilog/fc.v"
  "$repo_root/verilog/comparator.v"
  "$repo_root/verilog/chip.v"
)

case "$test_name" in
  far)
    top=top_tb_far_1000
    sources=("${far_sources[@]}" "$package_root/tb/top_tb_far_1000.sv")
    ;;
  ab)
    top=top_tb_far_vs_v18a_1000
    sources=("${v18a_sources[@]}" "${far_sources[@]}" \
      "$package_root/tb/top_tb_far_vs_v18a_1000.sv")
    ;;
  cycle_ab)
    top=top_tb_cycle_far_vs_v18a
    sources=("${v18a_sources[@]}" "${far_sources[@]}" \
      "$package_root/tb/top_tb_cycle_far_vs_v18a.sv")
    ;;
  repo_baseline|baseline)
    top=top_tb_far_vs_baseline_1000
    sources=("${repo_baseline_sources[@]}" "${far_sources[@]}" \
      "$package_root/tb/top_tb_far_vs_baseline_1000.sv")
    ;;
  cycle_repo_baseline|cycle_baseline)
    top=top_tb_cycle_far_vs_baseline
    sources=("${repo_baseline_sources[@]}" "${far_sources[@]}" \
      "$package_root/tb/top_tb_cycle_far_vs_baseline.sv")
    ;;
  *)
    echo "usage: $0 {far|ab|cycle_ab|repo_baseline|cycle_repo_baseline}" >&2
    exit 2
    ;;
esac

for source_file in "${sources[@]}"; do
  if [[ ! -f "$source_file" ]]; then
    echo "ERROR: source not found: $source_file" >&2
    exit 2
  fi
done

for tool_name in xvlog xelab xsim; do
  if ! command -v "$tool_name" >/dev/null 2>&1; then
    echo "ERROR: $tool_name is not in PATH. Source Vivado 2024.1 settings64.sh." >&2
    exit 127
  fi
done

printf 'Test       : %s\n' "$test_name"
printf 'Top        : %s\n' "$top"
printf 'Repository : %s\n' "$repo_root"
printf 'Data       : %s\n' "$data_root"

xvlog -sv "${sources[@]}" 2>&1 | tee xvlog.log
xelab "$top" -s "${top}_snapshot" --debug typical 2>&1 | tee xelab.log
xsim "${top}_snapshot" -runall 2>&1 | tee xsim.log
