"""Generate 128x128 PSX flat-color texture for psx_photo_civilian Blockbench UV layout."""
from __future__ import annotations

from pathlib import Path

try:
    from PIL import Image
except ImportError:
    raise SystemExit("pip install pillow")

W = H = 128

# Packed UVs from Blockbench (u1,v1,u2,v2) per cube face
UV = {
    "torso": {
        "north": [4, 4, 11, 10],
        "east": [0, 4, 4, 10],
        "south": [15, 4, 22, 10],
        "west": [11, 4, 15, 10],
        "up": [11, 4, 4, 0],
        "down": [18, 0, 11, 4],
    },
    "head": {
        "north": [53, 4, 57, 8],
        "east": [49, 4, 53, 8],
        "south": [61, 4, 65, 8],
        "west": [57, 4, 61, 8],
        "up": [57, 4, 53, 0],
        "down": [61, 0, 57, 4],
    },
    "hair": {
        "north": [72, 4, 76, 5],
        "east": [68, 4, 72, 5],
        "south": [80, 4, 84, 5],
        "west": [76, 4, 80, 5],
        "up": [76, 4, 72, 0],
        "down": [80, 0, 76, 4],
    },
    "arm_l": {
        "north": [91, 2, 92, 7],
        "east": [89, 2, 91, 7],
        "south": [94, 2, 95, 7],
        "west": [92, 2, 94, 7],
        "up": [92, 2, 91, 0],
        "down": [93, 0, 92, 2],
    },
    "arm_r": {
        "north": [100, 2, 101, 7],
        "east": [98, 2, 100, 7],
        "south": [103, 2, 104, 7],
        "west": [101, 2, 103, 7],
        "up": [101, 2, 100, 0],
        "down": [102, 0, 101, 2],
    },
    "leg_l": {
        "north": [26, 3, 28, 10],
        "east": [23, 3, 26, 10],
        "south": [31, 3, 33, 10],
        "west": [28, 3, 31, 10],
        "up": [28, 3, 26, 0],
        "down": [30, 0, 28, 3],
    },
    "leg_r": {
        "north": [39, 3, 41, 10],
        "east": [36, 3, 39, 10],
        "south": [44, 3, 46, 10],
        "west": [41, 3, 44, 10],
        "up": [41, 3, 39, 0],
        "down": [43, 0, 41, 3],
    },
    "shoe_l": {
        "north": [110, 3, 112, 5],
        "east": [107, 3, 110, 5],
        "south": [115, 3, 117, 5],
        "west": [112, 3, 115, 5],
        "up": [112, 3, 110, 0],
        "down": [114, 0, 112, 3],
    },
    "shoe_r": {
        "north": [3, 15, 5, 17],
        "east": [0, 15, 3, 17],
        "south": [8, 15, 10, 17],
        "west": [5, 15, 8, 17],
        "up": [5, 15, 3, 12],
        "down": [7, 12, 5, 15],
    },
}

# Flat PSX palette (no gradients)
BG = (26, 16, 40)
SHIRT = (212, 168, 42)
SHIRT_SIDE = (184, 137, 31)
SHIRT_BACK = (170, 128, 28)
JEANS = (91, 127, 168)
JEANS_SIDE = (74, 106, 143)
JEANS_BACK = (64, 92, 128)
SKIN = (198, 134, 66)
SKIN_SIDE = (170, 115, 56)
HAIR = (31, 24, 20)
HAIR_SIDE = (24, 18, 15)
SHOE = (138, 138, 138)
SHOE_SIDE = (118, 118, 118)
SHOE_SOLE = (92, 92, 92)
INK = (26, 22, 20)
BUTTON = (120, 90, 35)
POCKET = (196, 154, 38)
LIP = (139, 77, 77)
WHITE = (230, 220, 200)


def rect_bounds(uv: list[float]) -> tuple[int, int, int, int]:
    u1, v1, u2, v2 = uv
    x0, x1 = sorted((int(round(u1)), int(round(u2))))
    y0, y1 = sorted((int(round(v1)), int(round(v2))))
    return x0, y0, x1, y1


def fill_rect(px, x0: int, y0: int, x1: int, y1: int, color: tuple[int, int, int]) -> None:
    for y in range(y0, y1):
        for x in range(x0, x1):
            if 0 <= x < W and 0 <= y < H:
                px[x, y] = color


def fill_face(px, uv: list[float], color: tuple[int, int, int]) -> tuple[int, int, int, int]:
    x0, y0, x1, y1 = rect_bounds(uv)
    fill_rect(px, x0, y0, x1, y1, color)
    return x0, y0, x1, y1


def set_px(px, x: int, y: int, color: tuple[int, int, int]) -> None:
    if 0 <= x < W and 0 <= y < H:
        px[x, y] = color


def paint_torso_north(px) -> None:
    x0, y0, x1, y1 = fill_face(px, UV["torso"]["north"], SHIRT)
    w, h = x1 - x0, y1 - y0
    cx = x0 + w // 2
    # Open collar
    for x in range(cx - 1, cx + 2):
        set_px(px, x, y0, SKIN)
        set_px(px, x, y0 + 1, SKIN)
    # Buttons
    for row in range(2, h - 1):
        set_px(px, cx, y0 + row, BUTTON)
    # Chest pocket
    for y in range(y0 + 2, y0 + 4):
        for x in range(x0 + 1, x0 + 3):
            set_px(px, x, y, POCKET)
    set_px(px, x0 + 2, y0 + 2, INK)


def paint_head_north(px) -> None:
    x0, y0, x1, y1 = fill_face(px, UV["head"]["north"], SKIN)
    # Hair fringe
    for x in range(x0, x1):
        set_px(px, x, y0, HAIR)
        set_px(px, x, y0 + 1, HAIR)
    # Eyes
    set_px(px, x0 + 1, y0 + 2, INK)
    set_px(px, x1 - 2, y0 + 2, INK)
    # Brow
    set_px(px, x0 + 1, y0 + 1, HAIR)
    set_px(px, x1 - 2, y0 + 1, HAIR)
    # Mouth
    set_px(px, x0 + 2, y1 - 2, LIP)


def paint_hair_north(px) -> None:
    x0, y0, x1, y1 = fill_face(px, UV["hair"]["north"], HAIR)
    for x in range(x0, x1):
        if (x - x0) % 2 == 0:
            set_px(px, x, y0, HAIR_SIDE)


def paint_arm_north(px, key: str) -> None:
    x0, y0, x1, y1 = fill_face(px, UV[key]["north"], SHIRT)
    cx = x0 + (x1 - x0) // 2
    for y in range(y0, y1):
        set_px(px, cx, y, SHIRT_SIDE)


def paint_leg_north(px, key: str) -> None:
    x0, y0, x1, y1 = fill_face(px, UV[key]["north"], JEANS)
    cx = x0 + (x1 - x0) // 2
    for y in range(y0, y1):
        set_px(px, cx, y, JEANS_SIDE)
    # Cuff
    for x in range(x0, x1):
        set_px(px, x, y1 - 1, JEANS_BACK)


def paint_shoe_north(px, key: str) -> None:
    x0, y0, x1, y1 = fill_face(px, UV[key]["north"], SHOE)
    for x in range(x0, x1):
        set_px(px, x, y1 - 1, SHOE_SOLE)
    for x in range(x0 + 1, x1 - 1):
        set_px(px, x, y0, WHITE)


def paint_sides(px, cube: str, mapping: dict[str, tuple[int, int, int]]) -> None:
    for face, color in mapping.items():
        if face == "north":
            continue
        fill_face(px, UV[cube][face], color)


def main() -> None:
    img = Image.new("RGB", (W, H), BG)
    px = img.load()

    # Simplified side/back fills
    shirt_faces = {
        "east": SHIRT_SIDE,
        "west": SHIRT_SIDE,
        "south": SHIRT_BACK,
        "up": SHIRT,
        "down": SHIRT_SIDE,
    }
    skin_faces = {
        "east": SKIN_SIDE,
        "west": SKIN_SIDE,
        "south": SKIN_SIDE,
        "up": HAIR,
        "down": SKIN,
    }
    hair_faces = {f: HAIR if f != "down" else SKIN for f in UV["hair"]}
    arm_faces = {f: SHIRT_SIDE if f != "up" else SHIRT for f in UV["arm_l"]}
    jeans_faces = {
        "east": JEANS_SIDE,
        "west": JEANS_SIDE,
        "south": JEANS_BACK,
        "up": JEANS,
        "down": JEANS_SIDE,
    }
    shoe_faces = {
        "east": SHOE_SIDE,
        "west": SHOE_SIDE,
        "south": SHOE_SIDE,
        "up": SHOE,
        "down": SHOE_SOLE,
    }

    paint_sides(px, "torso", shirt_faces)
    paint_torso_north(px)

    paint_sides(px, "head", skin_faces)
    paint_head_north(px)

    paint_sides(px, "hair", hair_faces)
    paint_hair_north(px)

    for arm in ("arm_l", "arm_r"):
        paint_sides(px, arm, arm_faces)
        paint_arm_north(px, arm)

    for leg in ("leg_l", "leg_r"):
        paint_sides(px, leg, jeans_faces)
        paint_leg_north(px, leg)

    for shoe in ("shoe_l", "shoe_r"):
        paint_sides(px, shoe, shoe_faces)
        paint_shoe_north(px, shoe)

    out = Path(__file__).resolve().parents[1] / "assets" / "npcs" / "psx_student_civilian_atlas.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    img.save(out, format="PNG")
    print(out)


if __name__ == "__main__":
    main()
