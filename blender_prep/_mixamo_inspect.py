## Inspect: compare rest pose of mixamo_vitruvian vs an imported Mixamo FBX armature.
## Decides whether direct action transfer (no remap) is valid.
import bpy, os, math, traceback
LOG=r"H:/Work01/VitruvianGodot/blender_prep/hairtool_out/mixamo_inspect.log"; _l=[]
def log(*a):
    s=" ".join(str(x) for x in a); print("INSP:",s); _l.append(s)
def flush():
    os.makedirs(os.path.dirname(LOG),exist_ok=True)
    open(LOG,"w",encoding="utf-8").write("\n".join(_l))
try:
    arm=bpy.data.objects.get("mixamo_vitruvian")
    body=bpy.data.objects.get("cm_vitruvian")
    log("scene objects:", [o.name+"("+o.type+")" for o in bpy.data.objects])
    log("armature found:", bool(arm), "body found:", bool(body))
    if arm:
        log("arm scale:", tuple(round(v,5) for v in arm.scale), "dims:", tuple(round(v,3) for v in arm.dimensions))
        log("arm bone count:", len(arm.data.bones))
        log("existing actions:", [a.name for a in bpy.data.actions])
        keyb=["mixamorig:Hips","mixamorig:Spine","mixamorig:LeftArm","mixamorig:LeftForeArm",
              "mixamorig:LeftUpLeg","mixamorig:LeftLeg"]
        for bn in keyb:
            b=arm.data.bones.get(bn)
            if b:
                h=b.head_local; t=b.tail_local
                log("VIT", bn, "head", tuple(round(v,4) for v in h), "tail", tuple(round(v,4) for v in t),
                    "len", round(b.length,4))

    # import Walking FBX
    fbx=r"H:/Work01/VitruvianGodot/blender_prep/mixamo/Walking.fbx"
    before=set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=fbx)
    imported=[o for o in bpy.data.objects if o not in before]
    log("imported objs:", [o.name+"("+o.type+")" for o in imported])
    mx=[o for o in imported if o.type=='ARMATURE']
    if mx:
        mxa=mx[0]
        log("MX arm name:", mxa.name, "scale:", tuple(round(v,6) for v in mxa.scale),
            "dims:", tuple(round(v,3) for v in mxa.dimensions))
        log("MX bone count:", len(mxa.data.bones))
        for bn in keyb:
            b=mxa.data.bones.get(bn)
            if b:
                h=b.head_local; t=b.tail_local
                log("MX ", bn, "head", tuple(round(v,4) for v in h), "tail", tuple(round(v,4) for v in t),
                    "len", round(b.length,4))
        # action + hip translation range
        if mxa.animation_data and mxa.animation_data.action:
            act=mxa.animation_data.action
            log("MX action:", act.name, "frame_range:", tuple(act.frame_range))
            # sample hip location fcurves
            hiploc=[fc for fc in act.fcurves if 'mixamorig:Hips' in fc.data_path and fc.data_path.endswith('location')]
            for fc in hiploc:
                vals=[fc.evaluate(f) for f in range(int(act.frame_range[0]),int(act.frame_range[1])+1)]
                log("  hip loc axis",fc.array_index,"min",round(min(vals),4),"max",round(max(vals),4))
            # also check whether bone names all carry mixamorig: prefix
            paths=set(fc.data_path.split('"')[1] for fc in act.fcurves if '"' in fc.data_path)
            log("MX action bones sample:", sorted(list(paths))[:6], "total", len(paths))
    flush()
except Exception as e:
    log("FAIL", repr(e)); traceback.print_exc(); flush()
finally:
    try: bpy.ops.wm.quit_blender()
    except: pass
