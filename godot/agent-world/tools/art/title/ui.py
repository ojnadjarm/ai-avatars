#!/usr/bin/env python3
"""Menu art: hand-built gold logo letterforms with bevel/outline/glow backing, subtitle divider, 9-slice panel, selection bar and keycap."""
import numpy as np
from PIL import Image, ImageDraw

from px import BAYER, save_rgba, edge
from bg import C

LH = 40
# Display capitals on a 40 px body: (width, outline polygon, counter polygons), 8 px stems, chamfered corners.
GLYPHS = {
    'A': (30, [(0, 40), (11, 0), (19, 0), (30, 40), (22, 40), (20, 32), (10, 32), (8, 40)], [[(15, 14), (12, 26), (18, 26)]]),
    'V': (30, [(0, 0), (8, 0), (15, 29), (22, 0), (30, 0), (19, 40), (11, 40)], []),
    'I': (16, [(0, 0), (16, 0), (16, 7), (12, 7), (12, 33), (16, 33), (16, 40), (0, 40), (0, 33), (4, 33), (4, 7), (0, 7)], []),
    'T': (28, [(0, 0), (28, 0), (28, 12), (25, 8), (18, 8), (18, 40), (10, 40), (10, 8), (3, 8), (0, 12)], []),
    'R': (28, [(0, 0), (22, 0), (28, 6), (28, 17), (24, 21), (28, 27), (28, 40), (20, 40), (20, 30), (16, 25), (8, 25), (8, 40), (0, 40)],
          [[(8, 7), (18, 7), (20, 9), (20, 15), (18, 17), (8, 17)]]),
    'S': (27, [(6, 0), (27, 0), (27, 8), (10, 8), (8, 10), (8, 14), (10, 16), (21, 16), (27, 22), (27, 34), (21, 40), (0, 40),
               (0, 32), (17, 32), (19, 30), (19, 26), (17, 24), (6, 24), (0, 18), (0, 6)], []),
}
KERN = {'AV': -4, 'VA': -4, 'TA': -3, 'AT': -3}
# 5 px small capitals for the subtitle.
SMALL = {
    'W': ['X...X', 'X...X', 'X.X.X', 'XX.XX', 'X...X'], 'H': ['X..X', 'X..X', 'XXXX', 'X..X', 'X..X'],
    'E': ['XXXX', 'X...', 'XXX.', 'X...', 'XXXX'], 'R': ['XXX.', 'X..X', 'XXX.', 'X.X.', 'X..X'],
    'T': ['XXX', '.X.', '.X.', '.X.', '.X.'], 'A': ['.XX.', 'X..X', 'XXXX', 'X..X', 'X..X'],
    'G': ['.XXX', 'X...', 'X.XX', 'X..X', '.XXX'], 'N': ['X..X', 'XX.X', 'X.XX', 'X..X', 'X..X'],
    'S': ['.XXX', 'X...', '.XX.', '...X', 'XXX.'], 'D': ['XXX.', 'X..X', 'X..X', 'X..X', 'XXX.'],
}


def glyph_mask(ch):
    w, outline, counters = GLYPHS[ch]
    im = Image.new('L', (w, LH), 0)
    d = ImageDraw.Draw(im)
    d.polygon(outline, fill=255)
    for c in counters:
        d.polygon(c, fill=0)
    return np.array(im) > 127


def word_mask(s, spacing=3, space=12):
    """Lays out the display capitals with pair kerning; returns the letter mask and the I-stem centres."""
    x, parts, stems = 0, [], []
    for i, ch in enumerate(s):
        if ch == ' ':
            x += space
            continue
        x += KERN.get(s[i - 1:i + 1], 0) if i else 0
        parts.append((x, glyph_mask(ch)))
        if ch == 'I':
            stems.append(x + 8)
        x += GLYPHS[ch][0] + spacing
    m = np.zeros((LH, x - spacing), bool)
    for ox, g in parts:
        m[:, ox:ox + g.shape[1]] |= g
    return m, stems


def small_mask(s, spacing=2, space=4):
    cols = []
    for ch in s:
        if ch == ' ':
            cols.append(np.zeros((5, space), bool))
            continue
        cols.append(np.array([[c == 'X' for c in row] for row in SMALL[ch]]))
        cols.append(np.zeros((5, spacing), bool))
    return np.hstack(cols[:-1])


def grow(m, r=1):
    p = np.pad(m, r)
    out = np.zeros_like(p)
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            if abs(dx) + abs(dy) <= r:
                out |= np.roll(np.roll(p, dy, 0), dx, 1)
    return out


def logo():
    m, stems = word_mask('AI AVATARS')
    h, w = m.shape
    P = 6
    M = np.pad(m, ((P, P + 4), (P, P)))
    H, W = M.shape
    rgb = np.zeros((H, W, 3), np.float32)
    a = np.zeros((H, W), np.float32)
    yy, xx = np.mgrid[0:H, 0:W]
    t = (yy - P) / h
    # metal gradient: bright cap, horizon line, warm body, deep base
    cols = np.where((t < 0.2)[..., None], C['g3'],
            np.where((t < 0.47)[..., None], C['g2'],
            np.where((t < 0.53)[..., None], C['g3'],
            np.where((t < 0.82)[..., None], C['g1'], C['g0']))))
    rgb[M] = cols[M]
    a[M] = 1
    top = edge(M, 0, -1)
    rgb[top] = C['n11']
    bot = edge(M, 0, 1)
    rgb[bot] = C['g1'] * 0.7
    left = edge(M, -1, 0) & ~top
    rgb[left] = np.minimum(rgb[left] * 1.15, 255)
    top2 = edge(M & ~top, 0, -1) & ~left
    rgb[top2] = C['g3']
    right = edge(M, 1, 0) & ~top & ~bot
    rgb[right] = C['g1']
    # magenta gem set in each I stem
    for sx in stems:
        cx, cy = sx + P, P + LH // 2
        for dy in range(-3, 4):
            for dx in range(-3 + abs(dy), 4 - abs(dy)):
                k = abs(dx) + abs(dy)
                c = 'm3' if (dx, dy) in ((0, -1), (-1, -1), (0, -2)) else ('v0' if k == 3 else ('m0' if dy > 0 and k == 2 else 'm2' if k < 2 else 'm1'))
                rgb[cy + dy, cx + dx] = C[c]
    # bronze extrusion under the face
    B = M.copy()
    for k in range(1, 5):
        e = np.roll(M, k, 0) & ~B
        rgb[e] = C['g0'] if k < 3 else C['w1']
        rgb[e & edge(np.roll(M, k, 0), -1, 0)] = C['g1'] * 0.8
        a[e] = 1
        B |= e
    o1 = grow(B, 1)[1:-1, 1:-1] & ~B
    rgb[o1] = C['v0']
    a[o1] = 1
    o2 = grow(B, 2)[2:-2, 2:-2] & ~B & ~o1
    rgb[o2] = C['m0']
    a[o2] = 1
    sh = np.roll(B | o1 | o2, 3, 0) & ~(B | o1 | o2)
    rgb[sh] = C['n0']
    a[sh] = 0.85
    save_rgba(np.dstack([rgb, a * 255]), 'logo')
    # shimmer mask = letter fill only
    save_rgba(np.dstack([np.full((H, W, 3), 255.0), M * 255.0]), 'logo_mask')
    # glow backing: wide dithered magenta/violet aura
    G = 18
    Mg = np.pad(M, G).astype(np.float32)
    k = Mg.copy()
    for _ in range(G):
        k = np.maximum(k, (np.roll(k, 1, 0) + np.roll(k, -1, 0) + np.roll(k, 1, 1) + np.roll(k, -1, 1)) * 0.25 * 0.96)
    y2, x2 = np.mgrid[0:k.shape[0], 0:k.shape[1]]
    q = np.floor(k ** 1.4 * 10 + BAYER[y2 % 4, x2 % 4]) / 10
    col = np.dstack([np.full_like(q, 222), np.full_like(q, 79), np.full_like(q, 158)])
    save_rgba(np.dstack([col, np.clip(q, 0, 1) * 200]), 'logo_glow')
    # subtitle
    s = small_mask('WHERE THE AGENTS WANDER')
    sh_, sw_ = s.shape
    Wd = sw_ + 80
    Hd = 13
    rgb = np.zeros((Hd, Wd, 3), np.float32)
    a = np.zeros((Hd, Wd), np.float32)
    ox, oy = 40, 3
    shd = np.zeros((Hd, Wd), bool)
    shd[oy + 1:oy + sh_ + 1, ox:ox + sw_] = s
    txt = np.zeros((Hd, Wd), bool)
    txt[oy:oy + sh_, ox:ox + sw_] = s
    rgb[shd & ~txt] = C['v0']
    a[shd & ~txt] = 1
    rgb[txt] = C['n10']
    a[txt] = 1
    cy = oy + sh_ // 2
    for x0, x1, d in [(2, ox - 6, 1), (ox + sw_ + 6, Wd - 2, -1)]:
        for x in range(x0, x1):
            f = (x - x0) / max(1, x1 - x0 - 1)
            f = f if d == 1 else 1 - f
            rgb[cy, x] = C['g1'] if f < 0.6 else C['g2']
            a[cy, x] = 0.35 + 0.65 * f
        dx = x1 + 1 if d == 1 else x0 - 2
        for yy_, xx_ in [(cy, dx), (cy - 1, dx), (cy + 1, dx), (cy, dx - 1), (cy, dx + 1)]:
            rgb[yy_, xx_] = C['g3']
            a[yy_, xx_] = 1
    save_rgba(np.dstack([rgb, a * 255]), 'subtitle')


def nine_panel():
    """48x48 panel: night glass fading at the bottom, gold hairline top/bottom with filigree corners, dim sides."""
    S = 48
    rgb = np.zeros((S, S, 3), np.float32) + C['n1']
    yy, xx = np.mgrid[0:S, 0:S]
    a = np.full((S, S), 0.7, np.float32)
    rgb[yy < 10] = C['n2']
    a[(xx == 0) | (xx == S - 1)] = 0.0
    side = ((xx == 1) | (xx == S - 2)) & (yy > 6) & (yy < S - 7)
    rgb[side] = C['n4']
    a[side] = 0.9
    for y in (0, S - 1):
        rgb[y, :] = C['g1']
        a[y, :] = 1
    rgb[1, :] = C['g0']
    a[1, :] = 0.9
    rgb[0, 8:S - 8] = C['g2']
    for cx, sx in [(1, 1), (S - 2, -1)]:
        for cy, sy in [(0, 1), (S - 1, -1)]:
            for dx, dy, c in [(0, 0, 'g3'), (0, 1, 'g2'), (0, 2, 'g2'), (0, 3, 'g1'), (0, 4, 'g1'), (0, 5, 'g0'),
                              (1, 1, 'g2'), (2, 2, 'g1'), (2, 1, 'm2'), (1, 2, 'g1'), (3, 3, 'g0'), (4, 2, 'g1'), (5, 2, 'g0')]:
                x, y = cx + sx * dx, cy + sy * dy
                rgb[y, x] = C[c]
                a[y, x] = 1
    # centre jewel on the top edge
    for dx, dy, c in [(0, 0, 'm3'), (-1, 0, 'm2'), (1, 0, 'm2'), (0, 1, 'm1'), (-2, 0, 'g2'), (2, 0, 'g2'), (0, -0, 'm3')]:
        rgb[0 + dy, S // 2 + dx] = C[c]
        a[0 + dy, S // 2 + dx] = 1
    save_rgba(np.dstack([rgb, a * 255]), 'panel9')


def nine_select():
    """24x16 selection bar: magenta-to-clear gradient with gold hairlines, left gem notch."""
    Wd, Hd = 48, 16
    yy, xx = np.mgrid[0:Hd, 0:Wd]
    f = np.clip(1 - xx / (Wd - 1), 0, 1)
    q = np.floor(f * 6 + BAYER[yy % 4, xx % 4]) / 6
    rgb = np.zeros((Hd, Wd, 3), np.float32) + C['m1']
    a = q * 0.75
    hair = (yy == 0) | (yy == Hd - 1)
    rgb[hair] = C['g2']
    a[hair] = np.clip(q[hair] * 1.2, 0, 1)
    rgb[(yy > 0) & (yy < Hd - 1) & (xx < 2)] = C['m2']
    a[(yy > 0) & (yy < Hd - 1) & (xx < 2)] = 1
    save_rgba(np.dstack([rgb, a * 255]), 'select9')


def keycap():
    S = 12
    yy, xx = np.mgrid[0:S, 0:S]
    rgb = np.zeros((S, S, 3), np.float32) + C['n3']
    a = np.ones((S, S), np.float32)
    rgb[yy >= S - 3] = C['n1']
    rgb[(yy == 0) | (xx == 0) | (xx == S - 1)] = C['n6']
    rgb[yy == S - 1] = C['n0']
    for x, y in [(0, 0), (S - 1, 0), (0, S - 1), (S - 1, S - 1)]:
        a[y, x] = 0
    save_rgba(np.dstack([rgb, a * 255]), 'key9')


def gem():
    g = ["..a..", ".abc.", "abccd", ".bcd.", "..d.."]
    key = {'a': C['m3'], 'b': C['m2'], 'c': C['m1'], 'd': C['m0']}
    rgb = np.zeros((5, 5, 3), np.float32)
    al = np.zeros((5, 5), np.float32)
    for y, r in enumerate(g):
        for x, ch in enumerate(r):
            if ch != '.':
                rgb[y, x] = key[ch]
                al[y, x] = 1
    save_rgba(np.dstack([rgb, al * 255]), 'gem')


if __name__ == '__main__':
    logo()
    nine_panel()
    nine_select()
    keycap()
    gem()
