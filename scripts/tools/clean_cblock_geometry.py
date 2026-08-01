"""Remove ambiguous ground, vegetation, and tiny scan fragments from CBlock GLB.

The source is a single textured mesh. This tool keeps the recognizable building
components while dropping low, flat, green, or tiny disconnected components.
The replacement roads, landscaping, and props are authored clearly in Godot.
"""

from __future__ import annotations

import argparse
import io
import json
import struct
from pathlib import Path

import numpy as np
from PIL import Image


COMPONENT_DTYPES = {
    5121: np.uint8,
    5123: np.uint16,
    5125: np.uint32,
    5126: np.float32,
}
TYPE_COMPONENTS = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}
JSON_CHUNK = 0x4E4F534A
BIN_CHUNK = 0x004E4942


def read_glb(path: Path) -> tuple[dict, bytearray]:
    data = path.read_bytes()
    magic, version, total_length = struct.unpack_from("<4sII", data, 0)
    if magic != b"glTF" or version != 2:
        raise ValueError(f"{path} is not a GLB 2.0 file")

    chunks: list[tuple[int, bytes]] = []
    offset = 12
    while offset < total_length:
        chunk_length, chunk_type = struct.unpack_from("<II", data, offset)
        offset += 8
        chunks.append((chunk_type, data[offset : offset + chunk_length]))
        offset += chunk_length

    document = json.loads(
        next(chunk for kind, chunk in chunks if kind == JSON_CHUNK)
        .decode("utf-8")
        .rstrip("\0 ")
    )
    binary = bytearray(next(chunk for kind, chunk in chunks if kind == BIN_CHUNK))
    return document, binary


def accessor_array(document: dict, binary: bytearray, accessor_index: int) -> np.ndarray:
    accessor = document["accessors"][accessor_index]
    view = document["bufferViews"][accessor["bufferView"]]
    dtype = np.dtype(COMPONENT_DTYPES[accessor["componentType"]])
    component_count = TYPE_COMPONENTS[accessor["type"]]
    start = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
    stride = view.get("byteStride", dtype.itemsize * component_count)
    return np.ndarray(
        (accessor["count"], component_count),
        dtype=dtype,
        buffer=binary,
        offset=start,
        strides=(stride, dtype.itemsize),
    ).copy()


def embedded_image(document: dict, binary: bytearray, image_index: int) -> Image.Image:
    image = document["images"][image_index]
    view = document["bufferViews"][image["bufferView"]]
    start = view.get("byteOffset", 0)
    raw = bytes(binary[start : start + view["byteLength"]])
    return Image.open(io.BytesIO(raw)).convert("RGB")


def connected_roots(vertex_count: int, triangles: np.ndarray) -> np.ndarray:
    parent = np.arange(vertex_count, dtype=np.int32)
    sizes = np.ones(vertex_count, dtype=np.int32)

    def find(value: int) -> int:
        while parent[value] != value:
            parent[value] = parent[parent[value]]
            value = int(parent[value])
        return value

    def union(left: int, right: int) -> None:
        left_root = find(left)
        right_root = find(right)
        if left_root == right_root:
            return
        if sizes[left_root] < sizes[right_root]:
            left_root, right_root = right_root, left_root
        parent[right_root] = left_root
        sizes[left_root] += sizes[right_root]

    for triangle in triangles:
        union(int(triangle[0]), int(triangle[1]))
        union(int(triangle[0]), int(triangle[2]))

    return np.asarray([find(index) for index in range(vertex_count)], dtype=np.int32)


def clean_components(
    document: dict, binary: bytearray
) -> tuple[np.ndarray, int, int, int, list[dict[str, list[float]]]]:
    primitive = document["meshes"][0]["primitives"][0]
    positions = accessor_array(document, binary, primitive["attributes"]["POSITION"])
    uvs = accessor_array(document, binary, primitive["attributes"]["TEXCOORD_0"])
    indices = accessor_array(document, binary, primitive["indices"]).reshape(-1)
    triangles = indices.reshape(-1, 3).astype(np.int64)

    material = document["materials"][primitive["material"]]
    texture_index = material["pbrMetallicRoughness"]["baseColorTexture"]["index"]
    image_index = document["textures"][texture_index]["source"]
    image = np.asarray(embedded_image(document, binary, image_index))

    triangle_uvs = uvs[triangles].mean(axis=1)
    sample_x = np.clip(
        (triangle_uvs[:, 0] * (image.shape[1] - 1)).round().astype(int),
        0,
        image.shape[1] - 1,
    )
    sample_y = np.clip(
        ((1.0 - triangle_uvs[:, 1]) * (image.shape[0] - 1)).round().astype(int),
        0,
        image.shape[0] - 1,
    )
    colors = image[sample_y, sample_x].astype(np.float32) / 255.0
    green = (
        (colors[:, 1] > colors[:, 0] * 1.06)
        & (colors[:, 1] > colors[:, 2] * 1.10)
        & (colors[:, 1] > 0.16)
    )

    roots = connected_roots(len(positions), triangles)
    triangle_roots = roots[triangles[:, 0]]
    keep = np.ones(len(triangles), dtype=bool)
    removed_components = 0
    collision_boxes: list[dict[str, list[float]]] = []

    for root in np.unique(triangle_roots):
        mask = triangle_roots == root
        component_vertices = np.unique(triangles[mask])
        minimum = positions[component_vertices].min(axis=0)
        maximum = positions[component_vertices].max(axis=0)
        extent = maximum - minimum
        green_fraction = float(green[mask].mean())

        # Keep only unmistakable architectural masses. The generated source
        # contains hundreds of disconnected curb, shrub, road, roof-shard, and
        # prop components that remain visually muddy even after decimation.
        low_fragment = maximum[1] <= 0.045
        vegetation = (
            green_fraction >= 0.004
            and maximum[1] <= 0.12
            and extent[1] <= 0.11
        )
        tiny_prop = (
            extent[0] <= 0.022
            and extent[2] <= 0.022
            and extent[1] <= 0.045
        )
        flat_scan_fragment = (
            extent[1] <= 0.025 and max(extent[0], extent[2]) > 0.025
        )
        unreadable_sliver = (
            min(extent[0], extent[2]) <= 0.007
            and extent[1] <= 0.06
            and max(extent[0], extent[2]) >= 0.04
        )
        floating_fragment = minimum[1] > 0.03 and extent[1] < 0.06
        center = (minimum + maximum) * 0.5
        # One isolated center-north scan chunk reads as a floating wall/awning
        # after the low-detail surroundings are removed, so omit it explicitly.
        center_north_fragment = (
            0.04 <= center[0] <= 0.08
            and -0.19 <= center[2] <= -0.14
            and extent[1] < 0.08
        )

        if (
            low_fragment
            or vegetation
            or tiny_prop
            or flat_scan_fragment
            or unreadable_sliver
            or floating_fragment
            or center_north_fragment
        ):
            keep[mask] = False
            removed_components += 1
        elif (
            extent[1] > 0.018
            and extent[0] > 0.008
            and extent[2] > 0.008
        ):
            collision_boxes.append(
                {
                    "center": ((minimum + maximum) * 0.5).round(6).tolist(),
                    "size": extent.round(6).tolist(),
                    "triangles": int(mask.sum()),
                    "green_fraction": round(green_fraction, 6),
                }
            )

    cleaned_indices = triangles[keep].reshape(-1).astype(indices.dtype)
    return (
        cleaned_indices,
        len(triangles),
        int(keep.sum()),
        removed_components,
        collision_boxes,
    )


def replace_indices(
    document: dict, binary: bytearray, cleaned_indices: np.ndarray
) -> None:
    while len(binary) % 4:
        binary.append(0)
    byte_offset = len(binary)
    index_bytes = cleaned_indices.tobytes()
    binary.extend(index_bytes)

    primitive = document["meshes"][0]["primitives"][0]
    accessor = document["accessors"][primitive["indices"]]
    view_index = len(document["bufferViews"])
    document["bufferViews"].append(
        {
            "buffer": 0,
            "byteOffset": byte_offset,
            "byteLength": len(index_bytes),
            "target": 34963,
        }
    )
    accessor["bufferView"] = view_index
    accessor["byteOffset"] = 0
    accessor["count"] = int(cleaned_indices.size)
    accessor["min"] = [int(cleaned_indices.min())]
    accessor["max"] = [int(cleaned_indices.max())]
    document["buffers"][0]["byteLength"] = len(binary)


def compact_buffer_views(document: dict, binary: bytearray) -> bytearray:
    used: set[int] = set()
    for accessor in document.get("accessors", []):
        if "bufferView" in accessor:
            used.add(int(accessor["bufferView"]))
        sparse = accessor.get("sparse")
        if sparse:
            used.add(int(sparse["indices"]["bufferView"]))
            used.add(int(sparse["values"]["bufferView"]))
    for image in document.get("images", []):
        if "bufferView" in image:
            used.add(int(image["bufferView"]))

    mapping: dict[int, int] = {}
    output = bytearray()
    new_views: list[dict] = []
    for old_index in sorted(used):
        while len(output) % 4:
            output.append(0)
        old_view = document["bufferViews"][old_index]
        start = int(old_view.get("byteOffset", 0))
        length = int(old_view["byteLength"])
        new_view = dict(old_view)
        new_view["buffer"] = 0
        new_view["byteOffset"] = len(output)
        output.extend(binary[start : start + length])
        mapping[old_index] = len(new_views)
        new_views.append(new_view)

    for accessor in document.get("accessors", []):
        if "bufferView" in accessor:
            accessor["bufferView"] = mapping[int(accessor["bufferView"])]
        sparse = accessor.get("sparse")
        if sparse:
            sparse["indices"]["bufferView"] = mapping[
                int(sparse["indices"]["bufferView"])
            ]
            sparse["values"]["bufferView"] = mapping[
                int(sparse["values"]["bufferView"])
            ]
    for image in document.get("images", []):
        if "bufferView" in image:
            image["bufferView"] = mapping[int(image["bufferView"])]

    document["bufferViews"] = new_views
    document["buffers"][0]["byteLength"] = len(output)
    return output


def write_glb(path: Path, document: dict, binary: bytearray) -> None:
    json_bytes = json.dumps(document, separators=(",", ":")).encode("utf-8")
    json_bytes += b" " * ((4 - len(json_bytes) % 4) % 4)
    binary.extend(b"\0" * ((4 - len(binary) % 4) % 4))
    total_length = 12 + 8 + len(json_bytes) + 8 + len(binary)

    output = bytearray(struct.pack("<4sII", b"glTF", 2, total_length))
    output.extend(struct.pack("<II", len(json_bytes), JSON_CHUNK))
    output.extend(json_bytes)
    output.extend(struct.pack("<II", len(binary), BIN_CHUNK))
    output.extend(binary)
    path.write_bytes(output)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--collision-json", type=Path)
    args = parser.parse_args()

    document, binary = read_glb(args.input)
    (
        cleaned_indices,
        before,
        after,
        removed_components,
        collision_boxes,
    ) = clean_components(document, binary)
    replace_indices(document, binary, cleaned_indices)
    binary = compact_buffer_views(document, binary)
    write_glb(args.output, document, binary)
    if args.collision_json:
        args.collision_json.write_text(
            json.dumps({"scale": 140.0, "boxes": collision_boxes}, indent=2),
            encoding="utf-8",
        )
    print(
        f"{before:,} -> {after:,} triangles; "
        f"removed {removed_components} ambiguous components; "
        f"wrote {args.output}; {len(collision_boxes)} collision boxes"
    )


if __name__ == "__main__":
    main()
