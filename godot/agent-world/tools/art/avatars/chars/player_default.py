"""player_default: the newcomer - brown skin, dark curly hair, black t-shirt, blue jeans, white sneakers; waves hello."""
import numpy as np
from core import pat, Model, V, sphere, ellipsoid, cone, inter, warp
from rig import RAMPS, mats, ik, gait, root_path, follow, foot, swing_hand, yaw, lag, TAU
from hands import add_hand

MATS = mats(
    shirt=('navy', {'wrap': 0.4, 'gamma': 1.2, 'bias': -1.1}), jeans=('beard', {'wrap': 0.35, 'gamma': 1.15, 'bias': -1.7}),
    seam=('navy', {'bias': 0.6}), sneaker=('fletch', {'wrap': 0.5, 'bias': 0.3}), sole=('steel', {'bias': 1.2}),
    skin=('skin', {'kind': 'skin', 'bias': -0.6, 'ao': 0.5}), hair=('wood', {'wrap': 0.45, 'gamma': 1.1, 'bias': -0.5}),
    watch=('strap', {'bias': -0.5}),
)
MATS['hand'] = dict(MATS['skin'], ao=0.25, bias=-0.2)
MATS['face'] = dict(MATS['skin'], ramp=RAMPS['skin'][1:4], bias=-0.2)
MATS['face_hi'] = dict(MATS['skin'], ramp=RAMPS['skin'][:4], bias=0.1, ao=0.35)
MATS['nose'] = dict(MATS['face_hi'], bias=-0.3, ao=0.2)
ANIMS = {'idle': 6, 'walk': 8, 'talk': 4, 'wave': 6}
GAIT = dict(stride=4.3, lift=2.4, bob_amp=1.3, sway=0.65, hip_yaw=0.15, sh_yaw=0.13, arm=0.46, stance=0.58, heel=0.5)
HI = False
SIZE = 1.0
HAND = 1.2
HEAD_Y = 42.5
PORTRAIT = [('talk', 0), ('idle', 4), ('talk', 1), ('wave', 3)]
PFRAME = (3.0, 0.5)
EYE = {'k': '#2e1c22', 'w': '#f0d4cc', 'i': '#4f3028', 'h': '#f2f6ff', 'l': '#7a4c34', 'b': '#2e1c22'}
EYE_HI = pat(['..bbbb.', '.bbbbbb', 'b......', '.kkkkk.', 'kwiihwk', '.wiiiw.', '..lll..'], EYE, 3, 4)
EYE_HI_BLINK = pat(['..bbbb.', '.bbbbbb', 'b......', '.......', 'kkkkkkk', '.lllll.'], EYE, 3, 4)
MOUTH_C = {'k': '#4f3028', 'd': '#2e1c22', 'L': '#a86a4a', 'r': '#8e2240', 'w': '#f0d4cc'}
MOUTH_HI = {0: pat(['d.....d', '.dkkkd.', '..LLL..'], MOUTH_C, 3, 1), 1: pat(['.dkkd.', 'drrrrd', '.dkkd.'], MOUTH_C, 3, 1),
            2: pat(['k.....k', '.dwwwd.', '..dkd..', '...L...'], MOUTH_C, 3, 1)}
NOSE_HI = pat(['.k', '.k', 'kk'], {'k': '#7a4c34'}, 0, 0)
CURLS = [(-4.6, 3.0, 1.2), (-3.0, 5.4, 0.6), (0.0, 6.4, 0.2), (3.0, 5.4, 0.6), (4.6, 3.0, 1.2), (-1.6, 5.8, 3.0),
         (1.8, 5.6, 3.2), (-3.8, 4.4, -2.6), (0.0, 5.2, -3.6), (3.8, 4.4, -2.6), (-4.8, 1.2, -2.2), (4.8, 1.2, -2.2),
         (-2.4, 2.6, -5.0), (2.4, 2.6, -5.0), (0.0, 0.4, -5.6), (-4.0, 4.8, 2.6), (4.0, 4.8, 2.6)]


def pose(anim, f):
    """Every pose knob for one frame; build() only reads this dict."""
    n = ANIMS[anim]; ph = f / n
    p = dict(b=0.0, lean=0.0, sx=0.0, pyaw=0.0, syaw=0.0, head=V(0, 0, 0), hair=V(0, 0, 0), hem=V(0, 0, 0),
             rh=V(-7.4, 21.0, 1.0), lh=V(7.4, 21.0, 1.0), feet=[V(-2.6, 0, 0.3), V(2.6, 0, 0.3)], fpitch=(0.0, 0.0),
             mouth=0, blink=False, chest=0.0, rgrip='relaxed', lgrip='relaxed', rpalm=None, lpalm=None, rpoint=None, lpoint=None)
    if anim == 'idle':
        br = np.sin(TAU * ph)
        p['b'] = 0.3 * br; p['chest'] = 0.45 * br; p['sx'] = 0.35 * np.sin(TAU * ph + 0.6)
        p['head'] = V(0.25 * lag(ph, 1, 0.1), 0.25 * br, 0)
        p['hair'] = V(0.6 * lag(ph, 0.3, 0.2), 0, 0.4 * lag(ph, 0.3, 0.25))
        p['blink'] = f == 4
    elif anim == 'walk':
        g = gait(ph, **GAIT); rp = root_path(**GAIT)
        (z0, y0, a0), (z1, y1, a1) = g['feet']
        p['b'] = g['b']; p['lean'] = 1.0; p['sx'] = g['sway']; p['pyaw'] = g['pyaw']; p['syaw'] = g['syaw']
        p['feet'] = [V(-2.6, y0, z0 + 0.4), V(2.6, y1, z1 + 0.4)]; p['fpitch'] = (a0, a1)
        p['rh'] = swing_hand(V(-7.4, 21.0, 1.0), V(-5.6, 33.5, 0.4), g['arms'][0])
        p['lh'] = swing_hand(V(7.4, 21.0, 1.0), V(5.6, 33.5, 0.4), g['arms'][1])
        hr = follow(rp, 2.6, 0.3, ph); hm = follow(rp, 3.2, 0.35, ph)
        p['hair'] = V(-0.6 * hr[0], 0.5 * hr[1], -0.3 - 0.6 * hr[2])
        p['hem'] = V(-0.4 * hm[0], 0, -0.2 - 0.5 * hm[2])
        p['head'] = V(-0.3 * g['sway'], 0.3 * (gait(ph - 0.06, **GAIT)['b'] - g['b']), 0.2)
    elif anim == 'talk':
        p['head'] = V(0, [0, -0.5, 0.1, -0.3][f], 0.3)
        p['mouth'] = [0, 1, 0, 2][f]
        p['rh'] = [V(-7, 26, 5.5), V(-8, 29, 6.5), V(-7.5, 27.5, 6), V(-8.5, 29.5, 5.5)][f]
        p['rgrip'] = 'open'; p['rpalm'] = V(0.3, 1, 0.2)
        p['b'] = [0, -0.2, 0.1, -0.1][f]
    elif anim == 'wave':
        p['b'] = [0, -0.6, 0.3, 0.2, 0.3, 0.1][f]
        p['rh'] = [V(-7.4, 21, 1.0), V(-8.5, 24, 2.5), V(-11, 41, 3), V(-8, 43, 3.5), V(-12, 42, 3), V(-9, 36, 3)][f]
        p['head'] = V([0, 0, -0.4, 0.3, -0.4, 0][f], [0, -0.3, 0.2, 0.2, 0.2, 0][f], 0.4)
        p['mouth'] = [0, 0, 1, 2, 1, 0][f]
        p['sx'] = [0, 0.2, 0.5, 0.4, 0.5, 0.2][f]
        p['hair'] = V([0, 0.2, -0.3, 0.3, -0.3, 0][f], 0, 0)
        p['rgrip'] = ['relaxed', 'relaxed', 'open', 'open', 'open', 'relaxed'][f]
        p['rpalm'] = [None, None, V(0, 0, 1), V(0.3, 0, 1), V(-0.3, 0, 1), V(0.3, 0, 1)][f]
        p['rpoint'] = [None, None, V(-0.2, 1, 0), V(0.3, 1, 0), V(-0.4, 1, 0), V(0, 1, 0.3)][f]
    return p


def build(anim, f):
    """Signed-distance model of one frame in character space: +y up, +z forward (faces the 'down' camera), feet at y 0."""
    p = pose(anim, f)
    m = Model(); b = p['b']; ln = p['lean']; sx = p['sx']
    m.sel = {'hand'}
    for g, k in (('body', 1.0), ('leg', 0.8), ('head', 0.8), ('hair', 0.45)):
        m.group(g, k)
    pel = V(sx, 21.5 + b, 0)
    chest = V(0.6 * sx, 29.5 + b + 0.3 * p['chest'], 0.4 * ln)
    neck = V(0.4 * sx, 35.0 + b, 0.6 * ln)
    for side, ft, fp in ((-1, p['feet'][0], p['fpitch'][0]), (1, p['feet'][1], p['fpitch'][1])):
        hip = pel + yaw(V(2.4 * side, -1.4, 0), p['pyaw'])
        ank, fc, fr = foot(ft, fp, 2.0, V(0, 1.3, 1.4), toe=3.0)
        kn = ik(hip, ank, 9.6, 9.6, V(0, 0.1, 1))
        m.add(cone(hip, kn, 2.7, 2.2), 'jeans', 'leg')
        m.add(cone(kn, ank + V(0, 0.6, 0), 2.2, 2.05), 'jeans', 'leg')
        sy = ft[1]

        def shoe_tex(P, mt, sy=sy):
            mt = mt.copy(); mt[P[:, 1] < sy + 0.75] = 'sole'; return mt
        m.add(ellipsoid(fc, (2.15, 1.6, 3.3), rot=fr), 'sneaker', 'shoe%d' % side, shoe_tex)
        m.group('shoe%d' % side, 0.3)
    hem = p['hem']; fz = 0.08 * (p['feet'][0][2] + p['feet'][1][2])

    def hem_w(P):
        k = np.clip((pel[1] + 6 - P[:, 1]) / 6.0, 0, 1)
        return np.stack([hem[0] * k, 0 * k, (hem[2] + fz) * k], 1)
    m.add(ellipsoid(pel + V(0, -0.6, 0), (4.7, 3.4, 3.3)), 'jeans', 'leg')
    waist = inter(cone(pel + V(0, 6.5, 0.2), pel + V(0, 0.2, 0.1), 4.9, 5.0), lambda P: (pel[1] - 0.2) - P[:, 1])
    m.add(warp(waist, hem_w), 'shirt', 'body')
    m.add(ellipsoid(chest, (5.4, 6.3, 3.9)), 'shirt', 'body')
    m.add(cone(neck + V(0, -2, 0), neck + V(0, 2.2, 0.2), 1.75, 1.65), 'skin', 'body')
    m.add(ellipsoid(neck + V(0, -1.6, 0.9), (2.4, 0.7, 1.6)), 'seam', 'collar')
    for side, hand in ((-1, p['rh']), (1, p['lh'])):
        hand = hand + V(0, b * 0.6, 0)
        sh = V(0.4 * sx, 33.5 + b, 0.4 * ln) + yaw(V(5.6 * side, 0, 0), p['syaw'])
        el = ik(sh, hand, 6.4, 6.4, V(side * 0.5, -0.4, -1))
        mid = sh + 0.55 * (el - sh)
        m.add(sphere(sh, 2.55), 'shirt', 'body')
        m.add(cone(sh, mid, 2.45, 2.25), 'shirt', 'sl%d' % side)
        m.add(cone(sh, el, 1.75, 1.6), 'skin', 'arm%d' % side)
        g = 'rgrip' if side < 0 else 'lgrip'
        cuff = ('watch', 1.45) if side > 0 else None
        wr = add_hand(m, el, hand, side, p[g], p[g[0] + 'palm'], size=HAND, cuff=cuff, point=p[g[0] + 'point'])
        m.add(cone(el, wr, 1.6, 1.35), 'skin', 'arm%d' % side)
        m.group('arm%d' % side, 0.6); m.group('sl%d' % side, 0.4)
    H = V(0.3 * sx, HEAD_Y + b, 0.8 * ln) + p['head']
    face = 'face_hi' if HI else 'face'
    m.add(sphere(H, 5.9), face, 'head')
    m.add(ellipsoid(H + V(0, -2.7, 1.7), (4.0, 3.6, 4.0)), face, 'head')
    m.add(ellipsoid(H + V(0, -1.4, 5.9), (0.8, 1.2, 0.8)), 'nose' if HI else face, 'head')
    for s in (-1, 1):
        m.add(ellipsoid(H + V(5.6 * s, -0.4, -0.2), (0.8, 1.3, 0.9)), face, 'head')
    hr = p['hair']
    m.add(ellipsoid(H + V(0, 2.0, -1.0), (6.2, 4.6, 6.0)), 'hair', 'hair')
    for i, (cx, cy, cz) in enumerate(CURLS):
        w = 0.15 + 0.12 * max(cy, 0)
        m.add(sphere(H + V(cx, cy, cz) + hr * w, 2.0 + 0.25 * ((i * 7) % 3)), 'hair', 'hair')
    for s in (-1, 1):
        m.add(ellipsoid(H + V(5.1 * s, 0.2, 1.4), (0.9, 2.1, 1.3)), 'hair', 'hair')
    eye = {(0, 0): '#2e1c22', (0, 1): '#2e1c22'} if not p['blink'] else {(0, 0): '#4f3028', (1, 0): '#4f3028'}
    eye.update({(-1, -2): '#4f3028', (0, -2): '#4f3028'})
    if HI:
        eye = EYE_HI_BLINK if p['blink'] else EYE_HI
    for s in (-1, 1):
        m.stamps.append((H + V(2.3 * s, 0.3, 5.5), eye, V(0.2 * s, 0, 1), s > 0))
    if HI:
        m.stamps.append((H + V(0, -3.1, 5.6), MOUTH_HI[p['mouth']], V(0, 0, 1)))
        m.stamps.append((H + V(0.4, -1.6, 6.7), NOSE_HI, V(0, 0, 1)))
    else:
        m.stamps.append((H + V(-0.4, -3.4, 5.6), {(0, 0): '#4c1631', (1, 0): '#4c1631'} if p['mouth'] else {(0, 0): '#4f3028', (1, 0): '#4f3028'}, V(0, 0, 1)))
        m.stamps.append((H + V(0.6, -1.6, 6.4), {(0, 0): '#7a4c34'}, V(0, 0, 1)))
    m.glow = None
    return m, MATS
