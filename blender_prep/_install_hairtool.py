import bpy
print("Blender", bpy.app.version_string)
# install + enable the addon from the zip
bpy.ops.preferences.addon_install(filepath=r"G:/Downloads/hair_tool_4.5.7.zip", overwrite=True)
# find the module name (hair_tool variants)
import addon_utils
mods = [m.__name__ for m in addon_utils.modules()]
ht = [m for m in mods if 'hair' in m.lower()]
print("HAIR MODULES:", ht)
for m in ht:
    try:
        bpy.ops.preferences.addon_enable(module=m)
        print("ENABLED:", m)
    except Exception as e:
        print("FAIL enable", m, e)
bpy.ops.wm.save_userpref()
# verify operators present
print("has hair_grid_add:", hasattr(bpy.ops, 'object') and any('hair' in d for d in dir(bpy.ops.object)) )
print("hairtool ops:", [d for d in dir(bpy.ops.hairtool)] if hasattr(bpy.ops,'hairtool') else "no hairtool namespace")
