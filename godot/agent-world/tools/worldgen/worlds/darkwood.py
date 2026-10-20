#!/usr/bin/env python3
"""Darkwood night world spec: hand-placed layout plus seeded Poisson-disc scatter -> darkwood.json (pixel-scene + game).
usage: darkwood.py [OUT.json]"""
import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from magic_forest import lobe  # noqa: E402
EXTRAS = 'tools/worldgen/worlds/darkwood_extras.py'
W, H = 3840, 2160
SEED = 714
SCREEN = (640, 360)

CLIFF = {'poly': [[960, -4], [3844, -4], [3844, 470], [3700, 488], [3560, 500], [3400, 506], [3240, 496], [3080, 474],
                  [2900, 446], [2740, 426], [2600, 412], [2564, 404], [2460, 420], [2380, 436], [2300, 446], [2200, 466], [2080, 478],
                  [1960, 482], [1860, 472], [1760, 440], [1640, 396], [1540, 370], [1502, 358], [1428, 358], [1320, 340], [1180, 318],
                  [1060, 290], [990, 250], [966, 120]],
         'height': 44, 'stairs': [1446, 1488], 'fall': [2300, 2322]}
RAVEN = {'name': 'Ravenscar Heights', 'height': 36, 'stairs': [3300, 3332], 'elevation': 80,
         'poly': [[2900, -4], [3844, -4], [3844, 250], [3700, 262], [3560, 272], [3420, 270], [3344, 262], [3288, 262],
                  [3200, 250], [3100, 236], [3000, 210], [2930, 170], [2906, 90]]}
MIRE = [(860, 1560, 90, 36), (1160, 1600, 70, 30), (840, 1880, 100, 40), (1180, 1880, 60, 28)]
CHAPEL = (2980, 1300, 120, 56)
WELL = (3500, 1720, 34, 18)

POOL = (2230, 870, 160, 84)
POOL_PARTS = [(2205, 852, 142, 62), (2292, 896, 98, 54), (2160, 902, 78, 42)]
BOG = [(1420, 1222, 70, 32), (1640, 1338, 80, 36), (1862, 1250, 58, 28), (2080, 1352, 92, 38), (2380, 1300, 60, 30),
       (1250, 1380, 50, 24)]
CROSSINGS = [[2272, 584, 2326, 610], [2116, 1180, 2170, 1206], [2298, 238, 2352, 262]]
BRIDGES = [(2298, 597, 48, 24), (2143, 1193, 48, 24), (2325, 250, 48, 22)]


def _resample(pts, step):
    """Polyline resampled every ~`step` px; returns (points, arc length of each)."""
    p = np.asarray(pts, float)
    s = np.r_[0, np.cumsum(np.hypot(*np.diff(p, axis=0).T))]
    t = np.linspace(0, s[-1], max(2, int(s[-1] / step) + 1))
    return np.c_[np.interp(t, s, p[:, 0]), np.interp(t, s, p[:, 1])], t


def _gauss(a, sigma):
    """Gaussian smoothing of an (n, 2) array along its rows, edges held."""
    r = max(1, int(3 * sigma))
    k = np.exp(-0.5 * (np.arange(-r, r + 1) / sigma) ** 2)
    pad = np.pad(a, ((r, r), (0, 0)), mode='edge')
    return np.stack([np.convolve(pad[:, j], k / k.sum(), mode='valid') for j in range(a.shape[1])], 1)


def _ease(x):
    x = np.clip(x, 0, 1)
    return x * x * (3 - 2 * x)


def meander(pts, amp, wave, seed, pins=(), calm=110, soft=24, step=4, out_step=16):
    """Stream centre line: the control polyline bent side to side by two sines along its arc, the bend easing out over
    `calm` px at both ends and at pins (bridges), then smoothed by a `soft` px Gaussian so no bend turns into a corner."""
    ph = np.random.default_rng(seed).uniform(0, 2 * math.pi, 2)
    c, s = _resample(pts, step)
    tan = np.gradient(_gauss(c, 6), axis=0)
    nrm = np.c_[-tan[:, 1], tan[:, 0]] / np.hypot(*tan.T)[:, None]
    env = _ease(s / calm) * _ease((s[-1] - s) / calm)
    for px, py in pins:
        env *= _ease(np.hypot(c[:, 0] - px, c[:, 1] - py) / calm)
    off = amp * (0.75 * np.sin(2 * math.pi * s / wave + ph[0]) + 0.25 * np.sin(2 * math.pi * s / (wave * 0.55) + ph[1]))
    q = _gauss(c + nrm * (off * env)[:, None], soft / step)
    u = (s / s[-1])[:, None]
    q += (c[0] - q[0]) * (1 - u) + (c[-1] - q[-1]) * u
    keep = np.r_[np.arange(0, len(q) - 1, out_step // step), len(q) - 1]
    return [[int(round(x)), int(round(y))] for x, y in q[keep]]


PINS = [(x, y) for x, y, _, _ in BRIDGES]
STREAMS = [{'pts': meander([[2360, -4], [2350, 80], [2332, 180], [2318, 300], [2311, 380], [2311, 448]], 30, 160, 51, PINS),
            'width': 16},
           {'pts': meander([[2311, 486], [2306, 540], [2296, 600], [2280, 680], [2258, 760], [2240, 806]], 42, 150, 52, PINS),
            'width': 18},
           {'pts': meander([[2214, 926], [2196, 1040], [2160, 1120], [2142, 1200], [2120, 1280], [2100, 1318]], 38, 160, 53, PINS),
            'width': 16}]

PATHS = {
    'road': ([[430, 560], [640, 578], [900, 580], [1200, 575], [1466, 577], [1760, 592], [2080, 600], [2298, 597],
              [2470, 612]], 24),
    'east_leg': ([[2470, 612], [2484, 760], [2444, 950], [2340, 1110], [2200, 1192], [2143, 1193], [2000, 1180],
                  [1760, 1164], [1520, 1150], [1250, 1150], [980, 1100], [870, 1046]], 20),
    'west_leg': ([[430, 560], [465, 720], [505, 900], [570, 1030], [700, 1030]], 18),
    'stairs': ([[1466, 575], [1466, 500], [1467, 440], [1467, 380], [1467, 330], [1470, 300]], 16),
    'spire': ([[1470, 300], [1560, 322], [1680, 352], [1800, 398], [1880, 430], [1930, 452]], 16),
    'spring': ([[1680, 352], [1770, 296], [1900, 232], [2050, 186], [2190, 176], [2246, 190]], 14),
    'ruins': ([[1470, 300], [1380, 290], [1260, 262], [1150, 226], [1090, 214]], 14),
    'boundary': ([[430, 560], [380, 480], [320, 400], [262, 330], [214, 288], [196, 274]], 14),
    'glade': ([[780, 585], [788, 500], [796, 410], [800, 330], [800, 266]], 14),
    'hollow': ([[520, 990], [460, 1060], [400, 1100], [340, 1106]], 12),
    'ring': ([[400, 1100], [350, 1170], [318, 1240], [304, 1300]], 12),
    'shortcut': ([[1600, 585], [1630, 690], [1700, 790], [1820, 850], [1940, 872], [2040, 874]], 16),
    'shortcut_s': ([[1820, 850], [1790, 950], [1740, 1050], [1700, 1120], [1680, 1166]], 14),
    'colonnade': ([[1700, 790], [1620, 850], [1540, 896]], 12),
    'camp': ([[1100, 1140], [1060, 1220], [1010, 1290]], 12),
    'echo': ([[1660, 1170], [1580, 1236], [1520, 1300], [1480, 1336]], 12),
    'toll_road': ([[2470, 612], [2640, 640], [2820, 670], [2980, 690], [3160, 700], [3360, 690], [3540, 700], [3760, 720]], 22),
    'well': ([[2820, 670], [2840, 800], [2860, 880]], 12),
    'chapel': ([[2484, 760], [2640, 860], [2800, 960], [2880, 1080], [2900, 1200]], 14),
    'gravefern': ([[3360, 690], [3420, 800], [3540, 830], [3600, 940]], 12),
    'eastway': ([[3540, 700], [3600, 940], [3520, 1100], [3540, 1240], [3500, 1450], [3500, 1640], [3400, 1700],
                 [3420, 1790], [3560, 1820], [3600, 2000]], 14),
    'chapel_e': ([[2900, 1200], [3120, 1210], [3300, 1330], [3500, 1450]], 12),
    'ridge': ([[2246, 196], [2325, 250], [2480, 300], [2640, 340], [2760, 400], [2920, 370], [3080, 340], [3316, 340],
               [3316, 300], [3316, 262], [3320, 200], [3220, 140], [3120, 140]], 14),
    'heights': ([[3320, 200], [3440, 175], [3560, 180]], 12),
    'gloam': ([[3080, 340], [3300, 400], [3600, 440]], 12),
    'south_trail': ([[304, 1300], [345, 1380], [320, 1500], [320, 1620], [560, 1720], [1000, 1700], [1300, 1720], [1700, 1700],
                     [2000, 1700], [2300, 1680], [2600, 1720], [2900, 1740], [3200, 1720], [3500, 1640]], 16),
    'camp_s': ([[1010, 1290], [1000, 1450], [1000, 1700]], 12),
    'bog_s': ([[1760, 1164], [1770, 1290], [1790, 1440], [1760, 1580], [1700, 1700]], 12),
    'barrow': ([[320, 1620], [260, 1800], [240, 1950]], 11),
    'mire': ([[1000, 1700], [1000, 1840], [1000, 1975]], 11),
    'axe': ([[1700, 1700], [1640, 1840], [1600, 1970]], 11),
    'ossuary': ([[2300, 1680], [2300, 1840], [2300, 1990]], 11),
    'howl': ([[2900, 1740], [2880, 1880], [2860, 1990]], 11),
}

PLAZAS = [
    {'at': [779, 1010], 'r': [92, 58], 'spacing': 9.0, 'broken': 0.24, 'runes': [255, 60, 70], 'groove_pal': 'R0', 'glyph_pal': 'R2'},
    {'at': [800, 226], 'r': [70, 40], 'spacing': 8.5, 'broken': 0.4, 'runes': [190, 130, 255], 'groove_pal': 'V1', 'glyph_pal': 'V5'},
]

ZONES = [
    ('Boundary Dark', [0, 0, 560, 620], [262, 330]),
    ('Moon Glade', [560, 0, 400, 470], [800, 280]),
    ('Hollowmere Spire', [960, 0, 1600, 470], [1680, 352]),
    ('Lantern Road', [560, 480, 1420, 240], [1200, 575]),
    ('Watching Tree', [0, 860, 640, 580], [400, 1100]),
    ('Crimson Runestone', [640, 860, 640, 580], [779, 1060]),
    ('Blackwater Pool', [1980, 640, 580, 460], [2444, 950]),
    ('Bog of Echoes', [1290, 1090, 1270, 350], [1820, 1164]),
    ('Ravenscar Heights', [2900, 0, 940, 250], [3320, 200]),
    ('Owlwatch Ridge', [2564, 250, 1276, 250], [2920, 370]),
    ('Toll Road', [2560, 520, 720, 400], [2820, 670]),
    ('Gravefern Hollow', [3280, 720, 560, 400], [3420, 800]),
    ('Drowned Chapel', [2560, 960, 700, 480], [2900, 1200]),
    ('Hanging Woods', [3280, 1120, 560, 440], [3500, 1450]),
    ('Barrow Downs', [0, 1460, 680, 460], [320, 1500]),
    ('Weeping Mire', [700, 1460, 700, 460], [1000, 1700]),
    ("Woodcutter's Rest", [1420, 1460, 640, 420], [1700, 1700]),
    ('Bone Orchard', [2080, 1460, 640, 540], [2300, 1680]),
    ('Wolfsden Rocks', [2740, 1600, 560, 560], [2900, 1740]),
    ('Moonwell Clearing', [3300, 1580, 540, 580], [3560, 1820]),
]

LANDMARKS = [
    ('The Boundary Dark', [196, 274], False), ('Last Lantern Waymark', [470, 534], False),
    ('The Watching Tree', [330, 1074], True), ('Witch Ring', [304, 1316], False),
    ('Moon Glade', [800, 214], False), ('Lantern Road Gate', [900, 580], False),
    ('The Crimson Runestone', [779, 1004], False), ('Lost Camp', [1000, 1320], False),
    ('Spire Ruins', [1100, 196], False), ('Hollowmere Stair', [1467, 330], False),
    ('Hollowmere Spire', [1915, 436], True), ('Crossroads', [1600, 590], False),
    ('Fallen Colonnade', [1510, 904], False), ('Echo Stones', [1480, 1350], False),
    ('Spire Spring', [2256, 170], False), ('Moon Shrine', [2500, 578], False),
    ('The Blackwater Pool', [2230, 870], False), ('Old Plank Bridge', [2143, 1193], False),
    ('Raven Altar', [3120, 130], False), ('Ravenscar Spire', [3560, 150], True), ('Ravenscar Stair', [3316, 330], False),
    ('Owlwatch Cairn', [2760, 380], False), ('Old Toll Gate', [2980, 690], False), ('Gloam Shrine', [3600, 420], False),
    ('Wailing Well', [2860, 900], False), ('Gravefern Stones', [3684, 840], False), ('Drowned Chapel', [2980, 1236], False),
    ('Lantern Tree', [3620, 1260], False), ('Wolf Den', [2980, 1640], False), ('Moonwell', [3500, 1720], False),
    ('Howling Stone', [2860, 2000], False), ('Last Lantern', [3600, 2000], False), ('Old Barrow', [180, 1640], False),
    ('Cairn of Names', [240, 1960], False), ('Weeping Willow', [1060, 1560], False), ('Mire Lanterns', [1000, 1985], False),
    ("Woodcutter's Camp", [1620, 1600], False), ('Axe Stump', [1600, 1980], False), ('Bone Orchard', [2300, 1600], False),
    ('Ossuary Arch', [2300, 1990], False),
]

GAME_PROPS = {
    'prop_70956': {'at': [190, 262], 'size': [56, 48], 'collision': False},
    'prop_17608': {'at': [330, 1050], 'size': [90, 50], 'collision': False},
    'prop_240778': {'at': [779, 992], 'size': [30, 24], 'collision': False},
    'prop_102298': {'at': [2050, 874], 'size': [36, 60], 'collision': False},
}
PROP_GOALS = {'prop_70956': [204, 290], 'prop_17608': [340, 1104], 'prop_240778': [779, 1040],
              'prop_102298': [2036, 874]}

KEEPOUT = [((330, 1074), 120), ((1915, 436), 70), ((779, 1004), 40), ((800, 214), 50), ((900, 580), 46),
           ((1000, 1320), 50), ((1100, 196), 50), ((1510, 904), 60), ((1480, 1350), 60), ((2256, 170), 40),
           ((2500, 578), 50), ((304, 1316), 70), ((196, 274), 40), ((1330, 600), 50), ((470, 534), 26),
           ((3120, 130), 90), ((3560, 150), 80), ((3316, 330), 40), ((2760, 380), 56), ((2980, 690), 46), ((3600, 420), 56),
           ((2860, 900), 50), ((3684, 840), 90), ((3620, 1270), 70), ((2980, 1640), 70), ((3500, 1720), 90),
           ((2860, 2000), 46), ((3600, 2000), 40), ((180, 1640), 90), ((240, 1960), 40), ((1060, 1560), 50),
           ((1000, 1985), 40), ((1620, 1600), 60), ((2400, 1720), 240), ((1600, 1980), 40), ((2300, 1990), 50)]


def _grow(m, r):
    """Boolean mask dilated r steps (4- and 8-neighbour steps alternating)."""
    for k in range(r):
        n = m.copy()
        n[1:] |= m[:-1]
        n[:-1] |= m[1:]
        n[:, 1:] |= m[:, :-1]
        n[:, :-1] |= m[:, 1:]
        if k % 2:
            n[1:, 1:] |= m[:-1, :-1]
            n[:-1, :-1] |= m[1:, 1:]
            n[1:, :-1] |= m[:-1, 1:]
            n[:-1, 1:] |= m[1:, :-1]
        m = n
    return m


def blackwater_pool(blur=22, n=180, fillet=12, reach=34):
    """Blackwater Pool: three lobes blurred into one outline, plus a `fillet` px rounding where each stream meets it
    (a closing of pool + stream kept within `reach` px of the mouth), traced radially from the centre."""
    cx, cy = POOL[0], POOL[1]
    pad = blur * 3
    x0, y0 = int(min(e[0] - e[2] for e in POOL_PARTS)) - pad, int(min(e[1] - e[3] for e in POOL_PARTS)) - pad
    x1, y1 = int(max(e[0] + e[2] for e in POOL_PARTS)) + pad, int(max(e[1] + e[3] for e in POOL_PARTS)) + pad
    im = Image.new('L', (x1 - x0, y1 - y0))
    d = ImageDraw.Draw(im)
    for ex, ey, rx, ry in POOL_PARTS:
        d.ellipse([ex - rx - x0, ey - ry - y0, ex + rx - x0, ey + ry - y0], fill=255)
    m = np.array(im.filter(ImageFilter.GaussianBlur(blur))) > 100
    st = Image.new('L', im.size)
    ImageDraw.Draw(st).line([(x - x0, y - y0) for x, y in STREAMS[1]['pts'] + STREAMS[2]['pts']], fill=255,
                            width=STREAMS[1]['width'], joint='curve')
    st = np.array(st) > 0
    closed = ~_grow(~_grow(m | st, fillet), fillet)
    yy, xx = np.mgrid[0:m.shape[0], 0:m.shape[1]]
    near = np.zeros_like(m)
    for mx, my in (STREAMS[1]['pts'][-1], STREAMS[2]['pts'][0]):
        near |= np.hypot(xx - (mx - x0), yy - (my - y0)) < reach
    m |= closed & near & _grow(m, fillet)
    ph = np.random.default_rng(3).uniform(0, 6.3, 3)
    pts = []
    for k in range(n):
        a = 2 * math.pi * k / n
        dx, dy = math.cos(a), math.sin(a)
        t = 0
        while m[int(cy - y0 + dy * (t + 1)), int(cx - x0 + dx * (t + 1))]:
            t += 1
        f = 1 + 0.02 * math.sin(3 * a + ph[0]) + 0.012 * math.sin(7 * a + ph[1])
        pts.append([round(cx + dx * t * f), round(cy + dy * t * f)])
    return pts


def ponds():
    """Blackwater Pool with flared stream mouths; bogs, mires, chapel pond and well as noisy-harmonic ellipses."""
    return ([blackwater_pool()] + [lobe(*b, 10 + k, n=32) for k, b in enumerate(BOG)] +
            [lobe(*b, 30 + k, n=32) for k, b in enumerate(MIRE)] + [lobe(*CHAPEL, 40, n=36), lobe(*WELL, 41, n=24)])


def raster(draw_fn):
    """Full-map boolean mask from a PIL drawing callback."""
    im = Image.new('L', (W, H), 0)
    draw_fn(ImageDraw.Draw(im))
    return np.array(im) > 0


def masks(pond_polys):
    """Blocked-for-scatter masks: paths (with margin), water, plazas, cliff band, plateau top."""
    def paths(m):
        return lambda d: [d.line([tuple(p) for p in pts], fill=255, width=int(w + 2 * m), joint='curve') for pts, w in PATHS.values()]
    path_hard = raster(paths(10))
    path_soft = raster(paths(3))
    water = raster(lambda d: ([d.polygon([tuple(p) for p in pp], fill=255) for pp in pond_polys] +
                              [d.line([tuple(p) for p in s['pts']], fill=255, width=s['width'] + 6) for s in STREAMS]))
    plaza = raster(lambda d: [d.ellipse([p['at'][0] - p['r'][0] - 14, p['at'][1] - p['r'][1] - 10,
                                         p['at'][0] + p['r'][0] + 14, p['at'][1] + p['r'][1] + 10], fill=255) for p in PLAZAS])
    top = raster(lambda d: d.polygon([tuple(p) for p in CLIFF['poly']], fill=255))
    edge = np.where(top.any(0), H - np.argmax(top[::-1], 0), -999)
    yy = np.arange(H)[:, None]
    band = (yy >= edge[None, :] - 10) & (yy < edge[None, :] + CLIFF['height'] + 12)
    rtop = raster(lambda d: d.polygon([tuple(p) for p in RAVEN['poly']], fill=255))
    redge = np.where(rtop.any(0), H - np.argmax(rtop[::-1], 0), -999)
    band |= (yy >= redge[None, :] - 10) & (yy < redge[None, :] + RAVEN['height'] + 12)
    keep = np.zeros((H, W), bool)
    gy, gx = np.mgrid[0:H, 0:W]
    for (x, y), r in KEEPOUT:
        x0, x1, y0, y1 = max(0, x - r), min(W, x + r), max(0, y - r), min(H, y + r)
        keep[y0:y1, x0:x1] |= np.hypot(gx[y0:y1, x0:x1] - x, gy[y0:y1, x0:x1] - y) < r
    near_water = np.array(Image.fromarray((water * 255).astype(np.uint8)).resize((W // 8, H // 8), Image.BOX)) > 0
    return dict(path_hard=path_hard, path_soft=path_soft, water=water, plaza=plaza, top=top, band=band, keep=keep,
                near_water=near_water)


def poisson(rng, ok, radius_fn, tries, existing=()):
    """Dart-throwing Poisson disc: accept points where ok(x, y) and no neighbour inside radius_fn(x, y)."""
    cell = 16
    grid = {}
    pts = []
    for (x, y, r) in existing:
        grid.setdefault((int(x // cell), int(y // cell)), []).append((x, y, r))
    for _ in range(tries):
        x, y = rng.uniform(4, W - 4), rng.uniform(4, H - 4)
        if not ok(int(x), int(y)):
            continue
        r = radius_fn(int(x), int(y))
        reach = int(math.ceil(max(r, 60) / cell))
        cx, cy = int(x // cell), int(y // cell)
        bad = False
        for i in range(cx - reach, cx + reach + 1):
            for j in range(cy - reach, cy + reach + 1):
                for (qx, qy, qr) in grid.get((i, j), ()):
                    if (qx - x) ** 2 + (qy - y) ** 2 < max(r, qr) ** 2:
                        bad = True
                        break
                if bad:
                    break
            if bad:
                break
        if bad:
            continue
        grid.setdefault((cx, cy), []).append((x, y, r))
        pts.append((x, y, r))
    return pts


def near_water(M, x, y, d=7):
    """True when water lies within d coarse cells (8 px each) of (x, y)."""
    nw = M['near_water']
    i, j = int(y // 8), int(x // 8)
    return nw[max(0, i - d):i + d + 1, max(0, j - d):j + d + 1].any()


POOL_N = {'conifer': 36, 'oak': 36, 'willow': 12, 'bush': 14, 'holly': 8, 'hydrangea': 6, 'fern': 14, 'tuft': 10,
          'tallgrass': 10, 'meadow': 8, 'glowflora': 12}
SIZES = {'conifer': (1.6, 2.0), 'oak': (1.45, 1.85), 'willow': (1.45, 1.8), 'bush': (1.0, 1.6), 'holly': (1.0, 1.5),
         'hydrangea': (1.0, 1.4), 'fern': (1.1, 1.7), 'tuft': (1.0, 1.4), 'tallgrass': (1.0, 1.4), 'meadow': (1.0, 1.3),
         'glowflora': (0.9, 1.3)}


def plant(rng, preset, x, y, layer=None):
    """One pooled pixel-foliage instance: variant index, its size, and the PFPlacer-equivalent collision."""
    v = int(rng.integers(POOL_N[preset]))
    lo, hi = SIZES[preset]
    s = round(lo + (hi - lo) * v / max(POOL_N[preset] - 1, 1), 2)
    it = {'p': preset, 'at': [x, y], 'v': v, 's': s}
    if preset in ('conifer', 'oak', 'willow') and layer != 'fg':
        sc = s / 1.25
        it['shape'] = ['rect', round(x - 6 * sc, 1), y - 5, round(12 * sc, 1), 7]
    elif preset in ('bush', 'holly', 'hydrangea'):
        rx = 16 * s
        it['shape'] = ['ellipse', x, y - 2, round(rx * 0.8, 1), round(rx * 0.65 * 0.5, 1)]
    if layer:
        it['layer'] = layer
    return it


def in_rect(x, y, r):
    return r[0] <= x < r[0] + r[2] and r[1] <= y < r[1] + r[3]


def scatter(M, rng):
    """Seeded pooled foliage plus small props, kept off paths, water, plazas, the cliff band and landmark keep-outs."""
    blocked = M['path_hard'] | M['water'] | M['plaza'] | M['band'] | M['keep']
    crown = M['path_soft'] | M['water'] | M['plaza'] | M['keep']
    glowy_rects = [[1290, 1090, 1270, 350], [0, 860, 640, 580], [700, 1460, 700, 460], [2560, 960, 700, 480],
                   [3300, 1580, 540, 580]]

    def tree_ok(x, y):
        if blocked[y, x] or not (6 < x < W - 4 and 30 < y < H):
            return False
        return not any(crown[y + dy, x + dx] for dx in (-30, 0, 30) for dy in (-40, -80, -118)
                       if 0 <= y + dy < H and 0 <= x + dx < W)

    def tree_r(x, y):
        if x < 200 and y < 820:
            return 44
        return 74 if M['top'][y, x] else 82

    items = []
    for (x, y, _) in poisson(rng, tree_ok, tree_r, 20000):
        x, y = int(x), int(y)
        wet = near_water(M, x, y, 6)
        if x < 190 and y < 820:
            sp = 'conifer'
        elif wet and rng.random() < 0.6:
            sp = 'willow'
        else:
            sp = 'conifer' if rng.random() < (0.62 if M['top'][y, x] else 0.5) else 'oak'
        it = plant(rng, sp, x, y)
        if sp != 'conifer' and rng.random() < 0.25:
            it['emit'] = 'leaves'
        items.append(it)
    trunk_pts = [(it['at'][0], it['at'][1], 22) for it in items]
    for x in range(40, W, 150):
        items.append(plant(rng, 'oak', x + int(rng.integers(-30, 30)), H + 96, 'fg'))
    for y in range(60, 800, 110):
        items.append(plant(rng, 'oak', -34 + int(rng.integers(0, 20)), y, 'fg'))

    soft = M['path_soft'] | M['water'] | M['plaza'] | M['band'] | M['keep']
    props, glow = [], []

    def ok_small(x, y):
        return not soft[y, x] and 6 < x < W - 6 and 8 < y < H - 4 and not M['path_hard'][y, x]

    for (x, y, _) in poisson(rng, ok_small, lambda x, y: 34, 20000, trunk_pts):
        x, y = int(x), int(y)
        roll = rng.random()
        wet = near_water(M, x, y, 4)
        glowy = wet or any(in_rect(x, y, r) for r in glowy_rects)
        if wet and roll < 0.45:
            props.append({'kind': 'reeds', 'at': [x, y], 'n': int(rng.integers(7, 12)), 'seed': int(rng.integers(1, 999))})
        elif glowy and roll < 0.5:
            glow.append(plant(rng, 'glowflora', x, y))
        elif roll < 0.36:
            r2 = rng.random()
            items.append(plant(rng, 'holly' if r2 < 0.25 else 'hydrangea' if r2 < 0.35 else 'bush', x, y))
        elif roll < 0.64:
            items.append(plant(rng, 'fern', x, y))
        elif roll < 0.74:
            props.append({'kind': 'rock', 'at': [x, y], 'r': [int(rng.integers(6, 12)), int(rng.integers(4, 7))],
                          'seed': int(rng.integers(1, 999)), 'walk': bool(rng.random() < 0.4)})
        elif roll < 0.8:
            props.append({'kind': 'mushrooms', 'at': [x, y], 'seed': int(rng.integers(1, 999))})
        elif roll < 0.86:
            if rng.random() < 0.5:
                props.append({'kind': 'stump', 'at': [x, y], 'r': int(rng.integers(7, 10)), 'seed': int(rng.integers(1, 999))})
            else:
                props.append({'kind': 'log', 'at': [x, y], 'length': int(rng.integers(40, 64)), 'radius': 6,
                              'seed': int(rng.integers(1, 999))})
        elif rng.random() < 0.15:
            glow.append(plant(rng, 'glowflora', x, y))
        else:
            items.append(plant(rng, 'fern', x, y))

    for (x, y, _) in poisson(rng, lambda x, y: not M['water'][y, x] and not M['plaza'][y, x] and not M['band'][y, x],
                             lambda x, y: 34, 13500, [(it['at'][0], it['at'][1], 14) for it in items]):
        r = rng.random()
        items.append(plant(rng, 'meadow' if r < 0.18 else 'tallgrass' if r < 0.45 else 'tuft', int(x), int(y)))
    return items, props, glow


def road_lantern_points(M):
    """Lanterns every ~100 px along the road and the toll road, alternating sides 22 px off centre, skipping junctions and bridges."""
    pts, side = [], 1
    road = PATHS['road'][0] + PATHS['toll_road'][0][1:]
    skip = [(900, 580), (2298, 597), (1466, 575), (1600, 585), (780, 585), (430, 560), (2470, 612), (2820, 670),
            (2980, 690), (3360, 690), (3540, 700)]
    acc = 0.0
    for (x0, y0), (x1, y1) in zip(road[:-1], road[1:]):
        seg = math.hypot(x1 - x0, y1 - y0)
        nx, ny = -(y1 - y0) / seg, (x1 - x0) / seg
        t = 0.0
        while t < seg:
            if acc <= 0:
                px, py = x0 + (x1 - x0) * t / seg, y0 + (y1 - y0) * t / seg
                if min(math.hypot(px - a, py - b) for a, b in skip) > 48:
                    lx, ly = int(px + nx * 24 * side), int(py + ny * 24 * side)
                    if not M['water'][ly, lx]:
                        pts.append([lx, ly])
                        side = -side
                acc = 100.0
            step = min(seg - t, acc)
            t += step
            acc -= step
    return pts


def ring(c, r, angles, color, hgt):
    """Rune stones on an ellipse (ring_stones without its str-index seed bug)."""
    return [{'kind': 'rune_stone', 'at': [round(c[0] + math.cos(math.radians(a)) * r[0]), round(c[1] + math.sin(math.radians(a)) * r[1])],
             'seed': k + 1, 'height': hgt - 4 * (k % 3), 'color': color} for k, a in enumerate(angles)]


def hand_props():
    """Landmark props drawn by pixel-scene kinds."""
    p = [
        {'kind': 'gate', 'at': [900, 580], 'span': 60, 'height': 84, 'seed': 11},
        {'kind': 'signpost', 'at': [470, 534]}, {'kind': 'lantern', 'at': [452, 520]},
        {'kind': 'signpost', 'at': [1640, 560]},
        {'kind': 'dais', 'at': [800, 214]},
        {'kind': 'hokora', 'at': [2500, 578], 'color': [255, 170, 80]},
        {'kind': 'stone_lantern', 'at': [2464, 586], 'energy': 0.8, 'radius': 60},
        {'kind': 'stone_lantern', 'at': [2536, 586], 'energy': 0.8, 'radius': 60},
        {'kind': 'hokora', 'at': [2256, 170], 'color': [140, 200, 255]},
        {'kind': 'stone_lantern', 'at': [1446, 300], 'energy': 0.8, 'radius': 60},
        {'kind': 'stone_lantern', 'at': [1490, 300], 'energy': 0.8, 'radius': 60},
        {'kind': 'stone_lantern', 'at': [1440, 410], 'energy': 0.8, 'radius': 60},
        {'kind': 'stone_lantern', 'at': [1494, 410], 'energy': 0.8, 'radius': 60},
        {'kind': 'campfire', 'at': [1000, 1320], 'seats': [[-30, -6, 32], [26, 12, 28]]},
        {'kind': 'pillar', 'at': [1060, 180]}, {'kind': 'pillar', 'at': [1128, 168]}, {'kind': 'pillar', 'at': [1150, 250]},
        {'kind': 'rune_stone', 'at': [1090, 236], 'height': 40, 'color': [190, 130, 255], 'seed': 4},
        {'kind': 'pillar', 'at': [1462, 870]}, {'kind': 'pillar', 'at': [1530, 858]}, {'kind': 'pillar', 'at': [1566, 928]},
        {'kind': 'pillar', 'at': [1450, 940]}, {'kind': 'log', 'at': [1500, 960], 'length': 60, 'radius': 7, 'seed': 3},
        {'kind': 'rock', 'at': [1600, 910], 'r': [12, 7]},
        {'kind': 'mushrooms', 'at': [1580, 880]},
    ]
    p += [{'kind': 'mushrooms', 'at': [round(304 + 58 * math.cos(a)), round(1316 + 30 * math.sin(a))], 'seed': 30 + k}
          for k, a in enumerate(np.linspace(0, 2 * math.pi, 9, endpoint=False))]
    p += [{'kind': 'stump', 'at': [304, 1324], 'r': 9}]
    p += ring((1480, 1350), (48, 22), (200, 250, 300, 345, 30, 150), [120, 220, 255], 40)
    p += ring((800, 226), (96, 54), (190, 230, 310, 350, 20, 160), [190, 130, 255], 46)
    p += [{'kind': 'bridge', 'at': [x, y], 'span': s, 'width': w} for x, y, s, w in BRIDGES]
    p += [{'kind': 'rock', 'at': [x, y], 'r': [10, 6], 'walk': True} for x, y in ((2090, 820), (2110, 930), (2380, 840), (2350, 930))]
    return p + east_props() + south_props()


def east_props():
    """Ravenscar Heights, Owlwatch Ridge, Toll Road, Gravefern Hollow, Drowned Chapel, Hanging Woods, Wolfsden, Moonwell."""
    p = [{'kind': 'dais', 'at': [3120, 130]}]
    p += ring((3120, 140), (84, 44), (200, 240, 300, 340, 20, 160), [190, 130, 255], 44)
    p += ring((2760, 380), (40, 20), (200, 270, 340, 30, 150), [120, 170, 255], 32)
    p += [
        {'kind': 'stone_lantern', 'at': [3290, 350], 'energy': 0.8, 'radius': 60},
        {'kind': 'stone_lantern', 'at': [3342, 350], 'energy': 0.8, 'radius': 60},
        {'kind': 'hokora', 'at': [3600, 420], 'color': [120, 170, 255]},
        {'kind': 'stone_lantern', 'at': [3562, 440], 'energy': 0.8, 'radius': 60, 'color': [140, 190, 255]},
        {'kind': 'stone_lantern', 'at': [3638, 440], 'energy': 0.8, 'radius': 60, 'color': [140, 190, 255]},
        {'kind': 'gate', 'at': [2980, 690], 'span': 60, 'height': 84, 'seed': 13},
        {'kind': 'signpost', 'at': [2940, 660]}, {'kind': 'signpost', 'at': [3380, 670]},
        {'kind': 'stone_lantern', 'at': [2880, 910], 'energy': 0.9, 'radius': 70, 'color': [120, 200, 255]},
    ]
    p += [{'kind': 'rock', 'at': [round(2860 + 26 * math.cos(a)), round(900 + 14 * math.sin(a))], 'r': [7, 5], 'seed': 300 + k}
          for k, a in enumerate(np.linspace(0, 2 * math.pi, 8, endpoint=False))]
    p += [{'kind': 'rune_stone', 'at': [3640 + 44 * i, 800 + 34 * j + (i % 2) * 6], 'height': 24 + (i * 3 + j) % 4 * 2,
           'color': [120, 220, 170], 'seed': 310 + i * 3 + j} for i in range(3) for j in range(3)]
    p += [{'kind': 'pillar', 'at': [round(2980 + 138 * math.cos(math.radians(a))), round(1300 + 66 * math.sin(math.radians(a)))],
           'seed': 330 + k} for k, a in enumerate((200, 240, 300, 340, 20, 160))]
    p += [{'kind': 'stone_lantern', 'at': [2930, 1222], 'energy': 0.8, 'radius': 60, 'color': [120, 220, 200]}]
    p += [{'kind': 'rock', 'at': [x, y], 'r': [rx, ry], 'seed': 340 + k} for k, (x, y, rx, ry) in enumerate(
        [(2960, 1630, 20, 13), (3004, 1648, 16, 10), (2940, 1662, 14, 9), (3030, 1620, 12, 8), (2990, 1600, 10, 7)])]
    p += [{'kind': 'log', 'at': [2990, 1690], 'length': 64, 'radius': 8, 'seed': 350}, {'kind': 'stump', 'at': [2920, 1610], 'r': 9}]
    p += ring((3500, 1720), (74, 40), (210, 260, 300, 340, 20, 60, 120), [150, 200, 255], 40)
    p += [{'kind': 'rune_stone', 'at': [2860, 2000], 'height': 56, 'seed': 360, 'color': [120, 170, 255]},
          {'kind': 'stone_lantern', 'at': [3580, 2010], 'energy': 0.9, 'radius': 70},
          {'kind': 'signpost', 'at': [3624, 1990]}]
    return p


def south_props():
    """Barrow Downs, Weeping Mire, Woodcutter's Rest, Bone Orchard and Ossuary Arch."""
    p = ring((180, 1640), (72, 36), (200, 250, 290, 340, 30, 150), [255, 120, 90], 42)
    p += [{'kind': 'stump', 'at': [180, 1648], 'r': 11},
          {'kind': 'rune_stone', 'at': [240, 1960], 'height': 50, 'seed': 400, 'color': [255, 150, 90]},
          {'kind': 'rock', 'at': [212, 1976], 'r': [9, 6], 'seed': 401}, {'kind': 'rock', 'at': [266, 1972], 'r': [8, 5], 'seed': 402},
          {'kind': 'campfire', 'at': [1620, 1600], 'seats': [[-32, -6, 32], [28, 12, 30]]},
          {'kind': 'log', 'at': [1560, 1560], 'length': 70, 'radius': 8, 'seed': 403},
          {'kind': 'stump', 'at': [1690, 1560], 'r': 10}, {'kind': 'stump', 'at': [1600, 1980], 'r': 13},
          {'kind': 'log', 'at': [1650, 2000], 'length': 58, 'radius': 7, 'seed': 404},
          {'kind': 'gate', 'at': [2300, 1990], 'span': 56, 'height': 80, 'seed': 14}]
    return p


def lights(rng, M):
    """Moon pools at clearings and fireflies, at least four per screen."""
    out = [{'kind': 'moon_pool', 'at': a, 'color': [170, 200, 255], 'energy': e, 'radius': r, 'z': 60}
           for a, e, r in (([800, 230], 1.4, 160), ([1600, 590], 1.0, 130), ([2200, 840], 1.2, 170),
                           ([1760, 1200], 1.0, 170), ([1700, 360], 1.0, 150), ([779, 1010], 0.6, 120), ([1100, 210], 0.8, 120),
                           ([3120, 150], 1.2, 160), ([2760, 390], 0.8, 120), ([3684, 850], 0.9, 140), ([3500, 1720], 1.3, 160),
                           ([180, 1650], 0.9, 140), ([2300, 1640], 0.8, 150), ([2980, 1280], 0.9, 160), ([1000, 1700], 0.7, 130))]
    k = 0
    for sy in range(0, H, SCREEN[1]):
        for sx in range(0, W, SCREEN[0]):
            n = 0
            while n < 4:
                x, y = int(sx + rng.uniform(40, 600)), int(sy + rng.uniform(40, 320))
                if M['water'][y, x] and rng.random() < 0.7:
                    continue
                out.append({'kind': 'firefly', 'at': [x, y], 'color': [255, 214, 120], 'energy': 0.7, 'radius': 30,
                            'z': 12, 'phase': round(k * 1.37 % 9, 2)})
                n, k = n + 1, k + 1
    return out


def spec():
    rng = np.random.default_rng(SEED)
    pond_polys = ponds()
    M = masks(pond_polys)
    items, scat, glow = scatter(M, rng)
    lamp = road_lantern_points(M)
    boundary_trunks = [[int(x), int(y), int(h)] for x, y, h in
                       zip(rng.uniform(70, 170, 9), np.linspace(70, 760, 9) + rng.uniform(-20, 20, 9), rng.uniform(150, 210, 9))]
    boundary_trunks = [t for t in boundary_trunks if not M['path_hard'][t[1], t[0]]]
    orchard = [[int(x), int(y), int(h)] for x, y, h in zip(rng.uniform(2110, 2690, 40), rng.uniform(1500, 1960, 40), rng.uniform(110, 170, 40))]
    orchard = [t for t in orchard if not (M['path_hard'][t[1], t[0]] or M['water'][t[1], t[0]])][:14]
    items += [dict(plant(rng, 'oak', 3620, 1250), v=POOL_N['oak'] - 1, s=SIZES['oak'][1]),
              dict(plant(rng, 'willow', 1060, 1560), v=POOL_N['willow'] - 1, s=SIZES['willow'][1])]
    px, py = zip(*pond_polys[0])
    box = [min(px) - 40, min(py) - 40, max(px) + 40, max(py) + 40]
    lamp += [[3570, 1290], [3672, 1282], [3600, 1318], [970, 1990], [1030, 1990], [3600, 1960]]
    extras = [
        {'module': EXTRAS, 'fn': 'boundary_dark', 'at': [0, 0], 'rect': [0, 0, 560, 860], 'depth': 230, 'trunks': boundary_trunks},
        {'module': EXTRAS, 'fn': 'road_lanterns', 'at': lamp[0], 'pts': lamp, 'height': 62},
        {'module': EXTRAS, 'fn': 'watching_tree', 'at': [330, 1074]},
        {'module': EXTRAS, 'fn': 'hollowmere_spire', 'at': [1915, 436], 'height': 340},
        {'module': EXTRAS, 'fn': 'hollowmere_spire', 'at': [3560, 150], 'height': 230, 'seed': 29, 'name': 'dw_spire2',
         'beacon': [110, 160, 255]},
        {'module': EXTRAS, 'fn': 'bare_trunks', 'at': orchard[0][:2], 'trunks': orchard},
        {'module': EXTRAS, 'fn': 'crimson_runestone', 'at': [779, 1004], 'height': 66},
        {'module': EXTRAS, 'fn': 'red_mushrooms', 'at': [262, 1096], 'pts': [[262, 1096], [402, 1092], [236, 1132], [430, 1126], [290, 1150]]},
        {'module': EXTRAS, 'fn': 'forest', 'at': items[0]['at'], 'items': items + glow, 'pool': POOL_N},
        {'module': EXTRAS, 'fn': 'blackwater', 'at': [POOL[0], POOL[1]]},
        {'module': EXTRAS, 'fn': 'blackwater_shore', 'at': [POOL[0], POOL[1]], 'box': box,
         'items': [it for it in items if it.get('layer') != 'fg' and box[0] - 60 <= it['at'][0] <= box[2] + 60
                   and box[1] - 160 <= it['at'][1] <= box[3]]},
        {'module': EXTRAS, 'fn': 'mist', 'at': [1640, 1300],
         'pts': [[b[0], b[1] + 10, b[2] * 2] for b in BOG + MIRE] +
                [[1500, 1200, 160], [1980, 1290, 140], [2300, 760, 80], [POOL[0] - 90, POOL[1] + 40, 150],
                 [POOL[0] + 80, POOL[1] + 10, 170], [2980, 1330, 200], [3500, 1740, 80], [2400, 1900, 160]]},
    ]
    goals = {f'zone {n}': g for n, _, g in ZONES}
    goals.update({k: v for k, v in PROP_GOALS.items()})
    goals.update({'spire door': [1915, 456], 'spring': [2246, 196], 'witch ring': [304, 1300], 'camp': [1010, 1290],
                  'echo stones': [1480, 1336], 'colonnade': [1540, 896], 'ruins': [1090, 214], 'moon shrine': [2470, 612],
                  'raven altar': [3220, 140], 'ravenscar spire': [3560, 180], 'gloam shrine': [3600, 440],
                  'moonwell': [3420, 1790], 'last lantern': [3600, 1975], 'ossuary arch': [2300, 1960]})
    look = {'ambient': [40, 46, 98], 'moon': {'color': [150, 185, 255], 'energy': 0.5, 'height': 0.6},
            'moon_reflect': [2220, 850], 'waterline': -1, 'rays': 0.26, 'haze': [0.1, 0.12, 0.26],
            'falling': [0.45, 0.75, 0.6], 'motes': True, 'dof': 0.0}
    ground = {'seed': 33, 'base': 'grass', 'moss': 0.6, 'top_shadow': 50, 'tufts': 90000, 'leaves': 0.0002,
              'leaf_pals': ['R0', 'W1', 'E1', 'V1', 'E0'], 'flower_rate': 0.0003,
              'flowers': [['N10', [120, 170, 255], 0.45], ['V5', [190, 120, 255], 0.4], ['M3', [255, 120, 200], 0.35]]}
    fog = {'water': 0.3, 'top': 0.5, 'bottom': 0.35,
           'clear': [{'at': [1330, 590], 'r': [120, 50]}, {'at': [1915, 470], 'r': [80, 40]}]}
    game = {
        'id': 'darkwood', 'day': False, 'glow': True, 'plateau': 'Hollowmere Plateau',
        'terraces': [{k: RAVEN[k] for k in ('name', 'poly', 'height', 'stairs', 'elevation')}],
        'spawn': {'player': [1330, 600], 'agents': [1250, 590]},
        'zones': [{'name': n, 'rect': r} for n, r, _ in ZONES],
        'landmarks': [{'name': n, 'at': a, 'tall': t} for n, a, t in LANDMARKS],
        'props': GAME_PROPS,
        'extras': extras,
    }
    return {
        'name': 'The Dark Wood', 'size': [W, H], 'period': 9.0, 'look': look, 'ground': ground, 'cliff': CLIFF,
        'water': {'ponds': pond_polys, 'streams': STREAMS, 'crossings': CROSSINGS},
        'paths': [{'pts': pts, 'width': w} for pts, w in PATHS.values()],
        'plazas': PLAZAS, 'moon_gap': [800, 150], 'fog': fog, 'trees': [],
        'props': hand_props() + scat, 'lights': lights(rng, M),
        'walker': {'start': [1330, 600], 'radius': 6, 'goals': goals},
        'game': game,
    }


if __name__ == '__main__':
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, 'darkwood.json')
    s = spec()
    json.dump(s, open(out, 'w'), indent=1)
    print(f'SPEC {out} trees {len(s["trees"])} props {len(s["props"])} lights {len(s["lights"])} '
          f'extras {len(s["game"]["extras"])}')
