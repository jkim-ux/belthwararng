#!/usr/bin/env bash
# HWR-GRASS-001 R3 — rebuild the static ground kit (tileable grass/dirt textures + three leaf clumps).
#   tools/environment/grass/run_ground.sh            (from the repository root)
# Reuses the Blender bakes from run.sh (tools/environment/grass/build/*.npy); bakes first if they are missing.
# Requires: python3 with numpy + Pillow; Blender 5.2 LTS on PATH as `blender` only for the bake step.
# Output: game/assets/environment/grass/ground/{ground_grass.png, ground_dirt.png, ground_variation.png,
#         grass_clumps.glb, ground_manifest.json}   (deterministic: same inputs -> byte-identical files)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SRC="$ROOT/source_assets/environments/tiles/grass block 3d model.glb"
BUILD="$ROOT/tools/environment/grass/build"
OUT="$ROOT/game/assets/environment/grass/ground"
if [ ! -f "$BUILD/top_a_color.npy" ] || [ ! -f "$BUILD/side_color.npy" ]; then
  head -c 4 "$SRC" | grep -q glTF || { echo "source is not a GLB (LFS pointer?): $SRC" >&2; exit 1; }
  echo "source sha256: $(shasum -a 256 "$SRC" | cut -d' ' -f1)"
  mkdir -p "$BUILD"
  blender -b --python "$ROOT/tools/environment/grass/bake_grass_views.py" -- "$SRC" "$BUILD" 2>&1 | grep -E "^(source|images|pass|DONE)|Error|Traceback"
fi
python3 "$ROOT/tools/environment/grass/build_ground_kit.py" "$BUILD" "$OUT"
rm -f "$OUT"/grass_clumps_clump_leaves.png "$OUT"/grass_clumps_clump_leaves.png.import
echo "reimport in Godot: (cd game && godot --headless --path . --import)"
