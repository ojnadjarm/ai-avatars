#!/bin/bash
# Render a scene of this project under headless weston on the real GPU with Movie Maker (no window, no audio).
# usage: run.sh still RES_SCENE OUT.png [FRAME] [-- user args] | run.sh movie RES_SCENE OUTDIR FRAMES [-- user args]
set -u
usage() { echo "usage: run.sh still RES_SCENE OUT.png [FRAME] [-- args] | run.sh movie RES_SCENE OUTDIR FRAMES [-- args]"; exit 2; }
[ $# -ge 3 ] || usage
P="$(cd "$(dirname "$0")/../.." && pwd)"
MODE=$1 SCENE=$2 OUT=$3; shift 3
N=""
if [ $# -gt 0 ] && [ "$1" != "--" ]; then N=$1; shift; fi
[ "${1:-}" = "--" ] && shift
case "$MODE" in
  still) N=${N:-90}; FRAMES_DIR=$(mktemp -d) ;;
  movie) [ -n "$N" ] || usage; FRAMES_DIR=$OUT; mkdir -p "$FRAMES_DIR"; rm -f "$FRAMES_DIR"/f*.png ;;
  *) usage ;;
esac
SOCK=aiw-wl-$$
RT=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
weston --backend=headless --renderer=gl --width=1920 --height=1080 --socket=$SOCK --idle-time=0 >/dev/null 2>&1 &
WP=$!
cleanup() { kill $WP 2>/dev/null; [ "$MODE" = still ] && rm -rf "$FRAMES_DIR"; }
trap cleanup EXIT
for _ in $(seq 1 40); do [ -S "$RT/$SOCK" ] && break; sleep 0.25; done
if [ "$MODE" = still ]; then LAST=$(printf '%s/f%08d.png' "$FRAMES_DIR" "$N"); else LAST=$(printf '%s/f%08d.png' "$FRAMES_DIR" $(( N - 1 ))); fi
for try in 1 2 3; do
  WAYLAND_DISPLAY=$SOCK timeout $(( N / 2 + 150 )) godot --path "$P" --display-driver wayland --audio-driver Dummy \
    --resolution 1920x1080 --fixed-fps 30 --write-movie "$FRAMES_DIR/f.png" --quit-after $(( N + 2 )) "$SCENE" -- --offline "$@" 2>&1 \
    | grep -E "ERROR|SCRIPT|error|\[preview\]|\[world_art\]" | grep -v mcp_server | head -30
  [ -s "$LAST" ] && break
  echo "retry $try: godot stalled at start"
done
[ -s "$LAST" ] || { echo "FAIL no frame $LAST"; exit 1; }
if [ "$MODE" = still ]; then
  mkdir -p "$(dirname "$OUT")"
  mv "$LAST" "$OUT"
  echo "STILL $OUT (frame $N)"
else
  for i in $(seq "$N" $(( N + 3 ))); do rm -f "$(printf '%s/f%08d.png' "$FRAMES_DIR" "$i")"; done
  echo "MOVIE $FRAMES_DIR $(ls "$FRAMES_DIR"/f*.png | wc -l) frames"
fi
