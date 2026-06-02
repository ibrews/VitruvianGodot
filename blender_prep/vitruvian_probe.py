# Probe the Vitruvian char.blend: list objects, the base mesh's verts/UVs/
# shape-keys/materials/bounds, and which UDIM tiles the head occupies.
# Run: blender --background char.blend --python vitruvian_probe.py
import bpy, math

print("\n========== VITRUVIAN PROBE ==========")
print("Objects in file:")
for o in bpy.data.objects:
    info = "  %-28s type=%s" % (o.name, o.type)
    if o.type == 'MESH':
        info += " verts=%d polys=%d" % (len(o.data.vertices), len(o.data.polygons))
    print(info)

# Find the base char object (config char_obj: cm_vitruvian)
obj = bpy.data.objects.get("cm_vitruvian")
if obj is None:
    # fallback: largest mesh
    meshes = [o for o in bpy.data.objects if o.type == 'MESH']
    obj = max(meshes, key=lambda o: len(o.data.vertices)) if meshes else None
print("\nBASE OBJ:", obj.name if obj else None)
if obj:
    me = obj.data
    print("  verts=%d polys=%d" % (len(me.vertices), len(me.polygons)))
    print("  UV layers:", [uv.name for uv in me.uv_layers])
    print("  materials:", [ (i, (m.name if m else None)) for i,m in enumerate(me.materials)])
    print("  modifiers:", [(m.name, m.type) for m in obj.modifiers])
    # shape keys
    if me.shape_keys:
        kb = me.shape_keys.key_blocks
        print("  shape_keys: %d total. first 20:" % len(kb))
        for k in list(kb)[:20]:
            print("     ", k.name)
    else:
        print("  shape_keys: none")
    # bounds (local)
    xs=[v.co.x for v in me.vertices]; ys=[v.co.y for v in me.vertices]; zs=[v.co.z for v in me.vertices]
    print("  local bounds X[%.3f,%.3f] Y[%.3f,%.3f] Z[%.3f,%.3f]" % (min(xs),max(xs),min(ys),max(ys),min(zs),max(zs)))
    print("  world scale:", tuple(round(s,4) for s in obj.scale), "dims:", tuple(round(d,3) for d in obj.dimensions))

    # UDIM tile usage: for each polygon, which UDIM tile (1001+ floor(u)+10*floor(v))
    # Also detect head verts (top ~18% of Z) and which tiles their UVs land in.
    if me.uv_layers:
        uvl = me.uv_layers.active.data
        from collections import Counter
        tile_counter = Counter()
        zmin,zmax=min(zs),max(zs); zr=zmax-zmin
        head_z_cut = zmin + 0.80*zr   # head/neck region (upper 20%)
        head_tiles = Counter()
        for poly in me.polygons:
            # tile from first loop uv
            li = poly.loop_indices[0]
            u,v = uvl[li].uv
            tile = 1001 + int(math.floor(u)) + 10*int(math.floor(v))
            tile_counter[tile]+=1
            # is this poly in the head region?
            zc = sum(me.vertices[vi].co.z for vi in poly.vertices)/len(poly.vertices)
            if zc >= head_z_cut:
                head_tiles[tile]+=1
        print("  UDIM tile -> poly count (all):", dict(tile_counter))
        print("  UDIM tile -> poly count (HEAD region upper 20%% Z):", dict(head_tiles))
print("========== END PROBE ==========\n")
