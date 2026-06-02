# Thoroughly inventory hair.blend + char.blend hair: ALL objects (incl. unlinked),
# meshes, curves, particle systems and their render type, collections.
import bpy
print("=== FILE:", bpy.data.filepath)
print("--- bpy.data.objects (ALL, incl unlinked) ---")
for o in bpy.data.objects:
    line = "  %-32s %s" % (o.name, o.type)
    if o.type == 'MESH':
        line += " v=%d p=%d" % (len(o.data.vertices), len(o.data.polygons))
        zs = [v.co.z for v in o.data.vertices] or [0]
        line += " Z[%.2f,%.2f]" % (min(zs), max(zs))
    elif o.type == 'CURVES':
        line += " curves=%d" % len(o.data.curves)
    elif o.type == 'CURVE':
        line += " splines=%d" % len(o.data.splines)
    if o.particle_systems:
        line += " PARTICLES=%s" % [(ps.name, ps.settings.type, ps.settings.count, ps.settings.render_type) for ps in o.particle_systems]
    print(line)
print("--- mesh datablocks (may be unlinked hairstyles) ---")
for m in bpy.data.meshes:
    print("  mesh '%s' v=%d users=%d" % (m.name, len(m.vertices), m.users))
print("--- collections ---")
for c in bpy.data.collections:
    print("  coll '%s' objs=%s" % (c.name, [o.name for o in c.objects]))
