import bpy, bmesh, traceback
LOG=r"H:/Work01/VitruvianGodot/blender_prep/hairtool_out/clip.log"; _l=[]
def log(*a):
    s=" ".join(str(x) for x in a); print("HTDRV:",s); _l.append(s)
try:
    c=bpy.data.objects['VitEveGuides_converted']
    me=c.data
    bm=bmesh.new(); bm.from_mesh(me)
    bm.faces.ensure_lookup_table()
    # Clip: central over-face drape. front=-Y. remove faces whose centroid is in
    # the frontal-central facial region BELOW the brow (keeps crown z>1.645,
    # back Y>-0.035, and side framing locks |X|>0.10).
    todel=[]
    for f in bm.faces:
        ce=f.calc_center_median()
        # central forward drape over forehead/face (front=-Y); keep true crown
        # (z>1.71), back (y>=-0.045), and side framing locks (|x|>0.09).
        if abs(ce.x)<0.09 and ce.y < -0.045 and ce.z < 1.71:
            todel.append(f)
    log("faces total", len(bm.faces), "clipping", len(todel))
    bmesh.ops.delete(bm, geom=todel, context='FACES')
    # remove now-loose verts
    loose=[v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=loose, context='VERTS')
    bm.to_mesh(me); bm.free()
    me.update()
    log("after clip verts", len(me.vertices), "polys", len(me.polygons))

    for o in bpy.data.objects: o.select_set(False)
    c.select_set(True); bpy.context.view_layer.objects.active=c
    out=r"H:/Work01/VitruvianGodot/blender_prep/hairtool_out/hairtool_cards.glb"
    bpy.ops.export_scene.gltf(filepath=out, export_format='GLB', use_selection=True,
        export_apply=True, export_draco_mesh_compression_enable=False, export_yup=True)
    log("exported", out)
    open(LOG,"w").write("\n".join(_l))
except Exception as e:
    log("FAIL", repr(e)); traceback.print_exc(); open(LOG,"w").write("\n".join(_l))
finally:
    try: bpy.ops.wm.quit_blender()
    except: pass
