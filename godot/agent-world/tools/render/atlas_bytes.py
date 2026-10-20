#!/usr/bin/env python3
"""Foliage atlas GPU bytes and static reeds per built world (RGBA8 albedo/emissive, RG8 normal: art_textures.gd).
usage: atlas_bytes.py WORLD_DIR [WORLD_DIR...] [--max-mb 256]; exit 1 over budget or with a static reed."""
import argparse
import json
import os

from PIL import Image

BPP = {'albedo': 4, 'emissive': 4, 'normal': 2}


def measure(world):
    art = os.path.join(world, 'art')
    built = json.load(open(os.path.join(art, 'built.json')))
    seen, total = set(), 0
    for n in built['nodes']:
        if 'anim' not in n:
            continue
        for kind, f in n['files'].items():
            if f not in seen:
                seen.add(f)
                w, h = Image.open(os.path.join(art, f)).size
                total += w * h * BPP[kind]
    reeds = [n for n in built['nodes'] if n['name'].startswith('reeds')]
    frames = max((a['frames'] for a in built.get('foliage', {}).values()), default=0)
    return total, len(built.get('foliage', {})), sum('anim' not in n for n in reeds), len(reeds), frames


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('worlds', nargs='+')
    ap.add_argument('--max-mb', type=float, default=256)
    a = ap.parse_args()
    bad = 0
    for w in a.worlds:
        total, stems, static, reeds, frames = measure(w)
        ok = total <= a.max_mb * 1e6 and static == 0
        bad += not ok
        print(f'ATLAS {os.path.basename(os.path.normpath(w))} {total / 1e6:.1f} MB stems {stems} max frames {frames} '
              f'reeds {reeds} static {static} {"pass" if ok else "FAIL"}')
    return 1 if bad else 0


if __name__ == '__main__':
    raise SystemExit(main())
