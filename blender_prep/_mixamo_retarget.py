## Retarget 6 Mixamo FBX clips onto mixamo_vitruvian (A-pose CharMorph rig) via
## world-space constraint bake (handles A-pose vs T-pose rest mismatch), then either
## render verification montages (MODE=verify) or rebuild the animated body GLB
## (MODE=export) matching _animated_body_export.py conventions.
##
## Usage: blender -b vitruvian_rigged.blend --python _mixamo_retarget.py -- <verify|export>
import bpy, bmesh, os, math, sys, traceback
from mathutils import Matrix, Vector, Euler

ARGS = sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else []
MODE = ARGS[0] if ARGS else "verify"
ROOT = r"H:/Work01/VitruvianGodot"
MX_DIR = os.path.join(ROOT, "blender_prep", "mixamo")
OUTDIR = os.path.join(ROOT, "blender_prep", "hairtool_out")
RENDIR = os.path.join(OUTDIR, "mixamo_verify")
LOG = os.path.join(OUTDIR, "mixamo_retarget.log"); _l=[]
def log(*a):
    s=" ".join(str(x) for x in a); print("RTG:",s); _l.append(s)
def flush():
    os.makedirs(OUTDIR, exist_ok=True)
    open(LOG,"w",encoding="utf-8").write("\n".join(_l))

# clip file -> action name (cinematic timeline expects Idle/Sway/Walk/Turn/Wave)
CLIPS = [
    ("Breathing Idle.fbx", "Idle"),
    ("Standing Idle.fbx",  "Sway"),
    ("Walking.fbx",        "Walk"),
    ("Looking Around.fbx", "Turn"),
    ("Waving.fbx",         "Wave"),
    ("Happy Idle.fbx",     "HappyIdle"),
]

try:
    arm = bpy.data.objects["mixamo_vitruvian"]
    body = bpy.data.objects["cm_vitruvian"]

    # bones that exist in VIT armature (we map the intersection with each MX action)
    vit_bones = set(b.name for b in arm.data.bones)
    log("MODE", MODE, "VIT bones", len(vit_bones))

    # VIT rest hip world Z (for source height match)
    arm_eval = arm
    hip = arm.data.bones["mixamorig:Hips"]
    vit_hip_z = (arm.matrix_world @ hip.head_local).z
    log("VIT hip rest world z", round(vit_hip_z,4))

    def import_mx(path):
        before = set(bpy.data.objects)
        bpy.ops.import_scene.fbx(filepath=path)
        imp = [o for o in bpy.data.objects if o not in before]
        mxa = next(o for o in imp if o.type=='ARMATURE')
        return mxa, imp

    def retarget(path, action_name):
        mxa, imp = import_mx(path)
        act = mxa.animation_data.action
        f0, f1 = int(act.frame_range[0]), int(act.frame_range[1])
        # Y-up -> Z-up so MX world matches VIT (Blender Z-up). Mixamo forward +Z -> -Y (VIT faces -Y).
        mxa.rotation_euler = (math.pi/2, 0, 0)
        bpy.context.view_layer.update()
        # match source height to VIT so hip-location copy lands feet at ground
        mx_hip = mxa.data.bones["mixamorig:Hips"]
        mx_hip_z = (mxa.matrix_world @ mx_hip.head_local).z
        k = vit_hip_z / mx_hip_z if mx_hip_z else 1.0
        mxa.scale = tuple(s*k for s in mxa.scale)
        bpy.context.view_layer.update()
        log(action_name, "src frames", f0, f1, "height k", round(k,4),
            "mx_hip_z", round(mx_hip_z,4))

        # bones animated by this action that also exist in VIT
        mx_action_bones = set(fc.data_path.split('"')[1] for fc in act.fcurves if '"' in fc.data_path)
        mapped = [b for b in mx_action_bones if b in vit_bones]

        # constraints: copy world rotation to every mapped bone; copy world loc to Hips only
        bpy.ops.object.select_all(action='DESELECT')
        bpy.context.view_layer.objects.active = arm; arm.select_set(True)
        bpy.ops.object.mode_set(mode='POSE')
        for pb in arm.pose.bones:
            pb.rotation_mode = 'QUATERNION'
        added = []
        for bn in mapped:
            pb = arm.pose.bones[bn]
            cr = pb.constraints.new('COPY_ROTATION')
            cr.target = mxa; cr.subtarget = bn
            cr.target_space='WORLD'; cr.owner_space='WORLD'
            added.append((pb,cr))
            if bn == "mixamorig:Hips":
                cl = pb.constraints.new('COPY_LOCATION')
                cl.target = mxa; cl.subtarget = bn
                cl.target_space='WORLD'; cl.owner_space='WORLD'
        log(action_name, "mapped bones", len(mapped))

        # bake visual transform into a fresh action, clearing constraints
        if not arm.animation_data: arm.animation_data_create()
        arm.animation_data.action = None
        bpy.context.scene.frame_start = f0; bpy.context.scene.frame_end = f1
        bpy.ops.nla.bake(frame_start=f0, frame_end=f1, only_selected=False,
            visual_keying=True, clear_constraints=True, clear_parents=False,
            use_current_action=True, bake_types={'POSE'})
        baked = arm.animation_data.action
        baked.name = action_name; baked.use_fake_user = True
        # shift keys to start at frame 1 for clean glTF
        log(action_name, "baked", baked.name, "range", tuple(round(x,1) for x in baked.frame_range))

        bpy.ops.object.mode_set(mode='OBJECT')
        # cleanup imported source
        for o in imp:
            d = o.data
            bpy.data.objects.remove(o, do_unlink=True)
        return baked

    # ---- run retarget for all clips ----
    actions = []
    for fn, an in CLIPS:
        p = os.path.join(MX_DIR, fn)
        if not os.path.exists(p):
            log("MISSING", p); continue
        a = retarget(p, an)
        actions.append(a)
        if arm.animation_data: arm.animation_data.action = None  # detach before next bake
    # purge leftover imported Mixamo source actions so they don't export as junk anims
    target_names = set(an for _,an in CLIPS)
    for a in list(bpy.data.actions):
        if a.name not in target_names:
            log("purge stray action", a.name); bpy.data.actions.remove(a)
    log("actions built", [a.name for a in bpy.data.actions])

    if MODE == "verify":
        # Workbench render montages: front view, 3 frames per clip
        os.makedirs(RENDIR, exist_ok=True)
        scn = bpy.context.scene
        scn.render.engine = 'BLENDER_WORKBENCH'
        scn.render.resolution_x = 480; scn.render.resolution_y = 640
        scn.render.film_transparent = False
        # camera in front (-Y) looking +Y
        cam = bpy.data.objects.get("Camera")
        if cam is None:
            cd = bpy.data.cameras.new("Camera"); cam = bpy.data.objects.new("Camera", cd)
            scn.collection.objects.link(cam)
        cam.location = (0.0, -3.6, 1.0)
        cam.rotation_euler = (math.pi/2, 0, 0)   # look +Y
        cam.data.lens = 50
        scn.camera = cam
        for a in actions:
            arm.animation_data.action = a
            f0,f1 = int(a.frame_range[0]), int(a.frame_range[1])
            for tag,fr in (("a",f0),("b",(f0+f1)//2),("c",f1)):
                scn.frame_set(fr)
                bpy.context.view_layer.update()
                scn.render.filepath = os.path.join(RENDIR, f"{a.name}_{tag}.png")
                bpy.ops.render.render(write_still=True)
            log("rendered", a.name)
        flush()
    else:
        # EXPORT: replicate _animated_body_export.py body/clothing setup, then export GLB
        ASSETS = r"C:/Users/Sam/AppData/Roaming/Blender Foundation/Blender/4.5/scripts/addons/CharMorph/data/characters/Vitruvian/assets"
        for m in list(body.modifiers):
            if m.type=='PARTICLE_SYSTEM': body.modifiers.remove(m)
        body.data.materials.clear(); body.data.materials.append(bpy.data.materials.new("VitBody"))
        cloth=[]
        for c,mn in (("Shirt.blend","VitShirt"),("Pants.blend","VitPants")):
            cp = os.path.join(ASSETS,c)
            if not os.path.exists(cp):
                log("no cloth", cp); continue
            before=set(bpy.data.objects)
            with bpy.data.libraries.load(cp,link=False) as (df,dt):
                dt.objects=list(df.objects)
            for o in [o for o in bpy.data.objects if o not in before]:
                if o.type!='MESH': continue
                bpy.context.scene.collection.objects.link(o)
                o.data.materials.clear(); o.data.materials.append(bpy.data.materials.new(mn))
                cloth.append(o)
        for o in cloth:
            bpy.ops.object.select_all(action='DESELECT')
            o.select_set(True); arm.select_set(True); bpy.context.view_layer.objects.active=arm
            bpy.ops.object.parent_set(type='ARMATURE_AUTO')
        log("clothing", [o.name for o in cloth])

        # ---- occlusion trim: delete body skin hidden under the clothes ----
        # Robust to cloth normal winding: ray-cast each body vert ALONG ITS OUTWARD
        # NORMAL; if a cloth surface is just outside (within MAXD), that skin is covered
        # → drop it. Exposed skin (neck, forearms, hands, feet) normals miss the cloth.
        from mathutils.bvhtree import BVHTree
        def cloth_bvh(o):
            mw=o.matrix_world
            verts=[mw@v.co for v in o.data.vertices]
            polys=[tuple(p.vertices) for p in o.data.polygons]
            return BVHTree.FromPolygons(verts, polys)
        bvhs=[cloth_bvh(o) for o in cloth]
        MAXD=0.045   # cloth within 4.5cm outward of the skin = covered
        EPS=0.001
        me=body.data
        bm=bmesh.new(); bm.from_mesh(me)
        bm.verts.ensure_lookup_table(); bm.normal_update()
        mwb=body.matrix_world; rot=mwb.to_3x3()
        covered=[False]*len(bm.verts)
        for v in bm.verts:
            o_w=mwb@v.co; n_w=(rot@v.normal).normalized()
            for bvh in bvhs:
                loc,nrm,idx,dist=bvh.ray_cast(o_w+n_w*EPS, n_w, MAXD)
                if loc is not None:
                    covered[v.index]=True; break
        head=lambda f: f.calc_center_median().z>1.50         # head provided by the head GLB (z>1.50)
        # KEEP only the NECK COLUMN skin (tight cylinder around the neck axis, z 1.42-1.50)
        # so it fills the collar OPENING and flows smoothly into the body — but NOT the wider
        # chest/shoulder skin, which would poke through the shirt as skin blotches.
        def keepneck(f):
            c=f.calc_center_median()
            # wider + a touch lower so the collar opening (incl the front dip + clavicle
            # corners) is filled with skin — no holes. The inflated shirt hides the excess.
            return 1.39 < c.z <= 1.50 and (c.x*c.x + (c.y+0.02)**2) < 0.090*0.090
        todel=[f for f in bm.faces if head(f) or (all(covered[v.index] for v in f.verts) and not keepneck(f))]
        bmesh.ops.delete(bm, geom=todel, context='FACES')
        bm.verts.ensure_lookup_table()
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context='VERTS')
        for f in bm.faces: f.material_index=0
        bm.to_mesh(me); bm.free(); me.update()
        log("body trimmed verts", len(me.vertices), "covered", sum(covered))

        # ---- UDIM → 2×2 atlas UV remap (real body skin textures) ----
        # bake_skin_textures.py packs tiles 1001-1004 into quadrants of vit_body_*.png
        # (Godot has no UDIM). Remap the UDIM layer IN PLACE so TEXCOORD_0 samples the
        # atlas: u' = (frac+col)*0.5, v' = (frac+row)*0.5. The kept neck column is tile
        # 1001 — the same texture region as the face → neck tone finally matches.
        QUAD = {1001: (0, 0), 1002: (1, 0), 1003: (0, 1), 1004: (1, 1)}
        uvl_at = me.uv_layers["VitruvianUV_UDIM"]
        me.uv_layers.active = uvl_at
        for uv in me.uv_layers:
            uv.active_render = (uv.name == "VitruvianUV_UDIM")
        for d in uvl_at.data:
            u, v = d.uv
            tile = 1001 + int(math.floor(u)) + 10 * int(math.floor(v))
            col, row = QUAD.get(tile, (0, 0))
            d.uv = ((u - math.floor(u) + col) * 0.5, (v - math.floor(v) + row) * 0.5)
        log("body UVs remapped to 2x2 atlas (tiles 1001-1004)")

        # ---- SHOES: simple dark flats from the foot skin (audit: barefoot = asset-store).
        # Faces below the ankle get a VitShoes material; the foot region puffs out 1.5mm
        # along its normals (fading to 0 at the ankle) so the flat reads as a thin shoe
        # shell, not painted skin. Follows the rig/walk for free.
        import numpy as _np
        me.materials.append(bpy.data.materials.new("VitShoes"))
        shoe_idx=len(me.materials)-1
        ANKLE_Z=0.062
        sbm2=bmesh.new(); sbm2.from_mesh(me); sbm2.normal_update(); sbm2.verts.ensure_lookup_table()
        nshoe=0
        for f in sbm2.faces:
            if f.calc_center_median().z < ANKLE_Z:
                f.material_index=shoe_idx; nshoe+=1
        # MELT the toes: Laplacian-smooth the shoe-region POSITIONS so the foot becomes
        # a single shoe form (deep toe creases survive any amount of pure inflation),
        # then inflate along smoothed normals. Smoothing fades to 0 at the ankle lip.
        sverts=[v for v in sbm2.verts if v.co.z < ANKLE_Z + 0.002]
        for _ in range(14):
            disp={}
            for v in sverts:
                if not v.link_edges: continue
                avgp=Vector((0,0,0))
                for e in v.link_edges: avgp += e.other_vert(v).co
                avgp /= len(v.link_edges)
                wsm=min(1.0,(ANKLE_Z+0.002-v.co.z)/0.018)   # full melt below ~0.046
                disp[v]= (avgp - v.co) * 0.5 * wsm
            for v,dv in disp.items(): v.co += dv
        sbm2.normal_update()
        nrm2=_np.array([tuple(v.normal) for v in sbm2.verts])
        nbrs2=[[e.other_vert(v).index for e in v.link_edges] for v in sbm2.verts]
        for _ in range(10):
            avg2=_np.array([nrm2[nb].mean(axis=0) if nb else nrm2[i] for i,nb in enumerate(nbrs2)])
            nrm2=0.5*nrm2+0.5*avg2
            nrm2/=_np.clip(_np.linalg.norm(nrm2,axis=1,keepdims=True),1e-9,None)
        for i,v in enumerate(sbm2.verts):
            if v.co.z < ANKLE_Z + 0.004:
                w=min(1.0,(ANKLE_Z+0.004-v.co.z)/0.03)             # fade at the ankle lip
                amt=0.0015 + 0.0025*min(1.0,max(0.0,(0.035-v.co.z)/0.03))  # toes swell most
                v.co += Vector((nrm2[i][0],nrm2[i][1],nrm2[i][2]))*amt*w
        sbm2.to_mesh(me); sbm2.free(); me.update()
        log("shoes: faces",nshoe,"(toe-merged inflation)")

        # INFLATE the shirt (push verts out along SMOOTHED normals) so it sits proud of the
        # skin and hides any poke-through. Raw per-vert normals made the shoulder seams
        # inflate into POINTY SPIKES (audit #5/Tier-1 #10): at a hard seam/crease the normal
        # flips direction vert-to-vert, so +6mm tears the seam into peaks. Laplacian-smooth
        # the normal field first → low-frequency, seam-stable inflation direction.
        import numpy as _np
        for o in cloth:
            is_shirt = ("Shirt" in o.name) or (o.data.materials and "Shirt" in o.data.materials[0].name)
            if not is_shirt: continue
            sbm=bmesh.new(); sbm.from_mesh(o.data); sbm.normal_update()
            sbm.verts.ensure_lookup_table()
            nrm=_np.array([tuple(v.normal) for v in sbm.verts])
            nbrs=[[e.other_vert(v).index for e in v.link_edges] for v in sbm.verts]
            for _ in range(8):
                avg=_np.array([nrm[nb].mean(axis=0) if nb else nrm[i] for i,nb in enumerate(nbrs)])
                nrm=0.5*nrm+0.5*avg
                nrm/=_np.clip(_np.linalg.norm(nrm,axis=1,keepdims=True),1e-9,None)
            for i,v in enumerate(sbm.verts):
                v.co += Vector((nrm[i][0],nrm[i][1],nrm[i][2])) * 0.006
            sbm.to_mesh(o.data); sbm.free(); o.data.update()
            log("inflated shirt (smoothed normals)", o.name)

        # optional clothed verification render (export pass) before writing GLB
        if "clothtest" in ARGS:
            os.makedirs(RENDIR, exist_ok=True)
            scn=bpy.context.scene; scn.render.engine='BLENDER_WORKBENCH'
            scn.render.resolution_x=480; scn.render.resolution_y=640
            # tint body skin-pink, clothes dark, so any poke-through is obvious
            scn.display.shading.color_type='OBJECT'
            body.color=(0.92,0.55,0.50,1.0)
            for o in cloth: o.color=(0.10,0.11,0.14,1.0)
            cam=bpy.data.objects.get("Camera")
            if cam is None:
                cd=bpy.data.cameras.new("Camera"); cam=bpy.data.objects.new("Camera",cd); scn.collection.objects.link(cam)
            cam.location=(0.0,-3.6,1.0); cam.rotation_euler=(math.pi/2,0,0); cam.data.lens=50; scn.camera=cam
            wact=next((a for a in bpy.data.actions if a.name=="Walk"),None)
            if wact:
                arm.animation_data.action=wact
                for tag,fr in (("a",4),("b",16),("c",28)):
                    scn.frame_set(fr); bpy.context.view_layer.update()
                    scn.render.filepath=os.path.join(RENDIR,f"clothed_walk_{tag}.png")
                    bpy.ops.render.render(write_still=True)
                log("clothed verify rendered")
        # ensure an action is active so exporter sees the rig animated
        if actions: arm.animation_data.action = actions[0]
        bpy.ops.object.select_all(action='DESELECT')
        for o in [arm, body]+cloth: o.select_set(True)
        bpy.context.view_layer.objects.active=arm
        glb=os.path.join(ROOT,"godot_project","vitruvian_body.glb")
        bpy.ops.export_scene.gltf(filepath=glb, export_format='GLB', use_selection=True,
            export_apply=False, export_yup=True, export_materials='EXPORT',
            export_normals=True, export_tangents=True, export_texcoords=True,
            export_skins=True, export_animations=True, export_animation_mode='ACTIONS',
            export_bake_animation=True, export_anim_slide_to_zero=True)
        log("wrote", glb, "size", os.path.getsize(glb))
        flush()
except Exception as e:
    log("FAIL", repr(e)); traceback.print_exc(); flush()
finally:
    try: bpy.ops.wm.quit_blender()
    except: pass
