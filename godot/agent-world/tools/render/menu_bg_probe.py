#!/usr/bin/env python3
"""Fraction of menu-background pixels that differ between two frames; exit 1 below the threshold."""
import sys
import numpy as np
from PIL import Image

a, b = (np.asarray(Image.open(p).convert("RGB"), dtype=np.int16) for p in sys.argv[1:3])
margin = int(sys.argv[3]) if len(sys.argv) > 3 else 30
need = float(sys.argv[4]) if len(sys.argv) > 4 else 0.01
mask = np.zeros(a.shape[:2], bool)
mask[:margin], mask[-margin:], mask[:, :margin], mask[:, -margin:] = True, True, True, True
diff = np.abs(a - b).max(axis=2) > 2
frac_bg, frac_all = diff[mask].mean(), diff.mean()
print(f"MENU_BG margin={margin}px changed={frac_bg:.4f} whole={frac_all:.4f} need>{need}")
sys.exit(0 if frac_bg > need else 1)
