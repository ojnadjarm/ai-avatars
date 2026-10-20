#!/usr/bin/env python3
"""Hand pixels per walk_down frame for each avatar module; exits 1 unless every frame shows >= 8 hand px."""
import os, sys, argparse, importlib
sys.path.insert(0, os.path.join(os.environ.get('PIXEL_AVATAR', os.path.expanduser('~/.claude/skills/pixel-avatar')), 'scripts'))
import core
from build import CELL, PIV, SCALE

ap = argparse.ArgumentParser(description=__doc__)
ap.add_argument('--src', default=os.path.join(os.path.dirname(os.path.abspath(__file__)), 'chars'))
ap.add_argument('names', nargs='*', default=['player_default', 'darksaddler', 'luna', 'grok'])
a = ap.parse_args()
sys.path.insert(0, a.src)
core.set_pitch(22.0)
bad = 0
for name in a.names:
    mod = importlib.import_module(name); mod.HI = False
    px = []
    for f in range(mod.ANIMS['walk']):
        m, mats = mod.build('walk', f)
        o = core.render(m, mats, CELL, CELL, PIV, SCALE * getattr(mod, 'SIZE', 1.0), 0.0)
        px.append(int(o['selmask'].sum()) if 'hand' in getattr(m, 'sel', ()) else 0)
    bad += min(px) < 8
    print('%s walk_down hand px per frame %s' % (name, px))
print('HANDS %s' % ('fail' if bad else 'pass'))
sys.exit(1 if bad else 0)
