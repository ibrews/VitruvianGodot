import bpy, math, os, sys
from collections import Counter
out=[]
def log(*a): out.append(" ".join(str(x) for x in a)); print("T2:",*a)
A=r"C:/Users/Sam/AppData/Roaming/Blender Foundation/Blender/4.5/scripts/addons/CharMorph/data/characters/Vitruvian/assets"
# 1) body tiles (from the rigged blend's cm_vitruvian, z<1.52 like the export trim)
bpy.ops.wm.open_mainfile(filepath=r"H:/Work01/VitruvianGodot/blender_prep/vitruvian_rigged.blend")
body=bpy.data.objects["cm_vitruvian"]; me=body.data
log("uv layers:", [(uv.name, uv.active_render) for uv in me.uv_layers])
uvl=me.uv_layers["VitruvianUV_UDIM"].data if "VitruvianUV_UDIM" in me.uv_layers else me.uv_layers.active.data
cnt=Counter(); cnt_body=Counter()
for poly in me.polygons:
    u,v=uvl[poly.loop_indices[0]].uv
    tile=1001+int(math.floor(u))+10*int(math.floor(v))
    cnt[tile]+=1
    zc=sum((me.vertices[vi].co.z for vi in poly.vertices))/len(poly.vertices)
    if zc<1.52: cnt_body[tile]+=1
log("ALL tiles:", dict(cnt))
log("BODY(z<1.52) tiles:", dict(cnt_body))
# 2) asset blends
for bl in ("Tearline.blend","Lacrimal_Caruncle.blend"):
    with bpy.data.libraries.load(os.path.join(A,bl), link=False) as (df,dt):
        dt.objects=list(df.objects)
    for o in bpy.data.objects:
        if o.library is None and o.name not in ("cm_vitruvian",) and o.type=='MESH' and o.data.users>=1:
            pass
    # report just-loaded
    log(bl, "objects:", [(o.name,o.type) for o in dt.objects if o])
    for o in dt.objects:
        if o and o.type=='MESH':
            bb=[o.matrix_world @ __import__('mathutils').Vector(c) for c in o.bound_box]
            xs=[v.x for v in bb]; ys=[v.y for v in bb]; zs=[v.z for v in bb]
            log("  ",o.name,"verts",len(o.data.vertices),"mats",[m.name if m else "?" for m in o.data.materials],
                "bbox x[%.4f,%.4f] y[%.4f,%.4f] z[%.4f,%.4f]"%(min(xs),max(xs),min(ys),max(ys),min(zs),max(zs)),
                "uv",[uv.name for uv in o.data.uv_layers], "shapekeys", o.data.shape_keys.key_blocks.keys() if o.data.shape_keys else None)
open(r"H:/Work01/VitruvianGodot/blender_prep/hairtool_out/t2_probe.log","w").write("\n".join(out))
