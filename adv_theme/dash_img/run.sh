#!/usr/bin/env bash
set -euo pipefail
# Must run from adv_theme. No downloads are initiated by this script.
cd "$(dirname "$0")/.."
python dash_img/extract_bbb.py --list
python dash_img/extract_bbb.py --media-work runs/assets --time 120.5 \
  --targets 131087,595491,3078587 --strategy exact
