#!/bin/bash
# Record the scripted tour under headless weston (Movie Maker 1920x1080 @ 30 fps), encode OUTDIR/tour.mp4, write stills to OUTDIR.
# usage: run_tour.sh OUTDIR
set -euo pipefail
[ $# -eq 1 ] || { echo "usage: run_tour.sh OUTDIR"; exit 2; }
P="$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)"
OUT="$(mkdir -p "$1" && cd "$1" && pwd)"
MAX_FRAMES=${TOUR_MAX_FRAMES:-3900}
mkdir -p "${TOUR_TMP:-$HOME/.cache}"
FRAMES=$(mktemp -d "${TOUR_TMP:-$HOME/.cache}/aiw-tour.XXXXXX")
SOCK=aiw-tour-$$
RT=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
weston --backend=headless --renderer=gl --width=1920 --height=1080 --socket=$SOCK --idle-time=0 >/dev/null 2>&1 &
WP=$!
cleanup() { kill $WP 2>/dev/null || true; rm -rf "$FRAMES"; }
trap cleanup EXIT
for _ in $(seq 1 40); do [ -S "$RT/$SOCK" ] && break; sleep 0.25; done
LOG="$FRAMES/godot.log"
start=$(date +%s)
for try in 1 2 3; do
  rm -f "$FRAMES"/f*.png
  WAYLAND_DISPLAY=$SOCK timeout "${TOUR_TIMEOUT:-1800}" godot --path "$P" --display-driver wayland --audio-driver Dummy \
    --resolution 1920x1080 --fixed-fps 30 --write-movie "$FRAMES/f.png" --quit-after "$MAX_FRAMES" \
    res://tools/tour/tour.tscn -- --offline --out "$OUT" > "$LOG" 2>&1 || true
  grep -q '^\[tour\] done' "$LOG" && break
  echo "retry $try: tour did not finish"
  tail -5 "$LOG"
done
grep -E '^\[tour\]|SCRIPT ERROR|^ERROR' "$LOG" | grep -v mcp_server | grep -v '\[tour\] still' | head -40
grep -q '^\[tour\] done' "$LOG" || { echo "FAIL tour did not finish"; exit 1; }
n=$(ls "$FRAMES"/f*.png | wc -l)
echo "frames $n ($(( $(date +%s) - start )) s to record)"
ffmpeg -v error -y -framerate 30 -i "$FRAMES/f%08d.png" -c:v libx264 -preset slow -crf 18 -pix_fmt yuv420p \
  -an -movflags +faststart "$OUT/tour.mp4"
echo "TOUR $OUT/tour.mp4 $(ffprobe -v error -show_entries format=duration -of csv=p=0 "$OUT/tour.mp4") s, $(ls "$OUT"/*.png | wc -l) stills"
