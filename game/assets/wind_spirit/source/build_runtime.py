"""Prepare this approved Tripo repair for the village; not a generic auto-rigger.

python build_runtime.py corrected.glb output.glb
Requires numpy, scipy, Pillow and pymeshlab. Embedded texture bytes are retained.
"""
from glb_tools import *
from scipy.spatial import cKDTree
import pymeshlab
import argparse, hashlib, tempfile


def smooth(a, b, x):
    t = np.clip((x-a)/(b-a), 0, 1)
    return t*t*(3-2*t)


def simplify(g, prim, target):
    a = prim['attributes']
    p = g.accessor(a['POSITION']); n = g.accessor(a['NORMAL'])
    uv = g.accessor(a['TEXCOORD_0']); f = g.accessor(prim['indices']).reshape(-1, 3)
    ms = pymeshlab.MeshSet()
    # OBJ import assigns texture IDs to every wedge (the Python Mesh constructor
    # leaves them unassigned). Weld positions after loading to keep atlas seams.
    with tempfile.TemporaryDirectory(prefix='spirit-qem-') as td:
        tmp = Path(td)
        (tmp/'map.jpg').write_bytes(g.image_bytes(0))
        (tmp/'mesh.mtl').write_text('newmtl surface\nKd 1 1 1\nmap_Kd map.jpg\n')
        with (tmp/'mesh.obj').open('w') as obj:
            obj.write('mtllib mesh.mtl\n')
            np.savetxt(obj, p, fmt='v %.9g %.9g %.9g')
            np.savetxt(obj, uv, fmt='vt %.9g %.9g')
            obj.write('usemtl surface\n')
            np.savetxt(obj, np.repeat(f+1, 2, axis=1), fmt='f %d/%d %d/%d %d/%d')
        ms.load_new_mesh(str(tmp/'mesh.obj'))
    ms.meshing_remove_duplicate_vertices()
    ms.meshing_decimation_quadric_edge_collapse_with_texture(
        targetfacenum=target, qualitythr=.3, extratcoordw=1.,
        preserveboundary=True, boundaryweight=20., preservenormal=True)
    m = ms.current_mesh()
    points = m.vertex_matrix(); faces = m.face_matrix(); wedges = m.wedge_tex_coord_matrix()
    # Split only UV seams for glTF's per-vertex attributes.
    keys = np.column_stack((faces.ravel(), wedges))
    unique, inv = np.unique(keys, axis=0, return_inverse=True)
    pos = points[unique[:, 0].astype(int)].astype('f4')
    coords = unique[:, 1:].astype('f4')
    nearest = cKDTree(p).query(pos)[1]
    normals = n[nearest].copy()
    normals /= np.maximum(np.linalg.norm(normals, axis=1, keepdims=True), 1e-12)
    result = (pos, normals, coords, inv.reshape(-1, 3).astype('u4'), prim['material'])
    if 'COLOR_0' in a:
        result += (g.accessor(a['COLOR_0'])[nearest],)
    print('simplified', len(f), '->', len(faces), 'triangles', flush=True)
    return result


def add_skin(path):
    g = GLB(path); d = g.doc; data = bytearray(g.data)
    pivots = np.array([[0, 0, 0], [-.081, .425, .20],
                       [.175, .365, .25], [-.337, .365, .25],
                       [-.081, .255, -.177]], dtype='f4')
    names = ['Body', 'Head', 'WingLeft', 'WingRight', 'Tail']

    def accessor(arr, kind, component):
        while len(data) % 4: data.append(0)
        view = len(d['bufferViews'])
        view_data = {'buffer': 0, 'byteOffset': len(data), 'byteLength': arr.nbytes}
        if kind != 'MAT4': view_data['target'] = 34962
        d['bufferViews'].append(view_data)
        data.extend(arr.tobytes())
        idx = len(d['accessors'])
        d['accessors'].append({'bufferView': view, 'componentType': component,
                               'count': len(arr), 'type': kind})
        return idx

    for i, prim in enumerate(d['meshes'][0]['primitives']):
        p = g.accessor(prim['attributes']['POSITION'])
        x, y, z = p.T
        weights = np.zeros((len(p), 4), dtype='f4')
        joints = np.zeros((len(p), 4), dtype='<u2')
        if i == 2:
            weights[:, 0] = 1
            joints[:, 0] = 4
        else:
            # Continuous falloff keeps the fused shoulder watertight while flapping.
            head = smooth(.405, .51, y)
            wing = smooth(.218, .302, abs(x + .081))
            wing *= smooth(.15, .205, y) * (1-smooth(.355, .415, y))
            wing *= smooth(.025, .09, z) * (1-smooth(.29, .37, z))
            wing *= 1-head
            weights[:, 0] = 1-head-wing
            weights[:, 1] = head
            weights[:, 2] = wing
            joints[:, 1] = 1
            joints[:, 2] = np.where(x > -.081, 2, 3)
        assert np.allclose(weights.sum(1), 1) and weights.min() >= -1e-6
        joints[weights == 0] = 0
        prim['attributes']['JOINTS_0'] = accessor(joints, 'VEC4', 5123)
        prim['attributes']['WEIGHTS_0'] = accessor(weights, 'VEC4', 5126)
    # Separate mesh and skeleton roots. Rest pose reproduces the approved model.
    d['nodes'] = [{'name': 'SpiritMesh', 'mesh': 0, 'skin': 0}]
    d['scenes'] = [{'nodes': [0, 1]}]
    for i, (name, pivot) in enumerate(zip(names, pivots)):
        node = {'name': name, 'translation': pivot.tolist()}
        if i == 0: node['children'] = [2, 3, 4, 5]
        d['nodes'].append(node)
    ibm = np.repeat(np.eye(4, dtype='f4')[None], len(pivots), axis=0)
    ibm[:, :3, 3] = -pivots
    d['skins'] = [{'name': 'SpiritRig', 'skeleton': 1, 'joints': list(range(1, 6)),
                   'inverseBindMatrices': accessor(ibm.transpose(0, 2, 1).copy(), 'MAT4', 5126)}]
    d['asset']['generator'] = 'Approved spirit runtime reduction and five-bone rig'
    d['extensionsUsed'] = [e for e in d.get('extensionsUsed', []) if e != 'KHR_materials_sheen']
    if not d['extensionsUsed']: d.pop('extensionsUsed')
    # Godot compatibility renderer: preserve standard roughness/normal material.
    for mat in d['materials']:
        mat.pop('extensions', None)
        # LDR village lighting otherwise clips the pale plumage to flat white.
        mat['pbrMetallicRoughness']['baseColorFactor'] = [.55, .55, .55, 1]
    d['buffers'][0]['byteLength'] = len(data)
    js = json.dumps(d, separators=(',', ':')).encode()
    js += b' ' * (-len(js) % 4); data += b'\0' * (-len(data) % 4)
    raw = struct.pack('<4sII', b'glTF', 2, 28+len(js)+len(data))
    raw += struct.pack('<II', len(js), 0x4e4f534a)+js
    raw += struct.pack('<II', len(data), 0x004e4942)+data
    Path(path).write_bytes(raw)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('input'); parser.add_argument('output')
    args = parser.parse_args()
    g = GLB(args.input)
    parts = [simplify(g, prim, target) for prim, target in
             zip(g.doc['meshes'][0]['primitives'], [52000, 7000, 5000])]
    positions = np.concatenate([p[0] for p in parts]); offset = 0; ff = []
    for part in parts:
        ff.append(part[3]+offset); offset += len(part[0])
    wp, wf, _, _ = weld(positions, np.concatenate(ff))
    boundary, nonmanifold, degenerate = topology(wp, wf)
    assert len(boundary) == nonmanifold == degenerate == 0, (len(boundary), nonmanifold, degenerate)
    export_glb(args.output, g, parts)
    add_skin(args.output)
    out = GLB(args.output)
    assert all(g.image_bytes(i) == out.image_bytes(i) for i in range(3))
    result = {'source_sha256': hashlib.sha256(g.path.read_bytes()).hexdigest(),
              'output_sha256': hashlib.sha256(out.path.read_bytes()).hexdigest(),
              'triangles': sum(len(p[3]) for p in parts), 'vertices': len(positions),
              'bytes': out.path.stat().st_size, 'texture_images_unchanged': True,
              'boundary_edges': 0, 'nonmanifold_edges': 0, 'bones': 5}
    Path(args.output).with_suffix('.json').write_text(json.dumps(result, indent=2))
    print(json.dumps(result), flush=True)


if __name__ == '__main__': main()
