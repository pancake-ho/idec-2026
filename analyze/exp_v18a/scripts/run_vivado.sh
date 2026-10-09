#!/usr/bin/env bash
set -euo pipefail
# Usage: bash run_vivado.sh engine|top [repository root] [analysis output] [image count]
# First activate the existing Vivado 2024.1 environment on your machine.
mode="${1:-}"
if [[ "$mode" != engine && "$mode" != top ]]; then
    echo 'Usage: run_vivado.sh engine|top [repo] [out] [images]' >&2
    exit 2
fi
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
package_dir="$(cd -- "$script_dir/.." && pwd)"
repo_dir="${2:-$(cd -- "$package_dir/../.." && pwd)}"
repo_dir="$(cd -- "$repo_dir" && pwd)"
out_dir="${3:-$repo_dir/analyze/exp_v18a/outputs}"
mkdir -p -- "$out_dir"
out_dir="$(cd -- "$out_dir" && pwd)"
image_count="${4:-1000}"
if [[ ! "$image_count" =~ ^[0-9]+$ ]] || ((image_count < 1 || image_count > 1000)); then
    echo 'images must be an integer in 1..1000' >&2
    exit 2
fi
for command_name in xvlog xelab xsim; do
    command -v "$command_name" >/dev/null || {
        echo "Missing $command_name: activate your Vivado 2024.1 environment first." >&2
        exit 2
    }
done
python_cmd="${PYTHON:-python3}"
build_dir="$out_dir/vivado_$mode"
mkdir -p -- "$build_dir"
cd -- "$build_dir"
if [[ "$mode" == engine ]]; then
    if [[ ! -f "$out_dir/engine_cases.txt" ]]; then
        "$python_cmd" "$package_dir/run.py" engine-vectors --repo-root "$repo_dir" --out "$out_dir"
    fi
    xvlog -sv -work xil_defaultlib \
        "$repo_dir/verilog/pfdw_pipe49_booth_engine_v18a.sv" \
        "$package_dir/rtl/tb_engine_v18a_analysis.sv"
    xelab xil_defaultlib.tb_engine_v18a_analysis -s engine_analysis -debug typical
    xsim engine_analysis -runall -testplusarg "VECTORS=$out_dir/engine_cases.txt" | tee engine_console.log
    grep -q '^ENGINE_CONTRACT_PASS ' engine_console.log || {
        echo 'Engine simulation did not emit its success marker.' >&2
        exit 1
    }
else
    [[ -f "$out_dir/expected_trace.npz" ]] || {
        echo 'Run run.py validate or all with this --out before top simulation.' >&2
        exit 2
    }
    xvlog -sv -work xil_defaultlib \
        "$repo_dir/verilog/pfdw_pipe49_booth_engine_v18a.sv" \
        "$repo_dir/verilog/chip_pfdw_fc_v18a.sv" \
        "$package_dir/rtl/tb_chip_v18a_trace.sv"
    xelab xil_defaultlib.tb_chip_v18a_trace -s chip_analysis -debug typical
    xsim chip_analysis -runall \
        -testplusarg "DATA_DIR=$repo_dir/data" \
        -testplusarg "TRACE_CSV=$out_dir/rtl_trace.csv" \
        -testplusarg "IMAGES=$image_count"
    "$python_cmd" "$package_dir/run.py" compare-rtl \
        --repo-root "$repo_dir" --out "$out_dir" \
        --rtl-csv "$out_dir/rtl_trace.csv" --images "$image_count"
fi
