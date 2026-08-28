#!/usr/bin/env bash
set -euo pipefail

package_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
python3 "$package_root/scripts/collect_ppa.py" \
  --package-root "$package_root" \
  --csv "$package_root/build/orfs/ppa_summary.csv" \
  --markdown "$package_root/build/orfs/ppa_summary.md"
