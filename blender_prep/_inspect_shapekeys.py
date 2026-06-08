## Inspect the Vitruvian char.blend for EXISTING facial blendshapes / shape keys,
## armatures with face bones, and any expression assets. Read-only.
import bpy, os
print("=== FILE:", bpy.data.filepath)
print("=== OBJECTS ===")
for o in bpy.data.objects:
    extra = ""
    if o.type == 'MESH':
        me = o.data
        sk = me.shape_keys
        nkeys = len(sk.key_blocks) if sk else 0
        extra = "verts=%d shape_keys=%d" % (len(me.vertices), nkeys)
        if sk and nkeys > 0:
            extra += " :: " + ", ".join(kb.name for kb in sk.key_blocks[:60])
    elif o.type == 'ARMATURE':
        bones = [b.name for b in o.data.bones]
        face_bones = [b for b in bones if any(k in b.lower() for k in ("jaw","mouth","lip","tongue","teeth","eye","brow","cheek","face","tongue"))]
        extra = "bones=%d face_bones=%d :: %s" % (len(bones), len(face_bones), ", ".join(face_bones[:40]))
    print(" -", o.name, "(", o.type, ")", extra)

print("=== MESH DATABLOCKS with shape keys ===")
for me in bpy.data.meshes:
    if me.shape_keys and len(me.shape_keys.key_blocks) > 1:
        print(" -", me.name, "keys:", [kb.name for kb in me.shape_keys.key_blocks])

print("=== ACTIONS (may hold facial poses) ===")
for a in bpy.data.actions:
    print(" -", a.name, "fcurves=", len(a.fcurves))

# scan the Vitruvian data folder for expression / FACS / blendshape files
vdir = os.path.dirname(bpy.data.filepath)
print("=== VITRUVIAN DATA DIR:", vdir, "===")
for root, dirs, fnames in os.walk(vdir):
    for fn in fnames:
        low = fn.lower()
        if any(k in low for k in ("expr","facs","blend_shape","blendshape","shapekey","shape_key","arkit","viseme","face","emotion","morph","pose")):
            print("  *", os.path.relpath(os.path.join(root, fn), vdir))
print("=== DONE ===")
try: bpy.ops.wm.quit_blender()
except: pass
