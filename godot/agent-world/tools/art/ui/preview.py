#!/usr/bin/env python3
"""Contact sheet of the UI kit: every 9-slice drawn at a game size over the backdrop, scaled x3 (nearest)."""
import json
import os
import sys

from PIL import Image

UI = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', '..', 'assets', 'ui'))


def nine(src, margin, w, h, stretch=False):
    """Godot-style 9-slice: corners fixed, edges and centre tiled (or stretched)."""
    l, t, r, b = margin
    sw, sh = src.size
    out = Image.new('RGBA', (w, h))

    def part(box, size):
        p = src.crop(box)
        if size[0] <= 0 or size[1] <= 0 or p.size[0] == 0 or p.size[1] == 0:
            return None
        if stretch:
            return p.resize(size, Image.NEAREST)
        t_ = Image.new('RGBA', size)
        for yy in range(0, size[1], p.size[1]):
            for xx in range(0, size[0], p.size[0]):
                t_.paste(p, (xx, yy))
        return t_

    xs = [(0, l, 0, l), (l, sw - r, l, w - r), (sw - r, sw, w - r, w)]
    ys = [(0, t, 0, t), (t, sh - b, t, h - b), (sh - b, sh, h - b, h)]
    for sx0, sx1, dx0, dx1 in xs:
        for sy0, sy1, dy0, dy1 in ys:
            p = part((sx0, sy0, sx1, sy1), (dx1 - dx0, dy1 - dy0))
            if p is not None:
                out.alpha_composite(p, (dx0, dy0))
    return out


def main(out_path):
    meta = json.load(open(os.path.join(UI, 'ui.json')))['items']
    bg_path = os.path.join(UI, 'backdrop.png')
    sheet = Image.open(bg_path).convert('RGBA') if os.path.exists(bg_path) else Image.new('RGBA', (640, 360), (6, 7, 26, 255))
    sizes = {'panel': (150, 70), 'panel_dim': (110, 70), 'frame': (150, 90), 'modal': (170, 90), 'dialogue': (200, 60),
             'tooltip': (70, 20), 'nametag': (60, 13), 'portrait_frame': (52, 52), 'zone_banner': (200, 24),
             'minimap_frame': (72, 72), 'rule': (120, 3), 'panel9': (176, 118)}
    x, y, rowh = 6, 6, 0
    order = list(sizes) + sorted(k for k in meta if k not in sizes)
    for name in order:
        e = meta[name]
        src = Image.open(os.path.join(UI, e['file'])).convert('RGBA')
        if e.get('kind') == 'image':
            continue
        if 'frames' in e:
            src = src
        if e.get('kind') == 'nine' and 'margin' in e:
            w, h = sizes.get(name, (60 if name.startswith(('btn', 'focus', 'tab', 'field')) else 40, e['size'][1] if name.startswith(('slider', 'bar')) else 18))
            if name.startswith(('tab', 'btn', 'focus', 'field')):
                h = 20
            if name.startswith('scroll'):
                w, h = 7, 40
            im = nine(src, e['margin'], w, h, e.get('stretch', False))
        else:
            im = src
        if x + im.size[0] > 634:
            x, y, rowh = 6, y + rowh + 6, 0
        sheet.alpha_composite(im, (x, y))
        x += im.size[0] + 6
        rowh = max(rowh, im.size[1])
    sheet = sheet.resize((1920, 1080), Image.NEAREST)
    sheet.convert('RGB').save(out_path)
    print(out_path)


if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else '/tmp/ui_kit_sheet.png')
