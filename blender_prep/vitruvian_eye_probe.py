# Classify eye geometry by ORIGINAL material_index (slots are empty datablocks
# but per-poly material_index still encodes AqueosLayer/Cornea/Iris/Pupil/Sclera).
# Report per-index: poly count, mean Z, mean forward(+Y), mean radius from eye
# center — so the clear front shells (cornea/aqueous = highest +Y) are identifiable.
import bpy, math
obj = bpy.data.objects["cm_vitruvian"]
me = obj.data
uvl = me.uv_layers["VitruvianUV_UDIM"].data
# eye region verts: Z 1.60-1.66
from collections import defaultdict
agg = defaultdict(lambda: {"n":0,"z":0.0,"y":0.0,"r":0.0,"tiles":defaultdict(int)})
# eye center approx: average of eye-region verts
exs=[]; eys=[]; ezs=[]
for poly in me.polygons:
    zc = sum(me.vertices[vi].co.z for vi in poly.vertices)/len(poly.vertices)
    if 1.60 <= zc <= 1.665:
        u,v = uvl[poly.loop_indices[0]].uv
        tile = 1001 + int(math.floor(u)) + 10*int(math.floor(v))
        if tile in (1005,1007):
            c = poly.center
            exs.append(c.x); eys.append(c.y); ezs.append(c.z)
cx = sum(exs)/len(exs) if exs else 0
cy = sum(eys)/len(eys) if eys else 0
cz = sum(ezs)/len(ezs) if ezs else 0
for poly in me.polygons:
    zc = sum(me.vertices[vi].co.z for vi in poly.vertices)/len(poly.vertices)
    if not (1.60 <= zc <= 1.665):
        continue
    u,v = uvl[poly.loop_indices[0]].uv
    tile = 1001 + int(math.floor(u)) + 10*int(math.floor(v))
    if tile not in (1005,1007,1006):
        continue
    mi = poly.material_index
    c = poly.center
    a = agg[mi]
    a["n"]+=1; a["z"]+=c.z; a["y"]+=abs(c.x-cx); a["r"]+= ((c.x-cx)**2+(c.z-cz)**2)**0.5
    a["tiles"][tile]+=1
print("eye center x=%.3f y=%.3f z=%.3f"%(cx,cy,cz))
print("orig_mat_index | polys | meanZ | mean|x-cx| | meanRadius | tiles")
for mi in sorted(agg):
    a=agg[mi]; n=a["n"]
    print("  %2d | %5d | %.4f | %.4f | %.4f | %s" % (mi, n, a["z"]/n, a["y"]/n, a["r"]/n, dict(a["tiles"])))
# also report Y (forward) per index — forward dome = cornea
agg2 = defaultdict(lambda: [0,0.0,9,-9])
for poly in me.polygons:
    zc = sum(me.vertices[vi].co.z for vi in poly.vertices)/len(poly.vertices)
    if 1.60 <= zc <= 1.665:
        u,v = uvl[poly.loop_indices[0]].uv
        tile = 1001 + int(math.floor(u)) + 10*int(math.floor(v))
        if tile in (1005,1007):
            c=poly.center; mi=poly.material_index
            agg2[mi][0]+=1; agg2[mi][1]+=c.y; agg2[mi][2]=min(agg2[mi][2],c.y); agg2[mi][3]=max(agg2[mi][3],c.y)
print("orig_mat_index | polys | meanY(forward) | Ymin | Ymax  (higher Y = more frontal = cornea/aqueous)")
for mi in sorted(agg2):
    v=agg2[mi]
    print("  %2d | %5d | %.4f | %.4f | %.4f" % (mi, v[0], v[1]/v[0], v[2], v[3]))
