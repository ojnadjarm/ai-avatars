#!/usr/bin/env python3
"""Day-lake probe: mean lake colour of a preview still (HSL lightness, hue) and no moon glitter in a day built.json.
usage: water_probe.py STILL.png SPEC.json BUILT.json --at X,Y --zoom K [--pond N] [--min-l 0.35] [--hue 160,200]"""
import argparse
import colorsys
import json
import sys

import numpy as np
from PIL import Image, ImageDraw


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument('still')
    ap.add_argument('spec')
    ap.add_argument('built')
    ap.add_argument('--at', required=True)
    ap.add_argument('--zoom', type=float, required=True)
    ap.add_argument('--pond', type=int, default=0)
    ap.add_argument('--min-l', type=float, default=0.35)
    ap.add_argument('--hue', default='160,200')
    a = ap.parse_args()
    spec, built = json.load(open(a.spec)), json.load(open(a.built))
    img = np.asarray(Image.open(a.still).convert('RGB'), np.float32) / 255
    sh, sw = img.shape[:2]
    cx, cy = (float(v) for v in a.at.split(','))
    W, H = spec['size']
    m = Image.new('L', (W, H), 0)
    d = ImageDraw.Draw(m)
    d.polygon([tuple(p) for p in spec['water']['ponds'][a.pond]], fill=255)
    for x0, y0, x1, y1 in spec['water'].get('crossings', []):
        d.rectangle([x0, y0, x1, y1], fill=0)
    mask = np.asarray(m) > 0
    ys, xs = np.mgrid[0:sh, 0:sw]
    ax = np.floor(cx + (xs + 0.5 - sw / 2) / a.zoom).astype(int)
    ay = np.floor(cy + (ys + 0.5 - sh / 2) / a.zoom).astype(int)
    inside = (ax >= 0) & (ax < W) & (ay >= 0) & (ay < H)
    lake = np.zeros((sh, sw), bool)
    lake[inside] = mask[ay[inside], ax[inside]]
    n = int(lake.sum())
    if n < 1000:
        sys.exit(f'FAIL only {n} lake pixels in view')
    r, g, b = img[lake].mean(0)
    hue, light, _ = colorsys.rgb_to_hls(r, g, b)
    hue *= 360
    h0, h1 = (float(v) for v in a.hue.split(','))
    day = bool(built.get('day', False))
    moon_off = built.get('moon_reflect') is None
    ok = light > a.min_l and h0 <= hue <= h1 and (moon_off or not day)
    print(f'WATER {"pass" if ok else "FAIL"} px {n} rgb {r * 255:.0f},{g * 255:.0f},{b * 255:.0f} '
          f'L {light:.3f} (>{a.min_l}) hue {hue:.0f} ({h0:.0f}-{h1:.0f}) day {day} moon_reflect {built.get("moon_reflect")}')
    sys.exit(0 if ok else 1)


if __name__ == '__main__':
    main()
