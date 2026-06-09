import bpy, numpy as np
LOG=r"H:/Work01/VitruvianGodot/blender_prep/hairtool_out/probe_geo.log"; _l=[]
def log(*a):
    s=" ".join(str(x) for x in a); print("HTDRV:",s); _l.append(s)
h=bpy.data.objects['cm_vitruvian']; c=bpy.data.objects['VitEveGuides_converted']
hc=np.empty(len(h.data.vertices)*3,np.float32); h.data.vertices.foreach_get('co',hc); hc=hc.reshape(-1,3)
cc=np.empty(len(c.data.vertices)*3,np.float32); c.data.vertices.foreach_get('co',cc); cc=cc.reshape(-1,3)
log("HEAD X",round(hc[:,0].min(),3),round(hc[:,0].max(),3),"Y",round(hc[:,1].min(),3),round(hc[:,1].max(),3),"Z",round(hc[:,2].min(),3),round(hc[:,2].max(),3))
log("HAIR X",round(cc[:,0].min(),3),round(cc[:,0].max(),3),"Y",round(cc[:,1].min(),3),round(cc[:,1].max(),3),"Z",round(cc[:,2].min(),3),round(cc[:,2].max(),3))
# face surface Y at height slices, central column |X|<0.05
for z0 in [1.45,1.55,1.60,1.66,1.70,1.74]:
    m=(np.abs(hc[:,0])<0.05)&(np.abs(hc[:,2]-z0)<0.02)
    if m.sum():
        log(f"head z~{z0}: Ymin(front)={round(hc[m,1].min(),3)} Ymax(back)={round(hc[m,1].max(),3)} n={int(m.sum())}")
# hair central column drape: verts with |X|<0.08, Z in face band
mc=(np.abs(cc[:,0])<0.08)&(cc[:,2]>1.40)&(cc[:,2]<1.70)
log("hair central-face-band verts", int(mc.sum()))
if mc.sum():
    yy=cc[mc,1]
    log("  their Y: min",round(yy.min(),3),"max",round(yy.max(),3),"median",round(float(np.median(yy)),3))
    # how many are in FRONT of face (more negative Y than ~ -0.07 forehead)
    log("  verts with Y<-0.05 (over face):", int((yy<-0.05).sum()))
open(LOG,"w").write("\n".join(_l))
try: bpy.ops.wm.quit_blender()
except: pass
