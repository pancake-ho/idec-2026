#!/usr/bin/env bash
set -euo pipefail

package_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repo_root="$(git -C "$package_root" rev-parse --show-toplevel 2>/dev/null || true)"

if [[ -z "$repo_root" ]]; then
  echo "ERROR: place far_pfdw_v19 directly inside an idec-2026 Git clone." >&2
  exit 2
fi

remote_url="$(git -C "$repo_root" remote get-url origin 2>/dev/null || true)"
branch="$(git -C "$repo_root" branch --show-current 2>/dev/null || true)"
head_sha="$(git -C "$repo_root" rev-parse HEAD)"

echo "Repository : $repo_root"
echo "Origin     : ${remote_url:-not configured}"
echo "Branch     : ${branch:-detached HEAD}"
echo "HEAD       : $head_sha"

case "$remote_url" in
  *github.com/pancake-ho/idec-2026.git|*github.com:pancake-ho/idec-2026.git)
    ;;
  *)
    echo "WARNING: origin is not the reviewed pancake-ho/idec-2026 URL." >&2
    ;;
esac

required_repo_files=(
  verilog/chip.v
  verilog/comparator.v
  verilog/conv1.v
  verilog/conv2.v
  verilog/fc.v
  verilog/maxpool_relu.v
  data/input_1000.txt
  data/conv1_weight_1.txt
  data/conv1_weight_2.txt
  data/conv1_weight_3.txt
  data/conv1_bias.txt
  data/conv2_bias.txt
  data/conv2_weight_11.txt
  data/conv2_weight_12.txt
  data/conv2_weight_13.txt
  data/conv2_weight_21.txt
  data/conv2_weight_22.txt
  data/conv2_weight_23.txt
  data/conv2_weight_31.txt
  data/conv2_weight_32.txt
  data/conv2_weight_33.txt
  data/fc_weight.txt
  data/fc_bias.txt
)

for relative_path in "${required_repo_files[@]}"; do
  if [[ ! -s "$repo_root/$relative_path" ]]; then
    echo "ERROR: repository file missing or empty: $relative_path" >&2
    exit 1
  fi
done

expected_data=(
  "297731cdb5dd28abceed33043856b1186fa85b9a data/input_1000.txt"
  "62cb3502e76873c3f2519965c8a24d5aa5bbcdf4 data/conv1_weight_1.txt"
  "045f680601a69e5ba48256658a6f4d9e85dd2c22 data/conv1_weight_2.txt"
  "537e7f5daf4b411c208aab57917e07702f2b67a4 data/conv1_weight_3.txt"
  "1830bf8d2c0a4aac134b8be2ddff90d6cf775f11 data/conv1_bias.txt"
  "c3c579facc19354ffd83e224c9badf2d17216791 data/conv2_bias.txt"
  "0f3e1b6beef331fac5ebb1371bae35dead60c72f data/conv2_weight_11.txt"
  "6f884eacd6ef49bb50de8b12218baa535f856948 data/conv2_weight_12.txt"
  "6ff8f699b54a3f31a258e28ef692ef9a3cb69466 data/conv2_weight_13.txt"
  "31051357b8a3c8aff6c0535ab83f76f402fe4719 data/conv2_weight_21.txt"
  "8ddd90e443721cc309d6dd65ccdbc63eef14c7d5 data/conv2_weight_22.txt"
  "308489783e74b409ebd2e83cff54aa579cc8f398 data/conv2_weight_23.txt"
  "112d8b8e0bd48e51cbe50ec55fec04e44b41d1d0 data/conv2_weight_31.txt"
  "539520c18e24a34c31e5956af1994d820aad54d1 data/conv2_weight_32.txt"
  "89f2fdd8a5e42b84a4871d09f281c1af9b4385af data/conv2_weight_33.txt"
  "79a0eca6f8a348956138534861ea1d4534a00b75 data/fc_weight.txt"
  "3ffb44f12690aba986fe172e252e0dab7d47197f data/fc_bias.txt"
)

for hash_and_path in "${expected_data[@]}"; do
  expected_hash="${hash_and_path%% *}"
  relative_path="${hash_and_path#* }"
  actual_hash="$(git -C "$repo_root" hash-object "$relative_path")"
  if [[ "$actual_hash" != "$expected_hash" ]]; then
    echo "ERROR: data hash mismatch: $relative_path" >&2
    echo "  expected $expected_hash" >&2
    echo "  actual   $actual_hash" >&2
    exit 1
  fi
done

expected_baseline=(
  "2d4ce5c8deb27a8e0fed09ec901aa827fcde51ad verilog/chip.v"
  "288b469d5036511c15fb7924ada8857ac5989e20 verilog/comparator.v"
  "20820c037b5ef756cc328a6b4639610b9e0293bc verilog/conv1.v"
  "4850120f18eea56fc303f1b4e42838d634bc817a verilog/conv2.v"
  "a193161c96379c636634273f5117e5089e36e1b1 verilog/fc.v"
  "29679e819d687d70f336cf33dcaf545a8d186705 verilog/maxpool_relu.v"
)

for hash_and_path in "${expected_baseline[@]}"; do
  expected_hash="${hash_and_path%% *}"
  relative_path="${hash_and_path#* }"
  actual_hash="$(git -C "$repo_root" hash-object "$relative_path")"
  if [[ "$actual_hash" != "$expected_hash" ]]; then
    echo "WARNING: $relative_path changed after the reviewed main snapshot." >&2
  fi
done

"$package_root/scripts/check_source.sh"
git -C "$repo_root" diff --check

for tool_name in xvlog xelab xsim; do
  if command -v "$tool_name" >/dev/null 2>&1; then
    echo "Vivado tool: $tool_name found"
  else
    echo "Vivado tool: $tool_name not found (activate Vivado before RTL run)"
  fi
done

if [[ -n "${ORFS_FLOW_DIR:-}" && -f "$ORFS_FLOW_DIR/Makefile" ]]; then
  echo "ORFS       : $ORFS_FLOW_DIR"
else
  echo "ORFS       : not configured (set ORFS_FLOW_DIR before PPA run)"
fi

echo "Data hashes: PASS"
echo "Preflight  : PASS"
