#!/usr/bin/env python3
"""Near planes: shores, standing stones + campfire spot, framing oak and lantern tree, canopy, grass; normal + sway maps."""
import json
import math
import os

import numpy as np
from PIL import Image

from px import (W, H, PAD, LW, OUT, BAYER, Layer, fbm, line1, ramp, mix, poly, ellipse, lines, edge, dist_in)
from bg import C, MOON, HY, rim

YY, XX = np.mgrid[0:H, 0:LW].astype(np.float32)
SX = XX - PAD
FIRE = (560, 284)
LANTERN = (598, 176)


def dilate(a, r):
    out = a.copy()
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            out = np.maximum(out, np.roll(np.roll(a, dy, 0), dx, 1))
    return out


def save_weight(name, w, ph):
    """Sway weight (R) and phase (G), dilated so displaced pixels keep their weight."""
    wd, pd = dilate(w, 3), dilate(ph * (w > 0), 3)
    img = np.dstack([wd * 255, pd * 255, np.zeros_like(wd), np.full_like(wd, 255)]).astype(np.uint8)
    Image.fromarray(img, 'RGBA').save(os.path.join(OUT, name + '_w.png'))


def cyl(mask, axis_x, half):
    """Cylinder height across a vertical-ish trunk."""
    return np.sqrt(np.clip(1 - ((SX - axis_x) / np.maximum(half, 1)) ** 2, 0, 1)) * mask


def tube(points, widths):
    """Union of discs along a polyline with tapering widths (screen coords) -> mask and axis distance height."""
    m = np.zeros((H, LW), bool)
    hgt = np.zeros((H, LW), np.float32)
    for (x0, y0), (x1, y1), w0, w1 in zip(points[:-1], points[1:], widths[:-1], widths[1:]):
        n = int(max(abs(x1 - x0), abs(y1 - y0))) + 1
        for i in range(n):
            t = i / max(1, n - 1)
            x, y, w = x0 + (x1 - x0) * t + PAD, y0 + (y1 - y0) * t, w0 + (w1 - w0) * t
            r = w / 2
            ys, ye = int(max(0, y - r - 1)), int(min(H, y + r + 2))
            xs, xe = int(max(0, x - r - 1)), int(min(LW, x + r + 2))
            d = np.hypot(XX[ys:ye, xs:xe] - x, YY[ys:ye, xs:xe] - y)
            inside = d <= r
            m[ys:ye, xs:xe] |= inside
            hgt[ys:ye, xs:xe] = np.maximum(hgt[ys:ye, xs:xe], np.sqrt(np.clip(1 - (d / max(r, 0.5)) ** 2, 0, 1)) * r * 0.5 * inside)
    return m, hgt


def bezier(p0, p1, p2, n=24):
    return [((1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * p1[0] + t * t * p2[0],
             (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * p1[1] + t * t * p2[1]) for t in np.linspace(0, 1, n)]


def bark(L, m, hgt, light_x=1.0, base='wood'):
    """Bark: vertical furrows, side light toward +x (moon/fire), moss on tops."""
    bump = fbm(LW, H, 2, 5, 311, 2)
    m = (m | (np.roll(m, 1, 1) & (bump > 0.62)) | (np.roll(m, -1, 1) & (bump > 0.62))) & ~(edge(m, 1, 0) & (bump < 0.35)) & ~(edge(m, -1, 0) & (bump < 0.35))
    fur = fbm(LW, H, 2, 12, 301, 3)
    knot = fbm(LW, H, 10, 10, 303, 2)
    gy, gx = np.gradient(hgt)
    lit = np.clip(0.5 + gx * light_x * 0.9 - gy * 0.3, 0, 1)
    v = 0.22 + lit * 0.5 + (fur - 0.5) * 0.55 + (knot - 0.5) * 0.15
    cols = [C['n0'], C['v0'], C['w0'], C['n2'], C['w1'], C['n4'], C['n6']]
    rgb = ramp(np.clip(v, 0, 1), cols, 0.6)
    moss = (fbm(LW, H, 5, 3, 307, 3) > 0.62) & (gy < 0.1)
    rgb = np.where(moss[..., None], ramp(np.clip(v + 0.1, 0, 1), [C['t0'], C['t1'], C['t2'], C['t3']], 0.6), rgb)
    L.put(m, rgb, hgt + (fur - 0.5) * 1.5)
    r = rim(m, steps=1)
    brk = fbm(LW, H, 2, 6, 309, 2)
    L.rgb[r & (brk > 0.45)] = C['n7']
    L.rgb[r & (brk <= 0.45)] = C['n5']
    r2 = rim(m, steps=3) & ~r & (brk > 0.55)
    L.rgb[r2] = mix(L.rgb[r2], C['n6'], 0.6)


def leaf_cluster(L, cx, cy, rx, ry, rnd, wmap, pmap, wgt, dark=False):
    """A cluster of lit leaf puffs: back puffs darker, each puff domed, serrated edges, moon rim."""
    phase = rnd.random()
    puffs = []
    for i in range(int(rx * ry / 18) + 4):
        a = rnd.uniform(0, 2 * math.pi)
        rr = math.sqrt(rnd.random())
        puffs.append((cx + math.cos(a) * rx * rr, cy + math.sin(a) * ry * rr, rnd.uniform(3.5, 7.5)))
    puffs.sort(key=lambda p: p[1] - p[0] * 0.3)
    allm = np.zeros((H, LW), bool)
    cols = np.array([C['n0'], C['t0'], C['e0'], C['t1'], C['e1'], C['t2'], C['t3']], np.float32)
    for k, (x, y, r) in enumerate(puffs):
        x += PAD
        ys, ye = int(max(0, y - r - 2)), int(min(H, y + r + 2))
        xs, xe = int(max(0, x - r - 2)), int(min(LW, x + r + 2))
        if ys >= ye or xs >= xe:
            continue
        yy, xx = YY[ys:ye, xs:xe], XX[ys:ye, xs:xe]
        d = np.hypot((xx - x) / r, (yy - y) / (r * 0.8))
        m = d <= 1.0
        lr = np.random.default_rng(int(abs(x * 7 + y * 13)))
        bot = m & ~np.pad(m, ((0, 1), (0, 0)))[1:]
        m &= ~(bot & (lr.random(m.shape) > 0.55))
        topm = m & ~np.pad(m, ((1, 0), (0, 0)))[:-1]
        tips = np.roll(topm & (lr.random(m.shape) > 0.6), -1, 0)
        m |= tips
        dome = np.sqrt(np.clip(1 - d * d, 0, 1))
        toward = ((xx - x) * 0.6 - (yy - y) * 0.8) / r
        depth = k / max(1, len(puffs) - 1)
        v = 0.12 + dome * 0.18 + np.clip(toward, -1, 1) * 0.22 + depth * 0.18 - (0.12 if dark else 0)
        q = np.clip(v, 0, 0.999) * len(cols) + (BAYER[yy.astype(int) % 4, xx.astype(int) % 4] - 0.5) * 0.7
        rgb = cols[np.clip(q.astype(int), 0, len(cols) - 1)]
        sub = (slice(ys, ye), slice(xs, xe))
        L.rgb[sub][m] = rgb[m]
        L.a[sub][m] = 1
        L.hgt[sub][m] = (dome * r * 0.5 + 3)[m]
        allm[sub] |= m
        wmap[sub][m] = wgt
        pmap[sub][m] = phase
    r1 = rim(allm, steps=1)
    L.rgb[r1] = mix(L.rgb[r1], C['t5'], 0.8)
    r2 = rim(allm, steps=2) & ~r1
    L.rgb[r2] = mix(L.rgb[r2], C['t3'], 0.5)
    return allm


def shore():
    L = Layer()
    tex = fbm(LW, H, 4, 3, 401, 4)
    # left bank under the left pines, shelving into the lake with rocks
    top_l = 240 + np.clip(SX - 150, 0, None) * 0.2 + np.sin(SX * 0.07) * 2 + (line1(LW, 6, 402)[None, :] - 0.5) * 4
    ml = (YY >= top_l) & (SX < 250 - (YY - 240) * 1.4) & (YY < 330)
    v = 0.32 + (tex - 0.5) * 0.7 - (YY - top_l) / 70
    L.put(ml, ramp(np.clip(v, 0, 1), [C['n0'], C['n1'], C['v0'], C['n2'], C['e0'], C['b0']], 0.7), (tex * 2))
    L.rgb[edge(ml, 0, -1)] = C['n5']
    L.rgb[rim(ml, steps=1) & ~edge(ml, 0, -1)] = C['n4']
    # right promontory: plateau seen from 3/4, cliff face to the water
    top_r = 262 - np.clip(SX - 470, 0, None) * 0.12 + (line1(LW, 5, 403)[None, :] - 0.5) * 5
    lip = 298 + (line1(LW, 4, 404)[None, :] - 0.5) * 6
    mr = (YY >= top_r) & (SX > 455 + (YY - 262) * -0.4) & (YY < 318)
    plateau = mr & (YY < lip)
    face = mr & (YY >= lip)
    pv = 0.42 + (tex - 0.5) * 0.6 - (YY - top_r) / 120
    L.put(plateau, ramp(np.clip(pv, 0, 1), [C['n1'], C['e0'], C['t0'], C['e1'], C['t1'], C['e2']], 0.7), tex * 2 + 2)
    strata = np.sin(YY * 1.3 + fbm(LW, H, 6, 3, 405, 3) * 7) > 0.5
    fv = 0.3 + (tex - 0.5) * 0.7 + strata * 0.12 - (YY - lip) / 40
    L.put(face, ramp(np.clip(fv, 0, 1), [C['n0'], C['n1'], C['n2'], C['b0'], C['n3'], C['b1']], 0.7), tex * 4 + strata)
    L.rgb[edge(mr, 0, -1)] = C['n6']
    L.rgb[edge(plateau, 0, 1) & ~edge(mr, 0, 1)] = C['b1']
    # waterline rocks with moon rims
    rnd = np.random.default_rng(406)
    for x, y, r in [(200, 280, 7), (214, 286, 5), (226, 274, 4), (455, 312, 6), (440, 316, 4), (150, 300, 9),
                    (238, 282, 3), (470, 305, 5)]:
        m = ellipse(LW, H, (x + PAD - r, y - r * 0.7, x + PAD + r, y + r * 0.5))
        dome = np.sqrt(np.clip(1 - ((XX - x - PAD) / r) ** 2 - ((YY - y) / (r * 0.7)) ** 2, 0, 1))
        L.put(m, ramp(np.clip(0.25 + dome * 0.3 + (XX - x - PAD) / r * 0.15, 0, 1), [C['n0'], C['n1'], C['n2'], C['b0'], C['n4']], 0.6), dome * r * 0.6)
        L.rgb[rim(m, steps=1)] = C['n7']
    # reeds on the left bank edge
    for i in range(40):
        x = rnd.uniform(120, 240)
        yb = 300 - (x - 120) * 0.45 + rnd.uniform(-6, 8)
        hgt = rnd.uniform(6, 16)
        m = lines(LW, H, [(x + PAD, yb), (x + PAD + rnd.uniform(-2, 2), yb - hgt)], 1)
        L.put(m, C['n1'])
        tip = m & edge(m, 0, -1)
        L.rgb[tip] = C['n5']
    L.save('shore', normal=True, lift=1.7)


def mid():
    """Standing stones with magenta runes, fire pit with logs, seat log and an empty bedroll (avatar spot)."""
    L = Layer()
    rnd = np.random.default_rng(501)
    gran = fbm(LW, H, 3, 4, 502, 3)
    stones = [(498, 270, 7, 46, -0.07), (522, 264, 9, 62, 0.02), (546, 268, 6, 40, 0.09), (482, 274, 6, 24, -0.18)]
    for i, (x, yb, hw, h, lean) in enumerate(stones):
        top = yb - h
        pts = [(x - hw, yb), (x - hw * 1.05 + lean * h * 0.5, yb - h * 0.5), (x - hw * 0.7 + lean * h, top + 9),
               (x - hw * 0.1 + lean * h, top), (x + hw * 0.35 + lean * h, top + 4), (x + hw * 0.9 + lean * h, top + 14),
               (x + hw * 1.1 + lean * h * 0.5, yb - h * 0.45), (x + hw, yb)]
        m = poly(LW, H, [(px + PAD, py) for px, py in pts])
        side = (XX - (x + PAD + lean * (YY - yb) * -1)) / hw
        hgt = np.sqrt(np.clip(1 - side ** 2, 0, 1)) * hw * 0.6
        v = 0.3 + side * 0.18 + (gran - 0.5) * 0.6 - (YY - top) / h * 0.1
        L.put(m, ramp(np.clip(v, 0, 1), [C['n1'], C['v0'], C['n2'], C['b0'], C['n4'], C['b1'], C['n6']], 0.7), hgt + gran * 2)
        L.rgb[rim(m, steps=1)] = C['n8']
        lichen = m & (fbm(LW, H, 3, 3, 510 + i, 2) > 0.64)
        L.rgb[lichen] = mix(L.rgb[lichen], C['t2'], 0.6)
        if i < 3:
            rx, ry = x + PAD + lean * h * 0.5, top + h * 0.35
            glyph = rnd.integers(0, 3)
            pts = [[(0, -6), (0, 6)], [(-3, -3), (3, 3)], [(-3, 3), (3, -3)]]
            for gi, seg in enumerate(pts[:2 + glyph % 2]):
                gm = lines(LW, H, [(rx + seg[0][0], ry + seg[0][1]), (rx + seg[1][0], ry + seg[1][1])], 1) & m
                L.rgb[gm] = C['m2']
                L.emit[gm] = C['m2'] * 0.9
            dot = ellipse(LW, H, (rx - 1, ry + 8, rx + 1, ry + 10)) & m
            L.rgb[dot] = C['m3']
            L.emit[dot] = C['m3']
    fx, fy = FIRE[0] + PAD, FIRE[1]
    # stone ring
    for k in range(9):
        a = k / 9 * 2 * math.pi
        x, y = fx + math.cos(a) * 11, fy + 2 + math.sin(a) * 4
        m = ellipse(LW, H, (x - 3, y - 2, x + 3, y + 2))
        dome = np.sqrt(np.clip(1 - ((XX - x) / 3) ** 2 - ((YY - y) / 2) ** 2, 0, 1))
        L.put(m, ramp(np.clip(0.3 + dome * 0.4 + (YY < y) * 0.1, 0, 1), [C['n1'], C['b0'], C['b1'], C['n6']], 0.5), dome * 2)
    for (x0, y0, x1, y1) in [(fx - 8, fy + 2, fx + 6, fy - 3), (fx + 8, fy + 2, fx - 5, fy - 4)]:
        m, hg = tube([(x0 - PAD, y0), (x1 - PAD, y1)], [3, 3])
        L.put(m, ramp(np.clip(0.3 + hg * 0.4, 0, 1), [C['w0'], C['w1'], C['w2']], 0.5), hg)
    coal = ellipse(LW, H, (fx - 5, fy - 1, fx + 5, fy + 3))
    L.put(coal, C['f1'])
    L.emit[coal] = C['f2'] * 0.8
    # seat log (avatar spot) and bedroll
    m, hg = tube([(FIRE[0] + 18, 292), (FIRE[0] + 42, 288)], [6, 6])
    lg = fbm(LW, H, 3, 1, 521, 2)
    L.put(m, ramp(np.clip(0.15 + hg * 0.18 + (lg - 0.5) * 0.5 + (YY < 289) * 0.08, 0, 1), [C['n0'], C['w0'], C['w0'], C['w1'], C['b0']], 0.6), hg)
    ring = ellipse(LW, H, (FIRE[0] + 40 + PAD, 285, FIRE[0] + 46 + PAD, 292))
    L.put(ring & m, C['w1'])
    bed = poly(LW, H, [(FIRE[0] - 40 + PAD, 292), (FIRE[0] - 18 + PAD, 290), (FIRE[0] - 16 + PAD, 296), (FIRE[0] - 42 + PAD, 298)])
    L.put(bed, ramp(np.clip(0.35 + (fbm(LW, H, 2, 2, 520, 1) - 0.5) * 0.5 - (YY - 290) / 12, 0, 1), [C['n1'], C['v0'], C['r0'], C['v1']], 0.5), 1.0)
    camp(L)
    L.save('mid', normal=True, lift=1.7)


def camp(L):
    """Camp dressing on the fire plateau: canvas tent with a lit doorway, banner pole with a lamp, woodpile."""
    P_ = PAD
    canvas = fbm(LW, H, 2, 3, 531, 2)
    side = poly(LW, H, [(579 + P_, 259), (602 + P_, 258), (609 + P_, 281), (590 + P_, 282)])
    L.put(side, ramp(np.clip(0.35 + (canvas - 0.5) * 0.5 - (YY - 258) / 50, 0, 1), [C['w0'], C['w1'], C['r0'], C['w1']], 0.6), 3)
    seams = side & (((XX - P_ - 579) - (YY - 259) * 0.45).astype(int) % 7 == 0)
    L.rgb[seams] = C['w0']
    front = poly(LW, H, [(566 + P_, 282), (579 + P_, 258), (591 + P_, 282)])
    L.put(front, ramp(np.clip(0.55 + (canvas - 0.5) * 0.4 - (XX - P_ - 566) / 40, 0, 1), [C['w1'], C['w2'], C['g0'], C['g1']], 0.6), 4)
    door = poly(LW, H, [(573 + P_, 282), (579 + P_, 268), (584 + P_, 282)])
    L.put(door, C['f1'], 2)
    L.emit[door] = C['f2'] * 0.55
    glow = poly(LW, H, [(576 + P_, 282), (579 + P_, 274), (581 + P_, 282)])
    L.rgb[glow] = C['g2']
    L.emit[glow] = C['g2'] * 0.7
    L.rgb[edge(side, 0, -1)] = C['n6']
    L.rgb[edge(front, -1, 0) & (YY < 270)] = C['g2']
    for a_, b_ in [((566, 282), (560, 290)), ((609, 281), (614, 288)), ((579, 258), (574, 253))]:
        L.put(lines(LW, H, [(a_[0] + P_, a_[1]), (b_[0] + P_, b_[1])], 1), C['n3'], 1)
    flag = poly(LW, H, [(574 + P_, 249), (574 + P_, 254), (581 + P_, 251)])
    L.put(lines(LW, H, [(574 + P_, 247), (574 + P_, 258)], 1), C['w0'], 2)
    L.put(flag, C['m2'], 2)
    L.emit[flag] = C['m2'] * 0.25
    # banner pole with a hanging lamp at the plateau's left lip
    bx = 466 + P_
    L.put(lines(LW, H, [(bx, 294), (bx, 240)], 2), C['w1'], 2)
    L.put(lines(LW, H, [(bx, 240), (bx + 10, 240)], 1), C['w0'], 2)
    ban = poly(LW, H, [(bx + 2, 242), (bx + 9, 242), (bx + 9, 258), (bx + 5.5, 254), (bx + 2, 258)])
    L.put(ban, ramp(np.clip(0.5 + (XX - bx - 5) / 10 + (canvas - 0.5) * 0.3, 0, 1), [C['v0'], C['v1'], C['v2'], C['v3']], 0.5), 2)
    L.rgb[ban & (YY == 244)] = C['g2']
    L.rgb[ban & (np.abs(XX - bx - 5.5) < 1) & (np.abs(YY - 249) < 2)] = C['g3']
    L.rgb[edge(ban, 1, 0)] = C['n6']
    lamp = poly(LW, H, [(bx - 3, 246), (bx - 1, 246), (bx - 1, 251), (bx - 3, 251)])
    L.put(lines(LW, H, [(bx - 2, 241), (bx - 2, 245)], 1), C['n3'], 2)
    L.put(lamp, C['g2'], 3)
    L.emit[lamp] = C['g2'] * 1.1
    # woodpile: stacked log ends
    for (x, y) in [(476, 293), (482, 293), (488, 293), (479, 288), (485, 288), (482, 283)]:
        end = ellipse(LW, H, (x + P_ - 3, y - 3, x + P_ + 3, y + 2))
        L.put(end, C['w1'], 2)
        ring = ellipse(LW, H, (x + P_ - 1, y - 1, x + P_ + 1, y + 1)) & end
        L.rgb[ring] = C['w2']
        L.rgb[edge(end, 0, -1)] = C['w2']
        L.rgb[edge(end, 0, 1)] = C['n0']


def foreground():
    L = Layer()
    G = Layer()
    wmap = np.zeros((H, LW), np.float32)
    pmap = np.zeros((H, LW), np.float32)
    rnd = np.random.default_rng(601)
    # ground strip
    gt = 322 + (line1(LW, 10, 602)[None, :] - 0.5) * 10 - np.clip(80 - SX, 0, None) * 0.25 - np.clip(SX - 560, 0, None) * 0.2
    gm = YY >= gt
    tex = fbm(LW, H, 3, 2, 603, 4)
    v = 0.3 + (tex - 0.5) * 0.7 - (YY - gt) / 60
    L.put(gm, ramp(np.clip(v, 0, 1), [C['n0'], C['v0'], C['n1'], C['e0'], C['t0'], C['e1']], 0.7), tex * 2)
    L.rgb[edge(gm, 0, -1)] = C['t3']
    # oak, left: trunk, roots, the arching branch
    tm, th = tube([(18, 370), (24, 300), (20, 220), (30, 150), (44, 90)], [74, 56, 44, 40, 30])
    rm = np.zeros_like(tm)
    rh = np.zeros_like(th)
    for pts, ws in [([(30, 344), (70, 352), (100, 366)], [16, 8, 3]), ([(40, 330), (80, 330), (112, 342)], [12, 6, 2]),
                    ([(10, 340), (-10, 350)], [14, 8])]:
        m, h = tube(pts, ws)
        rm |= m
        rh = np.maximum(rh, h)
    bm1, bh1 = tube(bezier((40, 100), (80, 10), (220, 12)), list(np.linspace(28, 9, 24)))
    bm2, bh2 = tube(bezier((150, 22), (210, 0), (290, 4)), list(np.linspace(9, 3, 24)))
    bm3, bh3 = tube(bezier((38, 120), (0, 70), (-20, 20)), list(np.linspace(22, 10, 24)))
    oak = tm | rm | bm1 | bm2 | bm3
    hgt = np.maximum.reduce([th, rh, bh1, bh2, bh3])
    bark(L, oak, hgt)
    # hollow knot glowing faintly
    kn = ellipse(LW, H, (36 + PAD, 228, 44 + PAD, 240))
    L.rgb[kn] = C['n0']
    # right tree with the lantern branch
    rt, rth = tube([(640, 370), (636, 280), (640, 160), (650, 40), (660, -10)], [60, 46, 40, 34, 30])
    rb, rbh = tube(bezier((626, 150), (600, 138), (586, 140)), list(np.linspace(12, 4, 24)))
    bark(L, rt | rb, np.maximum(rth, rbh), light_x=-0.6)
    # lantern: rope, cage, glass glow
    lx, ly = LANTERN
    L.put(lines(LW, H, [(lx + PAD, 142), (lx + PAD, ly - 8)], 1), C['n3'])
    cage = poly(LW, H, [(lx - 4 + PAD, ly - 6), (lx + 4 + PAD, ly - 6), (lx + 5 + PAD, ly + 6), (lx - 5 + PAD, ly + 6)])
    glass = poly(LW, H, [(lx - 3 + PAD, ly - 4), (lx + 3 + PAD, ly - 4), (lx + 4 + PAD, ly + 5), (lx - 4 + PAD, ly + 5)])
    L.put(cage, C['w0'], 3)
    L.put(glass, C['g2'], 3)
    L.emit[glass] = C['g2'] * 1.1
    core = ellipse(LW, H, (lx - 1 + PAD, ly - 1, lx + 1 + PAD, ly + 2))
    L.rgb[core] = C['g3']
    L.emit[core] = C['g3'] * 1.4
    L.put(poly(LW, H, [(lx - 6 + PAD, ly - 6), (lx + PAD, ly - 11), (lx + 6 + PAD, ly - 6)]), C['n1'], 4)
    L.put(lines(LW, H, [(lx - 5 + PAD, ly + 7), (lx + 5 + PAD, ly + 7)], 1), C['n1'], 3)
    L.save('fg', normal=True, lift=1.7)
    # canopy clusters along the branch and the corners
    F = Layer()
    for (cx, cy, rx, ry, w) in [(60, 10, 46, 22, 0.6), (130, 4, 40, 18, 0.8), (205, 14, 34, 16, 1.0), (262, 10, 24, 12, 1.0),
                                (8, 50, 30, 30, 0.5), (300, 4, 16, 8, 1.0), (176, 30, 18, 10, 1.0), (96, 36, 20, 12, 0.9)]:
        leaf_cluster(F, cx, cy, rx, ry, rnd, wmap, pmap, w)
    for (cx, cy, rx, ry, w) in [(632, 20, 34, 26, 0.6), (600, 60, 22, 14, 0.8), (582, 128, 14, 9, 1.0), (622, 98, 18, 14, 0.7)]:
        leaf_cluster(F, cx, cy, rx, ry, rnd, wmap, pmap, w, dark=True)
    # hanging moss strands
    for i in range(16):
        x = rnd.uniform(60, 270)
        y0 = 18 + (x - 60) * -0.02 + rnd.uniform(4, 16)
        ln = rnd.uniform(10, 34)
        pts = [(x + PAD + math.sin(k * 0.5) * 0.8, y0 + k) for k in range(int(ln))]
        m = lines(LW, H, pts, 1)
        F.put(m, np.where((YY > y0 + ln * 0.6)[..., None], C['t2'], C['t1']).reshape(H, LW, 3), 2)
        wmap[m] = np.clip((YY[m] - y0) / ln, 0.2, 1.0)
        pmap[m] = rnd.random()
        if rnd.random() < 0.35:
            tip = ellipse(LW, H, (x + PAD - 1, y0 + ln - 1, x + PAD + 1, y0 + ln + 1))
            F.rgb[tip] = C['t6']
            F.a[tip] = 1
            F.emit[tip] = C['t6'] * 0.8
            wmap[tip] = 1.0
    F.save('fg_leaves', normal=True, lift=1.7)
    save_weight('fg_leaves', wmap, pmap)
    # grass, ferns, mushrooms, flowers along the ground and the bottom edge
    wmap[:] = 0
    pmap[:] = 0
    gtop = gt[0]
    for i in range(520):
        x = rnd.uniform(0, LW)
        front = rnd.random() < 0.35
        yb = (360 + rnd.uniform(0, 6)) if front else gtop[int(x) % LW] + rnd.uniform(-1, 30)
        hgt = rnd.uniform(14, 34) if front else rnd.uniform(4, 13)
        bend = rnd.uniform(-5, 5)
        pts = [(x + bend * (k / 6) ** 2, yb - hgt * k / 6) for k in range(7)]
        m = lines(LW, H, pts, 2 if (front and rnd.random() < 0.5) else 1)
        col = C['n0'] if front else (C['e0'] if rnd.random() < 0.5 else C['t0'])
        G.put(m, col, 1)
        tipm = m & (YY < yb - hgt * 0.7)
        G.rgb[tipm & rim(m, steps=1)] = C['n5'] if front else C['t3']
        wmap[m] = np.clip((yb - YY[m]) / hgt, 0, 1)
        pmap[m] = (x * 0.013) % 1.0
    for i in range(14):
        x = rnd.uniform(60, 600)
        y = gtop[int(x + PAD) % LW] + rnd.uniform(4, 30)
        # fern: arcing fronds
        for s in (-1, 1):
            for k in range(3):
                ln = rnd.uniform(8, 14)
                pts = bezier((x, y), (x + s * ln * 0.5, y - ln * (0.9 - k * 0.2)), (x + s * ln, y - ln * (0.3 - k * 0.15)), 10)
                m = lines(LW, H, [(a + PAD, b) for a, b in pts], 1)
                G.put(m, C['e1'] if k else C['e2'], 1)
                wmap[m] = 0.6
                pmap[m] = rnd.random()
    for i in range(9):
        x = [70, 76, 82, 300, 306, 470, 478, 520, 600][i] + rnd.uniform(-3, 3)
        y = gtop[int(x + PAD) % LW] + rnd.uniform(2, 28)
        kind = rnd.random()
        if kind < 0.5:
            stem = lines(LW, H, [(x + PAD, y), (x + PAD, y - 3)], 1)
            G.put(stem, C['n6'], 1)
            cap = ellipse(LW, H, (x + PAD - 2, y - 5, x + PAD + 2, y - 2))
            G.put(cap, C['t6'], 2)
            G.emit[cap] = C['t6'] * 0.45
            G.rgb[ellipse(LW, H, (x + PAD - 1, y - 5, x + PAD, y - 4))] = C['t7']
        else:
            stem = lines(LW, H, [(x + PAD, y), (x + PAD + 1, y - 7)], 1)
            G.put(stem, C['e1'], 1)
            fl = ellipse(LW, H, (x + PAD - 1, y - 9, x + PAD + 2, y - 6))
            G.put(fl, C['m2'], 2)
            G.emit[fl] = C['m2'] * 0.3
            wmap[stem | fl] = 0.8
    G.save('fg_grass', normal=True, lift=1.7)
    save_weight('fg_grass', wmap, pmap)


def moon():
    r = MOON[2]
    s = 2 * r + 2
    L = Layer(s, s)
    yy, xx = np.mgrid[0:s, 0:s].astype(np.float32)
    d = np.hypot(xx - r - 0.5, yy - r - 0.5) / r
    m = d <= 1.0
    maria = fbm(s, s, 9, 9, 701, 3)
    v = 0.86 - d ** 4 * 0.22 + (maria - 0.5) * 0.28 - ((xx - r) * -0.3 + (yy - r) * 0.3) / r * 0.08
    rgb = ramp(np.clip(v, 0, 1), [C['n7'], C['n8'], C['n9'], C['n10'], C['n11']], 0.6)
    rnd = np.random.default_rng(702)
    for i in range(9):
        cx, cy, cr = rnd.uniform(6, s - 6), rnd.uniform(6, s - 6), rnd.uniform(1.5, 3.5)
        ring = (np.abs(np.hypot(xx - cx, yy - cy) - cr) < 0.7)
        rgb[ring & (yy < cy) & m] = C['n9']
        rgb[ring & (yy >= cy) & m] = C['n11']
    L.put(m, rgb)
    L.save('moon')
    # halo: smooth radial falloff (no dither) plus one crisp 1 px corona ring just outside the disc
    hs = 220
    yy, xx = np.mgrid[0:hs, 0:hs].astype(np.float32)
    rr = np.hypot(xx - hs / 2 + 0.5, yy - hs / 2 + 0.5)
    d = rr / (hs / 2)
    a = np.clip(1 - d, 0, 1) ** 2.6 * 0.6 + np.clip(1 - d * 3.2, 0, 1) ** 1.5 * 0.55
    a = np.where(np.abs(rr - (r + 3)) < 0.6, np.maximum(a, 0.5), a)
    img = np.dstack([np.full_like(a, 150), np.full_like(a, 170), np.full_like(a, 255), np.clip(a, 0, 1) * 255])
    from px import save_rgba
    save_rgba(img, 'moon_halo')


def boat():
    """Small moored boat with a lantern on its mast (bobs in Godot)."""
    L = Layer(30, 26)
    hull = poly(30, 26, [(2, 18), (28, 18), (24, 23), (6, 23)])
    yy, xx = np.mgrid[0:26, 0:30]
    L.put(hull, np.where((yy < 20)[..., None], C['w1'], C['w0']).reshape(26, 30, 3))
    L.rgb[(yy == 18) & hull] = C['w2']
    L.rgb[(yy == 18) & hull & (xx > 12)] = C['n6']
    mast = lines(30, 26, [(15, 18), (15, 3)], 1)
    L.put(mast, C['w0'])
    arm = lines(30, 26, [(15, 4), (20, 4)], 1)
    L.put(arm, C['w0'])
    lan = poly(30, 26, [(19, 6), (21, 6), (22, 10), (18, 10)])
    L.put(lan, C['g2'])
    L.emit[lan] = C['g2'] * 1.2
    L.rgb[poly(30, 26, [(19, 7), (21, 7), (21, 9), (19, 9)])] = C['g3']
    L.save('boat')


def pool(name, rx, ry, col, alpha):
    """Dithered additive light pool (ellipse) at base resolution."""
    w, h = 2 * rx, 2 * ry
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    d = np.hypot((xx - rx) / rx, (yy - ry) / ry)
    a = np.clip(1 - d, 0, 1) ** 1.8 * alpha
    a = np.floor(a * 12 + BAYER[yy.astype(int) % 4, xx.astype(int) % 4]) / 12
    from px import save_rgba
    save_rgba(np.dstack([np.full_like(a, col[0]), np.full_like(a, col[1]), np.full_like(a, col[2]), np.clip(a, 0, 1) * 255]), name)


def lights():
    boat()
    pool('pool_fire', 70, 26, (255, 150, 70), 0.75)
    pool('pool_boat', 6, 30, (255, 190, 110), 0.5)
    pool('pool_lantern', 46, 46, (255, 190, 110), 0.5)
    pool('pool_stone', 30, 30, (222, 79, 158), 0.3)
    meta = [
        {"x": FIRE[0], "y": FIRE[1] - 6, "radius": 150, "energy": 4.0, "z": 30, "color": [255, 150, 70], "depth": 0.55, "seed": 1},
        {"x": LANTERN[0], "y": LANTERN[1], "radius": 110, "energy": 2.6, "z": 26, "color": [255, 196, 110], "depth": 1.0, "seed": 2},
        {"x": 522, "y": 240, "radius": 50, "energy": 1.6, "z": 12, "color": [222, 79, 158], "depth": 0.55, "seed": 3},
        {"x": 464, "y": 249, "radius": 44, "energy": 1.3, "z": 14, "color": [255, 190, 110], "depth": 0.55, "seed": 5},
        {"x": 300, "y": 338, "radius": 80, "energy": 1.0, "z": 18, "color": [94, 194, 156], "depth": 1.0, "seed": 4},
    ]
    with open(os.path.join(OUT, 'lights.json'), 'w') as f:
        json.dump(meta, f)


if __name__ == '__main__':
    moon()
    shore()
    mid()
    foreground()
    lights()
