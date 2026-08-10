"""Metro Department Store, Colon x Juan Luna -- the accurate rebuild.

    blender --background --python build_metro_colon.py

The most recognisable building on the oldest street in the Philippines, and the
one a Cebuano judges this map by. Built from the REAL OSM footprint (way
230174493: 17 nodes, 2,362 m2, `building:levels=7`, operator Vicsal Development
Corp) so it lands exactly where the surveyed streets put it.

WHAT THE EXISTING landmarks.build_metro_colon GETS WRONG
--------------------------------------------------------
That builder models Metro as a BILLBOARD WALL -- a blank slab hung with enormous
vinyl banners and floodlights. Against a photograph of the building that is not
what is there. The real Metro is:

  * a smooth CREAM / BEIGE PANELLED box, not a banner wall;
  * divided by a quiet VERTICAL PILASTER rhythm into wide bays;
  * almost WINDOWLESS above the ground floor -- a department store merchandises
    against solid wall -- relieved only by SPARSE NARROW HORIZONTAL SLOT
    windows and one long recessed reveal near the top;
  * turned on a CHAMFERED CORNER at the junction, which is where the signage
    goes;
  * signed with CHANNEL LETTERS MOUNTED DIRECTLY ON THE WALL -- the green
    peacock fan, blue "METRO", and "DEPARTMENT STORE / SUPERMARKET" under it --
    not with vinyl sheets;
  * bright GLAZED RETAIL at street level under a pale fascia, with one red
    tarpaulin sale banner slung above it.

The banners belong to the NEIGHBOURS (the lower wing to the west and the rounded
Motortrade block opposite, OSM way 964503684, whose 8-level footprint really is
wrapped in advertising). Attributing them to Metro is what made the old model
unrecognisable.

Follows the project law (CEBU_ARCHITECTURE_BIBLE.md s0): massing and anything
that breaks the outline is real geometry; everything else is a band standing
slightly PROUD of the wall. Exports metro.glb + metro_manifest.json to local
temp, where the Godot capture reads them by absolute path.
"""

import json
import math
import pathlib
import sys

import bpy
import numpy as np

HERE = pathlib.Path(__file__).parent
sys.path.insert(0, str(HERE))

import parts                                   # noqa: E402
import build_colon_slice as base               # noqa: E402  (main() is guarded)
from geo import project                        # noqa: E402

OUT = base.OUT
TEX = base.TEX
CC0 = base.CC0

METRO_WAY = 230174493
# The block across the junction: 8 levels, 321 m2, and a genuinely ROUNDED
# corner -- its outline turns through four ~25 degree steps rather than one
# chamfer. In photographs of this corner it is wrapped in horizontal
# advertising all the way up, which is the opposite of Metro's clean panels and
# is what makes the two read as different buildings.
COLON_CORNER_WAY = 964503684
CORNER_LEVELS = 8
CORNER_FLOOR = 3.35
LEVELS = 7
GROUND_H = 5.2          # tall glazed retail level
FLOOR_H = 3.6           # department-store floors
TOP = GROUND_H + (LEVELS - 1) * FLOOR_H     # 26.8 m


# ===========================================================================
# METRO signage texture -- channel letters on the cream wall
# ===========================================================================

# Sign ground. NOT white: it only ever shows through the anti-aliased edge of
# the alpha cut-out, so it must match the wall or every letter gets a white
# fringe once mipmapping blends the two.
CREAM = (0.80, 0.79, 0.75)
METRO_BLUE = (0.086, 0.278, 0.588)
METRO_GREEN = (0.243, 0.647, 0.216)


def tex_metro_wall():
    """A near-white wall map, derived from the CC0 plaster albedo.

    The building is pale cream verging on white. The CC0 plaster set is a warm
    BEIGE, and a material tint can only multiply -- it can darken that beige or
    push it further orange, but it can never desaturate it, which is why tinting
    alone left the facade looking tan. So the map is desaturated toward its own
    luminance and lifted here, once, at build time.
    """
    img = bpy.data.images.load(str(CC0 / "plaster_alb.jpg"))
    img.colorspace_settings.name = "Non-Color"       # read the raw bytes
    w, h = img.size
    px = np.array(img.pixels[:], dtype=np.float64).reshape(h, w, 4)[:, :, :3]
    lum = px @ np.array([0.299, 0.587, 0.114])
    out = lum[:, :, None] * 0.88 + px * 0.12          # kill the beige cast
    # Lift toward white but keep the panel grain: pushed to +0.30 first and the
    # facade clipped to flat paper, losing every joint and pilaster edge.
    out = np.clip(out * 0.86 + 0.20, 0.0, 1.0)
    base.write_png(TEX / "metro_wall.png", np.flipud(out))
    bpy.data.images.remove(img)


def _letter(ch, u, v, t=0.24):
    """Boolean mask for one letter over normalised (u, v); v=0 is the top."""
    if ch == "M":
        return ((u < t) | (u > 1 - t)
                | ((np.abs(u - 0.52 * v) < t * 0.62) & (v < 0.62))
                | ((np.abs(u - (1 - 0.52 * v)) < t * 0.62) & (v < 0.62)))
    if ch == "E":
        return (u < t) | (v < t) | (v > 1 - t) | (np.abs(v - 0.5) < t * 0.5)
    if ch == "T":
        return (v < t) | (np.abs(u - 0.5) < t * 0.62)
    if ch == "R":
        bowl_out = (((u - 0.42) / 0.58) ** 2 + ((v - 0.26) / 0.30) ** 2) <= 1.0
        bowl_in = (((u - 0.42) / (0.58 - t)) ** 2 + ((v - 0.26) / (0.30 - t * 0.8)) ** 2) <= 1.0
        leg = (np.abs(u - (0.30 + 1.05 * (v - 0.5))) < t * 0.62) & (v >= 0.5)
        return (u < t) | (bowl_out & ~bowl_in & (v < 0.56)) | leg
    if ch == "O":
        r = np.sqrt(((u - 0.5) / 0.48) ** 2 + ((v - 0.5) / 0.48) ** 2)
        return (r <= 1.0) & (r >= 1.0 - 2.0 * t)
    if ch == "S":
        return (((v < t) & (u > t * 0.6))
                | ((np.abs(v - 0.5) < t * 0.5))
                | ((v > 1 - t) & (u < 1 - t * 0.6))
                | ((u < t) & (v < 0.5)) | ((u > 1 - t) & (v > 0.5)))
    if ch == "A":
        return (((np.abs(u - (0.5 - 0.42 * v)) < t * 0.62))
                | ((np.abs(u - (0.5 + 0.42 * v)) < t * 0.62))
                | ((np.abs(v - 0.66) < t * 0.45) & (u > 0.20) & (u < 0.80)))
    if ch == "L":
        return (u < t) | (v > 1 - t)
    return np.zeros_like(u, dtype=bool)


def _draw_text(img, text, x0, x1, y0, y1, colour, t=0.24, gap=0.16, alpha=None):
    """Render block letters across a normalised box of the image."""
    h, w = img.shape[:2]
    n = len(text)
    span = (x1 - x0) / n
    lw = span * (1.0 - gap)
    for i, ch in enumerate(text):
        cx0 = x0 + span * i + (span - lw) * 0.5
        px0, px1 = int(cx0 * w), int((cx0 + lw) * w)
        py0, py1 = int(y0 * h), int(y1 * h)
        if px1 <= px0 or py1 <= py0:
            continue
        uu, vv = np.meshgrid(np.linspace(0, 1, px1 - px0),
                             np.linspace(0, 1, py1 - py0))
        m = _letter(ch, uu, vv, t)
        img[py0:py1, px0:px1][m] = colour
        if alpha is not None:
            alpha[py0:py1, px0:px1][m] = 1.0


def _draw_fan(img, cx, cy, r0, r1, a0, a1, blades=7, alpha=None):
    """The green peacock fan: tapered blades radiating from a low pivot."""
    h, w = img.shape[:2]
    ys, xs = np.mgrid[0:h, 0:w]
    dx = (xs - cx * w) / float(w)
    dy = (ys - cy * h) / float(h)
    ang = np.degrees(np.arctan2(-dy, dx))
    rad = np.sqrt(dx * dx + dy * dy)
    step = (a1 - a0) / blades
    for i in range(blades):
        lo = a0 + step * i
        hi = lo + step * 0.68            # gap between blades
        # blades shorten toward the outside of the fan
        edge = 1.0 - 0.22 * abs((i + 0.5) / blades - 0.5) * 2.0
        m = ((ang >= lo) & (ang <= hi) & (rad >= r0) & (rad <= r1 * edge))
        shade = 0.80 + 0.20 * (i / max(1, blades - 1))
        img[m] = (METRO_GREEN[0] * shade, METRO_GREEN[1] * shade,
                  METRO_GREEN[2] * shade)
        if alpha is not None:
            alpha[m] = 1.0


def tex_metro_sign(size=(1024, 640)):
    """The METRO channel letters, as a CUT-OUT with a transparent ground.

    On the real building the fan, the wordmark and the sub-lines are individual
    letters bolted straight onto the cream wall -- there is no signboard behind
    them. Rendering them on an opaque panel put a white rectangle on the
    facade, which is the single most obviously wrong thing a first pass can do
    to a landmark. So the background is transparent and the material uses an
    alpha SCISSOR (a hard cut, no blending) -- cheap on the Compatibility
    renderer and with no transparency sort order against the wall behind.
    """
    w, h = size
    img = np.zeros((h, w, 3))
    img[:] = CREAM                      # only shows through anti-aliased edges
    alpha = np.zeros((h, w))

    _draw_fan(img, cx=0.5, cy=0.46, r0=0.055, r1=0.20, a0=18.0, a1=162.0,
              alpha=alpha)
    _draw_text(img, "METRO", 0.10, 0.90, 0.50, 0.74, METRO_BLUE, t=0.25,
               alpha=alpha)
    # "DEPARTMENT STORE / SUPERMARKET" under the logotype. Drawn as word bars
    # rather than glyphs: at any distance the player ever sees this wall the
    # sub-text is a texture, and faking 20 letterforms buys nothing.
    dark = (0.10, 0.24, 0.46)
    _word_bars(img, 0.20, 0.80, 0.790, 0.845, dark, words=(3, 2), seed=3,
               alpha=alpha)
    _word_bars(img, 0.26, 0.74, 0.880, 0.930, dark, words=(4,), seed=9,
               alpha=alpha)
    base.write_png(TEX / "metro_sign.png", np.dstack([img, alpha]))


def _word_bars(img, x0, x1, y0, y1, colour, words=(3,), seed=0, alpha=None):
    """Rows of solid bars standing in for small lettering."""
    h, w = img.shape[:2]
    rng = np.random.default_rng(seed)
    total = sum(words)
    span = (x1 - x0) / total
    i = 0
    for count in words:
        for _ in range(count):
            wlen = span * rng.uniform(0.55, 0.88)
            cx0 = x0 + span * i + (span - wlen) * 0.5
            ys, xs = slice(int(y0 * h), int(y1 * h)), slice(int(cx0 * w), int((cx0 + wlen) * w))
            img[ys, xs] = colour
            if alpha is not None:
                alpha[ys, xs] = 1.0
            i += 1


def tex_sale_banner(size=(768, 384)):
    """The red tarpaulin sale banner slung over the ground-floor fascia."""
    w, h = size
    img = np.zeros((h, w, 3))
    img[:] = (0.62, 0.13, 0.14)
    img[:int(h * 0.10)] = (0.50, 0.10, 0.11)
    img[int(h * 0.90):] = (0.50, 0.10, 0.11)
    _draw_text(img, "SALE", 0.10, 0.62, 0.22, 0.70, (0.95, 0.93, 0.86), t=0.26)
    # a yellow discount roundel on the right
    ys, xs = np.mgrid[0:h, 0:w]
    r = np.sqrt(((xs - w * 0.80) / (w * 0.14)) ** 2 + ((ys - h * 0.5) / (h * 0.34)) ** 2)
    img[r <= 1.0] = (0.87, 0.76, 0.22)
    base.write_png(TEX / "metro_banner.png", img)


# ===========================================================================
# Footprint
# ===========================================================================

def _way_ring(way_id):
    """Raw OSM outline of one way, in map metres."""
    data = json.loads((HERE / "banilad_osm.json").read_text())
    for el in data["elements"]:
        if el.get("type") == "way" and el.get("id") == way_id:
            pts = [project(g["lat"], g["lon"]) for g in el["geometry"]]
            if math.dist(pts[0], pts[-1]) < 0.5:
                pts = pts[:-1]
            return pts
    raise SystemExit("way {} not found in banilad_osm.json".format(way_id))


def metro_footprint():
    """The real OSM outline, translated so its centroid sits at the origin."""
    pts = _way_ring(METRO_WAY)
    cx = sum(p[0] for p in pts) / len(pts)
    cy = sum(p[1] for p in pts) / len(pts)
    ring = [(x - cx, y - cy) for x, y in pts]
    if parts.signed_area(ring) < 0:
        ring = ring[::-1]
    return ring, (cx, cy)


def corner_block_footprint(origin):
    """The block opposite, in METRO's local space so both share one glb.

    Translated by Metro's centroid rather than its own, so the two buildings
    keep their true 40 m separation and the whole junction can be placed in the
    city with a single transform.
    """
    pts = _way_ring(COLON_CORNER_WAY)
    ring = [(x - origin[0], y - origin[1]) for x, y in pts]
    if parts.signed_area(ring) < 0:
        ring = ring[::-1]
    return ring


def sign_edges(ring):
    """Split the elevations into (METRO-branded, billboard-hung).

    Picked GEOMETRICALLY rather than by vertex index -- the ring is re-wound to
    counter-clockwise on load, so indices shift and an index list would silently
    point at the wrong walls after any OSM re-fetch.

      * BRANDED: the north-west END wall (the ~13.5 m return at the left-hand
        end of the main frontage; its normal points north AND west, which is
        what separates it from the 13.1 m wall across the notch, whose normal
        points north and EAST), plus the second-longest return.
      * BILLBOARD: the longest elevation. Metro's long Colon frontage is hung
        with printed vinyl rather than branded -- the downtown signage canyon
        runs on tarpaulins, and reserving the channel letters for the corner is
        what makes the branding read as a corner marker instead of wallpaper.
    """
    ranked = edges_by_length(ring)
    billboard = ranked[:1]
    branded = ranked[1:2]
    for e in ranked:
        _i, length, _a, _b, nrm = e
        if (12.0 <= length <= 16.0 and nrm[1] > 0.7 and nrm[0] < 0.0
                and e not in branded and e not in billboard):
            branded.append(e)
            break
    return branded, billboard


def edges_by_length(ring):
    """(index, length, a, b, outward normal), longest first."""
    n = len(ring)
    cx = sum(p[0] for p in ring) / n
    cy = sum(p[1] for p in ring) / n
    out = []
    for i in range(n):
        a, b, nrm = parts.edge_of(ring, i, outward_from=(cx, cy))
        out.append((i, math.dist(a, b), a, b, nrm))
    out.sort(key=lambda e: -e[1])
    return out


# ===========================================================================
# The building
# ===========================================================================

def build_metro(batch):
    ring, _origin = metro_footprint()
    cx = sum(p[0] for p in ring) / len(ring)
    cy = sum(p[1] for p in ring) / len(ring)

    # --- mass -------------------------------------------------------------
    v, f = parts.walls(ring, 0.0, TOP)
    batch.add(v, f, "Metro_Panel")
    # parapet: a capping band proud of the wall, then the roof slab
    v, f = parts.band_ring(ring, TOP, TOP + 1.5, offset=0.30)
    batch.add(v, f, "Metro_Parapet")
    v, f = parts.flat_polygon(parts.offset_ring(ring, 0.35), TOP + 1.35)
    batch.add(v, f, "Metro_Roof")

    # --- vertical pilaster rhythm ----------------------------------------
    # The quiet vertical division of the facade into wide bays. This is the
    # building's dominant surface texture and the thing that stops a 45 m
    # frontage reading as one blank slab.
    # Shallow and wide: on the real building these are panel joints and flat
    # pilaster strips, not deep fins. They must also stand LESS proud than the
    # signage, or a 16 m sign sits behind them and disappears at grazing angles.
    for px, py, bearing in _perimeter_stations(ring, 6.5):
        v, f = parts.box(px, py, 0.0, TOP + 0.4, 0.55, 0.15, bearing)
        batch.add(v, f, "Metro_Pilaster")

    # --- sparse slot windows ---------------------------------------------
    # A department store is almost windowless. Two slot courses only, and only
    # on the long street elevations -- punching a window grid here is exactly
    # what would make it stop looking like Metro.
    long_edges = [e for e in edges_by_length(ring) if e[1] >= 12.0][:4]
    for _i, length, a, b, nrm in long_edges:
        for z in (TOP - 3.4, GROUND_H + FLOOR_H * 2.1):
            v, f = parts.facade_panel(a, b, nrm, 0.06, 0.94, z, z + 1.05, 0.10)
            batch.add(v, f, "Metro_Slot")

    # --- ground floor: glazed retail under a pale fascia -------------------
    # NOTE: proud, not recessed. A recessed band sits inside the solid wall and
    # renders as nothing (PROJECT_STATUS.md s3, bug 4).
    v, f = parts.band_ring(ring, 0.35, GROUND_H - 1.35, offset=0.06)
    batch.add(v, f, "Metro_Glass")
    v, f = parts.band_ring(ring, GROUND_H - 1.35, GROUND_H + 0.15, offset=0.34)
    batch.add(v, f, "Metro_Fascia")
    # plinth
    v, f = parts.band_ring(ring, 0.0, 0.35, offset=0.36)
    batch.add(v, f, "Metro_Parapet")

    # --- signage on the corner elevations ---------------------------------
    # Channel letters mounted on the wall, high on the two frontages that face
    # the junction, plus the red tarpaulin over the ground-floor fascia.
    branded, billboards = sign_edges(ring)

    # Vinyl tarpaulins on the long frontage: a dark frame with the printed
    # sheet standing proud of it, so it reads as hung rather than painted on.
    for _i, length, a, b, nrm in billboards:
        bw = min(0.66, 30.0 / max(length, 1.0))
        t0 = 0.50 - bw * 0.5
        z0 = GROUND_H + FLOOR_H * 0.85
        z1 = z0 + FLOOR_H * 2.6
        v, f = parts.facade_panel(a, b, nrm, t0 - 0.012, t0 + bw + 0.012,
                                  z0 - 0.35, z1 + 0.35, 0.30)
        batch.add(v, f, "Billboard_Frame")
        v, f = parts.facade_panel(a, b, nrm, t0, t0 + bw, z0, z1, 0.44)
        batch.add(v, f, "Metro_Billboard", uvs=[(0, 0), (1, 0), (1, 1), (0, 1)])

    for k, (_i, length, a, b, nrm) in enumerate(branded):
        # Capped by fraction AND by metres, so the sign stays clear of the
        # corner returns on the short set-back elevation instead of wrapping
        # off the end of it.
        sign_w = min(0.52, 20.0 / max(length, 1.0))
        t0 = 0.50 - sign_w * 0.5
        z0 = GROUND_H + FLOOR_H * 0.55
        v, f = parts.facade_panel(a, b, nrm, t0, t0 + sign_w,
                                  z0, z0 + FLOOR_H * 2.0, 0.38)
        batch.add(v, f, "Metro_Sign", uvs=[(0, 0), (1, 0), (1, 1), (0, 1)])
        # sale banner below it
        bw = min(0.42, 12.0 / max(length, 1.0))
        bt = 0.50 - bw * 0.5
        v, f = parts.facade_panel(a, b, nrm, bt, bt + bw,
                                  GROUND_H + 0.35, GROUND_H + 2.05, 0.46)
        batch.add(v, f, "Metro_Banner", uvs=[(0, 0), (1, 0), (1, 1), (0, 1)])

    # --- roofscape --------------------------------------------------------
    # Lift overrun and plant -- the stepped element that shows above the
    # parapet in every photograph of this corner.
    v, f = parts.box(cx - 6.0, cy + 9.0, TOP + 1.35, TOP + 6.2, 6.5, 5.0)
    batch.add(v, f, "Metro_Panel")
    v, f = parts.box(cx - 6.0, cy + 9.0, TOP + 6.2, TOP + 6.6, 6.9, 5.4)
    batch.add(v, f, "Metro_Parapet")
    for i, (ox, oy) in enumerate(((6.0, -8.0), (12.0, 2.0), (-2.0, -14.0),
                                  (2.0, 6.0), (14.0, -12.0))):
        v, f = parts.box(cx + ox, cy + oy, TOP + 1.35,
                         TOP + 2.6 + (i % 3) * 0.5, 2.2, 1.7)
        batch.add(v, f, "Metro_Plant")
    for ox, oy in ((-14.0, 4.0), (10.0, 10.0)):
        v, f = parts.box(cx + ox, cy + oy, TOP + 1.35, TOP + 5.4, 0.10, 0.10)
        batch.add(v, f, "Pole")
    return ring


def _perimeter_stations(ring, spacing):
    """Points along a ring roughly `spacing` apart, with the edge bearing."""
    n = len(ring)
    for i in range(n):
        ax, ay = ring[i]
        bx, by = ring[(i + 1) % n]
        dx, dy = bx - ax, by - ay
        length = math.hypot(dx, dy)
        if length < 1e-6:
            continue
        bearing = math.atan2(dy, dx)
        count = max(1, int(round(length / spacing)))
        for k in range(count):
            t = (k + 0.5) / count
            yield ax + dx * t, ay + dy * t, bearing


AD_BANDS = ("Ad_Navy", "Ad_Red", "Ad_Cream", "Ad_Teal")


def build_corner_block(batch, ring):
    """The rounded block opposite: horizontal advertising all the way up.

    Its identity is the OPPOSITE of Metro's. Metro is clean panel with the
    branding held to the corner; this is a smaller, older block whose every
    floor is let out as billboard space, over a lit signage fascia at street
    level and with a hoarding standing on the roof above everything. Modelling
    it as another plain box would erase the contrast that makes the junction
    read.
    """
    top = CORNER_LEVELS * CORNER_FLOOR
    cx = sum(p[0] for p in ring) / len(ring)
    cy = sum(p[1] for p in ring) / len(ring)

    v, f = parts.walls(ring, 0.0, top)
    batch.add(v, f, "Corner_Wall")

    # One advertising band per floor, wrapped right around the rounded corner.
    # Two things keep this from reading as a beach umbrella: the band covers
    # only about half its floor, so grey concrete shows above and below it, and
    # the colour is picked off a hash rather than cycling the list in order --
    # a strict rotation put a rainbow up the building.
    for lvl in range(1, CORNER_LEVELS):
        z0 = lvl * CORNER_FLOOR + 0.85
        z1 = (lvl + 1) * CORNER_FLOOR - 0.85
        if z1 <= z0:
            continue
        v, f = parts.band_ring(ring, z0, z1, offset=0.22)
        pick = int(parts.hash_unit(lvl * 7919 + 3) * len(AD_BANDS))
        batch.add(v, f, AD_BANDS[min(pick, len(AD_BANDS) - 1)])

    # Ground floor: glazed shops under a lit yellow fascia.
    v, f = parts.band_ring(ring, 0.3, CORNER_FLOOR - 1.15, offset=0.06)
    batch.add(v, f, "Metro_Glass")
    v, f = parts.band_ring(ring, CORNER_FLOOR - 1.15, CORNER_FLOOR + 0.15,
                           offset=0.30)
    batch.add(v, f, "Corner_Fascia")

    # Parapet, then the roof hoarding on its frame.
    v, f = parts.band_ring(ring, top, top + 0.9, offset=0.26)
    batch.add(v, f, "Corner_Wall")
    edges = edges_by_length(ring)
    if edges:
        _i, length, a, b, nrm = edges[0]
        for t in (0.16, 0.84):
            px = a[0] + (b[0] - a[0]) * t
            py = a[1] + (b[1] - a[1]) * t
            v, f = parts.box(px, py, top + 0.9, top + 8.4, 0.22, 0.22)
            batch.add(v, f, "Pole")
        v, f = parts.facade_panel(a, b, nrm, 0.08, 0.92, top + 2.6, top + 8.6, 0.34)
        batch.add(v, f, "Ad_Navy")
        v, f = parts.facade_panel(a, b, nrm, 0.06, 0.94, top + 2.3, top + 8.9, 0.20)
        batch.add(v, f, "Billboard_Frame")
    return top


def build_context(batch, ring, corner_ring):
    """Sidewalk and road, so the junction is not a pair of models on a plate."""
    pts = list(ring) + list(corner_ring)
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    x0, x1 = min(xs) - 30.0, max(xs) + 30.0
    y0, y1 = min(ys) - 26.0, max(ys) + 26.0

    v, f = parts.flat_polygon([(x0, y0), (x1, y0), (x1, y1), (x0, y1)], -0.02)
    batch.add(v, f, "Asphalt")
    for r in (ring, corner_ring):
        walk = parts.offset_ring(r, -4.5)
        if len(walk) == len(r):
            v, f = parts.walls(walk, -0.02, 0.16)
            batch.add(v, f, "Sidewalk")
            v, f = parts.flat_polygon(walk, 0.16)
            batch.add(v, f, "Sidewalk")


MANIFEST_MATERIALS = {
    # near-white panelled facade -- the building's identity
    # Three near-white values, separated by LIGHTNESS not hue -- that spread is
    # the only thing that keeps the panel joints and pilasters legible once the
    # facade goes white.
    "Metro_Panel":    {"tex": "metro_wall", "tint": [0.88, 0.88, 0.86], "rough": 0.85},
    "Metro_Pilaster": {"tex": "metro_wall", "tint": [1.00, 1.00, 0.98], "rough": 0.85},
    "Metro_Parapet":  {"tex": "metro_wall", "tint": [0.78, 0.78, 0.76], "rough": 0.88},
    "Metro_Roof":     {"tex": "concrete", "tint": [0.62, 0.61, 0.58], "rough": 0.92},
    "Metro_Fascia":   {"solid": [0.74, 0.72, 0.66], "rough": 0.85},
    # Lit retail behind the glass -- a department store ground floor is the
    # brightest thing on the street, not a black hole.
    "Metro_Glass":    {"solid": [0.20, 0.21, 0.22], "rough": 0.30, "metal": 0.2},
    # Rough, or the sun blows the slots out to white and they read as skylights.
    "Metro_Slot":     {"solid": [0.11, 0.12, 0.14], "rough": 0.80},
    # Tinted to the wall: these are channel letters mounted ON the cream panel,
    # not a white signboard hung off it.
    "Metro_Sign":     {"uvtex": "metro_sign", "alpha": True, "rough": 0.60},
    "Metro_Banner":   {"uvtex": "metro_banner", "tint": [0.95, 0.92, 0.90], "rough": 0.80},
    # Plain blue vinyl -- no printed artwork.
    "Metro_Billboard": {"solid": [0.09, 0.20, 0.48], "rough": 0.82},
    "Billboard_Frame": {"solid": [0.16, 0.15, 0.14], "rough": 0.85},
    "Metro_Plant":    {"solid": [0.38, 0.38, 0.40], "rough": 0.8},
    "Pole":           {"solid": [0.30, 0.30, 0.30], "rough": 0.7},
    # The block opposite: older grey concrete, hung with flat advertising.
    "Corner_Wall":    {"tex": "concrete", "tint": [0.70, 0.69, 0.66], "rough": 0.90},
    "Corner_Fascia":  {"solid": [0.72, 0.60, 0.22], "rough": 0.75},
    # Sun-faded print, not fresh ink -- the palette's standing rule.
    "Ad_Navy":        {"solid": [0.14, 0.21, 0.38], "rough": 0.85},
    "Ad_Red":         {"solid": [0.46, 0.19, 0.17], "rough": 0.85},
    "Ad_Cream":       {"solid": [0.60, 0.58, 0.53], "rough": 0.85},
    "Ad_Teal":        {"solid": [0.22, 0.35, 0.35], "rough": 0.85},
    "Asphalt":        {"tex": "asphalt", "tint": [0.98, 0.98, 1.00], "rough": 0.95},
    "Sidewalk":       {"tex": "concrete", "tint": [0.70, 0.69, 0.66], "rough": 0.92},
}


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    print("[metro] generating wall + signage ...")
    tex_metro_wall()
    tex_metro_sign()
    tex_sale_banner()
    base.tex_signage()

    batch = base.UVBatch()
    ring = build_metro(batch)
    _r, origin = metro_footprint()
    corner_ring = corner_block_footprint(origin)
    corner_top = build_corner_block(batch, corner_ring)
    build_context(batch, ring, corner_ring)

    glb = OUT / "metro.glb"
    verts_n, tris_n = base.to_glb(batch, glb)

    def cc0(short):
        return {"albedo": str(CC0 / (short + "_alb.jpg")),
                "normal": str(CC0 / (short + "_nrm.jpg")),
                "rough": str(CC0 / (short + "_rgh.jpg"))}

    manifest = {
        "glb": str(glb),
        "textures": {
            "plaster": cc0("plaster"), "concrete": cc0("concrete"),
            "asphalt": cc0("asphalt"),
            # desaturated wall map + the CC0 plaster's own normal/roughness
            "metro_wall": {"albedo": str(TEX / "metro_wall.png"),
                           "normal": str(CC0 / "plaster_nrm.jpg"),
                           "rough": str(CC0 / "plaster_rgh.jpg")},
            "metro_sign": {"albedo": str(TEX / "metro_sign.png")},
            "metro_banner": {"albedo": str(TEX / "metro_banner.png")},
            "signage": {"albedo": str(TEX / "signage.png")},
        },
        "materials": MANIFEST_MATERIALS,
    }
    (OUT / "metro_manifest.json").write_text(json.dumps(manifest, indent=2))

    print("[metro] metro {} nodes top {:.1f} m | corner {} nodes top {:.1f} m"
          " | verts={} tris={}".format(
              len(ring), TOP, len(corner_ring), corner_top, verts_n, tris_n))
    print("[metro] glb ->", glb)
    print("[metro] DONE")


if __name__ == "__main__":
    main()
