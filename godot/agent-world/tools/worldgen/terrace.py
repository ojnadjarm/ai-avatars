#!/usr/bin/env python3
"""Raised terraces over a built world: pixel-scene cliff faces as lit sprites, their walls merged into block_face.png,
and built.json `levels` (the plateau plus every terrace) for the map-scale validator."""
import os

import numpy as np
from PIL import Image

import terrain

PAD = 8


def build(art, built, spec, game):
    """Draw each game.terraces entry {name, poly, height, stairs, elevation?} and write built['levels']."""
    W, H = spec['size']
    levels = []
    if spec.get('cliff'):
        c = spec['cliff']
        levels.append({'name': game.get('plateau', 'Plateau'), 'elevation': c['height'], 'poly': c['poly']})
    path = os.path.join(art, 'block_face.png')
    block = np.array(Image.open(path)) > 127
    for k, t in enumerate(game.get('terraces', [])):
        xs, ys = [p[0] for p in t['poly']], [p[1] for p in t['poly']]
        x0, y0 = max(0, int(min(xs)) - PAD), max(0, int(min(ys)) - PAD)
        x1, y1 = min(W, int(max(xs)) + PAD), min(H, int(max(ys)) + t['height'] + PAD)
        ground = dict(spec.get('ground', {}), tufts=0, flower_rate=0.0, leaves=0.0, top_shadow=0)
        sub = {'size': [x1 - x0, y1 - y0], 'ground': ground,
               'cliff': {'poly': [[p[0] - x0, p[1] - y0] for p in t['poly']], 'height': t['height'],
                         'stairs': [t['stairs'][0] - x0, t['stairs'][1] - x0]}}
        S, m = terrain.build(sub)
        face = m['face']
        S.mat[~face] = -1
        name = f'terrace{k}'
        files, _ = S.save(os.path.join(art, name), outline=False, band=0.5, dith=0.55, cluster=True)
        edge_top = int(m['edge'][m['top'].any(0)].min())
        built['nodes'].append(dict(name=name, files=files, x=x0, y=y0, w=S.w, h=S.h, sort=y0 + edge_top,
                                   layer='plateau', sway=0.0))
        wall = (m['face'] | m['side'])
        xx = np.arange(S.w)[None, :]
        wall &= ~((xx >= sub['cliff']['stairs'][0]) & (xx < sub['cliff']['stairs'][1]) & m['face'])
        block[y0:y1, x0:x1] |= wall
        levels.append({'name': t['name'], 'elevation': t.get('elevation', t['height']), 'poly': t['poly']})
        print(f'TERRACE {t["name"]} +{levels[-1]["elevation"]} face {int(face.sum())} px wall {int(wall.sum())} px')
    Image.fromarray((block * 255).astype(np.uint8), 'L').save(path)
    built['levels'] = levels
