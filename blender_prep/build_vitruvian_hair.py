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


def build_cards(strands, stride, w_root, w_tip, roll_max, name):
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new("UVMap")

    def h(n):  # deterministic pseudo-random in [0,1)
        x = math.sin(n * 12.9898) * 43758.5453
        return x - math.floor(x)

    made = 0
    for si in range(0, len(strands), stride):
        P = [Vector(p) for p in strands[si]]
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

hair = build_cards(load_strands(STYLE + ".npz", 2), stride=1,
                   w_root=0.0075, w_tip=0.0024, roll_max=0.6, name="VitHair")
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
