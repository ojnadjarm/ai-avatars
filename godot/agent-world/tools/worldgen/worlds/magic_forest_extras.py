"""Magic Forest extras hooks: landmarks and zone ground no pixel-scene kind draws, built from the skill's primitives."""
import math
import os

import numpy as np
from PIL import Image, ImageDraw

import flora
import terrain
import world_foliage
import kit
from art import Sprite, MID, ellipse, poly, line, grid, rng, value_noise, fbm, dome, smooth_path

def _layer(g, layer):
    g.nodes[-1]['layer'] = layer


def _flat(g, name, S, x0, y0, layer='shade'):
    """Save a ground-style sprite (no outline, ground dither) at top-left (x0, y0)."""
    files, _ = S.save(os.path.join(g.out, name), outline=False, band=0.5, dith=0.55, cluster=True)
    g.add_files(name, files, [S.w, S.h], (0, 0), x0, y0, layer=layer)
    _layer(g, layer)


def plant(g, name, preset, seed, size, x, y, shape=None, layer='ysort'):
    """One T715 pixel-foliage plant (pooled atlas); the layer is forced (plateau plants share the lowland y-sort)."""
    node = world_foliage.pool(g.out).place(g, name, preset, seed, size, x, y, shape=shape, layer=layer)
    _layer(g, layer)
    return node


def plateau_flora(g, e, spec):
    """Plateau trees, shrubs, ferns and grass placed by magic_forest.py, y-sorted with the lowland."""
    for k, p in enumerate(e['plants']):
        x, y = p['at']
        sc = p['size']
        shape = None
        if p['preset'] in ('oak', 'conifer'):
            shape = ('rect', x - 5 * sc, y - 5, 10 * sc, 7)
        elif p['preset'] in ('bush', 'holly', 'hydrangea'):
            shape = ('ellipse', x, y - 2, 13 * sc, 5 * sc)
        plant(g, f'mf_pl{k}', p['preset'], p['seed'], sc, x, y, shape=shape)
        if p['preset'] == 'oak':
            g.emitter('leaves', x, y - 48 * sc, w=32 * sc, h=12 * sc)


ZSTYLE = {  # zone -> (base material, threshold, det, pin palettes, pin rate)
    'Whispering Hollow': ('grass', 0.6, 0.13, ['P0', 'E5', 'P0'], 0.004),
    'Spiral Meadow': ('grass', 0.48, 0.1, ['R2', 'G3', 'P0', 'M2', 'G2'], 0.014),
    'Resting Oak': ('grass', 0.55, 0.1, ['G1', 'G2', 'W2'], 0.003),
    'Mirror Lake': ('grass', 0.62, 0.08, ['N7', 'B1', 'N9'], 0.005),
    'Cerulean Ring': ('grass', 0.58, 0.02, ['N10', 'N9', 'T6'], 0.003),
    'Amberviolet Glade': ('grass', 0.56, 0.06, ['V3', 'V4', 'G1', 'V5'], 0.008),
    'Deep Forest Edge': ('grass', 0.5, 0.12, ['E5', 'P0', 'G2'], 0.008),
    'Runestone Portal': ('grass', 0.6, 0.05, ['N9', 'V5'], 0.002),
    'Moss Gate': ('reed', 0.45, -0.06, ['E5', 'E4'], 0.004),
    'Southbrook Ruins': ('grass', 0.55, 0.14, ['N7', 'B1', 'G2'], 0.004),
    'Shimmer Run': ('grass', 0.55, 0.08, ['N10', 'T6'], 0.004),
    'Sunstone Rise': ('grass', 0.52, 0.12, ['G3', 'G2', 'P0'], 0.006),
    'Skyroot Bluff': ('reed', 0.5, -0.06, ['E5', 'W2', 'P0'], 0.004),
    'Fernfall Dell': ('reed', 0.46, -0.06, ['E5', 'E4', 'G1'], 0.005),
    'Willowbank': ('grass', 0.6, 0.08, ['N7', 'B1', 'N9'], 0.005),
    'Millrace Ruins': ('grass', 0.55, 0.14, ['N7', 'G2', 'W2'], 0.004),
    'Hare Meadow': ('grass', 0.48, 0.1, ['R2', 'G3', 'P0', 'M2'], 0.014),
    'Heron Reach': ('grass', 0.58, 0.08, ['N10', 'T6', 'G2'], 0.004),
    'Thornwood': ('mud', 0.52, -0.08, ['T1', 'T2', 'W1'], 0.01),
    'Foxglove Fields': ('grass', 0.48, 0.1, ['M2', 'V5', 'P0', 'R2'], 0.014),
    "Hermit's Knoll": ('grass', 0.56, 0.1, ['G1', 'W2', 'P0'], 0.004),
    'Reedwater Fen': ('mud', 0.55, -0.04, ['N7', 'B1', 'T1'], 0.008),
    'Old Quarry': ('grass', 0.5, 0.14, ['N7', 'W2', 'G2'], 0.006),
}


def _bare(spec, W, H):
    """Paths, plazas and water (ground overlays stay off them)."""
    im = Image.new('L', (W, H), 0)
    d = ImageDraw.Draw(im)
    for p in spec.get('paths', []):
        hw = p['width'] / 2 + 3
        pts = smooth_path([tuple(q) for q in p['pts']], 8)
        d.line(pts, fill=255, width=int(2 * hw))
        for x, y in pts:
            d.ellipse([x - hw, y - hw, x + hw, y + hw], fill=255)
    for pz in spec.get('plazas', []):
        (x, y), (rx, ry) = pz['at'], pz['r']
        d.ellipse([x - rx - 3, y - ry - 3, x + rx + 3, y + ry + 3], fill=255)
    for s in spec.get('water', {}).get('streams', []):
        d.line(smooth_path([tuple(q) for q in s['pts']], 6), fill=255, width=int(s['width'] + 6))
    for pp in spec.get('water', {}).get('ponds', []):
        d.polygon([tuple(q) for q in pp], fill=255)
    return np.array(im) > 0


def ground_patches(g, e, spec):
    """Per-zone ground mix (moss, soil, litter, flowers, gravel) as unlit ground overlays."""
    W, H = spec['size']
    bare = _bare(spec, W, H)
    face = terrain.plateau(spec, W, H)[1]
    for k, (name, (x0, y0, w, h)) in enumerate(e['zones']):
        mat, thr, det, pins, rate = ZSTYLE[name]
        x1, y1 = min(W, x0 + w), min(H, y0 + h)
        w, h = x1 - x0, y1 - y0
        free = ~bare[y0:y1, x0:x1] & ~face[y0:y1, x0:x1]
        n1 = fbm(w, h, 26, 3, 300 + k)
        n2 = value_noise(w, h, 3, 340 + k)
        yy, xx = grid(h, w)
        fade = (1 - np.hypot((xx - w / 2) / (w / 2), (yy - h / 2) / (h / 2))) * min(w, h) / 80.0
        patch = free & (n1 + (n2 - 0.5) * 0.08 > thr + np.clip(1 - fade, 0, 1) * 0.25)
        S = Sprite(w, h)
        S.put(patch, mat, 0.0, det + (n1 - 0.5) * 0.3 + (n2 - 0.5) * 0.06)
        r = rng(400 + k)
        dots = free & (r.random((h, w)) < rate * np.clip(fade, 0, 1))
        for j, pal in enumerate(pins):
            m = dots & (r.integers(0, len(pins), (h, w)) == j)
            S.put(m, 'grass', 0.5, 0.0)
            S.pin(m, pal)
        _flat(g, f'mf_ground{k}', S, x0, y0)


def portal_arch(g, e, spec):
    """The Runestone Portal: ivy-swallowed stone archway, blue and violet glowing runes, motes in the opening."""
    x, y = e['at']
    w, h = 108, 138
    cx, base = w / 2, h - 4
    S = Sprite(w, h)
    yy, xx = grid(h, w)
    nz = value_noise(w, h, 3, 5) - 0.5
    spring = base - 76
    plinth = (xx >= 6) & (xx < w - 6) & (yy >= base - 7) & (yy <= base)
    S.put(plinth, 'stone', 2.0 + dome(plinth, 3), -0.06 + nz * 0.1)
    pillars = np.zeros((h, w), bool)
    for px in (22, w - 22):
        u = np.clip((xx - px) / 9.5, -1, 1)
        m = (np.abs(xx - px) <= 9) & (yy >= spring) & (yy < base - 7)
        seam = ((base - 7 - yy) % 13) == 0
        S.put(m, 'stone', np.sqrt(1 - u * u) * 6 + 3, nz * 0.14 - seam * 0.16)
        pillars |= m
    rr = np.hypot(xx - cx, yy - spring)
    ring = (rr >= 23) & (rr <= 41) & (yy <= spring)
    ang = np.degrees(np.arctan2(spring - yy, xx - cx))
    vseam = (np.abs((ang + 7.5) % 15 - 7.5) < 1.2) & (rr > 24)
    S.put(ring, 'stone', 3 + (1 - np.abs(rr - 32) / 9) * 3, nz * 0.14 - vseam * 0.18)
    key = ring & (np.abs(xx - cx) <= 6) & (yy <= spring - 22)
    S.put(key, 'stone', 7.0, 0.08)
    ivy_src = ring | pillars
    ivy = ivy_src & (fbm(w, h, 9, 2, 17) + (xx < cx) * 0.1 + (yy < spring) * 0.06 > 0.72)
    for k in range(1, 6):
        sx = 10 + k * 13 + (k * 7) % 5
        top = int(spring - math.sqrt(max(0, 41 ** 2 - (sx - cx) ** 2))) if abs(sx - cx) < 41 else spring
        ivy |= line(w, h, [(sx, top + 2), (sx + (k % 3) - 1, top + 14 + (k * 5) % 16)]) & ~(rr < 23)
    S.put(ivy, 'leaf', S.hgt + 1.0, 0.06 + (value_noise(w, h, 2, 18) - 0.5) * 0.2)
    glyph = np.zeros((h, w), bool)
    for px in (22, w - 22):
        for k, gy in enumerate(range(int(spring) + 8, int(base) - 14, 14)):
            strokes = [[(px - 2, gy), (px + 2, gy)], [(px, gy), (px, gy + 6)], [(px - 2, gy + 4), (px + 2, gy + 7)]]
            for s in strokes[:2 + (k + px) % 2]:
                glyph |= line(w, h, s)
    for a in range(-60, 61, 30):
        t = math.radians(90 - a)
        gx, gy = cx + math.cos(t) * 32, spring - math.sin(t) * 32
        glyph |= line(w, h, [(gx - 2, gy - 1), (gx + 2, gy + 1)]) | line(w, h, [(gx, gy - 2), (gx, gy + 2)])
    glyph &= (pillars | ring) & ~ivy
    S.hgt[glyph] -= 1
    blue = glyph & (xx < cx)
    S.pin(blue, 'N10')
    S.glow(blue, (110, 170, 255), 0.9)
    S.pin(glyph & ~blue, 'V6')
    S.glow(glyph & ~blue, (190, 120, 255), 0.9)
    g.add('mf_portal', S, (int(cx), int(base)), x, y, shape=None)
    for px in (22, w - 22):
        g.collide.append(('rect', x - cx + px - 10, y - 9, 20, 9))
    g.light('point', x, y - 46, [120, 170, 255], 0.5, 64, 20, flicker=0.15)
    g.light('point', x, y - 104, [190, 120, 255], 0.4, 56, 24, flicker=0.2)
    g.emitter('motes', x, y - 48, w=40, h=56, color=[150, 190, 255])


def _blob(w, h, rx, ry, nz):
    """Centred ellipse mask with a noisy edge (nz in 0..1)."""
    yy, xx = grid(h, w)
    return ((xx - w / 2) / rx) ** 2 + ((yy - h / 2) / ry) ** 2 < 1 + (nz - 0.5) * 0.3


def cerulean_ring(g, e, spec):
    """Cerulean Mushroom Ring: dark fertile soil inside a tight ring of blue-capped mushroom clusters."""
    x, y = e['at']
    rx, ry = e['r']
    w, h = int(rx * 2 + 24), int(ry * 2 + 20)
    S = Sprite(w, h)
    yy, xx = grid(h, w)
    nz = value_noise(w, h, 4, 31)
    disc = _blob(w, h, rx + 6, ry + 4, nz)
    S.put(disc, 'mud', 0.0, -0.16 + (fbm(w, h, 8, 2, 32) - 0.5) * 0.2)
    spores = disc & (rng(33).random((h, w)) < 0.006)
    S.pin(spores, 'N10')
    _flat(g, 'mf_cring_soil', S, int(x - w / 2), int(y - h / 2))
    n = 12
    for k in range(n):
        a = 2 * math.pi * k / n + 0.13
        px, py = x + math.cos(a) * rx, y + math.sin(a) * ry
        M = flora.mushrooms(500 + k, n=3, mat_cap='flowerb')
        g.add(f'mf_cring{k}', M, (14, 18), px, py)
    for k in range(3):
        a = 2 * math.pi * k / 3 + 0.5
        g.light('point', x + math.cos(a) * rx, y + math.sin(a) * ry - 6, [90, 170, 255], 0.3, 46, 16, flicker=0.3)
    g.emitter('motes', x, y - 8, w=rx, h=ry, color=[120, 190, 255])


def amber_fungi(g, e, spec):
    """Amberviolet Fungi: violet caps veined with gold, growing from the oak roots, ember light."""
    x, y = e['at']
    for k, (dx, dy) in enumerate([(-16, 2), (8, 6), (26, -4), (-34, 10)]):
        M = flora.mushrooms(600 + k, n=5, mat_cap='cap')
        yy, xx = grid(M.h, M.w)
        vein = (M.mat == MID['cap']) & (((xx + yy * 2) % 4) == 0)
        M.pin(vein, 'G2')
        M.glow(vein, (255, 180, 80), 0.6)
        g.add(f'mf_amber{k}', M, (14, 18), x + dx, y + dy)
    g.light('point', x + 4, y - 8, [190, 120, 255], 0.3, 44, 14, flicker=0.2)


def spiral_flowers(g, e, spec):
    """Spiral Wildflowers: reds, whites and yellows in a loose spiral, one tall indigo flower at the centre."""
    x, y = e['at']
    w, h = 156, 100
    cx, cy = w / 2, h / 2
    S = Sprite(w, h)
    nz = value_noise(w, h, 5, 41)
    bed = _blob(w, h, 74, 46, nz)
    S.put(bed, 'grass', 0.3, 0.06 + (fbm(w, h, 10, 2, 42) - 0.5) * 0.2)
    r = rng(43)
    cols = ['R2', 'P0', 'G3']
    th = 0.8
    while th < 4.3 * math.pi:
        rad = 6 + 64 * th / (4.3 * math.pi)
        fx, fy = cx + math.cos(th) * rad, cy + math.sin(th) * rad * 0.62
        for _ in range(3):
            ox, oy = fx + r.normal(0, 2.2), fy + r.normal(0, 1.6)
            ix, iy = int(ox), int(oy)
            if 1 <= ix < w - 2 and 2 <= iy < h - 2:
                head = np.zeros((h, w), bool)
                head[iy:iy + 2, ix:ix + 2] = True
                pal = cols[int(th / (0.9 * math.pi)) % 3] if r.random() > 0.15 else cols[int(r.integers(3))]
                S.put(head, 'grass', 1.0, 0.0)
                S.pin(head, pal)
                stem = np.zeros((h, w), bool)
                stem[iy + 2, ix] = True
                S.put(stem, 'grass', 0.5, 0.0)
                S.pin(stem, 'E2')
        th += 5.0 / max(rad, 6)
    beetles = bed & (r.random((h, w)) < 0.002)
    S.pin(beetles, 'T7')
    _flat(g, 'mf_spiral_bed', S, int(x - cx), int(y - cy))
    F = Sprite(16, 44)
    fy_, fx_ = grid(44, 16)
    stem = line(16, 44, [(8, 42), (7, 28), (8, 12)])
    F.put(stem, 'reed', 2.0, 0.05)
    F.put(line(16, 44, [(7, 30), (3, 24)]) | line(16, 44, [(8, 26), (12, 21)]), 'reed', 2.5, 0.1)
    bell = ellipse(16, 44, 8, 8, 4.5, 6) & (fy_ <= 12)
    F.put(bell, 'cloth', dome(bell, 3) + 4, -0.18)
    F.pin(bell & (fy_ >= 11), 'N5')
    F.pin(bell & (fy_ <= 4) & (fx_ <= 7), 'V5')
    F.glow(bell, (110, 90, 255), 0.25)
    g.add('mf_indigo', F, (8, 42), x, y + 2)
    g.emitter('petals', x, y - 12, w=60, h=12, color=[255, 226, 140])


def shimmerfish(g, e, spec):
    """The Shimmerfish: a large fish holding still in the stream, scales shifting green to gold to red."""
    x, y = e['at']
    w, h = 30, 14
    S = Sprite(w, h)
    yy, xx = grid(h, w)
    body = ellipse(w, h, 13, 7, 10, 3.6)
    S.put(body, 'gold', dome(body, 3) + 1, 0.0)
    S.pin(body & (yy <= 5), 'T5')
    S.pin(body & (yy <= 4) & (xx < 9), 'E4')
    S.pin(body & (xx >= 18), 'R2')
    tail = poly(w, h, [(21, 7), (28, 2), (27, 7), (28, 12)])
    S.put(tail, 'foam', 1.0, -0.1)
    S.pin(tail & (xx >= 26), 'R3')
    fins = poly(w, h, [(10, 4), (15, 1), (16, 4)]) | poly(w, h, [(11, 10), (15, 13), (16, 10)])
    S.put(fins, 'foam', 1.5, 0.0)
    eye = np.zeros((h, w), bool)
    eye[6, 6] = True
    S.pin(eye, 'N0')
    S.glow(body, (255, 200, 90), 0.18)
    g.add('mf_shimmerfish', S, (13, 7), x, y, layer='bridge')
    _layer(g, 'bridge')


def _rim_points(rim, step):
    """Points every `step` px along the rim polyline."""
    out = []
    for (x0, y0), (x1, y1) in zip(rim, rim[1:]):
        n = max(1, int(math.hypot(x1 - x0, y1 - y0) / step))
        out += [(x0 + (x1 - x0) * t / n, y0 + (y1 - y0) * t / n) for t in range(n)]
    return out + [tuple(rim[-1])]


def living_wall(g, e, spec):
    """The Living Wall: a dense conifer row along the plateau's north rim, with a solid collision band."""
    rim = e['rim']
    for k, (px, py) in enumerate(_rim_points(rim, 8)):
        g.collide.append(('rect', px - 6, py - 4, 12, 14))
    r = rng(77)
    for k, (px, py) in enumerate(_rim_points(rim, 34)):
        if not 6 <= px <= rim[-1][0] - 6:
            continue
        plant(g, f'mf_wall{k}', 'conifer', int(r.integers(1, 9999)), float(r.uniform(1.6, 2.2)), px, py + 6)


ROCK = ['N9', 'N8', 'N7', 'N6', 'B1', 'N5', 'N4', 'B0', 'N3', 'N2']


def _chunks(h, w, seed, cw=22, ch=9):
    """Jittered-grid Voronoi rock chunks: per-pixel chunk id, distance gap to the second nearest seed, local y in chunk."""
    r = rng(seed)
    gy, gx = h // ch + 3, w // cw + 3
    sx = (np.arange(gx)[None, :] - 1 + r.uniform(0.15, 0.85, (gy, gx))) * cw + (np.arange(gy)[:, None] % 2) * cw / 2
    sy = (np.arange(gy)[:, None] - 1 + r.uniform(0.2, 0.8, (gy, gx))) * ch
    yy, xx = np.mgrid[0:h, 0:w]
    cy, cx = yy // ch + 1, xx // cw + 1
    best, second = np.full((h, w), 1e9), np.full((h, w), 1e9)
    cid, top = np.zeros((h, w), int), np.zeros((h, w))
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            ny, nx = np.clip(cy + dy, 0, gy - 1), np.clip(cx + dx, 0, gx - 1)
            d = np.hypot((xx - sx[ny, nx]) / cw, (yy - sy[ny, nx]) / ch)
            near = d < best
            second = np.where(near, best, np.minimum(second, d))
            cid = np.where(near, ny * gx + nx, cid)
            top = np.where(near, yy - sy[ny, nx], top)
            best = np.where(near, d, best)
    return cid, second - best, top / ch


def _earth_face(face, d, height, seed):
    """Sunlit rock cliff face in palette colours: grass overhang, thin soil, stacked rock chunks lit from above, dark foot."""
    h, w = face.shape
    r = rng(seed)
    yy, xx = (v.astype(int) for v in grid(h, w))
    u = np.clip(d / height, 0, 1)
    cid, gap, cy = _chunks(h, w, seed)
    ctone = r.uniform(-0.9, 0.9, cid.max() + 1)[cid]
    tone = 0.6 + u * 5.0 + ctone + cy * 1.1 + (kit.BAYER[yy % 4, xx % 4] - 0.5) * 0.6
    idx = np.array([kit.IDX[n] for n in ROCK])[np.clip(tone.astype(int), 0, len(ROCK) - 1)]
    crack = gap < 0.16
    lit = ~crack & np.roll(crack, 1, axis=0) & (u < 0.75)
    idx = np.where(lit, kit.IDX['N9'], idx)
    idx = np.where(crack, np.where(u < 0.5, kit.IDX['N4'], kit.IDX['N2']), idx)
    lip = 3 + (value_noise(w, h, 2, seed + 3) * 3).astype(int)
    drip = r.integers(0, 9, w)[None, :] * (r.random(w) > 0.55)[None, :]
    soil = (d >= lip) & (d < lip + 2)
    idx = np.where(soil, np.where(xx % 3 == 0, kit.IDX['W1'], kit.IDX['W2']), idx)
    idx = np.where(d < lip + drip, np.where(d < 2, kit.IDX['E4'], np.where(d < lip, kit.IDX['E3'], kit.IDX['E2'])), idx)
    foot = d >= height - 3
    idx = np.where(foot, kit.IDX['N1'], idx)
    tuft = (d >= height - 4) & (value_noise(w, h, 1.5, seed + 4) > 0.6) & (xx % 2 == 0)
    idx = np.where(tuft, kit.IDX['E2'], idx)
    im = np.zeros((h, w, 4), np.uint8)
    im[..., :3] = kit.RGB[idx].astype(np.uint8)
    im[..., 3] = face * 255
    return im


def plateau_read(g, e, spec):
    """Each raised level reads as raised: a sunlit top, a broken grass lip, a lit rock face, a long stepped cast shadow."""
    W, H = spec['size']
    lip_rgb, shade_rgb, sun_rgb = kit.RGB[kit.IDX['E5']], kit.RGB[kit.IDX['T0']], kit.RGB[kit.IDX['G3']]
    for k, c in enumerate(e['cliffs']):
        top, face, _, edge, _ = terrain.plateau({'cliff': c}, W, H)
        xs = np.where(top.any(0))[0]
        ys = np.where(top.any(1))[0]
        x0, x1 = int(xs.min()), int(xs.max()) + 1
        reach = int(c['height'] * 0.55)
        y0, y1 = int(ys.min()), min(H, int(edge[xs].max()) + c['height'] + reach + 4)
        h, w = y1 - y0, x1 - x0
        d = np.arange(y0, y1)[:, None] - edge[None, x0:x1]
        nz = value_noise(w, h, 4, 700 + k)
        yy, xx = (v.astype(int) for v in grid(h, w))
        bay = kit.BAYER[(yy + y0) % 4, (xx + x0) % 4]
        st0, st1 = c.get('stairs', [0, 0])
        cols = np.arange(x0, x1)[None, :]
        stairs = (cols >= st0 - 2) & (cols < st1 + 2)
        t = top[y0:y1, x0:x1]
        lip = t & (d >= -2) & (d < 0) & (nz > 0.3) & ~stairs
        below = (d - c['height']) / reach + (nz - 0.5) * 0.25
        shade = (below >= 0) & (below < 1) & ~t & ~face[y0:y1, x0:x1]
        alpha = np.select([below < 0.12, below < 0.45 + (bay - 0.5) * 0.12, below < 0.8 + (bay - 0.5) * 0.12],
                          [0.8, 0.66, 0.48], 0.24 * (bay > 0.5)) * shade
        im = np.zeros((h, w, 4), np.uint8)
        im[..., :3] = shade_rgb.astype(np.uint8)
        im[..., 3] = (alpha * 255).astype(np.uint8)
        sun = t & ~lip
        im[sun, :3] = sun_rgb.astype(np.uint8)
        im[sun, 3] = 34
        im[lip, :3] = lip_rgb.astype(np.uint8)
        im[lip, 3] = 210
        g.image(f'mf_plateau_read{k}', Image.fromarray(im, 'RGBA'), x0, y0, 'shade', sort=H + k)
        fy0 = max(0, int(edge[xs].min()) - 4)
        fm = face[fy0:y1, x0:x1] & ~stairs
        g.image(f'mf_plateau_face{k}', Image.fromarray(_earth_face(fm, d[fy0 - y0:], c['height'], 720 + k), 'RGBA'),
                x0, fy0, 'plateau', sort=int(edge[xs].max()) + c['height'])
        print(f'PLATEAU_READ {k} lip {int(lip.sum())} px sun {int(sun.sum())} px shadow {int(shade.sum())} px face {int(fm.sum())} px')
