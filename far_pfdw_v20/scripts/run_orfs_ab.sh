#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${ORFS_FLOW_DIR:-}" || ! -f "${ORFS_FLOW_DIR}/Makefile" ]]; then
  echo "ERROR: ORFS_FLOW_DIR must point to OpenROAD-flow-scripts/flow." >&2
  exit 2
fi

package_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
log_dir="${package_root}/build/orfs"
mkdir -p "${log_dir}"
python3 "${package_root}/scripts/generate_rtl.py"

orfs_commit="$(git -C "${ORFS_FLOW_DIR}" rev-parse HEAD 2>/dev/null || printf unknown)"
printf '%s\n' "${orfs_commit}" | tee "${log_dir}/orfs_commit.txt"

total_cores="${ORFS_NUM_CORES:-${SLURM_CPUS_PER_TASK:-16}}"
parallel="${ORFS_AB_PARALLEL:-1}"
if [[ "${parallel}" == "1" ]]; then
  cores_each=$((total_cores / 2))
  (( cores_each >= 1 )) || cores_each=1
else
  cores_each="${total_cores}"
fi

run_one() {
  local design="$1"
  local config="${package_root}/orfs/${design}/config.mk"
  local log="${log_dir}/${design}.log"
  echo "START ${design}: NUM_CORES=${cores_each}, log=${log}"
  (
    cd "${package_root}"
    export NUM_CORES="${cores_each}"
    make --file="${ORFS_FLOW_DIR}/Makefile" DESIGN_CONFIG="${config}"
    make --file="${ORFS_FLOW_DIR}/Makefile" DESIGN_CONFIG="${config}" metadata-generate
  ) >"${log}" 2>&1
  echo "DONE  ${design}"
}

if [[ "${parallel}" == "1" ]]; then
  run_one chip_v18a &
  pid_v18=$!
  run_one chip_v20_pow2 &
  pid_v20=$!
  rc=0
  wait "${pid_v18}" || rc=1
  wait "${pid_v20}" || rc=1
  if (( rc != 0 )); then
    echo "ERROR: at least one ORFS run failed." >&2
    tail -n 80 "${log_dir}/chip_v18a.log" || true
    tail -n 80 "${log_dir}/chip_v20_pow2.log" || true
    exit 1
  fi
else
  run_one chip_v18a
  run_one chip_v20_pow2
fi

# Export a self-contained zero-delay gate-simulation bundle before the
# node-local ORFS checkout disappears.  Vivado runs later on Windows.
gate_bundle="${log_dir}/gate_bundle"
netlist="${package_root}/results/asap7/chip_v20_pow2/base/6_final.v"
stdcell_source="${ORFS_FLOW_DIR}/platforms/asap7/verilog/stdcell"
test -s "${netlist}" || {
  echo "ERROR: final V20 netlist is missing: ${netlist}" >&2
  exit 1
}
test -d "${stdcell_source}" || {
  echo "ERROR: ASAP7 Verilog models are missing: ${stdcell_source}" >&2
  exit 1
}
rm -rf "${gate_bundle}"
mkdir -p "${gate_bundle}/stdcell"
cp -f "${netlist}" "${gate_bundle}/chip_v20_pow2_final.v"
rsync -a --include='*/' --include='*.v' --include='*.sv' --exclude='*' \
  "${stdcell_source}/" "${gate_bundle}/stdcell/"
test -s "${gate_bundle}/chip_v20_pow2_final.v"
test -n "$(find "${gate_bundle}/stdcell" -type f \( -name '*.v' -o -name '*.sv' \) -print -quit)"
(
  cd "${gate_bundle}"
  sha256sum chip_v20_pow2_final.v > SHA256SUMS
)
echo "GATE_BUNDLE=${gate_bundle}"

"${package_root}/scripts/ppa_summary.sh"
