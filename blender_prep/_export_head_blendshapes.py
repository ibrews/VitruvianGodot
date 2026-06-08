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
NECK_CUT_Z=1.49
SOCK={"L":Vector((-0.0335,-0.0531,1.6344)),"R":Vector((0.0335,-0.0531,1.6344))}
EYE_R=0.0125; EYE_RECESS=0.0025; IRIS_FWD=Vector((0.0,-1.0,0.0))   # forward so eyeballs sit in the socket opening (not buried behind skin)
try:
    obj=bpy.data.objects["cm_vitruvian"]
    for m in list(obj.modifiers):
        if m.type=='PARTICLE_SYSTEM': obj.modifiers.remove(m)
    uvs=obj.data.uv_layers; udim="VitruvianUV_UDIM"; uvs.active=uvs[udim]
    for uv in uvs: uv.active_render=(uv.name==udim)
    me=obj.data
    me.materials.clear()
    for nm in ("VitSkin","VitMouth","VitScalp","VitDelete"): me.materials.append(bpy.data.materials.new(nm))
    SKIN,MOUTH,SCALP,DEL=0,1,2,3
    uvl=me.uv_layers[udim].data
    for poly in me.polygons:
        u,v=uvl[poly.loop_indices[0]].uv
        tile=1001+int(math.floor(u))+10*int(math.floor(v))
        if tile==1001: poly.material_index=SKIN
        elif tile==1006: poly.material_index=MOUTH
        elif tile in (1005,1007): poly.material_index=DEL
        else: poly.material_index=SKIN
    bm=bmesh.new(); bm.from_mesh(me); bm.faces.ensure_lookup_table()
    bmesh.ops.delete(bm,geom=[f for f in bm.faces if f.material_index==DEL],context='FACES')
    bm.verts.ensure_lookup_table()
    bmesh.ops.delete(bm,geom=[v for v in bm.verts if not v.link_faces],context='VERTS')
    bm.verts.ensure_lookup_table()
    bmesh.ops.delete(bm,geom=[v for v in bm.verts if v.co.z<NECK_CUT_Z],context='VERTS')
    bm.faces.ensure_lookup_table(); bm.normal_update()
    # (Scalp dup REMOVED: with single-surface/no-separation it merges to skin so it no
    # longer darkens the crown, and its z>=1.625 region OVERLAPPED the eye sockets,
    # offsetting skin forward over the eyeballs → eyes vanished. The hair backing
    # handles the dark crown instead.)
    bm.to_mesh(me); bm.free(); me.update()
    log("head verts",len(me.vertices))

    # Godot 4.6 does NOT render blend shapes on MULTI-surface meshes, AND
    # bpy.ops.mesh.separate CORRUPTS the morph mesh for Godot's vertex pipeline
    # (verts silently don't deform). So the morph mesh must be a SINGLE surface built
    # WITHOUT any separation: merge mouth AND scalp into the skin material. The scalp
    # ends up skin-coloured but it's under the hair (the hair backing handles the crown).
    for p in me.polygons:
        if p.material_index in (MOUTH, SCALP):
            p.material_index = SKIN
    scalp_obj = None
    me.materials.clear(); me.materials.append(bpy.data.materials.new("VitSkin"))
    for p in me.polygons: p.material_index = 0
    me.update()
    log("morph mesh: SINGLE surface, no separation (scalp merged into skin)")

    # mouth verts from UV tile 1006 (post-rebuild indices)
    uvl2=me.uv_layers[udim].data
    mouth_vidx=set()
    for poly in me.polygons:
        u,v=uvl2[poly.loop_indices[0]].uv
        tile=1001+int(math.floor(u))+10*int(math.floor(v))
        if tile==1006:
            for vi in poly.vertices: mouth_vidx.add(vi)

    # =============== shape keys ===============
    obj.shape_key_add(name="Basis",from_mix=False)
    nv=len(me.vertices)
    base=np.array([me.vertices[i].co for i in range(nv)])
    def ss(e0,e1,x):
        t=max(0.0,min(1.0,(x-e0)/(e1-e0) if e1!=e0 else 0.0)); return t*t*(3-2*t)
    def add_key(name,off):
        kb=obj.shape_key_add(name=name,from_mix=False)
        nz=0
        for i in range(nv):
            o=off[i]
            if o[0] or o[1] or o[2]:
                kb.data[i].co=Vector(base[i])+Vector(o); nz+=1
        return nz
    def zeros(): return np.zeros((nv,3))

    # mouth geometry first (needed by jawOpen so it can hinge at the lip line)
    mc=base[sorted(mouth_vidx)] if mouth_vidx else base
    cornerL=np.array([mc[:,0].min(),mc[:,1].mean(),mc[:,2].mean()])  # char-left = -X
    cornerR=np.array([mc[:,0].max(),mc[:,1].mean(),mc[:,2].mean()])
    mcz=mc[:,2].mean()        # the lip-line height
    log("mouth line z (mcz)=",round(float(mcz),4)," mouth verts=",len(mouth_vidx))

    # jawOpen: hinge the lower jaw at the mandible joint (back, near ear height) and
    # ramp the weight in BELOW the lip line. The lower lip + chin + jaw swing DOWN and
    # BACK while the upper lip / nose stay put => the lips actually PART (a real opening)
    # instead of the whole chin just getting longer. Then the inner-lip rim is recessed
    # so the gap self-shadows and reads as a dark mouth, not skin-on-skin.
    JPY,JPZ=0.055,1.602; A=math.radians(34.0)          # jaw pivot (behind, ear height)
    off=zeros()
    for i in range(nv):
        z=base[i][2]
        w=ss(mcz+0.006, mcz-0.014, z)                  # 0 above lip line, 1 below it
        if w<=0: continue
        dy=base[i][1]-JPY; dz=base[i][2]-JPZ; a=A*w
        ca,sa=math.cos(a),math.sin(a)
        off[i]=[0.0,(JPY+ca*dy-sa*dz)-base[i][1],(JPZ+sa*dy+ca*dz)-base[i][2]]
    # recess the inner-lip rim (upper + lower) into the head so the open gap is shadowed
    for vi in sorted(mouth_vidx):
        dzc=abs(base[vi][2]-mcz)
        if dzc<0.011:
            rw=1.0-dzc/0.011
            off[vi][1]+=0.012*rw                       # +Y = backward into the head
    log("jawOpen",add_key("jawOpen",off))
    def corner_shape(corner, dx, dy, dz, rad, only_below=False, only_mouth=True):
        off=zeros()
        idxs=sorted(mouth_vidx) if only_mouth else range(nv)
        for vi in idxs:
            if only_below and base[vi][2]>mcz: continue
            d=np.linalg.norm(base[vi]-corner)
            w=max(0.0,1.0-d/rad)
            if w>0: off[vi]=[dx*w,dy*w,dz*w]
        return off
    # stronger so a closed-mouth smile/frown reads clearly (corner up&out / down&in)
    log("mouthSmileLeft",  add_key("mouthSmileLeft",  corner_shape(cornerL,-0.015,0.010,0.032,0.058)))
    log("mouthSmileRight", add_key("mouthSmileRight", corner_shape(cornerR, 0.015,0.010,0.032,0.058)))
    log("mouthFrownLeft",  add_key("mouthFrownLeft",  corner_shape(cornerL,-0.008,0.002,-0.028,0.054)))
    log("mouthFrownRight", add_key("mouthFrownRight", corner_shape(cornerR, 0.008,0.002,-0.028,0.054)))
    log("mouthLowerDownLeft",  add_key("mouthLowerDownLeft",  corner_shape(np.array([-0.012,mc[:,1].mean(),mcz]),0,0,-0.013,0.030,only_below=True)))
    log("mouthLowerDownRight", add_key("mouthLowerDownRight", corner_shape(np.array([ 0.012,mc[:,1].mean(),mcz]),0,0,-0.013,0.030,only_below=True)))
    # mouthFunnel: lips forward + narrow
    off=zeros()
    for vi in sorted(mouth_vidx):
        d=np.linalg.norm(base[vi]-np.array([0,mc[:,1].mean(),mcz]))
        w=max(0.0,1.0-d/0.030)
        if w>0: off[vi]=[(-base[vi][0]*0.25)*w,-0.006*w,0.0]
    log("mouthFunnel",add_key("mouthFunnel",off))

    # brows
    def brow_verts():
        out=[]
        for i in range(nv):
            x,y,z=base[i]
            if y<-0.015 and 1.652<z<1.705: out.append(i)
        return out
    bverts=brow_verts()
    def brow_shape(xmin,xmax,dz):
        off=zeros()
        for i in bverts:
            x,y,z=base[i]
            if xmin<=abs(x)<=xmax:
                w=ss(1.652,1.668,z)*ss(1.705,1.668,z)
                off[i]=[0,0,dz*w]
        return off
    log("browInnerUp",     add_key("browInnerUp",     brow_shape(0.0,0.030, 0.030)))
    log("browOuterUpLeft", add_key("browOuterUpLeft",  brow_shape(0.030,0.065,0.020) if True else zeros()))
    # split outer up by side
    def brow_side(side, dz):
        off=zeros()
        for i in bverts:
            x,y,z=base[i]
            if (x<0)==(side=="L") and 0.028<abs(x)<0.066:
                w=ss(1.652,1.668,z)*ss(1.705,1.668,z); off[i]=[0,0,dz*w]
        return off
    log("browOuterUpLeft",  add_key("browOuterUpLeft", brow_side("L",0.024)))
    log("browOuterUpRight", add_key("browOuterUpRight",brow_side("R",0.024)))
    def brow_down_side(side):
        off=zeros()
        for i in bverts:
            x,y,z=base[i]
            if (x<0)==(side=="L"):
                w=ss(1.652,1.666,z); off[i]=[(0.002 if side=="L" else -0.002)*w,0,-0.011*w]
        return off
    log("browDownLeft",  add_key("browDownLeft", brow_down_side("L")))
    log("browDownRight", add_key("browDownRight",brow_down_side("R")))

    # cheeks + eyes (per socket)
    def eye_region(center, rad=0.019):
        return [i for i in range(nv) if (Vector(base[i])-center).length<rad]
    for side,C in (("Left",SOCK["L"]),("Right",SOCK["R"])):
        reg=eye_region(C)
        # eyeBlink: upper-lid verts down to just below center + forward
        offB=zeros(); offW=zeros()
        MIDZ=C.z-0.002                            # where the closed lids meet
        for i in reg:
            x,y,z=base[i]
            if z>C.z-0.001:                        # upper lid → sweep down across the eye
                w=ss(C.z-0.001,C.z+0.013,z)
                offB[i]=[0,-0.004*w,(MIDZ-z)*w]
                offW[i]=[0,0,0.005*w]              # eyeWide = lift upper lid
            elif z<C.z-0.002:                      # lower lid → rise to meet
                w=ss(C.z-0.002,C.z-0.013,z)
                offB[i]=[0,-0.003*w,(MIDZ-z)*0.6*w]
        log("eyeBlink"+side,add_key("eyeBlink"+side,offB))
        log("eyeWide"+side, add_key("eyeWide"+side, offW))
        # cheekSquint: cheek below eye lifts toward eye
        offC=zeros()
        for i in range(nv):
            x,y,z=base[i]
            if y<-0.02 and 1.585<z<1.625 and (0.025<abs(x)<0.070) and ((x<0)==(side=="Left")):
                w=ss(1.585,1.610,z)*ss(1.625,1.610,z)
                offC[i]=[0,0,0.006*w]
        log("cheekSquint"+side,add_key("cheekSquint"+side,offC))

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
            "blink":{"eyeBlinkLeft":1,"eyeBlinkRight":1},
            "jawOpen":{"jawOpen":1},
            "smile":{"mouthSmileLeft":1,"mouthSmileRight":1,"cheekSquintLeft":0.5,"cheekSquintRight":0.5},
            "surprise":{"jawOpen":0.6,"browInnerUp":1,"browOuterUpLeft":0.8,"browOuterUpRight":0.8,"eyeWideLeft":1,"eyeWideRight":1},
            "frown":{"mouthFrownLeft":0.9,"mouthFrownRight":0.9,"browDownLeft":0.8,"browDownRight":0.8,"mouthLowerDownLeft":0.3,"mouthLowerDownRight":0.3},
        }
        for nm,d in EXPR.items():
            setk(d); scn.render.filepath=os.path.join(RENDIR,f"expr_{nm}.png"); bpy.ops.render.render(write_still=True); log("rendered",nm)
        setk({})

    # export head + eyes WITH morph targets
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    if scalp_obj: scalp_obj.select_set(True)
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
