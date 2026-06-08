## Skin the Hair Tool cards to a vertical bone CHAIN so the hair can be dynamically
## simulated (spring bones) in Godot. Roots (high Z) rigid to HR0 (follows head);
## tips (low Z) weighted down the chain so they swing/lag/settle.
## Output: godot_project/vitruvian_hair_rigged.glb  (mesh + HairRig armature, skinned)
import bpy, os, math, traceback
import numpy as np
from mathutils import Vector
LOG=r"H:/Work01/VitruvianGodot/blender_prep/hairtool_out/hair_rig.log"; _l=[]
def log(*a):
    s=" ".join(str(x) for x in a); print("HRIG:",s); _l.append(s)
def flush(): open(LOG,"w",encoding="utf-8").write("\n".join(_l))
try:
    # clean slate
    bpy.ops.wm.read_factory_settings(use_empty=True)
    src=os.environ.get("HAIR_SRC", r"H:/Work01/VitruvianGodot/blender_prep/hairtool_out/hairtool_cards.glb")
    out=os.environ.get("HAIR_OUT", r"H:/Work01/VitruvianGodot/godot_project/vitruvian_hair_rigged.glb")
    log("src", src, "out", out)
    bpy.ops.import_scene.gltf(filepath=src)
    meshes=[o for o in bpy.context.scene.objects if o.type=='MESH']
    # the procedural GLB also carries brow cards — rig the largest mesh (the hair) and
    # drop the rest so they don't get skinned into the chain.
    hair=max(meshes, key=lambda o: len(o.data.vertices))
    for o in meshes:
        if o is not hair: bpy.data.objects.remove(o, do_unlink=True)
    log("hair mesh", hair.name, "verts", len(hair.data.vertices))
    # ensure transforms applied so vert coords are world-space (Z-up)
    bpy.ops.object.select_all(action='DESELECT'); hair.select_set(True)
    bpy.context.view_layer.objects.active=hair
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    me=hair.data
    co=np.empty(len(me.vertices)*3, np.float32); me.vertices.foreach_get('co', co); co=co.reshape(-1,3)
    zmin,zmax=float(co[:,2].min()), float(co[:,2].max())
    log("hair Z range", round(zmin,3), round(zmax,3))

    # rename material so Godot can wire it
    if me.materials:
        me.materials[0].name="VitHair"
    else:
        me.materials.append(bpy.data.materials.new("VitHair"))

    # ---- build the chain armature ----
    NSEG=5                          # HR0..HR5 (6 bones; HR0 rigid root, HR1..5 spring)
    top=zmax-0.005                  # crown
    bot=zmin+0.02                   # below the longest tips
    zs=[top - (top-bot)*i/NSEG for i in range(NSEG+1)]   # NSEG+1 joint heights
    cx=float(np.median(co[:,0])); cy=float(np.median(co[:,1]))   # chain through hair centroid
    arm_data=bpy.data.armatures.new("HairRig"); armobj=bpy.data.objects.new("HairRig", arm_data)
    bpy.context.scene.collection.objects.link(armobj)
    bpy.context.view_layer.objects.active=armobj
    bpy.ops.object.mode_set(mode='EDIT')
    bones=[]
    for i in range(NSEG):
        b=arm_data.edit_bones.new("HR%d"%i)
        b.head=Vector((cx,cy,zs[i])); b.tail=Vector((cx,cy,zs[i+1]))
        if i>0: b.parent=bones[-1]; b.use_connect=True
        bones.append(b)
    bpy.ops.object.mode_set(mode='OBJECT')
    log("chain bones", [b.name for b in arm_data.bones], "z", [round(z,3) for z in zs])

    # ---- weight verts by Z (smooth blend down the chain), vectorized + bucketed ----
    for i in range(NSEG): hair.vertex_groups.new(name="HR%d"%i)
    vgs=[hair.vertex_groups["HR%d"%i] for i in range(NSEG)]
    span=top-bot
    u = np.clip((top - co[:,2])/span, 0.0, 0.9999)   # 0 crown .. ~1 tips
    fpos = u*NSEG
    idx = np.clip(np.floor(fpos).astype(int), 0, NSEG-1)
    frac = np.round(fpos-idx, 2)
    rigid = u < 0.12
    idx[rigid]=0; frac[rigid]=0.0
    wL = np.where(rigid, 1.0, 1.0-frac)              # lower-bone weight (bone idx)
    wU = np.where(rigid, 0.0, frac)                  # upper-bone weight (bone idx+1)
    # lower-bone assignment (batched per bone per quantized weight)
    for bone in range(NSEG):
        m = idx==bone
        verts = np.nonzero(m)[0]; ws = wL[m]
        for w in np.unique(ws):
            if w<=0: continue
            sel = verts[ws==w].tolist()
            vgs[bone].add(sel, float(w), 'REPLACE')
    # upper-bone assignment (bone idx+1)
    up = idx+1
    mU = (up < NSEG) & (wU > 0)
    for bone in range(1, NSEG):
        m = mU & (up==bone)
        verts = np.nonzero(m)[0]; ws = wU[m]
        for w in np.unique(ws):
            sel = verts[ws==w].tolist()
            vgs[bone].add(sel, float(w), 'REPLACE')
    log("weighting done (vectorized)")

    # parent with the existing groups (armature deform)
    hair.modifiers.new("Armature", 'ARMATURE').object=armobj
    hair.parent=armobj

    # ---- export skinned GLB ----
    bpy.ops.object.select_all(action='DESELECT')
    armobj.select_set(True); hair.select_set(True)
    bpy.context.view_layer.objects.active=armobj
    bpy.ops.export_scene.gltf(filepath=out, export_format='GLB', use_selection=True,
        export_apply=False, export_yup=True, export_materials='EXPORT',
        export_normals=True, export_tangents=True, export_texcoords=True, export_skins=True)
    log("wrote", out)
    flush()
except Exception as e:
    log("FAIL", repr(e)); traceback.print_exc(); flush()
finally:
    try: bpy.ops.wm.quit_blender()
    except: pass
