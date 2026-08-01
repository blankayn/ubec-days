"""Sample average pixel colour from regions of a captured Godot frame."""

import pathlib
import sys

import bpy

PATH = sys.argv[-1]
img = bpy.data.images.load(PATH)
w, h = img.size
px = list(img.pixels)


def sample(name, x0, y0, x1, y1):
    """Average an image region. Origin is bottom-left in Blender images."""
    r = g = b = 0.0
    n = 0
    for y in range(y0, y1):
        for x in range(x0, x1):
            i = (y * w + x) * 4
            r += px[i]
            g += px[i + 1]
            b += px[i + 2]
            n += 1
    if n == 0:
        return
    print("{:<22s} ({:.3f}, {:.3f}, {:.3f})".format(name, r / n, g / n, b / n))


print("image {:d} x {:d}".format(w, h))
# Blender loads PNG with row 0 at the bottom, so these y values count upward
# from the bottom of the displayed frame.
sample("road below player", w // 2 - 70, 250, w // 2 + 70, 300)
sample("road left lane", 240, 300, 400, 340)
sample("road far", w // 2 - 40, 420, w // 2 + 40, 445)
sample("sky", w // 2 - 60, 620, w // 2 + 60, 660)
