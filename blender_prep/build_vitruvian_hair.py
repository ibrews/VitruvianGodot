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
NCHILD = 6   # child hairs per guide (bulk); 0 = guides only
VDIR = r"C:\Users\Sam\AppData\Roaming\Blender Foundation\Blender\4.5\scripts\addons\CharMorph\data\characters\Vitruvian"
OUT = r"H:/Work01/VitruvianGodot/godot_project"
HAIRDIR = os.path.join(VDIR, "hairstyles")
NCOLS = 4
HEAD_C = Vector((0.0, -0.02, 1.66))
FLOOR_Z = 1.44   # neck line — no hair card extends below this (keeps hair off the chest/body)


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


def make_children(strands, k, root_spread=0.006, tip_spread=0.012, seed=5):
    # Real particle hair gets its BULK from child hairs interpolated around each
    # guide. We fake that: per guide, add k jittered copies offset by a random
    # root vector (spreads roots to fill gaps between sparse guides) plus a larger
    # tip vector that grows along the strand (so children fan out toward the ends).
    rng = np.random.RandomState(seed)
    out = []
    for st in strands:
        out.append(st)
        n = len(st)
        tparam = (np.arange(n) / (n - 1))[:, None]
        for _ in range(k):
            ro = (rng.rand(3) - 0.5) * 2 * root_spread
            tip = (rng.rand(3) - 0.5) * 2 * tip_spread
            out.append(st + ro + tip * tparam)
    return out


def add_crown_volume(strands, amount=0.016, cell=0.014, z_min=1.655):
    # THE anti-helmet fix for the crown. Crown cards lie flat on the scalp dome →
    # a smooth painted shell. Push crown-rooted strands OUTWARD along the radial,
    # by a per-CLUMP amount (coherent within ~`cell`-sized patches) that grows
    # toward the tip → the top breaks into 3D locks that stand proud, with shadow
    # gaps to the dark scalp between them. Relief survives at any distance, unlike
    # the minifying atlas detail. Side/back strands (already voluminous) untouched.
    hc = np.array([HEAD_C[0], HEAD_C[1], HEAD_C[2]])
    out = []
    for st in strands:
        r = st[0]
        if r[2] < z_min:
            out.append(st); continue
        key = (round(r[0] / cell), round(r[1] / cell), round(r[2] / cell))
        # deterministic per-clump height 0..1 (two frequencies → varied locks)
        h = 0.5 * (math.sin(key[0] * 12.9 + key[1] * 78.2 + key[2] * 37.7) * 0.5 + 0.5) \
            + 0.5 * (math.sin(key[0] * 5.1 - key[1] * 3.7 + key[2] * 9.3) * 0.5 + 0.5)
        radial = r - hc
        nrm = np.linalg.norm(radial)
        radial = radial / nrm if nrm > 1e-6 else np.array([0.0, 0.0, 1.0])
        push = amount * h
        n = len(st)
        st2 = st.astype(float).copy()
        for i in range(n):
            f = i / (n - 1)
            st2[i] = st[i] + radial * push * (0.45 + 0.55 * f)
        out.append(st2)
    return out


def crown_fill(strands, n_extra=900, seed=9):
    # Extra short scalp-hugging strands scattered across the CROWN so the top isn't
    # thin (Eve roots are sparse up there). Each is a clone of a random existing
    # crown-rooted guide, re-rooted at a jittered nearby scalp point — keeps the
    # local flow direction but adds root density only where the crown is bald.
    rng = np.random.RandomState(seed)
    crown = [st for st in strands if st[0][2] >= 1.66 and abs(st[0][0]) < 0.085 and st[0][1] > -0.045]
    if not crown:
        return []
    extra = []
    for _ in range(n_extra):
        st = crown[rng.randint(len(crown))]
        # short version (first ~60% of the strand) re-rooted with a small offset
        m = max(2, int(len(st) * 0.6))
        off = np.array([rng.uniform(-0.012, 0.012), rng.uniform(-0.012, 0.012), rng.uniform(-0.004, 0.004)])
        extra.append(st[:m] + off)
    return extra


def build_cards(strands, stride, w_root, w_tip, roll_max, name, wisp_ext=0.0):
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new("UVMap")

    def h(n):  # deterministic pseudo-random in [0,1)
        x = math.sin(n * 12.9898) * 43758.5453
        return x - math.floor(x)

    made = 0
    for si in range(0, len(strands), stride):
        P = [Vector(p) for p in strands[si]]
        # only wisp the LONG hanging locks (tip well below the hairline); crown / short
        # strands stay capped so the top doesn't sprout spiky flyaways.
        long_lock = len(P) >= 2 and float(P[-1].z) < 1.58 and (P[-1] - P[0]).length > 0.12
        if long_lock and wisp_ext > 0.0:
            # Extend the strand past its tip with a couple of fine flyaway points
            # (breaks the smooth helmet silhouette into wisps; these map to the
            # fine, mostly-transparent top of the atlas).
            tip_dir = (P[-1] - P[-2])
            seg = tip_dir.length
            tip_dir = tip_dir.normalized() if seg > 1e-7 else Vector((0, 0, 1))
            jitter = Vector((h(si * 3.1) - 0.5, h(si * 5.7) - 0.5, h(si * 7.3) - 0.5)) * seg * 0.4
            P.append(P[-1] + tip_dir * seg * (1.0 + wisp_ext) + jitter)
            P.append(P[-1] + tip_dir * seg * wisp_ext + jitter * 0.5)
        # neck-line floor, VARIED per strand so the ends feather across ~1.41-1.49 instead
        # of all bunching at one z (which clumps the dark tips into patches on the shoulders).
        floor_z = FLOOR_Z + (h(si * 2.7) - 0.4) * 0.09
        cut = None
        for i in range(len(P)):
            if P[i].z < floor_z:
                cut = i; break
        if cut is not None:
            P = P[:cut]
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

# TWO-LAYER scalp hair:
#  1. COVERAGE layer — dense scalp-hugging Combover so the whole CROWN/scalp is
#     covered with hair CARDS (this is what stops the bald-crown / dark-cap
#     "helmet": Eve alone is centre-parted and leaves the top bare).
#  2. FRAMING layer — long Eve locks, face-clipped, for the length that hangs and
#     frames the face.
# Both get crown volume + (Eve) children; the head-normal shader lights the whole
# mass as a rounded volume so the crown reads as hair, not a smooth shell.
# NECK-LENGTH bob: truncate every strand at the neck line so the hair ends around the
# neck/jaw and never reaches the chest — the single-chain spring rig can't do true
# per-card body collision, so short hair sidesteps the "falls into the body" problem.
def clip_length(strands, z_floor):
    # truncate each strand exactly at z_floor (interpolate the crossing point), so the
    # ends sit right at the neck line regardless of the coarse Eve point sampling.
    out = []
    for st in strands:
        keep = []
        for p in st:
            z = float(p[2])
            if z < z_floor:
                if keep:
                    pa = np.array(keep[-1]); za = float(pa[2])
                    if za > z_floor and za != z:
                        t = (za - z_floor) / (za - z)
                        keep.append(pa + (np.array(p) - pa) * t)
                break
            keep.append(np.array(p))
        if len(keep) >= 2:
            out.append(np.array(keep))
    return out

_hair_strands = clip_over_face(load_strands("Eve.npz", 2))
_hair_strands = clip_length(_hair_strands, 1.46)        # neck-length bob (ends ~neck/jaw)
_hair_strands = _hair_strands + crown_fill(_hair_strands, n_extra=1100)
_hair_strands = make_children(_hair_strands, k=12, root_spread=0.0050, tip_spread=0.012)  # denser → less polygonal
_hair_strands = add_crown_volume(_hair_strands, amount=0.010)
print("[hair] total %d strands (Eve + crown_fill + children + volume)" % len(_hair_strands))
# REGROOM: more, thinner, finer-tipped cards. Wisps applied ONLY to the long hanging
# locks (build_cards gates on tip height) so the length tapers to fine wisps while the
# crown stays a smooth capped dome — fuller silhouette, no spiky flyaways.
hair = build_cards(_hair_strands, stride=1,
                   w_root=0.0030, w_tip=0.0004, roll_max=0.95, name="VitHair", wisp_ext=0.30)
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
