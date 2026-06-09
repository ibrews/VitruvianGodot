## Rigged + ANIMATED neck-down body + clothing → vitruvian_body.glb (armature + glTF
## actions). Head GLB + hair attach to mixamorig:Head in Godot. Animations authored on
## the Mixamo rig: idle (A-pose breathing), sway, headturn, hairtoss.
import bpy, bmesh, os, math, traceback
from mathutils import Matrix, Vector, Euler
LOG=r"H:/Work01/VitruvianGodot/blender_prep/hairtool_out/anim_export.log"; _l=[]
def log(*a):
    s=" ".join(str(x) for x in a); print("ANIM:",s); _l.append(s)
def flush(): open(LOG,"w",encoding="utf-8").write("\n".join(_l))
try:
    OUT="H:/Work01/VitruvianGodot/godot_project"
    ASSETS=r"C:/Users/Sam/AppData/Roaming/Blender Foundation/Blender/4.5/scripts/addons/CharMorph/data/characters/Vitruvian/assets"
    body=bpy.data.objects["cm_vitruvian"]
    arm=bpy.data.objects["mixamo_vitruvian"]
    for m in list(body.modifiers):
        if m.type=='PARTICLE_SYSTEM': body.modifiers.remove(m)
    body.data.materials.clear(); body.data.materials.append(bpy.data.materials.new("VitBody"))

    # clothing append + auto-weight
    cloth=[]
    for c,mn in (("Shirt.blend","VitShirt"),("Pants.blend","VitPants")):
        before=set(bpy.data.objects)
        with bpy.data.libraries.load(os.path.join(ASSETS,c),link=False) as (df,dt):
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
    log("clothing weighted", [o.name for o in cloth])

    # delete head region from body mesh (keep neck-down) — bones stay intact
    me=body.data
    bm=bmesh.new(); bm.from_mesh(me); bm.faces.ensure_lookup_table()
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.calc_center_median().z>1.52], context='FACES')
    bm.verts.ensure_lookup_table()
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context='VERTS')
    for f in bm.faces: f.material_index=0
    bm.to_mesh(me); bm.free(); me.update()
    log("body neck-down verts", len(me.vertices))

    # ---------------- animation authoring ----------------
    bpy.ops.object.select_all(action='DESELECT')
    bpy.context.view_layer.objects.active=arm; arm.select_set(True)
    bpy.ops.object.mode_set(mode='POSE')
    for pb in arm.pose.bones: pb.rotation_mode='QUATERNION'
    bpy.context.view_layer.update()
    rest={pb.name: pb.matrix.copy() for pb in arm.pose.bones}

    def wbone(name, rots=(), trans=None):
        # GLOBAL-axis rotation about the bone origin (pre-multiply) + optional WORLD
        # translation. Blender Z=up, character faces -Y, left-right=X, fore/aft swing=X.
        pb=arm.pose.bones.get(name)
        if not pb: return
        R=Matrix.Identity(4)
        for ang,ax in rots: R=Matrix.Rotation(math.radians(ang),4,ax) @ R
        M = R @ rest[name]
        if trans is not None: M = Matrix.Translation(trans) @ M
        pb.matrix = M
        bpy.context.view_layer.update()

    ARMS_DOWN = 40.0
    def arms(swingL=0.0, swingR=0.0, ydL=ARMS_DOWN, ydR=-ARMS_DOWN, foreL=8.0, foreR=-8.0):
        # arms at A-pose (Y) with optional fore/aft swing (X)
        wbone("mixamorig:LeftArm",  ((ydL,'Y'),(swingL,'X')))
        wbone("mixamorig:RightArm", ((ydR,'Y'),(swingR,'X')))
        wbone("mixamorig:LeftForeArm",  ((foreL,'Y'),))
        wbone("mixamorig:RightForeArm", ((foreR,'Y'),))

    def torso(spine_x=0.0, spine_z=0.0, hips_y=0.0, hips_z=0.0, hips_bob=0.0, hips_shift=0.0,
              head_y=0.0, head_x=0.0):
        wbone("mixamorig:Hips",   ((hips_z,'Z'),(hips_y,'Y')), trans=Vector((hips_shift,0.0,hips_bob)))
        wbone("mixamorig:Spine",  ((spine_x,'X'),(spine_z,'Z')))
        wbone("mixamorig:Spine1", ((spine_x*0.6,'X'),(spine_z*0.6,'Z')))
        wbone("mixamorig:Neck", ((head_x*0.4,'X'),(head_y*0.4,'Z')))
        wbone("mixamorig:Head", ((head_x*0.6,'X'),(head_y*0.6,'Z')))

    def legs(upL=0.0, upR=0.0, kneeL=0.0, kneeR=0.0):
        wbone("mixamorig:LeftUpLeg",  ((upL,'X'),))
        wbone("mixamorig:RightUpLeg", ((upR,'X'),))
        wbone("mixamorig:LeftLeg",    ((kneeL,'X'),))
        wbone("mixamorig:RightLeg",   ((kneeR,'X'),))

    POSED=["mixamorig:Hips","mixamorig:Spine","mixamorig:Spine1","mixamorig:Neck","mixamorig:Head",
           "mixamorig:LeftArm","mixamorig:RightArm","mixamorig:LeftForeArm","mixamorig:RightForeArm",
           "mixamorig:LeftUpLeg","mixamorig:RightUpLeg","mixamorig:LeftLeg","mixamorig:RightLeg"]
    def keyall(f):
        for n in POSED:
            pb=arm.pose.bones.get(n)
            if pb:
                pb.keyframe_insert('rotation_quaternion', frame=f)
                pb.keyframe_insert('location', frame=f)

    def new_action(name):
        act=bpy.data.actions.new(name); act.use_fake_user=True
        if not arm.animation_data: arm.animation_data_create()
        arm.animation_data.action=act
        return act

    import math as _m
    PI2=2*_m.pi

    # IDLE: clearly alive — sway, breathe, subtle weight shift, head drift, arm sway
    new_action("Idle")
    for i in range(0,121,6):
        p=i/120.0*PI2
        torso(spine_x=2.5*_m.sin(p), spine_z=2.0*_m.sin(p*0.5),
              hips_y=3.0*_m.sin(p*0.5), hips_shift=0.015*_m.sin(p*0.5),
              hips_bob=0.006*_m.sin(p)-0.003, head_y=6.0*_m.sin(p*0.5+0.6), head_x=2.0*_m.sin(p))
        arms(swingL=5*_m.sin(p*0.5), swingR=5*_m.sin(p*0.5))
        legs()
        keyall(i)

    # SWAY: big weight shift L<->R (clearly moving)
    new_action("Sway")
    for i in range(0,121,8):
        p=i/120.0*PI2
        torso(hips_y=10*_m.sin(p), hips_shift=0.06*_m.sin(p), spine_z=-6*_m.sin(p),
              head_y=-8*_m.sin(p), spine_x=2*_m.sin(p*2))
        arms(swingL=6*_m.sin(p), swingR=6*_m.sin(p))
        legs()
        keyall(i)

    # TURN: whole body yaws left then right — unmistakable motion
    new_action("Turn")
    seq=[(0,0),(30,38),(60,0),(90,-38),(120,0)]
    for f,yaw in seq:
        torso(hips_z=yaw, spine_z=yaw*0.2, head_y=yaw*0.3)
        arms(); legs()
        keyall(f)

    # WAVE: right arm raises out to the side and waves; weight on one hip
    new_action("Wave")
    wseq=[(0,-40,0,0),(15,40,30,8),(25,55,-25,-6),(35,40,30,8),(45,55,-25,-6),(60,-40,0,0)]
    for f,ydR,foreR,tilt in wseq:
        torso(hips_y=4, head_x=tilt*0.3, head_y=-6)
        arms(ydR=ydR, foreR=foreR)   # right arm up/out, forearm oscillates
        legs()
        keyall(f)

    # WALK: in-place cycle (legs swing, knees bend, hips bob+counter-yaw, arms counter-swing)
    new_action("Walk")
    for i in range(0,41,2):
        p=i/40.0*PI2
        sw=18*_m.sin(p)
        kneeL=max(0.0,-_m.sin(p))*30; kneeR=max(0.0,_m.sin(p))*30
        legs(upL=sw, upR=-sw, kneeL=kneeL, kneeR=kneeR)
        torso(hips_z=6*_m.sin(p), spine_z=-6*_m.sin(p), hips_bob=0.022*abs(_m.sin(p))-0.014,
              head_y=-3*_m.sin(p), spine_x=4.0)
        arms(swingL=-sw*0.9, swingR=sw*0.9)
        keyall(i)

    bpy.ops.object.mode_set(mode='OBJECT')
    log("actions:", [a.name for a in bpy.data.actions])

    # export rigged + animated
    bpy.ops.object.select_all(action='DESELECT')
    for o in [arm, body]+cloth: o.select_set(True)
    bpy.context.view_layer.objects.active=arm
    glb=os.path.join(OUT,"vitruvian_body.glb")
    bpy.ops.export_scene.gltf(filepath=glb, export_format='GLB', use_selection=True,
        export_apply=False, export_yup=True, export_materials='EXPORT',
        export_normals=True, export_tangents=True, export_texcoords=True,
        export_skins=True, export_animations=True, export_animation_mode='ACTIONS',
        export_bake_animation=True, export_anim_slide_to_zero=True)
    log("wrote", glb)
    flush()
except Exception as e:
    log("FAIL", repr(e)); traceback.print_exc(); flush()
finally:
    try: bpy.ops.wm.quit_blender()
    except: pass
