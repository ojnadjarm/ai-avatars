"""Extras hook for the mini fixture: one glowing standing stone from the pixel-scene props generator."""
import props


def standing_stone(g, e, spec):
    """Rune stone sprite, collision and glyph light at e['at']."""
    x, y = e['at']
    S, piv = props.rune_stone(7, hgt=34, wd=12)
    g.add('extra_stone', S, piv, x, y, shape=('rect', x - 6, y - 4, 12, 6))
    g.light('point', x, y - 18, [120, 220, 255], 0.5, 40, 14, flicker=0.2)
