#!/bin/bash
# Darkwood check: pool, Watching Tree, stream and fog stills, a probe on the built spec and art (pool outline, stream
# bends and mouths, shore, mirror, glow), then the 20 s fps walk gate (p99 frame time <= P99_MS at load < 3).
# usage: dw_check.sh OUTDIR [P99_MS=16.7]
set -u
[ $# -ge 1 ] || { echo "usage: dw_check.sh OUTDIR [P99_MS]"; exit 2; }
P="$(cd "$(dirname "$0")/../.." && pwd)"
OUT=$1 GATE=${2:-16.7} D=$P/assets/worlds/darkwood
mkdir -p "$OUT"
for v in "pool 2230,870" "tree 330,1074" "stream 2290,560" "fog 1700,1250"; do
  set -- $v
  bash "$P/tools/render/run.sh" still res://tools/worldgen/preview.tscn "$OUT/$1.png" 90 -- --world res://assets/worlds/darkwood --at "$2" --zoom 2 | tail -1
done
python3 - "$D/scene.json" "$D/art" <<'EOF'; a=$?
import json, math, os, sys
sys.path.insert(0, os.path.expanduser(os.environ.get('PIXEL_SCENE', '~/.claude/skills/pixel-scene/scripts')))
import numpy as np
from PIL import Image
from art import poly, polyline_dist, smooth_path
spec, art = json.load(open(sys.argv[1])), sys.argv[2]
built = json.load(open(os.path.join(art, 'built.json')))
fails = []
pool = spec['water']['ponds'][0]
edge = max(math.dist(p, q) for p, q in zip(pool, pool[1:] + pool[:1]))
print(f'PROBE pool vertices {len(pool)} longest edge {edge:.1f} px')
if len(pool) < 64 or edge > 25:
    fails.append('pool is a coarse polygon')
streams = spec['water']['streams']
for k, s in enumerate(streams):
    pts = s['pts']
    length = sum(math.dist(p, q) for p, q in zip(pts, pts[1:]))
    (x0, y0), (x1, y1) = pts[0], pts[-1]
    chord = math.dist(pts[0], pts[-1])
    off = max(abs((x1 - x0) * (y0 - y) - (x0 - x) * (y1 - y0)) / chord for x, y in pts)
    c = np.array(smooth_path([tuple(p) for p in pts], 6), float)
    arc = np.r_[0, np.cumsum(np.hypot(*np.diff(c, axis=0).T))]
    t = np.arange(0, arc[-1], 4.0)
    q = np.c_[np.interp(t, arc, c[:, 0]), np.interp(t, arc, c[:, 1])]
    head = np.unwrap(np.arctan2(*np.diff(q, axis=0).T[::-1]))
    radius = 12 / max(np.abs(head[3:] - head[:-3]).max(), 1e-6)
    print(f'PROBE stream {k} sinuosity {length / chord:.3f} max bend {off:.0f} px min radius {radius:.1f} px')
    if length / chord < 1.02 or off < 15:
        fails.append(f'stream {k} is straight')
    if radius < 30:
        fails.append(f'stream {k} has a corner (radius {radius:.1f} < 30 px)')
X0, Y0 = min(p[0] for p in pool) - 60, min(p[1] for p in pool) - 60
W, H = max(p[0] for p in pool) + 60 - X0, max(p[1] for p in pool) + 60 - Y0
m = poly(W, H, [(x - X0, y - Y0) for x, y in pool])
for s in streams:
    m |= polyline_dist(W, H, [(x - X0, y - Y0) for x, y in smooth_path([tuple(p) for p in s['pts']], 6)]) < s['width'] / 2


def grow(a, r):
    for _ in range(r):
        b = a.copy()
        b[1:] |= a[:-1]
        b[:-1] |= a[1:]
        b[:, 1:] |= a[:, :-1]
        b[:, :-1] |= a[:, 1:]
        a = b
    return a


notch = ~grow(~grow(m, 6), 6) & ~m
yy, xx = np.mgrid[0:H, 0:W]
for name, (mx, my) in (('north', streams[1]['pts'][-1]), ('south', streams[2]['pts'][0])):
    px = int((notch & (np.hypot(xx - (mx - X0), yy - (my - Y0)) < 50)).sum())
    print(f'PROBE {name} mouth notch {px} px')
    if px > 12:
        fails.append(f'{name} stream mouth has a notch ({px} px)')
g = np.asarray(Image.open(os.path.join(art, 'ground.png')).convert('RGB'))[Y0:Y0 + H, X0:X0 + W].astype(int)
ring = grow(m, 6) & ~grow(m, 2)
mud = ring & (g[..., 1] < (g[..., 0] + g[..., 2]) // 2 + 8)
print(f'PROBE shore {mud.sum() / max(ring.sum(), 1):.2f} of the 3-6 px ring is bank (not grass)')
if mud.sum() < 0.6 * ring.sum():
    fails.append('pool has no shore band')
mir = [n for n in built['nodes'] if n['layer'] == 'mirror']
opaque = int((np.asarray(Image.open(os.path.join(art, mir[0]['files']['albedo'])))[..., 3] > 0).sum()) if mir else 0
print(f'PROBE mirror px {opaque} reeds {sum(n["name"].startswith("dw_reed") for n in built["nodes"])} '
      f'pads {sum(n["name"].startswith("dw_pad") for n in built["nodes"])}')
if opaque < 3000:
    fails.append('no tree reflection in the pool')
mist = sum(e['kind'] == 'mist' and e.get('w', 0) >= 40 for e in built['emit'])
print(f'PROBE mist emitters {mist} glow {built.get("glow")}')
if mist:
    fails.append('mist particle streaks remain')
if built.get('glow') is not True:
    fails.append('glow is off (owner 2026-10-20: glow on)')
print('PROBE ' + ('pass' if not fails else 'FAIL ' + '; '.join(fails)))
sys.exit(1 if fails else 0)
EOF
bash "$P/tools/render/fps_walk.sh" darkwood 20 "$GATE"; b=$?
[ $a -eq 0 ] && [ $b -eq 0 ] && echo "DWCHECK pass" && exit 0
echo "DWCHECK FAIL"; exit 1
