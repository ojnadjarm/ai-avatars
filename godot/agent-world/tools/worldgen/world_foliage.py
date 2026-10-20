#!/usr/bin/env python3
"""T715 pixel-foliage for the world pipeline: pooled rigid-piece plants baked to wind atlases (no sway maps)."""
import json
import math
import os
import sys
import time

import numpy as np
from PIL import Image

import placers

PF = os.path.expanduser(os.environ.get('PIXEL_FOLIAGE', '~/.claude/skills/pixel-foliage/scripts'))
sys.path.insert(0, PF)
try:
    import export  # noqa: E402
    import motion  # noqa: E402
    import plants  # noqa: E402
finally:
    sys.path.remove(PF)

VARIANTS = {'oak': 3, 'blossom': 2, 'willow': 2, 'conifer': 4, 'bush': 6, 'holly': 6, 'hydrangea': 6, 'fern': 6,
            'tuft': 6, 'tallgrass': 6, 'meadow': 6, 'glowflora': 4, 'reed': 4}
SIZE_STEP = {'oak': 0.5, 'blossom': 0.5, 'willow': 0.5}
# Wind ticks per second: big crowns step at 4 (36 atlas cells, not 108), still at most 1 px per step.
FPS = {'oak': 4, 'blossom': 4, 'willow': 4}
SHEETS = ('day_sheet', 'night_sheet', 'normal_sheet', 'emissive_sheet')
STILLS = ('day', 'night', 'normal', 'emissive')
_POOLS = {}


def pool(out):
    """The plant pool writing into art dir `out` (one per build, shared by pixel-scene placers and world extras)."""
    if out not in _POOLS:
        _POOLS[out] = Pool(out)
    return _POOLS[out]


class Pool:
    """(preset, seed variant, size bucket) -> one baked plant; every instance reuses its atlas files."""

    def __init__(self, out):
        self.out, self.plants, self.anims = out, {}, {}

    def get(self, preset, seed, size):
        v = seed % VARIANTS.get(preset, 4)
        step = SIZE_STEP.get(preset, 0.25)
        sz = max(step, round(size / step) * step)
        stem = f'pf_{preset}_v{v}_s{int(round(sz * 100))}'
        if stem not in self.plants:
            meta = self._bake(preset, v, sz, stem)
            f = meta['files']
            files = {'albedo': f['day_sheet'], 'normal': f['normal_sheet']}
            if 'emissive_sheet' in f:
                files['emissive'] = f['emissive_sheet']
            self.plants[stem] = (files, meta['size'], meta['pivot'])
            self.anims[stem] = meta['anim']
        return stem, self.plants[stem]

    def _bake(self, preset, v, sz, stem, tries=4):
        """Bake the first seed of this variant whose rigidity/step check passes (pixel-foliage checks.check)."""
        t0 = time.time()
        for k in range(tries):
            seed = 1000 + 37 * v + sum(map(ord, preset)) + 7919 * k
            rig = plants.PRESETS[preset](seed, sz)
            trk = motion.track(rig, fps=FPS.get(preset, motion.FPS))
            meta = export.save(rig, trk, os.path.join(self.out, stem), dict(species=preset, seed=seed, scale=sz))
            if meta['check']['ok']:
                meta = trim(self.out, stem, meta)
                print(f'PLANT {stem} seed {seed} frames {meta["anim"]["frames"]} cell {meta["size"]} '
                      f'{time.time() - t0:.1f}s', flush=True)
                return meta
            print(f'PLANT {stem} seed {seed} check failed {meta["check"]}', flush=True)
        sys.exit(f'FAIL pixel-foliage check {stem}: no passing seed in {tries}')

    def place(self, g, name, preset, seed, size, x, y, shape=None, layer='ysort'):
        """Add one instance to graph g with its pivot on (x, y); the node names its atlas in `anim`."""
        stem, (files, wh, piv) = self.get(preset, seed, size)
        g.add_files(name, files, wh, piv, x, y, layer=layer, shape=shape)
        g.nodes[-1]['anim'] = stem
        return g.nodes[-1]


def trim(out, stem, meta):
    """Crop cells and stills to the union of opaque px over all frames, repack with the fewest empty cells, rewrite json."""
    f, a = meta['files'], meta['anim']
    w, h = meta['size']
    load = {k: np.asarray(Image.open(os.path.join(out, f[k]))) for k in SHEETS if k in f}
    cells = {k: [im[r * h:(r + 1) * h, c * w:(c + 1) * w] for r, c in (divmod(i, a['cols']) for i in range(a['frames']))]
             for k, im in load.items()}
    used = np.zeros((h, w), bool)
    for k in ('day_sheet', 'emissive_sheet'):
        for c in cells.get(k, []):
            used |= c[..., 3] > 0
    ys, xs = np.nonzero(used)
    x0, y0, x1, y1 = int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1
    cw, ch, n = x1 - x0, y1 - y0, a['frames']
    cols = min(range(1, 17), key=lambda c: (math.ceil(n / c) * c - n, abs(c * cw - math.ceil(n / c) * ch)))
    rows = math.ceil(n / cols)
    for k, cl in cells.items():
        sheet = np.zeros((rows * ch, cols * cw, cl[0].shape[2]), np.uint8)
        for i, c in enumerate(cl):
            r, q = divmod(i, cols)
            sheet[r * ch:(r + 1) * ch, q * cw:(q + 1) * cw] = c[y0:y1, x0:x1]
        Image.fromarray(sheet).save(os.path.join(out, f[k]), optimize=True)
    for k in STILLS:
        if k in f:
            im = np.asarray(Image.open(os.path.join(out, f[k])))
            Image.fromarray(im[y0:y1, x0:x1]).save(os.path.join(out, f[k]), optimize=True)
    meta['size'] = [cw, ch]
    meta['pivot'] = [meta['pivot'][0] - x0, meta['pivot'][1] - y0]
    a['cols'], a['rows'] = cols, rows
    prefix = os.path.join(out, stem)
    with open(prefix + '.json', 'w') as fh:
        json.dump(meta, fh)
    for theme in ('day', 'night'):
        with open(prefix + ('' if theme == 'day' else '_night') + '.tscn', 'w') as fh:
            fh.write(export.tscn(meta, stem, 'res://foliage/', theme))
    return meta


class Placer(placers.PFPlacer):
    """pixel-scene's PFPlacer drawing every plant with T715 plants.py instead of the legacy species shim."""

    def __init__(self, g, fo=None):
        super().__init__(g, fo)
        self.pool = pool(g.out)

    def plant(self, name, preset, seed, size, x, y, shape=None, layer='ysort'):
        preset = preset if preset in plants.PRESETS else 'oak'
        return self.pool.place(self.g, name, preset, seed, size, x, y, shape=shape, layer=layer)

    def p_reeds(self, e, i, x, y):
        self.plant(f'reeds{i}', 'reed', e.get('seed', 180 + i), 1.0, x, y)


def finish(built, art):
    """Add the atlas animations, drop every sway key and sway map file left by static sprites (reeds)."""
    built['foliage'] = pool(art).anims
    dropped = 0
    for n in built['nodes']:
        n.pop('sway', None)
        w = n['files'].pop('sway', None)
        if w and os.path.isfile(os.path.join(art, w)):
            os.remove(os.path.join(art, w))
            dropped += 1
    print(f'FOLIAGE T715 plants {len(built["foliage"])} instances '
          f'{sum(1 for n in built["nodes"] if "anim" in n)} sway maps dropped {dropped}')
