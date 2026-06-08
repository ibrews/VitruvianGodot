## Color-code UDIM tiles on the head and render front + 3q (workbench) so I can SEE
## what tile 1006 is (inner cavity vs visible lips) and where eyes (1005/1007) are.
import bpy, bmesh, math, os
o = bpy.data.objects["cm_vitruvian"]
me = o.data
uvl = me.uv_layers["VitruvianUV_UDIM"].data
# materials: skin gray, 1006 red, 1005 green, 1007 blue, others gray
def mat(name, rgba):
    m = bpy.data.materials.new(name); m.use_nodes=False; m.diffuse_color=rgba; return m
M_skin=mat("skin",(0.8,0.7,0.62,1)); M_mouth=mat("mouth",(1,0,0,1))
M_eye=mat("eye",(0,1,0,1)); M_lash=mat("lash",(0,0.3,1,1))
me.materials.clear()
for m in (M_skin,M_mouth,M_eye,M_lash): me.materials.append(m)
for poly in me.polygons:
    u,v=uvl[poly.loop_indices[0]].uv
    tile=1001+int(math.floor(u))+10*int(math.floor(v))
    poly.material_index = {1006:1,1005:2,1007:3}.get(tile,0)
# delete body below neck so the head fills the frame
bm=bmesh.new(); bm.from_mesh(me); bm.verts.ensure_lookup_table()
bmesh.ops.delete(bm,geom=[v for v in bm.verts if v.co.z<1.50],context='VERTS')
bm.to_mesh(me); bm.free(); me.update()
# render workbench, color by material
scn=bpy.context.scene; scn.render.engine='BLENDER_WORKBENCH'
scn.display.shading.color_type='MATERIAL'
scn.render.resolution_x=500; scn.render.resolution_y=600
scn.render.image_settings.file_format='PNG'
cam=bpy.data.objects.get("Camera")
if cam is None:
    cd=bpy.data.cameras.new("Camera"); cam=bpy.data.objects.new("Camera",cd); scn.collection.objects.link(cam)
scn.camera=cam
RD=r"H:/Work01/VitruvianGodot/out"
shots={"front":((0.0,-0.42,1.62),(math.pi/2,0,0)),
       "3q":((0.28,-0.34,1.62),(math.pi/2,0,0.62)),
       "low":((0.0,-0.30,1.50),(math.radians(64),0,0))}   # looking UP into the mouth
for nm,(loc,rot) in shots.items():
    cam.location=loc; cam.rotation_euler=rot; cam.data.lens=50
    scn.render.filepath=os.path.join(RD,f"tileviz_{nm}.png"); bpy.ops.render.render(write_still=True)
    print("rendered",nm)
try: bpy.ops.wm.quit_blender()
except: pass
