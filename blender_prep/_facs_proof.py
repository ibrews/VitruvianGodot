## Proof: apply the REAL Vitruvian FACS morphs (morphs/L3/*.npz = idx+delta on the
## 39168-vert cm_vitruvian) as shape keys and render — does Jaw_Lower / Mouth_Large_Opened
## open the mouth WITH the real teeth/tongue, and do Happy/Smile read? Read-only render.
import bpy, os, math
import numpy as np
from mathutils import Vector
L3 = r"C:/Users/Sam/AppData/Roaming/Blender Foundation/Blender/4.5/scripts/addons/CharMorph/data/characters/Vitruvian/morphs/L3"
RD = r"H:/Work01/VitruvianGodot/out"
obj = bpy.data.objects["cm_vitruvian"]
me = obj.data
nv = len(me.vertices)
print("verts", nv)

def load_delta(name):
    z = np.load(os.path.join(L3, name + ".npz"), allow_pickle=True)
    idx = z["idx"].astype(int); d = z["delta"].astype(float)
    full = np.zeros((nv, 3)); full[idx] = d
    return full

WANT = ["Jaw_Lower", "Mouth_Large_Opened", "Smile_Lips_Closed", "Happy", "Eyes_Closed_Max", "Eyebrows_Raised_Left"]
base = np.array([v.co for v in me.vertices])
obj.shape_key_add(name="Basis", from_mix=False)
for nm in WANT:
    try:
        full = load_delta(nm)
        kb = obj.shape_key_add(name=nm, from_mix=False)
        moved = 0
        for i in range(nv):
            o = full[i]
            if o[0] or o[1] or o[2]:
                kb.data[i].co = Vector(base[i]) + Vector(o); moved += 1
        print("baked", nm, "moved", moved)
    except Exception as e:
        print("FAIL", nm, e)

# render front, workbench, per expression
scn = bpy.context.scene
scn.render.engine = 'BLENDER_WORKBENCH'
scn.render.resolution_x = 440; scn.render.resolution_y = 560
cam = bpy.data.objects.get("Camera")
if cam is None:
    cd = bpy.data.cameras.new("Camera"); cam = bpy.data.objects.new("Camera", cd); scn.collection.objects.link(cam)
cam.location = (0.0, -0.42, 1.60); cam.rotation_euler = (math.pi/2, 0, 0); cam.data.lens = 52; scn.camera = cam
kb = obj.data.shape_keys.key_blocks
EXPR = {"neutral": {}, "Jaw_Lower": {"Jaw_Lower": 1.0}, "Mouth_Large_Opened": {"Mouth_Large_Opened": 1.0},
        "Smile": {"Smile_Lips_Closed": 1.0}, "Happy": {"Happy": 1.0}}
for nm, d in EXPR.items():
    for k in kb: k.value = 0.0
    for n, v in d.items():
        if n in kb: kb[n].value = v
    scn.render.filepath = os.path.join(RD, "facs_%s.png" % nm)
    bpy.ops.render.render(write_still=True)
    print("rendered", nm)
try: bpy.ops.wm.quit_blender()
except: pass
