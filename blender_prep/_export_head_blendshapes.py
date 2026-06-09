## Vitruvian head export v6 — adds CC0 ARKit-named blendshapes (procedurally
## sculpted from landmark regions) so the Godot emote driver can animate the face.
## Rebuilds the head exactly like export_vitruvian_head.py (eyes, lashes, scalp),
## then adds shape keys on the face mesh and re-exports vitruvian_head.glb WITH morphs.
##
## Run: blender -b char.blend --python _export_head_blendshapes.py -- [verify]
import bpy, bmesh, os, math, sys
import numpy as np
from mathutils import Vector
ARGS=sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else []
VERIFY="verify" in ARGS
OUT="H:/Work01/VitruvianGodot/godot_project"
VDIR=os.path.dirname(bpy.data.filepath)
EYEBALL_GLB="H:/Work01/VitruvianGodot/blender_prep/eyeball_src.glb"
RENDIR=r"H:/Work01/VitruvianGodot/blender_prep/hairtool_out/face_shapes"
LOG=r"H:/Work01/VitruvianGodot/blender_prep/hairtool_out/head_blendshapes.log"; _l=[]
def log(*a):
    s=" ".join(str(x) for x in a); print("HEAD:",s); _l.append(s)
def flush():
    os.makedirs(os.path.dirname(LOG),exist_ok=True); open(LOG,"w",encoding="utf-8").write("\n".join(_l))
NECK_CUT_Z=1.47   # head keeps z>1.47; the body neck is kept up to z<1.50, so head+body OVERLAP
                  # 1.47-1.50 — that overlap closes the thin dark gap ('hole') at the junction.
SOCK={"L":Vector((-0.0335,-0.0531,1.6344)),"R":Vector((0.0335,-0.0531,1.6344))}
EYE_R=0.0120; EYE_RECESS=0.0050; IRIS_FWD=Vector((0.0,-1.0,0.0))   # slightly smaller + deeper so the eyeball edge stops clipping through the lid skin
try:
    obj=bpy.data.objects["cm_vitruvian"]
    for m in list(obj.modifiers):
        if m.type=='PARTICLE_SYSTEM': obj.modifiers.remove(m)
    uvs=obj.data.uv_layers; udim="VitruvianUV_UDIM"; uvs.active=uvs[udim]
    for uv in uvs: uv.active_render=(uv.name==udim)
    me=obj.data
    ORIG_NV=len(me.vertices)                 # FACS morph deltas index into THIS topology
    me.materials.clear()
    # surface 0 = VitSkin (face+lips), surface 1 = VitMouth (tile 1006 interior: cavity,
    # gums, TONGUE, TEETH — textured by vit_mouth.png). Keeping the mouth interior in the
    # SAME mesh (just a 2nd material/surface) means the FACS jaw morphs move the lower
    # teeth+tongue WITH the jaw (a real open mouth), not a static cavity.
    for nm in ("VitSkin","VitMouth","VitDelete"): me.materials.append(bpy.data.materials.new(nm))
    SKIN,MOUTH,DEL=0,1,2
    uvl=me.uv_layers[udim].data
    for poly in me.polygons:
        u,v=uvl[poly.loop_indices[0]].uv
        tile=1001+int(math.floor(u))+10*int(math.floor(v))
        if tile==1006: poly.material_index=MOUTH
        elif tile in (1005,1007): poly.material_index=DEL   # eyes/lashes (procedural replacements)
        else: poly.material_index=SKIN
    bm=bmesh.new(); bm.from_mesh(me)
    oidx=bm.verts.layers.int.new("oidx")     # remember each vert's ORIGINAL index → FACS delta lookup
    bm.verts.ensure_lookup_table()
    for i,v in enumerate(bm.verts): v[oidx]=i
    bm.faces.ensure_lookup_table()
    bmesh.ops.delete(bm,geom=[f for f in bm.faces if f.material_index==DEL],context='FACES')
    bm.verts.ensure_lookup_table()
    bmesh.ops.delete(bm,geom=[v for v in bm.verts if not v.link_faces],context='VERTS')
    bm.verts.ensure_lookup_table()
    # cut the head at z=1.50 (jaw). The BODY now keeps its neck/collar skin (see the retarget
    # occlusion-delete), so the body provides the smooth neck into the collar and the head just
    # needs face+jaw. They meet at 1.50 with no overlap — no filler, no blocky ripped-off gap.
    bmesh.ops.delete(bm,geom=[v for v in bm.verts if v.co.z<NECK_CUT_Z],context='VERTS')
    bm.faces.ensure_lookup_table(); bm.normal_update()
    bm.to_mesh(me); bm.free(); me.update()
    scalp_obj=None; mouth_obj=None           # mouth is now surface 1, not a separate object
    # map new vert index -> original cm_vitruvian index (for FACS delta lookup)
    oattr=me.attributes["oidx"].data
    new_to_orig=[int(oattr[i].value) for i in range(len(me.vertices))]
    nsurf=len({p.material_index for p in me.polygons})
    log("head verts",len(me.vertices),"surfaces",nsurf,"(0=VitSkin,1=VitMouth)")

    # =============== shape keys = REAL Vitruvian FACS morphs ===============
    # The project ships a FACS rig: morphs/L3/*.npz are idx+delta on THIS exact topology.
    # Use those artist-authored shapes instead of hand-sculpted ones. Jaw_Lower /
    # Mouth_Large_Opened move the jaw AND the lower teeth+tongue (surface 1 = VitMouth)
    # for a real open mouth; Happy/Sad/Angry/.. are ready FACS emotions; aa/ow/p_b_m/..
    # are speech visemes. Deltas are looked up via new_to_orig (original cm_vitruvian idx).
    L3=r"C:/Users/Sam/AppData/Roaming/Blender Foundation/Blender/4.5/scripts/addons/CharMorph/data/characters/Vitruvian/morphs/L3"
    FACS=["Jaw_Lower","Mouth_Large_Opened","Lips_Up_Funnel",
          "Lips_Up_Corner_Wide_Left","Lips_Up_Corner_Wide_Right",
          "Happy","Sad","Angry","Scared","Disgusted","Thinking","Kiss","Smile_Lips_Closed",
          "Eyebrows_Raised_Left","Eyebrows_Raised_Right","Eyebrows_Frown_Left","Eyebrows_Frown_Right",
          "Eyes_Closed_Max","Eyes_Opened_Max_Left","Eyes_Opened_Max_Right","Eyes_Squint",
          "aa_02","ow_08","p_b_m_21","f_v_18","ey_eh_uh_04"]
    nv=len(me.vertices)
    base=np.array([me.vertices[i].co for i in range(nv)])
    obj.shape_key_add(name="Basis",from_mix=False)
    def add_facs(name):
        fp=os.path.join(L3,name+".npz")
        if not os.path.exists(fp): log("MISSING",name); return 0
        z=np.load(fp,allow_pickle=True)
        full=np.zeros((ORIG_NV,3)); full[z["idx"].astype(int)]=z["delta"].astype(float)
        kb=obj.shape_key_add(name=name,from_mix=False); nz=0
        for i in range(nv):
            o=full[new_to_orig[i]]
            if o[0] or o[1] or o[2]:
                kb.data[i].co=Vector(base[i])+Vector(o); nz+=1
        return nz
    for nm in FACS: log("FACS",nm,add_facs(nm))
    log("TOTAL shape keys:",len(obj.data.shape_keys.key_blocks))

    # =============== eyeballs + lashes (verbatim from head export) ===============
    bpy.ops.import_scene.gltf(filepath=EYEBALL_GLB)
    src={}
    for o in list(bpy.context.selected_objects):
        if o.type=='MESH' and o.name in ("eyeball","cornea"):
            bpy.ops.object.select_all(action='DESELECT')
            o.select_set(True); bpy.context.view_layer.objects.active=o
            bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
            src[o.name]=o
    eb=src["eyeball"]; ebme=eb.data; iris_axis=None; bestd=9.0
    uvl3=ebme.uv_layers.active.data
    for poly in ebme.polygons:
        for li in poly.loop_indices:
            uv=uvl3[li].uv; d=(uv.x-0.5)**2+(uv.y-0.5)**2
            if d<bestd: bestd=d; iris_axis=ebme.vertices[ebme.loops[li].vertex_index].co.normalized()
    rot_q=iris_axis.rotation_difference(IRIS_FWD)
    eye_mat_obj={"eyeball":bpy.data.materials.new("VitEyeball"),"cornea":bpy.data.materials.new("VitCornea")}
    eye_objs=[]
    for side,center in SOCK.items():
        for nm,so in src.items():
            d=so.copy(); d.data=so.data.copy(); bpy.context.scene.collection.objects.link(d)
            d.name="Eye_%s_%s"%(side,nm); d.rotation_mode='QUATERNION'; d.rotation_quaternion=rot_q
            d.scale=(EYE_R,EYE_R,EYE_R); d.location=center+Vector((0.0,EYE_RECESS,0.0))
            d.data.materials.clear(); d.data.materials.append(eye_mat_obj[nm]); eye_objs.append(d)
    for so in src.values(): bpy.data.objects.remove(so,do_unlink=True)
    # lashes
    NCOLS=4; lash_mat=bpy.data.materials.new("VitLash")
    def _emit_lash(bm,uvl,root,lash_dir,side_vec,length,w_root,w_tip,curl,col):
        u0=col/NCOLS+0.012; u1=(col+1)/NCOLS-0.012; seg=4; prev=None
        for j in range(seg+1):
            f=j/seg; w=w_root*(1-f)+w_tip*f
            p=root+lash_dir*(length*f)+Vector((0,0,1))*(curl*f*f)
            A=bm.verts.new(p+side_vec*w); B=bm.verts.new(p-side_vec*w); vrow=1.0-f
            if prev is not None:
                face=bm.faces.new((prev[0],prev[1],B,A)); pv=1.0-(j-1)/seg
                for loop in face.loops:
                    vert=loop.vert
                    uu=u0 if (vert==prev[0] or vert==A) else u1
                    vv=pv if (vert==prev[0] or vert==prev[1]) else vrow
                    loop[uvl].uv=(uu,vv)
            prev=(A,B)
    def build_lashes(center,R,name):
        bm=bmesh.new(); uvl=bm.loops.layers.uv.new("UVMap")
        up=Vector((0,0,1)); right=Vector((1,0,0)); fwd=Vector((0,-1,0))
        for k in range(7):
            a=math.radians(-58+116*k/6); rim_dir=(math.cos(a)*up+math.sin(a)*right).normalized()
            root=center+rim_dir*(R*0.85)+fwd*(R*1.15)
            lash_dir=(rim_dir*0.45+fwd*0.7+up*0.85).normalized()
            side=lash_dir.cross(fwd); side=side.normalized() if side.length>1e-6 else lash_dir.cross(right).normalized()
            _emit_lash(bm,uvl,root,lash_dir,side,0.0085,0.0013,0.00015,0.0028,k%NCOLS)
        for k in range(3):
            a=math.radians(150+60*k/2); rim_dir=(math.cos(a)*up+math.sin(a)*right).normalized()
            root=center+rim_dir*(R*0.85)+fwd*(R*1.15)
            lash_dir=(rim_dir*0.5+fwd*0.7-up*0.4).normalized()
            side=lash_dir.cross(fwd); side=side.normalized() if side.length>1e-6 else lash_dir.cross(right).normalized()
            _emit_lash(bm,uvl,root,lash_dir,side,0.0042,0.0008,0.00012,-0.0008,k%NCOLS)
        m=bpy.data.meshes.new(name); bm.normal_update(); bm.to_mesh(m); bm.free()
        m.materials.append(lash_mat); o=bpy.data.objects.new(name,m); bpy.context.scene.collection.objects.link(o); return o
    # Eyelashes DISABLED — the procedural lash cards read as freaky dark scratch-marks
    # hanging over the eye (user feedback). A clean eye with no lashes looks far better
    # than bad card lashes. (Set LASHES=1 to re-enable the old build for experimentation.)
    if os.environ.get("LASHES"):
        for side_name,center in SOCK.items():
            eye_objs.append(build_lashes(center+Vector((0.0,EYE_RECESS,0.0)),EYE_R,"Lash_%s"%side_name))

    # ---- procedural EYELIDS (skin caps over the eyeball top/bottom) ----
    # Fixes the "doll-eye" (bare sphere in socket) by giving the eye an almond shape,
    # and the UPPER lid is a separate object so Godot can rotate it DOWN to blink.
    # Sphere-patch around the eye centre; origin set AT the centre so a rotation in
    # Godot sweeps the lid around the eyeball.
    lid_mat = bpy.data.materials.new("VitSkin")   # name-prefix match → skin shader in Godot
    def build_lid(center, R, name, upper=True):
        bm=bmesh.new()
        fwd=Vector((0,-1,0)); up=Vector((0,0,1)); right=Vector((1,0,0))
        Rlid=R*1.12
        if upper:
            el0,el1=math.radians(6),math.radians(82); azmax=math.radians(56)
        else:
            el0,el1=math.radians(-4),math.radians(-46); azmax=math.radians(50)
        NAZ,NEL=12,4; vd={}
        for ie in range(NEL+1):
            el=el0+(el1-el0)*ie/NEL
            for ia in range(NAZ+1):
                az=-azmax+2*azmax*ia/NAZ
                faz=(math.sin(az)*right+math.cos(az)*fwd)
                d=(faz*math.cos(el)+up*math.sin(el)).normalized()
                vd[(ia,ie)]=bm.verts.new(center+d*Rlid)
        for ie in range(NEL):
            for ia in range(NAZ):
                bm.faces.new((vd[(ia,ie)],vd[(ia+1,ie)],vd[(ia+1,ie+1)],vd[(ia,ie+1)]))
        m=bpy.data.meshes.new(name); bm.normal_update(); bm.to_mesh(m); bm.free()
        m.materials.append(lid_mat)
        o=bpy.data.objects.new(name,m); bpy.context.scene.collection.objects.link(o)
        # move origin to the eye centre so a Godot rotation sweeps around the eyeball
        for v in o.data.vertices: v.co -= center
        o.location = center
        return o
    # NOTE: procedural lid caps occluded the eyeballs in Godot (they sit just in front
    # of the iris); disabled. Eyes are visible (open) + alive via catchlight + saccade.
    if os.environ.get("EYELIDS"):
        for side_name,center in SOCK.items():
            c = center + Vector((0.0, EYE_RECESS, 0.0))
            eye_objs.append(build_lid(c, EYE_R, "LidUp_%s"%side_name, upper=True))
            eye_objs.append(build_lid(c, EYE_R, "LidLo_%s"%side_name, upper=False))
        log("added eyelids")

    # ---- EYESHADOW patch: a thin shell floating just over the UPPER-LID skin (elevation
    # above the lash line up toward the crease). Godot gives it a tinted, mostly-transparent
    # material driven by a look-dev slider (opacity 0 = none). Sits a touch proud of the
    # skin so it reads as makeup on the lid. ----
    shadow_mat = bpy.data.materials.new("VitEyeshadow")
    def build_eyeshadow(center, R, name):
        bm=bmesh.new(); uvl=bm.loops.layers.uv.new("UVMap")
        fwd=Vector((0,-1,0)); up=Vector((0,0,1)); right=Vector((1,0,0))
        Rsh=R*1.42                                   # float outside the lid skin
        el0,el1=math.radians(10),math.radians(74); azmax=math.radians(62)
        NAZ,NEL=14,5; vd={}
        for ie in range(NEL+1):
            el=el0+(el1-el0)*ie/NEL
            for ia in range(NAZ+1):
                az=-azmax+2*azmax*ia/NAZ
                faz=(math.sin(az)*right+math.cos(az)*fwd)
                d=(faz*math.cos(el)+up*math.sin(el)).normalized()
                v=bm.verts.new(center+d*Rsh); vd[(ia,ie)]=v
        for ie in range(NEL):
            for ia in range(NAZ):
                f=bm.faces.new((vd[(ia,ie)],vd[(ia+1,ie)],vd[(ia+1,ie+1)],vd[(ia,ie+1)]))
                # V across elevation: 1 at lash line (dense) -> 0 toward crease (fades)
                for loop in f.loops:
                    p=loop.vert.co
                    loop[uvl].uv=(0.5,0.0)
        m=bpy.data.meshes.new(name); bm.normal_update(); bm.to_mesh(m); bm.free()
        m.materials.append(shadow_mat)
        o=bpy.data.objects.new(name,m); bpy.context.scene.collection.objects.link(o)
        return o
    for side_name,center in SOCK.items():
        eye_objs.append(build_eyeshadow(center+Vector((0.0,EYE_RECESS,0.0)),EYE_R,"Eyeshadow_%s"%side_name))
    log("added eyeshadow patches")

    # (Neck-base filler REMOVED — the body now keeps its real neck/collar skin, so no
    # crude filler cone is needed. That filler read as flat skin tabs/wings; gone now.)

    if VERIFY:
        os.makedirs(RENDIR,exist_ok=True)
        scn=bpy.context.scene; scn.render.engine='BLENDER_WORKBENCH'
        scn.render.resolution_x=420; scn.render.resolution_y=520
        cam=bpy.data.objects.get("Camera")
        if cam is None:
            cd=bpy.data.cameras.new("Camera"); cam=bpy.data.objects.new("Camera",cd); scn.collection.objects.link(cam)
        cam.location=(0.0,-0.42,1.62); cam.rotation_euler=(math.pi/2,0,0); cam.data.lens=45; scn.camera=cam
        kb=obj.data.shape_keys.key_blocks
        def setk(d):
            for k in kb: k.value=0.0
            for n,val in d.items():
                if n in kb: kb[n].value=val
        EXPR={
            "neutral":{},
            "blink":{"Eyes_Closed_Max":1},
            "jawOpen":{"Mouth_Large_Opened":1},
            "happy":{"Happy":1},
            "surprise":{"Mouth_Large_Opened":0.5,"Eyebrows_Raised_Left":1,"Eyebrows_Raised_Right":1,"Eyes_Opened_Max_Left":0.9,"Eyes_Opened_Max_Right":0.9},
            "sad":{"Sad":1},
        }
        for nm,d in EXPR.items():
            setk(d); scn.render.filepath=os.path.join(RENDIR,f"expr_{nm}.png"); bpy.ops.render.render(write_still=True); log("rendered",nm)
        setk({})

    # export head + eyes WITH morph targets
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    if scalp_obj: scalp_obj.select_set(True)
    if mouth_obj: mouth_obj.select_set(True)
    for d in eye_objs: d.select_set(True)
    bpy.context.view_layer.objects.active=obj
    glb=os.path.join(OUT,"vitruvian_head.glb")
    bpy.ops.export_scene.gltf(filepath=glb,export_format='GLB',use_selection=True,
        export_apply=False, export_morph=True, export_morph_normal=True,
        export_yup=True,export_materials='EXPORT',export_normals=True,export_tangents=True,export_texcoords=True)
    log("wrote",glb,"size",os.path.getsize(glb))
    flush()
except Exception as e:
    import traceback; log("FAIL",repr(e)); traceback.print_exc(); flush()
finally:
    try: bpy.ops.wm.quit_blender()
    except: pass
