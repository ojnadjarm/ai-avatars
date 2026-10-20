"""Grok: plumed knight in steel and gold with red cape, sword and kite shield; bespoke model + per-frame poses."""
import numpy as np
from core import (Model, V, sphere, ellipsoid, cone, torus, box, warp, inter, sub, rot_x, rot_z, rot_y, frame_to)
from rig import mats, ik, gait, root_path, follow, foot, swing_hand, yaw, lag, TAU
from hands import add_hand

MATS = mats(
    steel=('steel', {'kind': 'metal'}), dsteel=('steel', {'kind': 'metal', 'bias': -1.4}), gold=('gold', {'kind': 'metal'}),
    red=('red', {'wrap': 0.35, 'gamma': 1.1}), cape_in='cape_in', plume=('red', {'wrap': 0.5, 'gamma': 0.9, 'bias': 0.3}),
    plume_s=('red', {'wrap': 0.5, 'bias': -0.8}), dark='dark', leather=('leather', {'bias': -1.0}),
    blade=('steel', {'kind': 'metal', 'bias': 0.6}),
)
MATS['hand'] = dict(MATS['steel'], bias=-0.5)
HAND = 1.3
ANIMS = {'idle': 6, 'walk': 8, 'talk': 4, 'guard': 8}
HI = False
HEAD_Y = 44
GAIT = dict(stride=4.2, lift=1.9, bob_amp=2.2, sway=1.3, hip_yaw=0.07, sh_yaw=0.06, arm=0.28, stance=0.66, heel=0.3, arm_lag=0.09)
PORTRAIT = [('talk', 0), ('idle', 2), ('talk', 1), ('guard', 4)]
PFRAME = (2.5, 0.42)

LION = {(0, -2): '#fff2b0', (1, -2): '#f2c45a', (-1, -1): '#f2c45a', (0, -1): '#fff2b0', (1, -1): '#b8862e',
        (0, 0): '#f2c45a', (1, 0): '#f2c45a', (-1, 0): '#b8862e', (0, 1): '#f2c45a', (-1, 1): '#b8862e', (1, 1): '#b8862e',
        (-1, 2): '#b8862e', (1, 2): '#6e4a1c', (2, -1): '#b8862e'}


def pose(anim, f):
    n = ANIMS[anim]; ph = f / n
    p = dict(b=0.0, lean=0.0, head=V(0, 0, 0), plume=V(0, 0, 0), cape=V(0, 0, 0), crouch=0.0,
             rh=V(-10.0, 21.0, 2.0), lh=V(9.0, 24.0, 5.5), feet=[V(-4.0, 0, 0.3), V(4.0, 0, 0.3)],
             sword=V(0.05, -1, 0.35), shield_face=V(0.45, 0, 0.9), shield_up=V(0, 1, 0), glint=0, fold=0.0, chest=0.0, sx=0.0, pyaw=0.0, syaw=0.0, roll=0.0,
             fpitch=(0.0, 0.0), pads=V(0, 0, 0), rgrip='relaxed', lgrip='relaxed', rpalm=None, lpalm=None, rpoint=None, lpoint=None)
    if anim == 'idle':
        br = np.sin(TAU * ph)
        p['b'] = 0.5 * br; p['chest'] = 0.5 * br
        p['plume'] = V(lag(ph, 0.8, 0.3), lag(ph, 0.4, 0.2), lag(ph, 1.0, 0.25))
        p['cape'] = V(lag(ph, 0.5, 0.35), 0, lag(ph, 0.6, 0.3))
        p['head'] = V(0, 0.2 * br, 0)
        p['fold'] = 0.4 * br
        p['glint'] = 1 if f == 2 else 0
    elif anim == 'walk':
        # knight's armoured gait: wide stance, long double support, hard drop into the down pose, rolling weight shift;
        # plume, cape and pauldrons are heavy springs that overshoot on every heel strike
        g = gait(ph, **GAIT); rp = root_path(**GAIT)
        (z0, y0, a0), (z1, y1, a1) = g['feet']
        p['b'] = g['b']; p['lean'] = 1.6; p['sx'] = g['sway']; p['pyaw'] = g['pyaw']; p['syaw'] = g['syaw']
        p['roll'] = -0.45 * g['sway']; p['crouch'] = 0.35 * (-g['b'] / GAIT['bob_amp'])
        p['feet'] = [V(-4.4, y0, z0 + 0.4), V(4.4, y1, z1 + 0.4)]; p['fpitch'] = (a0, a1)
        th_r, th_l = g['arms']
        p['rh'] = swing_hand(V(-10, 22.0, 4.6), V(-7.6, 34.5, 0.6), th_r, bend=0.5)
        p['lh'] = V(9.0, 24.5, 5.5) + V(0, 0, 1.6 * th_l)
        sw = follow(rp, 2.6, 0.4, ph)
        p['sword'] = V(0.05 - 0.15 * sw[0], -1, 0.35 + 0.5 * th_r - 0.2 * sw[2])
        pl = follow(rp, 2.6, 0.25, ph); cp = follow(rp, 1.4, 0.3, ph); pd = follow(rp, 3.2, 0.3, ph)
        p['plume'] = V(-1.2 * pl[0], 0.9 * pl[1], -1.6 - 1.0 * pl[1] - 1.2 * pl[2])
        p['cape'] = V(-2.0 * cp[0], 0, -2.4 - 2.2 * cp[1] - 1.8 * cp[2])
        p['pads'] = V(0, 1.1 * pd[1], 0)
        p['head'] = V(-0.3 * g['sway'], 0.3 * (gait(ph - 0.05, **GAIT)['b'] - g['b']), 0)
        p['fold'] = TAU * ph + 1.5 * cp[0]
    elif anim == 'talk':
        p['head'] = V(0, [0, -0.5, 0, -0.3][f], 0.3)
        p['rh'] = [V(-9.5, 25, 6), V(-10, 28.5, 7.5), V(-9.5, 26.5, 7), V(-10.5, 29, 7)][f]
        p['sword'] = V(0.05, -1, 0.8)
        p['plume'] = V(lag(ph, 0.5, 0.25), 0, lag(ph, 0.6, 0.3))
        p['cape'] = V(lag(ph, 0.3, 0.3), 0, 0)
        p['b'] = [0, -0.3, 0, -0.2][f]
    elif anim == 'guard':
        # ready, brace, shield sweep up, raise, impact, hold, recover, settle
        p['b'] = [0, -1.0, -1.6, -2.0, -2.4, -2.0, -1.0, -0.3][f]
        p['crouch'] = [0, 0.4, 0.7, 1.0, 1.0, 1.0, 0.5, 0.1][f]
        p['lean'] = [0, 1.0, 1.8, 2.2, 1.2, 2.0, 1.2, 0.3][f]
        p['lh'] = [V(9.0, 24.0, 5.5), V(8, 26, 7), V(5.5, 30, 9.5), V(3, 32, 11), V(3, 32, 10),
                   V(3, 32, 11), V(6.5, 28, 7), V(9, 24.2, 5.6)][f]
        p['shield_face'] = [V(0.45, 0, 0.9), V(0.6, 0, 0.9), V(0.4, 0, 1), V(0.05, 0.1, 1), V(0.05, 0.15, 1),
                            V(0.05, 0.1, 1), V(0.6, 0, 1), V(0.45, 0, 0.9)][f]
        p['shield_up'] = [V(0, 1, 0), V(-0.2, 1, 0), V(-0.25, 1, 0.1), V(-0.1, 1, 0.1), V(-0.1, 1, 0.1),
                          V(-0.1, 1, 0.1), V(-0.1, 1, 0), V(0, 1, 0)][f]
        p['rh'] = [V(-10, 21, 2), V(-10.5, 22, 1), V(-11, 24, -1), V(-11, 25, -2), V(-11, 25.5, -2.5),
                   V(-11, 25, -2), V(-10.5, 22.5, 0), V(-10, 21, 1.5)][f]
        p['sword'] = [V(0.05, -1, 0.35), V(0.1, -1, 0.1), V(0.2, -0.6, -0.8), V(0.3, -0.3, -1), V(0.3, -0.3, -1),
                      V(0.3, -0.3, -1), V(0.1, -1, -0.2), V(0.05, -1, 0.3)][f]
        p['feet'] = [V(-4.0, 0, 0.3), V(4.0, 0, 0.3)] if f in (0, 7) else [V(-5.0, 0, -2.2), V(4.6, 0, 2.6)]
        p['plume'] = V(0, [0, -0.5, -0.8, -0.6, 0.6, 0.2, 0, 0][f], [0, 0.5, 0.6, 0.2, -2.0, -1.2, -0.4, 0][f])
        p['cape'] = V(0, 0, [0, 0.4, 0.4, 0.0, -1.8, -1.0, -0.3, 0][f])
        p['glint'] = {3: 1, 4: 2, 5: 1}.get(f, 0)
    return p


def build(anim, f):
    p = pose(anim, f)
    m = Model(); b = p['b']; ln = p['lean']; cr = p['crouch']; m.sel = {'hand'}
    for g, k in (('leg', 0.8), ('body', 1.0), ('helm', 0.6), ('plume', 1.0), ('pad', 0.6)):
        m.group(g, k)
    sx = p['sx']
    pel = V(sx, 22 + b, -0.6 * cr)
    chest = V(0.6 * sx, 31 + b + 0.2 * p['chest'], 0.5 * ln)
    neck = V(0.4 * sx, 37.4 + b, 0.8 * ln)
    # legs: greaves, knee cops, sabatons
    for side, ft in ((-1, p['feet'][0]), (1, p['feet'][1])):
        hip = pel + yaw(V(3.4 * side, -1.6, 0), p['pyaw'])
        ank, fc, fr = foot(ft, p['fpitch'][(side + 1) // 2], 2.4, V(0, 1.4, 1.4), toe=3.2)
        kn = ik(hip, ank, 9.6, 9.4, V(0.15 * side, 0.1, 1))
        m.add(cone(hip, kn, 3.3, 2.7), 'steel', 'leg')
        m.add(cone(kn, ank, 2.8, 2.1), 'steel', 'leg')
        m.add(sphere(kn + V(0, 0.3, 1.2), 1.9), 'gold', None)
        m.add(ellipsoid(fc, (2.4, 1.6, 3.4), rot=fr), 'dsteel', None)
    # fauld with red tabard panel
    def fauld_tex(P, mt):
        mt = mt.copy()
        mt[(np.abs(P[:, 0]) < 2.6) & (P[:, 2] > 1.0)] = 'red'
        mt[np.abs(P[:, 1] - (pel[1] + 1.2)) < 0.6] = 'gold'
        return mt
    fl = inter(cone(pel + V(0, 3.5, 0), pel + V(0, -5, 0.2), 6.6, 7.6), lambda P: (pel[1] - 5.6) - P[:, 1])
    m.add(warp(fl, lambda P: np.stack([0 * P[:, 0], 0 * P[:, 0], 0.12 * (p['feet'][0][2] + p['feet'][1][2]) * np.clip((pel[1] - P[:, 1]) / 6, 0, 1)], 1)), 'steel', None, fauld_tex)
    # breastplate with gold filigree and lion
    def chest_tex(P, mt):
        mt = mt.copy(); q = P - chest
        rim = np.abs(np.sqrt((q[:, 0] / 6.6) ** 2 + ((q[:, 1] + 1) / 6.2) ** 2) - 0.86) < 0.07
        mt[rim & (q[:, 2] > 1.5)] = 'gold'
        return mt
    m.add(ellipsoid(chest, (7.4, 7.2, 5.4)), 'steel', 'body', chest_tex)
    m.add(ellipsoid(pel + V(0, 4.0, 0), (6.0, 4.0, 4.4)), 'steel', 'body', chest_tex)
    m.stamps.append((chest + V(0, -0.4, 5.5), LION, V(0, 0, 1)))
    m.add(torus(neck + V(0, -0.8, 0), 3.4, 1.4), 'gold', None)
    # cape
    cp = p['cape']
    def cape_w(P):
        k = np.clip((neck[1] - P[:, 1]) / 26, 0, 1) ** 1.5
        return np.stack([cp[0] * k, 0 * k, cp[2] * k], 1)
    capec = inter(cone(neck + V(0, 0, -2.2), V(0, 7 + b * 0.3, -5.0 - cr), 7.6, 10.4),
                  lambda P: np.maximum(P[:, 2] - (-1.6 - 0.04 * (neck[1] - P[:, 1])), (6.5 + b * 0.3) - P[:, 1]))
    def cape_f(P):
        q = P - cape_w(P); a = np.arctan2(q[:, 0], -q[:, 2]); k = np.clip((neck[1] - q[:, 1]) / 26, 0, 1)
        return capec(q) - 0.6 * k * np.sin(a * 6 + p['fold']) - 0.25 * k * np.sin(a * 11 - p['fold'])
    def cape_tex(P, mt):
        mt = mt.copy(); q = P - cape_w(P)
        mt[q[:, 2] > -1.9 - 0.04 * (neck[1] - q[:, 1])] = 'cape_in'; return mt
    m.add(cape_f, 'red', None, cape_tex)
    # arms with pauldrons
    for side, hand in ((-1, p['rh']), (1, p['lh'])):
        hand = hand + V(0, b * 0.6, 0)
        sh = V(0.5 * sx, 34.5 + b + side * p['roll'], 0.5 * ln) + yaw(V(7.6 * side, 0, 0), p['syaw'])
        el = ik(sh, hand, 7.2, 7.4, V(side * 0.7, -0.3, -1))
        def pad_tex(P, mt, sh=sh + p['pads']):
            mt = mt.copy(); q = P - sh
            mt[np.abs(q[:, 1] + 0.4 - 0.25 * np.abs(q[:, 2])) < 0.55] = 'gold'; return mt
        m.add(ellipsoid(sh + V(0.8 * side, 1.4, 0) + p['pads'], (4.6, 3.6, 4.4), rot=rot_z(-0.35 * side)), 'steel', 'pad', pad_tex)
        m.add(cone(sh, el, 2.6, 2.3), 'dsteel', 'arm%d' % side)
        m.add(sphere(el, 2.0), 'gold', None)
        ax = p['sword'] / np.linalg.norm(p['sword']) if side < 0 else p['shield_up'] / np.linalg.norm(p['shield_up'])
        wr = add_hand(m, el, hand, side, 'grip', axis=ax, size=HAND, cuff=('dsteel', 2.25))
        m.add(cone(el, wr, 2.6, 2.1), 'steel', 'arm%d' % side)
        m.group('arm%d' % side, 0.5)
    # head: great helm with T visor, gold crest
    H = V(0.3 * sx, 44.0 + b, 0.9 * ln) + p['head']
    def helm_tex(P, mt):
        mt = mt.copy(); q = P - H
        front = q[:, 2] > 3.2
        mt[front & (np.abs(q[:, 1] - 0.6) < 0.75) & (np.abs(q[:, 0]) < 4.4)] = 'dark'
        mt[front & (np.abs(q[:, 0]) < 0.75) & (q[:, 1] < 0.6) & (q[:, 1] > -4.4)] = 'dark'
        mt[front & (np.abs(np.abs(q[:, 0]) - 1.7) < 0.5) & (q[:, 1] > 1.5) & (q[:, 1] < 4.5)] = 'gold'
        mt[np.abs(q[:, 1] + 4.2) < 0.55] = 'gold'
        return mt
    m.add(ellipsoid(H, (6.3, 7.0, 6.5)), 'steel', 'helm', helm_tex)
    m.add(ellipsoid(H + V(0, -2.8, 2.0), (5.4, 4.6, 5.0)), 'steel', 'helm', helm_tex)
    m.add(ellipsoid(H + V(0, -0.6, 3.0), (5.0, 4.6, 4.2)), 'steel', 'helm', helm_tex)
    m.add(ellipsoid(H + V(0, 3.0, -0.6), (1.0, 4.6, 6.6)), 'gold', None)
    for s in (-1, 1):
        if HI:
            m.stamps.append((H + V(2.2 * s, 0.6, 7.3), {(0, 0): '#9db5da', (1, 0): '#f2f6ff' if s > 0 else '#5a76ac'}, V(0.2 * s, 0, 1), s > 0))
        else:
            m.stamps.append((H + V(2.0 * s, 0.6, 7.3), {(0, 0): '#5a76ac'}, V(0.2 * s, 0, 1)))
    # plume: chain arcing back
    pl = p['plume']
    c0 = H + V(0, 6.6, 0.8)
    c1 = H + V(0.2, 10.6, -2.6) + pl * 0.35
    c2 = H + V(0.4, 10.2, -8.4) + pl * 0.75
    c3 = H + V(0.6, 6.0, -12.4) + pl * 1.2
    c4 = H + V(0.8, 1.2, -13.4) + pl * 1.6
    def plume_tex(P, mt):
        mt = mt.copy(); s = np.sin((P[:, 1] - H[1]) * 1.3 + (P[:, 2] - H[2]) * 0.9 + P[:, 0] * 1.2)
        mt[s > 0.55] = 'plume_s'; return mt
    for a_, b_, r0, r1 in ((c0, c1, 1.6, 2.6), (c1, c2, 2.6, 2.7), (c2, c3, 2.7, 2.0), (c3, c4, 2.0, 0.7)):
        m.add(cone(a_, b_, r0, r1), 'plume', 'plume', plume_tex)
    # sword in the right hand
    rh = p['rh'] + V(0, b * 0.6, 0)
    sd = p['sword'] / np.linalg.norm(p['sword'])
    m.add(cone(rh - sd * 3.2, rh + sd * 1.0, 0.8, 0.8), 'leather', None)
    m.add(sphere(rh - sd * 3.6, 1.1), 'gold', None)
    perp = np.cross(sd, V(0, 0, 1)) if abs(sd[2]) < 0.9 else np.cross(sd, V(1, 0, 0))
    perp /= np.linalg.norm(perp)
    m.add(cone(rh + sd * 1.6 - perp * 3.0, rh + sd * 1.6 + perp * 3.0, 0.7, 0.7), 'gold', None)
    bl = rh + sd * 17.5
    m.add(cone(rh + sd * 2.0, bl, 1.25, 0.25), 'blade', None)
    # kite shield on the left arm
    lh = p['lh'] + V(0, b * 0.6, 0)
    up = p['shield_up'] / np.linalg.norm(p['shield_up'])
    fc = p['shield_face'] - (p['shield_face'] @ up) * up; fc /= np.linalg.norm(fc)
    rt = np.cross(up, fc)
    Rm = np.stack([rt, up, fc], 1)
    sc = lh + fc * 2.0 + up * 0.5
    def kite(P):
        q = (P - sc) @ Rm
        w = 5.2 * np.clip((q[:, 1] + 9.0) / 12.0, 0.12, 1.0)
        top = 4.0 - 0.18 * q[:, 0] ** 2 / 5
        dx = np.abs(q[:, 0]) - w; dy = np.maximum(q[:, 1] - top, -9.0 - q[:, 1])
        d2 = np.maximum(dx, dy)
        bow = -0.06 * q[:, 0] ** 2
        dz = np.abs(q[:, 2] - bow * 0.3) - 0.9
        return np.maximum(d2 * 0.8, dz)
    def kite_tex(P, mt):
        mt = mt.copy(); q = (P - sc) @ Rm
        w = 5.2 * np.clip((q[:, 1] + 9.0) / 12.0, 0.12, 1.0); top = 4.0 - 0.18 * q[:, 0] ** 2 / 5
        inner = (np.abs(q[:, 0]) < w - 1.1) & (q[:, 1] < top - 1.1) & (q[:, 1] > -7.6) & (q[:, 2] > 0)
        mt[inner] = 'red'
        mt[inner & (np.abs(q[:, 0]) < 0.6)] = 'gold'
        mt[inner & (np.abs(q[:, 1] - 0.4) < 0.6)] = 'gold'
        return mt
    m.add(kite, 'steel', None, kite_tex)
    m.stamps.append((sc + fc * 1.2 + up * 0.4, {(0, 0): '#fff2b0', (1, 0): '#f2c45a', (0, 1): '#b8862e', (1, 1): '#b8862e', (-1, 0): '#f2c45a'}, fc))
    if p['glint']:
        g = p['glint']
        cen = sc + fc * 1.6 + up * 2.6 + rt * 2.4
        m.dots.append((cen, '#f2f6ff', 1.0, 99))
        for k in range(1, 2 + g):
            for d in (V(1, 0, 0), V(-1, 0, 0), V(0, 1, 0), V(0, -1, 0)):
                m.dots.append((cen + d * k, '#c8dbf0' if k < 2 else '#7894c4', 1.0, 99))
    m.glow = None
    return m, MATS
