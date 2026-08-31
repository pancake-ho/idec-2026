#!/usr/bin/env bash
#SBATCH --job-name=orfs-ppa-ab
#SBATCH --partition=batch_eebme_ugrad
#SBATCH --account=ugrad_eebme
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-task=16
#SBATCH --mem-per-gpu=29696M
#SBATCH --time=08:00:00
#SBATCH --output=/data/surt321/repos/idec/logs/orfs-ppa-ab-%A.out
#SBATCH --error=/data/surt321/repos/idec/logs/orfs-ppa-ab-%A.err

set -euo pipefail

readonly REPO_ROOT="/data/surt321/repos/idec"
readonly PACKAGE_REL="far_pfdw_v19"
readonly LOCAL_ROOT="/local_datasets/${USER}/orfs_ppa_${SLURM_JOB_ID}"
readonly LOCAL_REPO="${LOCAL_ROOT}/idec"
readonly ORFS_ROOT="${LOCAL_ROOT}/OpenROAD-flow-scripts"

readonly ORFS_COMMIT="a5ff7ef7dac4338e6e5fad7710b85fc6c8f3503c"
readonly SIF_NAS="/data/surt321/containers/orfs/openroad_orfs_26Q3-54-ga5ff7ef7d_8742089692b5140d.sif"
readonly SIF_SHA256="8742089692b5140d4289c4e4fe07fa68baa8df5c42f80d797b94479be51a1a72"
readonly TOOLS_NAS="/data/surt321/containers/orfs/orfs_native_a5ff7ef7d_x86-64-v3.tar.gz"
readonly TOOLS_SHA256="399ce2747f6aca4af0e46ca40bd9d5a233314e599b84262ab4bbdcda3edd4e85"

readonly LOCAL_SIF="${LOCAL_ROOT}/orfs.sif"
readonly LOCAL_TOOLS="${LOCAL_ROOT}/orfs_native.tar.gz"

sync_artifacts() {
  local src="${LOCAL_REPO}/${PACKAGE_REL}"
  local dst="${REPO_ROOT}/${PACKAGE_REL}"
  local rel

  for rel in build/orfs logs reports results; do
    if [[ -d "${src}/${rel}" ]]; then
      mkdir -p "${dst}/${rel}"
      rsync -a "${src}/${rel}/" "${dst}/${rel}/"
    fi
  done
}

on_exit() {
  local rc=$?
  trap - EXIT
  set +e
  sync_artifacts
  echo
  echo "JOB_EXIT_CODE=${rc}"
  echo "LOCAL_ROOT=${LOCAL_ROOT}"
  exit "${rc}"
}
trap on_exit EXIT

echo "=================================================="
echo "FAR-PFDW V18A vs V19 full ORFS PPA A/B"
echo "=================================================="
echo "JOB_ID       : ${SLURM_JOB_ID}"
echo "NODE         : ${SLURMD_NODENAME:-unknown}"
echo "CPUS         : ${SLURM_CPUS_PER_TASK:-unknown}"
echo "REPO_ROOT    : ${REPO_ROOT}"
echo "LOCAL_ROOT   : ${LOCAL_ROOT}"
echo "ORFS_COMMIT  : ${ORFS_COMMIT}"

test -d "${REPO_ROOT}/${PACKAGE_REL}"
test -r "${SIF_NAS}"
test -r "${TOOLS_NAS}"

mkdir -p "${LOCAL_ROOT}" "${LOCAL_REPO}" "${LOCAL_ROOT}/tmp"

echo
echo "[Copy pinned runtime and native tools to local disk]"
cp -f "${SIF_NAS}" "${LOCAL_SIF}"
cp -f "${TOOLS_NAS}" "${LOCAL_TOOLS}"
printf '%s  %s\n' "${SIF_SHA256}" "${LOCAL_SIF}" | sha256sum -c -
printf '%s  %s\n' "${TOOLS_SHA256}" "${LOCAL_TOOLS}" | sha256sum -c -

echo
echo "[Clone pinned ORFS source without build submodules]"
git clone --no-recurse-submodules \
  https://github.com/The-OpenROAD-Project/OpenROAD-flow-scripts.git \
  "${ORFS_ROOT}"
git -C "${ORFS_ROOT}" checkout --detach "${ORFS_COMMIT}"
test "$(git -C "${ORFS_ROOT}" rev-parse HEAD)" = "${ORFS_COMMIT}"

echo
echo "[Install reusable native tool archive]"
readonly TOOLS_STAGE="${LOCAL_ROOT}/native_tools_stage"
mkdir -p "${TOOLS_STAGE}" "${ORFS_ROOT}/tools/install"
tar -xzf "${LOCAL_TOOLS}" -C "${TOOLS_STAGE}"

if [[ -d "${TOOLS_STAGE}/tools/install" ]]; then
  readonly TOOLS_INSTALL_SOURCE="${TOOLS_STAGE}/tools/install"
elif [[ -d "${TOOLS_STAGE}/install" ]]; then
  readonly TOOLS_INSTALL_SOURCE="${TOOLS_STAGE}/install"
else
  echo "ERROR: unsupported native-tool archive layout." >&2
  echo "Top-level archive entries:" >&2
  find "${TOOLS_STAGE}" -maxdepth 3 -mindepth 1 -printf '%P\n' \
    | sed -n '1,80p' >&2
  exit 3
fi

echo "TOOLS_INSTALL_SOURCE=${TOOLS_INSTALL_SOURCE}"
rsync -a "${TOOLS_INSTALL_SOURCE}/" "${ORFS_ROOT}/tools/install/"
mkdir -p "${ORFS_ROOT}/dependencies"

for required_path in \
  "${ORFS_ROOT}/tools/install/OpenROAD/bin/openroad" \
  "${ORFS_ROOT}/tools/install/yosys/bin/yosys" \
  "${ORFS_ROOT}/tools/install/yosys/share/yosys/plugins/slang.so"; do
  if [[ ! -e "${required_path}" ]]; then
    echo "ERROR: native-tool file is missing: ${required_path}" >&2
    exit 4
  fi
done

test -x "${ORFS_ROOT}/tools/install/OpenROAD/bin/openroad"
test -x "${ORFS_ROOT}/tools/install/yosys/bin/yosys"

echo
echo "[Copy design repository to node-local workspace]"
rsync -a \
  --exclude='/.git/' \
  --exclude='/logs/' \
  --exclude='/far_pfdw_v19/build/orfs/' \
  --exclude='/far_pfdw_v19/logs/' \
  --exclude='/far_pfdw_v19/reports/' \
  --exclude='/far_pfdw_v19/results/' \
  --exclude='/far_pfdw_v19/objects/' \
  "${REPO_ROOT}/" "${LOCAL_REPO}/"

echo
echo "[Validate relocated native tools and run full A/B flow]"
singularity exec --cleanenv \
  --bind /data:/data \
  --bind /local_datasets:/local_datasets \
  "${LOCAL_SIF}" /usr/bin/bash -s -- \
  "${ORFS_ROOT}" \
  "${LOCAL_REPO}" \
  "${LOCAL_ROOT}/tmp" \
  "${SLURM_CPUS_PER_TASK:-16}" <<'CONTAINER_EOF'
set -euo pipefail

readonly ORFS_ROOT="$1"
readonly LOCAL_REPO="$2"
readonly JOB_TMPDIR="$3"
readonly ORFS_NUM_CORES="$4"

export TMPDIR="${JOB_TMPDIR}"

echo "[Container entry]"
echo "ORFS_ROOT=${ORFS_ROOT}"
echo "LOCAL_REPO=${LOCAL_REPO}"
echo "TMPDIR=${TMPDIR}"
echo "ORFS_NUM_CORES=${ORFS_NUM_CORES}"

test -d "${ORFS_ROOT}/flow"
test -f "${ORFS_ROOT}/env.sh"
test -d "${LOCAL_REPO}/far_pfdw_v19"

mkdir -p "${ORFS_ROOT}/dependencies" "${TMPDIR}"

# env.sh adds this relocated archive's OpenROAD, Yosys, and formal tools
# to PATH.  dev_env.sh only adds dependencies/bin and is not sufficient here.
source "${ORFS_ROOT}/env.sh"

export ORFS_FLOW_DIR="${ORFS_ROOT}/flow"
export NUM_CORES="${ORFS_NUM_CORES}"
export OMP_NUM_THREADS="${ORFS_NUM_CORES}"
export LD_LIBRARY_PATH="${ORFS_ROOT}/tools/install/OpenROAD/lib:${ORFS_ROOT}/tools/install/yosys/lib:${ORFS_ROOT}/tools/install/kepler-formal/lib:${LD_LIBRARY_PATH:-}"

expected_openroad="${ORFS_ROOT}/tools/install/OpenROAD/bin/openroad"
expected_yosys="${ORFS_ROOT}/tools/install/yosys/bin/yosys"
actual_openroad="$(command -v openroad || true)"
actual_yosys="$(command -v yosys || true)"

if [[ -z "${actual_openroad}" || -z "${actual_yosys}" ]]; then
  echo "ERROR: relocated OpenROAD/Yosys is not visible in PATH." >&2
  echo "PATH=${PATH}" >&2
  exit 5
fi

actual_openroad="$(readlink -f "${actual_openroad}")"
actual_yosys="$(readlink -f "${actual_yosys}")"

echo "EXPECTED_OPENROAD=${expected_openroad}"
echo "ACTUAL_OPENROAD=${actual_openroad}"
echo "EXPECTED_YOSYS=${expected_yosys}"
echo "ACTUAL_YOSYS=${actual_yosys}"
test "${actual_openroad}" = "${expected_openroad}"
test "${actual_yosys}" = "${expected_yosys}"

openroad -version
yosys -V
yosys -m slang -p 'slang_version'
command -v eqy
command -v sby

cd "${LOCAL_REPO}"
bash far_pfdw_v19/scripts/check_source.sh
bash far_pfdw_v19/scripts/run_orfs_ab.sh
bash far_pfdw_v19/scripts/ppa_summary.sh

test -s far_pfdw_v19/build/orfs/ppa_summary.csv
test -s far_pfdw_v19/build/orfs/ppa_summary.md

echo
cat far_pfdw_v19/build/orfs/ppa_summary.md
echo "PPA_AB_RESULT=PASS"
CONTAINER_EOF

echo
echo "RESULT=PASS"