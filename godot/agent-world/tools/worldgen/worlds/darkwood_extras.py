"""Darkwood extras hooks: landmarks no pixel-scene kind draws, built from the skill's Sprite primitives."""
import json
import math
import os

import numpy as np
from PIL import Image, ImageDraw

import flora
import props
import world_foliage
from art import I, Sprite, dome, ellipse, grid, line, poly, rng, value_noise
from kit import BAYER

WARM = [255, 176, 96]
MAGENTA = [255, 80, 200]
CRIMSON = [255, 46, 60]


def _cyl(xx, cx, half, r):
    """Cylinder height across x for a column of half width `half`."""
    u = np.clip((xx - cx) / np.maximum(half, 1e-3), -1, 1)
    return np.sqrt(1 - u * u) * r


def _lamp(seed, hgt):
    """Tall iron road lantern on a wooden post with a hook arm; returns sprite, pivot, glass centre."""
    w, h = 24, hgt + 6
    S = Sprite(w, h)
    yy, xx = grid(h, w)
    base, top = h - 3, h - 3 - hgt
    nz = (value_noise(w, h, 2, seed) - 0.5) * 0.14
    post = (xx >= 5) & (xx <= 7) & (yy >= top) & (yy <= base)
    S.put(post, 'wood', _cyl(xx, 6, 1.6, 1.6), nz)
    for by in (top + 10, base - 12):
        S.put(post & (yy >= by) & (yy <= by + 1), 'iron', 2.2, 0.1)
    S.put((yy >= top) & (yy <= top + 1) & (xx >= 5) & (xx <= 18), 'iron', 2.5, 0.12)
    S.put(line(w, h, [(7, top + 8), (14, top + 1)], 1), 'iron', 2.0, 0.0)
    S.put((xx == 16) & (yy >= top + 2) & (yy <= top + 5), 'iron', 2.0, 0.0)
    g0 = top + 9
    cap = poly(w, h, [(11, g0), (21, g0), (19, g0 - 3), (13, g0 - 3)])
    S.put(cap, 'iron', 4.0 + (g0 - yy) * 0.4, 0.15)
    frame = (xx >= 12) & (xx <= 20) & (yy >= g0) & (yy <= g0 + 11)
    glass = (xx >= 13) & (xx <= 19) & (yy >= g0 + 1) & (yy <= g0 + 10)
    S.put(frame, 'iron', 3.0, 0.0)
    S.put(glass, 'gold', 3.0, 0.5)
    S.pin(glass, 'G2')
    core = glass & (yy >= g0 + 4) & (yy <= g0 + 7) & (xx >= 15) & (xx <= 17)
    S.pin(core, 'G3')
    bars = glass & ((xx == 16) | (yy == g0 + 5))
    S.pin(bars & ~core, 'N1')
    S.glow(glass & ~bars, (255, 190, 100), 0.5)
    S.glow(core, (255, 236, 170), 0.45)
    S.put((yy >= g0 + 11) & (yy <= g0 + 12) & (xx >= 13) & (xx <= 19), 'iron', 2.0, 0.1)
    S.put((xx == 16) & (yy == g0 + 13), 'iron', 1.0, 0.0)
    foot = ellipse(w, h, 6, base, 5, 2)
    S.put(foot, 'stone', dome(foot, 1.5) + 0.5, -0.05)
    return S, (6, base), (16, g0 + 5)


def road_lanterns(g, e, spec):
    """Shoulder-high lanterns at e['pts'] [[x, y], ...]: sprite, post collision, warm flickering light and halo."""
    hgt = e.get('height', 62)
    for k, (x, y) in enumerate(e['pts']):
        S, piv, glass = _lamp(31 + k, hgt)
        g.add(f'dw_lamp{k}', S, piv, x, y, shape=('rect', x - 3, y - 3, 6, 4))
        gx, gy = x - piv[0] + glass[0], y - piv[1] + glass[1]
        g.light('point', gx, gy + 5, WARM, e.get('energy', 0.95), e.get('radius', 104), 30, flicker=0.16)
        g.emitter('halo', gx, gy, color=[255, 196, 120], size=22)


def _limb(im, pts, w0, w1):
    """Tapered limb: discs along a polyline, width w0 at the start to w1 at the end, drawn into a PIL L image."""
    d = ImageDraw.Draw(im)
    pts = [np.array(p, float) for p in pts]
    total = sum(np.hypot(*(q - p)) for p, q in zip(pts[:-1], pts[1:])) or 1.0
    s = 0.0
    for p, q in zip(pts[:-1], pts[1:]):
        ln = np.hypot(*(q - p))
        for t in np.arange(0, ln, 0.7):
            c = p + (q - p) * t / max(ln, 1e-3)
            r = (w0 + (w1 - w0) * (s + t) / total) / 2
            d.ellipse([c[0] - r, c[1] - r, c[0] + r, c[1] + r], fill=255)
        s += ln


def _bough(r, x, y, ang, length, wd, depth, out):
    """Crooked branch from (x, y) at `ang` (rad, 0 = up): bends a little each knot, forks into thinner boughs."""
    pts, a = [(x, y)], ang
    for _ in range(4):
        a += r.uniform(-0.32, 0.32)
        x, y = x + math.sin(a) * length / 4, y - math.cos(a) * length / 4
        pts.append((x, y))
    out.append((pts, wd, max(wd * 0.5, 1.2), depth))
    if depth == 0:
        return
    for k, side in enumerate((-1, 1)):
        fx, fy = pts[2 + k]
        _bough(r, fx, fy, a + side * r.uniform(0.35, 0.75), length * r.uniform(0.55, 0.72), wd * 0.55, depth - 1, out)
    _bough(r, x, y, a + r.uniform(-0.2, 0.2), length * 0.6, wd * 0.5, depth - 1, out)


def _tree_mask(w, h, cx, base, seed=17):
    """Gnarled leaning trunk with a root flare, crooked tapering boughs that fork three deep, splayed roots; (mask, limb mask)."""
    r = rng(seed)
    yy, xx = grid(h, w)
    up = (base - yy).astype(float)
    spine = cx + 5 * np.sin(up / 46) - up * 0.03
    half = 20 + 24 * np.exp(-up / 13) + 3 * np.sin(up / 9) * (up > 20) - np.clip(up - 100, 0, 60) * 0.3
    trunk = (np.abs(xx - spine) <= half) & (up >= 0) & (up <= 142)
    im = Image.new('L', (w, h))
    boughs = []
    tops = ((-1.05, 78, 14), (-0.5, 92, 13), (0.05, 84, 16), (0.55, 90, 13), (1.1, 76, 12))
    for k, (ang, ln, wd) in enumerate(tops):
        y0 = base - 116 - k % 2 * 14 - (k == 2) * 18
        x0 = cx + 5 * math.sin((base - y0) / 46) - (base - y0) * 0.03 + ang * 9
        _bough(r, x0, y0, ang, ln, wd, 2, boughs)
    for pts, w0, w1, depth in boughs:
        _limb(im, pts, w0, w1)
    limbs = np.array(im) > 0
    twig_im = Image.new('L', (w, h))
    td = ImageDraw.Draw(twig_im)
    for pts, w0, w1, depth in boughs:
        if depth == 0:
            x, y = pts[-1]
            for _ in range(2):
                a = r.uniform(-1.4, 1.4)
                x1, y1 = x + math.sin(a) * r.uniform(5, 11), y - math.cos(a) * r.uniform(5, 11)
                td.line([(x, y), (x1, y1), (x1 + r.uniform(-4, 4), y1 - r.uniform(2, 5))], fill=255, width=1)
    twigs = np.array(twig_im) > 0
    root_im = Image.new('L', (w, h))
    for side, reach, drop, wd in ((-1, 98, 3, 13), (1, 104, 2, 13), (-1, 56, 7, 9), (1, 62, 6, 9), (-1, 30, 9, 7), (1, 34, 8, 7)):
        x0 = cx + side * 14
        pts = [(x0, base - 14), (x0 + side * reach * 0.35, base - 6 + r.uniform(-2, 2)),
               (x0 + side * reach * 0.7, base - 1 + r.uniform(-2, 2)), (x0 + side * reach, base + drop * 0.3)]
        _limb(root_im, pts, wd, 2)
    roots = np.array(root_im) > 0
    limbs &= ~trunk
    return trunk | limbs | twigs | roots, limbs | twigs


def _watcher_sprite(seed):
    """The Watching Tree: bark, moss on limb tops, hanging moss, closed knot eyes, wound mouth, shelf fungi, root hollow."""
    w, h = 290, 304
    cx, base = 145, h - 6
    m, limbs = _tree_mask(w, h, cx, base, seed)
    S = Sprite(w, h)
    yy, xx = grid(h, w)
    wav = np.sin(xx * 0.9 + value_noise(w, h, 5, seed + 7) * 5)
    grain = np.sin(xx * 1.9 + value_noise(w, h, 6, seed) * 7) * 0.1 + (value_noise(w, h, 3, seed + 1) - 0.5) * 0.2
    S.put(m, 'bark', dome(m, 9) + _cyl(xx, cx, 22, 4) * (yy > base - 150), grain - 0.16)
    S.pin(m & ~limbs & (wav > 0.9) & (yy > base - 100) & (yy < base - 4), 'W0')
    top = m & ~np.roll(m, 2, axis=0) & limbs
    S.put(top & (value_noise(w, h, 3, seed + 2) > 0.35), 'moss', S.hgt + 0.6, 0.04)
    r = rng(seed)
    for _ in range(44):
        x0 = int(r.uniform(cx - 130, cx + 130))
        col = np.nonzero(limbs[:, x0])[0]
        if col.size == 0:
            continue
        y0 = col.max() + 1
        S.put((xx == x0) & (yy >= y0) & (yy < y0 + r.integers(6, 28)), 'moss', 1.0, -0.12)
    for ex, ey in ((cx - 9, base - 104), (cx + 9, base - 106)):
        knot = ellipse(w, h, ex, ey, 6.5, 3.5) & m
        S.put(knot, 'bark', S.hgt - 1.5, -0.3)
        slit = (np.abs(yy - ey) < 1) & (np.abs(xx - ex) <= 5)
        S.pin(slit & ~(np.abs(xx - ex) <= 1), 'N0')
        lid = (yy == ey - 3) & (np.abs(xx - ex) <= 4)
        S.pin(lid, 'W0')
        glint = slit & (np.abs(xx - ex) <= 1)
        S.pin(glint, 'M3')
        S.glow(glint, (255, 90, 210), 1.0)
    mouth = ellipse(w, h, cx, base - 64, 10, 6) & (yy > base - 66)
    S.pin(mouth, 'N0')
    S.pin(ellipse(w, h, cx, base - 64, 11, 7) & ~ellipse(w, h, cx, base - 64, 10, 6) & m, 'W0')
    for fx, fy, fr in ((cx - 18, base - 74, 7), (cx + 16, base - 58, 6), (cx - 14, base - 50, 5), (cx + 12, base - 88, 5)):
        shelf = ellipse(w, h, fx, fy, fr, fr * 0.45) & (yy <= fy)
        S.put(shelf, 'foam', 4.0, 0.05)
        S.pin(shelf & (yy == fy), 'P1')
    hollow = ellipse(w, h, cx, base - 7, 17, 10) & (yy <= base - 1)
    S.pin(hollow, 'N0')
    S.pin(ellipse(w, h, cx, base - 7, 13, 7) & (yy <= base - 1), 'N0')
    for k in range(7):
        sx = cx - 22 + k * 7 + r.integers(-1, 2)
        S.pin(line(w, h, [(sx, base - 18 - r.integers(0, 4)), (sx + 3, base - 10)], 1) & m & ~hollow, 'S2')
    return S, (cx, base), [(cx - 9, base - 104), (cx + 9, base - 106)]


def watching_tree(g, e, spec):
    """The Watching Tree at e['at']: huge sprite, trunk collision, blinking magenta eye lights, hollow glow."""
    x, y = e['at']
    S, piv, eyes = _watcher_sprite(e.get('seed', 17))
    g.add('dw_watcher', S, piv, x, y, shape=('rect', x - 30, y - 16, 60, 16))
    for k, (ex, ey) in enumerate(eyes):
        wx, wy = x - piv[0] + ex, y - piv[1] + ey
        g.light('point', wx, wy, MAGENTA, 0.9, 44, 18, flicker=0.95, phase=k * 0.2)
        g.emitter('halo', wx, wy, color=MAGENTA, size=12)
    g.light('point', x, y - 8, [255, 70, 90], 0.5, 60, 8, flicker=0.4)
    g.emitter('motes', x, y - 120, w=60, h=40, color=[255, 120, 220])


def _spire_sprite(seed, hgt):
    """Hollowmere Spire: stepped plinth, coursed tapering tower, parapet, drum, slate cone, gold finial, lit windows."""
    w, h = 110, hgt + 14
    cx, base = w / 2, h - 4
    S = Sprite(w, h)
    yy, xx = grid(h, w)
    nz = (value_noise(w, h, 3, seed) - 0.5) * 0.16
    course = ((yy % 7) == 0)
    joint = (((xx + (yy // 7 % 2) * 5).astype(int) % 10) == 0)
    stone_det = nz - course * 0.13 - joint * 0.08 - 0.08
    y_body0, y_body1 = base - 14, base - 14 - int(hgt * 0.6)
    y_drum = y_body1 - 12
    y_cone = y_drum - 44
    apex = base - hgt + 10
    for hw, y0, y1 in ((42, base - 6, base), (36, base - 14, base - 6)):
        st = (np.abs(xx - cx) <= hw) & (yy >= y0) & (yy <= y1)
        S.put(st, 'stone', _cyl(xx, cx, hw, 5) + (y1 - yy) * 0.3, nz - 0.04)
        S.pin(st & (yy == y0), 'N3')
    t = np.clip((y_body0 - yy) / (y_body0 - y_body1), 0, 1)
    half = 30 - 6 * t
    body = (np.abs(xx - cx) <= half) & (yy <= y_body0) & (yy >= y_body1)
    S.put(body, 'stone', _cyl(xx, cx, half, 9), stone_det)
    corb = (np.abs(xx - cx) <= 26 + (y_body1 - yy + 6) * 0.8) & (yy <= y_body1 + 6) & (yy >= y_body1)
    S.put(corb, 'stone', _cyl(xx, cx, 31, 9) + 1, stone_det)
    par = (np.abs(xx - cx) <= 31) & (yy < y_body1) & (yy >= y_drum)
    merlon = ((xx.astype(int) - int(cx) + 31) % 8 < 5) | (yy >= y_drum + 5)
    S.put(par & merlon, 'stone', _cyl(xx, cx, 31, 10) + 1.5, stone_det + 0.04)
    drum = (np.abs(xx - cx) <= 19) & (yy < y_drum + 5) & (yy >= y_cone)
    S.put(drum, 'stone', _cyl(xx, cx, 19, 7), stone_det)
    tc = np.clip((yy - apex) / max(y_cone - apex, 1), 0, 1)
    chalf = 25 * tc ** 0.9
    cone = (np.abs(xx - cx) <= chalf) & (yy >= apex) & (yy <= y_cone + 3)
    slate = ((yy % 4) == 0) & cone
    S.put(cone, 'rune', _cyl(xx, cx, np.maximum(chalf, 1), 8) + (y_cone - yy) * 0.04, nz - slate * 0.14)
    S.pin(cone & (yy == y_cone + 3), 'V0')
    S.put((np.abs(xx - cx) <= 0.6) & (yy >= apex - 9) & (yy < apex), 'gold', 3.0, 0.2)
    orb = ellipse(w, h, cx, apex - 10, 2, 2)
    S.put(orb, 'gold', 4.0, 0.3)
    S.pin(orb, 'G2')
    S.glow(orb, (255, 200, 110), 0.4)
    ivy = body & (np.abs(xx - (cx - 18 + np.sin(yy * 0.09) * 5)) < 3 + value_noise(w, h, 3, seed + 3) * 4) & (yy > y_body0 - 150)
    S.put(ivy & (value_noise(w, h, 2, seed + 4) > 0.4), 'moss', S.hgt + 0.5, 0.0)
    S.put(body & (yy > y_body0 - 26 - value_noise(w, h, 4, seed + 5) * 18) & (value_noise(w, h, 2, seed + 6) > 0.5),
          'moss', S.hgt + 0.3, 0.02)
    lights = []

    def window(wx, wy, wh, pal_out, pal_in, rgb, k):
        win = ((np.abs(xx - wx) <= 1.6) & (yy >= wy - wh) & (yy <= wy)) | ellipse(w, h, wx, wy - wh, 1.6, 1.6)
        S.pin(win, pal_out)
        S.pin(win & (yy >= wy - wh + 2) & (np.abs(xx - wx) <= 0.6), pal_in)
        S.glow(win, rgb, k)
        S.pin((yy == wy + 1) & (np.abs(xx - wx) <= 2.5), 'N1')
        lights.append((wx, wy - wh / 2))

    for k, frac in enumerate((0.18, 0.36, 0.55, 0.74, 0.9)):
        wy = int(y_body0 - (y_body0 - y_body1) * frac)
        window(cx + (-9 if k % 2 else 8), wy, 7, 'G1', 'G3', (255, 186, 96), 0.75)
    for dx in (-9, 0, 9):
        window(cx + dx, y_drum - 12, 9, 'M2', 'M3', (255, 80, 200), 1.0)
    door = (((np.abs(xx - cx) <= 6) & (yy >= base - 30) & (yy <= base - 14)) | ellipse(w, h, cx, base - 30, 6, 5)) & (yy <= base - 14)
    S.pin(door, 'N0')
    S.pin(door & (yy >= base - 18), 'G1')
    S.glow(door & (yy >= base - 20), (255, 170, 80), 0.5)
    S.pin(((((np.abs(xx - cx) <= 8) & (yy >= base - 30)) | ellipse(w, h, cx, base - 30, 8, 7)) & ~door & (yy <= base - 14)), 'N2')
    return S, (int(cx), base), lights, (cx, y_drum - 16)


def hollowmere_spire(g, e, spec):
    """A spire at e['at'], e['height'] px tall: plinth collision, gold window lights, beacon (e['beacon'], magenta), door light."""
    x, y = e['at']
    S, piv, wins, beacon = _spire_sprite(e.get('seed', 23), e.get('height', 340))
    g.add(e.get('name', 'dw_spire'), S, piv, x, y, shape=('rect', x - 40, y - 14, 80, 14))
    ox, oy = x - piv[0], y - piv[1]
    for wx, wy in wins[:5:2]:
        g.light('point', ox + wx, oy + wy, WARM, 0.6, 50, 30, flicker=0.2)
    bx, by = ox + beacon[0], oy + beacon[1]
    col = e.get('beacon', MAGENTA)
    g.light('point', bx, by, col, 1.4, 180, 60, flicker=0.12)
    g.emitter('halo', bx, by, color=col, size=46)
    g.emitter('motes', bx, by - 30, w=24, h=40, color=[min(255, c + 60) for c in col])
    g.light('point', x, y - 14, [255, 170, 80], 1.1, 80, 16, flicker=0.25)


def crimson_runestone(g, e, spec):
    """The Crimson Runestone: a dark basalt rune_stone with red sigils, red light pool, and glowing veins in the soil."""
    x, y = e['at']
    S, piv = props.rune_stone(e.get('seed', 6), hgt=e.get('height', 66), wd=e.get('width', 24))
    S.det[S.mat >= 0] -= 0.2
    glyph = S.fix == I['M2']
    S.fix[glyph] = I['R2']
    S.emi[:] = 0
    S.glow(glyph, CRIMSON, 1.0)
    g.add('dw_runestone', S, piv, x, y, shape=('rect', x - 13, y - 6, 26, 8))
    g.light('point', x, y - e.get('height', 66) * 0.6, CRIMSON, 1.0, 76, 22, flicker=0.3)
    g.light('point', x, y + 4, [220, 40, 60], 0.7, 140, 8, flicker=0.2)
    g.emitter('motes', x, y - 30, w=16, h=24, color=[255, 90, 90])
    w, h = 300, 180
    cx, cy = w // 2, h // 2
    V = Sprite(w, h)
    yy, xx = grid(h, w)
    r = rng(e.get('seed', 6) + 40)
    veins = np.zeros((h, w), bool)
    for k in range(11):
        a = k / 11 * 2 * math.pi + r.uniform(-0.2, 0.2)
        px, py, pts = cx + math.cos(a) * 10, cy + math.sin(a) * 5, []
        for _ in range(int(r.uniform(7, 13))):
            pts.append((px, py))
            a += r.uniform(-0.55, 0.55)
            px, py = px + math.cos(a) * 9, py + math.sin(a) * 5
        veins |= line(w, h, pts, 1)
        if len(pts) > 4:
            bx, by = pts[len(pts) // 2]
            veins |= line(w, h, [(bx, by), (bx + r.uniform(-14, 14), by + r.uniform(-8, 8))], 1)
    veins &= ~ellipse(w, h, cx, cy, 10, 5)
    V.put(veins, 'red', 0.5, 0.0)
    V.pin(veins, 'R1')
    core = veins & (np.hypot((xx - cx) / 1.0, (yy - cy) * 1.8) < 60)
    V.pin(core, 'R2')
    V.glow(veins, (255, 50, 60), 0.35)
    V.glow(core, (255, 60, 70), 0.4)
    g.add('dw_veins', V, (cx, cy), x, y - 2, layer='bridge')


def red_mushrooms(g, e, spec):
    """Glowing red mushroom clusters at e['pts'] near the root hollow, each with a small red light."""
    for k, (x, y) in enumerate(e['pts']):
        g.add(f'dw_redcap{k}', flora.mushrooms(70 + k, n=5, mat_cap='red'), (14, 18), x, y)
        g.light('point', x, y - 6, [255, 70, 80], 0.45, 50, 30, flicker=0.3, phase=k * 0.7)


def forest(g, e, spec):
    """Pooled T715 pixel-foliage (world_foliage pool: one atlas per preset, variant and size bucket); canopy AO shade."""
    pool = world_foliage.pool(g.out)
    cols = ([120, 255, 210], [190, 130, 255])
    W, H = spec['size']
    ao = np.zeros((H, W), np.float32)
    for k, it in enumerate(e['items']):
        p, (x, y), v, s = it['p'], it['at'], it['v'], it['s']
        layer = it.get('layer', 'ysort')
        shape = tuple(it['shape']) if it.get('shape') else None
        pool.place(g, f'dw_{p}{k}', p, v, s, x, y, shape=shape, layer=layer)
        if it.get('emit'):
            g.emitter(it['emit'], x, y - 90 * s / 1.25, w=40 * s, h=14 * s)
        if p == 'glowflora' and k % 2 == 0:
            g.light('point', x, y - 8, cols[k % 4 // 2], 0.4, 46, 20, flicker=0.25, phase=k * 0.9 % 9)
        if p in ('oak', 'willow', 'conifer') and layer != 'fg':
            rad = (52 if p != 'conifer' else 30) * s
            x0, x1 = max(0, int(x - rad)), min(W, int(x + rad + 16))
            y0, y1 = max(0, int(y - rad * 0.8)), min(H, int(y + rad * 0.5))
            if x1 > x0 and y1 > y0:
                yy, xx = np.mgrid[y0:y1, x0:x1]
                ao[y0:y1, x0:x1] += np.clip(1 - np.hypot((xx - x - 8) / rad, (yy - y + 6) / (rad * 0.7)), 0, 1) ** 1.3
    a = (np.clip(ao, 0, 1.2) / 1.2 * e.get('ao', 0.5) * 255).astype(np.uint8)
    rgba = np.zeros((H, W, 4), np.uint8)
    rgba[..., :3] = (6, 7, 26)
    rgba[..., 3] = a
    g.image('dw_canopy_ao', Image.fromarray(rgba, 'RGBA'), 0, 0, 'shade')
    print(f'FOREST items {len(e["items"])} variants {len(pool.plants)}')


def _bare_trunk(seed, hgt):
    """Tall dead boundary trunk, bark stripped in pale vertical lines on its east face."""
    r = rng(seed)
    w, h = 30, hgt + 6
    cx, base = 15, h - 3
    pts = [(cx + r.uniform(-1, 1), base)]
    for k in range(1, 6):
        pts.append((cx + r.uniform(-3, 3), base - hgt * k / 5))
    m = np.zeros((h, w), bool)
    yy, xx = grid(h, w)
    for (x0, y0), (x1, y1) in zip(pts[:-1], pts[1:]):
        wd = int(9 - 5 * (base - y0) / hgt)
        m |= line(w, h, [(x0, y0), (x1, y1)], max(wd, 3))
    m |= poly(w, h, [(cx - 9, base), (cx - 4, base - 10), (cx + 4, base - 10), (cx + 10, base)])
    for sgn in (-1, 1):
        yb = base - hgt * r.uniform(0.45, 0.75)
        m |= line(w, h, [(cx, yb), (cx + sgn * 10, yb), (cx + sgn * 10, yb - 14)], 2)
    S = Sprite(w, h)
    S.put(m, 'bark', dome(m, 3), (value_noise(w, h, 3, seed) - 0.5) * 0.16 - 0.14)
    strip = m & (xx >= cx + 1) & ((xx.astype(int) % 2) == 0) & (yy > base - hgt * 0.8) & (yy < base - 12)
    S.pin(strip & (value_noise(w, h, 2, seed + 1) > 0.3), 'P1')
    return S, (cx, base)


def boundary_dark(g, e, spec):
    """Boundary Dark: fog wall rising to the west edge (fog.png), stripped boundary trunks at e['trunks']."""
    x0, y0, x1, y1 = e['rect']
    depth = e.get('depth', 220)
    path = os.path.join(g.out, 'fog.png')
    fog = np.array(Image.open(path)).astype(np.float32) / 255
    H, W = fog.shape
    yy, xx = grid(H, W)
    ramp = np.clip(1 - (xx - x0) / depth, 0, 1) ** 1.4
    fade = np.clip((yy - y0) / 80, 0, 1) * np.clip((y1 - yy) / 120, 0, 1)
    fog = np.maximum(fog, ramp * fade * e.get('density', 1.0) + value_noise(W, H, 40, 77) * 0.25 * ramp * fade)
    Image.fromarray((np.clip(fog, 0, 1) * 255).astype(np.uint8), 'L').save(path)
    vw, vh = depth + 40, y1 - y0
    vy, vx = grid(vh, vw)
    vr = np.clip(1 - vx / depth, 0, 1) ** 1.2
    va = (vr * 1.1 + (value_noise(vw, vh, 18, 91) - 0.5) * 0.4 * vr) * np.clip(vy / 80, 0, 1) * np.clip((vh - vy) / 140, 0, 1)
    va = np.floor(np.clip(va, 0, 0.94) * 6 + BAYER[vy.astype(int) % 4, vx.astype(int) % 4] - 0.5).clip(0, 6) / 6 * 0.94
    veil = np.zeros((vh, vw, 4), np.uint8)
    veil[..., :3] = (6, 7, 26)
    veil[..., 3] = (va * 255).astype(np.uint8)
    g.image('dw_boundary_veil', Image.fromarray(veil, 'RGBA'), x0, y0, 'fg', sort=y1)
    for k, (x, y, hgt) in enumerate(e['trunks']):
        S, piv = _bare_trunk(80 + k, hgt)
        g.add(f'dw_bare{k}', S, piv, x, y, shape=('rect', x - 5, y - 4, 10, 5))


def bare_trunks(g, e, spec):
    """Stripped dead trunks at e['trunks'] [[x, y, height], ...] (Bone Orchard), each with a faint pale wisp light."""
    for k, (x, y, hgt) in enumerate(e['trunks']):
        S, piv = _bare_trunk(200 + k, hgt)
        g.add(f'dw_orchard{k}', S, piv, x, y, shape=('rect', x - 5, y - 4, 10, 5))
        if k % 3 == 0:
            g.light('point', x, y - hgt * 0.6, [190, 210, 255], 0.35, 60, 30, flicker=0.3, phase=k * 0.8)


def blackwater(g, e, spec):
    """Blackwater Pool: a slow green pulse deep below, iridescent vapour over the centre (its mist is in the fog map)."""
    x, y = e['at']
    g.light('point', x, y, [70, 255, 140], 0.7, 90, 4, flicker=0.7)
    g.emitter('motes', x, y - 6, w=40, h=10, color=[170, 150, 255])


def mist(g, e, spec):
    """Ground mist banks at e['pts'] [[x, y, w], ...]: soft noisy ellipses (w wide, w/3 tall) added to fog.png density."""
    path = os.path.join(g.out, 'fog.png')
    fog = np.array(Image.open(path)).astype(np.float32) / 255
    H, W = fog.shape
    for k, (x, y, w) in enumerate(e['pts']):
        rx, ry = w * 0.6, w * 0.22 + 14
        x0, x1, y0, y1 = max(0, int(x - rx)), min(W, int(x + rx)), max(0, int(y - ry)), min(H, int(y + ry))
        if x1 <= x0 or y1 <= y0:
            continue
        yy, xx = grid(y1 - y0, x1 - x0)
        r = np.hypot((xx + x0 - x) / rx, (yy + y0 - y) / ry)
        bank = np.clip(1 - r, 0, 1) ** 0.8 * (0.6 + 0.6 * value_noise(x1 - x0, y1 - y0, 24, 300 + k))
        fog[y0:y1, x0:x1] = np.maximum(fog[y0:y1, x0:x1], bank * e.get('density', 0.75))
    Image.fromarray((np.clip(fog, 0, 1) * 255).astype(np.uint8), 'L').save(path)


def _rings(mask, n):
    """Steps (alternating 4- and 8-neighbour dilations, about Euclidean) from `mask` out to n; n + 1 beyond, 0 inside."""
    d = np.full(mask.shape, n + 1, np.int16)
    d[mask] = 0
    cur = mask.copy()
    for k in range(1, n + 1):
        nxt = cur.copy()
        nxt[1:] |= cur[:-1]
        nxt[:-1] |= cur[1:]
        nxt[:, 1:] |= cur[:, :-1]
        nxt[:, :-1] |= cur[:, 1:]
        if k % 2 == 0:
            nxt[1:, 1:] |= cur[:-1, :-1]
            nxt[1:, :-1] |= cur[:-1, 1:]
            nxt[:-1, 1:] |= cur[1:, :-1]
            nxt[:-1, :-1] |= cur[1:, 1:]
        d[nxt & ~cur] = k
        cur = nxt
    return d


def _shore(g, box, pond, water, seed):
    """Shore band painted into ground.png / _n / _e: wet mud at the waterline, pebbles and rocks on a bank that slopes
    up to an overhanging grass lip, about 12 px wide round the pool and narrowing to 4 px along the streams."""
    x0, y0, x1, y1 = box
    w, h = x1 - x0, y1 - y0
    d = _rings(water, 16).astype(np.float32)
    near_pool = _rings(pond, 48).astype(np.float32)
    pool_k = np.clip(1 - near_pool / 44, 0, 1)
    width = 4 + pool_k * (7 + (value_noise(w, h, 22, seed) - 0.5) * 10) + (value_noise(w, h, 5, seed + 4) - 0.5) * 3
    band = ~water & (d <= width)
    t = np.clip(d / np.maximum(width, 1), 0, 1)
    S = Sprite(w, h)
    S.put(band, 'mud', d * 0.35, 0.0 + t * 0.1 + (value_noise(w, h, 2, seed + 1) - 0.5) * 0.14)
    S.put(band & (d <= 2), 'mud', 0.0, -0.16 + (value_noise(w, h, 3, seed + 2) - 0.5) * 0.08)
    S.put(band & (d <= 1), 'water', 0.0, 0.08)
    lip = band & (d > width - 2 - (value_noise(w, h, 3, seed + 5) > 0.62) * 2)
    S.put(lip, 'moss', width * 0.35 + 1.2, 0.04 + (value_noise(w, h, 2, seed + 6) - 0.5) * 0.12)
    S.put(band & (d > width - 4) & ~lip, 'mud', width * 0.3, -0.34)
    r = rng(seed + 3)
    yy, xx = grid(h, w)
    cand = np.argwhere(band & (d >= 2) & (d < width - 3))
    for k in r.choice(len(cand), min(len(cand), len(cand) // 16), replace=False):
        cy, cx = cand[k]
        big = r.random() < 0.12
        rx = r.uniform(2.5, 4.5) if big else r.uniform(0.8, 1.8)
        x_0, x_1, y_0, y_1 = max(0, int(cx - rx - 1)), min(w, int(cx + rx + 2)), max(0, int(cy - rx)), min(h, int(cy + rx + 1))
        m = np.zeros((h, w), bool)
        m[y_0:y_1, x_0:x_1] = (((xx[y_0:y_1, x_0:x_1] - cx) / rx) ** 2 + ((yy[y_0:y_1, x_0:x_1] - cy) / (rx * 0.7)) ** 2) <= 1
        S.put(m, 'stone', dome(m, rx) + d * 0.35 + 0.5, r.uniform(-0.02, 0.16))
    prefix = os.path.join(g.out, 'dw_shore')
    S.save(prefix, outline=False, band=0.5, dith=0.55, cluster=True)
    for name, src, fill in (('ground.png', 'dw_shore.png', None), ('ground_n.png', 'dw_shore_n.png', None),
                            ('ground_e.png', None, 0)):
        path = os.path.join(g.out, name)
        if not os.path.isfile(path):
            continue
        dst = np.array(Image.open(path))
        if src:
            patch = np.array(Image.open(os.path.join(g.out, src)).convert(Image.open(path).mode))
            dst[y0:y1, x0:x1][band] = patch[band]
        else:
            dst[y0:y1, x0:x1][band] = fill
        Image.fromarray(dst).save(path)
    for f in ('dw_shore.png', 'dw_shore_n.png', 'dw_shore_e.png'):
        if os.path.isfile(os.path.join(g.out, f)):
            os.remove(os.path.join(g.out, f))
    return d


def _pads(g, box, pond_in, seed):
    """Lily pad clusters on the open water (drawn in the bridge layer, above the water shader), some with a pale bloom."""
    x0, y0 = box[:2]
    r = rng(seed)
    cand = np.argwhere(pond_in)
    for k in range(7):
        cy, cx = cand[r.integers(len(cand))]
        S = Sprite(28, 16)
        yy, xx = grid(16, 28)
        for j in range(r.integers(2, 5)):
            px, py, rx = r.uniform(6, 22), r.uniform(5, 11), r.uniform(3.0, 5.0)
            m = ((xx - px) / rx) ** 2 + ((yy - py) / (rx * 0.6)) ** 2 <= 1
            ang = r.uniform(0, 2 * math.pi)
            notch = (np.cos(np.arctan2(yy - py, xx - px) - ang) > 0.93)
            m &= ~notch
            S.put(m, 'leaf', dome(m, 1.2) + 0.4, r.uniform(-0.18, -0.02), mode='max')
            if r.random() < 0.35:
                b = (np.abs(xx - px) <= 0.6) & (np.abs(yy - py + 1) <= 0.6)
                S.put(b, 'flowerm', 2.0, 0.1)
                S.glow(b, (255, 150, 220), 0.5)
        if S.alpha.any():
            g.add(f'dw_pad{k}', S, (14, 8), x0 + cx, y0 + cy, layer='bridge')


def _mirror(g, box, pond_in, items, spec):
    """Trees, shrubs and reeds round the pool flipped about their feet, cut to the still water: dw_pool_mirror.png,
    read by the water shader (node layer `mirror`)."""
    x0, y0, x1, y1 = box
    w, h = x1 - x0, y1 - y0
    canvas = Image.new('RGBA', (w, h))
    pool = world_foliage.pool(g.out)
    for it in sorted(items, key=lambda i: i['at'][1]):
        stem, (_, _, piv) = pool.get(it['p'], it['v'], it['s'])
        meta = json.load(open(os.path.join(g.out, stem + '.json')))
        im = Image.open(os.path.join(g.out, meta['files']['day'])).convert('RGBA').transpose(Image.FLIP_TOP_BOTTOM)
        X, Y = it['at']
        px, py = int(X - piv[0] - x0), int(Y + piv[1] - (im.height - 1) - y0)
        if -px < im.width and -py < im.height and px < w and py < h:
            canvas.alpha_composite(im.crop((max(0, -px), max(0, -py), im.width, im.height)), (max(px, 0), max(py, 0)))
    a = np.array(canvas)
    a[..., 3] = np.where(pond_in, a[..., 3], 0)
    Image.fromarray(a).save(os.path.join(g.out, 'dw_pool_mirror.png'))
    g.nodes.append(dict(name='dw_pool_mirror', files={'albedo': 'dw_pool_mirror.png'}, x=x0, y=y0, w=w, h=h,
                        layer='mirror', sort=-900))


def blackwater_shore(g, e, spec):
    """Blackwater Pool to the T704 bar: a real shore, reed clumps and lily pads, and the trees mirrored in the water."""
    x0, y0, x1, y1 = e['box']
    w, h = x1 - x0, y1 - y0
    water = np.array(Image.open(os.path.join(g.out, 'water.png')))[y0:y1, x0:x1, 3] > 127
    pond = poly(w, h, [(x - x0, y - y0) for x, y in spec['water']['ponds'][0]])
    d = _shore(g, e['box'], pond, water, 7140)
    pool = world_foliage.pool(g.out)
    r = rng(7141)
    reeds = []
    ring = np.argwhere(~water & (d >= 3) & (d <= 5) & (_rings(pond, 20) <= 8))
    for k in range(e.get('reeds', 14)):
        cy, cx = ring[r.integers(len(ring))]
        it = {'p': 'reed', 'at': [int(x0 + cx), int(y0 + cy)], 'v': int(r.integers(4)), 's': 1.0}
        pool.place(g, f'dw_reed{k}', 'reed', it['v'], 1.0, *it['at'])
        reeds.append(it)
    inside = _rings(~pond, 14)
    _pads(g, e['box'], inside > 10, 7142)
    pond_in = inside > 2
    _mirror(g, e['box'], pond_in, e['items'] + reeds, spec)
    print(f'SHORE band px {int((~water & (d <= 13)).sum())} reeds {len(reeds)} mirror items {len(e["items"]) + len(reeds)}')
