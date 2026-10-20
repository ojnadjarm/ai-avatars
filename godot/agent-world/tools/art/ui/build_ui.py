#!/usr/bin/env python3
"""UI kit in the T704 title look: 9-slice glass panels with gold hairlines and filigree, widgets, keycaps, backdrop."""
import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'title')))
import px  # noqa: E402
import ui as title_ui  # noqa: E402
from bg import C  # noqa: E402

P = px.P
OUT = os.path.join(P, 'assets', 'ui')
px.OUT = OUT
MENU = os.path.join(P, 'assets', 'menu')
MANIFEST = {}
PALETTE = np.array(list(C.values()), np.float32)

# Filigree corners, top-left orientation; digits are gold g0..g3, m/M magenta gems, a space leaves the pixel alone.
FILIGREE = [
    "3221110",
    "2m2    ",
    "22 1   ",
    "1 1 0  ",
    "1  0   ",
    "1      ",
    "0      ",
]
FILIGREE_GEM = [
    "32221110",
    "2M2     ",
    "2mm1    ",
    "21 2 0  ",
    "1  1 1  ",
    "1   0   ",
    "1  0    ",
    "0       ",
]
KNOT = ["321", "2  ", "1  "]
KEYS = {'0': 'g0', '1': 'g1', '2': 'g2', '3': 'g3', 'm': 'm2', 'M': 'm3', 'n': 'n4', 'd': 'n0'}


class Kit:
    """RGBA canvas whose every colour is a palette key."""

    def __init__(self, w, h):
        self.w, self.h = w, h
        self.rgb = np.zeros((h, w, 3), np.float32)
        self.a = np.zeros((h, w), np.float32)

    def fill(self, col, a=1.0, x0=0, y0=0, x1=None, y1=None):
        x1 = self.w if x1 is None else x1
        y1 = self.h if y1 is None else y1
        self.rgb[y0:y1, x0:x1] = C[col]
        self.a[y0:y1, x0:x1] = a

    def dot(self, x, y, col, a=1.0):
        if 0 <= x < self.w and 0 <= y < self.h:
            self.rgb[y, x] = C[col]
            self.a[y, x] = a

    def clear(self, x, y):
        self.a[y, x] = 0

    def hline(self, y, col, a=1.0, x0=0, x1=None):
        self.fill(col, a, x0, y, x1, y + 1)

    def vline(self, x, col, a=1.0, y0=0, y1=None):
        self.fill(col, a, x, y0, x + 1, y1)

    def glyph(self, rows, x, y, sx=1, sy=1, keys=KEYS):
        for j, r in enumerate(rows):
            for i, ch in enumerate(r):
                if ch != ' ':
                    self.dot(x + i * sx, y + j * sy, keys.get(ch, ch))

    def corners(self, rows, inset=0):
        """Stamp a top-left glyph mirrored into all four corners."""
        for sx, ox in ((1, inset), (-1, self.w - 1 - inset)):
            for sy, oy in ((1, inset), (-1, self.h - 1 - inset)):
                self.glyph(rows, ox, oy, sx, sy)

    def mask(self, m, col, a=1.0, ox=0, oy=0):
        h, w = m.shape
        sub_rgb = self.rgb[oy:oy + h, ox:ox + w]
        sub_a = self.a[oy:oy + h, ox:ox + w]
        sub_rgb[m] = C[col]
        sub_a[m] = a

    def save(self, name, margin=None, frames=1, kind='nine', **extra):
        os.makedirs(OUT, exist_ok=True)
        rgba = np.dstack([self.rgb, self.a * 255]).clip(0, 255).astype(np.uint8)
        Image.fromarray(rgba, 'RGBA').save(os.path.join(OUT, name + '.png'))
        entry = {'file': name + '.png', 'size': [self.w // frames, self.h], 'kind': kind}
        if margin is not None:
            entry['margin'] = list(margin) if isinstance(margin, (list, tuple)) else [margin] * 4
        if frames > 1:
            entry['frames'] = frames
        entry.update(extra)
        MANIFEST[name] = entry


def text_mask(s, font='Silkscreen-Regular.ttf', size=8, spacing=1):
    f = ImageFont.truetype(os.path.join(P, 'assets', 'fonts', font), size)
    w = sum(int(f.getlength(ch)) + spacing for ch in s) + 8
    im = Image.new('L', (w, size + 12), 0)
    d = ImageDraw.Draw(im)
    x = 4
    for ch in s:
        d.text((x, 2), ch, font=f, fill=255)
        x += int(f.getlength(ch)) + spacing
    a = np.array(im) > 127
    ys, xs = np.nonzero(a)
    return a[ys.min():ys.max() + 1, xs.min():xs.max() + 1]


# ── Panels ────────────────────────────────────────────────────────────────

def glass_panel(name, w, h, m, fill='n1', fill_a=0.86, band='n2', band_rows=5, top='g1', top_mid='g2',
                under='g0', bottom='g1', side='n4', corner=FILIGREE, double=False, inset=0):
    """Night glass: tinted top band, gold hairline top and bottom, dim side lines, filigree corners."""
    k = Kit(w, h)
    k.fill(fill, fill_a)
    if band:
        k.fill(band, fill_a, 0, 1, w, 1 + band_rows)
        for x in range(w):
            if (x % 2) == 0:
                k.dot(x, 1 + band_rows, band, fill_a)
    k.vline(0, fill, 0.0)
    k.vline(w - 1, fill, 0.0)
    k.vline(1, side, 0.9, 4, h - 4)
    k.vline(w - 2, side, 0.9, 4, h - 4)
    k.hline(0, top)
    k.hline(0, top_mid, 1.0, m, w - m)
    k.hline(1, under, 0.9, 1, w - 1)
    k.hline(h - 1, bottom)
    k.hline(h - 2, under, 0.9, 1, w - 1)
    if double:
        k.hline(3, under, 1.0, m // 2, w - m // 2)
        k.hline(h - 4, under, 1.0, m // 2, w - m // 2)
    if corner:
        k.corners(corner, inset)
    k.save(name, m)
    return k


def panels():
    glass_panel('panel', 24, 24, 8)
    glass_panel('panel_dim', 24, 24, 8, fill='n0', fill_a=0.78, band='n1', band_rows=3, top='g0', top_mid='g0',
                under='n2', bottom='g0', side='n3', corner=KNOT)
    glass_panel('frame', 32, 32, 12, fill_a=0.5, band_rows=8, corner=FILIGREE_GEM)
    glass_panel('modal', 48, 48, 16, fill_a=0.94, band_rows=10, corner=FILIGREE_GEM, double=True)
    glass_panel('dialogue', 32, 32, 10, fill_a=0.9, band_rows=4, top_mid='g2', corner=FILIGREE_GEM)
    tooltip()
    nametag()
    portrait_frame()
    zone_banner()
    minimap_frame()
    rule()


def tooltip():
    k = Kit(12, 12)
    k.fill('n0', 0.94)
    for x, y in ((0, 0), (11, 0), (0, 11), (11, 11)):
        k.clear(x, y)
    k.hline(0, 'n5', 1.0, 1, 11)
    k.hline(11, 'n3', 1.0, 1, 11)
    k.vline(0, 'n4', 1.0, 1, 11)
    k.vline(11, 'n4', 1.0, 1, 11)
    k.glyph(["32", "1 "], 1, 1)
    k.save('tooltip', 4)


def nametag():
    """Violet plate with pointed ends and gold hairlines."""
    w, h = 32, 13
    k = Kit(w, h)
    c = h // 2
    for x in range(w):
        reach = min(x, w - 1 - x, 6)
        span = c if reach >= 6 else reach
        for y in range(c - span, c + span + 1):
            k.dot(x, y, 'v1', 0.95)
        if reach >= 6:
            k.dot(x, 0, 'g2')
            k.dot(x, 1, 'v2', 0.95)
            k.dot(x, h - 1, 'g0')
        else:
            k.dot(x, c - span, 'g2' if reach > 2 else 'g1')
            k.dot(x, c + span, 'g0')
    k.glyph(["3", "2"], 1, c - 1)
    k.glyph(["3", "2"], w - 2, c - 1)
    k.save('nametag', [7, 4, 7, 4])


def portrait_frame():
    """52 px gold bevel with corner gems; the centre is open for the portrait."""
    s = 52
    k = Kit(s, s)
    k.fill('n0', 1.0)
    k.fill('n0', 0.0, 4, 4, s - 4, s - 4)
    k.hline(1, 'g2', 1.0, 1, s - 1)
    k.vline(1, 'g2', 1.0, 1, s - 1)
    k.hline(s - 2, 'g0', 1.0, 1, s - 1)
    k.vline(s - 2, 'g0', 1.0, 1, s - 1)
    k.hline(2, 'g1', 1.0, 2, s - 2)
    k.vline(2, 'g1', 1.0, 2, s - 2)
    k.hline(s - 3, 'g1', 1.0, 2, s - 2)
    k.vline(s - 3, 'g1', 1.0, 2, s - 2)
    k.dot(1, 1, 'g3')
    gem = [" M ", "Mmm", " m "]
    for x, y in ((0, 0), (s - 3, 0), (0, s - 3), (s - 3, s - 3)):
        k.fill('n0', 1.0, x, y, x + 3, y + 3)
        k.glyph(gem, x, y)
    k.save('portrait_frame', 8)


def zone_banner():
    """Banner plate for zone names: glass body, chevron ends, hairlines trailing into diamond studs."""
    w, h, m = 160, 24, 30
    k = Kit(w, h)
    c = h // 2
    body0 = 18
    for x in range(w):
        e = min(x, w - 1 - x)
        if e >= body0:
            k.vline(x, 'v0', 0.88, 3, h - 3)
            k.dot(x, 3, 'g1')
            k.dot(x, 4, 'g0', 0.9)
            k.dot(x, h - 4, 'g1')
            k.dot(x, h - 5, 'g0', 0.9)
            k.dot(x, 1, 'g2' if e >= m else 'g1', 1.0 if e >= m else 0.7)
            k.dot(x, h - 2, 'g1' if e >= m else 'g0', 1.0 if e >= m else 0.7)
        elif e >= body0 - (h - 6) // 2:
            d = body0 - e
            for y in range(3 + d, h - 3 - d):
                k.dot(x, y, 'v0', 0.88)
            k.dot(x, 3 + d, 'g1')
            k.dot(x, h - 4 - d, 'g1')
        if 2 <= e < body0:
            f = (e - 2) / (body0 - 2)
            if e < body0 - (h - 6) // 2:
                k.dot(x, c, 'g1' if f > 0.5 else 'g0', 0.35 + 0.65 * f)
    for sx, ox in ((1, 0), (-1, w - 1)):
        k.glyph([" 3 ", "323", " 2 "], ox + sx * 1 - (2 if sx < 0 else 0), c - 1)
    k.save('zone_banner', [m, 6, m, 6])


def minimap_frame():
    s, m = 72, 10
    k = Kit(s, s)
    k.fill('n0', 0.0)
    k.hline(0, 'n0'), k.hline(s - 1, 'n0'), k.vline(0, 'n0'), k.vline(s - 1, 'n0')
    k.hline(1, 'g2', 1.0, 1, s - 1)
    k.vline(1, 'g1', 1.0, 1, s - 1)
    k.vline(s - 2, 'g1', 1.0, 1, s - 1)
    k.hline(s - 2, 'g0', 1.0, 1, s - 1)
    k.hline(2, 'g0', 1.0, 2, s - 2)
    k.vline(2, 'g0', 1.0, 2, s - 2)
    k.vline(s - 3, 'g0', 1.0, 2, s - 2)
    k.hline(s - 3, 'g0', 1.0, 2, s - 2)
    k.hline(3, 'n0', 0.7, 3, s - 3), k.vline(3, 'n0', 0.7, 3, s - 3)
    k.hline(s - 4, 'n0', 0.7, 3, s - 3), k.vline(s - 4, 'n0', 0.7, 3, s - 3)
    k.corners(FILIGREE_GEM, 1)
    k.save('minimap_frame', m)


def rule():
    """Separator: gold hairline fading at both ends with a centre-less tile."""
    w = 24
    k = Kit(w, 3)
    for x in range(w):
        e = min(x, w - 1 - x)
        f = min(1.0, e / 8)
        k.dot(x, 1, 'g1' if f >= 1 else 'g0', 0.25 + 0.75 * f)
        if f >= 1:
            k.dot(x, 2, 'n0', 0.6)
    k.save('rule', [9, 1, 9, 1])


# ── Buttons and form widgets ──────────────────────────────────────────────

def button(name, fill, fill_a, top, bottom, side, hi=None, lo=None, notch=None, inset=False):
    w, h = 24, 16
    k = Kit(w, h)
    k.fill(fill, fill_a)
    if hi:
        k.hline(1, hi, fill_a, 1, w - 1)
    if lo:
        k.hline(h - 2, lo, fill_a, 1, w - 1)
    if inset:
        k.hline(1, 'n0', 1.0, 1, w - 1)
        k.vline(1, 'n0', 0.8, 1, h - 1)
    k.hline(0, top, 1.0, 1, w - 1)
    k.hline(h - 1, bottom, 1.0, 1, w - 1)
    k.vline(0, side, 1.0, 1, h - 1)
    k.vline(w - 1, side, 1.0, 1, h - 1)
    if notch:
        k.fill(notch, 1.0, 1, 2, 3, h - 2)
    for x in (0, w - 1):
        for y in (0, h - 1):
            k.clear(x, y)
    k.save(name, [6, 5, 6, 5])


def focus_frames():
    """Focus ring (static) and 4-frame shimmer: a glint hops corner to corner, inside the 9-slice corners so tiled edges never repeat it."""
    w, h, n = 24, 16, 4

    def ring(k, ox):
        k.hline(0, 'g1', 1.0, ox + 1, ox + w - 1)
        k.hline(h - 1, 'g1', 1.0, ox + 1, ox + w - 1)
        k.vline(ox, 'g1', 1.0, 1, h - 1)
        k.vline(ox + w - 1, 'g1', 1.0, 1, h - 1)
        for x, y in ((ox, 0), (ox + w - 1, 0), (ox, h - 1), (ox + w - 1, h - 1)):
            k.dot(x, y, 'g3')

    strip = Kit(w * n, h)
    corners = ((0, 0, 1, 1), (w - 1, 0, -1, 1), (w - 1, h - 1, -1, -1), (0, h - 1, 1, -1))
    for f, (cx, cy, dx, dy) in enumerate(corners):
        ox = f * w
        ring(strip, ox)
        for i, col in enumerate(('g3', 'g3', 'g2', 'g2')):
            strip.dot(ox + cx + dx * (1 + i), cy, col)
        for i, col in enumerate(('g3', 'g2', 'g2')):
            strip.dot(ox + cx, cy + dy * (1 + i), col)
    strip.save('focus_shimmer', [6, 5, 6, 5], frames=n)
    k = Kit(w, h)
    ring(k, 0)
    k.dot(0, 2, 'g3')
    k.dot(w - 1, h - 3, 'g3')
    k.save('focus', [6, 5, 6, 5])


def buttons():
    button('btn_normal', 'n2', 0.92, 'g0', 'n0', 'n4', hi='n3', lo='n1')
    button('btn_hover', 'v1', 0.94, 'g2', 'g1', 'v3', hi='v2', lo='v0', notch='m2')
    button('btn_pressed', 'n1', 0.96, 'g1', 'g0', 'n4', notch='m1', inset=True)
    button('btn_disabled', 'n1', 0.6, 'n3', 'n2', 'n2')
    button('btn_quiet', 'n1', 0.8, 'n5', 'n0', 'n3', hi='n2')
    button('btn_quiet_hover', 'n2', 0.9, 'g1', 'g0', 'n4', hi='n3')
    focus_frames()


def tab(name, fill, fill_a, top, top_end, side, under=None):
    w, h = 16, 16
    k = Kit(w, h)
    k.fill(fill, fill_a, 0, 0, w, h)
    k.hline(0, top, 1.0, 1, w - 1)
    k.dot(1, 0, top_end), k.dot(w - 2, 0, top_end)
    k.clear(0, 0), k.clear(w - 1, 0)
    if under:
        k.hline(1, under, 0.9, 1, w - 1)
    k.vline(0, side, 0.9, 1, h)
    k.vline(w - 1, side, 0.9, 1, h)
    k.save(name, [5, 4, 5, 2])


def tabs():
    tab('tab_selected', 'n2', 0.94, 'g2', 'g3', 'n4', under='g0')
    tab('tab_unselected', 'n1', 0.55, 'n4', 'n4', 'n2')
    tab('tab_hovered', 'n2', 0.75, 'g0', 'g1', 'n3')


def gem_icon(k, ox, oy, lit=True):
    rows = ["  M  ", " Mmm ", "Mmmm0", " m00 ", "  0  "] if lit else ["  n  ", " nnn ", "nnnnd", " ndd ", "  d  "]
    keys = dict(KEYS, M='m3', m='m2', **{'0': 'm0'}) if lit else dict(KEYS, n='n4', d='n2')
    k.glyph(rows, ox, oy, keys=keys)


def checks():
    s = 11
    for name, lit in (('check_off', False), ('check_on', True)):
        k = Kit(s, s)
        k.fill('n0', 0.95)
        k.hline(0, 'n5'), k.vline(0, 'n4'), k.vline(s - 1, 'n4'), k.hline(s - 1, 'n3')
        k.hline(1, 'n0', 1.0, 1, s - 1)
        if lit:
            k.hline(0, 'g1'), k.hline(s - 1, 'g0')
            gem_icon(k, 3, 3)
        k.save(name, kind='icon')
    circle = ["  ####  ", " #....# ", "#......#", "#......#", "#......#", "#......#", " #....# ", "  ####  "]
    for name, lit in (('radio_off', False), ('radio_on', True)):
        k = Kit(11, 11)
        for j, r in enumerate(circle):
            for i, ch in enumerate(r):
                if ch == '#':
                    k.dot(i + 1, j + 1, ('g2' if j < 4 else 'g1') if lit else ('n6' if j < 4 else 'n4'))
                elif ch == '.':
                    k.dot(i + 1, j + 1, 'n0', 0.95)
        if lit:
            gem_icon(k, 3, 3)
        k.save(name, kind='icon')


def slider_parts():
    k = Kit(9, 6)
    k.fill('n0', 0.95)
    k.hline(0, 'n0'), k.hline(5, 'n4'), k.vline(0, 'n3'), k.vline(8, 'n3')
    k.clear(0, 0), k.clear(8, 0), k.clear(0, 5), k.clear(8, 5)
    k.save('slider_track', [3, 2, 3, 2])
    for name, body, top, bot in (('slider_fill', 'm1', 'm2', 'm0'), ('slider_fill_hover', 'm2', 'm3', 'm1')):
        k = Kit(9, 6)
        k.fill(body)
        k.hline(0, top), k.hline(5, bot)
        k.clear(0, 0), k.clear(8, 0), k.clear(0, 5), k.clear(8, 5)
        k.save(name, [3, 2, 3, 2])
    knob = ["  d  ", " d3d ", "d322d", "d221d", "d211d", "d110d", " d0d ", "  d  "]
    for name, keys in (('slider_grabber', KEYS), ('slider_grabber_hover', dict(KEYS, **{'1': 'g2', '0': 'g1', '2': 'g3'}))):
        k = Kit(7, 10)
        k.glyph(knob, 1, 1, keys=keys)
        k.save(name, kind='icon')


def scroll_parts():
    k = Kit(7, 7)
    k.fill('n0', 0.7)
    k.vline(0, 'n2', 0.9), k.vline(6, 'n2', 0.9)
    k.save('scroll_track', 3)
    for name, body, hi, lo, spine in (('scroll_grabber', 'n4', 'n6', 'n2', 'g0'), ('scroll_grabber_hover', 'n5', 'n7', 'n3', 'g1'),
                                      ('scroll_grabber_pressed', 'n6', 'n8', 'n4', 'g2')):
        k = Kit(7, 7)
        k.fill(body)
        k.hline(0, hi, 1.0, 1, 6), k.vline(0, hi, 1.0, 1, 6)
        k.hline(6, lo, 1.0, 1, 6), k.vline(6, lo, 1.0, 1, 6)
        for x, y in ((0, 0), (6, 0), (0, 6), (6, 6)):
            k.clear(x, y)
        k.dot(3, 3, spine)
        k.save(name, 3)


def text_fields():
    for name, border, top, corner in (('field', 'n3', 'n3', None), ('field_focus', 'g0', 'g1', 'g2'), ('field_readonly', 'n2', 'n2', None)):
        k = Kit(16, 16)
        k.fill('n0', 0.95 if name != 'field_readonly' else 0.7)
        k.hline(0, top), k.vline(0, border), k.vline(15, border), k.hline(15, 'n4' if corner is None else 'g1')
        k.hline(1, 'n0', 1.0, 1, 15)
        if corner:
            k.glyph(["32", "2 "], 0, 0)
            k.glyph(["23", " 2"], 14, 0)
        k.save(name, 5)


def bars():
    k = Kit(8, 6)
    k.fill('n0', 0.95)
    k.hline(5, 'n3'), k.hline(0, 'n0')
    k.save('bar_track', 2)
    k = Kit(8, 6)
    k.fill('n9')
    k.hline(0, 'n11'), k.hline(1, 'n10'), k.hline(5, 'n8')
    k.save('bar_fill', 2)


# ── Keycaps, cursor ───────────────────────────────────────────────────────

def keycap(name, label=None, art=None):
    """12 px tall key: lit face, darker skirt, Silkscreen label or a pixel glyph."""
    m = text_mask(label) if label else None
    gw = m.shape[1] if m is not None else len(art[0])
    w = max(12, gw + 6)
    k = Kit(w, 12)
    k.fill('n3')
    k.fill('n1', 1.0, 0, 9, w, 12)
    k.hline(0, 'n6'), k.vline(0, 'n6', 1.0, 0, 9), k.vline(w - 1, 'n5', 1.0, 0, 9)
    k.hline(11, 'n0')
    for x, y in ((0, 0), (w - 1, 0), (0, 11), (w - 1, 11)):
        k.clear(x, y)
    ox = (w - gw) // 2
    if m is not None:
        oy = 2 + max(0, (6 - m.shape[0]) // 2)
        k.mask(m, 'n0', 1.0, ox, oy + 1)
        k.mask(m, 'n10', 1.0, ox, oy)
    else:
        k.glyph(art, ox, 2, keys={'#': 'n10', 'o': 'g2'})
    k.save(name, [4, 4, 4, 4], kind='key')


def keycaps():
    title_ui.keycap()
    MANIFEST['key9'] = {'file': 'key9.png', 'size': [12, 12], 'margin': [4, 4, 4, 4], 'kind': 'nine'}
    keycap('key_e', 'E')
    keycap('key_esc', 'ESC')
    keycap('key_ctrl_l', 'CTRL+L')
    keycap('key_enter', 'ENTER')
    keycap('key_shift', 'SHIFT')
    up = ["       ", "   #   ", "  ###  ", " ##### ", "       "]
    side = ["  #", " ##", "###", " ##", "  #"]
    keycap('key_up', art=up)
    keycap('key_down', art=up[::-1])
    keycap('key_left', art=side)
    keycap('key_right', art=[r[::-1] for r in side])
    mouse_wheel()


def mouse_wheel():
    rows = [" ##### ", "#..o..#", "#..o..#", "#######", "#.....#", "#.....#", "#.....#", "#.....#", " #...# ", "  ###  "]
    k = Kit(9, 12)
    for j, r in enumerate(rows):
        for i, ch in enumerate(r):
            col = {'#': 'n7', '.': 'n3', 'o': 'g2'}.get(ch)
            if col:
                k.dot(i + 1, j + 1, col)
    k.dot(4, 0, 'g3'), k.dot(4, 11, 'g1')
    k.save('key_wheel', kind='icon')


def arrows():
    """Gold chevrons for tab scrolling, option buttons and spin boxes; *_hover variants are brighter."""
    right = ["dd   ", "d3d  ", "d32d ", "d21d ", "d1d  ", "dd   "]
    for name, rows in (('arrow_right', right), ('arrow_left', [r[::-1] for r in right]),
                       ('arrow_down', ["dddddd", "d3221d", " d21d ", "  dd  "]),
                       ('arrow_up', ["  dd  ", " d32d ", "d3221d", "dddddd"])):
        for suffix, keys in (('', KEYS), ('_hover', dict(KEYS, **{'0': 'g1', '1': 'g2', '2': 'g3', 'd': 'v1'}))):
            k = Kit(len(rows[0]), len(rows))
            k.glyph(rows, 0, 0, keys=keys)
            k.save(name + suffix, kind='icon')


def cursor():
    rows = [
        "d          ",
        "d3d        ",
        "d32d       ",
        "d322d      ",
        "d3221d     ",
        "d32211d    ",
        "d322110d   ",
        "d3221100d  ",
        "d32mddddd  ",
        "d3d d1d    ",
        "dd   d1d   ",
        "      dd   ",
    ]
    k = Kit(12, 12)
    k.glyph(rows, 0, 0)
    k.save('cursor', kind='icon', hotspot=[0, 0])


# ── Title-shared pieces and the backdrop ──────────────────────────────────

def title_pieces():
    title_ui.nine_select()
    title_ui.gem()
    title_ui.nine_panel()
    MANIFEST['select9'] = {'file': 'select9.png', 'size': [48, 16], 'margin': [2, 3, 2, 3], 'kind': 'nine'}
    MANIFEST['gem'] = {'file': 'gem.png', 'size': [5, 5], 'kind': 'icon'}
    MANIFEST['panel9'] = {'file': 'panel9.png', 'size': [48, 48], 'margin': [8, 8, 8, 8], 'kind': 'nine', 'stretch': True}
    k = Kit(8, 8)
    k.glyph(FILIGREE_GEM, 0, 0)
    k.save('corner', kind='icon')


def quantize(rgb):
    """Snap every pixel to the nearest palette colour with an ordered dither between the two nearest."""
    h, w, _ = rgb.shape
    flat = rgb.reshape(-1, 3)
    d = ((flat[:, None, :] - PALETTE[None, :, :]) ** 2).sum(2)
    o = np.argsort(d, 1)[:, :2]
    d1 = np.sqrt(np.take_along_axis(d, o[:, :1], 1))[:, 0]
    d2 = np.sqrt(np.take_along_axis(d, o[:, 1:2], 1))[:, 0]
    t = d1 / np.maximum(d1 + d2, 1e-3)
    yy, xx = np.mgrid[0:h, 0:w]
    pick = np.where(t > px.BAYER[yy % 4, xx % 4].reshape(-1) * 0.9, o[:, 1], o[:, 0])
    return PALETTE[pick].reshape(h, w, 3)


def _layer(name):
    p = os.path.join(MENU, name + '.png')
    return np.asarray(Image.open(p).convert('RGBA'), np.float32) if os.path.exists(p) else None


def _over(dst, src, x=0, y=0, mul=(1, 1, 1), add=False):
    h, w = src.shape[:2]
    H, W = dst.shape[:2]
    x0, y0 = max(0, x), max(0, y)
    x1, y1 = min(W, x + w), min(H, y + h)
    if x1 <= x0 or y1 <= y0:
        return
    s = src[y0 - y:y1 - y, x0 - x:x1 - x]
    a = s[..., 3:4] / 255
    c = s[..., :3] * np.array(mul, np.float32)
    if add:
        dst[y0:y1, x0:x1] += c * a
    else:
        dst[y0:y1, x0:x1] = dst[y0:y1, x0:x1] * (1 - a) + c * a


def backdrop():
    """The title's far planes without the menu: painted sky, mountains, castle, pines, mirrored lake, shores."""
    W, H, PAD, HY = 640, 360, 24, 214
    yy, xx = np.mgrid[0:H, 0:W]
    sky = px.ramp(np.clip(yy / HY, 0, 1) ** 0.9, [C['n0'], C['n1'], C['v0'], C['n2'], C['v1'], C['v2']], 0.9)
    img = sky.astype(np.float32)
    rng = np.random.default_rng(714)
    for _ in range(260):
        x, y = rng.integers(0, W), rng.integers(0, HY - 30)
        img[y, x] = C[rng.choice(['n8', 'n9', 'n10', 'n11'], p=[0.4, 0.3, 0.2, 0.1])]
    if _layer('mtn_far') is None:
        return False
    dark = (0.56, 0.56, 0.66)
    _over(img, _layer('moon_halo'), 476 - 110 - PAD, 86 - 110, add=True)
    _over(img, _layer('moon'), 476 - 24 - PAD, 86 - 24, mul=(1.2, 1.2, 1.3))
    for n in ('mtn_far', 'mtn_near', 'castle', 'pines_far'):
        _over(img, _layer(n), -PAD)
    _over(img, _layer('castle_e'), -PAD, add=True)
    sky_part = img[:HY].copy()
    lake = sky_part[::-1][:H - HY] * np.array([0.42, 0.45, 0.6], np.float32) + C['t0'] * 0.35
    rows = np.arange(H - HY)
    for r in rows:
        if (r // 2 + r // 7) % 3 == 0:
            lake[r] = np.roll(lake[r], 1 + r // 24, 0)
    img[HY:] = lake
    _over(img, _layer('boat'), 332, 236, mul=dark)
    for n in ('pines_right', 'pines_left'):
        _over(img, _layer(n), -PAD)
    _over(img, _layer('shore'), -PAD, mul=dark)
    _over(img, _layer('mid'), -PAD, mul=dark)
    _over(img, _layer('mid_e'), -PAD, add=True)
    _over(img, _layer('fg'), -PAD, mul=tuple(v * 0.7 for v in dark))
    _over(img, _layer('fg_leaves'), -PAD, mul=tuple(v * 0.7 for v in dark))
    _over(img, _layer('fg_grass'), -PAD, mul=tuple(v * 0.7 for v in dark))
    for n, at, r in (('pool_fire', (560, 290), (70, 26)), ('pool_stone', (522, 238), (30, 30)), ('pool_lantern', (598, 178), (46, 46))):
        _over(img, _layer(n), at[0] - r[0], at[1] - r[1], mul=(0.8, 0.8, 0.8), add=True)
    img = quantize(np.clip(img, 0, 255))
    k = Kit(W, H)
    k.rgb, k.a = img, np.ones((H, W), np.float32)
    k.save('backdrop', kind='image')
    return True


def check_palette():
    """Every opaque pixel of every kit PNG must be a palette colour."""
    pal = {tuple(int(v) for v in c) for c in PALETTE}
    bad = []
    for name, e in MANIFEST.items():
        a = np.asarray(Image.open(os.path.join(OUT, e['file'])).convert('RGBA'))
        cols = {tuple(int(v) for v in c) for c in a[a[..., 3] > 0][:, :3]}
        if cols - pal:
            bad.append((name, len(cols - pal)))
    return bad


def main():
    os.makedirs(OUT, exist_ok=True)
    title_pieces()
    panels()
    buttons()
    tabs()
    checks()
    slider_parts()
    scroll_parts()
    text_fields()
    bars()
    keycaps()
    arrows()
    cursor()
    has_bg = backdrop()
    bad = check_palette()
    pal = {k: '#%02x%02x%02x' % tuple(int(x) for x in v) for k, v in C.items()}
    with open(os.path.join(OUT, 'ui.json'), 'w') as f:
        json.dump({'base': [640, 360], 'palette': pal, 'items': MANIFEST}, f, indent=1, sort_keys=True)
    print('ui kit: %d items -> %s%s' % (len(MANIFEST), OUT, '' if has_bg else ' (no assets/menu: backdrop skipped)'))
    if bad:
        print('off-palette:', bad)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
