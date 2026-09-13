"""Render the exported GLB bytes, including their actual animation channels.

Requires NumPy, Pillow and ModernGL (EGL/Mesa is supported). This is a real
mesh preview renderer, not an image-generation or concept-image compositor.
"""
from __future__ import annotations
import io,json,struct,math,argparse
from pathlib import Path
import numpy as np
from PIL import Image,ImageDraw,ImageFont
import moderngl

def norm(v):return np.array(v)/max(1e-10,np.linalg.norm(v))
def look_at(eye,target):
    eye=np.array(eye);z=norm(eye-target);x=norm(np.cross([0,1,0],z));y=np.cross(z,x)
    m=np.eye(4);m[:3,:3]=[x,y,z];m[:3,3]=-m[:3,:3]@eye;return m
def ortho(width,aspect,near=.1,far=100):
    h=width/aspect;m=np.eye(4);m[0,0]=2/width;m[1,1]=2/h;m[2,2]=-2/(far-near);m[2,3]=-(far+near)/(far-near);return m
def trs(t=(0,0,0),q=(0,0,0,1),s=(1,1,1)):
    x,y,z,w=q;m=np.eye(4)
    m[:3,:3]=[[1-2*(y*y+z*z),2*(x*y-z*w),2*(x*z+y*w)],
              [2*(x*y+z*w),1-2*(x*x+z*z),2*(y*z-x*w)],
              [2*(x*z-y*w),2*(y*z+x*w),1-2*(x*x+y*y)]]
    m[:3,:3]=m[:3,:3]@np.diag(s);m[:3,3]=t;return m

class GLB:
    def __init__(self,path):
        raw=Path(path).read_bytes();n=struct.unpack_from('<I',raw,12)[0];self.doc=json.loads(raw[20:20+n]);self.data=raw[28+n:]
    def accessor(self,i):
        a=self.doc['accessors'][i];v=self.doc['bufferViews'][a['bufferView']]
        typ={5126:'<f4',5125:'<u4',5123:'<u2',5121:'u1'}[a['componentType']]
        dim={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}[a['type']]
        return np.frombuffer(self.data,dtype=typ,count=a['count']*dim,offset=v.get('byteOffset',0)+a.get('byteOffset',0)).reshape(a['count'],dim)
    def transforms(self,clip=None,time=0):
        overrides={}
        if clip:
            ani=next((a for a in self.doc.get('animations',[]) if a['name']==clip),None)
            if ani:
                for c in ani['channels']:
                    s=ani['samplers'][c['sampler']];ts=self.accessor(s['input']).ravel();vals=self.accessor(s['output']);tm=time
                    if ani.get('extras',{}).get('loop'):tm%=float(ts[-1])
                    tm=float(np.clip(tm,ts[0],ts[-1]));i=min(len(ts)-2,max(0,int(np.searchsorted(ts,tm)-1)))
                    u=(tm-ts[i])/max(1e-8,ts[i+1]-ts[i]);v0,v1=vals[i].copy(),vals[i+1].copy();path=c['target']['path']
                    if path=='rotation' and np.dot(v0,v1)<0:v1=-v1
                    v=v0*(1-u)+v1*u
                    if path=='rotation':v/=max(1e-8,np.linalg.norm(v))
                    overrides[(c['target']['node'],path)]=v
        matrices={}
        def visit(i,parent):
            n=self.doc['nodes'][i]
            m=trs(overrides.get((i,'translation'),n.get('translation',[0,0,0])),overrides.get((i,'rotation'),n.get('rotation',[0,0,0,1])),overrides.get((i,'scale'),n.get('scale',[1,1,1])))
            matrices[i]=parent@m
            for child in n.get('children',[]):visit(child,matrices[i])
        for i in self.doc['scenes'][self.doc.get('scene',0)]['nodes']:visit(i,np.eye(4))
        return matrices

VERT='''#version 330
in vec4 in_color; out vec4 v_color; in vec3 in_pos; in vec3 in_normal; in vec2 in_uv;
uniform mat4 model, vp, light_vp;
out vec3 world_pos; out vec3 normal; out vec2 uv; out vec4 light_pos;
void main(){v_color=in_color;vec4 p=model*vec4(in_pos,1);world_pos=p.xyz;normal=transpose(inverse(mat3(model)))*in_normal;uv=in_uv;light_pos=light_vp*p;gl_Position=vp*p;}
'''
FRAG='''#version 330
in vec4 v_color;in vec3 world_pos;in vec3 normal;in vec2 uv;in vec4 light_pos;
uniform vec3 base_color, eye, light_dir;uniform float roughness;uniform int textured;
uniform sampler2D albedo;uniform sampler2D shadow_tex;
out vec4 color;
float shadow(){vec3 p=light_pos.xyz/light_pos.w*.5+.5;float s=0;
 if(p.x<0||p.x>1||p.y<0||p.y>1)return 1.;
 for(int x=-2;x<=2;x++)for(int y=-2;y<=2;y++){float d=texture(shadow_tex,p.xy+vec2(x,y)/2048.0).r;s+=p.z-.00032<d?1.:.0;}return s/25.;}
vec3 aces(vec3 x){return clamp((x*(2.51*x+.03))/(x*(2.43*x+.59)+.14),0,1);}
void main(){vec3 n=normalize(normal); if(!gl_FrontFacing)n=-n;vec3 v=normalize(eye-world_pos);vec3 h=normalize(light_dir+v);
 vec3 c=base_color*v_color.rgb;if(textured==1)c*=pow(texture(albedo,uv).rgb,vec3(2.2));
 float sh=shadow();float nd=max(dot(n,light_dir),0);float hemi=.5+.5*n.y;
 vec3 ambient=mix(vec3(.27,.23,.18),vec3(.67,.75,.79),hemi);
 float fill=max(dot(n,normalize(vec3(1,.4,1))),0);
 vec3 diffuse=c*(ambient*.60+vec3(1.13,1.02,.88)*nd*(.25+.75*sh)+fill*.14);
 float spec=pow(max(dot(n,h),0),mix(110.,10.,roughness))*(1.-roughness*.8)*.24*sh;
 float rim=pow(1.-max(dot(n,v),0),4.)*max(n.y,0)*.09;
 color=vec4(pow(aces(diffuse+spec+rim*c),vec3(1./2.2)),1);}
'''
SHADOW_V='''#version 330
in vec3 in_pos;uniform mat4 model, light_vp;void main(){gl_Position=light_vp*model*vec4(in_pos,1);}
'''
SHADOW_F='''#version 330
void main(){}
'''

class Renderer:
    def __init__(self,w,h):
        self.w,self.h=w,h;self.ctx=moderngl.create_standalone_context(backend='egl');c=self.ctx
        self.prog=c.program(vertex_shader=VERT,fragment_shader=FRAG);self.depth_prog=c.program(vertex_shader=SHADOW_V,fragment_shader=SHADOW_F)
        self.color=c.texture((w,h),4);self.depth=c.depth_renderbuffer((w,h));self.fbo=c.framebuffer([self.color],self.depth)
        self.shadow=c.depth_texture((2048,2048));self.shadow.compare_func='';self.shadow.repeat_x=False;self.shadow.repeat_y=False
        self.shadow_fbo=c.framebuffer(depth_attachment=self.shadow);self.white=c.texture((1,1),3,b'\xff\xff\xff')
        self.cache={}
    def load(self,path):
        path=str(path)
        if path in self.cache:return self.cache[path]
        glb=GLB(path);parts=[];texs={};c=self.ctx
        for i,img in enumerate(glb.doc.get('images',[])):
            v=glb.doc['bufferViews'][img['bufferView']];im=Image.open(io.BytesIO(glb.data[v.get('byteOffset',0):v.get('byteOffset',0)+v['byteLength']])).convert('RGB')
            t=c.texture(im.size,3,im.tobytes());t.build_mipmaps();texs[i]=t
        for ni,node in enumerate(glb.doc['nodes']):
            if 'mesh' not in node:continue
            for p in glb.doc['meshes'][node['mesh']]['primitives']:
                attrs=p['attributes'];pos=glb.accessor(attrs['POSITION']);normal=glb.accessor(attrs['NORMAL']);uv=glb.accessor(attrs['TEXCOORD_0']) if 'TEXCOORD_0' in attrs else np.zeros((len(pos),2))
                color=glb.accessor(attrs['COLOR_0']) if 'COLOR_0' in attrs else np.ones((len(pos),4))
                if color.shape[1]==3:color=np.c_[color,np.ones(len(pos))]
                vv=c.buffer(np.concatenate([pos,normal,uv,color],axis=1).astype('f4').tobytes());ii=c.buffer(glb.accessor(p['indices']).astype('u4').tobytes())
                vao=c.vertex_array(self.prog,[(vv,'3f 3f 2f 4f','in_pos','in_normal','in_uv','in_color')],ii)
                dvao=c.vertex_array(self.depth_prog,[(vv,'3f 36x','in_pos')],ii)
                mat=glb.doc['materials'][p['material']]['pbrMetallicRoughness'];texture=self.white
                mat.setdefault('baseColorFactor',[1,1,1,1]);mat.setdefault('roughnessFactor',1)
                if 'baseColorTexture' in mat:texture=texs[glb.doc['textures'][mat['baseColorTexture']['index']]['source']]
                parts.append((ni,vao,dvao,mat,texture))
        self.cache[path]=(glb,parts);return glb,parts
    def render(self,instances,eye=(3.7,2.3,5.8),target=(0,.75,-.35),width=3.8,ground=True):
        c=self.ctx;c.enable(moderngl.DEPTH_TEST);c.disable(moderngl.CULL_FACE)
        lv=look_at(np.array(target)+[-7,12,7],np.array(target));lp=ortho(max(6,width*1.2),1,.1,55)@lv
        vp=ortho(width,self.w/self.h,.1,100)@look_at(np.array(eye),np.array(target));commands=[]
        for path,model,clip,time in instances:
            glb,parts=self.load(path);tr=glb.transforms(clip,time)
            for ni,vao,dvao,mat,texture in parts:commands.append((model@tr[ni],vao,dvao,mat,texture))
        self.shadow_fbo.use();c.viewport=(0,0,2048,2048);self.shadow_fbo.clear(depth=1)
        self.depth_prog['light_vp'].write(lp.astype('f4').T.tobytes())
        for model,vao,dvao,mat,texture in commands:
            self.depth_prog['model'].write(model.astype('f4').T.tobytes());dvao.render()
        self.fbo.use();c.viewport=(0,0,self.w,self.h);self.fbo.clear(.529,.651,.671,1,depth=1)
        self.prog['vp'].write(vp.astype('f4').T.tobytes());self.prog['light_vp'].write(lp.astype('f4').T.tobytes());self.prog['eye'].value=tuple(eye)
        self.prog['light_dir'].value=tuple(norm([-7,12,7]));self.shadow.use(1);self.prog['shadow_tex'].value=1;self.prog['albedo'].value=0
        for model,vao,dvao,mat,texture in commands:
            self.prog['model'].write(model.astype('f4').T.tobytes());self.prog['base_color'].value=tuple(mat['baseColorFactor'][:3]);self.prog['roughness'].value=mat['roughnessFactor']
            self.prog['textured'].value=1 if 'baseColorTexture' in mat else 0;texture.use(0);vao.render()
        return Image.frombytes('RGBA',(self.w,self.h),self.fbo.read(components=4)).transpose(Image.Transpose.FLIP_TOP_BOTTOM).convert('RGB')


def main():
    parser=argparse.ArgumentParser(description='Render actual Godot-exported tree meshes; no concept-image compositing.')
    parser.add_argument('--export-dir',type=Path,required=True)
    parser.add_argument('--output-dir',type=Path,required=True)
    args=parser.parse_args();args.output_dir.mkdir(parents=True,exist_ok=True)
    path=args.export_dir/'tree_review.glb'
    shots=[('tree_model.jpg',(0,2.55,7),(0,1.43,0),3.65,(1400,1400)),
           ('tree_three_quarter.jpg',(-3.8,2.7,6),(0,1.4,0),4.,(1300,1100)),
           ('tree_detail.jpg',(-.35,2.8,5.3),(-.35,2.08,.12),1.7,(1200,1000))]
    for name,eye,target,width,size in shots:
        r=Renderer(size[0]*2,size[1]*2)
        frame=r.render([(path,np.eye(4),None,0)],eye=eye,target=target,width=width,ground=False)
        # Standard 2x supersampling for fine stems/veins; no retouching.
        frame.resize(size,Image.Resampling.LANCZOS).save(args.output_dir/name,quality=90,optimize=True)
        print(name,flush=True)
    stage=args.export_dir/'compact_village.glb'
    if stage.exists():
        cam=json.loads((args.export_dir/'camera.json').read_text());eye=np.array(cam['position']);pitch=math.radians(cam['pitch'])
        target=eye-np.array([0,math.sin(pitch),math.cos(pitch)])*60
        eye[0]=16;target[0]=16
        r=Renderer(2800,1268)
        frame=r.render([(stage,np.eye(4),None,0)],eye=tuple(eye),target=tuple(target),width=34,ground=False)
        frame.resize((1400,634),Image.Resampling.LANCZOS).save(args.output_dir/'village_trees.jpg',quality=90,optimize=True)
        print('village_trees.jpg',flush=True)
if __name__=='__main__':main()
