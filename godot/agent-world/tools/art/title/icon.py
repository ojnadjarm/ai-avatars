#!/usr/bin/env python3
"""App icon: 32 px pixel-art Hollowmere Spire under the moon, written as crisp SVG rects to P/icon.svg."""
import os

import numpy as np

from px import P, BAYER
from bg import C

N = 32


def grid():
    yy, xx = np.mgrid[0:N, 0:N]
    img = np.zeros((N, N, 3), np.float32)
    a = np.ones((N, N), bool)
    # night sky bands with a 2-step dither seam
    sky = [C['n0'], C['n1'], C['n2'], C['v1'], C['v2']]
    q = np.clip(yy / 26 * len(sky) + (BAYER[yy % 4, xx % 4] - 0.5) * 0.8, 0, len(sky) - 1).astype(int)
    img[:] = np.array(sky, np.float32)[q]
    for x, y in [(4, 4), (9, 2), (27, 16), (3, 13), (7, 9)]:
        img[y, x] = C['n9']
    # moon with a one-ring halo
    d = np.hypot(xx - 21.5, yy - 9.5)
    img[(d <= 8.5) & (d > 6.5)] = C['v3']
    img[d <= 6.5] = C['n10']
    img[(d <= 6.5) & (xx + yy > 33)] = C['n9']
    img[(d <= 5.5) & (xx + yy < 26)] = C['n11']
    for cx, cy in [(19, 8), (23, 12)]:
        img[cy, cx] = C['n8']
    # cliff, curtain wall and spire
    cliff = (yy >= 25) & (yy <= 27) & (np.abs(xx - 15.5) <= 13 - (yy - 25) * -1)
    img[cliff] = C['n0']
    wall = (yy >= 19) & (yy <= 25) & (xx >= 6) & (xx <= 25)
    img[wall] = C['n1']
    img[(yy == 18) & (xx >= 6) & (xx <= 25) & (xx % 2 == 0)] = C['n1']
    img[(yy == 18) & (xx >= 6) & (xx <= 25) & (xx % 2 == 0) & (xx > 18)] = C['n6']
    for tx in (6, 24):
        img[(yy >= 15) & (yy <= 25) & (xx >= tx) & (xx <= tx + 1)] = C['n2']
        img[(yy >= 15) & (yy <= 25) & (xx == tx + 1)] = C['n6']
        img[(yy >= 12) & (yy <= 14) & (np.abs(xx - tx - 0.5) <= (yy - 12) * 0.5 + 0.5)] = C['v3']
        img[(yy >= 12) & (yy <= 14) & (np.abs(xx - tx - 0.5) <= (yy - 12) * 0.5 + 0.5) & (xx > tx)] = C['v5']
    tower = (yy >= 11) & (yy <= 25) & (xx >= 13) & (xx <= 18)
    img[tower] = C['n2']
    img[tower & (xx == 18)] = C['n7']
    roof = (yy >= 4) & (yy <= 10) & (np.abs(xx - 15.5) <= (yy - 4) * 0.5 + 0.5)
    img[roof] = C['v3']
    img[roof & (xx >= 16)] = C['v5']
    img[roof & (xx >= 16) & (xx - 16 >= (yy - 4) * 0.5)] = C['v6']
    img[2:4, 15:17] = C['m2']
    img[2, 15] = C['m3']
    img[(yy == 21) & np.isin(xx, [8, 11, 20, 23])] = C['g2']
    img[14:16, 15:17] = C['g3']
    img[19, 15:17] = C['g2']
    img[22:24, 15:17] = C['m2']
    # lake with the moon's reflection
    lake = yy >= 28
    img[lake] = C['n1']
    img[lake & (yy % 2 == 0)] = C['n2']
    img[(yy == 28) & (xx >= 19) & (xx <= 23)] = C['n8']
    img[(yy == 30) & (xx >= 20) & (xx <= 22)] = C['n7']
    # rounded corners and a 1 px gold frame
    r = 4
    cd = np.hypot(np.clip(np.maximum(r - xx, xx - (N - 1 - r)), 0, None), np.clip(np.maximum(r - yy, yy - (N - 1 - r)), 0, None))
    a[cd > r + 0.3] = False
    frame = a & ~((cd <= r - 0.7) & (xx > 0) & (xx < N - 1) & (yy > 0) & (yy < N - 1))
    img[frame] = C['g1']
    return img.astype(np.uint8), a


def svg(img, a):
    """Horizontal runs of equal colour become one rect each."""
    out = []
    for y in range(N):
        x = 0
        while x < N:
            if not a[y, x]:
                x += 1
                continue
            c = tuple(img[y, x])
            e = x
            while e + 1 < N and a[y, e + 1] and tuple(img[y, e + 1]) == c:
                e += 1
            out.append(f'<rect x="{x}" y="{y}" width="{e - x + 1}" height="1" fill="#{c[0]:02x}{c[1]:02x}{c[2]:02x}"/>')
            x = e + 1
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" viewBox="0 0 32 32" shape-rendering="crispEdges">\n'
            + '\n'.join(out) + '\n</svg>\n')


if __name__ == '__main__':
    with open(os.path.join(P, 'icon.svg'), 'w') as f:
        f.write(svg(*grid()))
