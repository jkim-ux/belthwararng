#!/usr/bin/env bash
# HWR-GRASS-001 — rebuild the game grass tiles from the Tripo source in one command.
#   tools/environment/grass/run.sh            (from the repository root)
# Requires: Blender 5.2 LTS on PATH as `blender` (brew install --cask blender), python3 with numpy + Pillow.
# Input : source_assets/environments/tiles/grass block 3d model.glb   (Git LFS; run `git lfs pull` first)
# Output: game/assets/environment/grass/grass_tile_{a,b}.glb + grass_manifest.json
# Scratch: tools/environment/grass/build/ (bakes as .npy, atlas previews; ignored by git)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SRC="$ROOT/source_assets/environments/tiles/grass block 3d model.glb"
BUILD="$ROOT/tools/environment/grass/build"
OUT="$ROOT/game/assets/environment/grass"
head -c 4 "$SRC" | grep -q glTF || { echo "source is not a GLB (LFS pointer?): $SRC" >&2; exit 1; }
echo "source sha256: $(shasum -a 256 "$SRC" | cut -d' ' -f1)"
mkdir -p "$BUILD"
blender -b --python "$ROOT/tools/environment/grass/bake_grass_views.py" -- "$SRC" "$BUILD" 2>&1 | grep -E "^(source|images|pass|DONE)|Error|Traceback"
python3 "$ROOT/tools/environment/grass/build_grass_tile.py" "$BUILD" "$OUT"
echo "reimport in Godot: (cd game && godot --headless --path . --import)"
