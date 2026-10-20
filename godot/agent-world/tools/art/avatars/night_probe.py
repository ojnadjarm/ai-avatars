#!/usr/bin/env python3
"""Night readability of the real player.gd node in Darkwood at x3: edge and body vs ground (WCAG) >= 3:1 and head p98 L* < 90 (no white blob); exits 1 otherwise."""
import os, sys, argparse, subprocess, tempfile
import numpy as np
from PIL import Image

P = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../..'))
SPOTS = [(1330, 600), (505, 900), (1520, 1150)]
LIFT = 30


def render(out, spot, flag):
    args = ['--world', 'res://assets/worlds/darkwood', '--avatars', '--zoom', '3',
            '--at', '%d,%d' % (spot[0], spot[1] - LIFT), '--player-at', '%d,%d' % spot] + ([flag] if flag else [])
    r = subprocess.run(['bash', os.path.join(P, 'tools/render/run.sh'), 'still', 'res://tools/worldgen/preview.tscn', out, '90', '--'] + args,
                       capture_output=True, text=True)
    if not os.path.exists(out):
        sys.exit('render failed: ' + r.stdout[-400:])
    return np.asarray(Image.open(out).convert('RGB'), float) / 255.0


def dilate(m, n):
    for _ in range(n):
        p = np.pad(m, 1)
        m = p[1:-1, 1:-1] | p[:-2, 1:-1] | p[2:, 1:-1] | p[1:-1, :-2] | p[1:-1, 2:]
    return m


def erode(m, n):
    return ~dilate(~m, n)


def luma(rgb):
    c = np.where(rgb <= 0.04045, rgb / 12.92, ((rgb + 0.055) / 1.055) ** 2.4)
    return c @ np.array([0.2126, 0.7152, 0.0722])


def lstar(y):
    return np.where(y > 0.008856, 116.0 * np.cbrt(y) - 16.0, 903.3 * y)


def head(mask):
    rows = np.where(mask.any(1))[0]
    m = mask.copy()
    m[rows[0] + int(0.25 * (rows[-1] - rows[0] + 1)):] = False
    return m


def ratio(a, b):
    hi, lo = max(a, b), min(a, b)
    return (hi + 0.05) / (lo + 0.05)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--out', default=tempfile.mkdtemp(prefix='night-probe-'))
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    worst = 99.0; worst_body = 99.0; worst_head = 0.0
    for i, spot in enumerate(SPOTS):
        im = {k: render('%s/s%d-%s.png' % (a.out, i, k), spot, f) for k, f in (('rim', ''), ('norim', '--no-rim'), ('hide', '--hide-player'))}
        y0, y1, x0, x1 = 540 + 3 * LIFT - 300, 540 + 3 * LIFT + 30, 960 - 120, 960 + 120
        crop = {k: v[y0:y1, x0:x1] for k, v in im.items()}
        mask = np.abs(crop['norim'] - crop['hide']).sum(-1) > 0.05
        mask = dilate(erode(mask, 1), 1)
        mask[:100] = False; mask[:, :60] = False; mask[:, 180:] = False
        edge = mask & ~erode(mask, 3)
        ring = dilate(mask, 15) & ~dilate(mask, 3)
        g = float(np.median(luma(crop['hide'][ring])))
        e_rim, e_no = float(luma(crop['rim'][edge]).mean()), float(luma(crop['norim'][edge]).mean())
        b_rim, b_no = float(luma(crop['rim'][mask]).mean()), float(luma(crop['norim'][mask]).mean())
        r_edge = ratio(e_rim, g)
        h = float(np.percentile(lstar(luma(crop['rim'][head(mask)])), 98))
        worst_head = max(worst_head, h)
        worst = min(worst, r_edge); worst_body = min(worst_body, ratio(b_rim, g))
        print('spot %s px %d ground %.3f | edge %.2f:1 (no rim %.2f:1) | body %.2f:1 (no rim %.2f:1) | head p98 L* %.1f' % (
            spot, int(mask.sum()), g, r_edge, ratio(e_no, g), ratio(b_rim, g), ratio(b_no, g), h))
        Image.fromarray(np.concatenate([(crop[k] * 255).astype(np.uint8) for k in ('norim', 'rim', 'hide')], 1)).save('%s/s%d-crop.png' % (a.out, i))
    ok = worst >= 3.0 and worst_body >= 3.0 and worst_head < 90.0
    print('NIGHT %s worst edge %.2f:1 body %.2f:1 head L* %.1f (%s)' % ('pass' if ok else 'fail', worst, worst_body, worst_head, a.out))
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main())
