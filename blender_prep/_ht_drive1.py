import bpy, sys, traceback, numpy as np

LOG = r"H:/Work01/VitruvianGodot/blender_prep/hairtool_out/drive1.log"
_lines = []
def log(*a):
    s = " ".join(str(x) for x in a)
    print("HTDRV:", s)
    _lines.append(s)
def flush():
    with open(LOG, "w", encoding="utf-8") as f:
        f.write("\n".join(_lines))

def view3d_override():
    win = bpy.context.window_manager.windows[0]
    for area in win.screen.areas:
        if area.type == 'VIEW_3D':
            region = next((r for r in area.regions if r.type == 'WINDOW'), None)
            return dict(window=win, screen=win.screen, area=area, region=region)
    return dict(window=win, screen=win.screen)

try:
    log("blender", bpy.app.version_string)
    try:
        bpy.ops.preferences.addon_enable(module="hair_tool")
        log("addon_enable ok")
    except Exception as e:
        log("addon_enable FAIL", e)

    log("objects:", [(o.name, o.type) for o in bpy.data.objects])
    guides = bpy.data.objects.get("VitEveGuides")
    head = bpy.data.objects.get("cm_vitruvian")
    log("guides:", guides, "head:", head)
    if guides:
        log("guides.type", guides.type, "surface", guides.data.surface, "uvmap", guides.data.surface_uv_map)
        log("guides curves count", len(guides.data.curves), "points", len(guides.data.points))
        log("guides modifiers", [(m.name, m.type) for m in guides.modifiers])

    # select + active
    for o in bpy.data.objects:
        o.select_set(False)
    guides.select_set(True)
    bpy.context.view_layer.objects.active = guides

    ov = view3d_override()
    log("override area", ov.get("area"))

    # Add interpolated strands hair system
    try:
        with bpy.context.temp_override(**ov):
            res = bpy.ops.object.add_hair_system(mode='INTERPOLATED_STRANDS')
        log("add_hair_system ->", res)
    except Exception as e:
        log("add_hair_system FAIL", repr(e))
        traceback.print_exc()

    # report state
    log("after: guides modifiers", [(m.name, m.type, getattr(m,'node_group',None) and m.node_group.name) for m in guides.modifiers])
    try:
        hn = guides.ht_props.hair_nodes
        log("is_using_gnodes", hn.is_using_gnodes, "n_systems", len(hn.hair_systems), "system_index", hn.system_index)
    except Exception as e:
        log("ht_props read FAIL", e)

    # evaluate output mesh
    try:
        deps = bpy.context.evaluated_depsgraph_get()
        ev = guides.evaluated_get(deps)
        me = ev.to_mesh()
        log("eval mesh verts", len(me.vertices), "polys", len(me.polygons), "uv_layers", [l.name for l in me.uv_layers], "materials", [m.name if m else None for m in me.materials])
        ev.to_mesh_clear()
    except Exception as e:
        log("eval mesh FAIL", repr(e))
        traceback.print_exc()

    # save working file
    out = r"H:/Work01/VitruvianGodot/blender_prep/hairtool_work.blend"
    bpy.ops.wm.save_as_mainfile(filepath=out)
    log("saved", out)
except Exception as e:
    log("TOP FAIL", repr(e))
    traceback.print_exc()
finally:
    flush()
    try:
        bpy.ops.wm.quit_blender()
    except Exception:
        pass
