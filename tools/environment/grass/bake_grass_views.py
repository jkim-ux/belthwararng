"""HWR-GRASS-001 step 1: orthographic data bakes of the Tripo grass block (runs inside Blender).

Renders the 1.93M-triangle source with emission-only materials so every pixel is exact
projected data (no lighting):
  * top-down per Z band:  color (linear RGB), world normal (normal map applied), height
  * front strip (shared): color + alpha of the front 0.07 band -> dirt wall + grass fin card

Usage (see run.sh):
  blender -b --python bake_grass_views.py -- <source.glb> <out_dir> [top_w top_h]

Outputs *.npy float32 arrays (row 0 = far/top edge, i.e. glTF -Z) plus bake_meta.json.
Blender 5.2 LTS, EEVEE. glTF import converts Y-up to Blender Z-up: blender(x, y, z) = gltf(x, -z, y).
"""
import bpy, sys, os, json, time
import numpy as np

argv = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT = argv[0], argv[1]
TOP_W = int(argv[2]) if len(argv) > 2 else 2048
TOP_H = int(argv[3]) if len(argv) > 3 else 1024
os.makedirs(OUT, exist_ok=True)

# Measured slab footprint of the source (glTF units). Bottom face spans x[-0.462,0.464] z[-0.466,0.465];
# the vertical dirt wall sits ~0.008 inside that, so the sampled footprint is inset to stay on the wall.
X_CENTER, X_HALF = 0.001, 0.455
Z_CENTER, Z_HALF = -0.0005, 0.455
WALL_OUTER = 0.4655                        # actual outer dirt wall / bottom face extent
CELL_W, CELL_D = 2.0, 0.9                  # VillageStage3D.CELL_W / CELL_D
SCALE = CELL_W / (2.0 * X_HALF)            # source -> world, uniform (2.1598)
BAND = CELL_D / SCALE                      # 0.4167 source units of depth per tile
HEIGHT_MAX = 0.2                           # height pass = z_blender / HEIGHT_MAX
SIDE_H = 0.15                              # front strip covers z_blender in [0, SIDE_H]
SIDE_DEPTH = 0.07                          # front band depth used for the fin card
BANDS = {
    "a": Z_CENTER - Z_HALF + BAND / 2.0 + 0.015,   # far half; the far mound edge retreats ~0.012 further than the near one
    "b": Z_CENTER + Z_HALF - BAND / 2.0,   # near half (glTF +Z)
}

t0 = time.time()
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
obj = [o for o in bpy.data.objects if o.type == "MESH"][0]
mesh = obj.data
print("source", obj.name, "tris", len(mesh.polygons), "verts", len(mesh.vertices))
src_mat = mesh.materials[0]
images = {}
for node in src_mat.node_tree.nodes:
    if node.type == "TEX_IMAGE" and node.image is not None:
        n = node.image.name.lower()
        key = "basecolor" if "basecolor" in n else ("normal" if "normal" in n else ("rm" if "_rm" in n else n))
        images[key] = node.image
print("images", {k: (v.name, tuple(v.size)) for k, v in images.items()})

sc = bpy.context.scene
sc.render.engine = "BLENDER_EEVEE"
sc.render.image_settings.file_format = "OPEN_EXR"
sc.render.image_settings.color_depth = "32"
sc.render.image_settings.color_mode = "RGBA"
sc.view_settings.view_transform = "Standard"
sc.view_settings.look = "None"
sc.view_settings.exposure = 0.0
sc.view_settings.gamma = 1.0
sc.world = bpy.data.worlds.new("Black")
sc.world.use_nodes = True
sc.world.node_tree.nodes["Background"].inputs[0].default_value = (0, 0, 0, 1)
cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
sc.collection.objects.link(cam)
sc.camera = cam
cam.data.type = "ORTHO"
cam.data.clip_start = 0.01
cam.data.clip_end = 10.0


def emission_material(name, build):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Strength"].default_value = 1.0
    nt.links.new(em.outputs[0], out.inputs[0])
    build(nt, em)
    m.use_backface_culling = False
    return m


def build_color(nt, em):
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = images["basecolor"]
    tex.image.colorspace_settings.name = "sRGB"
    nt.links.new(tex.outputs["Color"], em.inputs["Color"])


def build_normal(nt, em):
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = images["normal"]
    tex.image.colorspace_settings.name = "Non-Color"
    nm = nt.nodes.new("ShaderNodeNormalMap")
    nm.space = "TANGENT"
    nm.inputs["Strength"].default_value = 1.0
    nt.links.new(tex.outputs["Color"], nm.inputs["Color"])
    scale = nt.nodes.new("ShaderNodeVectorMath")
    scale.operation = "MULTIPLY_ADD"
    scale.inputs[1].default_value = (0.5, 0.5, 0.5)
    scale.inputs[2].default_value = (0.5, 0.5, 0.5)
    nt.links.new(nm.outputs["Normal"], scale.inputs[0])
    nt.links.new(scale.outputs[0], em.inputs["Color"])


def build_height(nt, em):
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(geo.outputs["Position"], sep.inputs[0])
    mul = nt.nodes.new("ShaderNodeMath")
    mul.operation = "MULTIPLY"
    mul.inputs[1].default_value = 1.0 / HEIGHT_MAX
    nt.links.new(sep.outputs["Z"], mul.inputs[0])
    comb = nt.nodes.new("ShaderNodeCombineXYZ")
    for i in range(3):
        nt.links.new(mul.outputs[0], comb.inputs[i])
    nt.links.new(comb.outputs[0], em.inputs["Color"])


MATS = {
    "color": emission_material("bake_color", build_color),
    "normal": emission_material("bake_normal", build_normal),
    "height": emission_material("bake_height", build_height),
}


def render_pass(tag, mat, w, h, pixel_aspect_y, samples, filter_size, transparent=False):
    mesh.materials[0] = mat
    sc.render.resolution_x, sc.render.resolution_y = w, h
    sc.render.resolution_percentage = 100
    sc.render.pixel_aspect_x, sc.render.pixel_aspect_y = 1.0, pixel_aspect_y
    sc.render.film_transparent = transparent
    sc.eevee.taa_render_samples = samples
    sc.render.filter_size = filter_size
    path = os.path.join(OUT, f"{tag}.exr")
    sc.render.filepath = path
    t = time.time()
    bpy.ops.render.render(write_still=True)
    img = bpy.data.images.load(path, check_existing=False)
    buf = np.empty(w * h * 4, dtype=np.float32)
    img.pixels.foreach_get(buf)
    arr = buf.reshape(h, w, 4)[::-1].copy()   # Blender pixels are bottom-up; store top-down
    bpy.data.images.remove(img)
    np.save(os.path.join(OUT, f"{tag}.npy"), arr)
    os.remove(path)
    print(f"pass {tag}: {w}x{h} in {time.time() - t:.1f}s  min={arr[..., :3].min():.4f} max={arr[..., :3].max():.4f}", flush=True)
    return arr


# ---------------------------------------------------------------- top-down bands
top_aspect_y = (BAND / (2.0 * X_HALF)) / (TOP_H / TOP_W)
for band, z_center in BANDS.items():
    cam.location = (X_CENTER, -z_center, 2.0)      # blender y = -gltf z
    cam.rotation_euler = (0.0, 0.0, 0.0)
    cam.data.ortho_scale = 2.0 * X_HALF
    render_pass(f"top_{band}_color", MATS["color"], TOP_W, TOP_H, top_aspect_y, 16, 1.5)
    render_pass(f"top_{band}_normal", MATS["normal"], TOP_W, TOP_H, top_aspect_y, 1, 0.01)
    render_pass(f"top_{band}_height", MATS["height"], TOP_W, TOP_H, top_aspect_y, 1, 0.01)

# ---------------------------------------------------------------- front strip (shared by all sides)
SIDE_W, SIDE_HPX = 2048, 256
side_aspect_y = (SIDE_H / (2.0 * X_HALF)) / (SIDE_HPX / SIDE_W)
front_y = -(Z_CENTER + WALL_OUTER)                 # blender y of the near (glTF +Z) dirt wall
cam.location = (X_CENTER, front_y - 1.0, SIDE_H / 2.0)
cam.rotation_euler = (np.radians(90.0), 0.0, 0.0)  # look along +Y (into the block)
cam.data.ortho_scale = 2.0 * X_HALF
cam.data.clip_start = 1.0 - 0.006
cam.data.clip_end = 1.0 + SIDE_DEPTH
render_pass("side_color", MATS["color"], SIDE_W, SIDE_HPX, side_aspect_y, 16, 1.5, transparent=True)
render_pass("side_normal", MATS["normal"], SIDE_W, SIDE_HPX, side_aspect_y, 1, 0.01, transparent=True)
render_pass("side_height", MATS["height"], SIDE_W, SIDE_HPX, side_aspect_y, 1, 0.01, transparent=True)

meta = {
    "source": SRC,
    "blender": bpy.app.version_string,
    "source_tris": len(mesh.polygons),
    "source_verts": len(mesh.vertices),
    "x_center": X_CENTER, "x_half": X_HALF, "z_center": Z_CENTER, "z_half": Z_HALF,
    "scale": SCALE, "band": BAND, "bands": BANDS,
    "cell_w": CELL_W, "cell_d": CELL_D,
    "top_size": [TOP_W, TOP_H], "height_max": HEIGHT_MAX,
    "side_size": [SIDE_W, SIDE_HPX], "side_h": SIDE_H, "side_depth": SIDE_DEPTH,
    "seconds": round(time.time() - t0, 1),
}
with open(os.path.join(OUT, "bake_meta.json"), "w") as f:
    json.dump(meta, f, indent=1)
print("DONE", meta["seconds"], "s")
