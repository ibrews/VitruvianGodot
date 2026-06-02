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
             and f.calc_center_median().z >= 1.645 and f.calc_center_median().y > -0.065]
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

# ---- procedural eyelash cards (no lash npz exists; build an upper-lid arc) ----
NCOLS = 4
LASH_LEN = 0.0065
lash_mat = bpy.data.materials.new("VitLash")
def build_lashes(center, R, name):
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new("UVMap")
    up = Vector((0, 0, 1)); right = Vector((1, 0, 0)); fwd = Vector((0, -1, 0))
    N = 11
    for k in range(N):
        a = math.radians(-66 + 132 * k / (N - 1))   # around the upper rim, 0=top
        rim_dir = (math.cos(a) * up + math.sin(a) * right).normalized()
        root = center + rim_dir * (R * 0.92) + fwd * (R * 0.35)
        lash_dir = (rim_dir * 0.35 + fwd * 1.0 + up * 0.5).normalized()
        side = lash_dir.cross(fwd)
        if side.length < 1e-6: side = lash_dir.cross(right)
        side = side.normalized()
        col = k % NCOLS
        u0 = col / NCOLS + 0.01; u1 = (col + 1) / NCOLS - 0.01
        seg = 3; prev = None
        for j in range(seg + 1):
            f = j / seg
            w = 0.0017 * (1 - f) + 0.0004 * f
            p = root + lash_dir * (LASH_LEN * f) + up * (0.0016 * f * f)  # slight upward curl
            A = bm.verts.new(p + side * w); B = bm.verts.new(p - side * w)
            vrow = 1.0 - f
            if prev is not None:
                face = bm.faces.new((prev[0], prev[1], B, A))
                pv = 1.0 - (j - 1) / seg
                for loop in face.loops:
                    vert = loop.vert
                    uu = u0 if (vert == prev[0] or vert == A) else u1
                    vv = pv if (vert == prev[0] or vert == prev[1]) else vrow
                    loop[uvl].uv = (uu, vv)
            prev = (A, B)
    me = bpy.data.meshes.new(name); bm.normal_update(); bm.to_mesh(me); bm.free()
    me.materials.append(lash_mat)
    o = bpy.data.objects.new(name, me); bpy.context.scene.collection.objects.link(o)
    return o
for side_name, center in SOCKETS.items():
    eye_objs.append(build_lashes(center + Vector((0.0, EYE_RECESS, 0.0)), EYE_R, "Lash_%s" % side_name))
print("[export] added eyelashes")

# NOTE: eyebrows are now built as alpha CARDS in build_vitruvian_hair.py (from the
# eyebrow guide-strand npz), not the flat Vitruvian-EyeBrows mesh — so we no longer
# append it here.

# Export head + eyes.
bpy.ops.object.select_all(action='DESELECT')
obj.select_set(True)
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
