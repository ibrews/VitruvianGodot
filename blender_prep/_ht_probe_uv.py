import bpy, numpy as np, traceback
LOG = r"H:/Work01/VitruvianGodot/blender_prep/hairtool_out/probe_uv.log"
_l=[]
def log(*a):
    s=" ".join(str(x) for x in a); print("HTDRV:",s); _l.append(s)
try:
    c = bpy.data.objects.get("VitEveGuides_converted")
    me = c.data
    log("verts", len(me.vertices), "polys", len(me.polygons))
    for uvname in ['UVMap','HairTool_UV']:
        uv = me.uv_layers.get(uvname)
        if not uv:
            log(uvname, "MISSING"); continue
        arr = np.empty(len(uv.data)*2, dtype=np.float32)
        uv.data.foreach_get('uv', arr)
        arr = arr.reshape(-1,2)
        log(uvname, "u[min,max]", round(float(arr[:,0].min()),3), round(float(arr[:,0].max()),3),
            "v[min,max]", round(float(arr[:,1].min()),3), round(float(arr[:,1].max()),3))
    # per-card overlap check: examine first few faces' loop UVs to see tile span of single quad
    uv = me.uv_layers['UVMap']
    log("first 8 polys loop-uv spans (u_span,v_span):")
    for p in me.polygons[:8]:
        us=[]; vs=[]
        for li in p.loop_indices:
            uvv = uv.data[li].uv; us.append(uvv[0]); vs.append(uvv[1])
        log("  poly",p.index,"verts",len(p.vertices),"u",round(min(us),2),round(max(us),2),"v",round(min(vs),2),round(max(vs),2))
    # material nodes
    mat = me.materials[0] if me.materials else None
    if mat and mat.use_nodes:
        log("material", mat.name, "nodes:", [n.bl_idname for n in mat.node_tree.nodes])
        imgs = [n.image.name for n in mat.node_tree.nodes if n.bl_idname=='ShaderNodeTexImage' and n.image]
        log("material image textures:", imgs)
    # bounds of mesh in Z to understand hair length on head
    co = np.empty(len(me.vertices)*3, dtype=np.float32); me.vertices.foreach_get('co', co); co=co.reshape(-1,3)
    log("mesh local Z range", round(float(co[:,2].min()),3), round(float(co[:,2].max()),3))
    log("head Z range", )
    h = bpy.data.objects.get('cm_vitruvian')
    hco = np.empty(len(h.data.vertices)*3,dtype=np.float32); h.data.vertices.foreach_get('co',hco); hco=hco.reshape(-1,3)
    log("head local Z", round(float(hco[:,2].min()),3), round(float(hco[:,2].max()),3))
    open(LOG,"w").write("\n".join(_l))
except Exception as e:
    log("FAIL", repr(e)); traceback.print_exc(); open(LOG,"w").write("\n".join(_l))
finally:
    try: bpy.ops.wm.quit_blender()
    except: pass
