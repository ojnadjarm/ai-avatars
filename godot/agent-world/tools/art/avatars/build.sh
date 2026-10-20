#!/bin/bash
# Rebuild the 4 game avatar sheets with /pixel-avatar into assets/characters, plus owner review files in ~/drop/T714/avatars.
set -euo pipefail
P="$(cd "$(dirname "$(readlink -f "$0")")/../../.." && pwd)"
S="${PIXEL_AVATAR:-$HOME/.claude/skills/pixel-avatar}/scripts"
NAMES=(player_default darksaddler luna grok)
DROP="${AVATAR_DROP:-$HOME/drop/T714/avatars}"
load=$(cut -d' ' -f1 /proc/loadavg)
jobs=$(python3 -c "import os; print(max(1, os.cpu_count() - 2) if $load < 8 else 4)")
cd "$P"
echo "load $load jobs $jobs"
python3 "$S/build.py" --jobs "$jobs" --src tools/art/avatars/chars --out assets/characters "${NAMES[@]}"
mkdir -p "$DROP"
python3 "$S/sheet.py" --src assets/characters --out "$DROP" "${NAMES[@]}"
