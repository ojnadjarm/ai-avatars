"""Luna: green-hooded ranger with longbow and quiver; bespoke model + per-frame poses."""
import numpy as np
from core import (pat, Model, V, sphere, ellipsoid, cone, torus, warp, inter, sub, rot_x, rot_z, rot_y)
from rig import mats, ik, gait, root_path, follow, foot, swing_hand, yaw, lag, TAU
from hands import add_hand

MATS = mats(
    hood=('hood', {'wrap': 0.3, 'gamma': 1.3, 'bias': -0.6}), hood_in='hood_in', hood_edge=('hood', {'bias': 0.4}), cloak=('hood', {'wrap': 0.25, 'gamma': 1.4, 'bias': -0.7}),
    leather=('leather', {'wrap': 0.3, 'bias': -0.6}), strap=('strap', {'bias': 0.3}), linen=('linen', {'wrap': 0.4}),
    skin=('skin_young', {'kind': 'skin', 'bias': 0.85}), hair=('blonde', {'wrap': 0.5, 'gamma': 0.9, 'bias': 0.25}),
    hair_s=('blonde', {'wrap': 0.5, 'bias': -0.9}), legging='legging', boot=('leather', {'bias': -1.2}),
    wood='wood', silver=('silver', {'kind': 'metal'}), fletch='fletch', red='red', gold=('gold', {'kind': 'metal'}),
)
MATS['hand'] = dict(MATS['skin'], ao=0.25)
HAND = 1.1
ANIMS = {'idle': 6, 'walk': 8, 'talk': 4, 'draw': 8}
HI = False
SIZE = 1.08
HEAD_Y = 44.3
GAIT = dict(stride=5.4, lift=3.4, bob_amp=1.7, sway=0.7, hip_yaw=0.22, sh_yaw=0.16, arm=0.5, stance=0.55, heel=0.75)
PORTRAIT = [('talk', 0), ('idle', 3), ('talk', 1), ('draw', 4)]
PFRAME = (3.3, 0.5)
EYE_C = {'k': '#2e1c22', 'l': '#a86a4a', 'w': '#f0d4cc', 'g': '#257a70', 'G': '#5ec29c', 'p': '#0a1f2c', 'h': '#f2f6ff', 'd': '#14464f'}
EYE_HI = pat(['...kkkk..', '.kkkkkkk.', 'kkwdpphkk', '.wgdppgGw', '.wgGGGGw.', '..wGGGw..', '...lll...'], EYE_C, 4, 3)
EYE_HI_BLINK = pat(['.........', '.........', '.........', 'kkkkkkkkk', '.kllllll.', '..lllll..'], EYE_C, 4, 3)
MOUTH_HI = {0: pat(['.rr.', 'rRRr'], {'r': '#d0404a', 'R': '#f08070'}, 2, 0),
            1: pat(['.rrr.', 'rkkkr', '.rRr.'], {'r': '#d0404a', 'R': '#f08070', 'k': '#4c1631'}, 2, 0),
            2: pat(['.rrr.', 'rkkkr', 'rkkkr', '.rRr.'], {'r': '#d0404a', 'R': '#f08070', 'k': '#4c1631'}, 2, 0)}


def pose(anim, f):
    n = ANIMS[anim]; ph = f / n
    p = dict(b=0.0, hipx=0.0, lean=0.0, head=V(0, 0, 0), look=0.0, hair=V(0, 0, 0), cloak=V(0, 0, 0),
             lh=V(8.2, 21.5, 1.5), rh=V(-7.6, 21.5, 1.0), feet=[V(-3.0, 0, 0.3), V(3.0, 0, 0.3)],
             bow_up=V(0.05, 1, 0.0), bow_face=V(1, 0, 0), draw=0.0, string=None, arrow=None, mouth=0,
             blink=False, flight=None, fold=0.0, chest=0.0, pyaw=0.0, syaw=0.0, fpitch=(0.0, 0.0), shx=0.0, rgrip='relaxed', lgrip='relaxed', rpalm=None, lpalm=None, rpoint=None, lpoint=None)
    if anim == 'idle':
        br = np.sin(TAU * ph)
        p['b'] = 0.3 * br; p['chest'] = 0.3 * br
        p['hipx'] = 0.6 * np.sin(TAU * ph + 0.5)
        p['look'] = [0, 0, 0.6, 0.6, 0, -0.3][f]
        p['head'] = V(0.4 * p['look'], 0.2 * br, 0)
        p['hair'] = V(lag(ph, 0.6, 0.2), 0, lag(ph, 0.4, 0.25))
        p['cloak'] = V(lag(ph, 0.5, 0.3), 0, lag(ph, 0.5, 0.2))
        p['feet'] = [V(-3.2, 0, 0.6), V(3.0, 0, -0.4)]
        p['blink'] = f == 3
    elif anim == 'walk':
        # ranger's light step: long stride, short stance, springy rise onto the toe, free counter-rotation and arm swing
        g = gait(ph, **GAIT); rp = root_path(**GAIT)
        (z0, y0, a0), (z1, y1, a1) = g['feet']
        p['b'] = g['b']; p['lean'] = 1.5; p['hipx'] = g['sway']; p['shx'] = 0.4 * g['sway']; p['pyaw'] = g['pyaw']; p['syaw'] = g['syaw']
        p['feet'] = [V(-2.8, y0, z0 + 0.5), V(2.8, y1, z1 + 0.5)]; p['fpitch'] = (a0, a1)
        th_r, th_l = g['arms']
        p['rh'] = swing_hand(V(-7.4, 22.0, 1.0), V(-5.1, 35.8, 0.75), th_r)
        p['lh'] = swing_hand(V(8.0, 22.0, 1.5), V(5.1, 35.8, 0.75), th_l * 0.8)
        bw = follow(rp, 2.8, 0.35, ph)
        p['bow_up'] = V(0.05 - 0.3 * bw[0], 1, -0.55 * th_l + 0.4 * bw[2])
        hr = follow(rp, 2.2, 0.28, ph); cl = follow(rp, 1.6, 0.25, ph)
        p['hair'] = V(-1.6 * hr[0], 1.2 * hr[1], -1.2 - 1.4 * hr[1] - 1.2 * hr[2])
        p['cloak'] = V(-2.2 * cl[0], 0, -2.6 - 2.4 * cl[1] - 1.6 * cl[2])
        p['head'] = V(-0.4 * g['sway'], 0.35 * (gait(ph - 0.06, **GAIT)['b'] - g['b']), 0.3)
        p['chest'] = -0.6 * g['b']
        p['fold'] = TAU * ph + 2.0 * cl[0]
    elif anim == 'talk':
        p['head'] = V([0, 0.3, 0, -0.2][f], [0, -0.4, 0, -0.2][f], 0.3)
        p['mouth'] = [0, 1, 0, 2][f]
        p['rh'] = [V(-6.5, 27, 6), V(-7.5, 30, 7), V(-6.8, 28.5, 6.5), V(-7.8, 30.5, 6)][f]
        p['hair'] = V(lag(ph, 0.3, 0.25), 0, 0)
        p['hipx'] = 0.6
        p['feet'] = [V(-3.2, 0, 0.6), V(3.0, 0, -0.4)]
        p['rgrip'] = 'open'; p['rpalm'] = V(0.3, 1, 0.3); p['rpoint'] = V(-1, 0.5, 0.4)
    elif anim == 'draw':
        # ready, raise, nock, draw, full draw, hold, release, follow-through
        p['lh'] = [V(8.2, 21.5, 1.5), V(6, 30, 9), V(4, 33, 12), V(3, 33.5, 13), V(3, 33.5, 13.2),
                   V(3, 33.5, 13.2), V(3.2, 33.8, 13.5), V(4.5, 31, 11)][f]
        p['rh'] = [V(-7.6, 21.5, 1), V(-5, 28, 6), V(0.5, 33, 10.5), V(-0.5, 34.5, 5), V(-1.5, 35.5, 1.5),
                   V(-1.5, 35.5, 1.5), V(-5, 36.5, -1.5), V(-6.5, 33, -0.5)][f]
        p['bow_up'] = [V(0.05, 1, 0), V(0.3, 1, 0.2), V(0.12, 1, 0), V(0.12, 1, 0), V(0.12, 1, 0),
                       V(0.12, 1, 0), V(0.12, 1, 0), V(0.2, 1, 0.1)][f]
        p['bow_face'] = V(0, 0, 1) if f >= 2 else V(1, 0, 0.3)
        p['draw'] = [0, 0, 0.1, 0.6, 1.0, 1.0, 0.0, 0.0][f]
        p['arrow'] = f in (2, 3, 4, 5)
        p['flight'] = {6: 1, 7: 2}.get(f)
        p['b'] = [0, -0.4, -0.6, -0.9, -1.0, -1.0, -0.6, -0.2][f]
        p['lean'] = [0, 0.6, 0.8, -0.4, -0.8, -0.8, -1.2, -0.4][f]
        p['head'] = V(0, 0, [0, 0.4, 0.6, 0.6, 0.6, 0.6, 0.2, 0][f])
        p['hair'] = V(0, 0, [0, 0.4, 0, -0.4, -0.6, -0.6, -1.4, -0.8][f])
        p['cloak'] = V(0, 0, [0, 0.4, 0, -0.5, -0.8, -0.8, -1.8, -1.0][f])
        p['feet'] = [V(-3.6, 0, -1.2), V(3.4, 0, 1.8)] if f else [V(-3.0, 0, 0.3), V(3.0, 0, 0.3)]
        p['blink'] = f in (4, 5)
        p['rgrip'] = ['relaxed', 'relaxed', 'hook', 'hook', 'hook', 'hook', 'open', 'relaxed'][f]
        p['rpalm'] = [None, None, V(1, 0, 0), V(1, -0.3, 0), V(1, -0.3, 0), V(1, -0.3, 0), V(0.5, 0, -1), None][f]
        p['rpoint'] = [None, None, None, V(1, 0, 0.3), V(1, 0, 0.6), V(1, 0, 0.6), V(-0.6, 0.3, -1), None][f]
    return p


def build(anim, f):
    p = pose(anim, f)
    m = Model(); b = p['b']; ln = p['lean']; hx = p['hipx']; m.sel = {'hand'}
    for g, k in (('body', 1.1), ('leg', 0.8), ('head', 0.8), ('hood', 0.9), ('hair', 0.9), ('bow', 0.4), ('quiv', 0.5)):
        m.group(g, k)
    pel = V(hx, 23.5 + b, 0)
    chest = V(hx * 0.4, 32 + b + p['chest'] * 0.3, 0.5 * ln)
    neck = V(hx * 0.2, 38 + b, 0.7 * ln)
    # legs
    for side, ft in ((-1, p['feet'][0]), (1, p['feet'][1])):
        hip = pel + yaw(V(2.6 * side, -1.5, 0), p['pyaw'])
        ank, fc, fr = foot(ft, p['fpitch'][(side + 1) // 2], 2.0, V(0, 1.2, 1.3), toe=2.9)
        kn = ik(hip, ank, 10.4, 10.4, V(0, 0.1, 1))
        m.add(cone(hip, kn, 2.7, 2.0), 'legging', 'leg')
        m.add(cone(kn, ank, 2.2, 1.7), 'boot', 'leg')
        m.add(cone(kn + (ank - kn) * 0.05, kn + (ank - kn) * 0.12, 2.5, 2.5), 'boot', 'leg')
        m.add(ellipsoid(fc, (1.8, 1.3, 2.9), rot=fr), 'boot', 'leg')
    # tunic skirt (leather flaps)
    def skirt_tex(P, mt):
        mt = mt.copy(); a = np.arctan2(P[:, 0] - pel[0], P[:, 2])
        mt[np.abs(np.sin(a * 4)) < 0.12] = 'strap'; return mt
    sk = inter(inter(cone(pel + V(0, 2.5, 0), pel + V(0, -4.5, 0.2), 4.4, 5.8), lambda P: (pel[1] - 5.2) - P[:, 1]), lambda P: P[:, 1] - (pel[1] + 2.4))
    m.add(warp(sk, lambda P: np.stack([0 * P[:, 0], 0 * P[:, 0], 0.15 * (p['feet'][1][2] + p['feet'][0][2]) * np.clip((pel[1] - P[:, 1]) / 6, 0, 1)], 1)), 'leather', None, skirt_tex)
    # torso
    def torso_tex(P, mt):
        mt = mt.copy(); q = P - chest
        x1 = np.abs(q[:, 0] - q[:, 1] * 0.55) < 0.95
        x2 = np.abs(q[:, 0] + q[:, 1] * 0.55) < 0.95
        mt[(x1 | x2) & (q[:, 2] > 0) & (q[:, 1] < 3.5)] = 'strap'
        mt[np.abs(P[:, 1] - (pel[1] + 3.6)) < 0.9] = 'strap'
        return mt
    m.add(ellipsoid(chest, (5.0, 6.2, 3.7)), 'leather', 'body', torso_tex)
    for s_ in (-1, 1):
        m.add(cone(chest + V(4.0 * s_, 4.2, 1.6), chest + V(-3.4 * s_, -5.6, 2.9), 0.75, 0.75), 'strap', 'strap')
    m.group('strap', 0.3)
    m.add(ellipsoid(pel + V(0, 3.2, 0), (4.4, 3.4, 3.3)), 'leather', 'body', torso_tex)
    m.stamps.append((pel + V(0, 3.6, 4.3), {(0, 0): '#f2c45a', (1, 0): '#b8862e', (0, 1): '#b8862e'}, V(0, 0, 1)))
    m.add(cone(neck + V(0, -2, 0), neck + V(0, 2.5, 0.3), 1.8, 1.7), 'skin', 'body')
    m.add(ellipsoid(pel + V(-4.2, 1.6, 2.2), (1.7, 2.0, 1.3)), 'strap', None)
    m.add(cone(pel + V(4.0, 3.0, 2.0), pel + V(4.6, -2.6, 2.6), 0.7, 0.45), 'silver', None)
    # arms
    bow_axis = p['bow_up'] / np.linalg.norm(p['bow_up'])
    for side, hand in ((-1, p['rh']), (1, p['lh'])):
        hand = hand + V(0, b * 0.6, 0)
        sh = V(p['shx'], 35.8 + b, 0.5 * ln) + yaw(V(5.1 * side, 0, 0), p['syaw'])
        el = ik(sh, hand, 6.6, 6.6, V(side * 0.5, -0.4, -1))
        m.add(sphere(sh, 2.6), 'linen', 'body')
        m.add(cone(sh, el, 2.2, 1.8), 'linen', 'arm%d' % side)
        g = 'rgrip' if side < 0 else 'lgrip'
        wr = add_hand(m, el, hand, side, p[g], p[g[0] + 'palm'], axis=bow_axis if side > 0 else None,
                      size=HAND, point=p[g[0] + 'point'])
        m.add(cone(el + (wr - el) * 0.12, wr, 1.95, 1.6), 'leather', 'arm%d' % side)
        m.group('arm%d' % side, 0.6)
    # cloak: back drape from the shoulders with an open front
    cl = p['cloak']
    def cloak_w(P):
        k = np.clip((neck[1] - P[:, 1]) / 18, 0, 1) ** 1.6
        return np.stack([cl[0] * k, 0 * k, cl[2] * k], 1)
    def cloak_tex(P, mt):
        mt = mt.copy(); q = P - cloak_w(P)
        mt[q[:, 2] > 1.8 - 0.05 * (neck[1] - q[:, 1])] = 'hood_in'; return mt
    cloak = inter(cone(neck + V(0, 1, -0.6), V(hx * 0.3, 19 + b, -2.2), 6.6, 8.6),
                  lambda P: np.maximum((P[:, 2] - 2.6 + 0.12 * (neck[1] - P[:, 1])), (19.0 + b - 1.2 * np.cos(np.arctan2(P[:, 0], -P[:, 2]) * 4)) - P[:, 1]))
    def cloak_f(P):
        q = P - cloak_w(P); a = np.arctan2(q[:, 0], -q[:, 2])
        k = np.clip((neck[1] - q[:, 1]) / 18, 0, 1)
        return cloak(q) - 0.6 * k * np.sin(a * 7 + p['fold']) - 0.25 * k * np.sin(a * 13 - p['fold'])
    m.add(cloak_f, 'cloak', None, cloak_tex)
    capl = inter(ellipsoid(neck + V(0, -0.6, -0.4), (7.7, 5.6, 5.9)), lambda P: (neck[1] - 4.6 - 0.9 * np.cos(np.arctan2(P[:, 0], P[:, 2]) * 5)) - P[:, 1])
    m.add(capl, 'hood', 'hood')
    m.stamps.append((neck + V(0, -1.4, 5.3), {(0, 0): '#f2f6ff', (1, 0): '#c8dbf0', (-1, 0): '#7894c4', (0, 1): '#7894c4'}, V(0, 0, 1)))
    # quiver on the back
    q0, q1 = V(-3.5 + hx * 0.4, 23 + b, -4.6), V(3.4 + hx * 0.4, 39 + b, -5.6)
    m.add(cone(q0, q1, 2.0, 2.3), 'leather', 'quiv')
    for k, (dx, dz) in enumerate(((0, 0), (1.2, 0.8), (-1.0, 0.6))):
        tipa = q1 + V(dx + 0.6, 2.2 + k * 0.4, dz)
        m.add(ellipsoid(tipa + V(0.4, 1.6, 0), (0.7, 1.9, 0.9), rot=rot_z(-0.4)), 'fletch' if k != 1 else 'red')
    # head
    H = V(hx * 0.15, 44.3 + b, 0.9 * ln + 0.4) + p['head']
    m.add(sphere(H, 6.4), 'skin', 'head')
    m.add(ellipsoid(H + V(0, -3.0, 2.8), (4.4, 3.3, 3.6)), 'skin', 'head')
    m.add(ellipsoid(H + V(0, -1.2, 6.3), (0.85, 1.2, 0.9)), 'skin', 'head')
    hr = p['hair']
    def hair_tex(P, mt):
        mt = mt.copy(); a = np.arctan2(P[:, 0] - H[0], P[:, 2] - H[2])
        mt[np.sin(a * 11 + P[:, 1] * 0.2) > 0.5] = 'hair_s'; return mt
    m.add(ellipsoid(H + V(0, 1.4, -0.2), (6.8, 5.4, 6.6)), 'hair', 'hair', hair_tex)
    m.add(ellipsoid(H + V(1.2, 3.4, 5.0), (4.6, 2.0, 1.9), rot=rot_z(-0.35)), 'hair', 'hair', hair_tex)
    for s in (-1, 1):
        top = H + V(5.2 * s, 0.5, 2.6)
        mid = H + V(5.6 * s, -6.0, 2.8) + hr * 0.5
        end = H + V(4.6 * s, -12.0, 3.4) + hr
        m.add(cone(top, mid, 2.1, 1.9), 'hair', 'hair', hair_tex)
        m.add(cone(mid, end, 1.9, 0.9), 'hair', 'hair', hair_tex)
    # hood shell with face opening
    hc = H + V(0, 1.0, -1.0)
    open_e = ellipsoid(H + V(0, -2.6, 6.9), (5.5, 7.0, 4.4))
    hood0 = sub(ellipsoid(hc, (7.6, 8.3, 8.0)), open_e)
    def hood(P):
        q = P - hc; a = np.arctan2(q[:, 0], -q[:, 2])
        k = np.clip((hc[1] + 6 - P[:, 1]) / 12, 0, 1)
        return hood0(P) - 0.35 * k * np.sin(a * 5 + q[:, 1] * 0.25) - 0.15 * np.sin(a * 11)
    def hood_tex(P, mt):
        mt = mt.copy(); r = length3((P - hc) / V(7.6, 8.3, 8.0))
        mt[(r < 0.9) & (P[:, 2] > H[2])] = 'hood_in'
        mt[(r >= 0.9) & (r < 1.0) & (P[:, 2] > H[2] + 3.0)] = 'hood_edge'; return mt
    m.add(hood, 'hood', 'hood', hood_tex)
    m.add(cone(hc + V(0, 3.0, -5.5), hc + V(0 + hr[0], -2.5, -10.5 + hr[2] * 0.6), 2.8, 0.7), 'hood', 'hood')
    # face
    lk = p['look']
    if p['blink']:
        eye = {(0, 0): '#7a4c34', (1, 0): '#7a4c34'}
    else:
        eye = {(0, -1): '#2e1c22', (0, 0): '#257a70', (0, 1): '#5ec29c', (1, -1): '#2e1c22', (1, 0): '#0a1f2c', (1, 1): '#f2f6ff'}
    if HI:
        eye = EYE_HI_BLINK if p['blink'] else EYE_HI
    for s in (-1, 1):
        m.stamps.append((H + V(2.4 * s + 0.5 * lk, 0.0, 5.95), eye, V(0.2 * s, 0, 1), s > 0))
    if HI:
        m.stamps.append((H + V(0, -4.0, 6.0), MOUTH_HI[p['mouth']], V(0, 0, 1)))
    mo = {0: {(0, 0): '#a86a4a', (1, 0): '#a86a4a'}, 1: {(0, 0): '#4c1631', (1, 0): '#8e2240'},
          2: {(0, 0): '#4c1631', (1, 0): '#4c1631', (0, 1): '#8e2240', (1, 1): '#4c1631'}}[p['mouth']]
    if not HI:
        m.stamps.append((H + V(-0.5, -4.0, 6.0), mo, V(0, 0, 1)))
    # bow in the left hand: limbs curve away from the archer
    lh = p['lh'] + V(0, b * 0.6, 0)
    up = p['bow_up'] / np.linalg.norm(p['bow_up'])
    face = p['bow_face'] - (p['bow_face'] @ up) * up; face /= np.linalg.norm(face)
    pts = []
    for t in np.linspace(-1, 1, 9):
        pts.append(lh + up * t * 13.5 + face * (2.6 * (1 - t * t) - 1.0) * (1 + 0.5 * p['draw']) - face * 0.0)
    for i in range(8):
        r = 1.05 - 0.55 * abs(i - 3.5) / 3.5
        m.add(cone(pts[i], pts[i + 1], r, r), 'wood', 'bow')
    m.add(cone(lh - up * 1.3, lh + up * 1.3, 1.2, 1.2), 'leather', 'bow')
    nock = pts[0] * 0 + (pts[0] + pts[-1]) / 2
    rh = p['rh'] + V(0, b * 0.6, 0)
    if p['draw'] > 0 or p['arrow']:
        nock = nock + (rh - nock) * min(1.0, 0.3 + p['draw'])
    m.lines.append((pts[0], nock, '#c8dbf0', 1.5)); m.lines.append((nock, pts[-1], '#c8dbf0', 1.5))
    if p['arrow']:
        d = lh + face * 2.5 - nock; d /= np.linalg.norm(d)
        tip = nock + d * 19
        m.lines.append((nock, tip, '#a86a4a', 1.5))
        m.dots.append((tip, '#f2f6ff', 0.0)); m.dots.append((nock - d * 0.6, '#d0404a', 0.0))
    if p['flight']:
        d = V(0, 0.02, 1.0); st = V(1.5, 34 + b, 18 + 16 * p['flight'])
        m.lines.append((st, st + d * 12, '#a86a4a', 99)); m.dots.append((st + d * 12.5, '#f2f6ff', 0.5, 99))
        for k in range(3):
            m.dots.append((st - d * (2 + 3 * k), '#9db5da', 0.0, 99))
    m.glow = None
    return m, MATS


def length3(v):
    return np.sqrt((v * v).sum(-1))
