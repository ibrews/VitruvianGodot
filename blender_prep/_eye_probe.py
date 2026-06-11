import bpy, bmesh, math
from mathutils import Vector
out=[]
def log(*a): out.append(" ".join(str(x) for x in a)); print("EP:",*a)
obj=bpy.data.objects["cm_vitruvian"]
me=obj.data
uvs=me.uv_layers; uvs.active=uvs["VitruvianUV_UDIM"]
uvl=me.uv_layers["VitruvianUV_UDIM"].data
bm=bmesh.new(); bm.from_mesh(me)
bm.faces.ensure_lookup_table()
uvbm=bm.loops.layers.uv.active
def tile_of(f):
    u,v=f.loops[0][uvbm].uv
    return 1001+int(math.floor(u))+10*int(math.floor(v))
# collect faces per tile of interest
for TILE in (1005,1007):
    faces=[f for f in bm.faces if tile_of(f)==TILE]
    log("tile",TILE,"faces",len(faces))
    # connected components among these faces
    fset=set(f.index for f in faces)
    seen=set(); islands=[]
    import collections
    for f in faces:
        if f.index in seen: continue
        comp=[]; dq=collections.deque([f])
        seen.add(f.index)
        while dq:
            g=dq.popleft(); comp.append(g)
            for e in g.edges:
                for h in e.link_faces:
                    if h.index in fset and h.index not in seen:
                        seen.add(h.index); dq.append(h)
        islands.append(comp)
    log("tile",TILE,"islands",len(islands))
    for i,comp in enumerate(sorted(islands,key=lambda c:-len(c))[:12]):
        vs=set(v for f in comp for v in f.verts)
        xs=[v.co.x for v in vs]; ys=[v.co.y for v in vs]; zs=[v.co.z for v in vs]
        # uv bbox too
        us=[l[uvbm].uv.x for f in comp for l in f.loops]; vv=[l[uvbm].uv.y for f in comp for l in f.loops]
        log("  isl%d faces=%d verts=%d x[%.4f,%.4f] y[%.4f,%.4f] z[%.4f,%.4f] uv u[%.2f,%.2f] v[%.2f,%.2f]"%(
            i,len(comp),len(vs),min(xs),max(xs),min(ys),max(ys),min(zs),max(zs),min(us),max(us),min(vv),max(vv)))
open(r"H:/Work01/VitruvianGodot/blender_prep/hairtool_out/eye_probe.log","w").write("\n".join(out))
