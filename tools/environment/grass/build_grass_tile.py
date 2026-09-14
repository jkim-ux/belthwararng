"""HWR-GRASS-001 step 2: turn the Blender data bakes into game-ready grass tiles (numpy + Pillow only).

Per Z band (variant a / b) this builds ONE mesh, ONE material, ONE 2048x1536 atlas set:
  * turf   : 128x64 height-field sampled from the top-down height bake (world 2.0 x 0.9, one village cell)
  * wall   : dirt strip around the four sides, top edge welded to the turf edge, bottom at -WALL_DEPTH
  * fins   : two alpha-scissor cards on the near/far edges carrying the front-view grass-tip silhouette
Heights, colour and normals of the outer band are cross-faded into one shared, mirror-symmetric 2D edge patch,
so any tile (also rotated 180 deg) meets any neighbour without a height step or a texture seam.
TEXCOORD_1 (UV2).x = wind bend mask (0 wall/root .. 1 tip), .y = part id (0 turf, 0.5 wall, 1 fin).

Usage: python3 build_grass_tile.py <build_dir> <out_dir> [--grid 128x64]
"""
import sys, os, json, struct, io, hashlib, time
import numpy as np
from PIL import Image

BUILD, OUT = sys.argv[1], sys.argv[2]
GRID_X, GRID_Z = 128, 64
for i, a in enumerate(sys.argv):
    if a == "--grid":
        GRID_X, GRID_Z = [int(v) for v in sys.argv[i + 1].split("x")]
os.makedirs(OUT, exist_ok=True)
meta = json.load(open(os.path.join(BUILD, "bake_meta.json")))
S = meta["scale"]                       # source units -> world units
CELL_W, CELL_D = meta["cell_w"], meta["cell_d"]
HMAX = meta["height_max"]
SIDE_H = meta["side_h"]
TOP_W, TOP_H = meta["top_size"]
ATLAS_H = TOP_H + 512                    # + 256 wall rows + 256 fin rows
WALL_ROWS, FIN_ROWS = 256, 256
WALL_DEPTH = 0.2                         # world units below the y=0 reference (canal water sits at -0.12)
WALL_SRC_TOP = 0.05                      # source height of the vertical dirt wall used for the wall strip
FIN_SRC_BOTTOM, FIN_SRC_TOP = 0.045, SIDE_H
BLEND_X, BLEND_Z = 0.035, 0.05           # fraction of the tile width/depth whose texture blends into the shared edge band
FIN_OFFSET = 0.003                       # world units outside the wall plane
EPS = 0.002


def srgb(x):
    x = np.clip(x, 0.0, 1.0)
    return np.where(x <= 0.0031308, 12.92 * x, 1.055 * np.power(x, 1 / 2.4) - 0.055)


def fill_holes(h, bad, iters=40):
    """Replace 'bad' texels with the mean of valid neighbours, growing inward."""
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


def load_band(band):
    c = np.load(os.path.join(BUILD, f"top_{band}_color.npy"))[..., :3]
    n = np.load(os.path.join(BUILD, f"top_{band}_normal.npy"))[..., :3] * 2.0 - 1.0
    h = np.load(os.path.join(BUILD, f"top_{band}_height.npy"))[..., 0] * HMAX
    # blender (x, y, z) -> glTF (x, z_b, -y_b); world-normal in glTF axes
    n_gltf = np.stack([n[..., 0], n[..., 2], -n[..., 1]], axis=-1)
    n_gltf /= np.maximum(np.linalg.norm(n_gltf, axis=-1, keepdims=True), 1e-6)
    flip = n_gltf[..., 1] < 0.0
    n_gltf[flip] *= -1.0
    bad = h < 0.03                       # rays that fell through to the bottom face / outside the wall
    h = fill_holes(h, bad)
    c = np.stack([fill_holes(c[..., k], bad) for k in range(3)], axis=-1)
    n_gltf = np.stack([fill_holes(n_gltf[..., k], bad) for k in range(3)], axis=-1)
    n_gltf /= np.maximum(np.linalg.norm(n_gltf, axis=-1, keepdims=True), 1e-6)
    return c, n_gltf, h, int(bad.sum())


def blend_weights(n, frac):
    """Weight toward the shared edge profile: 1 at the edge, 0 at the end of the band (smoothstep)."""
    b = max(1, int(round(n * frac)))
    t = np.linspace(0.0, 1.0, b, endpoint=False)
    w = np.zeros(n)
    ramp = 1.0 - (3 * t * t - 2 * t * t * t)
    w[:b] = ramp
    w[n - b:] = np.maximum(w[n - b:], ramp[::-1])
    return w


def edge_band_x(arr, n, flip_sign=None):
    """Shared left/right band (H, n, C): a real patch made symmetric in z so rotated tiles match too.
    Column i is the content i texels inward from the edge. flip_sign negates a vector component under reversal."""
    band = arr[:, :n].astype(np.float64)
    rev = band[::-1].copy()
    if flip_sign is not None:
        rev[..., flip_sign] *= -1.0
    return 0.5 * (band + rev)


def edge_band_z(arr, n, flip_sign=None):
    """Shared far/near band (n, W, C): row i is i texels inward from the edge, symmetric in x."""
    band = arr[:n].astype(np.float64)
    rev = band[:, ::-1].copy()
    if flip_sign is not None:
        rev[..., flip_sign] *= -1.0
    return 0.5 * (band + rev)


def apply_edge_blend(arr, band_x, band_z, wx, wz, mirror_comp=None):
    """Cross-fade the outer texels of arr (H, W, C) into the shared 2D edge bands (mirrored at each edge),
    so the seam line of every tile carries identical texels and the blend region still looks like grass.
    For normal maps the mirrored copy negates the component across the seam (mirror_comp = (x_comp, z_comp))."""
    out = arr.astype(np.float64).copy()
    H, W = out.shape[:2]
    bx, bz = band_x.shape[1], band_z.shape[0]
    band_x, band_z = band_x.copy(), band_z.copy()
    mx, mz = band_x[:, ::-1].copy(), band_z[::-1].copy()
    if mirror_comp is not None:
        cx, cz = mirror_comp
        # the mirrored component must vanish on the seam line for both sides to agree
        band_x[..., cx] *= (np.arange(bx) / bx)[None, :]
        band_z[..., cz] *= (np.arange(bz) / bz)[:, None]
        mx, mz = band_x[:, ::-1].copy(), band_z[::-1].copy()
        mx[..., cx] *= -1.0
        mz[..., cz] *= -1.0
    w = wx[:bx][None, :, None]
    out[:, :bx] = out[:, :bx] * (1 - w) + band_x * w
    out[:, W - bx:] = out[:, W - bx:] * (1 - w[:, ::-1]) + mx * w[:, ::-1]
    w = wz[:bz][:, None, None]
    out[:bz] = out[:bz] * (1 - w) + band_z * w
    out[H - bz:] = out[H - bz:] * (1 - w[::-1]) + mz * w[::-1]
    return out


def grid_sample(h2d, gx, gz, pct=70):
    """Vertex heights: percentile pooling in a window centred on each grid vertex (keeps tufts)."""
    H, W = h2d.shape
    xs = np.linspace(0, W - 1, gx + 1)
    zs = np.linspace(0, H - 1, gz + 1)
    rx, rz = max(1, W // (2 * gx)), max(1, H // (2 * gz))
    out = np.zeros((gz + 1, gx + 1))
    for j, z in enumerate(zs):
        z0, z1 = int(max(0, round(z) - rz)), int(min(H, round(z) + rz + 1))
        rows = h2d[z0:z1]
        for i, x in enumerate(xs):
            x0, x1 = int(max(0, round(x) - rx)), int(min(W, round(x) + rx + 1))
            out[j, i] = np.percentile(rows[:, x0:x1], pct)
    return out


def bilinear_upsample(grid, W, H):
    gz, gx = grid.shape[0] - 1, grid.shape[1] - 1
    u = np.linspace(0, gx, W)
    v = np.linspace(0, gz, H)
    i0 = np.clip(np.floor(u).astype(int), 0, gx - 1)
    j0 = np.clip(np.floor(v).astype(int), 0, gz - 1)
    fu, fv = (u - i0)[None, :], (v - j0)[:, None]
    g = grid
    return (g[j0][:, i0] * (1 - fu) * (1 - fv) + g[j0][:, i0 + 1] * fu * (1 - fv)
            + g[j0 + 1][:, i0] * (1 - fu) * fv + g[j0 + 1][:, i0 + 1] * fu * fv)


def grid_normals(pos):
    """pos: (gz+1, gx+1, 3) world positions -> smooth vertex normals from central differences."""
    dx = np.gradient(pos, axis=1)
    dz = np.gradient(pos, axis=0)
    n = np.cross(dz, dx)
    n /= np.maximum(np.linalg.norm(n, axis=-1, keepdims=True), 1e-9)
    if n[..., 1].mean() < 0:
        n = -n
    return n


# ---------------------------------------------------------------- shared inputs
t0 = time.time()
bands = {b: load_band(b) for b in ("a", "b")}
side = np.load(os.path.join(BUILD, "side_color.npy"))            # (256, 2048, 4) linear, row 0 = top (z = SIDE_H)
side[..., :3] /= np.maximum(side[..., 3:4], 1e-3)                # Blender writes premultiplied alpha; cards need straight colour
# shared 2D edge bands (colour + normal) taken from variant a's far/left edge, symmetric for rot-180 tiles
BX, BZ = int(round(TOP_W * BLEND_X)), int(round(TOP_H * BLEND_Z))
band_c_x, band_c_z = edge_band_x(bands["a"][0], BX), edge_band_z(bands["a"][0], BZ)
band_n_x, band_n_z = edge_band_x(bands["a"][1], BX, flip_sign=2), edge_band_z(bands["a"][1], BZ, flip_sign=0)
wx, wz = blend_weights(TOP_W, BLEND_X), blend_weights(TOP_H, BLEND_Z)

# heights blend into the same 2D edge band, so the seam geometry of every tile is identical (and mirrored)
band_h_x, band_h_z = edge_band_x(bands["a"][2][..., None], BX)[..., 0], edge_band_z(bands["a"][2][..., None], BZ)[..., 0]
grids = {}
for b, (c, n, h, holes) in bands.items():
    hb = apply_edge_blend(h[..., None], band_h_x[..., None], band_h_z[..., None], wx, wz)[..., 0]
    g = grid_sample(hb, GRID_X, GRID_Z)
    # the mirrored band makes both edges equal up to sampling noise; make them exactly equal and symmetric
    ex = 0.5 * (g[:, 0] + g[:, -1]); ex = 0.5 * (ex + ex[::-1])
    ez = 0.5 * (g[0, :] + g[-1, :]); ez = 0.5 * (ez + ez[::-1])
    g[:, 0] = g[:, -1] = ex
    g[0, :] = g[-1, :] = ez
    grids[b] = g
Y0 = min(float(grids[b].min()) for b in grids) - EPS
print(f"source->world scale {S:.4f}, y reference (source) {Y0:.4f}, grid {GRID_X}x{GRID_Z}")


# ---------------------------------------------------------------- side strips (shared)
side_rows_z = (np.arange(side.shape[0])[::-1] + 0.5) / side.shape[0] * SIDE_H   # source z of each strip row
def side_rows(z_lo, z_hi):
    sel = np.where((side_rows_z >= z_lo) & (side_rows_z < z_hi))[0]
    return side[sel.min():sel.max() + 1]

wall_src = side_rows(0.0, WALL_SRC_TOP)                              # opaque dirt
wall_src = np.concatenate([wall_src[:, :, :3], np.ones_like(wall_src[:, :, :1])], axis=-1)
wall_half = np.asarray(Image.fromarray((np.clip(wall_src, 0, 1) * 255).astype(np.uint8)).resize((TOP_W, WALL_ROWS // 2), Image.LANCZOS)).astype(np.float64) / 255.0
# stack two copies (seam blended) so tall walls repeat instead of stretching
wall_block = np.concatenate([wall_half, wall_half], axis=0)
bw = 12
for k in range(bw):
    t = (k + 0.5) / bw
    r0, r1 = WALL_ROWS // 2 - bw + k, WALL_ROWS // 2 + k
    wall_block[r0] = wall_block[r0] * (1 - 0.5 * t) + wall_block[r1] * 0.5 * t
# X-tileable wall (the strip runs along the tile edge, neighbours continue it)
wxw = blend_weights(TOP_W, 0.06)
wall_block = wall_block * (1 - wxw[None, :, None]) + wall_block[:, ::-1] * wxw[None, :, None]
WALL_WORLD_H = 2 * WALL_SRC_TOP * S                                  # world height covered by the block

fin_src = side_rows(FIN_SRC_BOTTOM, FIN_SRC_TOP)
fin_block = np.asarray(Image.fromarray((np.clip(fin_src, 0, 1) * 255).astype(np.uint8)).resize((TOP_W, FIN_ROWS), Image.LANCZOS)).astype(np.float64) / 255.0
# grass only: dirt-coloured texels of the rounded edge are cut so interior seams never show brown
dirt = (fin_block[..., 0] > fin_block[..., 1] * 0.95)
fin_block[..., 3] = np.where(dirt, 0.0, fin_block[..., 3])
# drop isolated specks (single anti-aliased texels that would float above the grass after alpha scissor)
a = fin_block[..., 3]
neigh = sum(np.roll(np.roll(a, dy, 0), dx, 1) for dy in (-1, 0, 1) for dx in (-1, 0, 1)) / 9.0
fin_block[..., 3] = np.where(neigh < 0.3, 0.0, a)
FIN_Y0, FIN_Y1 = (FIN_SRC_BOTTOM - Y0) * S, (FIN_SRC_TOP - Y0) * S


# ---------------------------------------------------------------- mesh + atlas per variant
def build_variant(band):
    c, n, h, holes = bands[band]
    g = grids[band]
    cb = apply_edge_blend(c, band_c_x, band_c_z, wx, wz)
    nb = apply_edge_blend(n, band_n_x, band_n_z, wx, wz, mirror_comp=(0, 2))
    nb /= np.maximum(np.linalg.norm(nb, axis=-1, keepdims=True), 1e-6)

    # --- turf grid
    xs = np.linspace(-CELL_W / 2, CELL_W / 2, GRID_X + 1)
    zs = np.linspace(-CELL_D / 2, CELL_D / 2, GRID_Z + 1)
    X, Z = np.meshgrid(xs, zs)
    Y = (g - Y0) * S
    pos = np.stack([X, Y, Z], axis=-1)
    nrm = grid_normals(pos)
    tan = np.zeros_like(pos)
    tan[..., 0] = 1.0
    tan -= nrm * (nrm * tan).sum(-1, keepdims=True)
    tan /= np.maximum(np.linalg.norm(tan, axis=-1, keepdims=True), 1e-9)
    uv = np.stack([X / CELL_W + 0.5, (Z / CELL_D + 0.5) * (TOP_H / ATLAS_H)], axis=-1)
    h_world = Y
    mask = np.clip((h_world - 0.02) / 0.14, 0.0, 1.0) ** 1.3
    col = np.stack([mask, np.zeros_like(mask), np.zeros_like(mask), np.ones_like(mask)], axis=-1)

    V_pos = [pos.reshape(-1, 3)]
    V_nrm = [nrm.reshape(-1, 3)]
    V_tan = [np.concatenate([tan.reshape(-1, 3), np.ones((tan.size // 3, 1))], axis=1)]
    V_uv = [uv.reshape(-1, 2)]
    V_col = [col.reshape(-1, 4)]
    idx = []
    W1 = GRID_X + 1
    for j in range(GRID_Z):
        for i in range(GRID_X):
            a, b_, c_, d = j * W1 + i, j * W1 + i + 1, (j + 1) * W1 + i, (j + 1) * W1 + i + 1
            idx += [a, c_, b_, b_, c_, d]          # CCW seen from +Y
    base = W1 * (GRID_Z + 1)

    # --- walls: (edge vertices in order, outward normal, u fraction of the atlas used)
    def wall(edge_pts, edge_mask, outward, u_span):
        nonlocal base
        m = len(edge_pts)
        top = np.array(edge_pts)
        bot = top.copy()
        bot[:, 1] = -WALL_DEPTH
        length = np.linalg.norm(top[-1, [0, 2]] - top[0, [0, 2]])
        u = np.linspace(0, u_span, m)
        v_top = TOP_H / ATLAS_H
        v_bot = v_top + np.clip((top[:, 1] + WALL_DEPTH) / WALL_WORLD_H, 0, 1) * (WALL_ROWS / ATLAS_H)
        P = np.concatenate([top, bot])
        N = np.tile(np.array(outward, dtype=float), (2 * m, 1))
        T = np.tile(np.array([-outward[2], 0.0, outward[0], 1.0]), (2 * m, 1))
        UV = np.concatenate([np.stack([u, np.full(m, v_top)], 1), np.stack([u, v_bot], 1)])
        # top row is welded to the turf edge, so it must carry the same bend mask or the wind opens a crack
        C = np.concatenate([np.stack([np.asarray(edge_mask), np.full(m, 0.5), np.zeros(m), np.ones(m)], 1), np.tile(np.array([0.0, 0.5, 0.0, 1.0]), (m, 1))])
        V_pos.append(P); V_nrm.append(N); V_tan.append(T); V_uv.append(UV); V_col.append(C)
        ids = []
        for k in range(m - 1):
            t0_, t1_, b0_, b1_ = base + k, base + k + 1, base + m + k, base + m + k + 1
            tri1, tri2 = [t0_, b0_, t1_], [t1_, b0_, b1_]
            # orient outward
            p = P
            nn = np.cross(p[tri1[1] - base] - p[tri1[0] - base], p[tri1[2] - base] - p[tri1[0] - base])
            if np.dot(nn, outward) < 0:
                tri1, tri2 = tri1[::-1], tri2[::-1]
            ids += tri1 + tri2
        base += 2 * m
        return ids

    front = pos[-1, :, :]                     # z = +CELL_D/2 (toward the village camera)
    back = pos[0, :, :]
    left = pos[:, 0, :]
    right = pos[:, -1, :]
    idx += wall(list(front), mask[-1, :], (0, 0, 1), 1.0)
    idx += wall(list(back[::-1]), mask[0, ::-1], (0, 0, -1), 1.0)
    idx += wall(list(left), mask[:, 0], (-1, 0, 0), CELL_D / CELL_W)
    idx += wall(list(right[::-1]), mask[::-1, -1], (1, 0, 0), CELL_D / CELL_W)

    # --- fins (double sided cards just outside each wall)
    def fin(p0, p1, outward, u0, u1):
        nonlocal base
        o = np.array(outward, dtype=float) * FIN_OFFSET
        p0, p1 = np.array(p0, dtype=float) + o, np.array(p1, dtype=float) + o
        P = np.array([[p0[0], FIN_Y0, p0[2]], [p1[0], FIN_Y0, p1[2]], [p0[0], FIN_Y1, p0[2]], [p1[0], FIN_Y1, p1[2]]])
        N = np.tile(np.array([0.0, 1.0, 0.0]), (4, 1))        # up-normals: cards shade like the turf, not like walls
        T = np.tile(np.array([-outward[2], 0.0, outward[0], 1.0]), (4, 1))
        v_top = (TOP_H + WALL_ROWS) / ATLAS_H
        v_bot = 1.0
        UV = np.array([[u0, v_bot], [u1, v_bot], [u0, v_top], [u1, v_top]])
        C = np.array([[0, 1, 0, 1], [0, 1, 0, 1], [1, 1, 0, 1], [1, 1, 0, 1]], dtype=float)
        V_pos.append(P); V_nrm.append(N); V_tan.append(T); V_uv.append(UV); V_col.append(C)
        ids = [base, base + 1, base + 2, base + 1, base + 3, base + 2]
        base += 4
        return ids

    hw, hd = CELL_W / 2, CELL_D / 2
    # only the near/far edges get cards: the village camera looks along -Z, so cards on the +-X edges
    # would be seen edge-on as thin vertical lines at every column seam
    idx += fin((-hw, 0, hd), (hw, 0, hd), (0, 0, 1), 0.0, 1.0)
    idx += fin((hw, 0, -hd), (-hw, 0, -hd), (0, 0, -1), 0.0, 1.0)

    P = np.concatenate(V_pos).astype(np.float32)
    N = np.concatenate(V_nrm).astype(np.float32)
    T = np.concatenate(V_tan).astype(np.float32)
    UV = np.concatenate(V_uv).astype(np.float32)
    C = np.concatenate(V_col).astype(np.float32)
    I = np.array(idx, dtype=np.uint32)

    # --- atlas: colour (sRGB, alpha) and tangent-space normal
    nf = grid_normals(pos)
    Nf = np.stack([bilinear_upsample(nf[..., k], TOP_W, TOP_H) for k in range(3)], axis=-1)
    Nf /= np.maximum(np.linalg.norm(Nf, axis=-1, keepdims=True), 1e-9)
    Tf = np.zeros_like(Nf); Tf[..., 0] = 1.0
    Tf -= Nf * (Nf * Tf).sum(-1, keepdims=True)
    Tf /= np.maximum(np.linalg.norm(Tf, axis=-1, keepdims=True), 1e-9)
    Bf = np.cross(Nf, Tf)
    ts = np.stack([(nb * Tf).sum(-1), (nb * Bf).sum(-1), (nb * Nf).sum(-1)], axis=-1)
    ts /= np.maximum(np.linalg.norm(ts, axis=-1, keepdims=True), 1e-9)

    color_atlas = np.zeros((ATLAS_H, TOP_W, 4))
    color_atlas[:TOP_H, :, :3] = srgb(cb)
    color_atlas[:TOP_H, :, 3] = 1.0
    color_atlas[TOP_H:TOP_H + WALL_ROWS, :, :3] = srgb(wall_block[..., :3])
    color_atlas[TOP_H:TOP_H + WALL_ROWS, :, 3] = 1.0
    color_atlas[TOP_H + WALL_ROWS:, :, :3] = srgb(fin_block[..., :3])
    color_atlas[TOP_H + WALL_ROWS:, :, 3] = fin_block[..., 3]
    normal_atlas = np.full((ATLAS_H, TOP_W, 3), 0.5)
    normal_atlas[..., 2] = 1.0
    normal_atlas[:TOP_H] = ts * 0.5 + 0.5
    color_png = Image.fromarray((np.clip(color_atlas, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA")
    normal_png = Image.fromarray((np.clip(normal_atlas, 0, 1) * 255 + 0.5).astype(np.uint8), "RGB")
    color_png.save(os.path.join(BUILD, f"atlas_{band}_color.png"))
    normal_png.save(os.path.join(BUILD, f"atlas_{band}_normal.png"))
    stats = {
        "holes_filled_texels": holes,
        "turf_height_world_min": float(Y.min()), "turf_height_world_mean": float(Y.mean()), "turf_height_world_max": float(Y.max()),
        "turf_tris": GRID_X * GRID_Z * 2, "wall_tris": 2 * (2 * GRID_X + 2 * GRID_Z), "fin_tris": 4,
    }
    return P, N, T, UV, C, I, color_png, normal_png, stats


def write_glb(path, name, P, N, T, UV, C, I, color_png, normal_png, extras):
    buffers = []
    views = []

    def add(data, target=None):
        off = sum(len(b) for b in buffers)
        pad = (-len(data)) % 4
        buffers.append(data + b"\0" * pad)
        v = {"buffer": 0, "byteOffset": off, "byteLength": len(data)}
        if target:
            v["target"] = target
        views.append(v)
        return len(views) - 1

    def img_bytes(img):
        bio = io.BytesIO(); img.save(bio, format="PNG", optimize=True); return bio.getvalue()

    accessors = []
    def acc(arr, ctype, atype, target, minmax=False):
        bv = add(arr.tobytes(), target)
        a = {"bufferView": bv, "componentType": ctype, "count": int(arr.shape[0]), "type": atype}
        if minmax:
            a["min"] = [float(x) for x in arr.min(0)]
            a["max"] = [float(x) for x in arr.max(0)]
        accessors.append(a)
        return len(accessors) - 1

    a_pos = acc(P, 5126, "VEC3", 34962, True)
    a_nrm = acc(N, 5126, "VEC3", 34962)
    a_tan = acc(T, 5126, "VEC4", 34962)
    a_uv = acc(UV, 5126, "VEC2", 34962)
    a_col = acc(np.ascontiguousarray(C[:, :2]), 5126, "VEC2", 34962)   # UV2: x = bend mask, y = part id (COLOR_0 would tint a plain import)
    a_idx = acc(I.reshape(-1, 1), 5125, "SCALAR", 34963)
    bv_color = add(img_bytes(color_png))
    bv_normal = add(img_bytes(normal_png))
    js = {
        "asset": {"version": "2.0", "generator": "belthwararng tools/environment/grass/build_grass_tile.py"},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [{"name": name, "mesh": 0, "extras": extras}],
        "meshes": [{"name": name, "primitives": [{
            "attributes": {"POSITION": a_pos, "NORMAL": a_nrm, "TANGENT": a_tan, "TEXCOORD_0": a_uv, "TEXCOORD_1": a_col},
            "indices": a_idx, "material": 0, "mode": 4}]}],
        "materials": [{"name": name + "_mat", "doubleSided": True, "alphaMode": "MASK", "alphaCutoff": 0.5,
                       "pbrMetallicRoughness": {"baseColorTexture": {"index": 0}, "metallicFactor": 0.0, "roughnessFactor": 0.92},
                       "normalTexture": {"index": 1}}],
        "textures": [{"source": 0, "sampler": 0}, {"source": 1, "sampler": 0}],
        "samplers": [{"magFilter": 9729, "minFilter": 9987, "wrapS": 33071, "wrapT": 33071}],
        "images": [{"name": name + "_color", "mimeType": "image/png", "bufferView": bv_color},
                   {"name": name + "_normal", "mimeType": "image/png", "bufferView": bv_normal}],
        "bufferViews": views,
        "accessors": accessors,
        "buffers": [{"byteLength": sum(len(b) for b in buffers)}],
    }
    jb = json.dumps(js, separators=(",", ":")).encode()
    jb += b" " * ((-len(jb)) % 4)
    bb = b"".join(buffers)
    total = 12 + 8 + len(jb) + 8 + len(bb)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, total))
        f.write(struct.pack("<II", len(jb), 0x4E4F534A)); f.write(jb)
        f.write(struct.pack("<II", len(bb), 0x004E4942)); f.write(bb)
    return total


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


manifest = {
    "task": "HWR-GRASS-001",
    "source": {"path": meta["source"], "bytes": os.path.getsize(meta["source"]), "sha256": sha256(meta["source"]),
               "tris": meta["source_tris"], "verts": meta["source_verts"],
               "textures": "3x 4096x4096 JPEG (basecolor, metallic/roughness, normal)",
               "license": "user-provided Tripo generation (grass block 3d model)"},
    "tools": {"blender": meta["blender"], "numpy": np.__version__, "python": sys.version.split()[0]},
    "units": "1 unit = 1 Godot world unit; one tile = one village cell VillageStage3D.CELL_W x CELL_D",
    "footprint_world": [CELL_W, CELL_D],
    "pivot": "tile centre; y=0 = lowest turf/dirt point (village ground plane); walls extend to -WALL_DEPTH",
    "wall_depth_world": WALL_DEPTH,
    "source_to_world_scale": S,
    "source_y_reference": Y0,
    "sampled_source_footprint": {"x_half": meta["x_half"], "z_band": meta["band"], "bands": meta["bands"]},
    "fixed_parts": "UV2.x = bend mask: wall (UV2.y=0.5) and turf roots are 0, tips reach 1",
    "atlas": {"size": [TOP_W, ATLAS_H], "rows": {"turf": [0, TOP_H], "wall": [TOP_H, TOP_H + WALL_ROWS], "fin": [TOP_H + WALL_ROWS, ATLAS_H]},
              "color": "sRGB RGBA (alpha only used by fins)", "normal": "tangent-space, +Y up (glTF), roughness constant 0.92 (source RM map is flat: rough 0.92+-0.04, metal ~0)"},
    "lod": "LOD0 in the GLB; Godot importer meshes/generate_lods generates further levels (see report)",
    "variants": {},
}
for band in ("a", "b"):
    P, N, T, UV, C, I, cpng, npng, stats = build_variant(band)
    name = f"grass_tile_{band}"
    path = os.path.join(OUT, name + ".glb")
    extras = {"task": "HWR-GRASS-001", "footprint": [CELL_W, CELL_D], "wall_depth": WALL_DEPTH, "variant": band}
    size = write_glb(path, name, P, N, T, UV, C, I, cpng, npng, extras)
    manifest["variants"][band] = {
        "file": os.path.relpath(path, os.path.dirname(OUT)), "bytes": size, "sha256": sha256(path),
        "verts": int(P.shape[0]), "tris": int(I.size // 3), **stats,
    }
    print(f"{name}: {P.shape[0]} verts, {I.size // 3} tris, {size:,} bytes  turf y [{stats['turf_height_world_min']:.3f}, {stats['turf_height_world_max']:.3f}] mean {stats['turf_height_world_mean']:.3f}")
manifest["seconds"] = round(time.time() - t0, 1)
with open(os.path.join(OUT, "grass_manifest.json"), "w") as f:
    json.dump(manifest, f, indent=1)
print("DONE", manifest["seconds"], "s")
