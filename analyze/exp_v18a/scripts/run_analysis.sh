#!/usr/bin/env bash
set -euo pipefail
# Usage: bash run_analysis.sh [repository root] [additional run.py options]
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
package_dir="$(cd -- "$script_dir/.." && pwd)"
repo_dir="${1:-$(cd -- "$package_dir/../.." && pwd)}"
if [[ $# -gt 0 ]]; then shift; fi
python_cmd="${PYTHON:-python3}"
exec "$python_cmd" "$package_dir/run.py" all --repo-root "$repo_dir" "$@"
