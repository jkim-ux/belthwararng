"""HWR-GRASS-001 R3: static ground kit (tileable grass/dirt base colour + three small leaf clumps).

Inputs (scratch from bake_grass_views.py, see run.sh / run_ground.sh):
  build/top_{a,b}_color.npy, top_{a,b}_height.npy   top-down colour + height of the Tripo grass block
  build/side_color.npy, side_height.npy              front strip (the dirt wall is the bottom 0.045 units)
  build/bake_meta.json
Outputs (game/assets/environment/grass/ground/):
  ground_grass.png      1024x1024 sRGB, tileable, covers GRASS_WORLD x GRASS_WORLD world units
  ground_dirt.png       1024x1024 sRGB, tileable, covers DIRT_WORLD x DIRT_WORLD world units
  ground_variation.png  256x256 grey, tileable, smooth low-frequency mottling (sampled at ~9 units)
  grass_clumps.glb      three opaque leaf-clump meshes + one shared 256x256 leaf colour texture
  ground_manifest.json

Colour comes from the source bakes: patches of the top-down bake are splatted onto a toroidal canvas
(so the result tiles without a seam and has no direction), then the mean is moved to the village's
sage/beige palette and the contrast is lowered.  Nothing here is a plain flat colour or high-contrast
procedural noise; the leaf colour of the clumps is the same remapped source colour.

Usage: python3 build_ground_kit.py <build_dir> <out_dir>
"""
import hashlib, io, json, os, struct, sys, time
import numpy as np
from PIL import Image

BUILD, OUT = sys.argv[1], sys.argv[2]
os.makedirs(OUT, exist_ok=True)
t0 = time.time()
meta = json.load(open(os.path.join(BUILD, "bake_meta.json")))
HMAX = meta["height_max"]
SEED = 20260914

# ------------------------------------------------------------------ palette (sRGB targets, tunable)
GRASS_TARGET = (0.470, 0.515, 0.385)     # albedo; the village light (0.9 sun + 0.6 ambient) lifts it to a light olive-sage on screen
GRASS_CONTRAST = 0.032                   # sRGB std of the finished texture (source ~0.075)
DIRT_TARGET = (0.600, 0.520, 0.400)      # albedo; reads as warm beige under the same light
DIRT_CONTRAST = 0.030
LEAF_ROOT = (0.360, 0.450, 0.270)        # clump leaf gradient, darker than the ground so silhouettes read
LEAF_TIP = (0.520, 0.590, 0.360)
CLOVER_ROOT = (0.330, 0.440, 0.290)
CLOVER_TIP = (0.480, 0.570, 0.370)

GRASS_WORLD = 3.0        # world units covered by one repeat of ground_grass.png
DIRT_WORLD = 2.0
TEX = 1024


def srgb(x):
    x = np.clip(x, 0.0, 1.0)
    return np.where(x <= 0.0031308, 12.92 * x, 1.055 * np.power(x, 1 / 2.4) - 0.055)


def unsrgb(x):
    x = np.clip(np.asarray(x, dtype=np.float64), 0.0, 1.0)
    return np.where(x <= 0.04045, x / 12.92, np.power((x + 0.055) / 1.055, 2.4))


def fill_holes(h, bad, iters=40):
    h = h.copy()
    valid = ~bad
    for _ in range(iters):
        if valid.all():
            break
        acc = np.zeros_like(h)
        cnt = np.zeros_like(h)
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, -1), (1, -1), (-1, 1)):
            sv = np.roll(valid, (dy, dx), (0, 1))
            sh = np.roll(h, (dy, dx), (0, 1))
            acc += np.where(sv, sh, 0.0)
            cnt += sv
        fillable = (~valid) & (cnt > 0)
        h[fillable] = acc[fillable] / cnt[fillable]
        valid = valid | fillable
    return h


def box_down(img, f):
    h, w = img.shape[0] // f * f, img.shape[1] // f * f
    return img[:h, :w].reshape(h // f, f, w // f, f, -1).mean((1, 3))


def bilinear(img, ys, xs):
    """Sample img (H,W,C) at float rows ys / cols xs (clamped)."""
    H, W = img.shape[:2]
    ys = np.clip(ys, 0, H - 1.001)
    xs = np.clip(xs, 0, W - 1.001)
    y0 = np.floor(ys).astype(int); x0 = np.floor(xs).astype(int)
    fy = (ys - y0)[..., None]; fx = (xs - x0)[..., None]
    return ((img[y0, x0] * (1 - fx) + img[y0, x0 + 1] * fx) * (1 - fy)
            + (img[y0 + 1, x0] * (1 - fx) + img[y0 + 1, x0 + 1] * fx) * fy)


def resize(img, new_h, new_w):
    ys = (np.arange(new_h) + 0.5) * img.shape[0] / new_h - 0.5
    xs = (np.arange(new_w) + 0.5) * img.shape[1] / new_w - 0.5
    return bilinear(img, ys[:, None].repeat(new_w, 1), xs[None, :].repeat(new_h, 0))


# ------------------------------------------------------------------ sources
def load_top(band):
    c = np.load(os.path.join(BUILD, f"top_{band}_color.npy"))[..., :3].astype(np.float64)
    h = np.load(os.path.join(BUILD, f"top_{band}_height.npy"))[..., 0] * HMAX
    bad = h < 0.03
    return np.stack([fill_holes(c[..., k], bad) for k in range(3)], -1)


def load_dirt_strip():
    s = np.load(os.path.join(BUILD, "side_color.npy")).astype(np.float64)
    a = s[..., 3]
    rows = s.shape[0]
    z = np.linspace(meta["side_h"], 0.0, rows)
    lo = int(np.argmax(z < 0.045))
    strip = s[lo:, :, :3] / np.maximum(a[lo:, :, None], 1e-3)
    cover = a[lo:] > 0.9
    strip = np.stack([fill_holes(strip[..., k], ~cover) for k in range(3)], -1)
    return strip, 0.045, meta["side_h"] * 0 + 2.0 * meta["x_half"] * meta["scale"]   # (strip, world height, world width)


# ------------------------------------------------------------------ toroidal patch splatting
def splat(src, canvas_px, src_px_per_canvas_px, n_patches, r_min, r_max, seed, falloff=3.0):
    rng = np.random.default_rng(seed)
    acc = np.zeros((canvas_px, canvas_px, 3))
    wsum = np.zeros((canvas_px, canvas_px, 1))
    H, W = src.shape[:2]
    for _ in range(n_patches):
        r = int(rng.integers(r_min, r_max + 1))
        cy, cx = rng.uniform(0, canvas_px, 2)
        ang = rng.uniform(0, 2 * np.pi)
        flip = 1.0 if rng.random() < 0.5 else -1.0
        s = src_px_per_canvas_px
        margin = r * s * 1.5 + 1
        sy = rng.uniform(margin, max(margin + 1, H - margin))
        sx = rng.uniform(margin, max(margin + 1, W - margin))
        g = np.arange(-r, r + 1)
        gy, gx = np.meshgrid(g, g, indexing="ij")
        d2 = (gy ** 2 + gx ** 2) / float(r * r)
        w = np.clip(1.0 - d2, 0.0, 1.0) ** falloff
        ca, sa = np.cos(ang), np.sin(ang)
        ry = sy + s * (gy * ca - gx * sa)
        rx = sx + s * flip * (gy * sa + gx * ca)
        patch = bilinear(src, ry, rx)
        iy = (int(round(cy)) + gy) % canvas_px
        ix = (int(round(cx)) + gx) % canvas_px
        np.add.at(acc, (iy, ix), patch * w[..., None])
        np.add.at(wsum, (iy, ix), w[..., None])
    return acc / np.maximum(wsum, 1e-6)


def remap(lin, target_srgb, target_std_srgb):
    """Move the mean to the target colour and scale the deviations so the sRGB std hits the target."""
    mean = lin.reshape(-1, 3).mean(0)
    dev = lin - mean
    # soft-limit bright/dark outliers (single yellow tips would otherwise repeat as visible dots)
    lim = 1.6 * dev.reshape(-1, 3).std(0)
    dev = lim * np.tanh(dev / np.maximum(lim, 1e-6))
    out = unsrgb(target_srgb) + dev
    std = srgb(out).reshape(-1, 3).std(0).mean()
    k = target_std_srgb / max(std, 1e-6)
    return np.clip(unsrgb(target_srgb) + dev * k, 0.0, 1.0)


def smooth_noise(size, cycles, n_waves, seed, amp=1.0):
    rng = np.random.default_rng(seed)
    y, x = np.meshgrid(np.arange(size) / size, np.arange(size) / size, indexing="ij")
    v = np.zeros((size, size))
    for _ in range(n_waves):
        fx, fy = rng.integers(-cycles, cycles + 1, 2)
        if fx == 0 and fy == 0:
            fy = 1
        v += np.cos(2 * np.pi * (fx * x + fy * y) + rng.uniform(0, 2 * np.pi)) / np.sqrt(n_waves)
    v = v / max(np.abs(v).max(), 1e-6)
    return v * amp


def save_png(path, arr_srgb01, mode="RGB"):
    a = np.clip(np.rint(arr_srgb01 * 255.0), 0, 255).astype(np.uint8)
    Image.fromarray(a, mode).save(path, optimize=True)


def preview_tiled(path, arr_srgb01, n=2, size=512):
    img = Image.fromarray(np.clip(np.rint(arr_srgb01 * 255.0), 0, 255).astype(np.uint8), "RGB")
    img = img.resize((size, size), Image.BILINEAR)
    sheet = Image.new("RGB", (size * n, size * n))
    for i in range(n):
        for j in range(n):
            sheet.paste(img, (i * size, j * size))
    sheet.save(path)


# ------------------------------------------------------------------ 1. grass base colour
print("grass texture ...", flush=True)
canvas_ppu = TEX / GRASS_WORLD                     # 341 px per world unit
src_parts = []
for band in ("a", "b"):
    top = load_top(band)                            # 2048x1024 for 2.0 x 0.9 world -> 1024 / 1138 px per unit
    top = box_down(top, 2)                          # 1024x512
    src_parts.append(resize(top, int(0.9 * canvas_ppu), int(2.0 * canvas_ppu)))   # 307 x 682, square texels
grass_src = np.concatenate(src_parts, 0)           # 614 x 682 (two bands stacked; patches never straddle the join by more than r)
grass_lin = splat(grass_src, TEX, 1.0, 1400, 34, 80, SEED + 1)
grass_lin = remap(grass_lin, GRASS_TARGET, GRASS_CONTRAST)
grass_srgb = srgb(grass_lin)
save_png(os.path.join(OUT, "ground_grass.png"), grass_srgb)
preview_tiled(os.path.join(BUILD, "preview_ground_grass_tiled.png"), grass_srgb)
print("  mean sRGB", grass_srgb.reshape(-1, 3).mean(0).round(3), "std", grass_srgb.reshape(-1, 3).std(0).round(3), f"{time.time() - t0:.0f}s", flush=True)

# ------------------------------------------------------------------ 2. dirt base colour
print("dirt texture ...", flush=True)
strip, strip_h_world, strip_w_world = load_dirt_strip()      # ~77 rows x 2048 for 2.0 x 0.045 world
dirt_ppu = TEX / DIRT_WORLD                                    # 512 px per world unit
strip_sq = resize(strip, max(8, int(strip_h_world * dirt_ppu)), int(strip_w_world * dirt_ppu))   # 23 x 1024
dirt_lin = splat(strip_sq, TEX, 1.0, 26000, 6, 10, SEED + 2, falloff=2.0)
mottle = smooth_noise(TEX, 3, 8, SEED + 3, 0.035)
dirt_lin = dirt_lin * (1.0 + mottle[..., None])
dirt_lin = remap(dirt_lin, DIRT_TARGET, DIRT_CONTRAST)
dirt_srgb = srgb(dirt_lin)
save_png(os.path.join(OUT, "ground_dirt.png"), dirt_srgb)
preview_tiled(os.path.join(BUILD, "preview_ground_dirt_tiled.png"), dirt_srgb)
print("  mean sRGB", dirt_srgb.reshape(-1, 3).mean(0).round(3), "std", dirt_srgb.reshape(-1, 3).std(0).round(3), f"{time.time() - t0:.0f}s", flush=True)

# ------------------------------------------------------------------ 3. large-scale variation (linear grey, mean 0.5)
var = smooth_noise(256, 3, 10, SEED + 4, 0.5) + 0.5
Image.fromarray(np.clip(np.rint(var * 255.0), 0, 255).astype(np.uint8), "L").save(os.path.join(OUT, "ground_variation.png"), optimize=True)


# ------------------------------------------------------------------ 4. leaf clumps
class MeshBuilder:
    def __init__(self):
        self.P, self.N, self.UV, self.I = [], [], [], []

    def vert(self, p, n, uv):
        self.P.append(p); self.N.append(n); self.UV.append(uv)
        return len(self.P) - 1

    def tri(self, a, b, c):
        self.I.extend((a, b, c))

    def arrays(self):
        return (np.asarray(self.P, np.float32), np.asarray(self.N, np.float32),
                np.asarray(self.UV, np.float32), np.asarray(self.I, np.uint32))


def blade(mb, rng, base, length, width, tilt, bend, yaw, u_col, segs=4):
    """Curved tapered strip: root at `base`, leaning `tilt` rad from vertical towards `yaw`, bending further along."""
    d_h = np.array([np.cos(yaw), 0.0, np.sin(yaw)])
    side = np.array([-np.sin(yaw), 0.0, np.cos(yaw)])
    p = np.array(base, dtype=np.float64)
    ring = []
    u0 = u_col + rng.uniform(0.03, 0.30)
    for i in range(segs + 1):
        t = i / segs
        a = tilt + bend * t ** 1.6
        d = np.cos(a) * np.array([0.0, 1.0, 0.0]) + np.sin(a) * d_h
        if i > 0:
            p = p + d * (length / segs)
        w = width * (1.0 - 0.92 * t ** 1.3)
        n = np.cross(side, d); n /= np.linalg.norm(n)
        ring.append((mb.vert(p - side * w, n, (u0, 1.0 - t)), mb.vert(p + side * w, n, (u0 + 0.02, 1.0 - t))))
    for i in range(segs):
        a0, b0 = ring[i]; a1, b1 = ring[i + 1]
        mb.tri(a0, b0, b1); mb.tri(a0, b1, a1)


def tuft(rng, n_blades, length_range, width, radius, tilt_range, bend_range, u_col):
    mb = MeshBuilder()
    for k in range(n_blades):
        ang = 2 * np.pi * (k + rng.uniform(-0.3, 0.3)) / n_blades
        r = radius * np.sqrt(rng.uniform(0.05, 1.0))
        base = (r * np.cos(ang), 0.0, r * np.sin(ang))
        yaw = ang + rng.uniform(-0.6, 0.6)
        blade(mb, rng, base, rng.uniform(*length_range), width * rng.uniform(0.8, 1.2),
              rng.uniform(*tilt_range), rng.uniform(*bend_range), yaw, u_col)
    return mb


def clover(rng, n_stems, u_col):
    mb = MeshBuilder()
    for k in range(n_stems):
        ang = 2 * np.pi * k / n_stems + rng.uniform(-0.4, 0.4)
        r = 0.055 * np.sqrt(rng.uniform(0.1, 1.0))
        base = np.array([r * np.cos(ang), 0.0, r * np.sin(ang)])
        h = rng.uniform(0.045, 0.075)
        lean = rng.uniform(0.0, 0.25)
        top = base + np.array([np.cos(ang) * lean * h, h, np.sin(ang) * lean * h])
        u0 = u_col + rng.uniform(0.03, 0.28)
        # stem: thin quad facing the camera-ish (+Z)
        s = np.array([0.004, 0.0, 0.0])
        n = np.array([0.0, 0.0, 1.0])
        a = mb.vert(base - s, n, (u0, 1.0)); b = mb.vert(base + s, n, (u0 + 0.01, 1.0))
        c = mb.vert(top - s, n, (u0, 0.55)); d = mb.vert(top + s, n, (u0 + 0.01, 0.55))
        mb.tri(a, b, d); mb.tri(a, d, c)
        # three rounded leaflets in a fan around the stem top, drooping slightly outward
        for j in range(3):
            la = ang + (j - 1) * 2.1 + rng.uniform(-0.2, 0.2)
            ld = np.array([np.cos(la), 0.0, np.sin(la)])
            R = rng.uniform(0.020, 0.030)
            centre = top + ld * (R * 0.9) + np.array([0.0, 0.004, 0.0])
            droop = -0.35
            nrm = np.array([0.0, 1.0, 0.0]) * np.cos(droop) - ld * np.sin(droop) * 0.0
            nrm = np.array([-ld[0] * 0.3, 1.0, -ld[2] * 0.3]); nrm /= np.linalg.norm(nrm)
            ci = mb.vert(centre, nrm, (u0 + 0.005, 0.15))
            rim = []
            for m in range(7):
                th = 2 * np.pi * m / 7
                rr = R * (1.0 - 0.28 * np.cos(2 * (th - np.pi)) * 0.5 - 0.22 * max(np.cos(th - np.pi), 0.0))   # heart-ish notch at the back
                q = centre + (ld * np.cos(th) + np.array([-ld[2], 0.0, ld[0]]) * np.sin(th)) * rr
                q = q + np.array([0.0, -0.35 * rr * (0.5 + 0.5 * np.cos(th)), 0.0])
                rim.append(mb.vert(q, nrm, (u0 + 0.005, 0.0 + 0.3 * (0.5 + 0.5 * np.cos(th)))))
            for m in range(7):
                mb.tri(ci, rim[m], rim[(m + 1) % 7])
    return mb


rng = np.random.default_rng(SEED + 5)
CLUMPS = {
    "clump_short": tuft(rng, 14, (0.085, 0.125), 0.017, 0.075, (0.18, 0.55), (0.25, 0.75), 0.0),
    "clump_clover": clover(rng, 7, 1.0 / 3.0),
    "clump_edge": tuft(rng, 18, (0.16, 0.235), 0.021, 0.115, (0.12, 0.60), (0.30, 0.95), 2.0 / 3.0),
}

# shared leaf texture: three columns (short / clover / edge), gradient along v (row 0 = tip, bottom = root)
LT = 256
leaf = np.zeros((LT, LT, 3))
v = np.linspace(0.0, 1.0, LT)[:, None]           # 0 tip -> 1 root
cols = {0: (LEAF_TIP, LEAF_ROOT), 1: (CLOVER_TIP, CLOVER_ROOT), 2: (LEAF_TIP, LEAF_ROOT)}
u_var = smooth_noise(LT, 4, 6, SEED + 6, 0.045)
for k, (tip, root) in cols.items():
    x0, x1 = k * LT // 3, (k + 1) * LT // 3 if k < 2 else LT
    grad = unsrgb(tip) * (1.0 - v) + unsrgb(root) * v
    band = grad[:, None, :].repeat(x1 - x0, 1) * (1.0 + u_var[:, x0:x1, None])
    if k == 2:                                       # edge tufts: a touch more yellow at the tips
        band[..., 0] *= 1.0 + 0.08 * (1.0 - v[:, :, None].repeat(x1 - x0, 1)[..., 0])
    leaf[:, x0:x1] = band
save_png(os.path.join(OUT, "clump_leaves.png"), srgb(leaf))


def write_glb(path, meshes, texture_png_path, extras):
    buffers, views, accessors = [], [], []

    def add(data, target=None):
        off = sum(len(b) for b in buffers)
        buffers.append(data + b"\0" * ((-len(data)) % 4))
        v = {"buffer": 0, "byteOffset": off, "byteLength": len(data)}
        if target:
            v["target"] = target
        views.append(v)
        return len(views) - 1

    def acc(arr, ctype, atype, target, minmax=False):
        a = {"bufferView": add(arr.tobytes(), target), "componentType": ctype, "count": int(arr.shape[0]), "type": atype}
        if minmax:
            a["min"] = [float(x) for x in arr.min(0)]; a["max"] = [float(x) for x in arr.max(0)]
        accessors.append(a)
        return len(accessors) - 1

    nodes, gmeshes = [], []
    for name, (P, N, UV, I) in meshes.items():
        prim = {"attributes": {"POSITION": acc(P, 5126, "VEC3", 34962, True), "NORMAL": acc(N, 5126, "VEC3", 34962),
                               "TEXCOORD_0": acc(UV, 5126, "VEC2", 34962)},
                "indices": acc(I.reshape(-1, 1), 5125, "SCALAR", 34963), "material": 0, "mode": 4}
        gmeshes.append({"name": name, "primitives": [prim]})
        nodes.append({"name": name, "mesh": len(gmeshes) - 1, "extras": extras[name]})
    bv_tex = add(open(texture_png_path, "rb").read())
    js = {
        "asset": {"version": "2.0", "generator": "belthwararng tools/environment/grass/build_ground_kit.py"},
        "scene": 0, "scenes": [{"nodes": list(range(len(nodes)))}], "nodes": nodes, "meshes": gmeshes,
        "materials": [{"name": "clump_leaves", "doubleSided": True,
                       "pbrMetallicRoughness": {"baseColorTexture": {"index": 0}, "metallicFactor": 0.0, "roughnessFactor": 0.9}}],
        "textures": [{"source": 0, "sampler": 0}],
        "samplers": [{"magFilter": 9729, "minFilter": 9987, "wrapS": 33071, "wrapT": 33071}],
        "images": [{"name": "clump_leaves", "mimeType": "image/png", "bufferView": bv_tex}],
        "bufferViews": views, "accessors": accessors,
        "buffers": [{"byteLength": sum(len(b) for b in buffers)}],
    }
    jb = json.dumps(js, separators=(",", ":")).encode()
    jb += b" " * ((-len(jb)) % 4)
    bb = b"".join(buffers)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(jb) + 8 + len(bb)))
        f.write(struct.pack("<II", len(jb), 0x4E4F534A)); f.write(jb)
        f.write(struct.pack("<II", len(bb), 0x004E4942)); f.write(bb)


mesh_arrays, extras, clump_info = {}, {}, {}
for name, mb in CLUMPS.items():
    P, N, UV, I = mb.arrays()
    mesh_arrays[name] = (P, N, UV, I)
    info = {"tris": int(len(I) // 3), "verts": int(len(P)), "height": float(P[:, 1].max()), "radius": float(np.hypot(P[:, 0], P[:, 2]).max())}
    extras[name] = info
    clump_info[name] = info
    print(f"  {name}: {info['tris']} tris, height {info['height']:.3f}, radius {info['radius']:.3f}")
write_glb(os.path.join(OUT, "grass_clumps.glb"), mesh_arrays, os.path.join(OUT, "clump_leaves.png"), extras)
os.remove(os.path.join(OUT, "clump_leaves.png"))     # embedded in the GLB; keep one copy of the resource


# ------------------------------------------------------------------ 5. manifest
def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def file_entry(name, **extra):
    p = os.path.join(OUT, name)
    return dict({"file": name, "bytes": os.path.getsize(p), "sha256": sha256(p)}, **extra)


manifest = {
    "task": "HWR-GRASS-001 R3",
    "source": {"path": meta["source"], "bytes": os.path.getsize(meta["source"]), "sha256": sha256(meta["source"]),
               "tris": meta["source_tris"], "bake": "bake_grass_views.py top-down colour/height + front strip (see bake_meta.json)"},
    "tools": {"numpy": np.__version__, "python": sys.version.split()[0], "blender_bake": meta["blender"]},
    "seed": SEED,
    "palette_srgb": {"grass_target": GRASS_TARGET, "grass_contrast_std": GRASS_CONTRAST, "dirt_target": DIRT_TARGET,
                     "dirt_contrast_std": DIRT_CONTRAST, "leaf_root": LEAF_ROOT, "leaf_tip": LEAF_TIP,
                     "clover_root": CLOVER_ROOT, "clover_tip": CLOVER_TIP},
    "active": [
        file_entry("ground_grass.png", size=[TEX, TEX], world_units_per_repeat=GRASS_WORLD, colorspace="sRGB",
                   method="toroidal splat of 1400 rotated/flipped patches (0.10-0.23 units) from both top-down bakes, mean/contrast remapped"),
        file_entry("ground_dirt.png", size=[TEX, TEX], world_units_per_repeat=DIRT_WORLD, colorspace="sRGB",
                   method="toroidal splat of 26000 small patches from the dirt wall strip + 3.5% smooth mottling, mean/contrast remapped"),
        file_entry("ground_variation.png", size=[256, 256], colorspace="linear grey, mean 0.5", method="sum of 10 tileable cosine waves (1-3 cycles)"),
        file_entry("grass_clumps.glb", meshes=clump_info, texture="clump_leaves 256x256 sRGB embedded, opaque, doubleSided",
                   pivot="clump base centre, y=0 ground, +Y up", material="one shared material for all three meshes"),
    ],
    "legacy_kept_for_reference": ["grass_tile_a.glb", "grass_tile_b.glb", "grass_wind.gdshader", "grass_tile.gd", "grass_field.gd", "grass_review.tscn"],
    "seconds": round(time.time() - t0, 1),
}
with open(os.path.join(OUT, "ground_manifest.json"), "w") as f:
    json.dump(manifest, f, indent=1)
print("DONE", manifest["seconds"], "s")
