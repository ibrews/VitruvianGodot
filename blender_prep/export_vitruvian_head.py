# Vitruvian head finished pass v3 — fixes blank-white eyes by splitting the eye
# by ORIGINAL material index and dropping the clear cornea/aqueous shells that
# occlude the iris. Surfaces: skin, sclera, mouth, iris, pupil (+ eyebrow mesh).
#
# Original eye material indices (config order): 3=AqueosLayer 4=Pupil
# 5=Sclera_Cornea 6=Iris. The frontal cap of 5 (center.y > CORNEA_Y) is the clear
# cornea dome → delete; the rest of 5 is the white sclera bowl → keep.
import bpy, bmesh, os, math
import numpy as np

OUT = "H:/Work01/MetaHumanGodot/out/vitruvian_spike"
os.makedirs(OUT, exist_ok=True)
VDIR = os.path.dirname(bpy.data.filepath)
DATA = os.path.join(VDIR, "textures", "4K")
EYEBROWS_BLEND = os.path.join(VDIR, "eyebrows.blend")
NECK_CUT_Z = 1.49
TEX_SIZE = 2048
SKIN_TONE = 0.45
# Camera-facing front is -Y (verified empirically). Keep the full sclera sphere
# (white eyeball); drop only the clear aqueous layer; push iris+pupil toward the
# camera (-Y) so they sit proud of the eyeball and read as a real iris.
IRIS_PUSH = -0.016

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

# Snapshot ORIGINAL per-poly material index (encodes Aqueous/Pupil/Cornea/Iris).
orig_idx = [p.material_index for p in me.polygons]
centers = [p.center.copy() for p in me.polygons]

# New slots: 0 skin, 1 sclera, 2 mouth, 3 iris, 4 pupil, 5 = DELETE marker.
me.materials.clear()
for nm in ("VitSkin", "VitSclera", "VitMouth", "VitIris", "VitPupil", "VitDelete"):
    me.materials.append(bpy.data.materials.new(nm))
uvl = me.uv_layers[udim].data
DEL = 5
for i, poly in enumerate(me.polygons):
    u, v = uvl[poly.loop_indices[0]].uv
    tile = 1001 + int(math.floor(u)) + 10 * int(math.floor(v))
    oi = orig_idx[i]
    slot = 0
    if tile == 1001:
        slot = 0
    elif tile == 1006:
        slot = 2
    elif tile == 1007:
        slot = 3  # iris
    elif tile == 1005:
        if oi == 3:           # AqueosLayer → drop (clear fluid)
            slot = DEL
        elif oi == 4:         # Pupil
            slot = 4
        elif oi == 5:         # Sclera_Cornea → keep whole as white eyeball
            slot = 1
        else:
            slot = 1
    poly.material_index = slot

# Delete cornea/aqueous faces, then loose verts, then the body below the neck.
bm = bmesh.new(); bm.from_mesh(me)
bm.faces.ensure_lookup_table()
del_faces = [f for f in bm.faces if f.material_index == DEL]
bmesh.ops.delete(bm, geom=del_faces, context='FACES')
bm.verts.ensure_lookup_table()
loose = [v for v in bm.verts if not v.link_faces]
bmesh.ops.delete(bm, geom=loose, context='VERTS')
bm.verts.ensure_lookup_table()
bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.z < NECK_CUT_Z], context='VERTS')
bm.to_mesh(me); bm.free(); me.update()
print("[export] head verts:", len(me.vertices), "polys:", len(me.polygons))

# Nudge iris (slot 3) + pupil (slot 4) forward into the opened aperture so they
# sit proud of the sclera rim and read from the front.
iris_pupil_verts = set()
for poly in me.polygons:
    if poly.material_index in (3, 4):
        for vi in poly.vertices:
            iris_pupil_verts.add(vi)
for vi in iris_pupil_verts:
    me.vertices[vi].co.y += IRIS_PUSH
me.update()
print("[export] pushed %d iris/pupil verts forward by %.3f" % (len(iris_pupil_verts), IRIS_PUSH))

# Append eyebrow groom.
with bpy.data.libraries.load(EYEBROWS_BLEND) as (src, dst):
    dst.objects = ["Vitruvian-EyeBrows"]
brow = None
for o in dst.objects:
    if o:
        bpy.context.scene.collection.objects.link(o); brow = o
if brow:
    brow.data.materials.clear()
    brow.data.materials.append(bpy.data.materials.new("VitBrows"))

bpy.ops.object.select_all(action='DESELECT')
obj.select_set(True)
if brow: brow.select_set(True)
bpy.context.view_layer.objects.active = obj
glb = os.path.join(OUT, "vitruvian_head.glb")
bpy.ops.export_scene.gltf(filepath=glb, export_format='GLB', use_selection=True,
    export_apply=True, export_yup=True, export_materials='EXPORT',
    export_normals=True, export_tangents=True, export_texcoords=True)
print("[export] wrote", glb)

# ---- textures (same as v2) ----
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
    return np.where(c <= 0.0031308, c * 12.92, (1 + a) * np.power(np.clip(c, 0, None), 1/2.4) - a)
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
    print("[tex] wrote", os.path.basename(path), w, "x", h, "mean", round(float(u8.mean()), 1))

light = exr(os.path.join(DATA, "skin_light_col.1001.exr"), TEX_SIZE)
dark  = exr(os.path.join(DATA, "skin_dark_col.1001.exr"), TEX_SIZE)
save_png(light * (1 - SKIN_TONE) + dark * SKIN_TONE, os.path.join(OUT, "vit_face_bc.png"), True)
crc = exr(os.path.join(DATA, "skin_cavity_rough_coat.1001.exr"), TEX_SIZE)
save_png(np.repeat(crc[..., 1:2], 3, 2), os.path.join(OUT, "vit_face_rough.png"), False)
disp = exr(os.path.join(DATA, "skin_disp.1001.exr"), TEX_SIZE)[..., 0]
gy, gx = np.gradient(disp.astype(np.float32))
nx, ny, nz = -gx * 6.0, -gy * 6.0, np.ones_like(disp)
ln = np.sqrt(nx*nx + ny*ny + nz*nz)
save_png(np.dstack([nx/ln*0.5+0.5, ny/ln*0.5+0.5, nz/ln*0.5+0.5]), os.path.join(OUT, "vit_face_n.png"), False)
save_png(exr(os.path.join(DATA, "sclera_col.1005.exr"), 1024), os.path.join(OUT, "vit_sclera.png"), True)
save_png(exr(os.path.join(DATA, "iris_col.1007.exr"), 1024), os.path.join(OUT, "vit_iris.png"), True)
save_png(exr(os.path.join(DATA, "mouth_col.1006.exr"), 1024), os.path.join(OUT, "vit_mouth.png"), True)
print("[export] DONE")
