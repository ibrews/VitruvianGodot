import bpy, traceback
LOG=r"H:/Work01/VitruvianGodot/blender_prep/hairtool_out/investigate.log"; _l=[]
def log(*a):
    s=" ".join(str(x) for x in a); print("HTINV:",s); _l.append(s)
try:
    log("=== file", bpy.data.filepath)
    log("objects:")
    for o in bpy.data.objects:
        info=f"  {o.name} [{o.type}]"
        if o.type=='MESH':
            me=o.data
            sk = me.shape_keys
            nsk = len(sk.key_blocks) if sk else 0
            co=[v.co for v in me.vertices]
            zs=[c.z for c in co]
            info+=f" verts={len(me.vertices)} shapekeys={nsk} vgroups={len(o.vertex_groups)} Zrange=({min(zs):.2f},{max(zs):.2f})" if co else f" verts=0 shapekeys={nsk}"
            info+=f" mats={[ (m.name if m else None) for m in me.materials]}"
        if o.type=='ARMATURE':
            info+=f" bones={len(o.data.bones)}"
        info+=f" modifiers={[m.type for m in o.modifiers]}"
        log(info)
    # detail shape keys on the main body mesh
    body=bpy.data.objects.get("cm_vitruvian") or next((o for o in bpy.data.objects if o.type=='MESH'), None)
    if body and body.data.shape_keys:
        names=[kb.name for kb in body.data.shape_keys.key_blocks]
        log(f"=== {body.name} shapekeys ({len(names)}):")
        for n in names[:80]: log("   "+n)
    # armatures
    arms=[o for o in bpy.data.objects if o.type=='ARMATURE']
    log("armatures:", [a.name for a in arms])
    for a in arms:
        log(f"  {a.name} bones:", [b.name for b in a.data.bones][:60])
    # actions/animations
    log("actions:", [a.name for a in bpy.data.actions])
    open(LOG,"w",encoding="utf-8").write("\n".join(_l))
except Exception as e:
    log("FAIL", repr(e)); traceback.print_exc(); open(LOG,"w",encoding="utf-8").write("\n".join(_l))
finally:
    try: bpy.ops.wm.quit_blender()
    except: pass
