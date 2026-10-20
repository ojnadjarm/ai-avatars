#!/usr/bin/env python3
"""Pixel-art primitives: tileable value noise, ramps with ordered dither, masks, normals and PNG output."""
import argparse
import os

import numpy as np
from PIL import Image, ImageDraw

W, H = 640, 360
PAD = 24
LW = W + 2 * PAD
BAYER = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]) / 16.0 + 1 / 32
P = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', '..'))
_ap = argparse.ArgumentParser(add_help=False)
_ap.add_argument('--out', default=os.path.join(P, 'assets', 'menu'))
OUT = os.path.abspath(_ap.parse_known_args()[0].out)


def hexc(h):
    return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)], np.float32)


def noise2(w, h, cx, cy, seed, tile=True):
    """Smooth value noise, cell size cx by cy, horizontally tileable when w % cx == 0."""
    r = np.random.default_rng(seed)
    gw, gh = int(np.ceil(w / cx)) + 1, int(np.ceil(h / cy)) + 2
    g = r.random((gh, gw))
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    xx, yy = xx / cx, yy / cy
    x0, y0 = xx.astype(int), yy.astype(int)
    fx, fy = xx - x0, yy - y0
    fx, fy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
    m = (gw - 1) if (tile and w % cx == 0) else gw
    x1 = (x0 + 1) % m
    x0 = x0 % m
    a = g[y0, x0] * (1 - fx) + g[y0, x1] * fx
    b = g[y0 + 1, x0] * (1 - fx) + g[y0 + 1, x1] * fx
    return a * (1 - fy) + b * fy


def fbm(w, h, cx, cy, seed, oct=4, gain=0.5):
    out = np.zeros((h, w), np.float32)
    amp, tot = 1.0, 0.0
    for o in range(oct):
        out += amp * noise2(w, h, max(1, cx >> o), max(1, cy >> o), seed + o * 101)
        tot += amp
        amp *= gain
    return out / tot


def line1(n, cell, seed, oct=5, gain=0.5):
    """1D fbm in [0,1] of length n."""
    return fbm(n, 1, cell, 1, seed, oct, gain)[0]


def ramp(v, cols, dither=0.5, ox=0, oy=0):
    """Map value field v in [0,1] to a colour ramp with Bayer dither on band edges."""
    hh, ww = v.shape
    yy, xx = np.mgrid[0:hh, 0:ww]
    q = np.clip(v, 0, 0.9999) * len(cols)
    q = q + (BAYER[(yy + oy) % 4, (xx + ox) % 4] - 0.5) * dither
    k = np.clip(q.astype(int), 0, len(cols) - 1)
    return np.array(cols, np.float32)[k]


def mix(a, b, t):
    return a + (b - a) * t


def poly(w, h, pts):
    im = Image.new('L', (w, h), 0)
    ImageDraw.Draw(im).polygon([tuple(map(float, p)) for p in pts], fill=255)
    return np.array(im) > 127


def ellipse(w, h, box):
    im = Image.new('L', (w, h), 0)
    ImageDraw.Draw(im).ellipse(box, fill=255)
    return np.array(im) > 127


def lines(w, h, pts, width=1):
    im = Image.new('L', (w, h), 0)
    ImageDraw.Draw(im).line([tuple(map(float, p)) for p in pts], fill=255, width=width)
    return np.array(im) > 127


def edge(mask, dx, dy):
    """Pixels of mask whose neighbour at (dx, dy) is outside."""
    p = np.pad(mask, 1)
    nb = p[1 + dy:1 + dy + mask.shape[0], 1 + dx:1 + dx + mask.shape[1]]
    return mask & ~nb


def dist_in(mask, maxd=16):
    """Chamfer-ish inside distance to the silhouette, capped."""
    d = np.zeros(mask.shape, np.float32)
    cur = mask.copy()
    for i in range(maxd):
        p = np.pad(cur, 1)
        cur = cur & p[:-2, 1:-1] & p[2:, 1:-1] & p[1:-1, :-2] & p[1:-1, 2:]
        d += cur
        if not cur.any():
            break
    return d


def normals(hgt, k=1.0):
    gy, gx = np.gradient(hgt.astype(np.float32))
    n = np.dstack([-gx * k, gy * k, np.ones_like(hgt)])
    return n / np.linalg.norm(n, axis=2, keepdims=True)


class Layer:
    """RGBA layer with optional height (for a normal map) and emissive."""

    def __init__(self, w=LW, h=H):
        self.w, self.h = w, h
        self.rgb = np.zeros((h, w, 3), np.float32)
        self.a = np.zeros((h, w), np.float32)
        self.hgt = np.zeros((h, w), np.float32)
        self.emit = np.zeros((h, w, 3), np.float32)

    def put(self, mask, rgb, hgt=None):
        self.rgb[mask] = rgb[mask] if np.ndim(rgb) == 3 else rgb
        self.a[mask] = 1.0
        if hgt is not None:
            self.hgt[mask] = hgt[mask] if np.ndim(hgt) == 2 else hgt

    def save(self, name, normal=False, lift=1.0):
        os.makedirs(OUT, exist_ok=True)
        rgba = np.dstack([np.clip(self.rgb * lift, 0, 255), self.a * 255]).astype(np.uint8)
        Image.fromarray(rgba, 'RGBA').save(os.path.join(OUT, name + '.png'))
        if normal:
            n = normals(self.hgt, 1.0)
            nn = np.dstack([(n * 0.5 + 0.5) * 255, self.a * 255]).astype(np.uint8)
            Image.fromarray(nn, 'RGBA').save(os.path.join(OUT, name + '_n.png'))
        if self.emit.any():
            e = np.dstack([np.clip(self.emit, 0, 255), (self.emit.max(2) > 0) * 255]).astype(np.uint8)
            Image.fromarray(e, 'RGBA').save(os.path.join(OUT, name + '_e.png'))


def save_rgba(arr, name):
    os.makedirs(OUT, exist_ok=True)
    Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), 'RGBA').save(os.path.join(OUT, name + '.png'))
