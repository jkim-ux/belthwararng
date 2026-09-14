import json, struct, io, copy
from pathlib import Path
import numpy as np
from PIL import Image

class GLB:
    def __init__(self,path):
        self.path=Path(path); raw=self.path.read_bytes()
        magic,version,total=struct.unpack_from('<4sII',raw)
        assert magic==b'glTF' and version==2 and total==len(raw)
        self.data=b''; self.doc={}; offset=12
        while offset<len(raw):
            size,kind=struct.unpack_from('<II',raw,offset); chunk=raw[offset+8:offset+8+size]
            if kind==0x4e4f534a:self.doc=json.loads(chunk)
            elif kind==0x004e4942:self.data=chunk
            offset+=8+size
    def accessor(self,i):
        a=self.doc['accessors'][i]; v=self.doc['bufferViews'][a['bufferView']]
        dtype=np.dtype({5126:'<f4',5125:'<u4',5123:'<u2',5121:'u1'}[a['componentType']])
        count=a['count']; dim={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4}[a['type']]
        return np.ndarray((count,dim),dtype=dtype,buffer=self.data,offset=v.get('byteOffset',0)+a.get('byteOffset',0),strides=(v.get('byteStride',dim*dtype.itemsize),dtype.itemsize)).copy()
    def image_bytes(self,i):
        v=self.doc['bufferViews'][self.doc['images'][i]['bufferView']]; start=v.get('byteOffset',0)
        return self.data[start:start+v['byteLength']]
    def mesh(self):
        p=self.doc['meshes'][0]['primitives'][0]; a=p['attributes']
        return self.accessor(a['POSITION']),self.accessor(a['NORMAL']),self.accessor(a['TEXCOORD_0']),self.accessor(p['indices']).reshape(-1,3)

def export_glb(path,source,primitives,materials=None):
    doc={'asset':{'version':'2.0','generator':'Bird local mesh repair'},'scene':0,'scenes':[{'nodes':[0]}],'nodes':[{'name':'WindSpirit','mesh':0}],'meshes':[{'name':'WindSpirit','primitives':[]}],'materials':copy.deepcopy(materials or source.doc['materials']),'textures':copy.deepcopy(source.doc.get('textures',[])),'samplers':copy.deepcopy(source.doc.get('samplers',[])),'images':[],'accessors':[],'bufferViews':[],'buffers':[]}
    data=bytearray()
    def view(raw,target=None):
        while len(data)%4:data.append(0)
        v={'buffer':0,'byteOffset':len(data),'byteLength':len(raw)}
        if target:v['target']=target
        data.extend(raw); doc['bufferViews'].append(v); return len(doc['bufferViews'])-1
    def accessor(arr,typ,component,target):
        arr=np.ascontiguousarray(arr,dtype='<f4' if component==5126 else '<u4')
        a={'bufferView':view(arr.tobytes(),target),'componentType':component,'count':len(arr),'type':typ}
        if typ=='VEC3':a.update(min=arr.min(axis=0).tolist(),max=arr.max(axis=0).tolist())
        doc['accessors'].append(a);return len(doc['accessors'])-1
    for i,info in enumerate(source.doc.get('images',[])):
        im=copy.deepcopy(info);im['bufferView']=view(source.image_bytes(i));doc['images'].append(im)
    for primitive in primitives:
        p,n,uv,f,mat=primitive[:5]
        attrs={'POSITION':accessor(p,'VEC3',5126,34962),'NORMAL':accessor(n,'VEC3',5126,34962),'TEXCOORD_0':accessor(uv,'VEC2',5126,34962)}
        if len(primitive)>5:attrs['COLOR_0']=accessor(primitive[5],'VEC3',5126,34962)
        doc['meshes'][0]['primitives'].append({'attributes':attrs,'indices':accessor(f.ravel(),'SCALAR',5125,34963),'material':mat,'mode':4})
    extensions=set()
    for mat in doc['materials']:extensions.update(mat.get('extensions',{}))
    if extensions:doc['extensionsUsed']=sorted(extensions)
    while len(data)%4:data.append(0)
    doc['buffers']=[{'byteLength':len(data)}];j=json.dumps(doc,separators=(',',':')).encode()
    j+=b' '*((-len(j))%4)
    raw=struct.pack('<4sII',b'glTF',2,12+8+len(j)+8+len(data))+struct.pack('<II',len(j),0x4e4f534a)+j+struct.pack('<II',len(data),0x004e4942)+data
    Path(path).write_bytes(raw)

def weld(p,f,decimals=7):
    q=np.round(p,decimals);_,index,inverse=np.unique(q,axis=0,return_index=True,return_inverse=True)
    return p[index],inverse[f],inverse,index

def topology(p,f):
    edges=np.concatenate([f[:,[0,1]],f[:,[1,2]],f[:,[2,0]]]); se=np.sort(edges,axis=1)
    key=se[:,0].astype(np.int64)*len(p)+se[:,1]; uk,idx,cnt=np.unique(key,return_index=True,return_counts=True)
    boundary=edges[idx[cnt==1]]
    return boundary, int(np.sum(cnt>2)), int(np.sum((f[:,0]==f[:,1])|(f[:,1]==f[:,2])|(f[:,2]==f[:,0])))

def compact(p,n,uv,f):
    keep,inv=np.unique(f,return_inverse=True);return p[keep],n[keep],uv[keep],inv.reshape(-1,3).astype('u4')
