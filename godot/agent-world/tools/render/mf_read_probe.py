#!/usr/bin/env python3
"""Magic Forest readability probe: lake shape (no hourglass), plateau reads as raised, Moss Gate reads, on preview stills.
usage: mf_read_probe.py SPEC.json --plateau STILL@X,Y,K --gate STILL@X,Y,K"""
import argparse
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.expanduser(os.environ.get('PIXEL_SCENE', '~/.claude/skills/pixel-scene/scripts')))
import art  # noqa: E402
import terrain  # noqa: E402

# Thresholds: a pinch below 0.85 or solidity below 0.95 reads as an hourglass (old lake 0.68, 0.92); a face under 44 px
# is under 2/3 of a 63-78 px avatar; ΔE 20 is "a different material" (old face vs path 3.6); the old build measured 1.7 L*
# top vs lowland and 5.5 L* shadow (10-20 px below the foot vs 34-64 px), both judged unreadable, so the bar is 8 and 7.5.
LIMITS = {'pinch': 0.85, 'solidity': 0.95, 'face_px': 44, 'face_vs_path_de': 20.0, 'top_vs_low_l': 8.0,
          'shadow_l': 7.5, 'gate_px': 1500, 'moss_hue': (70.0, 150.0)}


def lab(rgb):
    """sRGB 0..1 (N,3) -> CIE L*a*b* (D65)."""
    c = np.where(rgb > 0.04045, ((rgb + 0.055) / 1.055) ** 2.4, rgb / 12.92)
    xyz = c @ np.array([[0.4124, 0.3576, 0.1805], [0.2126, 0.7152, 0.0722], [0.0193, 0.1192, 0.9505]]).T
    xyz /= np.array([0.95047, 1.0, 1.08883])
    f = np.where(xyz > 0.008856, np.cbrt(xyz), 7.787 * xyz + 16 / 116)
    return np.stack([116 * f[:, 1] - 16, 500 * (f[:, 0] - f[:, 1]), 200 * (f[:, 1] - f[:, 2])], 1)


def view(arg, W, H):
    """STILL@X,Y,K -> (image 0..1, art x per screen px, art y per screen px, in-map mask)."""
    path, cam = arg.split('@')
    cx, cy, k = (float(v) for v in cam.split(','))
    img = np.asarray(Image.open(path).convert('RGB'), np.float32) / 255
    sh, sw = img.shape[:2]
    ys, xs = np.mgrid[0:sh, 0:sw]
    ax = np.floor(cx + (xs + 0.5 - sw / 2) / k).astype(int)
    ay = np.floor(cy + (ys + 0.5 - sh / 2) / k).astype(int)
    inside = (ax >= 0) & (ax < W) & (ay >= 0) & (ay < H)
    return img, np.clip(ax, 0, W - 1), np.clip(ay, 0, H - 1), inside


def lake_shape(spec):
    """Row-width pinch (narrowest / widest row in the middle 60%) and solidity (area / convex hull area) of pond 0."""
    pts = spec['water']['ponds'][0]
    xs, ys = [p[0] for p in pts], [p[1] for p in pts]
    x0, y0 = min(xs), min(ys)
    im = Image.new('L', (max(xs) - x0 + 1, max(ys) - y0 + 1))
    ImageDraw.Draw(im).polygon([(p[0] - x0, p[1] - y0) for p in pts], fill=1)
    w = (np.asarray(im) > 0).sum(1)
    n = len(w)
    pinch = w[int(n * 0.2):int(n * 0.8)].min() / w.max()
    hull = Image.new('L', im.size)
    ImageDraw.Draw(hull).polygon(_hull([(p[0] - x0, p[1] - y0) for p in pts]), fill=1)
    solidity = (np.asarray(im) > 0).sum() / max((np.asarray(hull) > 0).sum(), 1)
    return float(pinch), float(solidity)


def _hull(pts):
    pts = sorted(set(pts))
    cross = lambda o, a, b: (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
    lo, hi = [], []
    for p in pts:
        while len(lo) >= 2 and cross(lo[-2], lo[-1], p) <= 0:
            lo.pop()
        lo.append(p)
    for p in reversed(pts):
        while len(hi) >= 2 and cross(hi[-2], hi[-1], p) <= 0:
            hi.pop()
        hi.append(p)
    return lo[:-1] + hi[:-1]


def path_mask(spec, W, H):
    """Path cores (half width minus 2 px) drawn as thick polylines."""
    im = Image.new('L', (W, H), 0)
    d = ImageDraw.Draw(im)
    for p in spec.get('paths', []):
        hw = max(p['width'] / 2 - 2, 1)
        pts = art.smooth_path([tuple(q) for q in p['pts']], 8)
        d.line(pts, fill=255, width=int(2 * hw))
        for x, y in pts:
            d.ellipse([x - hw, y - hw, x + hw, y + hw], fill=255)
    return np.asarray(im) > 0


def water_mask(spec, W, H):
    """Streams (plus banks) and ponds, kept out of the ground samples."""
    im = Image.new('L', (W, H), 0)
    d = ImageDraw.Draw(im)
    for st in spec['water'].get('streams', []):
        d.line(art.smooth_path([tuple(q) for q in st['pts']], 6), fill=255, width=int(st['width'] + 8))
    for pp in spec['water'].get('ponds', []):
        d.polygon([tuple(q) for q in pp], fill=255)
    return np.asarray(im) > 0


def plateau(spec, arg):
    """Face vs path ΔE (foliage-green occluders left out), top vs lowland L*, shadow band vs open lowland L*, on the still."""
    W, H = spec['size']
    c = spec['cliff']
    top, face, _, edge, _ = terrain.plateau(spec, W, H)
    paths = path_mask(spec, W, H) | water_mask(spec, W, H)
    img, ax, ay, inside = view(arg, W, H)
    yy = np.arange(H)[:, None]
    below = yy - (edge[None, :] + c['height'])
    has = top.any(0)[None, :]
    low_near = (below >= 10) & (below < 20) & has & ~paths
    low_far = (below >= 34) & (below < 64) & has & ~paths
    top_near = top & (yy >= edge[None, :] - 120) & (yy < edge[None, :] - 4) & ~paths
    stairs = (np.arange(W)[None, :] >= c['stairs'][0] - 4) & (np.arange(W)[None, :] < c['stairs'][1] + 4)
    masks = {'face': face & ~stairs, 'path': path_mask(spec, W, H) & ~face & ~top, 'top': top_near, 'near': low_near, 'far': low_far}
    L = {}
    for k, m in masks.items():
        sel = inside & m[ay, ax]
        if sel.sum() < 400:
            sys.exit(f'FAIL plateau view has only {int(sel.sum())} {k} px')
        L[k] = lab(img[sel])
    med = {k: np.median(v, 0) for k, v in L.items()}
    mat = {k: np.median(v[~((v[:, 1] < -8) & (v[:, 2] > 8))], 0) for k, v in L.items() if k in ('face', 'path')}
    de = float(np.linalg.norm(mat['face'] - mat['path']))
    return {'face_px': c['height'], 'face_vs_path_de': de, 'top_vs_low_l': float(med['top'][0] - med['far'][0]),
            'shadow_l': float(med['far'][0] - med['near'][0])}


def gate(spec, arg):
    """Torii red pixels around the Moss Gate and the mean hue of the moss ground around it."""
    W, H = spec['size']
    img, ax, ay, inside = view(arg, W, H)
    g = next(p for p in spec['props'] if p['kind'] == 'gate')
    gx, gy = g['at']
    box = inside & (np.abs(ax - gx) < 40) & (ay > gy - 100) & (ay < gy + 4)
    r, gg, b = img[..., 0], img[..., 1], img[..., 2]
    red = int((box & (r > 0.45) & (r > gg * 1.6) & (r > b * 1.6)).sum())
    ring = inside & (np.hypot(ax - gx, (ay - gy) * 1.6) < 160) & ~box
    sel = img[ring]
    mx, mn = sel.max(1), sel.min(1)
    green = sel[(mx - mn) > 0.08]
    rr, g2, bb = green.mean(0)
    import colorsys
    hue = colorsys.rgb_to_hls(rr, g2, bb)[0] * 360
    return {'gate_px': red, 'moss_hue': hue}


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument('spec')
    ap.add_argument('--plateau', required=True)
    ap.add_argument('--gate', required=True)
    a = ap.parse_args()
    import json
    spec = json.load(open(a.spec))
    pinch, solidity = lake_shape(spec)
    got = {'pinch': pinch, 'solidity': solidity}
    got.update(plateau(spec, a.plateau))
    got.update(gate(spec, a.gate))
    ok = True
    for k, lim in LIMITS.items():
        v = got[k]
        good = lim[0] <= v <= lim[1] if isinstance(lim, tuple) else v >= lim
        ok &= good
        print(f'{"pass" if good else "FAIL"} {k} {v:.2f} (limit {lim})')
    print(f'MFREAD {"pass" if ok else "FAIL"}')
    sys.exit(0 if ok else 1)


if __name__ == '__main__':
    main()
