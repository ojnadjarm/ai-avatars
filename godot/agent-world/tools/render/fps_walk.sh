#!/bin/bash
# Real-time frame times of a world walk at 1920x1080 under headless weston on the GPU (no Movie Maker, vsync off).
# Exit 1 when p99 frame time > P99_MS, 3 when the 1-min load is >= MAX_LOAD (a busy machine makes the run meaningless).
# usage: fps_walk.sh WORLD_ID [SECS=20] [P99_MS=16.7] [MAX_LOAD=3]
set -u
[ $# -ge 1 ] || { echo "usage: fps_walk.sh WORLD_ID [SECS] [P99_MS] [MAX_LOAD]"; exit 2; }
P="$(cd "$(dirname "$0")/../.." && pwd)"
ID=$1 SECS=${2:-20} GATE=${3:-16.7} MAX_LOAD=${4:-3}
SOCK=aiw-fps-$$
RT=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
weston --backend=headless --renderer=gl --width=1920 --height=1080 --socket=$SOCK --idle-time=0 >/dev/null 2>&1 &
WP=$!
LOG=$(mktemp)
trap 'kill $WP 2>/dev/null; rm -f $LOG' EXIT
for _ in $(seq 1 40); do [ -S "$RT/$SOCK" ] && break; sleep 0.25; done
LOAD=$(cut -d' ' -f1 /proc/loadavg)
echo "load $LOAD"
awk -v l="$LOAD" -v m="$MAX_LOAD" 'BEGIN { exit !(l >= m) }' && { echo "FPS SKIP load $LOAD >= $MAX_LOAD"; exit 3; }
for try in 1 2 3; do
  WAYLAND_DISPLAY=$SOCK timeout $(( SECS + 90 )) godot --path "$P" --display-driver wayland --audio-driver Dummy \
    --resolution 1920x1080 --disable-vsync res://tools/render/fps_walk.tscn -- --offline --world "$ID" --secs "$SECS" ${FPS_ARGS:-} > "$LOG" 2>&1
  grep -q '^\[fps\] min=' "$LOG" && break
  echo "retry $try: no fps report"
done
grep -E '^\[fps\]|SCRIPT ERROR' "$LOG"
P99=$(sed -n 's/^\[fps\] p50=.* p99=\([0-9.]*\)ms.*/\1/p' "$LOG")
[ -n "$P99" ] && awk -v p="$P99" -v g="$GATE" 'BEGIN { exit !(p <= g) }' && { echo "FPS pass p99 ${P99} ms <= $GATE"; exit 0; }
echo "FPS FAIL p99 ${P99:-none} ms > $GATE"; exit 1
