import bpy
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=r"H:/Work01/VitruvianGodot/godot_project/vitruvian_head.glb")
for o in bpy.context.scene.objects:
    if o.type=='MESH' and o.name.startswith("Eye_L"):
        me=o.data
        print("EPB: obj",o.name,"mats",[m.name if m else "?" for m in me.materials])
        uvl=me.uv_layers.active.data
        import collections
        per=collections.defaultdict(list)
        for poly in me.polygons:
            for li in poly.loop_indices:
                per[poly.material_index].append(tuple(uvl[li].uv))
        for mi_,uvs in sorted(per.items()):
            us=[u for u,v in uvs]; vs=[v for u,v in uvs]
            print("EPB: slot",mi_,me.materials[mi_].name if mi_<len(me.materials) else "?",
                  "faces~",len(uvs)//4,"u[%.3f,%.3f] v[%.3f,%.3f]"%(min(us),max(us),min(vs),max(vs)))
