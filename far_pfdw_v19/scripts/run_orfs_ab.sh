#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${ORFS_FLOW_DIR:-}" ]]; then
  echo "ERROR: set ORFS_FLOW_DIR to the OpenROAD-flow-scripts/flow directory." >&2
  exit 2
fi

orfs_makefile="$ORFS_FLOW_DIR/Makefile"
if [[ ! -f "$orfs_makefile" ]]; then
  echo "ERROR: ORFS Makefile not found: $orfs_makefile" >&2
  exit 2
fi

package_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
log_dir="$package_root/build/orfs"
mkdir -p "$log_dir"

if git -C "$ORFS_FLOW_DIR" rev-parse HEAD >/dev/null 2>&1; then
  git -C "$ORFS_FLOW_DIR" rev-parse HEAD | tee "$log_dir/orfs_commit.txt"
else
  printf 'unknown\n' | tee "$log_dir/orfs_commit.txt"
fi

run_one() {
  local config_name="$1"
  local config="$package_root/orfs/$config_name/config.mk"

  if [[ ! -f "$config" ]]; then
    echo "ERROR: config not found: $config" >&2
    exit 2
  fi

  echo "Running ORFS: $config_name"
  (
    cd "$package_root"
    make --file="$orfs_makefile" DESIGN_CONFIG="$config"
    make --file="$orfs_makefile" DESIGN_CONFIG="$config" metadata-generate
  ) 2>&1 | tee "$log_dir/$config_name.log"
}

run_one chip_v18a
run_one chip_v19_far

echo "A/B runs finished. Run scripts/ppa_summary.sh."
echo "Reports: $package_root/reports/asap7"
