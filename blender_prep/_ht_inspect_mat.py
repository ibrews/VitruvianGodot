import bpy, traceback, os
LOG = r"H:/Work01/VitruvianGodot/blender_prep/hairtool_out/inspect_mat.log"
OUT = r"H:/Work01/VitruvianGodot/blender_prep/hairtool_out/"
_l=[]
def log(*a):
    s=" ".join(str(x) for x in a); print("HTDRV:",s); _l.append(s)
try:
    # save all images that have data (extract bundled textures)
    for img in bpy.data.images:
        if img.name=='Render Result' or img.size[0]==0: continue
        try:
            p = OUT + "tex_" + bpy.path.clean_name(img.name) + ".png"
            img.file_format='PNG'
            img.save_render(p) if not img.has_data else img.filepath_raw==img.filepath_raw
            # robust save:
            img.filepath_raw = p; img.file_format='PNG'; img.save()
            log("saved image", img.name, img.size[:], "->", p)
        except Exception as e:
            log("save img fail", img.name, repr(e))

    mat = bpy.data.materials.get('HT_Default_Material')
    nt = mat.node_tree
    log("=== material node graph ===")
    for n in nt.nodes:
        extra=""
        if n.bl_idname=='ShaderNodeTexImage':
            extra="img="+(n.image.name if n.image else "None")
            # what feeds its Vector input?
            vin=n.inputs.get('Vector')
            if vin and vin.is_linked:
                fn=vin.links[0].from_node
                extra+=" vec_from="+fn.bl_idname+("("+fn.uv_map+")" if fn.bl_idname=='ShaderNodeUVMap' else "")+("("+fn.attribute_name+")" if fn.bl_idname=='ShaderNodeAttribute' else "")
        if n.bl_idname=='ShaderNodeAttribute':
            extra="attr="+n.attribute_name
        if n.bl_idname=='ShaderNodeBump':
            extra="bump strength_in_linked="+str(n.inputs['Strength'].is_linked)+" height_linked="+str(n.inputs['Height'].is_linked)
        if n.bl_idname=='ShaderNodeGroup':
            extra="group="+(n.node_tree.name if n.node_tree else "None")
        log(f"  {n.bl_idname} '{n.name}' {extra}")
    # output surface connection
    out = next((n for n in nt.nodes if n.bl_idname=='ShaderNodeOutputMaterial'), None)
    if out and out.inputs['Surface'].is_linked:
        log("Surface <-", out.inputs['Surface'].links[0].from_node.bl_idname, out.inputs['Surface'].links[0].from_node.name)
    open(LOG,"w").write("\n".join(_l))
except Exception as e:
    log("FAIL", repr(e)); traceback.print_exc(); open(LOG,"w").write("\n".join(_l))
finally:
    try: bpy.ops.wm.quit_blender()
    except: pass
