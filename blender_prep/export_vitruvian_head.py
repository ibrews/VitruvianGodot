# Vitruvian head export v5 — REAL-TIME REBUILD per researched plan.
# Skin (Game_Pack bake comes separately), mouth, scalp cap, eyebrow groom, and a
# proper real-time EYE: delete Vitruvian's Cycles refraction eye stack entirely
# and drop in blackears' radial-UV eyeball + cornea spheres (procedural iris in
# the Godot shader → no iris-texture occlusion / walleye problems).
#
# Run: blender --background char.blend --python export_vitruvian_head.py
import bpy, bmesh, os, math
import numpy as np
from mathutils import Vector

OUT = "H:/Work01/VitruvianGodot/godot_project"   # write straight into the repo
VDIR = os.path.dirname(bpy.data.filepath)
DATA = os.path.join(VDIR, "textures", "4K")
EYEBROWS_BLEND = os.path.join(VDIR, "eyebrows.blend")
EYEBALL_GLB = "H:/Work01/VitruvianGodot/blender_prep/eyeball_src.glb"
NECK_CUT_Z = 1.49
TEX_SIZE = 2048
SKIN_TONE = 0.45
# Eye sockets (probed): centers + radius, face-forward = -Y.
SOCKETS = {"L": Vector((-0.0335, -0.0531, 1.6344)), "R": Vector((0.0335, -0.0531, 1.6344))}
EYE_R = 0.0125            # human eyeball ≈ 12mm radius
EYE_RECESS = 0.0025       # nudge +Y (away from camera) so it sits behind the lids
IRIS_FWD = Vector((0.0, -1.0, 0.0))   # iris should face the camera (-Y)

obj = bpy.data.objects["cm_vitruvian"]
for m in list(obj.modifiers):
    if m.type == 'PARTICLE_SYSTEM':
        obj.modifiers.remove(m)
uvs = obj.data.uv_layers
udim = "VitruvianUV_UDIM"
uvs.active = uvs[udim]
for uv in uvs:
    uv.active_render = (uv.name == udim)
me = obj.data

# Material slots: 0 skin, 1 mouth, 2 scalp, 3 = DELETE (eyes).
me.materials.clear()
for nm in ("VitSkin", "VitMouth", "VitScalp", "VitDelete"):
    me.materials.append(bpy.data.materials.new(nm))
SKIN, MOUTH, SCALP, DEL = 0, 1, 2, 3
uvl = me.uv_layers[udim].data
for poly in me.polygons:
    u, v = uvl[poly.loop_indices[0]].uv
    tile = 1001 + int(math.floor(u)) + 10 * int(math.floor(v))
    if tile == 1001:
        poly.material_index = SKIN
    elif tile == 1006:
        poly.material_index = MOUTH
    elif tile in (1005, 1007):
        poly.material_index = DEL   # all Vitruvian eye geometry → delete
    else:
        poly.material_index = SKIN

# Delete eye faces + loose verts + body below neck.
bm = bmesh.new(); bm.from_mesh(me)
bm.faces.ensure_lookup_table()
bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.material_index == DEL], context='FACES')
bm.verts.ensure_lookup_table()
bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context='VERTS')
bm.verts.ensure_lookup_table()
bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.z < NECK_CUT_Z], context='VERTS')
# Scalp cap (dark) under the hair part.
bm.faces.ensure_lookup_table(); bm.normal_update()
scalp_src = [f for f in bm.faces if f.material_index == SKIN
             and f.calc_center_median().z >= 1.655 and f.calc_center_median().y > -0.05]
dup = bmesh.ops.duplicate(bm, geom=scalp_src)
for el in dup["geom"]:
    if isinstance(el, bmesh.types.BMFace):
        el.material_index = SCALP
        for vv in el.verts:
            vv.co += vv.normal * 0.003
bm.to_mesh(me); bm.free(); me.update()
print("[export] head verts:", len(me.vertices), "polys:", len(me.polygons))

# ---- place blackears eyeballs ----
bpy.ops.import_scene.gltf(filepath=EYEBALL_GLB)
src = {}
for o in list(bpy.context.selected_objects):
    # NOTE: skip "eyeball_back" — it's coincident (r=1.0) with "eyeball" and
    # z-fights, blanking one eye white. The open back is hidden in the socket.
    if o.type == 'MESH' and o.name in ("eyeball", "cornea"):
        # bake import rotation + scale into mesh data so local co is final-oriented
        bpy.ops.object.select_all(action='DESELECT')
        o.select_set(True); bpy.context.view_layer.objects.active = o
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
        src[o.name] = o
# iris-front axis from the eyeball's UV(0.5,0.5) vertex
eb = src["eyeball"]; ebme = eb.data
iris_axis = None; bestd = 9.0
uvl2 = ebme.uv_layers.active.data
for poly in ebme.polygons:
    for li in poly.loop_indices:
        uv = uvl2[li].uv
        d = (uv.x - 0.5) ** 2 + (uv.y - 0.5) ** 2
        if d < bestd:
            bestd = d; iris_axis = ebme.vertices[ebme.loops[li].vertex_index].co.normalized()
print("[export] eyeball iris axis (local):", tuple(round(c, 2) for c in iris_axis))
rot_q = iris_axis.rotation_difference(IRIS_FWD)

# ONE shared material datablock per type — else Blender auto-suffixes the second
# eye's material to "VitEyeball.001" and Godot's name match misses it (→ white eye).
eye_mat_obj = {"eyeball": bpy.data.materials.new("VitEyeball"),
               "cornea": bpy.data.materials.new("VitCornea")}
eye_objs = []
for side, center in SOCKETS.items():
    for nm, so in src.items():
        d = so.copy(); d.data = so.data.copy()
        bpy.context.scene.collection.objects.link(d)
        d.name = "Eye_%s_%s" % (side, nm)
        d.rotation_mode = 'QUATERNION'
        d.rotation_quaternion = rot_q
        d.scale = (EYE_R, EYE_R, EYE_R)
        d.location = center + Vector((0.0, EYE_RECESS, 0.0))
        d.data.materials.clear()
        d.data.materials.append(eye_mat_obj[nm])
        eye_objs.append(d)
# remove the import originals
for so in src.values():
    bpy.data.objects.remove(so, do_unlink=True)
print("[export] placed", len(eye_objs), "eye objects")

# Eyebrow groom.
with bpy.data.libraries.load(EYEBROWS_BLEND) as (s, dst):
    dst.objects = ["Vitruvian-EyeBrows"]
brow = None
for o in dst.objects:
    if o:
        bpy.context.scene.collection.objects.link(o); brow = o
if brow:
    brow.data.materials.clear()
    brow.data.materials.append(bpy.data.materials.new("VitBrows"))

# Export head + eyebrows + eyes.
bpy.ops.object.select_all(action='DESELECT')
obj.select_set(True)
if brow: brow.select_set(True)
for d in eye_objs: d.select_set(True)
bpy.context.view_layer.objects.active = obj
glb = os.path.join(OUT, "vitruvian_head.glb")
bpy.ops.export_scene.gltf(filepath=glb, export_format='GLB', use_selection=True,
    export_apply=True, export_yup=True, export_materials='EXPORT',
    export_normals=True, export_tangents=True, export_texcoords=True)
print("[export] wrote", glb)

# ---- textures (skin + mouth; eyes are procedural now) ----
import zlib, struct
def _chunk(tag, data):
    return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xffffffff)
def exr(path, size):
    img = bpy.data.images.load(path, check_existing=False)
    w, h = img.size
    px = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, img.channels)
    bpy.data.images.remove(img)
    if w != size:
        step = max(1, w // size); px = px[::step, ::step, :]
    return px
def lin2srgb(c):
    a = 0.055
    return np.where(c <= 0.0031308, c * 12.92, (1 + a) * np.power(np.clip(c, 0, None), 1 / 2.4) - a)
def save_png(arr, path, srgb):
    rgb = np.clip(arr[..., :3], 0, 1)
    if srgb: rgb = lin2srgb(rgb)
    rgb = np.flipud(rgb)
    h, w = rgb.shape[:2]
    u8 = (np.clip(rgb, 0, 1) * 255 + 0.5).astype(np.uint8)
    raw = np.hstack([np.zeros((h, 1), np.uint8), u8.reshape(h, w * 3)]).tobytes()
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + _chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
                + _chunk(b"IDAT", zlib.compress(raw, 6)) + _chunk(b"IEND", b""))
    print("[tex] wrote", os.path.basename(path), w, "x", h)

light = exr(os.path.join(DATA, "skin_light_col.1001.exr"), TEX_SIZE)
dark = exr(os.path.join(DATA, "skin_dark_col.1001.exr"), TEX_SIZE)
save_png(light * (1 - SKIN_TONE) + dark * SKIN_TONE, os.path.join(OUT, "vit_face_bc.png"), True)
crc = exr(os.path.join(DATA, "skin_cavity_rough_coat.1001.exr"), TEX_SIZE)
save_png(np.repeat(crc[..., 1:2], 3, 2), os.path.join(OUT, "vit_face_rough.png"), False)
disp = exr(os.path.join(DATA, "skin_disp.1001.exr"), TEX_SIZE)[..., 0]
gy, gx = np.gradient(disp.astype(np.float32))
nx, ny, nz = -gx * 6.0, -gy * 6.0, np.ones_like(disp)
ln = np.sqrt(nx * nx + ny * ny + nz * nz)
save_png(np.dstack([nx / ln * 0.5 + 0.5, ny / ln * 0.5 + 0.5, nz / ln * 0.5 + 0.5]), os.path.join(OUT, "vit_face_n.png"), False)
save_png(exr(os.path.join(DATA, "mouth_col.1006.exr"), 1024), os.path.join(OUT, "vit_mouth.png"), True)
print("[export] DONE")
