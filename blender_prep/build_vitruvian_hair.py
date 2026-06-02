# Build a renderable scalp-hair mesh from a CharMorph Vitruvian hairstyle .npz
# (guide strands), densified with jittered children, as cross-section ribbons so
# it reads from any angle. Exports vitruvian_hair.glb (Y-up) co-located with the
# head. Run: blender --background --python build_vitruvian_hair.py -- <Style>
import bpy, bmesh, os, sys, math
import numpy as np
from mathutils import Vector

STYLE = sys.argv[-1] if "--" in sys.argv else "Eve"
VDIR = r"C:\Users\Sam\AppData\Roaming\Blender Foundation\Blender\4.5\scripts\addons\CharMorph\data\characters\Vitruvian"
OUT = "H:/Work01/MetaHumanGodot/out/vitruvian_spike"
NPZ = os.path.join(VDIR, "hairstyles", STYLE + ".npz")

CHILDREN = 8          # interpolated children per guide
CHILD_JITTER = 0.005  # m, root scatter
WIDTH_ROOT = 0.0020   # ribbon half-width at root (m)
WIDTH_TIP = 0.0006    # at tip
POINT_STEP = 2        # subsample strand points → fewer segments, same coverage (smaller GLB)
HEAD_C = Vector((0.0, -0.02, 1.66))  # approx head center for outward orientation

z = np.load(NPZ, allow_pickle=True)
cnt = z["cnt"].astype(int)
data = z["data"].astype(float)
# split into strands
strands = []
off = 0
for c in cnt:
    if c >= 2:
        st = data[off:off + c]
        if POINT_STEP > 1 and c > 3:
            idx = list(range(0, c, POINT_STEP))
            if idx[-1] != c - 1:
                idx.append(c - 1)        # always keep the tip
            st = st[idx]
        strands.append(st.copy())
    off += c
print("[hair] style=%s guides=%d points=%d" % (STYLE, len(strands), len(data)))

# fresh scene
bpy.ops.wm.read_factory_settings(use_empty=True)
me = bpy.data.meshes.new("VitruvianHair")
bm = bmesh.new()

def add_ribbon(pts, half_w_root, half_w_tip):
    n = len(pts)
    P = [Vector(p) for p in pts]
    # tangents
    tans = []
    for i in range(n):
        if i == 0: t = P[1] - P[0]
        elif i == n - 1: t = P[n - 1] - P[n - 2]
        else: t = P[i + 1] - P[i - 1]
        if t.length < 1e-7: t = Vector((0, 0, 1))
        tans.append(t.normalized())
    # outward radial at root → orient one ribbon plane to face outward
    radial = (P[0] - HEAD_C)
    radial = radial.normalized() if radial.length > 1e-6 else Vector((0, 1, 0))
    # two perpendicular width directions per point (cross-section X)
    for axis in range(2):
        loops = []
        prev = None
        for i in range(n):
            t = tans[i]
            s = t.cross(radial)
            if s.length < 1e-6: s = t.cross(Vector((1, 0, 0)))
            s.normalize()
            if axis == 1:
                s = t.cross(s).normalized()
            w = half_w_root * (1 - i / (n - 1)) + half_w_tip * (i / (n - 1))
            a = bm.verts.new(P[i] + s * w)
            b = bm.verts.new(P[i] - s * w)
            if prev is not None:
                bm.faces.new((prev[0], prev[1], b, a))
            prev = (a, b)

rng_state = 12345
def jitter(seed):
    # deterministic small offset
    x = math.sin(seed * 12.9898) * 43758.5453
    y = math.sin(seed * 78.233) * 43758.5453
    zc = math.sin(seed * 37.719) * 43758.5453
    f = lambda v: (v - math.floor(v)) * 2 - 1
    return Vector((f(x), f(y), f(zc)))

sidx = 0
for st in strands:
    add_ribbon(st, WIDTH_ROOT, WIDTH_TIP)
    # children: copy with a small root-anchored offset that decays toward tip
    for k in range(CHILDREN):
        off_v = np.array(jitter(sidx * 7 + k * 101)) * CHILD_JITTER
        child = st + off_v[None, :] * np.linspace(1.0, 0.3, len(st))[:, None]
        add_ribbon(child, WIDTH_ROOT * 0.7, WIDTH_TIP * 0.7)
    sidx += 1

bm.normal_update()
bm.to_mesh(me)
bm.free()
obj = bpy.data.objects.new("VitruvianHair", me)
mat = bpy.data.materials.new("VitHair")
me.materials.append(mat)
bpy.context.scene.collection.objects.link(obj)
print("[hair] verts=%d polys=%d" % (len(me.vertices), len(me.polygons)))

bpy.ops.object.select_all(action='DESELECT')
obj.select_set(True)
bpy.context.view_layer.objects.active = obj
glb = os.path.join(OUT, "vitruvian_hair.glb")
# Stock Godot 4.6 can't decode Draco glTF → keep mesh uncompressed; control size
# via strand point subsampling (POINT_STEP) instead.
bpy.ops.export_scene.gltf(filepath=glb, export_format='GLB', use_selection=True,
    export_apply=True, export_yup=True, export_normals=True, export_materials='EXPORT')
print("[hair] wrote", glb)
