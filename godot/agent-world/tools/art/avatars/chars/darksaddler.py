"""DarkSaddler: purple-robed elder wizard with a violet crystal staff; bespoke model + per-frame poses."""
import numpy as np
from core import (pat, Model, V, sphere, ellipsoid, cone, torus, octa, warp, inter, rot_x, rot_z, frame_to)
from rig import mats, ik, gait, root_path, follow, foot, swing_hand, yaw, lag, TAU
from hands import add_hand

MATS = mats(
    robe=('purple', {'wrap': 0.35, 'gamma': 1.15}), inner='navy', gold=('gold', {'kind': 'metal'}),
    skin=('skin', {'kind': 'skin'}), beard=('beard', {'wrap': 0.6, 'gamma': 0.9, 'bias': 0.2}),
    beard_s=('beard', {'wrap': 0.6, 'gamma': 1.1, 'bias': -0.8}), silver=('silver', {'kind': 'metal'}),
    wood='wood', boot='boot', crystal=('crystal', {'kind': 'emis'}), hat=('purple', {'wrap': 0.2, 'gamma': 1.3}),
)
MATS['hand'] = dict(MATS['skin'], ao=0.25, bias=0.8)
HAND = 1.15
HAND_B = 0.5
ANIMS = {'idle': 6, 'walk': 8, 'talk': 4, 'cast': 8}
HI = False
HEAD_Y = 44
GAIT = dict(stride=3.6, lift=1.7, bob_amp=1.1, sway=0.8, hip_yaw=0.1, sh_yaw=0.12, arm=0.32, stance=0.64, heel=0.35)
PORTRAIT = [('talk', 0), ('idle', 4), ('talk', 1), ('cast', 4)]
PFRAME = (2.5, 0.56)
EYE_C = {'k': '#2e1c22', 'l': '#4f3028', 'w': '#c8dbf0', 'i': '#5a76ac', 'I': '#32447c', 'p': '#06071a', 'h': '#f2f6ff'}
EYE_HI = pat(['kkkkkkk', 'kwhpiIw', '.wIpIw.', '..lll..'], EYE_C, 3, 1)
EYE_HI_BLINK = pat(['......', '.kkkk.', 'llllll'], EYE_C, 3, 1)
MOUTH_HI = {1: pat(['kkkk', '.kk.'], {'k': '#2e1c22'}, 2, 0), 2: pat(['kkkkk', 'krrrk', '.kkk.'], {'k': '#2e1c22', 'r': '#4c1631'}, 2, 0)}
EMIS_COL = (190, 140, 255)


def pose(anim, f):
    n = ANIMS[anim]; ph = f / n
    p = dict(b=0.0, lean=0.0, head=V(0, 0, 0), hat_tip=V(0, 0, 0), beard=V(0, 0, 0), hem=V(0, 0, 0),
             lh=V(10.0, 25.0, 3.5), rh=V(-8.4, 24.0, 2.6), feet=[V(-3.4, 0, 0.5), V(3.4, 0, 0.5)],
             staff_dir=V(0.02, 1, -0.02), staff_len=(25.0, 35.0), glow=0.35, mouth=0, blink=False,
             motes=[], burst=0.0, brim=0.0, cuff_open=0.0, fold=0.0, sx=0.0, syaw=0.0, fpitch=(0.0, 0.0), legs=(0.0, 0.0), kick=(0.0, 0.0),
             staff_bot=None, rgrip='relaxed', lgrip='relaxed', rpalm=None, lpalm=None, rpoint=None, lpoint=None)
    if anim == 'idle':
        br = np.sin(TAU * ph)
        p['b'] = 0.45 * br
        p['head'] = V(0.3 * lag(ph, 1, 0.1), 0.35 * br, 0)
        p['hat_tip'] = V(lag(ph, 1.0, 0.25), 0, lag(ph, 0.6, 0.3))
        p['beard'] = V(lag(ph, 0.5, 0.2), 0, lag(ph, 0.35, 0.15))
        p['rh'] = V(-8.2, 24.3 + 0.4 * br, 3.2 + 0.4 * np.sin(TAU * ph * 2))
        p['glow'] = 0.45 + 0.25 * np.sin(TAU * ph)
        p['fold'] = 0.25 * br
        p['blink'] = f == 4
        p['motes'] = [(a, 0) for a in (ph, ph + 0.33, ph + 0.66)]
    elif anim == 'walk':
        # elder's gait: short stoop-shouldered step, staff planted with the far foot like a cane, robe dragged by the knees
        g = gait(ph, **GAIT); rp = root_path(**GAIT)
        (z0, y0, a0), (z1, y1, a1) = g['feet']
        p['b'] = g['b']; p['lean'] = 2.0; p['sx'] = g['sway']; p['syaw'] = g['syaw']
        p['feet'] = [V(-3.4, y0, z0 + 0.6), V(3.4, y1, z1 + 0.6)]; p['fpitch'] = (a0, a1); p['legs'] = (z0, z1)
        p['kick'] = tuple(max(0.0, z / GAIT['stride']) ** 1.5 + 0.6 * y / GAIT['lift'] for z, y in ((z0, y0), (z1, y1)))
        drag = follow(rp, 1.5, 0.3, ph)
        p['hem'] = V(-1.2 * drag[0], 0, -0.9 - 1.4 * drag[2] + 0.6 * drag[1])
        sh = V(-6.3, 34.3, 0.7)
        p['rh'] = swing_hand(V(-8.0, 24.5, 2.6), sh, g['arms'][0]) + V(0.6 * g['sway'], 0, 0)
        sb = V(11.0, 0.5 * y0, 1.4 + 1.15 * z0)
        p['staff_bot'] = sb
        p['lh'] = V(10.0 + 0.4 * g['sway'], 25.0 + 0.3 * y0, 3.0 + 0.4 * z0 + 0.3 * y0)
        hat = follow(rp, 1.7, 0.22, ph); brd = follow(rp, 2.6, 0.35, ph)
        p['hat_tip'] = V(-2.2 * hat[0], 0, -1.6 - 3.0 * hat[1] - 1.5 * hat[2])
        p['beard'] = V(-1.3 * brd[0], -0.5 * brd[1], -0.6 - 1.0 * brd[2] - 0.6 * brd[1])
        p['head'] = V(0.2 * g['sway'], -0.25 * (g['b'] - gait(ph - 0.06, **GAIT)['b']), 1.0)
        p['fold'] = 1.4 * drag[0] + TAU * ph * 0.5
        p['glow'] = 0.4 + 0.15 * np.sin(TAU * ph * 2)
    elif anim == 'talk':
        nod = [0, -0.6, 0.1, -0.4][f]
        p['head'] = V(0, nod, 0.3)
        p['mouth'] = [0, 1, 0, 2][f]
        p['rh'] = [V(-8, 28, 5.5), V(-9.5, 31.5, 6.5), V(-8.5, 29.5, 6), V(-10, 32.5, 5.5)][f]
        p['beard'] = V(0, -0.5 * (p['mouth'] > 0), 0.3 * (p['mouth'] > 0))
        p['hat_tip'] = V(lag(ph, 0.7, 0.25), 0, lag(ph, 0.5, 0.3))
        p['b'] = [0, -0.2, 0.1, -0.1][f]
        p['glow'] = 0.4
        p['rgrip'] = 'open'; p['rpalm'] = V(0, 1, 0.2); p['rpoint'] = V(-0.7, 0.3, 1)
    elif anim == 'cast':
        p['b'] = [0, -1.6, -1.0, 0.6, 0.8, 0.4, -0.4, 0][f]
        p['lean'] = [0, -1.5, -0.5, 1.5, 2.0, 1.6, 0.6, 0][f]
        p['lh'] = [V(10, 25, 3.5), V(10.5, 22, 0.5), V(9, 35, 4), V(6, 46, 7), V(5.5, 48, 8),
                   V(5.5, 47.5, 8), V(8.5, 36, 5), V(10, 26, 3.5)][f]
        p['staff_dir'] = [V(0.02, 1, -0.02), V(0.1, 1, -0.25), V(0, 1, 0.15), V(-0.15, 1, 0.55), V(-0.2, 1, 0.65),
                          V(-0.2, 1, 0.6), V(0, 1, 0.2), V(0.02, 1, 0)][f]
        p['rh'] = [V(-8.4, 24, 2.6), V(-8, 29, 5), V(-10, 33, 6), V(-12, 39, 6), V(-13, 41, 7),
                   V(-12.5, 40, 7), V(-9, 30, 5), V(-8.4, 24.5, 3)][f]
        p['glow'] = [0.35, 0.5, 0.7, 0.95, 1.0, 0.85, 0.55, 0.4][f]
        p['burst'] = [0, 0, 0, 0.3, 1.0, 0.7, 0.2, 0][f]
        p['hem'] = V([0, 0, 0, 0.6, 1.4, 1.0, 0.4, 0][f], 0, [0, 0.4, 0, -0.8, -1.8, -1.2, -0.4, 0][f])
        p['hat_tip'] = V([0, 0.4, 0.2, -0.6, -1.5, -1.2, -0.3, 0][f], 0, [0, 0.5, 0, -1.0, -2.5, -2.0, -0.8, 0][f])
        p['beard'] = V([0, 0, 0, 0.3, 0.8, 0.6, 0.2, 0][f], 0, [0, 0.3, 0, -0.4, -0.9, -0.6, -0.2, 0][f])
        p['head'] = V(0, [0, -0.6, -0.2, 0.6, 0.8, 0.6, 0.1, 0][f], [0, 0.6, 0.2, 0.2, 0.0, 0.2, 0.3, 0][f])
        p['mouth'] = [0, 0, 0, 1, 2, 1, 0, 0][f]
        p['brim'] = [0, 0, 0, -0.05, -0.12, -0.08, 0, 0][f]
        p['cuff_open'] = p['burst']
        p['rgrip'] = ['relaxed', 'relaxed', 'open', 'open', 'open', 'open', 'relaxed', 'relaxed'][f]
        p['rpalm'] = [None, None, V(0, 1, 0.1), V(0, 1, 0.1), V(0, 1, 0.1), V(0, 1, 0.1), None, None][f]
        p['rpoint'] = [None, None, V(-0.3, 0.1, 1), V(-0.3, 0.1, 1), V(-0.3, 0.1, 1), V(-0.3, 0.1, 1), None, None][f]
        p['fold'] = p['burst'] * 1.2
    return p


def build(anim, f):
    p = pose(anim, f)
    m = Model(); b = p['b']; ln = p['lean']; m.sel = {'hand'}
    m.group('robe', 1.6); m.group('head', 0.9); m.group('beard', 1.0); m.group('hat', 1.4)
    sx = p['sx']
    chest = V(0.6 * sx, 31 + b, 0.4 * ln)
    neck = V(0.4 * sx, 37.5 + b, 0.7 * ln)
    hem = p['hem']; lz = p['legs']; kk = p['kick']

    def hem_h(q):
        w = np.clip(0.5 + q[:, 0] / 7.0, 0, 1)
        return 0.25 + 6.0 * ((1 - w) * kk[0] + w * kk[1]) * np.clip((q[:, 2] - 2.0) / 5.0, 0, 1)

    def robe_warp(P):
        k = np.clip((32 + b - P[:, 1]) / 31.0, 0, 1) ** 2
        w = np.clip(0.5 + P[:, 0] / 9.0, 0, 1)
        knee = 0.8 * ((1 - w) * lz[0] + w * lz[1]) * np.clip((26 + b - P[:, 1]) / 14.0, 0, 1) * (0.35 + 0.65 * np.clip(P[:, 1] / 12.0, 0, 1))
        return np.stack([hem[0] * k + sx * (1 - k) * 0.8, 0 * k, hem[2] * k + knee + 0.035 * ln * (P[:, 1] - 10)], 1)

    def robe_tex(P, mt):
        q = P - robe_warp(P)
        mt = mt.copy()
        front = q[:, 2] > 0.8
        w = 1.4 + np.clip(30 + b - q[:, 1], 0, 40) * 0.055
        ax = np.abs(q[:, 0])
        mt[front & (ax < w)] = 'inner'
        lat = (np.abs(((q[:, 1] * 0.5 + q[:, 0] * 0.5) % 2.2) - 1.1) < 0.2) | (np.abs(((q[:, 1] * 0.5 - q[:, 0] * 0.5) % 2.2) - 1.1) < 0.2)
        mt[front & (ax < w - 0.6) & lat & (q[:, 1] < 22 + b)] = 'gold'
        mt[front & (ax >= w) & (ax < w + 1.15) & (q[:, 1] < 34 + b)] = 'gold'
        mt[q[:, 1] < hem_h(q) + 2.05] = 'gold'
        ang = np.arctan2(q[:, 0], q[:, 2])
        mt[(np.abs(q[:, 1] - 4.6) < 0.7) & (np.abs(((ang * 8 / np.pi) % 1) - 0.5) < 0.12) & ~(front & (ax < w + 1.15))] = 'gold'
        return mt
    base = inter(cone((0, 30 + b, 0.3 * ln), (0, 3.2, 0.2), 6.0, 10.2), lambda P: hem_h(P) - P[:, 1])
    fph = p['fold']
    def folds(P):
        k = np.clip((28 + b - P[:, 1]) / 26.0, 0, 1)
        ang = np.arctan2(P[:, 0], P[:, 2])
        return base(P) - 0.55 * k * np.sin(ang * 7 + fph + 0.25 * P[:, 1] * 0.2) - 0.3 * k * np.sin(ang * 3 - fph * 0.7)
    skirt = warp(folds, robe_warp)
    m.add(skirt, 'robe', 'robe', robe_tex)
    m.add(ellipsoid(chest, (6.6, 6.8, 5.0)), 'robe', 'robe', robe_tex)
    # mantle over the shoulders, gold edge
    def mantle_tex(P, mt):
        mt = mt.copy(); mt[P[:, 1] < neck[1] - 6.3] = 'gold'; return mt
    mant = inter(ellipsoid(neck + V(0, -2.5, -0.4), (8.6, 5.2, 6.6)), lambda P: (neck[1] - 7.2) - P[:, 1])
    m.add(warp(mant, lambda P: np.stack([hem[0] * 0.15 + 0 * P[:, 0], 0 * P[:, 0], 0.1 * hem[2] + 0 * P[:, 0]], 1)), 'hat', None, mantle_tex)
    # sash
    m.add(torus((0, 24.2 + b, 0.25 * ln), 6.95, 0.95), 'inner')
    m.stamps.append((V(0, 24.2 + b, 7.6 + 0.25 * ln), {(0, 0): '#f2c45a', (1, 0): '#b8862e', (0, 1): '#b8862e', (-1, 0): '#fff2b0'}, V(0, 0, 1)))
    # collar
    def collar_tex(P, mt):
        mt = mt.copy(); mt[P[:, 1] > neck[1] + 0.9] = 'gold'; return mt
    m.add(torus(neck + V(0, 0.2, -0.6), 5.0, 1.5, rot=rot_x(-0.25)), 'robe', None, collar_tex)
    m.stamps.append((neck + V(0, -2.2, 5.4), {(0, 0): '#d0a8ee', (0, -1): '#a77ad0', (0, 1): '#5c3889'}, V(0, 0, 1)))
    # arms; the left hand grips the staff
    staff_axis = p['staff_dir'] / np.linalg.norm(p['staff_dir'])
    if p['staff_bot'] is not None:
        staff_axis = p['lh'] + V(0, b * 0.5, 0) - p['staff_bot']; staff_axis /= np.linalg.norm(staff_axis)
    for side, hand in ((-1, p['rh']), (1, p['lh'])):
        hand = hand + V(0, b * 0.5, 0)
        sh = V(0.5 * sx, 34.3 + b, 0.5 * ln) + yaw(V(6.3 * side, 0, 0), p['syaw'])
        el = ik(sh, hand, 7.4, 7.8, V(side * 0.8, -0.3, -1))
        m.add(cone(sh, el, 2.5, 2.7), 'robe', 'robe')
        g = 'rgrip' if side < 0 else 'lgrip'
        wr = add_hand(m, el, hand, side, p[g], p[g[0] + 'palm'], axis=staff_axis if side > 0 else None,
                      size=HAND, point=p[g[0] + 'point'], reach=0.3)
        d = wr - el; d /= np.linalg.norm(d)
        bell = 3.7 + 0.6 * p['cuff_open']
        def cuff_tex(P, mt, wr=wr, d=d):
            mt = mt.copy(); mt[((P - wr) @ d) > -1.3] = 'gold'; return mt
        sl = inter(cone(el, wr, 2.6, bell), lambda P, wr=wr, d=d: (P - wr) @ d)
        m.add(sl, 'robe', None, cuff_tex)
    # feet
    for ft, fp in zip(p['feet'], p['fpitch']):
        _, fc, fr = foot(ft, fp, 2.4, V(0, 1.4, 1.4))
        m.add(ellipsoid(fc, (2.1, 1.5, 3.1), rot=fr), 'boot')
    # staff
    sd = p['staff_dir'] / np.linalg.norm(p['staff_dir'])
    lh = p['lh'] + V(0, b * 0.5, 0)
    if p['staff_bot'] is not None:
        sd = lh - p['staff_bot']; sd /= np.linalg.norm(sd)
    bot = lh - sd * p['staff_len'][0]; top = lh + sd * p['staff_len'][1]
    bot[1] = max(bot[1], 0.3)
    mid = (bot + top) / 2 + V(0.5, 0, 0)
    m.add(cone(bot, mid, 0.85, 1.0), 'wood', 'staff')
    m.add(cone(mid, top, 1.0, 1.25), 'wood', 'staff')
    m.add(sphere(top + sd * 0.3 + V(0.8, 0, 0), 1.25), 'wood', 'staff')
    m.group('staff', 0.6)
    cc = top + sd * 4.6
    R = frame_to(sd)
    for k in range(3):
        a = TAU * k / 3 + 0.4
        off = R @ V(np.cos(a) * 2.6, 0, np.sin(a) * 2.6)
        m.add(cone(top + sd * 0.6, cc + off - sd * 0.4, 0.75, 0.45), 'silver', 'claw')
        m.add(cone(cc + off - sd * 0.4, cc + off * 0.55 + sd * 1.8, 0.45, 0.3), 'silver', 'claw')
    m.group('claw', 0.5)
    m.add(octa(cc, 2.5, sy=2.0, rot=R), 'crystal')
    # head
    H = V(0.3 * sx, 44 + b, 0.9 * ln) + p['head']
    m.add(sphere(H, 6.9), 'skin', 'head')
    m.add(ellipsoid(H + V(0, -1.4, 6.6), (1.3, 1.7, 1.3)), 'skin', 'head')
    def hair_tex(P, mt):
        mt = mt.copy(); a = np.arctan2(P[:, 0] - H[0], P[:, 2] - H[2])
        mt[np.sin(a * 9 + P[:, 1] * 0.15) > 0.45] = 'beard_s'; return mt
    m.add(ellipsoid(H + V(0, 0.2, -1.8), (7.3, 6.4, 6.4)), 'beard', 'hair', hair_tex)
    m.add(cone(H + V(0, -1.5, -3.2), V(0, 35 + b, -4.8 + 0.2 * ln) + p['beard'] * 0.4, 4.6, 3.0), 'beard', 'hair', hair_tex)
    m.group('hair', 1.2)
    for s in (-1, 1):
        m.add(ellipsoid(H + V(2.6 * s, 2.1, 6.0), (2.1, 0.75, 1.0), rot=rot_z(-0.3 * s)), 'beard')
        m.add(cone(H + V(0.4 * s, -3.3, 6.6), H + V(4.2 * s, -5.0, 5.4) + p['beard'] * 0.3, 1.35, 0.85), 'beard', 'beard')
    jaw = 0.6 if p['mouth'] else 0.0
    tip = V(0, 24.5 + b, 6.2 + 0.4 * ln) + p['beard'] + V(0, -jaw, 0)
    bmid = H + V(0, -10.5 - jaw, 6.2) + p['beard'] * 0.5

    def beard_tex(P, mt):
        mt = mt.copy()
        s = np.sin(P[:, 0] * 1.35 + np.sin(P[:, 1] * 0.45) * 1.3) > 0.55
        mt[s & (P[:, 1] < H[1] - 4.5)] = 'beard_s'
        return mt
    m.add(cone(H + V(0, -4.6 - jaw, 4.6), bmid, 5.0, 3.6), 'beard', 'beard', beard_tex)
    m.add(cone(bmid, tip, 3.6, 0.9), 'beard', 'beard', beard_tex)
    # eyes, mouth
    if p['blink']:
        eye = {(0, 0): '#4f3028', (1, 0): '#4f3028'}
    else:
        eye = {(0, 0): '#06071a', (0, -1): '#4f3028', (1, 0): '#9db5da'}
    if HI:
        eye = EYE_HI_BLINK if p['blink'] else EYE_HI
    for s in (-1, 1):
        m.stamps.append((H + V(2.5 * s, 0.6, 6.45), eye, V(0.25 * s, 0, 1), s > 0))
    if p['mouth'] and HI:
        m.stamps.append((H + V(0, -4.9, 7.2), MOUTH_HI[p['mouth']], V(0, 0, 1)))
    elif p['mouth']:
        mo = {(0, 0): '#2e1c22', (1, 0): '#2e1c22'} if p['mouth'] == 1 else {(0, 0): '#2e1c22', (1, 0): '#2e1c22', (0, 1): '#4c1631', (1, 1): '#2e1c22'}
        m.stamps.append((H + V(-0.4, -4.9, 7.2), mo, V(0, 0, 1)))
    # hat
    Hb = H + V(0, 6.4, -0.8)
    tilt = rot_x(0.16 + p['brim'])
    m.add(ellipsoid(Hb, (12.4, 1.1, 10.8), rot=tilt), 'hat', 'hat')
    m.add(ellipsoid(Hb + V(0, -0.5, 0), (12.0, 0.85, 10.4), rot=tilt), 'hat', 'hat')
    t = p['hat_tip']
    a0, a1 = Hb + V(0, 0.5, 0), Hb + V(0, 9.0, -1.2)
    a2 = Hb + V(1.2 + t[0] * 0.6, 14.0, -3.4 + t[2] * 0.6)
    a3 = Hb + V(4.2 + t[0] * 1.4, 16.2, -6.6 + t[2] * 1.4)
    m.add(cone(a0, a1, 6.6, 3.7), 'hat', 'hat')
    m.add(cone(a1, a2, 3.7, 2.0), 'hat', 'hat')
    m.add(cone(a2, a3, 2.0, 0.6), 'hat', 'hat')
    def band_tex(P, mt):
        return mt
    m.add(torus(Hb + V(0, 1.8, 0), 6.15, 1.35), 'silver', None, band_tex)
    m.stamps.append((Hb + V(0, 1.8, 7.5), {(0, 0): '#fff2b0', (0, -1): '#f2c45a', (0, 1): '#f2c45a', (1, -1): '#b8862e', (1, 1): '#b8862e'}, V(0, 0, 1)))
    star = {(0, 0): '#fff2b0', (1, 0): '#b8862e', (-1, 0): '#b8862e', (0, 1): '#b8862e', (0, -1): '#b8862e'}
    small = {(0, 0): '#f2c45a'}
    for (ang, hgt, pat) in ((0.7, 0.35, star), (-0.9, 0.55, small), (2.4, 0.4, star), (-2.2, 0.3, small), (3.3, 0.7, small), (0.1, 0.8, small)):
        c = a0 + (a1 - a0) * hgt
        r = 6.6 + (3.7 - 6.6) * hgt
        dirv = V(np.sin(ang), 0.25, np.cos(ang))
        m.stamps.append((c + V(np.sin(ang), 0, np.cos(ang)) * (r + 0.2), pat, dirv))
    for (ang, pat) in ((1.2, star), (-1.4, star), (2.8, small), (-0.4, small)):
        m.stamps.append((Hb + V(np.sin(ang) * 10.5, 1.0, np.cos(ang) * 9.6), pat, V(np.sin(ang) * 0.2, 1, np.cos(ang) * 0.2)))
    if anim == 'cast' and 2 <= f <= 6:
        m.add(sphere(p['rh'] + V(-0.4, b * 0.5 + 2.6, 2.4), 1.2 + 0.9 * p['burst']), 'crystal')
    # glow motes and burst (emissive overlay)
    g = p['glow']
    for ph, _ in p['motes']:
        a = TAU * ph
        pt = cc + V(np.cos(a) * 4.5, 1.5 + 3 * ((ph * 2) % 1), np.sin(a) * 4.5)
        m.dots.append((pt, '#d0a8ee' if g > 0.5 else '#a77ad0', 1.0, 0.0 if np.sin(a) > 0 else 2.0))
    if p['burst'] > 0:
        for k in range(10):
            a = TAU * k / 10
            r = 4 + 7 * p['burst']
            m.dots.append((cc + V(np.cos(a) * r, np.sin(a) * r * 0.9, 1.0), '#f2f6ff' if k % 2 else '#ff9ccc', 1.0))
    m.glow = (cc, g, EMIS_COL)
    mt = dict(MATS); mt['crystal'] = dict(MATS['crystal'], bias=(g - 0.5) * 1.6)
    return m, mt
