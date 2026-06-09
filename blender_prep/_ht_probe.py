import bpy, addon_utils
try:
    bpy.ops.preferences.addon_enable(module="hair_tool")
    print("HT_ENABLED ok")
except Exception as e:
    print("HT_ENABLE_FAIL", e)
ns = [n for n in dir(bpy.ops) if 'hair' in n.lower() or n=='htool']
print("HT_NAMESPACES", ns)
for n in ns:
    ops = [d for d in dir(getattr(bpy.ops, n))]
    print("OPS[%s]"%n, ops)
# also scan all op namespaces for hair-ish operators
import io
with open(r"H:/Work01/VitruvianGodot/out/_ht_ops.txt","w") as f:
    for n in dir(bpy.ops):
        sub = getattr(bpy.ops, n)
        for d in dir(sub):
            f.write("%s.%s\n"%(n,d))
print("HT_PROBE_DONE")
bpy.ops.wm.quit_blender()
