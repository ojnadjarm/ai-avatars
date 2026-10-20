#!/bin/bash
# Build the title menu art (bg, fg, ui layers) into OUT_DIR (default P/assets/menu).
set -euo pipefail
cd "$(dirname "$0")"
ARGS=()
[ $# -ge 1 ] && ARGS=(--out "$1")
python3 bg.py "${ARGS[@]}"
python3 fg.py "${ARGS[@]}"
python3 ui.py "${ARGS[@]}"
