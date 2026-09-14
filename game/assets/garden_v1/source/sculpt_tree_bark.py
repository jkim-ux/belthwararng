"""Bake the tree's continuous, ridged trunk/branches/roots to a portable GLB.

Authoring only: Python + NumPy + SciPy + scikit-image. The game loads the baked
mesh, so none of these dependencies is needed by Godot or the exported game.
The scalar field joins the branches before meshing; no intersecting tube caps.
"""
from pathlib import Path
import json, struct
import numpy as np
from scipy.ndimage import map_coordinates, gaussian_filter
from skimage.measure import marching_cubes

ROOT = Path(__file__).resolve().parents[1]
STEP = .020
LO = np.array([-1.95, -.24, -1.40])
HI = np.array([1.75, 4.02, 1.23])
SHAPE = np.ceil((HI-LO)/STEP).astype(int)+1

def catmull(points, count):
    p=np.asarray(points,float);t=np.linspace(0,len(p)-1,count)
    i=np.minimum(t.astype(int),len(p)-2);u=(t-i)[:,None]
    a,b,c,d=p[np.maximum(i-1,0)],p[i],p[i+1],p[np.minimum(i+2,len(p)-1)]
    return .5*(2*b+(-a+c)*u+(2*a-5*b+4*c-d)*u*u+(-a+3*b-3*c+d)*u*u*u)

PATHS = [
    ([(0,-.04,0),(.18,.42,.05),(.27,.92,.03),(.06,1.38,0),(-.33,1.92,-.04),(-.4,2.48,-.08),(-.23,3.15,-.13),(.04,3.85,-.15)], [.43,.31,.28,.25,.21,.16,.105,.015]),
    ([(.10,1.38,0),(-.52,1.80,.06),(-1.08,2.12,.10),(-1.37,2.51,.13)], [.205,.15,.105,.024]),
    ([(-.1,1.68,-.02),(.45,2.11,-.04),(.88,2.30,.04),(1.08,2.63,.03)], [.20,.14,.09,.023]),
    ([(-.37,2.15,-.07),(.03,2.72,-.11),(.39,3.02,-.21),(.7,3.54,-.22)], [.155,.105,.07,.012]),
    ([(-.37,2.4,-.09),(-.7,2.91,-.17),(-1,3.47,-.30)], [.11,.065,.012]),
    ([(-.18,1.88,-.12),(.14,2.46,-.57),(.32,2.94,-.9)], [.13,.075,.012]),
]
rng=np.random.default_rng(61)
for i in range(9):
    a=i*np.pi*2/9+.17;d=np.array([np.cos(a),0,np.sin(a)]);length=rng.uniform(.67,1.04)
    PATHS.append(([(.04,.33,0),d*.31+[0,.13,0],d*length*.65+[0,.008,0],d*length+[0,-.04,0]], [.18,.12,.045,.004]))

def main():
    field=np.full(SHAPE,5.,np.float32)
    nearest=np.full(SHAPE,5.,np.float32)
    theta=np.zeros(SHAPE,np.float32)
    flow=np.zeros(SHAPE,np.float32)
    for pi,(points,radii) in enumerate(PATHS):
        pts=catmull(points,max(12,len(points)*12))
        rs=np.interp(np.linspace(0,len(radii)-1,len(pts)),np.arange(len(radii)),radii)
        pd=np.full(SHAPE,5.,np.float32)
        for j,(a,b,ra,rb) in enumerate(zip(pts[:-1],pts[1:],rs[:-1],rs[1:])):
            pad=max(ra,rb)+.13
            low=np.maximum(0,np.floor((np.minimum(a,b)-pad-LO)/STEP).astype(int))
            high=np.minimum(SHAPE,np.ceil((np.maximum(a,b)+pad-LO)/STEP).astype(int)+1)
            slices=tuple(slice(x,y) for x,y in zip(low,high))
            q=np.stack(np.meshgrid(*[LO[k]+np.arange(low[k],high[k])*STEP for k in range(3)],indexing='ij'),axis=-1)
            ab=b-a;t=np.clip(np.sum((q-a)*ab,axis=-1)/np.dot(ab,ab),0,1)
            delta=q-a-t[...,None]*ab
            distance=np.linalg.norm(delta,axis=-1)-(ra+(rb-ra)*t)
            pd[slices]=np.minimum(pd[slices],distance)
            better=distance<nearest[slices]
            tangent=ab/np.linalg.norm(ab)
            right=np.cross(tangent,[0,0,-1]);right/=max(np.linalg.norm(right),1e-9)
            other=np.cross(right,tangent)
            angles=np.arctan2(delta@other,delta@right)
            theta[slices]=np.where(better,angles,theta[slices])
            flow[slices]=np.where(better,(j+t)/len(pts)*4.0,flow[slices])
            nearest[slices]=np.minimum(nearest[slices],distance)
        # Smooth min between whole branches, never between adjacent segments.
        k=.065 if pi<6 else .075
        h=np.maximum(k-np.abs(field-pd),0)/k
        field=np.minimum(field,pd)-h*h*k*.25
    xyz=np.meshgrid(*[LO[k]+np.arange(SHAPE[k])*STEP for k in range(3)],indexing='ij',sparse=True)
    x,y,z=xyz
    theta=gaussian_filter(theta,.7)
    wind=theta+.21*np.sin(y*4.0+x*2.5)+.055*np.sin(y*13.0+z*6.0)
    ridge=np.sin(wind*15.0+np.sin(y*7.0+theta*3.0)*.75)
    grain=np.sin(wind*31.0+y*9.0+np.sin(y*15.0+x*9.0))
    field -= ridge*.0055+grain*.0025
    # Small oval whorl in the front bark, continuous with the surrounding field.
    knot=np.sqrt(((x-.27)/.085)**2+((y-.94)/.135)**2)
    front=np.exp(-((z-.27)/.12)**2)
    field-=np.sin(knot*10.)*np.exp(-knot*.8)*front*.011
    verts,faces,_,_=marching_cubes(field,0,spacing=(STEP,)*3,allow_degenerate=False)
    verts+=LO
    # Smooth marching normals while retaining the actual carved ridge geometry.
    grad=np.gradient(gaussian_filter(field,.60),STEP)
    coords=((verts-LO)/STEP).T
    norm=np.stack([map_coordinates(g,coords,order=1) for g in grad],axis=1)
    norm/=np.maximum(np.linalg.norm(norm,axis=1,keepdims=True),1e-9)
    th=map_coordinates(theta,coords,order=1)
    x,y,z=verts.T
    wind=th+.21*np.sin(y*4.+x*2.5)+.055*np.sin(y*13.+z*6.)
    grooves=np.sin(wind*15.+np.sin(y*7.+th*3.)*.75)
    fine=np.sin(wind*31.+y*9.+np.sin(y*15.+x*9.))
    broken=(.5+.5*np.sin(y*23.+x*31.+np.sin(z*18.)))
    base=np.array([.61,.435,.262])
    col=base+grooves[:,None]*np.array([.039,.036,.024])+fine[:,None]*.017
    col-=((np.maximum(0,-grooves)**8)*(.032+.028*broken))[:,None]
    col+=np.sin(y*8.+z*11.)[:,None]*np.array([.022,.018,.009])
    knot=np.sqrt(((x-.27)/.085)**2+((y-.94)/.135)**2)
    col-=((.5+.5*np.sin(knot*10.))**5*np.exp(-knot*.8)*np.exp(-((z-.27)/.12)**2)*.09)[:,None]
    col=np.clip(col,0,1)
    col=np.where(col<=.04045,col/12.92,((col+.055)/1.055)**2.4)
    # glTF winding is counter-clockwise; the importer converts to Godot winding.
    cross=np.cross(verts[faces[:,1]]-verts[faces[:,0]],verts[faces[:,2]]-verts[faces[:,0]])
    flip=np.sum(cross*norm[faces].sum(axis=1),axis=1)<0
    faces[flip]=faces[flip][:,[0,2,1]]
    save_glb(verts,norm,col,faces)

def save_glb(verts,norm,col,faces):
    binary=bytearray();views=[];accessors=[]
    def acc(data,kind,integer=False):
        a=np.asarray(data,dtype='<u4' if integer else '<f4')
        while len(binary)%4:binary.append(0)
        view={'buffer':0,'byteOffset':len(binary),'byteLength':a.nbytes}
        binary.extend(a.tobytes());views.append(view)
        d={'bufferView':len(views)-1,'componentType':5125 if integer else 5126,'count':len(a),'type':kind}
        if kind=='VEC3':d.update(min=a.min(axis=0).tolist(),max=a.max(axis=0).tolist())
        accessors.append(d);return len(accessors)-1
    attrs={'POSITION':acc(verts,'VEC3'),'NORMAL':acc(norm,'VEC3'),'COLOR_0':acc(col,'VEC3')}
    index=acc(faces.ravel(),'SCALAR',True)
    doc={'asset':{'version':'2.0','generator':'HWR-006 continuous bark sculpt'},'scene':0,'scenes':[{'nodes':[0]}],
         'nodes':[{'name':'ContinuousBark','mesh':0}], 'meshes':[{'primitives':[{'attributes':attrs,'indices':index,'material':0}]}],
         'materials':[{'name':'HoneyBark','pbrMetallicRoughness':{'baseColorFactor':[1,1,1,1],'roughnessFactor':.92,'metallicFactor':0}}],
         'buffers':[{'byteLength':len(binary)}],'bufferViews':views,'accessors':accessors}
    js=json.dumps(doc,separators=(',',':')).encode();js+=b' '*(-len(js)%4)
    payload=struct.pack('<III',0x46546c67,2,28+len(js)+len(binary))+struct.pack('<II',len(js),0x4e4f534a)+js+struct.pack('<II',len(binary),0x004e4942)+binary
    out=ROOT/'models'/'tree_bark.glb';out.parent.mkdir(exist_ok=True);out.write_bytes(payload)
    print(f'{out.name}: {len(verts)} vertices / {len(faces)} triangles / {len(payload)} bytes',flush=True)

if __name__=='__main__':main()
