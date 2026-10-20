#!/usr/bin/env python3
"""Magic Forest (day) world spec: hand-placed layout + seeded Poisson-disc scatter -> magic_forest.json.
usage: magic_forest.py [OUT.json]"""
import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

SKILL = os.path.expanduser(os.environ.get('PIXEL_SCENE', '~/.claude/skills/pixel-scene/scripts'))
sys.path.insert(0, SKILL)
import art  # noqa: E402
import terrain  # noqa: E402

W, H = 3840, 2160
SEED = 714
EXTRAS = 'tools/worldgen/worlds/magic_forest_extras.py'
HERE = os.path.dirname(os.path.abspath(__file__))

RIM = [(-4, 930), (150, 915), (330, 925), (500, 950), (640, 985), (700, 1030)]
CLIFF = {'poly': RIM + [(690, 1070), (620, 1112), (596, 1134), (546, 1134), (480, 1185), (340, 1245), (180, 1280),
                       (-4, 1295)],
         'height': 50, 'stairs': [556, 586], 'fall': [300, 318]}
BLUFF = {'name': 'Skyroot Bluff', 'height': 60, 'stairs': [3150, 3182],
         'poly': [(2770, -4), (3844, -4), (3844, 600), (3700, 622), (3560, 640), (3420, 630), (3300, 612), (3196, 612),
                  (3136, 612), (3080, 598), (2980, 572), (2880, 540), (2810, 500), (2776, 420), (2764, 260)]}


def lobe(cx, cy, rx, ry, seed, n=28):
    """Noisy ellipse polygon for a lake lobe."""
    r = np.random.default_rng(seed)
    ph = r.uniform(0, 6.3, 3)
    pts = []
    for k in range(n):
        a = 2 * math.pi * k / n
        f = 1 + 0.05 * math.sin(3 * a + ph[0]) + 0.035 * math.sin(5 * a + ph[1]) + 0.02 * math.sin(8 * a + ph[2])
        pts.append([round(cx + math.cos(a) * rx * f), round(cy + math.sin(a) * ry * f)])
    return pts


def lake(cx, cy, parts, seed, blur=36, n=96):
    """One organic lake: smooth union of ellipses (blurred raster) traced radially from (cx, cy)."""
    pad = blur * 3
    x0, y0 = int(min(e[0] - e[2] for e in parts)) - pad, int(min(e[1] - e[3] for e in parts)) - pad
    x1, y1 = int(max(e[0] + e[2] for e in parts)) + pad, int(max(e[1] + e[3] for e in parts)) + pad
    im = Image.new('L', (x1 - x0, y1 - y0))
    d = ImageDraw.Draw(im)
    for ex, ey, rx, ry in parts:
        d.ellipse([ex - rx - x0, ey - ry - y0, ex + rx - x0, ey + ry - y0], fill=255)
    m = np.array(im.filter(ImageFilter.GaussianBlur(blur))) > 100
    ph = np.random.default_rng(seed).uniform(0, 6.3, 3)
    pts = []
    for k in range(n):
        a = 2 * math.pi * k / n
        dx, dy = math.cos(a), math.sin(a)
        t = 0
        while m[int(cy - y0 + dy * (t + 1)), int(cx - x0 + dx * (t + 1))]:
            t += 1
        f = 1 + 0.025 * math.sin(3 * a + ph[0]) + 0.018 * math.sin(7 * a + ph[1]) + 0.01 * math.sin(13 * a + ph[2])
        pts.append([round(cx + dx * t * f), round(cy + dy * t * f)])
    return pts


WATER = {
    'ponds': [lake(2170, 880, [(2150, 780, 165, 100), (2195, 985, 160, 82), (2172, 884, 150, 90)], 1),
              lobe(3520, 900, 120, 58, 3), lobe(2900, 862, 52, 28, 4), lobe(1560, 1660, 110, 48, 5),
              lobe(1790, 1720, 84, 40, 6), lobe(1660, 1840, 96, 40, 7), lobe(1880, 1900, 60, 30, 8), lobe(452, 1112, 22, 11, 9)],
    'streams': [
        {'pts': [[1990, -4], [1972, 110], [1955, 250], [1948, 380], [1950, 480], [1975, 580], [2030, 650], [2075, 705]],
         'width': 16},
        {'pts': [[440, 1120], [418, 1140], [384, 1146], [356, 1162], [350, 1190], [332, 1214], [314, 1234], [309, 1256]],
         'width': 12},
        {'pts': [[309, 1302], [360, 1324], [470, 1335], [600, 1310], [760, 1272], [920, 1262], [1060, 1270],
                 [1140, 1240], [1172, 1190], [1180, 1140], [1220, 1095], [1330, 1070], [1500, 1080], [1680, 1090],
                 [1840, 1060], [1960, 1030], [2010, 1012], [2060, 1004]], 'width': 20},
        {'pts': [[2325, 1008], [2420, 1040], [2500, 1050], [2600, 1060], [2700, 1090], [2800, 1150], [2880, 1240],
                 [2930, 1360], [2940, 1480], [2910, 1600], [2884, 1720], [2886, 1840], [2924, 1960], [2958, 2080],
                 [2976, 2164]], 'width': 18},
    ],
    'crossings': [[1929, 289, 1975, 312], [1146, 1165, 1202, 1188], [2000, 879, 2344, 903],
                  [472, 1306, 500, 1362], [2458, 1022, 2486, 1072], [2912, 1408, 2966, 1432], [2858, 1768, 2912, 1792],
                  [2636, 1050, 2666, 1102]],
}

PATHS = [
    # main loop, west half: Hollow -> Hokora -> Amberviolet -> Cerulean -> Portal -> Hollow
    {'pts': [[1300, 840], [1120, 770], [970, 600], [720, 470], [560, 480], [440, 580], [470, 760], [640, 880],
             [790, 990], [1000, 945], [1300, 840]], 'width': 18},
    # main loop, east half: Hollow -> Spiral Meadow -> Resting Oak -> north bridge -> lake bridge -> Hollow
    {'pts': [[1300, 840], [1230, 700], [1260, 560], [1420, 450], [1600, 400], [1850, 310], [1952, 300], [2100, 310],
             [2330, 440], [2470, 600], [2470, 820], [2300, 891], [2170, 891], [2040, 893], [1800, 900], [1500, 860],
             [1300, 840]], 'width': 16},
    # south loop over Southbrook Bridge, Sunken Pillars, Sun Stones and the outflow ford
    {'pts': [[1240, 900], [1140, 1040], [1125, 1176], [1174, 1176], [1225, 1180], [1420, 1230], [1650, 1300],
             [1900, 1240], [2120, 1180], [2330, 1270], [2450, 1170], [2471, 1047], [2470, 900]], 'width': 14},
    # shortcut: Hokora -> Moss Gate -> Resting Oak
    {'pts': [[970, 600], [965, 440], [960, 330], [1080, 230], [1300, 210], [1480, 290], [1600, 400]], 'width': 12},
    # branch: portal -> plateau stairs -> Deep Forest Edge
    {'pts': [[740, 1030], [690, 1140], [571, 1192], [571, 1118], [440, 1066], [300, 1056], [230, 1125]], 'width': 13},
    # branch: stairs foot -> ford -> falls pool
    {'pts': [[590, 1195], [490, 1290], [486, 1340], [460, 1385], [330, 1360]], 'width': 11},
    # branch: Amberviolet -> Fallen Giant
    {'pts': [[560, 480], [400, 370], [262, 296]], 'width': 11},
    # east: Resting Oak loop -> Fernfall Dell -> Skyroot Bluff stair -> bluff top -> Skyroot -> Menhirs / Eyrie
    {'pts': [[2470, 600], [2620, 640], [2760, 700], [2900, 760], [3040, 720], [3166, 690], [3166, 640], [3166, 590],
             [3240, 520], [3380, 400], [3500, 420], [3640, 500]], 'width': 16},
    {'pts': [[3240, 520], [3120, 420], [2980, 300], [2940, 470]], 'width': 12},
    # east: bluff stair foot -> Willowbank -> Hare Meadow -> Bramble Gate -> Thornwood Camp
    {'pts': [[3166, 690], [3300, 780], [3380, 1000], [3460, 1180], [3520, 1300], [3540, 1460], [3500, 1650],
             [3520, 1820], [3560, 1960]], 'width': 15},
    # Fernfall Dell -> Millrace Ruins -> Mill Bridge -> Hare Meadow
    {'pts': [[2900, 760], [2860, 900], [2760, 980], [2652, 1030], [2650, 1076], [2652, 1120], [2690, 1200], [2760, 1340], [2860, 1418], [2939, 1420],
             [3020, 1420], [3200, 1360], [3380, 1310], [3520, 1300]], 'width': 13},
    # south trail: falls pool -> Foxglove -> Hermit's Knoll -> Reedwater Fen -> Old Quarry -> Heron Bridge -> Thornwood
    {'pts': [[330, 1360], [320, 1500], [330, 1640], [520, 1740], [800, 1720], [1000, 1700], [1240, 1720],
             [1440, 1760], [1700, 1770], [1960, 1780], [2300, 1760], [2600, 1790], [2830, 1780], [2885, 1780],
             [2960, 1780], [3200, 1800], [3500, 1820]], 'width': 15},
    # south loop -> Reedwater Fen; Hermit's Knoll -> woodpile; Foxglove -> Boundary Stone; Quarry -> steps
    {'pts': [[1650, 1300], [1640, 1420], [1680, 1560], [1700, 1770]], 'width': 12},
    {'pts': [[1000, 1700], [980, 1840], [960, 1960]], 'width': 11},
    {'pts': [[330, 1640], [260, 1820], [220, 1990]], 'width': 11},
    {'pts': [[2300, 1760], [2300, 1880], [2280, 1990]], 'width': 11},
    {'pts': [[1440, 1760], [1480, 1880], [1500, 1960]], 'width': 11},
    {'pts': [[2600, 1790], [2660, 1880], [2705, 1950]], 'width': 11},
    # Old Quarry north -> Sunstone Rise
    {'pts': [[2300, 1760], [2300, 1620], [2290, 1440], [2330, 1272]], 'width': 12},
]

PLAZAS = [
    {'at': [790, 1000], 'r': [70, 42], 'broken': 0.22, 'runes': [120, 170, 255], 'groove_pal': 'T4', 'glyph_pal': 'T7'},
    {'at': [2330, 1272], 'r': [46, 28], 'broken': 0.4, 'runes': [255, 200, 110], 'groove_pal': 'G1', 'glyph_pal': 'G3'},
    {'at': [2980, 240], 'r': [64, 38], 'broken': 0.45, 'runes': [200, 230, 255], 'groove_pal': 'N9', 'glyph_pal': 'N10'},
    {'at': [3520, 1300], 'r': [56, 32], 'broken': 0.2},
    {'at': [2300, 1600], 'r': [76, 42], 'broken': 0.55},
]

ZONES = [  # name, rect, walker goal (walkable point near the centre)
    ('Whispering Hollow', [1110, 740, 480, 300], [1300, 860]),
    ('Spiral Meadow', [1130, 460, 480, 280], [1240, 600]),
    ('Resting Oak', [1340, 120, 560, 340], [1600, 395]),
    ('Mirror Lake', [1930, 620, 630, 480], [2090, 893]),
    ('Cerulean Ring', [60, 560, 560, 300], [400, 700]),
    ('Amberviolet Glade', [120, 300, 620, 260], [520, 490]),
    ('Deep Forest Edge', [0, 940, 640, 360], [330, 1055]),
    ('Runestone Portal', [670, 880, 460, 300], [830, 1020]),
    ('Moss Gate', [700, 160, 520, 330], [965, 452]),
    ('Southbrook Ruins', [1240, 1130, 760, 300], [1600, 1280]),
    ('Shimmer Run', [1960, 40, 600, 560], [2200, 372]),
    ('Sunstone Rise', [2120, 1110, 440, 330], [2290, 1215]),
    ('Skyroot Bluff', [2780, 40, 1060, 560], [3240, 520]),
    ('Fernfall Dell', [2580, 700, 620, 360], [2900, 760]),
    ('Willowbank', [3220, 700, 620, 420], [3380, 1000]),
    ('Millrace Ruins', [2580, 1080, 640, 440], [2690, 1200]),
    ('Hare Meadow', [3240, 1140, 600, 420], [3460, 1180]),
    ('Heron Reach', [2560, 1560, 640, 580], [2600, 1790]),
    ('Thornwood', [3220, 1580, 620, 560], [3520, 1820]),
    ('Foxglove Fields', [40, 1480, 640, 420], [320, 1500]),
    ("Hermit's Knoll", [720, 1500, 600, 460], [1000, 1720]),
    ('Reedwater Fen', [1360, 1500, 680, 460], [1700, 1770]),
    ('Old Quarry', [2060, 1480, 480, 560], [2300, 1760]),
]

LANDMARKS = [
    ('Fallen Giant', [240, 268], False), ('Moss Gate', [960, 330], False), ('The Resting Oak', [1580, 340], True),
    ('Shimmer Run Bridge', [1952, 300], False), ('Amberviolet Roots', [450, 495], False),
    ('Wayside Hokora', [960, 560], False), ('Spiral Wildflowers', [1350, 650], False),
    ('Shimmerfish Pool', [1950, 470], False), ('The Living Wall', [330, 935], False),
    ('The Runestone Portal', [790, 995], True), ('Hollow Campfire', [1440, 880], False),
    ('Mirror Lake Bridge', [2170, 890], False), ('Deep Forest Falls', [309, 1285], False),
    ('Southbrook Bridge', [1174, 1176], False), ('Sunken Pillars', [1650, 1290], False),
    ('Sun Stones', [2330, 1270], False), ('Cerulean Ring', [340, 650], False), ('Deep Forest Edge', [230, 1150], False),
    ('Windworn Menhirs', [2980, 240], False), ('The Skyroot', [3420, 300], True), ('Bluff Lookout', [2925, 480], False),
    ('Bluff Stair', [3166, 690], False), ('Eyrie Shrine', [3640, 500], False), ('Fern Spring', [2900, 862], False),
    ('Kingfisher Pond', [3520, 900], False), ('Old Millstones', [2680, 1250], False), ('Mill Bridge', [2939, 1420], False),
    ('Meadow Dais', [3520, 1300], False), ('Heron Bridge', [2885, 1780], False), ('Bramble Gate', [3500, 1650], False),
    ('Twin Lantern Waymark', [2705, 1960], False), ('Thornwood Camp', [3560, 1980], False),
    ('Foxglove Ring', [330, 1640], False), ('Boundary Stone', [220, 1995], False), ("Hermit's Fire", [1000, 1660], False),
    ("Hermit's Woodpile", [960, 1965], False), ('Reedwater Pools', [1560, 1600], False), ('Fen Hokora', [1500, 1965], False),
    ('Quarry Pillars', [2300, 1600], False), ('Quarry Steps', [2280, 1995], False),
]

PROPS = {  # old prop id -> at, size, walker goal
    'prop_49480': ([790, 990], [84, 40], [830, 1020]),      # The Runestone Portal
    'prop_189094': ([340, 650], [120, 70], [400, 668]),     # Cerulean Mushroom Ring
    'prop_218917': ([452, 500], [50, 30], [500, 505]),      # Amberviolet Fungi
    'prop_14598': ([1350, 650], [110, 70], [1270, 640]),    # Spiral Wildflowers
    'prop_80039': ([2060, 880], [120, 60], [2060, 893]),    # The Mirror Lake
    'prop_118646': ([230, 1150], [100, 50], [232, 1128]),   # The Deep Forest Edge
    'prop_136309': ([1950, 470], [40, 30], [1928, 470]),    # The Shimmerfish
    'prop_164380': ([1580, 360], [90, 40], [1580, 405]),    # The Resting Oak
}

HAND_TREES = [
    ('oak', [1580, 340], 2.4, 7), ('oak', [410, 450], 1.9, 21), ('oak', [530, 420], 1.6, 22),
    ('blossom', [880, 300], 1.5, 31), ('blossom', [1060, 330], 1.4, 32), ('willow', [1915, 760], 1.6, 41),
    ('willow', [2400, 700], 1.7, 42), ('willow', [2030, 1110], 1.5, 43), ('willow', [2330, 1100], 1.4, 44),
    ('blossom', [1460, 560], 1.5, 33), ('blossom', [1170, 520], 1.4, 34), ('oak', [1160, 690], 1.7, 23),
    ('oak', [1600, 760], 1.8, 24), ('oak', [1060, 860], 1.6, 25),
    ('willow', [700, 1240], 1.5, 45), ('oak', [930, 1170], 1.7, 26),
    ('oak', [3420, 300], 2.8, 8), ('willow', [3372, 850], 1.7, 46), ('willow', [3680, 830], 1.6, 47),
    ('blossom', [3380, 1240], 1.5, 35), ('blossom', [3680, 1360], 1.4, 36), ('blossom', [200, 1560], 1.5, 37),
    ('blossom', [560, 1820], 1.4, 38), ('oak', [1140, 1590], 1.9, 27), ('willow', [1420, 1690], 1.6, 48),
    ('willow', [1900, 1640], 1.5, 49), ('oak', [2560, 2000], 1.8, 28), ('oak', [2870, 1010], 1.8, 29),
]

# scatter mixes: region rect -> (tree species weights, tree radius, shrub weights, extra kinds)
MIXES = [  # name, rect, tree weights, tree spacing, shrub/fern weights, forest density (share of the noise field)
    ('plateau', None, {'pine': 0.85, 'oak': 0.15}, 46, {'holly': 0.5, 'bush': 0.2, 'fern': 1.6}, 0.75),
    ('amber', [80, 260, 700, 330], {'oak': 0.7, 'pine': 0.3}, 64, {'bush': 0.4, 'fern': 1.2}, 0.45),
    ('ring', [40, 560, 620, 280], {'pine': 0.75, 'oak': 0.25}, 60, {'holly': 0.4, 'bush': 0.4, 'fern': 1.0}, 0.4),
    ('meadow', [1120, 440, 520, 300], {'blossom': 0.5, 'oak': 0.5}, 90, {'hydrangea': 0.8, 'bush': 0.3, 'fern': 0.2}, 0.06),
    ('lake', [1900, 600, 660, 520], {'willow': 0.5, 'oak': 0.2, 'pine': 0.3}, 70, {'bush': 0.6, 'fern': 0.5}, 0.25),
    ('ne', [1960, 0, 600, 600], {'pine': 0.75, 'oak': 0.25}, 60, {'holly': 0.4, 'bush': 0.4, 'fern': 0.8}, 0.55),
    ('south', [1200, 1100, 1360, 340], {'oak': 0.35, 'pine': 0.55, 'blossom': 0.1}, 62, {'bush': 0.5, 'holly': 0.3, 'fern': 0.8}, 0.3),
    ('bluff', [2760, 0, 1080, 660], {'pine': 0.6, 'oak': 0.4}, 58, {'holly': 0.4, 'bush': 0.4, 'fern': 1.0}, 0.45),
    ('dell', [2560, 660, 640, 420], {'oak': 0.5, 'pine': 0.3, 'willow': 0.2}, 60, {'fern': 2.0, 'bush': 0.3}, 0.4),
    ('willowbank', [3200, 660, 640, 460], {'willow': 0.6, 'oak': 0.4}, 70, {'bush': 0.5, 'fern': 0.6, 'hydrangea': 0.4}, 0.3),
    ('hare', [3220, 1120, 620, 460], {'blossom': 0.6, 'oak': 0.4}, 90, {'hydrangea': 0.8, 'bush': 0.3}, 0.08),
    ('thorn', [3200, 1580, 640, 580], {'pine': 0.5, 'oak': 0.5}, 54, {'holly': 1.2, 'bush': 0.5, 'fern': 0.6}, 0.55),
    ('fox', [0, 1460, 720, 700], {'blossom': 0.5, 'oak': 0.5}, 84, {'hydrangea': 0.9, 'bush': 0.3, 'fern': 0.3}, 0.14),
    ('fen', [1340, 1480, 700, 680], {'willow': 0.6, 'oak': 0.2, 'pine': 0.2}, 70, {'bush': 0.4, 'fern': 0.8}, 0.25),
    ('default', [0, 0, W, H], {'oak': 0.35, 'pine': 0.55, 'blossom': 0.05, 'willow': 0.05}, 62,
     {'bush': 0.5, 'holly': 0.3, 'hydrangea': 0.2, 'fern': 0.9}, 0.28),
]

CLEAR = [  # (x, y, r_trees, r_small): kept open around landmarks and views
    (790, 985, 120, 70), (340, 650, 95, 62), (452, 500, 50, 26), (1580, 360, 120, 40), (1350, 650, 90, 64),
    (1440, 880, 70, 36), (1300, 840, 120, 40), (960, 565, 70, 50), (960, 330, 60, 34), (240, 268, 80, 64),
    (1650, 1290, 110, 80), (2330, 1270, 95, 70), (1950, 470, 40, 16), (309, 1310, 90, 40), (571, 1185, 70, 44), (571, 1118, 50, 40), (3166, 598, 50, 40),
    (2170, 890, 80, 30), (1174, 1176, 70, 30), (230, 1140, 60, 30), (486, 1335, 40, 20), (2471, 1047, 40, 20),
    (1952, 300, 60, 26), (1270, 640, 30, 18),
    (2980, 240, 110, 70), (3420, 300, 70, 30), (2925, 480, 50, 30), (3166, 690, 50, 30), (3640, 500, 70, 44),
    (2900, 862, 60, 30), (3520, 900, 40, 20), (2680, 1250, 90, 60), (2939, 1420, 50, 26), (3520, 1300, 100, 64),
    (2885, 1780, 50, 26), (3500, 1650, 60, 34), (2705, 1960, 50, 30), (3560, 1980, 70, 40), (330, 1640, 90, 60),
    (220, 1995, 50, 30), (1000, 1660, 70, 40), (960, 1965, 60, 40), (1560, 1600, 40, 20), (1500, 1965, 60, 40),
    (2300, 1600, 110, 76), (2280, 1995, 60, 44),
]


class Masks:
    """Keep-out masks at full art resolution for the scatter (paths, water, plazas, cliff, clearings)."""

    def __init__(self):
        spec = {'cliff': CLIFF}
        self.top, self.face, _, self.edge, _ = terrain.plateau(spec, W, H)
        self.btop, _, _, self.bedge, _ = terrain.plateau({'cliff': BLUFF}, W, H)
        self.paths = [art.smooth_path([tuple(p) for p in q['pts']], 8) for q in PATHS]
        self.streams = [art.smooth_path([tuple(p) for p in s['pts']], 6) for s in WATER['streams']]
        self.cache = {}

    def blocked(self, path_m, water_m, plaza_m, clear_idx):
        """Bool mask of cells closed to a kind with the given margins; clear_idx picks r_trees (2) or r_small (3)."""
        key = (path_m, water_m, plaza_m, clear_idx)
        if key in self.cache:
            return self.cache[key]
        im = Image.new('L', (W, H), 0)
        d = ImageDraw.Draw(im)
        for pts, q in zip(self.paths, PATHS):
            self._line(d, pts, q['width'] / 2 + path_m)
        for pts, s in zip(self.streams, WATER['streams']):
            self._line(d, pts, s['width'] / 2 + 2 + water_m)
        for pp in WATER['ponds']:
            d.polygon([tuple(p) for p in pp], fill=255)
            if water_m:
                d.line([tuple(p) for p in pp + pp[:1]], fill=255, width=int(2 * water_m))
        for x0, y0, x1, y1 in WATER['crossings']:
            d.rectangle([x0 - water_m, y0 - water_m, x1 + water_m, y1 + water_m], fill=255)
        for pz in PLAZAS:
            (x, y), (rx, ry) = pz['at'], pz['r']
            d.ellipse([x - rx - plaza_m, y - ry - plaza_m, x + rx + plaza_m, y + ry + plaza_m], fill=255)
        for c in CLEAR:
            x, y, r = c[0], c[1], c[clear_idx]
            d.ellipse([x - r, y - r, x + r, y + r], fill=255)
        m = np.array(im) > 0
        yy = np.arange(H)[:, None]
        m |= (yy >= self.edge[None, :] - 4) & (yy < self.edge[None, :] + CLIFF['height'] * 3 // 2 + 6) & self.top.any(0)[None, :]
        m |= (yy >= self.bedge[None, :] - 6) & (yy < self.bedge[None, :] + BLUFF['height'] * 3 // 2 + 6) & self.btop.any(0)[None, :]
        self.cache[key] = m
        return m

    @staticmethod
    def _line(d, pts, hw):
        pts = [tuple(p) for p in pts]
        d.line(pts, fill=255, width=int(2 * hw + 1))
        for x, y in pts:
            d.ellipse([x - hw, y - hw, x + hw, y + hw], fill=255)

    def on_plateau(self, x, y):
        return bool(self.top[int(y), int(x)])

    def rim_dist(self, x, y):
        """Rows from (x, y) up to the first lowland row (distance inside the plateau from its north rim)."""
        k = 0
        while y - k > 0 and self.top[int(y - k), int(x)]:
            k += 1
        return k


def poisson(rng, rect, r, ok, tries=30):
    """Bridson Poisson-disc samples inside rect with min distance r that pass ok(x, y)."""
    x0, y0, w, h = rect
    cs = r / math.sqrt(2)
    gw, gh = int(w / cs) + 1, int(h / cs) + 1
    grid = -np.ones((gh, gw), int)
    pts, active = [], []

    def fits(x, y):
        gx, gy = int((x - x0) / cs), int((y - y0) / cs)
        for j in range(max(0, gy - 2), min(gh, gy + 3)):
            for i in range(max(0, gx - 2), min(gw, gx + 3)):
                k = grid[j, i]
                if k >= 0 and (pts[k][0] - x) ** 2 + (pts[k][1] - y) ** 2 < r * r:
                    return False
        return True

    def add(x, y):
        pts.append((x, y))
        grid[int((y - y0) / cs), int((x - x0) / cs)] = len(pts) - 1
        active.append(len(pts) - 1)

    for _ in range(200):
        x, y = x0 + rng.uniform(0, w), y0 + rng.uniform(0, h)
        if ok(x, y):
            add(x, y)
            break
    while active:
        i = active[rng.integers(len(active))]
        px, py = pts[i]
        for _ in range(tries):
            a, d = rng.uniform(0, 2 * math.pi), rng.uniform(r, 2 * r)
            x, y = px + math.cos(a) * d, py + math.sin(a) * d
            if x0 <= x < x0 + w and y0 <= y < y0 + h and fits(x, y) and ok(x, y):
                add(x, y)
                break
        else:
            active.remove(i)
        if not active:
            for _ in range(400):
                x, y = x0 + rng.uniform(0, w), y0 + rng.uniform(0, h)
                if fits(x, y) and ok(x, y):
                    add(x, y)
                    break
    return pts


def pick(rng, weights):
    ks = list(weights)
    p = np.array([weights[k] for k in ks], float)
    return ks[rng.choice(len(ks), p=p / p.sum())]


def region_of(x, y, M):
    if M.on_plateau(x, y):
        return MIXES[0]
    for mx in MIXES[1:]:
        rx, ry, rw, rh = mx[1]
        if rx <= x < rx + rw and ry <= y < ry + rh:
            return mx
    return MIXES[-1]


def forest_field():
    """0..1 rank of a smooth noise field minus a border bonus: trees stand where it is under the mix density."""
    n = art.fbm(W, H, 150, 3, SEED).astype(np.float32)
    flat = n.ravel()
    rank = np.empty(flat.size, np.float32)
    rank[np.argsort(flat)] = np.linspace(0, 1, flat.size, dtype=np.float32)
    yy, xx = np.mgrid[0:H, 0:W]
    edge = np.clip(1 - (np.minimum.reduce([xx, yy, W - 1 - xx, H - 1 - yy]) - 70) / 230, 0, 1)
    return rank.reshape(H, W) - 0.7 * edge


def scatter(M):
    """Trees, shrubs, ferns, tufts, reeds and rocks off paths, water, plazas and clearings."""
    rng = np.random.default_rng(SEED)
    trees, props = [], []
    tb = M.blocked(20, 16, 34, 2)
    tp = M.blocked(2, 0, 0, 3)

    dense = forest_field()

    def tree_ok(x, y):
        xi, yi = int(x), int(y)
        if not (8 <= xi < W - 8 and 20 <= yi < H - 2) or tb[yi, xi]:
            return False
        if dense[yi, xi] > region_of(x, y, M)[5]:
            return False
        if any(tp[max(0, yi - dy), min(W - 1, max(0, xi + dx))] for dy in (16, 50, 90, 130) for dx in (-36, 0, 36)):
            return False
        if M.on_plateau(x, y) and M.rim_dist(x, y) < 26:
            return False
        return all((x - t['at'][0]) ** 2 + (y - t['at'][1]) ** 2 > 60 ** 2 for t in hand)

    hand = [{'species': s, 'at': at, 'seed': sd, 'scale': sc} for s, at, sc, sd in HAND_TREES]
    trees.extend(hand)
    for k, mx in enumerate(MIXES):
        name, rect, weights, rad = mx[0], mx[1], mx[2], mx[3]
        rect = rect or [0, 900, 720, 420]
        for x, y in poisson(rng, rect, rad, lambda x, y: tree_ok(x, y) and region_of(x, y, M) is mx):
            sp = pick(rng, weights)
            sc = float(rng.uniform(1.3, 1.75) if sp == 'pine' else rng.uniform(1.4, 2.0))
            trees.append({'species': sp, 'at': [int(x), int(y)], 'seed': int(rng.integers(1, 9999)), 'scale': round(sc, 2)})
    tree_pts = [t['at'] for t in trees]

    sb = M.blocked(9, 8, 14, 3)

    def small_ok(x, y, near):
        xi, yi = int(x), int(y)
        if not (10 <= xi < W - 10 and 12 <= yi < H - 2) or sb[yi, xi]:
            return False
        if M.on_plateau(x, y) and M.rim_dist(x, y) < 18:
            return False
        return all((x - a) ** 2 + (y - b) ** 2 > near ** 2 for a, b in tree_pts)

    for x, y in poisson(rng, [0, 0, W, H], 62, lambda x, y: small_ok(x, y, 26)):
        mx = region_of(x, y, M)
        kind = pick(rng, mx[4])
        seed = int(rng.integers(1, 9999))
        if kind == 'fern':
            props.append({'kind': 'fern', 'at': [int(x), int(y)], 'r': int(rng.integers(14, 19)), 'seed': seed})
        else:
            rx = int(rng.integers(18, 25))
            e = {'kind': 'holly' if kind == 'holly' else 'shrub', 'at': [int(x), int(y)], 'r': [rx, int(rx * 0.66)],
                 'seed': seed}
            if kind == 'hydrangea':
                e['flowers'] = 'pink' if rng.random() < 0.6 else 'violet'
            props.append(e)
    gb = M.blocked(3, 4, 4, 3)
    for x, y in poisson(rng, [0, 0, W, H], 50, lambda x, y: not gb[int(y), int(x)] and 4 <= y < H - 2):
        mx = region_of(x, y, M)
        e = {'kind': 'tuft', 'at': [int(x), int(y)], 'seed': int(rng.integers(1, 9999))}
        u = rng.random()
        if mx[0] == 'meadow' or (mx[0] not in ('plateau', 'ring') and u < 0.25):
            e['bloom'] = ['blue', 'violet', 'mint'][int(rng.integers(3))]
        elif u < 0.55:
            e['heads'] = True
        props.append(e)
    shore = M.blocked(0, 0, 0, 3)
    for rect in REEDS:
        for x, y in poisson(rng, rect, 34, lambda x, y: near_water(shore, x, y) and not tp[int(y), int(x)]):
            props.append({'kind': 'reeds', 'at': [int(x), int(y)], 'n': int(rng.integers(9, 14)), 'seed': int(rng.integers(1, 9999))})
    rb = M.blocked(6, 3, 10, 3)
    for x, y in poisson(rng, [0, 0, W, H], 150, lambda x, y: not rb[int(y), int(x)] and 10 <= y < H - 6):
        rx = int(rng.integers(6, 13))
        props.append({'kind': 'rock', 'at': [int(x), int(y)], 'r': [rx, max(4, int(rx * 0.65))],
                      'seed': int(rng.integers(1, 9999)), 'moss': 0.6})
    return split_plateau(M, trees, no_slivers(props))


def _collider(p):
    """Footprint ellipse (cx, cy, a, b) of a scattered shrub, holly or rock, as pixel-scene placers shape it."""
    (x, y), (rx, ry) = p['at'], p['r']
    if p['kind'] == 'rock':
        return x, y - ry * 0.4, rx, ry * 0.6
    return x, y - 2, rx * 0.8, ry * 0.5


def no_slivers(props, gap_min=14):
    """Drop the smaller of two scattered colliders whose gap is open but narrower than a walker (2 x 6 px feet + 2)."""
    solid = [i for i, p in enumerate(props) if p['kind'] in ('shrub', 'holly') or (p['kind'] == 'rock' and not p.get('walk'))]
    cells = {}
    for i in solid:
        cells.setdefault((props[i]['at'][0] // 64, props[i]['at'][1] // 64), []).append(i)
    drop = set()
    for i in solid:
        if i in drop:
            continue
        x1, y1, a1, b1 = _collider(props[i])
        cx, cy = props[i]['at'][0] // 64, props[i]['at'][1] // 64
        for j in [j for dx in (-1, 0, 1) for dy in (-1, 0, 1) for j in cells.get((cx + dx, cy + dy), []) if j > i]:
            if j in drop:
                continue
            x2, y2, a2, b2 = _collider(props[j])
            dist = math.hypot(x2 - x1, y2 - y1)
            t = math.atan2(y2 - y1, x2 - x1)
            reach = lambda a, b: a * b / math.hypot(b * math.cos(t), a * math.sin(t))
            if 0 < dist - reach(a1, b1) - reach(a2, b2) < gap_min:
                drop.add(i if a1 * b1 < a2 * b2 else j)
                if i in drop:
                    break
    print(f'NO_SLIVERS dropped {len(drop)} of {len(solid)} scattered colliders')
    return [p for k, p in enumerate(props) if k not in drop]



REEDS = [[1880, 600, 560, 520], [3380, 820, 280, 170], [2830, 820, 140, 90], [1420, 1580, 540, 360],
         [2780, 1100, 220, 1060]]

PRESET = {'pine': 'conifer', 'oak': 'oak', 'blossom': 'blossom', 'willow': 'willow'}


def split_plateau(M, trees, props):
    """Move plateau foliage to the plateau_flora extras hook so it y-sorts with the lowland (no plateau layer)."""
    plants, low_t, low_p = [], [], []
    for t in trees:
        if M.on_plateau(*t['at']):
            plants.append({'preset': PRESET[t['species']], 'at': t['at'], 'seed': t['seed'],
                           'size': round(t['scale'] * 1.25, 3)})
        else:
            low_t.append(t)
    for p in props:
        if not M.on_plateau(*p['at']) or p['kind'] not in ('fern', 'shrub', 'holly', 'tuft'):
            low_p.append(p)
        elif p['kind'] == 'fern':
            plants.append({'preset': 'fern', 'at': p['at'], 'seed': p['seed'], 'size': round(p['r'] / 12, 3)})
        elif p['kind'] == 'tuft':
            plants.append({'preset': 'tallgrass' if p.get('heads') else 'tuft', 'at': p['at'], 'seed': p['seed'], 'size': 1.0})
        else:
            pre = 'holly' if p['kind'] == 'holly' else 'bush'
            plants.append({'preset': pre, 'at': p['at'], 'seed': p['seed'], 'size': round(p['r'][0] / 16, 3)})
    return low_t, low_p, plants


def near_water(shore, x, y):
    """Dry cell within 4-10 px of water (reed belts)."""
    xi, yi = int(x), int(y)
    if shore[yi, xi]:
        return False
    win = shore[max(0, yi - 10):yi + 11, max(0, xi - 10):xi + 11]
    return bool(win.any()) and not shore[max(0, yi - 3):yi + 4, max(0, xi - 3):xi + 4].any()


def hand_props():
    """Landmark props drawn by pixel-scene kinds."""
    P = [
        {'kind': 'gate', 'at': [960, 330], 'span': 52, 'height': 84},
        {'kind': 'hokora', 'at': [960, 560], 'color': [255, 196, 120], 'energy': 0.45, 'radius': 70},
        {'kind': 'stone_lantern', 'at': [918, 582], 'energy': 0.35, 'radius': 46},
        {'kind': 'stone_lantern', 'at': [1002, 582], 'energy': 0.35, 'radius': 46},
        {'kind': 'campfire', 'at': [1440, 880], 'seats': [[-34, -4, 34], [30, 12, 30]]},
        {'kind': 'log', 'at': [240, 268], 'length': 110, 'radius': 10, 'seed': 3},
        {'kind': 'stump', 'at': [306, 250], 'r': 11},
        {'kind': 'bridge', 'at': [1952, 300], 'span': 40, 'width': 20},
        {'kind': 'bridge', 'at': [1174, 1176], 'span': 50, 'width': 20},
        {'kind': 'bridge', 'at': [2060, 890], 'span': 112, 'width': 20}, {'kind': 'bridge', 'at': [2172, 890], 'span': 112, 'width': 20},
        {'kind': 'bridge', 'at': [2284, 890], 'span': 112, 'width': 20},
        {'kind': 'signpost', 'at': [1272, 812]}, {'kind': 'signpost', 'at': [1004, 482]},
        {'kind': 'signpost', 'at': [1100, 1104]}, {'kind': 'signpost', 'at': [612, 1148]},
    ]
    for k, ang in enumerate([200, 250, 290, 340, 30, 150]):
        a = math.radians(ang)
        P.append({'kind': 'rune_stone', 'at': [round(2330 + math.cos(a) * 58), round(1272 + math.sin(a) * 32)],
                  'height': 40 + (k * 7) % 12, 'seed': k + 1, 'color': [255, 200, 110]})
    for k, (dx, dy) in enumerate([(-66, -18), (62, -22), (-50, 26), (70, 20), (8, -40)]):
        P.append({'kind': 'pillar', 'at': [1650 + dx, 1295 + dy], 'seed': 40 + k})
    for k, (x, y, rx) in enumerate([(1612, 1326, 9), (1700, 1262, 7), (1580, 1280, 6), (2402, 1300, 8), (2260, 1240, 7)]):
        P.append({'kind': 'rock', 'at': [x, y], 'r': [rx, rx * 2 // 3], 'seed': 60 + k})
    for k, y in enumerate((1318, 1334, 1350)):
        P.append({'kind': 'rock', 'at': [486 + (k % 2) * 4 - 2, y], 'r': [7, 4], 'walk': True, 'layer': 'bridge', 'seed': 70 + k})
    for k, y in enumerate((1034, 1047, 1060)):
        P.append({'kind': 'rock', 'at': [2471 + (k % 2) * 4 - 2, y], 'r': [6, 4], 'walk': True, 'layer': 'bridge', 'seed': 75 + k})
    for k, (x, y) in enumerate([(372, 470), (498, 534), (590, 452), (210, 590), (520, 610), (1330, 380)]):
        P.append({'kind': 'mushrooms', 'at': [x, y], 'seed': 80 + k})
    return P + east_props() + south_props()


def ring(cx, cy, rx, ry, angles, seed, **kw):
    """Rune stones on an ellipse."""
    return [dict({'kind': 'rune_stone', 'at': [round(cx + math.cos(math.radians(a)) * rx), round(cy + math.sin(math.radians(a)) * ry)],
                  'seed': seed + k, 'height': 38 + (k * 7) % 12}, **kw) for k, a in enumerate(angles)]


def east_props():
    """Skyroot Bluff, Fernfall Dell, Willowbank, Millrace Ruins, Hare Meadow, Heron Reach and Thornwood landmarks."""
    P = ring(2980, 240, 82, 48, (200, 240, 290, 330, 20, 160), 90, color=[200, 230, 255])
    P += [
        {'kind': 'stone_lantern', 'at': [2898, 486], 'energy': 0.3, 'radius': 44},
        {'kind': 'stone_lantern', 'at': [2952, 486], 'energy': 0.3, 'radius': 44},
        {'kind': 'signpost', 'at': [2925, 470]},
        {'kind': 'hokora', 'at': [3640, 500], 'color': [255, 210, 150], 'energy': 0.4, 'radius': 70},
        {'kind': 'stone_lantern', 'at': [3600, 520], 'energy': 0.3, 'radius': 44},
        {'kind': 'stone_lantern', 'at': [3680, 520], 'energy': 0.3, 'radius': 44},
        {'kind': 'mushrooms', 'at': [3470, 320], 'seed': 95}, {'kind': 'mushrooms', 'at': [3372, 316], 'seed': 96},
        {'kind': 'signpost', 'at': [3204, 700]}, {'kind': 'stone_lantern', 'at': [3130, 700], 'energy': 0.3, 'radius': 44},
        {'kind': 'log', 'at': [2830, 906], 'length': 70, 'radius': 8, 'seed': 97},
        {'kind': 'rock', 'at': [2950, 880], 'r': [9, 6], 'seed': 98}, {'kind': 'rock', 'at': [2856, 842], 'r': [7, 5], 'seed': 99},
        {'kind': 'signpost', 'at': [3440, 980]}, {'kind': 'rock', 'at': [3640, 930], 'r': [10, 6], 'seed': 100},
        {'kind': 'bridge', 'at': [2939, 1420], 'span': 54, 'width': 22},
        {'kind': 'bridge', 'at': [2885, 1780], 'span': 54, 'width': 22},
        {'kind': 'dais', 'at': [3520, 1300]},
        {'kind': 'gate', 'at': [3500, 1650], 'span': 52, 'height': 84, 'seed': 12},
        {'kind': 'stone_lantern', 'at': [2680, 1964], 'energy': 0.3, 'radius': 44},
        {'kind': 'stone_lantern', 'at': [2732, 1964], 'energy': 0.3, 'radius': 44},
        {'kind': 'signpost', 'at': [2705, 1948]},
        {'kind': 'campfire', 'at': [3560, 1980], 'seats': [[-32, -4, 34], [30, 10, 30]]},
        {'kind': 'log', 'at': [3600, 2030], 'length': 60, 'radius': 7, 'seed': 101},
    ]
    for k, (dx, dy) in enumerate([(-70, -20), (60, -26), (-44, 30), (74, 24)]):
        P.append({'kind': 'pillar', 'at': [2680 + dx, 1255 + dy], 'seed': 110 + k})
    P += [{'kind': 'rock', 'at': [2700, 1232], 'r': [14, 9], 'seed': 115}, {'kind': 'rock', 'at': [2660, 1280], 'r': [11, 7], 'seed': 116},
          {'kind': 'log', 'at': [2620, 1300], 'length': 64, 'radius': 8, 'seed': 117}]
    return P


def south_props():
    """Foxglove Fields, Hermit's Knoll, Reedwater Fen and Old Quarry landmarks."""
    P = [{'kind': 'mushrooms', 'at': [round(330 + 58 * math.cos(a)), round(1640 + 30 * math.sin(a))], 'seed': 120 + k}
         for k, a in enumerate(np.linspace(0, 2 * math.pi, 9, endpoint=False))]
    P += [
        {'kind': 'stump', 'at': [330, 1648], 'r': 10},
        {'kind': 'rune_stone', 'at': [220, 1995], 'height': 48, 'seed': 131, 'color': [255, 200, 110]},
        {'kind': 'campfire', 'at': [1000, 1660], 'seats': [[-34, -4, 34], [30, 12, 30]]},
        {'kind': 'log', 'at': [930, 1960], 'length': 72, 'radius': 8, 'seed': 132},
        {'kind': 'log', 'at': [990, 1976], 'length': 64, 'radius': 7, 'seed': 133},
        {'kind': 'stump', 'at': [1040, 1950], 'r': 11}, {'kind': 'stump', 'at': [900, 1990], 'r': 9},
        {'kind': 'signpost', 'at': [1600, 1606]}, {'kind': 'rock', 'at': [1640, 1612], 'r': [8, 5], 'seed': 134},
        {'kind': 'hokora', 'at': [1500, 1965], 'color': [255, 196, 120], 'energy': 0.4, 'radius': 70},
        {'kind': 'stone_lantern', 'at': [1460, 1985], 'energy': 0.3, 'radius': 44},
        {'kind': 'stone_lantern', 'at': [1540, 1985], 'energy': 0.3, 'radius': 44},
        {'kind': 'rock', 'at': [2260, 1990], 'r': [16, 10], 'seed': 135}, {'kind': 'rock', 'at': [2300, 2004], 'r': [12, 8], 'seed': 136},
        {'kind': 'rock', 'at': [2320, 1980], 'r': [9, 6], 'seed': 137}, {'kind': 'stump', 'at': [2250, 2020], 'r': 9},
    ]
    for k, (dx, dy) in enumerate([(-80, -16), (70, -24), (-58, 30), (84, 20), (6, -44)]):
        P.append({'kind': 'pillar', 'at': [2300 + dx, 1605 + dy], 'seed': 140 + k})
    return P


LIGHTS = [
    {'kind': 'point', 'at': [790, 960], 'color': [120, 170, 255], 'energy': 0.55, 'radius': 120, 'z': 30, 'flicker': 0.12},
    {'kind': 'point', 'at': [340, 640], 'color': [90, 170, 255], 'energy': 0.5, 'radius': 96, 'z': 20, 'flicker': 0.2},
    {'kind': 'point', 'at': [452, 490], 'color': [255, 170, 90], 'energy': 0.45, 'radius': 72, 'z': 18, 'flicker': 0.15},
    {'kind': 'point', 'at': [309, 1300], 'color': [150, 230, 190], 'energy': 0.3, 'radius': 90, 'z': 24},
    {'kind': 'point', 'at': [2330, 1250], 'color': [255, 210, 130], 'energy': 0.35, 'radius': 90, 'z': 24},
    {'kind': 'moon_pool', 'at': [1350, 640], 'color': [255, 236, 190], 'energy': 0.55, 'radius': 150, 'z': 60},
    {'kind': 'moon_pool', 'at': [1590, 410], 'color': [255, 226, 170], 'energy': 0.5, 'radius': 130, 'z': 60},
    {'kind': 'moon_pool', 'at': [1300, 850], 'color': [255, 232, 180], 'energy': 0.45, 'radius': 150, 'z': 60},
    {'kind': 'moon_pool', 'at': [2160, 900], 'color': [240, 248, 255], 'energy': 0.4, 'radius': 140, 'z': 60},
    {'kind': 'moon_pool', 'at': [960, 570], 'color': [255, 236, 190], 'energy': 0.4, 'radius': 110, 'z': 60},
    {'kind': 'moon_pool', 'at': [3420, 400], 'color': [255, 236, 190], 'energy': 0.5, 'radius': 150, 'z': 60},
    {'kind': 'moon_pool', 'at': [3520, 1290], 'color': [255, 232, 180], 'energy': 0.45, 'radius': 140, 'z': 60},
    {'kind': 'moon_pool', 'at': [330, 1660], 'color': [255, 236, 190], 'energy': 0.45, 'radius': 130, 'z': 60},
    {'kind': 'moon_pool', 'at': [1000, 1690], 'color': [255, 232, 180], 'energy': 0.4, 'radius': 120, 'z': 60},
    {'kind': 'moon_pool', 'at': [1680, 1760], 'color': [240, 248, 255], 'energy': 0.4, 'radius': 140, 'z': 60},
    {'kind': 'point', 'at': [3520, 1290], 'color': [150, 200, 255], 'energy': 0.45, 'radius': 96, 'z': 24, 'flicker': 0.15},
    {'kind': 'point', 'at': [2980, 240], 'color': [180, 220, 255], 'energy': 0.35, 'radius': 96, 'z': 24},
]

EXTRA_HOOKS = [
    {'fn': 'ground_patches', 'at': [0, 0], 'zones': [[n, r] for n, r, _ in ZONES]},
    {'fn': 'portal_arch', 'at': [790, 990]},
    {'fn': 'cerulean_ring', 'at': [340, 650], 'r': [52, 30]},
    {'fn': 'amber_fungi', 'at': [452, 500]},
    {'fn': 'spiral_flowers', 'at': [1350, 650]},
    {'fn': 'shimmerfish', 'at': [1950, 470]},
    {'fn': 'living_wall', 'at': [330, 935], 'rim': RIM},
    {'fn': 'plateau_read', 'at': [0, 0], 'cliffs': [CLIFF, BLUFF]},
]


def build():
    M = Masks()
    trees, scat, plants = scatter(M)
    goals = {f'zone {n}': g for n, _, g in ZONES}
    goals.update({f'prop {k}': v[2] for k, v in PROPS.items()})
    spec = {
        'name': 'The Magic Forest',
        'size': [W, H],
        'period': 9.0,
        'look': {'ambient': [236, 228, 206], 'moon': {'color': [255, 222, 160], 'energy': 0.42, 'height': 0.32},
                 'moon_reflect': [2230, 760], 'waterline': min(q[1] for q in WATER['ponds'][0]), 'rays': 0.16, 'haze': [0.05, 0.045, 0.02],
                 'falling': [0.95, 0.72, 0.32], 'motes': False, 'dof': 0.0},
        'ground': {'seed': 41, 'base': 'grass', 'moss': 0.76, 'top_shadow': 0, 'tufts': 157000, 'leaves': 0.0,
                   'leaf_pals': ['G1', 'G2', 'R1', 'E3', 'W2'], 'flower_rate': 0.0003,
                   'flowers': [['R2', None, 0], ['P0', None, 0], ['G3', None, 0], ['M2', None, 0], ['N10', None, 0]],
                   'lift': 0.04},
        'cliff': CLIFF,
        'water': WATER,
        'paths': PATHS,
        'plazas': PLAZAS,
        'moon_gap': [1450, 470],
        'fog': {'water': 0.18, 'top': 0.0, 'bottom': 0.0, 'clear': []},
        'trees': trees,
        'props': hand_props() + scat,
        'lights': LIGHTS,
        'walker': {'start': [1300, 830], 'radius': 6, 'goals': goals},
        'game': {
            'id': 'magic_forest', 'day': True, 'plateau': 'Deep Forest Edge',
            'terraces': [{k: BLUFF[k] for k in ('name', 'poly', 'height', 'stairs')}],
            'spawn': {'player': [1300, 830], 'agents': [1180, 790]},
            'zones': [{'name': n, 'rect': r} for n, r, _ in ZONES],
            'landmarks': [{'name': n, 'at': a, 'tall': t} for n, a, t in LANDMARKS],
            'props': {k: {'at': v[0], 'size': v[1], 'collision': False} for k, v in PROPS.items()},
            'extras': [dict(e, module=EXTRAS) for e in EXTRA_HOOKS + [{'fn': 'plateau_flora', 'at': [330, 1100], 'plants': plants}]],
        },
    }
    return spec


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, 'magic_forest.json')
    spec = build()
    with open(out, 'w') as f:
        json.dump(spec, f, indent=1)
    kinds = {}
    for p in spec['props']:
        kinds[p['kind']] = kinds.get(p['kind'], 0) + 1
    sp = {}
    for t in spec['trees']:
        sp[t['species']] = sp.get(t['species'], 0) + 1
    print(f'WROTE {out} trees {len(spec["trees"])} {sp} props {len(spec["props"])} {kinds} plateau plants {len(spec["game"]["extras"][-1]["plants"])}')


if __name__ == '__main__':
    main()
