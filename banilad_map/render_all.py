"""Render every preview, one Blender process per shot.

A single Blender process rendering the whole set tends to die partway through
and take the remaining shots with it, leaving some previews stale while others
are current -- which is worse than failing outright, because the set silently
stops agreeing with itself. One process per shot means a crash costs one image,
and the run reports exactly which ones are missing.

    python render_all.py
    python render_all.py --blender "C:/Program Files/.../blender.exe"
"""

import argparse
import pathlib
import re
import shutil
import subprocess
import sys

HERE = pathlib.Path(__file__).parent
SCRIPT = HERE / "render_preview.py"

DEFAULT_BLENDER_CANDIDATES = [
    r"C:\Program Files\Blender Foundation\Blender 4.2\blender.exe",
    r"C:\Program Files\Blender Foundation\Blender 4.3\blender.exe",
    "/usr/bin/blender",
]


def find_blender(explicit):
    if explicit:
        return explicit
    found = shutil.which("blender")
    if found:
        return found
    for candidate in DEFAULT_BLENDER_CANDIDATES:
        if pathlib.Path(candidate).exists():
            return candidate
    raise SystemExit("blender not found; pass --blender <path>")


def shot_names():
    """Read the shot list out of render_preview.py so it stays the one source."""
    text = SCRIPT.read_text(encoding="utf-8")
    block = re.search(r"^SHOTS = \[(.*?)^\]", text, re.S | re.M)
    if not block:
        raise SystemExit("could not find SHOTS in render_preview.py")
    return re.findall(r'^\s*\("([A-Za-z0-9_]+)"', block.group(1), re.M)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--blender", default=None)
    ap.add_argument("shots", nargs="*", help="defaults to every shot")
    args = ap.parse_args()

    blender = find_blender(args.blender)
    names = args.shots or shot_names()

    ok, failed = [], []
    for i, name in enumerate(names, 1):
        print("[all] {:d}/{:d} {:s}".format(i, len(names), name), flush=True)
        result = subprocess.run(
            [blender, "-b", "-noaudio", "-P", str(SCRIPT), "--", name],
            capture_output=True, text=True,
        )
        target = HERE / "preview_{:s}.png".format(name)
        if result.returncode == 0 and target.exists():
            ok.append(name)
        else:
            failed.append(name)
            print("[all]   FAILED (exit {:d})".format(result.returncode),
                  flush=True)
            tail = (result.stderr or result.stdout or "").strip().splitlines()
            for line in tail[-4:]:
                print("[all]   | " + line, flush=True)

    print("\n[all] {:d} rendered, {:d} failed".format(len(ok), len(failed)))
    if failed:
        print("[all] failed: {:s}".format(", ".join(failed)))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
