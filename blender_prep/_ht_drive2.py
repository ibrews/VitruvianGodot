import bpy, traceback

LOG = r"H:/Work01/VitruvianGodot/blender_prep/hairtool_out/drive2.log"
_lines = []
def log(*a):
    s = " ".join(str(x) for x in a)
    print("HTDRV:", s); _lines.append(s)
def flush():
    open(LOG,"w",encoding="utf-8").write("\n".join(_lines))

def view3d_override():
    win = bpy.context.window_manager.windows[0]
    for area in win.screen.areas:
        if area.type == 'VIEW_3D':
            region = next((r for r in area.regions if r.type=='WINDOW'), None)
            return dict(window=win, screen=win.screen, area=area, region=region)
    return dict(window=win, screen=win.screen)

try:
    bpy.ops.preferences.addon_enable(module="hair_tool")
    log("blender", bpy.app.version_string)
    guides = bpy.data.objects.get("VitEveGuides")
    head = bpy.data.objects.get("cm_vitruvian")
    log("objects before", [(o.name,o.type) for o in bpy.data.objects])

    for o in bpy.data.objects: o.select_set(False)
    guides.select_set(True)
    bpy.context.view_layer.objects.active = guides
    ov = view3d_override()

    try:
        with bpy.context.temp_override(**ov):
            res = bpy.ops.hair_system.convert_to_mesh()
        log("convert_to_mesh ->", res)
    except Exception as e:
        log("convert_to_mesh FAIL", repr(e)); traceback.print_exc()

    log("objects after", [(o.name,o.type) for o in bpy.data.objects])
    log("active after", bpy.context.view_layer.objects.active)

    # find the card mesh: a MESH that isn't the head
    cards = [o for o in bpy.data.objects if o.type=='MESH' and o.name != 'cm_vitruvian']
    log("card mesh candidates", [o.name for o in cards])
    for c in cards:
        me = c.data
        log(f"  {c.name}: verts {len(me.vertices)} polys {len(me.polygons)} uv {[l.name for l in me.uv_layers]} mats {[m.name if m else None for m in me.materials]} colattr {[a.name for a in me.color_attributes]}")
        log(f"  {c.name}: modifiers {[(m.name,m.type) for m in c.modifiers]}")
        log(f"  {c.name}: dims {tuple(round(x,3) for x in c.dimensions)} loc {tuple(round(x,3) for x in c.location)}")

    # Export the largest card mesh to GLB (no draco)
    if cards:
        card = max(cards, key=lambda o: len(o.data.polygons))
        for o in bpy.data.objects: o.select_set(False)
        card.select_set(True)
        bpy.context.view_layer.objects.active = card
        out_glb = r"H:/Work01/VitruvianGodot/blender_prep/hairtool_out/hairtool_cards.glb"
        try:
            bpy.ops.export_scene.gltf(
                filepath=out_glb, export_format='GLB',
                use_selection=True, export_apply=True,
                export_draco_mesh_compression_enable=False,
                export_yup=True,
            )
            log("exported GLB", out_glb, "from", card.name, "polys", len(card.data.polygons))
        except Exception as e:
            log("GLB export FAIL", repr(e)); traceback.print_exc()

    bpy.ops.wm.save_as_mainfile(filepath=r"H:/Work01/VitruvianGodot/blender_prep/hairtool_work2.blend")
    log("saved work2")
except Exception as e:
    log("TOP FAIL", repr(e)); traceback.print_exc()
finally:
    flush()
    try: bpy.ops.wm.quit_blender()
    except Exception: pass
