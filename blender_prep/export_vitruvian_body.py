## Full-body export (neck-down) + CharMorph Shirt/Pants clothing.
## Pairs with the existing vitruvian_head.glb (head+eyes+lashes) — both come from the
## same char.blend coordinate space so they align at the neck automatically.
## Run: blender --background char.blend --python export_vitruvian_body.py
import bpy, bmesh, os, math, traceback
import numpy as np
from mathutils import Vector

OUT = "H:/Work01/VitruvianGodot/godot_project"
VDIR = os.path.dirname(bpy.data.filepath)
ASSETS = os.path.join(VDIR, "assets")
DATA = os.path.join(VDIR, "textures", "4K")
NECK_KEEP_Z = 1.52     # keep body up to just above the head's neck cut (1.49) → overlap
LOG = r"H:/Work01/VitruvianGodot/blender_prep/hairtool_out/body_export.log"; _l=[]
def log(*a):
    s=" ".join(str(x) for x in a); print("HTBE:",s); _l.append(s)

try:
    obj = bpy.data.objects["cm_vitruvian"]
    for m in list(obj.modifiers):
        if m.type == 'PARTICLE_SYSTEM':
            obj.modifiers.remove(m)
    me = obj.data
    me.uv_layers.active = me.uv_layers["VitruvianUV_UDIM"]

    # one flat skin material for the body (clothing covers most; exposed skin = hands/
    # forearms/feet/neck reads as plain skin tone — fine for a clothed look-dev figure)
    me.materials.clear()
    me.materials.append(bpy.data.materials.new("VitBody"))

    bm = bmesh.new(); bm.from_mesh(me)
    bm.faces.ensure_lookup_table()
    # keep only neck-down body geometry
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.calc_center_median().z > NECK_KEEP_Z], context='FACES')
    bm.verts.ensure_lookup_table()
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context='VERTS')
    for f in bm.faces:
        f.material_index = 0
    bm.to_mesh(me); bm.free(); me.update()
    log("body verts", len(me.vertices), "polys", len(me.polygons))

    export_objs = [obj]

    # ---- append CharMorph clothing (Shirt + Pants) ----
    for cloth, matname in (("Shirt.blend", "VitShirt"), ("Pants.blend", "VitPants")):
        path = os.path.join(ASSETS, cloth)
        before = set(bpy.data.objects)
        with bpy.data.libraries.load(path, link=False) as (df, dt):
            dt.objects = list(df.objects)
        new = [o for o in bpy.data.objects if o not in before]
        for o in new:
            if o.type != 'MESH':
                continue
            bpy.context.scene.collection.objects.link(o)
            o.data.materials.clear()
            o.data.materials.append(bpy.data.materials.new(matname))
            co = [o.matrix_world @ v.co for v in o.data.vertices]
            zs = [c.z for c in co]
            log(f"  {cloth} obj '{o.name}' verts={len(o.data.vertices)} Z=({min(zs):.2f},{max(zs):.2f})")
            export_objs.append(o)

    # export
    bpy.ops.object.select_all(action='DESELECT')
    for o in export_objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = obj
    glb = os.path.join(OUT, "vitruvian_body.glb")
    bpy.ops.export_scene.gltf(filepath=glb, export_format='GLB', use_selection=True,
        export_apply=True, export_yup=True, export_materials='EXPORT',
        export_normals=True, export_tangents=True, export_texcoords=True)
    log("wrote", glb)

    # sample a representative body skin tone (linear) from the light-skin EXR tile 1002
    try:
        img = bpy.data.images.load(os.path.join(DATA, "skin_light_col.1002.exr"), check_existing=False)
        px = np.array(img.pixels[:], dtype=np.float32).reshape(-1, img.channels)
        m = px[:, 3] > 0.5 if img.channels == 4 else np.ones(len(px), bool)
        tone = px[m][:, :3].mean(axis=0)
        bpy.data.images.remove(img)
        log("BODY_SKIN_TONE_LINEAR", round(float(tone[0]),4), round(float(tone[1]),4), round(float(tone[2]),4))
    except Exception as e:
        log("skin tone sample fail", repr(e))
    open(LOG,"w",encoding="utf-8").write("\n".join(_l))
except Exception as e:
    log("FAIL", repr(e)); traceback.print_exc(); open(LOG,"w",encoding="utf-8").write("\n".join(_l))
finally:
    try: bpy.ops.wm.quit_blender()
    except: pass
