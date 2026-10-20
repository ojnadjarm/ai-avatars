#!/usr/bin/env python3
"""Oak read probe: every pooled oak still (pf_oak_*.png, rest pose) needs canopy px >= 3x trunk px and canopy height
>= 3x bare trunk height (trunk rows with no leaf over the trunk). usage: oak_probe.py ART_DIR [ART_DIR...]"""
import glob
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.expanduser(os.environ.get('PIXEL_FOLIAGE', '~/.claude/skills/pixel-foliage/scripts')))
import palette as P  # noqa: E402

DAY = P.TABLE['day'].reshape(-1, 3).astype(np.int32)
RAMP = np.repeat(np.arange(len(P.NAMES)), P.LEVELS)
MIN = 3.0


def measure(path):
    """(canopy px, trunk px, canopy rows, bare trunk rows) of one day still, by nearest palette ramp."""
    a = np.array(Image.open(path).convert('RGBA')).astype(np.int32)
    op = a[..., 3] == 255
    rid = np.full(op.shape, -1)
    c = a[..., :3][op]
    rid[op] = RAMP[((c[:, None, :] - DAY[None]) ** 2).sum(-1).argmin(1)]
    bark, leaf = rid == P.RID['bark'], op & (rid != P.RID['bark'])
    h = a.shape[0]
    base = bark[h * 2 // 3:]
    xs = np.nonzero(base.any(0))[0]
    x0, x1 = xs.min() - 2, xs.max() + 3
    span_bark, span_leaf = bark[:, x0:x1].any(1), leaf[:, x0:x1].any(1)
    bare = int((span_bark & ~span_leaf).sum())
    rows = np.nonzero(leaf.any(1))[0]
    return int(leaf.sum()), int(bark.sum()), int(rows.max() - rows.min() + 1), bare


def main(dirs):
    files = sorted(f for d in dirs for f in glob.glob(os.path.join(d, 'pf_oak_v*_s*.png'))
                   if os.path.basename(f).count('_') == 3)
    bad = 0
    for f in files:
        cp, tp, ch, bh = measure(f)
        ra, rh = cp / max(1, tp), ch / max(1, bh)
        ok = ra >= MIN and rh >= MIN
        bad += not ok
        print(f'{"ok  " if ok else "FAIL"} {os.path.basename(f)} canopy/trunk px {ra:.2f} canopy/bare-trunk height {rh:.2f}'
              f' ({ch}/{bh})')
    print(f'OAKPROBE {"pass" if files and not bad else "FAIL"} {len(files)} oaks, {bad} below {MIN}x')
    return 0 if files and not bad else 1


if __name__ == '__main__':
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    sys.exit(main(sys.argv[1:]))
