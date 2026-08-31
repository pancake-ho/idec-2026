#!/usr/bin/env bash
#SBATCH --job-name=pfdw-v20-ppa
#SBATCH --partition=batch_eebme_ugrad
#SBATCH --account=ugrad_eebme
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-task=16
#SBATCH --mem-per-gpu=29696M
#SBATCH --time=08:00:00
#SBATCH --output=logs/pfdw-v20-ppa-%A.out
#SBATCH --error=logs/pfdw-v20-ppa-%A.err
set -euo pipefail

readonly REPO_ROOT="${REPO_ROOT:-/data/${USER}/repos/idec}"
readonly PACKAGE_REL="far_pfdw_v20"
readonly LOCAL_ROOT="/local_datasets/${USER}/pfdw_v20_${SLURM_JOB_ID}"
readonly LOCAL_REPO="${LOCAL_ROOT}/idec"
readonly ORFS_ROOT="${LOCAL_ROOT}/OpenROAD-flow-scripts"
readonly ORFS_COMMIT="a5ff7ef7dac4338e6e5fad7710b85fc6c8f3503c"
readonly V20_SIF_NAS="${SIF_NAS:-/data/${USER}/containers/orfs/openroad_orfs_26Q3-54-ga5ff7ef7d_8742089692b5140d.sif}"
readonly V20_TOOLS_NAS="${TOOLS_NAS:-/data/${USER}/containers/orfs/orfs_native_a5ff7ef7d_x86-64-v3.tar.gz}"
readonly SIF_SHA256="8742089692b5140d4289c4e4fe07fa68baa8df5c42f80d797b94479be51a1a72"
readonly TOOLS_SHA256="399ce2747f6aca4af0e46ca40bd9d5a233314e599b84262ab4bbdcda3edd4e85"
readonly LOCAL_SIF="${LOCAL_ROOT}/orfs.sif"
readonly LOCAL_TOOLS="${LOCAL_ROOT}/native_tools.tar.gz"

require_executable() {
  local path="$1"
  if [[ ! -x "${path}" ]]; then
    echo "ERROR: required executable is missing or not executable: ${path}" >&2
    ls -l "${path}" 2>/dev/null || true
    exit 4
  fi
  echo "HOST_EXECUTABLE_OK=${path}"
}

require_nonempty_file() {
  local path="$1"
  if [[ ! -s "${path}" ]]; then
    echo "ERROR: required file is missing or empty: ${path}" >&2
    ls -l "${path}" 2>/dev/null || true
    exit 4
  fi
  echo "HOST_FILE_OK=${path}"
}

sync_artifacts() {
  local source="${LOCAL_REPO}/${PACKAGE_REL}"
  local destination="${REPO_ROOT}/${PACKAGE_REL}"
  local relative
  for relative in build logs reports results; do
    if [[ -d "${source}/${relative}" ]]; then
      mkdir -p "${destination}/${relative}"
      rsync -a "${source}/${relative}/" "${destination}/${relative}/"
    fi
  done
}

on_exit() {
  local rc=$?
  trap - EXIT
  set +e
  sync_artifacts
  echo "JOB_EXIT_CODE=${rc}"
  echo "LOCAL_ROOT=${LOCAL_ROOT}"
  exit "${rc}"
}
trap on_exit EXIT

echo "JOB_ID=${SLURM_JOB_ID}"
echo "NODE=${SLURMD_NODENAME:-unknown}"
echo "CPUS=${SLURM_CPUS_PER_TASK:-unknown}"
echo "REPO_ROOT=${REPO_ROOT}"
echo "LOCAL_ROOT=${LOCAL_ROOT}"
echo "ORFS_COMMIT=${ORFS_COMMIT}"

test -d "${REPO_ROOT}/${PACKAGE_REL}"
test -r "${V20_SIF_NAS}"
test -r "${V20_TOOLS_NAS}"
mkdir -p "${LOCAL_ROOT}" "${LOCAL_ROOT}/tmp" "${LOCAL_REPO}"
cp -f "${V20_SIF_NAS}" "${LOCAL_SIF}"
cp -f "${V20_TOOLS_NAS}" "${LOCAL_TOOLS}"
printf '%s  %s\n' "${SIF_SHA256}" "${LOCAL_SIF}" | sha256sum -c -
printf '%s  %s\n' "${TOOLS_SHA256}" "${LOCAL_TOOLS}" | sha256sum -c -

git clone --no-recurse-submodules \
  https://github.com/The-OpenROAD-Project/OpenROAD-flow-scripts.git \
  "${ORFS_ROOT}"
git -C "${ORFS_ROOT}" checkout --detach "${ORFS_COMMIT}"
actual_orfs_commit="$(git -C "${ORFS_ROOT}" rev-parse HEAD)"
echo "ACTUAL_ORFS_COMMIT=${actual_orfs_commit}"
if [[ "${actual_orfs_commit}" != "${ORFS_COMMIT}" ]]; then
  echo "ERROR: ORFS commit mismatch." >&2
  exit 4
fi

readonly TOOLS_STAGE="${LOCAL_ROOT}/native_tools"
mkdir -p "${TOOLS_STAGE}" "${ORFS_ROOT}/tools/install"
tar -xzf "${LOCAL_TOOLS}" -C "${TOOLS_STAGE}"
if [[ -d "${TOOLS_STAGE}/install" ]]; then
  tools_source="${TOOLS_STAGE}/install"
elif [[ -d "${TOOLS_STAGE}/tools/install" ]]; then
  tools_source="${TOOLS_STAGE}/tools/install"
else
  echo "ERROR: unsupported native tool archive layout." >&2
  exit 3
fi
rsync -a "${tools_source}/" "${ORFS_ROOT}/tools/install/"
mkdir -p "${ORFS_ROOT}/dependencies"
require_executable "${ORFS_ROOT}/tools/install/OpenROAD/bin/openroad"
require_executable "${ORFS_ROOT}/tools/install/yosys/bin/yosys"
require_nonempty_file "${ORFS_ROOT}/tools/install/yosys/share/yosys/plugins/slang.so"
echo "HOST_NATIVE_TOOLS_STAGE=PASS"

rsync -a \
  --exclude='/.git/' \
  --exclude='/logs/' \
  --exclude='/far_pfdw_v20/build/orfs/' \
  --exclude='/far_pfdw_v20/logs/' \
  --exclude='/far_pfdw_v20/reports/' \
  --exclude='/far_pfdw_v20/results/' \
  --exclude='/far_pfdw_v20/objects/' \
  "${REPO_ROOT}/" "${LOCAL_REPO}/"
require_nonempty_file "${LOCAL_REPO}/${PACKAGE_REL}/scripts/check_source.sh"
require_nonempty_file "${LOCAL_REPO}/${PACKAGE_REL}/scripts/run_orfs_ab.sh"
echo "LOCAL_REPO_STAGE=PASS"

export SINGULARITYENV_ORFS_ROOT="${ORFS_ROOT}"
export SINGULARITYENV_LOCAL_REPO="${LOCAL_REPO}"
export SINGULARITYENV_TMPDIR="${LOCAL_ROOT}/tmp"
export SINGULARITYENV_ORFS_NUM_CORES="${SLURM_CPUS_PER_TASK:-16}"

singularity exec --cleanenv \
  --bind /data:/data \
  --bind /local_datasets:/local_datasets \
  "${LOCAL_SIF}" /usr/bin/bash -s <<'CONTAINER_EOF'
set -euo pipefail
echo "CONTAINER_STAGE=ENTERED"
mkdir -p "${ORFS_ROOT}/dependencies" "${TMPDIR}"
if ! source "${ORFS_ROOT}/dev_env.sh"; then
  echo "ERROR: ORFS dev_env.sh failed." >&2
  exit 5
fi
export ORFS_FLOW_DIR="${ORFS_ROOT}/flow"
export ORFS_NUM_CORES
export ORFS_AB_PARALLEL=1
export OMP_NUM_THREADS=8
export PATH="${ORFS_ROOT}/tools/install/OpenROAD/bin:${ORFS_ROOT}/tools/install/yosys/bin:${PATH}"
export LD_LIBRARY_PATH="${ORFS_ROOT}/tools/install/OpenROAD/lib:${ORFS_ROOT}/tools/install/yosys/lib:${LD_LIBRARY_PATH:-}"
hash -r

expected_openroad="${ORFS_ROOT}/tools/install/OpenROAD/bin/openroad"
expected_yosys="${ORFS_ROOT}/tools/install/yosys/bin/yosys"
slang_plugin="${ORFS_ROOT}/tools/install/yosys/share/yosys/plugins/slang.so"
actual_openroad="$(readlink -f "$(command -v openroad || true)")"
actual_yosys="$(readlink -f "$(command -v yosys || true)")"
echo "CONTAINER_PATH=${PATH}"
echo "ACTUAL_OPENROAD=${actual_openroad}"
echo "EXPECTED_OPENROAD=${expected_openroad}"
echo "ACTUAL_YOSYS=${actual_yosys}"
echo "EXPECTED_YOSYS=${expected_yosys}"
ls -l "${expected_openroad}" "${expected_yosys}" "${slang_plugin}"
if [[ "${actual_openroad}" != "${expected_openroad}" ]]; then
  echo "ERROR: OpenROAD path mismatch." >&2
  exit 5
fi
if [[ "${actual_yosys}" != "${expected_yosys}" ]]; then
  echo "ERROR: Yosys path mismatch." >&2
  exit 5
fi
"${expected_openroad}" -version
"${expected_yosys}" -V
"${expected_yosys}" -m "${slang_plugin}" -p 'slang_version'
"${expected_yosys}" -m slang -p 'slang_version'
echo "CONTAINER_NATIVE_TOOLS_STAGE=PASS"

cd "${LOCAL_REPO}"
bash far_pfdw_v20/scripts/check_source.sh
python3 far_pfdw_v20/scripts/search_pow2_mp.py
bash far_pfdw_v20/scripts/run_orfs_ab.sh
test -s far_pfdw_v20/build/orfs/ppa_summary.csv
test -s far_pfdw_v20/build/orfs/ppa_summary.md
cat far_pfdw_v20/build/orfs/ppa_summary.md
echo "PFDW_V20_RESULT=PASS"
CONTAINER_EOF

echo "RESULT=PASS"
