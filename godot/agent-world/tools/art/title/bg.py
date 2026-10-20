#!/usr/bin/env python3
"""Distant planes: two mountain ranges, Hollowmere Spire on its cliff, far-shore pines, mid shores."""
import math

import numpy as np

from px import (W, H, PAD, LW, Layer, hexc, fbm, line1, ramp, mix, poly, ellipse, lines, edge, dist_in)

HY = 214                       # waterline (screen y)
MOON = (452, 86, 24)           # screen x, y, radius
C = {k: hexc(v) for k, v in dict(
    n0='06071a', n1='0c1028', n2='131a3c', n3='1b2550', n4='253265', n5='32447c', n6='435a94', n7='5a76ac',
    n8='7894c4', n9='9db5da', n10='c8dbf0', n11='f2f6ff', v0='1d1335', v1='2c1b4f', v2='41286b', v3='5c3889',
    v4='7e52ac', v5='a77ad0', v6='d0a8ee', m0='5e1a5e', m1='9c2c7c', m2='de4f9e', m3='ff9ccc', g1='b8862e',
    g2='f2c45a', g3='fff2b0', t0='0a1f2c', t1='0f3140', t2='14464f', t3='1b5e60', t5='379a83', t6='5ec29c',
    t7='a4f0cc', b0='22303a', b1='3a4a52', w0='2e1c22', w1='4f3028', w2='7a4c34', f2='ff8a3a', e0='15291f',
    e1='24452e', e2='3a6a3a', f1='c0501e', r0='4c1631', t4='257a70', g0='6e4a1c').items()}


def moon_dir(x, y):
    """Unit vector from a screen point toward the moon."""
    dx, dy = MOON[0] - x, MOON[1] - y
    d = math.hypot(dx, dy) or 1
    return dx / d, dy / d


def rim(mask, toward=None, steps=1):
    """Silhouette pixels facing the moon (per-pixel direction), up to `steps` deep."""
    hh, ww = mask.shape
    yy, xx = np.mgrid[0:hh, 0:ww].astype(np.float32)
    dx, dy = MOON[0] + PAD - xx, MOON[1] - yy
    d = np.hypot(dx, dy) + 1e-3
    out = np.zeros_like(mask)
    for s in range(1, steps + 1):
        sx = np.clip(np.round(xx + dx / d * s * 1.0).astype(int), 0, ww - 1)
        sy = np.clip(np.round(yy + dy / d * s * 1.0).astype(int), 0, hh - 1)
        out |= mask & ~mask[sy, sx]
    return out


def peak_range(lay, peaks, cols_lit, cols_dark, snow_lit, snow_dark, seed, haze=None):
    """Peaks back to front: jagged silhouettes, lit side faces the moon, gullies and snow."""
    rnd = np.random.default_rng(seed)
    hh, ww = lay.h, lay.w
    yy, xx = np.mgrid[0:hh, 0:ww].astype(np.float32)
    gul = fbm(ww, hh, 4, 16, seed + 7, 3)
    rid = 1 - np.abs(2 * fbm(ww, hh, 16, 10, seed + 5, 4) - 1)
    fgx = np.gradient(rid, axis=1) * 14
    gul2 = fbm(ww, hh, 8, 3, seed + 9, 3)
    for i, (px, py, hw_l, hw_r, base) in enumerate(peaks):
        px += PAD
        n1 = (line1(ww, 16, seed + i * 13, 4) - 0.5) * 18 + (line1(ww, 4, seed + i * 17, 2) - 0.5) * 5
        sl = np.where(xx < px, (px - xx) / hw_l, (xx - px) / hw_r)
        top = py + (base - py) * sl ** 0.8
        top = top + n1[None, :] * np.clip(np.abs(xx - px) / 10, 0, 1)
        m = (yy >= top) & (yy <= HY + 1) & (xx > px - hw_l * 1.3) & (xx < px + hw_r * 1.3)
        lit_right = (MOON[0] + PAD) > px
        split = px + (yy - py) * (0.35 if lit_right else -0.35) + (line1(hh, 6, seed + i * 7, 3)[:, None] * 10 - 5)
        lit = (xx > split) if lit_right else (xx < split)
        # facets: secondary ridges as diagonal streaks
        fsgn = 1 if lit_right else -1
        v_l = 0.6 + (gul - 0.5) * 0.35 + fgx * fsgn * 0.7 + (rid - 0.5) * 0.25 - (yy - py) / max(1, base - py) * 0.35
        v_d = 0.30 + (gul2 - 0.5) * 0.5 + fgx * fsgn * 0.5 - (yy - py) / max(1, base - py) * 0.25
        rf, crest, crease = spurs(px, py, hw_l, hw_r, base, top, xx, yy, 1 if lit_right else -1, rnd, seed + i * 31)
        v_l = v_l + rf * 0.2
        v_d = v_d + rf * 0.15
        rgb_l = ramp(np.clip(v_l, 0, 1), cols_lit, 0.3)
        rgb_d = ramp(np.clip(v_d, 0, 1), cols_dark, 0.3)
        snowline = py + (base - py) * (0.28 + rnd.uniform(0, 0.12)) + (gul - 0.5) * 18
        sn = yy < snowline
        rgb = np.where(lit[..., None], rgb_l, rgb_d)
        rgb = np.where((sn & lit & (gul > 0.38))[..., None], ramp(np.clip(gul, 0, 1), snow_lit, 0.5), rgb)
        rgb = np.where((sn & ~lit & (gul2 > 0.45))[..., None], ramp(np.clip(gul2, 0, 1), snow_dark, 0.5), rgb)
        upper = yy < py + (base - py) * 0.75
        main = (edge(lit, -1 if lit_right else 1, 0) | edge(lit, 0, -1)) & upper & (yy > py + 2)
        rgb = np.where(((crest & upper) | main)[..., None] & lit[..., None], cols_lit[-1], rgb)
        rgb = np.where((crest & upper & ~lit)[..., None], cols_dark[-1], rgb)
        thr = 0.3 + (gul - 0.5) * 0.3
        rgb = np.where((lit & (rf > thr))[..., None], cols_lit[-2], rgb)
        rgb = np.where((lit & (rf < -thr))[..., None], cols_lit[0], rgb)
        rgb = np.where((~lit & (rf > thr))[..., None], cols_dark[-1], rgb)
        rgb = np.where((~lit & (rf < -thr))[..., None], cols_dark[0], rgb)
        rgb = np.where((crease & upper)[..., None], cols_dark[0], rgb)
        streak = (crest | (rf > 0.45)) & (yy < snowline + 14) & (rf >= 0)
        rgb = np.where((streak & lit)[..., None], snow_lit[-2], rgb)
        rgb = np.where((streak & ~lit & (rf > 0.3))[..., None], snow_dark[-1], rgb)
        lay.put(m, rgb)
        r = rim(m, steps=1) & lit
        lay.rgb[r] = snow_lit[-1]
    if haze is not None:
        col, y0, y1, amt = haze
        t = np.clip((yy - y0) / (y1 - y0), 0, 1) * amt
        lay.rgb = mix(lay.rgb, col, t[..., None])


def spurs(px, py, hw_l, hw_r, base, top, xx, yy, lit_sign, rnd, seed):
    """Spur ridges running down from the crest: signed face light (+ toward the moon) and the 1 px crest line."""
    hh, ww = xx.shape
    best = np.full((hh, ww), 9.0, np.float32)
    rf = np.zeros((hh, ww), np.float32)
    crest = np.zeros((hh, ww), bool)
    jit = line1(hh, 5, seed, 3)
    for j in range(int(rnd.integers(4, 7))):
        u = rnd.uniform(-0.55, 0.55)
        xs = px + u * (hw_r if u > 0 else hw_l)
        xi = int(np.clip(xs, 0, ww - 1))
        ys = float(top[0, xi]) + 2 if np.ndim(top) == 2 else py
        if ys >= base - 8:
            continue
        slope = np.sign(u) * rnd.uniform(0.3, 0.8) + rnd.uniform(-0.1, 0.1)
        dy = np.clip(yy - ys, 0, None)
        rx = xs + dy * slope + (np.roll(jit, j * 37)[:, None] - 0.5) * np.clip(dy / 30, 0, 1) * 8
        wid = np.clip(4 + dy * 0.35, 4, 18)
        dx = xx - rx
        n = np.abs(dx) / wid
        on = (yy > ys) & (n < 1) & (n < best)
        best[on] = n[on]
        rf[on] = (np.sign(dx) * lit_sign * (1 - n))[on]
        crest |= (yy > ys) & (np.abs(dx) < 0.6)
    crease = (rf < -0.75)
    return rf, crest, crease


def mountains():
    far = Layer()
    peaks = [(-10, 130, 60, 70, 214), (120, 120, 80, 60, 214), (232, 96, 90, 110, 214), (360, 132, 70, 60, 214),
             (590, 100, 100, 80, 214), (690, 124, 60, 60, 214)]
    peak_range(far, peaks, [C['v3'], C['v4'], C['v5'], C['v6']], [C['v1'], C['v2'], C['v3']],
               [C['n8'], C['n9'], C['n10'], C['n11']], [C['v4'], C['v5']], 11, (C['v3'] * 0.6 + C['n5'] * 0.4, 100, 214, 0.6))
    far.save('mtn_far')
    near = Layer()
    peaks = [(60, 156, 90, 60, 214), (172, 166, 60, 50, 214), (318, 150, 80, 60, 214), (560, 160, 70, 60, 214),
             (650, 148, 70, 80, 214)]
    peak_range(near, peaks, [C['n4'], C['n5'], C['n6'], C['n7']], [C['v0'], C['v1'], C['n3']],
               [C['n7'], C['n8'], C['n9']], [C['n5'], C['n6']], 23, (C['v2'] * 0.5 + C['n3'] * 0.5, 150, 214, 0.55))
    near.save('mtn_near')


def window(lay, x, y, w=1, h=2, col='g2', arch=False):
    x += PAD
    lay.rgb[y:y + h, x:x + w] = C[col]
    lay.a[y:y + h, x:x + w] = 1
    lay.emit[y:y + h, x:x + w] = C[col] * 1.0
    if arch and w >= 2:
        lay.rgb[y, x:x + w] = C['g1']


def castle():
    """Hollowmere Spire: backlit castle on a sea cliff, gold windows, magenta crystal at the needle."""
    L = Layer()
    hh, ww = L.h, L.w
    yy, xx = np.mgrid[0:hh, 0:ww].astype(np.float32)
    P = PAD
    # cliff
    nc = line1(ww, 6, 71, 5)
    top = np.full(ww, 999.0)
    for x in range(ww):
        sx = x - P
        if 372 <= sx <= 552:
            if sx < 404:
                t = 214 - (sx - 372) / 32 * 40
            elif sx <= 520:
                t = 172 + abs(math.sin(sx * 0.21)) * 2
            else:
                t = 172 + (sx - 520) / 32 * 42
            top[x] = t + (nc[x] - 0.5) * 7
    cliff = yy >= top[None, :]
    cliff &= yy <= HY + 2
    tex = fbm(ww, hh, 6, 4, 77, 4)
    strata = (np.sin(yy * 0.9 + tex * 6) > 0.6)
    v = 0.35 + (tex - 0.5) * 0.8 - (yy - 172) / 60 * 0.25 + strata * 0.12
    L.put(cliff, ramp(np.clip(v, 0, 1), [C['n1'], C['n2'], C['n3'], C['b0'], C['n4']], 0.7))
    L.rgb[rim(cliff, steps=2)] = C['n7']
    L.rgb[rim(cliff, steps=1)] = C['n8']

    def block(x0, y0, x1, y1, base='n2', face='n3'):
        m = (xx >= x0 + P) & (xx < x1 + P) & (yy >= y0) & (yy < y1)
        stone = fbm(ww, hh, 3, 2, 91, 2)
        rgb = ramp(np.clip(0.4 + (stone - 0.5) * 0.9 + (xx - (x0 + P)) / max(1, x1 - x0) * 0.25, 0, 1),
                   [C['v0'], C[base], C[face], C['n4']], 0.6)
        L.put(m, rgb)
        return m

    def roof(cx, y_base, hw, h, col='v1'):
        m = poly(ww, hh, [(cx + P - hw - 1, y_base), (cx + P, y_base - h), (cx + P + hw + 1, y_base)])
        sh = (xx - (cx + P)) / max(1, hw)
        L.put(m, ramp(np.clip(0.5 + sh * 0.4 + (yy - (y_base - h)) / h * 0.15, 0, 1), [C['v0'], C[col], C['v2'], C['v3']], 0.5))
        return m

    def crenels(x0, x1, y):
        for x in range(x0, x1, 3):
            block(x, y - 2, x + 2, y)

    sil = np.zeros((hh, ww), bool)
    # curtain wall + towers
    sil |= block(414, 158, 516, 176)
    crenels(414, 516, 158)
    sil |= block(408, 126, 424, 176)
    sil |= roof(416, 126, 9, 18)
    sil |= block(506, 134, 520, 176)
    sil |= roof(513, 134, 8, 16)
    # keep with buttresses
    sil |= block(434, 112, 494, 160)
    crenels(434, 494, 112)
    sil |= roof(446, 112, 9, 14)
    sil |= roof(482, 112, 9, 12)
    # spire tower + needle crossing the moon
    sil |= block(452, 70, 466, 114)
    sil |= block(449, 70, 469, 74, 'n3', 'n4')
    sil |= roof(459, 70, 8, 30, 'v1')
    sil |= lines(ww, hh, [(459 + P, 40), (459 + P, 30)], 1)
    L.put(lines(ww, hh, [(459 + P, 40), (459 + P, 30)], 1), C['n6'])
    # small watchtower on a sea stack, bridged
    stack = poly(ww, hh, [(366 + P, HY + 2), (368 + P, 176), (374 + P, 168), (382 + P, 172), (384 + P, HY + 2)])
    L.put(stack, ramp(np.clip(0.35 + (tex - 0.5) * 0.8, 0, 1), [C['n1'], C['n2'], C['n3'], C['b0']], 0.7))
    sil |= stack
    sil |= block(369, 146, 380, 170)
    sil |= roof(374, 146, 7, 14)
    br = lines(ww, hh, [(380 + P, 160), (392 + P, 156), (408 + P, 158)], 2)
    L.put(br, C['n2'])
    sil |= br
    L.put(br & ~lines(ww, hh, [(381 + P, 160), (392 + P, 157), (407 + P, 159)], 1), C['n1'])
    # moon rim on the whole silhouette
    r1 = rim(sil, steps=1)
    L.rgb[rim(sil, steps=2) & ~r1] = mix(L.rgb[rim(sil, steps=2) & ~r1], C['n6'], 0.6)
    L.rgb[r1] = C['n9']
    # windows
    for x, y in [(412, 136), (418, 136), (412, 148), (418, 150), (510, 144), (514, 152), (374, 152), (376, 160)]:
        window(L, x, y, 1, 2)
    for x in (440, 448, 456, 470, 478, 486):
        window(L, x, 122, 2, 3, arch=True)
    for x in (444, 462, 482):
        window(L, x, 136, 2, 4, 'g3', arch=True)
    window(L, 456, 82, 2, 4, 'g3', True)
    window(L, 460, 96, 2, 3, 'g2', True)
    for x in range(418, 512, 9):
        window(L, x, 166, 1, 2, 'g1')
    # rose window on keep
    rw = ellipse(ww, hh, (463 + P - 4, 142, 463 + P + 4, 150))
    L.rgb[rw] = C['m2']
    L.emit[rw] = C['m2']
    L.rgb[ellipse(ww, hh, (463 + P - 1, 145, 463 + P + 1, 147))] = C['m3']
    L.emit[ellipse(ww, hh, (463 + P - 1, 145, 463 + P + 1, 147))] = C['m3']
    # crystal at the needle base
    cr = poly(ww, hh, [(459 + P, 58), (462 + P, 63), (459 + P, 68), (456 + P, 63)])
    L.put(cr, C['m2'])
    L.emit[cr] = C['m3']
    L.rgb[poly(ww, hh, [(459 + P, 59), (460 + P, 63), (459 + P, 66), (458 + P, 63)])] = C['m3']
    L.save('castle')


def pine(mask_w, mask_h, cx, base, height, halfw, rnd):
    """Fir: drooping serrated tiers, slight lean."""
    from px import poly as P
    m = np.zeros((mask_h, mask_w), bool)
    tiers = max(4, int(height // 6))
    lean = rnd.uniform(-0.06, 0.06)
    for k in range(tiers):
        f = (k + 1) / tiers
        y = base - height + height * 0.92 * f
        x = cx + lean * (base - y)
        wk = halfw * (0.15 + 0.85 * f ** 0.9) * rnd.uniform(0.85, 1.15)
        th = height * 0.92 / tiers * 1.7
        pts = [(x, y - th), (x + wk * 0.45, y - th * 0.4), (x + wk, y + rnd.uniform(0, 2.5)),
               (x + wk * 0.7, y - 0.5), (x + wk * 0.45, y + 1.2), (x, y), (x - wk * 0.45, y + 1.2),
               (x - wk * 0.7, y - 0.5), (x - wk, y + rnd.uniform(0, 2.5)), (x - wk * 0.45, y - th * 0.4)]
        m |= P(mask_w, mask_h, pts)
    tx = cx + lean * height
    m |= P(mask_w, mask_h, [(tx, base - height - 3), (tx + 1, base - height + 3), (tx - 1, base - height + 3)])
    m[int(base - 3):int(base + 2), int(cx - 1):int(cx + 2)] = True
    return m


def pine_row(name, xs_n, base_fn, hmin, hmax, dark, lit, rim_col, seed, haze=None, mist_y=None, extra=None):
    rnd = np.random.default_rng(seed)
    L = Layer()
    xs = np.sort(rnd.uniform(-10, LW + 10, xs_n))
    tex = fbm(LW, H, 2, 2, seed + 3, 2)
    for x in xs:
        hgt = rnd.uniform(hmin, hmax)
        b = base_fn(x) + rnd.uniform(-2, 2)
        m = pine(LW, H, x, b, hgt, hgt * rnd.uniform(0.26, 0.34), np.random.default_rng(abs(int(x * 31)) + seed))
        # inner shading: lighter toward moon side
        md = 1 if (MOON[0] + PAD) > x else -1
        yy, xx = np.mgrid[0:H, 0:LW]
        side = np.clip((xx - x) * md / (hgt * 0.3) * 0.5 + 0.5, 0, 1)
        v = 0.25 + side * 0.35 + (tex - 0.5) * 0.5 - np.clip((yy - (b - hgt)) / hgt, 0, 1) * 0.25
        L.put(m, ramp(np.clip(v, 0, 1), dark, 0.7))
        r = rim(m, steps=1)
        L.rgb[r] = rim_col
        r2 = rim(m, steps=2) & ~r
        L.rgb[r2] = mix(L.rgb[r2], lit, 0.7)
    if extra:
        extra(L)
    if haze is not None:
        col, y0, y1, amt = haze
        yy = np.mgrid[0:H, 0:LW][0]
        L.rgb = mix(L.rgb, col, (np.clip((yy - y0) / (y1 - y0), 0, 1) * amt)[..., None])
    L.save(name)


def forests():
    pine_row('pines_far', 140, lambda x: HY + 1, 8, 22, [C['n1'], C['n2'], C['v1'], C['n3']], C['n5'], C['n7'], 31,
             (C['v2'] * 0.5 + C['n4'] * 0.5, 196, 216, 0.55))
    # left mid shore: dense pines rising from a bank, low enough to keep the logo sky open
    def bank_left(x):
        sx = x - PAD
        return 246 + max(0, sx - 180) * 0.25 + math.sin(sx * 0.05) * 3

    def left_extra(L):
        yy, xx = np.mgrid[0:H, 0:LW].astype(np.float32)
        sx = xx - PAD
        top = 238 + np.clip(sx - 150, 0, None) * 0.18 + np.sin(sx * 0.07) * 2
        m = (yy >= top) & (sx < 300) & (yy < 300)
        tex = fbm(LW, H, 4, 2, 5, 3)
        L.put(m & (L.a == 0) | m, ramp(np.clip(0.3 + (tex - 0.5) * 0.7 - (yy - top) / 50, 0, 1),
                                       [C['n0'], C['n1'], C['n2'], C['b0']], 0.7))
        L.rgb[edge(m, 0, -1)] = C['n5']

    _pines_side('pines_left', 0, 270, bank_left, 22, 36, 92, 41, None)

    def bank_right(x):
        sx = x - PAD
        return 262 - max(0, sx - 470) * 0.1

    _pines_side('pines_right', 610, 700, bank_right, 6, 70, 120, 43, None)


def _pines_side(name, x0, x1, base_fn, n, hmin, hmax, seed, extra):
    rnd = np.random.default_rng(seed)
    L = Layer()
    xs = np.sort(rnd.uniform(x0, x1, n)) + PAD
    tex = fbm(LW, H, 2, 2, seed + 3, 2)
    yy, xx = np.mgrid[0:H, 0:LW]
    # taller at the outer edge, shorter toward the lake
    for x in xs:
        sx = x - PAD
        edge_f = 1 - min(1, abs(sx - (x0 if x0 == 0 else x1)) / max(1, (x1 - x0)))
        hgt = hmin + (hmax - hmin) * (0.35 + 0.65 * edge_f) * rnd.uniform(0.75, 1.1)
        b = base_fn(x) + rnd.uniform(-2, 3)
        m = pine(LW, H, x, b, hgt, hgt * rnd.uniform(0.24, 0.31), np.random.default_rng(int(x * 17) + seed))
        md = 1 if (MOON[0] + PAD) > x else -1
        side = np.clip((xx - x) * md / (hgt * 0.3) * 0.5 + 0.5, 0, 1)
        tier = (np.sin((yy - b) * 1.1) > 0.55) * 0.12
        v = 0.2 + side * 0.32 + (tex - 0.5) * 0.5 + tier - np.clip((yy - (b - hgt)) / hgt, 0, 1) * 0.2
        L.put(m, ramp(np.clip(v, 0, 1), [C['n0'], C['n1'], C['n2'], C['v1'], C['n3'], C['n4']], 0.7))
        r = rim(m, steps=1)
        L.rgb[r] = C['n8']
        r2 = rim(m, steps=2) & ~r
        L.rgb[r2] = mix(L.rgb[r2], C['n6'], 0.8)
    if extra:
        extra(L)
    L.save(name)


if __name__ == '__main__':
    mountains()
    castle()
    forests()
