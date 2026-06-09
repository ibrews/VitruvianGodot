## Probe + test-sculpt facial blendshapes on the CC0 Vitruvian face mesh.
## Rebuilds the head face mesh (matching export_vitruvian_head.py region logic),
## detects landmark regions from the eye sockets + mouth UV tile, makes a few TEST
## shape keys (jawOpen, mouthSmileL/R, browInnerUp), and renders neutral vs each
## so we can verify region detection + deform quality before building the full set.
import bpy, bmesh, os, math, sys, traceback
import numpy as np
from mathutils import Vector
LOG=r"H:/Work01/VitruvianGodot/blender_prep/hairtool_out/face_probe.log"; _l=[]
RENDIR=r"H:/Work01/VitruvianGodot/blender_prep/hairtool_out/face_probe"
def log(*a):
    s=" ".join(str(x) for x in a); print("FACE:",s); _l.append(s)
def flush():
    os.makedirs(os.path.dirname(LOG),exist_ok=True)
    open(LOG,"w",encoding="utf-8").write("\n".join(_l))
try:
    SOCK={"L":Vector((-0.0335,-0.0531,1.6344)),"R":Vector((0.0335,-0.0531,1.6344))}
    EYE_Z=1.6344; NECK_CUT_Z=1.49
    obj=bpy.data.objects["cm_vitruvian"]
    for m in list(obj.modifiers):
        if m.type=='PARTICLE_SYSTEM': obj.modifiers.remove(m)
    uvs=obj.data.uv_layers; udim="VitruvianUV_UDIM"; uvs.active=uvs[udim]
    me=obj.data
    # tile -> region (same as head export): 1006 mouth, 1005/1007 eyes(del)
    uvl=me.uv_layers[udim].data
    mouth_polys=set()
    del_polys=set()
    for poly in me.polygons:
        u,v=uvl[poly.loop_indices[0]].uv
        tile=1001+int(math.floor(u))+10*int(math.floor(v))
        if tile==1006: mouth_polys.add(poly.index)
        elif tile in (1005,1007): del_polys.add(poly.index)
    log("mouth polys",len(mouth_polys),"eye(del) polys",len(del_polys))
    # delete eye faces + loose + below neck (match export)
    bm=bmesh.new(); bm.from_mesh(me); bm.faces.ensure_lookup_table()
    bmesh.ops.delete(bm,geom=[f for f in bm.faces if f.index in del_polys],context='FACES')
    bm.verts.ensure_lookup_table()
    bmesh.ops.delete(bm,geom=[v for v in bm.verts if not v.link_faces],context='VERTS')
    bm.verts.ensure_lookup_table()
    bmesh.ops.delete(bm,geom=[v for v in bm.verts if v.co.z<NECK_CUT_Z],context='VERTS')
    bm.to_mesh(me); bm.free(); me.update()
    log("head verts",len(me.vertices))

    co=np.array([v.co for v in me.vertices])
    log("bounds x",round(co[:,0].min(),3),round(co[:,0].max(),3),
        "y",round(co[:,1].min(),3),round(co[:,1].max(),3),
        "z",round(co[:,2].min(),3),round(co[:,2].max(),3))
    # mouth verts (from polys, re-find by proximity since indices changed after delete)
    # recompute mouth region by UV after rebuild
    uvl2=me.uv_layers[udim].data
    mouth_vidx=set()
    for poly in me.polygons:
        u,v=uvl2[poly.loop_indices[0]].uv
        tile=1001+int(math.floor(u))+10*int(math.floor(v))
        if tile==1006:
            for vi in poly.vertices: mouth_vidx.add(vi)
    mouth_vidx=sorted(mouth_vidx)
    if mouth_vidx:
        mc=co[mouth_vidx]
        log("mouth verts",len(mouth_vidx),"x",round(mc[:,0].min(),3),round(mc[:,0].max(),3),
            "y",round(mc[:,1].min(),3),round(mc[:,1].max(),3),"z",round(mc[:,2].min(),3),round(mc[:,2].max(),3))
        mouth_ctr=mc.mean(0); log("mouth center",tuple(round(x,3) for x in mouth_ctr))

    # ----- TEST shape keys -----
    obj.shape_key_add(name="Basis", from_mix=False)
    basis=obj.data.shape_keys.key_blocks["Basis"]
    nv=len(me.vertices)
    base=np.array([basis.data[i].co for i in range(nv)])

    def add_key(name, offsets):
        kb=obj.shape_key_add(name=name, from_mix=False)
        for i in range(nv):
            kb.data[i].co = base[i] + Vector(offsets[i])
        return kb

    def smoothstep(e0,e1,x):
        t=np.clip((x-e0)/(e1-e0+1e-9),0,1); return t*t*(3-2*t)

    # jawOpen: rotate lower-face verts down about a left-right hinge at jaw height.
    HINGE_Z=1.605; HINGE_Y=-0.005
    ang=math.radians(14.0)
    off=np.zeros((nv,3))
    for i in range(nv):
        z=base[i][2]
        w=smoothstep(HINGE_Z,1.55,z)   # 0 above hinge, 1 well below
        if w<=0: continue
        # rotate point about X axis through (any x, HINGE_Y, HINGE_Z)
        dy=base[i][1]-HINGE_Y; dz=base[i][2]-HINGE_Z
        ca,sa=math.cos(ang*w),math.sin(ang*w)
        ndy=ca*dy - sa*dz; ndz=sa*dy + ca*dz
        off[i]=[0.0, (HINGE_Y+ndy)-base[i][1], (HINGE_Z+ndz)-base[i][2]]
    add_key("jawOpen", off)

    # mouthSmile L/R: pull mouth-corner verts up+out, falloff by dist from corner.
    if mouth_vidx:
        mc=co[mouth_vidx]
        for side,sx in (("Left",1.0),("Right",-1.0)):  # ARKit Left = character's left = +X? we'll verify in render
            corner_x = mc[:,0].max() if sx>0 else mc[:,0].min()
            corner = np.array([corner_x, mc[:,1].mean(), mc[:,2].mean()])
            off=np.zeros((nv,3))
            for vi in mouth_vidx:
                d=np.linalg.norm(base[vi]-corner)
                w=max(0.0,1.0-d/0.045)
                off[vi]=[sx*0.004*w, 0.002*w, 0.010*w]  # out, back(+y), up(+z)
            add_key("mouthSmile"+side, off)

    # browInnerUp: inner brow verts (above eyes, near center x) move up.
    off=np.zeros((nv,3))
    for i in range(nv):
        x,y,z=base[i]
        if y<-0.02 and 1.655<z<1.695 and abs(x)<0.045:
            w=smoothstep(0.045,0.0,abs(x))*smoothstep(1.655,1.675,z)*smoothstep(1.695,1.675,z)
            off[i]=[0,0,0.010*w]
    add_key("browInnerUp", off)

    log("shape keys:", [k.name for k in obj.data.shape_keys.key_blocks])

    # ----- render neutral + each key at full -----
    os.makedirs(RENDIR,exist_ok=True)
    scn=bpy.context.scene; scn.render.engine='BLENDER_WORKBENCH'
    scn.render.resolution_x=420; scn.render.resolution_y=520
    cam=bpy.data.objects.get("Camera")
    if cam is None:
        cd=bpy.data.cameras.new("Camera"); cam=bpy.data.objects.new("Camera",cd); scn.collection.objects.link(cam)
    cam.location=(0.0,-0.42,1.62); cam.rotation_euler=(math.pi/2,0,0); cam.data.lens=45; scn.camera=cam
    # hide everything except the face obj
    for o in bpy.data.objects:
        if o.type=='MESH' and o is not obj: o.hide_render=True
    keys=[k for k in obj.data.shape_keys.key_blocks if k.name!="Basis"]
    for k in obj.data.shape_keys.key_blocks: k.value=0.0
    scn.render.filepath=os.path.join(RENDIR,"face_neutral.png"); bpy.ops.render.render(write_still=True)
    for k in keys:
        k.value=1.0
        scn.render.filepath=os.path.join(RENDIR,f"face_{k.name}.png"); bpy.ops.render.render(write_still=True)
        k.value=0.0
        log("rendered",k.name)
    flush()
except Exception as e:
    log("FAIL",repr(e)); traceback.print_exc(); flush()
finally:
    try: bpy.ops.wm.quit_blender()
    except: pass
