import bpy, math, os, traceback
LOG=r"H:/Work01/VitruvianGodot/blender_prep/hairtool_out/body_probe.log"; _l=[]
def log(*a):
    s=" ".join(str(x) for x in a); print("HTBP:",s); _l.append(s)
try:
    obj=bpy.data.objects["cm_vitruvian"]
    me=obj.data
    uvname="VitruvianUV_UDIM"
    uvl=me.uv_layers[uvname].data
    # histogram tiles
    from collections import Counter
    tiles=Counter()
    for poly in me.polygons:
        u,v=uvl[poly.loop_indices[0]].uv
        tile=1001+int(math.floor(u))+10*int(math.floor(v))
        tiles[tile]+=1
    log("UDIM tile -> poly count:", dict(sorted(tiles.items())))
    log("total polys", len(me.polygons), "verts", len(me.vertices))
    zs=[v.co.z for v in me.vertices]
    log("body Z range", round(min(zs),3), round(max(zs),3))
    log("uv layers", [l.name for l in me.uv_layers])

    # inspect clothing asset blends
    CHARDIR=r"C:/Users/Sam/AppData/Roaming/Blender Foundation/Blender/4.5/scripts/addons/CharMorph/data/characters/Vitruvian/assets"
    for cloth in ("Shirt.blend","Pants.blend"):
        p=os.path.join(CHARDIR,cloth)
        with bpy.data.libraries.load(p) as (df,dt):
            dt.objects=list(df.objects)
            dt.meshes=list(df.meshes)
        log(f"=== {cloth}: objects={df.objects} meshes={df.meshes}")
    open(LOG,"w",encoding="utf-8").write("\n".join(_l))
except Exception as e:
    log("FAIL", repr(e)); traceback.print_exc(); open(LOG,"w",encoding="utf-8").write("\n".join(_l))
finally:
    try: bpy.ops.wm.quit_blender()
    except: pass
