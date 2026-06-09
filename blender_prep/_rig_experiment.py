import bpy, traceback
LOG=r"H:/Work01/VitruvianGodot/blender_prep/hairtool_out/rig_exp.log"; _l=[]
def log(*a):
    s=" ".join(str(x) for x in a); print("RIGX:",s); _l.append(s)
def flush(): open(LOG,"w",encoding="utf-8").write("\n".join(_l))
try:
    try:
        bpy.ops.preferences.addon_enable(module="CharMorph")
        log("charmorph enabled")
    except Exception as e:
        log("enable fail", e)
    obj = bpy.data.objects["cm_vitruvian"]
    # make sure object mode + active
    for o in bpy.data.objects: o.select_set(False)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    log("obj verts", len(obj.data.vertices), "charmorph_template", obj.data.get("charmorph_template"))

    # init morpher
    from CharMorph.common import manager as mm
    log("morpher before", mm.morpher)
    mm.create_charmorphs(obj)
    log("morpher after", mm.morpher, "core.obj", getattr(getattr(mm.morpher,'core',None),'obj',None))
    arm_opts = list(mm.morpher.core.char.armature.keys()) if mm.morpher and mm.morpher.core else None
    log("armature options", arm_opts)

    ui = bpy.context.window_manager.charmorph_ui
    ui.rig = "mixamo"
    log("ui.rig set to", ui.rig)

    res = bpy.ops.charmorph.rig()
    log("charmorph.rig ->", res)

    # report armatures + parenting
    arms = [o for o in bpy.data.objects if o.type=='ARMATURE']
    log("armatures:", [(a.name, len(a.data.bones)) for a in arms])
    for a in arms:
        log("  bones sample:", [b.name for b in a.data.bones][:12])
    log("cm_vitruvian parent:", obj.parent.name if obj.parent else None, "modifiers:", [(m.type,getattr(m,'object',None) and m.object.name) for m in obj.modifiers])
    log("vgroups on body now:", len(obj.vertex_groups))

    if res == {'FINISHED'} and arms:
        out = r"H:/Work01/VitruvianGodot/blender_prep/vitruvian_rigged.blend"
        bpy.ops.wm.save_as_mainfile(filepath=out)
        log("SAVED", out)
    flush()
except Exception as e:
    log("FAIL", repr(e)); traceback.print_exc(); flush()
finally:
    try: bpy.ops.wm.quit_blender()
    except: pass
