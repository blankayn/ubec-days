"""Turn a straight-on building photo into a low-poly textured asset.

The "extrude trick": map a facade photo onto the front of a box, extrude it
back to give the building depth, and paint the faces the photo cannot see with
colours sampled out of the photo itself, so the sides read as the same building
instead of untextured grey. Textures are set to nearest-neighbour, which is
what the rest of the PSX art in this project uses.

    blender --background --python image_to_building.py
    blender --background --python image_to_building.py -- gaisano_stretch

Run with no arguments to build every preset. Each writes a GLB into
assets/buildings/.

What the photo cannot give you:
  * the sides and back, which get flat sampled colour (see SIDE_SAMPLE)
  * anything not in frame -- for the mall that is the covered walkway to the
    avenue, which stays hand-authored in build_map.py

Pixel coordinates in the presets are top-down, matching how you read the image
in any viewer. Blender stores rows bottom-up; from_top() does the flip.
"""

import math
import pathlib
import sys

import bpy
import numpy as np

HERE = pathlib.Path(__file__).parent
PROJECT = HERE.parent
OUT_DIR = PROJECT / "assets" / "buildings"

FACADE = str(HERE / "references" / "gaisano_facade.png")

# Gaisano Country Mall, measured off the built map: 182.8 x 193.4 m footprint,
# 16.4 m to the roof. The photo's facade band is 4.79:1 but the real frontage
# is 11.2:1, so the two presets below are the two honest ways to resolve that.
PRESETS = {
    # True to the site: full 182.8 m frontage, texture stretched 2.3x across.
    "gaisano_stretch": {
        "image": FACADE,
        "crop": (11, 277, 1529, 592),
        "width": 182.8,
        "height": 16.4,
        "depth": 96.0,
        "roof_sample": (250, 400, 350, 430),
        "wall_sample": (400, 330, 520, 372),
    },
    # True to the photo: keeps the arches square, covers 79 m of the frontage.
    "gaisano_aspect": {
        "image": FACADE,
        "crop": (11, 277, 1529, 592),
        "width": None,          # derived from the crop's aspect ratio
        "height": 16.4,
        "depth": 96.0,
        "roof_sample": (250, 400, 350, 430),
        "wall_sample": (400, 330, 520, 372),
    },
}


def log(msg):
    print("[img2bld] {:s}".format(msg))
    sys.stdout.flush()


def load_pixels(path):
    image = bpy.data.images.load(path, check_existing=True)
    width, height = image.size
    buffer = np.empty(width * height * 4, dtype=np.float32)
    image.pixels.foreach_get(buffer)
    return image, buffer.reshape(height, width, 4)


def from_top(pixels, y):
    """Top-down row index -> Blender's bottom-up row index."""
    return pixels.shape[0] - 1 - y


def sample_colour(pixels, box):
    """Mean linear colour of a pixel rectangle, given top-down coordinates."""
    x0, y0, x1, y1 = box
    region = pixels[from_top(pixels, y1):from_top(pixels, y0), x0:x1, :3]
    if region.size == 0:
        return (0.5, 0.5, 0.5, 1.0)
    mean = region.reshape(-1, 3).mean(axis=0)
    return (float(mean[0]), float(mean[1]), float(mean[2]), 1.0)


def image_material(name, image):
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    bsdf = nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = 0.9
    bsdf.inputs["Metallic"].default_value = 0.0

    texture = nodes.new("ShaderNodeTexImage")
    texture.image = image
    # PSX look, and it survives into the GLB as a NEAREST sampler.
    texture.interpolation = "Closest"
    texture.extension = "CLIP"
    texture.location = (-400, 200)
    links.new(texture.outputs["Color"], bsdf.inputs["Base Color"])
    return material


def flat_material(name, colour):
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    bsdf = material.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = colour
    bsdf.inputs["Roughness"].default_value = 0.92
    bsdf.inputs["Metallic"].default_value = 0.0
    return material


def build_card(name, spec):
    """One box: photo on the front, sampled colour everywhere else."""
    image, pixels = load_pixels(spec["image"])
    img_w, img_h = image.size

    x0, y0, x1, y1 = spec["crop"]
    crop_aspect = (x1 - x0) / float(y1 - y0)

    height = float(spec["height"])
    width = float(spec["width"]) if spec.get("width") else height * crop_aspect
    depth = float(spec["depth"])
    stretch = (width / height) / crop_aspect

    # Front face is -Y so the building looks toward the viewer; the caller
    # rotates it into place in the city.
    hw, hd = width * 0.5, depth * 0.5
    verts = [
        (-hw, -hd, 0.0), (hw, -hd, 0.0), (hw, -hd, height), (-hw, -hd, height),
        (-hw, hd, 0.0), (hw, hd, 0.0), (hw, hd, height), (-hw, hd, height),
    ]
    faces = [
        (0, 1, 2, 3),   # front  - photo
        (5, 4, 7, 6),   # back
        (4, 0, 3, 7),   # left
        (1, 5, 6, 2),   # right
        (3, 2, 6, 7),   # roof
        (4, 5, 1, 0),   # underside
    ]

    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)

    facade_mat = image_material("%s_Facade" % name, image)
    wall_mat = flat_material("%s_Wall" % name,
                             sample_colour(pixels, spec["wall_sample"]))
    roof_mat = flat_material("%s_Roof" % name,
                             sample_colour(pixels, spec["roof_sample"]))
    mesh.materials.append(facade_mat)
    mesh.materials.append(wall_mat)
    mesh.materials.append(roof_mat)
    for polygon, slot in zip(mesh.polygons, [0, 1, 1, 1, 2, 1]):
        polygon.material_index = slot

    # UVs: the front face gets the cropped band, everything else collapses to a
    # single pixel so the flat materials show no texture seams.
    u0, u1 = x0 / img_w, x1 / img_w
    v0, v1 = 1.0 - y1 / img_h, 1.0 - y0 / img_h
    uv_layer = mesh.uv_layers.new(name="UVMap")
    front_uvs = [(u0, v0), (u1, v0), (u1, v1), (u0, v1)]
    for polygon in mesh.polygons:
        for corner, loop_index in enumerate(polygon.loop_indices):
            if polygon.material_index == 0:
                uv_layer.data[loop_index].uv = front_uvs[corner]
            else:
                uv_layer.data[loop_index].uv = (0.0, 0.0)

    log("%s: %.1f x %.1f x %.1f m, crop %dx%d px (%.2f:1), texture stretch %.2fx"
        % (name, width, height, depth,
           x1 - x0, y1 - y0, crop_aspect, stretch))
    return obj


def export(obj, name):
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    out = OUT_DIR / ("%s.glb" % name)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.export_scene.gltf(
        filepath=str(out),
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_apply=True,
        export_cameras=False,
        export_lights=False,
        export_materials="EXPORT",
    )
    log("wrote %s (%.2f MB)" % (out.name, out.stat().st_size / 1048576))


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def main():
    wanted = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    names = wanted or list(PRESETS)
    unknown = [n for n in names if n not in PRESETS]
    if unknown:
        raise SystemExit("unknown preset(s): %s\nknown: %s"
                         % (", ".join(unknown), ", ".join(sorted(PRESETS))))
    for name in names:
        clear_scene()
        export(build_card(name, PRESETS[name]), name)
    log("DONE")


main()
