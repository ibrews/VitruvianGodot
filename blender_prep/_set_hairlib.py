import bpy
try:
    bpy.ops.preferences.addon_enable(module="hair_tool")
except Exception as e:
    print("enable:", e)
prefs = bpy.context.preferences.addons["hair_tool"].preferences
LIB = r"H:/Work01/HairTool_Library/HairLibrary_45"
# add a library path entry if not present
found = False
for lp in prefs.lib_paths:
    if lp.directory.replace("\\","/").rstrip("/").lower() == LIB.lower():
        found = True
if not found:
    item = prefs.lib_paths.add()
    item.directory = LIB
    prefs.lib_active_index = len(prefs.lib_paths) - 1
print("lib_paths now:", [lp.directory for lp in prefs.lib_paths], "active:", prefs.lib_active_index)
bpy.ops.wm.save_userpref()
print("SAVED_PREFS")
bpy.ops.wm.quit_blender()
