#!/usr/bin/bash
#SBATCH -J orfs-native-check
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-gpu=16
#SBATCH --mem-per-gpu=29G
#SBATCH -p batch_eebme_ugrad
#SBATCH -t 0-08:00:00
#SBATCH -o logs/orfs-native-check-%A.out
#SBATCH -e logs/orfs-native-check-%A.err

set -Eeuo pipefail
umask 022

REPO_ROOT="/data/${USER}/repos/idec"

BASE_SIF="/data/${USER}/containers/orfs/openroad_orfs_26Q3-54-ga5ff7ef7d_8742089692b5140d.sif"
EXPECTED_SIF_SHA256="8742089692b5140d4289c4e4fe07fa68baa8df5c42f80d797b94479be51a1a72"

ORFS_REPOSITORY="https://github.com/The-OpenROAD-Project/OpenROAD-flow-scripts.git"
ORFS_COMMIT="a5ff7ef7d"
OPENROAD_COMMIT="6b9d7fb806"

LOCAL_ROOT="/local_datasets/${USER}/orfs_native_${SLURM_JOB_ID}"
LOCAL_SIF="${LOCAL_ROOT}/orfs_base.sif"
ORFS_NATIVE="${LOCAL_ROOT}/OpenROAD-flow-scripts"

BUILD_THREADS=8

PERSIST_DIR="/data/${USER}/containers/orfs"
PERSIST_ARCHIVE="${PERSIST_DIR}/orfs_native_a5ff7ef7d_x86-64-v3.tar.gz"
PERSIST_SHA="${PERSIST_ARCHIVE}.sha256"

on_exit()
{
    rc=$?
    trap - EXIT

    if [[ -f "${ORFS_NATIVE}/build_openroad.log" ]]; then
        cp \
          "${ORFS_NATIVE}/build_openroad.log" \
          "${REPO_ROOT}/logs/orfs-native-build-${SLURM_JOB_ID}.log" \
          || true
    fi

    echo
    echo "JOB_EXIT_CODE=${rc}"
    echo "LOCAL_ROOT=${LOCAL_ROOT}"

    exit "${rc}"
}

trap on_exit EXIT

echo "=================================================="
echo "ORFS portable native build and CTS validation"
echo "=================================================="
echo "JOB_ID        : ${SLURM_JOB_ID}"
echo "NODE          : $(hostname)"
echo "USER          : ${USER}"
echo "PARTITION     : ${SLURM_JOB_PARTITION}"
echo "CPUS          : ${SLURM_CPUS_ON_NODE:-unknown}"
echo "GPUS          : ${SLURM_GPUS_ON_NODE:-unknown}"
echo "MEM_PER_GPU   : ${SLURM_MEM_PER_GPU:-unknown}"
echo "REPO_ROOT     : ${REPO_ROOT}"
echo "LOCAL_ROOT    : ${LOCAL_ROOT}"
echo "ORFS_COMMIT   : ${ORFS_COMMIT}"
echo "OPENROAD_COMMIT: ${OPENROAD_COMMIT}"
echo

if [[ ! -r "${BASE_SIF}" ]]; then
    echo "ERROR: base SIF not found: ${BASE_SIF}" >&2
    exit 2
fi

if [[ ! -d "${REPO_ROOT}/far_pfdw_v19" ]]; then
    echo "ERROR: FAR-PFDW package not found." >&2
    exit 2
fi

if [[ -e "${LOCAL_ROOT}" ]]; then
    echo "ERROR: local job directory already exists: ${LOCAL_ROOT}" >&2
    exit 2
fi

mkdir -p "${LOCAL_ROOT}"
mkdir -p "${PERSIST_DIR}"

echo "[Host CPU]"

lscpu |
grep -E \
  'Architecture|Model name|CPU\(s\)|Thread|Core|Socket|Flags' \
  || true

if grep -qw avx512f /proc/cpuinfo; then
    echo "HOST_AVX512F=YES"
else
    echo "HOST_AVX512F=NO"
fi

echo
echo "[Memory]"
free -h

echo
echo "[Filesystem]"
df -h /data /local_datasets

echo
echo "[Copy one SIF file from NAS to local disk]"

cp --reflink=auto "${BASE_SIF}" "${LOCAL_SIF}"

ACTUAL_SIF_SHA256="$(
    sha256sum "${LOCAL_SIF}" |
    awk '{print $1}'
)"

echo "EXPECTED_SIF_SHA256=${EXPECTED_SIF_SHA256}"
echo "ACTUAL_SIF_SHA256=${ACTUAL_SIF_SHA256}"

if [[ "${ACTUAL_SIF_SHA256}" != "${EXPECTED_SIF_SHA256}" ]]; then
    echo "ERROR: copied SIF checksum mismatch." >&2
    exit 2
fi

echo
echo "[Clone complete ORFS source into local disk]"

git clone \
  "${ORFS_REPOSITORY}" \
  "${ORFS_NATIVE}"

git -C "${ORFS_NATIVE}" \
  checkout --detach "${ORFS_COMMIT}"

git -C "${ORFS_NATIVE}" \
  submodule sync --recursive

git -C "${ORFS_NATIVE}" \
  submodule update \
  --init \
  --recursive \
  --jobs "${BUILD_THREADS}"

ACTUAL_ORFS_COMMIT="$(
    git -C "${ORFS_NATIVE}" rev-parse HEAD
)"

ACTUAL_OPENROAD_COMMIT="$(
    git -C "${ORFS_NATIVE}/tools/OpenROAD" rev-parse HEAD
)"

echo "ACTUAL_ORFS_COMMIT=${ACTUAL_ORFS_COMMIT}"
echo "ACTUAL_OPENROAD_COMMIT=${ACTUAL_OPENROAD_COMMIT}"

case "${ACTUAL_ORFS_COMMIT}" in
    "${ORFS_COMMIT}"*)
        ;;
    *)
        echo "ERROR: ORFS commit mismatch." >&2
        exit 2
        ;;
esac

case "${ACTUAL_OPENROAD_COMMIT}" in
    "${OPENROAD_COMMIT}"*)
        ;;
    *)
        echo "ERROR: OpenROAD submodule commit mismatch." >&2
        exit 2
        ;;
esac

echo
echo "[Prepare local dependency prefix]"

# A clean ORFS Git checkout does not contain this generated directory.
# The SIF supplies actual build dependencies through
# /etc/openroad_deps_prefixes.txt.
mkdir -p "${ORFS_NATIVE}/dependencies"

echo
echo "[Required source files]"

test -d "${ORFS_NATIVE}/dependencies"
test -x "${ORFS_NATIVE}/build_openroad.sh"
test -x "${ORFS_NATIVE}/tools/OpenROAD/etc/Build.sh"
test -f "${ORFS_NATIVE}/dev_env.sh"

ls -ld \
  "${ORFS_NATIVE}/dependencies" \
  "${ORFS_NATIVE}/tools/OpenROAD"

ls -l \
  "${ORFS_NATIVE}/build_openroad.sh" \
  "${ORFS_NATIVE}/tools/OpenROAD/etc/Build.sh"

echo
echo "[Portable native build inside SIF environment]"

singularity exec \
  --bind /local_datasets:/local_datasets \
  "${LOCAL_SIF}" \
  env \
    ORFS_NATIVE="${ORFS_NATIVE}" \
    BUILD_THREADS="${BUILD_THREADS}" \
  bash -lc '
    set -Eeuo pipefail

    case "${ORFS_NATIVE}" in
        /local_datasets/*/orfs_native_*/OpenROAD-flow-scripts)
            ;;
        *)
            echo "ERROR: unsafe ORFS_NATIVE path: ${ORFS_NATIVE}" >&2
            exit 2
            ;;
    esac

    cd "${ORFS_NATIVE}"

    echo "ORFS source:"
    git rev-parse HEAD

    echo "OpenROAD source:"
    git -C tools/OpenROAD rev-parse HEAD

    export CFLAGS="-O2 -march=x86-64-v3 -mtune=generic"
    export CXXFLAGS="-O2 -march=x86-64-v3 -mtune=generic"

    ./build_openroad.sh \
      --local \
      --threads "${BUILD_THREADS}" \
      --no_init

    source ./env.sh

    echo
    echo "[Native tool validation]"

    command -v openroad
    command -v yosys

    openroad -version
    yosys -V
    yosys -m slang -p "slang_version"

    echo
    echo "[ASAP7 GCD CTS smoke test]"

    cd flow

    make \
      DESIGN_CONFIG=./designs/asap7/gcd/config.mk \
      clean_all

    make \
      DESIGN_CONFIG=./designs/asap7/gcd/config.mk \
      cts

    test -f results/asap7/gcd/base/4_1_cts.odb

    echo "NATIVE_GCD_CTS=PASS"
  '

echo
echo "[Package native tool installation]"

LOCAL_ARCHIVE="${LOCAL_ROOT}/$(basename "${PERSIST_ARCHIVE}")"

tar \
  -C "${ORFS_NATIVE}/tools" \
  -czf "${LOCAL_ARCHIVE}" \
  install

LOCAL_ARCHIVE_SHA256="$(
    sha256sum "${LOCAL_ARCHIVE}" |
    awk '{print $1}'
)"

PARTIAL_ARCHIVE="${PERSIST_ARCHIVE}.partial.${SLURM_JOB_ID}"

cp "${LOCAL_ARCHIVE}" "${PARTIAL_ARCHIVE}"
mv "${PARTIAL_ARCHIVE}" "${PERSIST_ARCHIVE}"

printf '%s  %s\n' \
  "${LOCAL_ARCHIVE_SHA256}" \
  "$(basename "${PERSIST_ARCHIVE}")" \
  > "${PERSIST_SHA}"

chmod 0444 "${PERSIST_ARCHIVE}" "${PERSIST_SHA}"

echo
echo "PERSIST_ARCHIVE=${PERSIST_ARCHIVE}"
echo "ARCHIVE_SHA256=${LOCAL_ARCHIVE_SHA256}"
echo "NATIVE_GCD_CTS=PASS"
echo "RESULT=PASS"