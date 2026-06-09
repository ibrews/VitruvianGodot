## Relaxed A-pose + clothing-weighted body re-export (static, baked pose).
## Opens vitruvian_rigged.blend (body already Mixamo-rigged), appends + auto-weights
## Shirt/Pants, lowers the arms into an A-pose, bakes the pose, exports neck-down.
import bpy, bmesh, os, math, traceback
from mathutils import Matrix, Vector
LOG=r"H:/Work01/VitruvianGodot/blender_prep/hairtool_out/pose_export.log"; _l=[]
def log(*a):
    s=" ".join(str(x) for x in a); print("POSE:",s); _l.append(s)
def flush(): open(LOG,"w",encoding="utf-8").write("\n".join(_l))
try:
    OUT="H:/Work01/VitruvianGodot/godot_project"
    ASSETS=r"C:/Users/Sam/AppData/Roaming/Blender Foundation/Blender/4.5/scripts/addons/CharMorph/data/characters/Vitruvian/assets"
    body=bpy.data.objects["cm_vitruvian"]
    arm=bpy.data.objects["mixamo_vitruvian"]
    # remove leftover particle systems
    for m in list(body.modifiers):
        if m.type=='PARTICLE_SYSTEM': body.modifiers.remove(m)
    # one flat material for the body
    body.data.materials.clear(); body.data.materials.append(bpy.data.materials.new("VitBody"))

    cloth_objs=[]
    for cloth,matname in (("Shirt.blend","VitShirt"),("Pants.blend","VitPants")):
        before=set(bpy.data.objects)
        with bpy.data.libraries.load(os.path.join(ASSETS,cloth),link=False) as (df,dt):
            dt.objects=list(df.objects)
        for o in [o for o in bpy.data.objects if o not in before]:
            if o.type!='MESH': continue
            bpy.context.scene.collection.objects.link(o)
            o.data.materials.clear(); o.data.materials.append(bpy.data.materials.new(matname))
            cloth_objs.append(o)
    log("clothing", [o.name for o in cloth_objs])

    # auto-weight clothing to the rig
    for o in cloth_objs:
        bpy.ops.object.select_all(action='DESELECT')
        o.select_set(True); arm.select_set(True)
        bpy.context.view_layer.objects.active=arm
        bpy.ops.object.parent_set(type='ARMATURE_AUTO')
    log("clothing auto-weighted")

    # ---- A-pose: lower upper arms about global Y ----
    bpy.ops.object.select_all(action='DESELECT')
    bpy.context.view_layer.objects.active=arm; arm.select_set(True)
    bpy.ops.object.mode_set(mode='POSE')
    def rot_bone(name, ang_deg, axis='Y'):
        pb=arm.pose.bones.get(name)
        if not pb:
            log("  no bone", name); return
        R=Matrix.Rotation(math.radians(ang_deg), 4, axis)
        pb.matrix = R @ pb.matrix
        bpy.context.view_layer.update()
    # left arm should swing DOWN; sign chosen, will verify in render
    rot_bone("mixamorig:LeftArm",  40, 'Y')
    rot_bone("mixamorig:RightArm", -40, 'Y')
    rot_bone("mixamorig:LeftForeArm",  8, 'Y')
    rot_bone("mixamorig:RightForeArm", -8, 'Y')
    bpy.ops.object.mode_set(mode='OBJECT')
    log("posed arms")

    # ---- bake pose: apply armature modifier on body + clothing ----
    for o in [body]+cloth_objs:
        bpy.ops.object.select_all(action='DESELECT')
        o.select_set(True); bpy.context.view_layer.objects.active=o
        for m in list(o.modifiers):
            if m.type=='ARMATURE':
                try: bpy.ops.object.modifier_apply(modifier=m.name)
                except Exception as e: log("apply fail",o.name,repr(e))
    log("baked pose")

    # ---- delete head region (keep neck-down body) ----
    me=body.data
    bm=bmesh.new(); bm.from_mesh(me); bm.faces.ensure_lookup_table()
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.calc_center_median().z>1.52], context='FACES')
    bm.verts.ensure_lookup_table()
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context='VERTS')
    for f in bm.faces: f.material_index=0
    bm.to_mesh(me); bm.free(); me.update()
    log("body neck-down verts", len(me.vertices))

    # export static posed body + clothing
    bpy.ops.object.select_all(action='DESELECT')
    for o in [body]+cloth_objs: o.select_set(True)
    bpy.context.view_layer.objects.active=body
    glb=os.path.join(OUT,"vitruvian_body.glb")
    bpy.ops.export_scene.gltf(filepath=glb,export_format='GLB',use_selection=True,
        export_apply=True,export_yup=True,export_materials='EXPORT',
        export_normals=True,export_tangents=True,export_texcoords=True)
    log("wrote",glb)
    flush()
except Exception as e:
    log("FAIL",repr(e)); traceback.print_exc(); flush()
finally:
    try: bpy.ops.wm.quit_blender()
    except: pass
