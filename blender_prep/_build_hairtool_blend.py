import bpy, os
import numpy as np
VDIR=r"C:\Users\Sam\AppData\Roaming\Blender Foundation\Blender\4.5\scripts\addons\CharMorph\data\characters\Vitruvian"
HAIRDIR=os.path.join(VDIR,"hairstyles")

def load_strands(npz, ps=1):
    z=np.load(os.path.join(HAIRDIR,npz),allow_pickle=True)
    cnt=z["cnt"].astype(int); data=z["data"].astype(float); out=[]; off=0
    for c in cnt:
        if c>=2:
            st=data[off:off+c]
            if ps>1 and c>3:
                idx=list(range(0,c,ps))
                if idx[-1]!=c-1: idx.append(c-1)
                st=st[idx]
            out.append(st)
        off+=c
    return out

def clip_face(strands):
    out=[]
    for st in strands:
        keep=[]
        for p in st:
            x,y,zz=float(p[0]),float(p[1]),float(p[2])
            if abs(x)<0.072 and y<-0.030 and 1.30<zz<1.665: break
            keep.append(p)
        if len(keep)>=2: out.append(np.array(keep))
    return out

# open the Vitruvian head file
bpy.ops.wm.open_mainfile(filepath=os.path.join(VDIR,"char.blend"))
# remove the stray Plane, keep cm_vitruvian + camera
for o in list(bpy.data.objects):
    if o.name=="Plane": bpy.data.objects.remove(o, do_unlink=True)
head=bpy.data.objects["cm_vitruvian"]
# strip particle systems (eyelashes/eyebrows) for a clean scalp surface
for m in list(head.modifiers):
    if m.type=='PARTICLE_SYSTEM': head.modifiers.remove(m)

strands=clip_face(load_strands("Eve.npz",1))
print("guide strands:", len(strands), "pts:", sum(len(s) for s in strands))
sizes=[len(s) for s in strands]
allpts=np.concatenate(strands).astype(np.float32)

# build NEW hair Curves datablock
cu=bpy.data.hair_curves.new("VitEveGuides")
ok=False
try:
    cu.add_curves(sizes)         # Blender 4.x
    ok=True
    print("add_curves OK")
except Exception as e:
    print("add_curves failed:", e)
if ok:
    cu.attributes['position'].data.foreach_set('vector', allpts.ravel())
    cu.update_tag()
obj=bpy.data.objects.new("VitEveGuides", cu)
bpy.context.scene.collection.objects.link(obj)
# attach to scalp surface for Hair Tool surface features
try:
    cu.surface=head
    uvname = head.data.uv_layers.active.name if head.data.uv_layers.active else (head.data.uv_layers[0].name if head.data.uv_layers else "")
    if uvname: cu.surface_uv_map=uvname
    print("surface set, uv:", uvname)
except Exception as e:
    print("surface set failed:", e)
print("curves count:", len(cu.curves) if hasattr(cu,'curves') else '?', "points:", len(cu.points) if hasattr(cu,'points') else '?')
out=r"H:/Work01/VitruvianGodot/blender_prep/vitruvian_hairtool.blend"
bpy.ops.wm.save_as_mainfile(filepath=out)
print("SAVED", out)
