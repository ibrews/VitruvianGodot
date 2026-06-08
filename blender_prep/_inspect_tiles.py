## What geometry lives in each UDIM tile of cm_vitruvian? Identify teeth / tongue /
## mouth-interior / eyes / gums that I may have been deleting. Read-only.
import bpy, math
import numpy as np
o = bpy.data.objects["cm_vitruvian"]
me = o.data
uvl = me.uv_layers.active.data
co = np.array([v.co for v in me.vertices])
print("MESH verts", len(me.vertices), "polys", len(me.polygons))
print("UV layers:", [u.name for u in me.uv_layers], "active:", me.uv_layers.active.name)

# bucket polygons by UDIM tile
from collections import defaultdict
tiles = defaultdict(list)
for poly in me.polygons:
    u, v = uvl[poly.loop_indices[0]].uv
    tile = 1001 + int(math.floor(u)) + 10 * int(math.floor(v))
    tiles[tile].append(poly.index)

def region(vidx):
    pts = co[list(vidx)]
    return pts.min(0), pts.max(0), pts.mean(0)

for tile in sorted(tiles):
    polys = tiles[tile]
    vset = set()
    for pi in polys:
        for vi in me.polygons[pi].vertices: vset.add(vi)
    lo, hi, c = region(vset)
    # guess by location: mouth interior ~ behind lips (y>-0.02, z 1.55-1.60),
    # eyes ~ z~1.63 |x|~0.033, teeth ~ small y>~ -0.01 z~1.56
    print("tile %d: faces=%5d verts=%5d  bbox x[%.3f,%.3f] y[%.3f,%.3f] z[%.3f,%.3f]  cen(%.3f,%.3f,%.3f)" % (
        tile, len(polys), len(vset), lo[0],hi[0], lo[1],hi[1], lo[2],hi[2], c[0],c[1],c[2]))

# Also: anything with 'teeth/tongue/eye' in material names?
print("MATERIALS:", [m.name for m in me.materials])
# vertex groups (rig) that hint at jaw
print("VGROUPS (jaw/teeth/tongue/eye):", [g.name for g in o.vertex_groups if any(k in g.name.lower() for k in ("jaw","teeth","tongue","eye","lip","mouth"))][:40])
try: bpy.ops.wm.quit_blender()
except: pass
