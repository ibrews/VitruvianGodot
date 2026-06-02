# Build scalp hair as proper UV-mapped HAIR CARDS (not solid ribbons) from a
# CharMorph hairstyle's guide strands (hairstyles/*.npz), textured with the
# procedural strand atlas (vit_hair_atlas.png) via the repo hair_card.gdshader
# (use_red_mask) → each card shows a clump of fine alpha strands.
#
# Also builds an eyebrow card set the same way (from the eyebrow npz).
# Run: blender --background --python build_vitruvian_hair.py -- <Style>
import bpy, bmesh, os, sys, math
import numpy as np
from mathutils import Vector

STYLE = sys.argv[-1] if "--" in sys.argv else "Eve"
# Clip strands draping over the face (framing-locks trick) — for long styles only.
CLIP_FACE = STYLE in ("Eve", "Back1", "SceneHair_1_O4saken", "Bob")
VDIR = r"C:\Users\Sam\AppData\Roaming\Blender Foundation\Blender\4.5\scripts\addons\CharMorph\data\characters\Vitruvian"
OUT = r"H:/Work01/VitruvianGodot/godot_project"
HAIRDIR = os.path.join(VDIR, "hairstyles")
NCOLS = 4
HEAD_C = Vector((0.0, -0.02, 1.66))


def load_strands(npz, point_step):
    z = np.load(os.path.join(HAIRDIR, npz), allow_pickle=True)
    cnt = z["cnt"].astype(int); data = z["data"].astype(float)
    out = []; off = 0
    for c in cnt:
        if c >= 2:
            st = data[off:off + c]
            if point_step > 1 and c > 3:
                idx = list(range(0, c, point_step))
                if idx[-1] != c - 1: idx.append(c - 1)
                st = st[idx]
            out.append(st)
        off += c
    return out


def clip_over_face(strands):
    # FRAMING-LOCKS trick: a long style (Eve) drapes strands DOWN OVER THE FACE,
    # which read as a flat curtain. Truncate each strand at the first point that
    # enters the face box (centred, forward, below the hairline) so the face stays
    # clear — while strands that flow back / down the SIDES never enter the box and
    # keep their full length as locks that hang against the background (those read
    # as real strands far better than a scalp-hugging cap). Blender Z-up coords.
    out = []
    for st in strands:
        keep = []
        for p in st:
            x, y, zz = float(p[0]), float(p[1]), float(p[2])
            over_face = (abs(x) < 0.072) and (y < -0.030) and (1.30 < zz < 1.665)
            if over_face:
                break          # stop the strand at the hairline / face boundary
            keep.append(p)
        if len(keep) >= 2:
            out.append(np.array(keep))
    return out


def build_cards(strands, stride, w_root, w_tip, roll_max, name, wisp_ext=0.0):
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new("UVMap")

    def h(n):  # deterministic pseudo-random in [0,1)
        x = math.sin(n * 12.9898) * 43758.5453
        return x - math.floor(x)

    made = 0
    for si in range(0, len(strands), stride):
        P = [Vector(p) for p in strands[si]]
        if len(P) >= 2 and wisp_ext > 0.0:
            # Extend the strand past its tip with a couple of fine flyaway points
            # (breaks the smooth helmet silhouette into wisps; these map to the
            # fine, mostly-transparent top of the atlas).
            tip_dir = (P[-1] - P[-2])
            seg = tip_dir.length
            tip_dir = tip_dir.normalized() if seg > 1e-7 else Vector((0, 0, 1))
            jitter = Vector((h(si * 3.1) - 0.5, h(si * 5.7) - 0.5, h(si * 7.3) - 0.5)) * seg * 0.4
            P.append(P[-1] + tip_dir * seg * (1.0 + wisp_ext) + jitter)
            P.append(P[-1] + tip_dir * seg * wisp_ext + jitter * 0.5)
        n = len(P)
        if n < 2:
            continue
        col = si % NCOLS
        u0 = col / NCOLS + 0.01
        u1 = (col + 1) / NCOLS - 0.01
        roll = (h(si) * 2 - 1) * roll_max
        radial = (P[0] - HEAD_C)
        radial = radial.normalized() if radial.length > 1e-6 else Vector((0, 1, 0))
        prev = None
        for i in range(n):
            t = (P[1] - P[0]) if i == 0 else (P[n - 1] - P[n - 2]) if i == n - 1 else (P[i + 1] - P[i - 1])
            t = t.normalized() if t.length > 1e-7 else Vector((0, 0, 1))
            s = t.cross(radial)
            if s.length < 1e-6:
                s = t.cross(Vector((1, 0, 0)))
            s = s.normalized()
            s = (math.cos(roll) * s + math.sin(roll) * t.cross(s)).normalized()
            frac = i / (n - 1)
            w = w_root * (1 - frac) + w_tip * frac
            a = bm.verts.new(P[i] + s * w)
            b = bm.verts.new(P[i] - s * w)
            vrow = 1.0 - frac     # root→V1 (dense atlas bottom), tip→V0 (fine top)
            if prev is not None:
                f = bm.faces.new((prev[0], prev[1], b, a))
                pv = 1.0 - (i - 1) / (n - 1)
                for loop in f.loops:
                    vert = loop.vert
                    uu = u0 if (vert == prev[0] or vert == a) else u1
                    vv = pv if (vert == prev[0] or vert == prev[1]) else vrow
                    loop[uvl].uv = (uu, vv)
            prev = (a, b)
        made += 1

    me = bpy.data.meshes.new(name)
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    me.materials.append(bpy.data.materials.new(name + "Mat"))
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    print("[hair] %s: cards=%d verts=%d polys=%d" % (name, made, len(me.vertices), len(me.polygons)))
    return obj


bpy.ops.wm.read_factory_settings(use_empty=True)

# Short, dense, COMBED styles (Combover/SlickedBack) hug the scalp and never drape
# the face → no alpha "waterline" zigzag, and the combed flow reads beautifully with
# the shader's anisotropic strand-flow specular. (Eve = long hair that curtains the
# face, which is what produced the helmet + hard hairline.)
_hair_strands = load_strands(STYLE + ".npz", 2)
if CLIP_FACE:
    _n0 = len(_hair_strands)
    _hair_strands = clip_over_face(_hair_strands)
    print("[hair] clip_over_face: %d → %d strands" % (_n0, len(_hair_strands)))
TARGET_CARDS = 1600
_stride = max(1, len(_hair_strands) // TARGET_CARDS)
print("[hair] style=%s strands=%d stride=%d (~%d cards)" % (STYLE, len(_hair_strands), _stride, len(_hair_strands) // _stride))
hair = build_cards(_hair_strands, stride=_stride,
                   w_root=0.0050, w_tip=0.0010, roll_max=0.6, name="VitHair", wisp_ext=0.25)
brows = build_cards(load_strands("mind_eyebrows_11_Default.npz", 1), stride=4,
                    w_root=0.0016, w_tip=0.0006, roll_max=0.30, name="VitBrowCards")

objs = [hair, brows]
bpy.ops.object.select_all(action='DESELECT')
for o in objs:
    o.select_set(True)
bpy.context.view_layer.objects.active = hair
glb = os.path.join(OUT, "vitruvian_hair.glb")
bpy.ops.export_scene.gltf(filepath=glb, export_format='GLB', use_selection=True,
    export_apply=True, export_yup=True, export_normals=True, export_materials='EXPORT')
print("[hair] wrote", glb)
