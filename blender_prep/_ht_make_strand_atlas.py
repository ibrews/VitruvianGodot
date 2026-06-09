import bpy, numpy as np, traceback, random
OUT = r"H:/Work01/VitruvianGodot/blender_prep/hairtool_out/"
LOG = OUT + "strand_atlas.log"; _l=[]
def log(*a):
    s=" ".join(str(x) for x in a); print("HTDRV:",s); _l.append(s)
def save_rgba(name, rgba, non_color=False):
    h,w,_=rgba.shape
    img=bpy.data.images.new(name,width=w,height=h,alpha=True,float_buffer=False)
    img.colorspace_settings.name='Non-Color' if non_color else 'sRGB'
    img.pixels=np.flipud(rgba).astype(np.float32).ravel()  # blender bottom-row-first
    img.filepath_raw=OUT+name; img.file_format='PNG'; img.save()
    log("saved",name,(w,h))
try:
    random.seed(7); np.random.seed(7)
    RES=2048
    # buffers (top row = V=1 = ROOT, bottom row = V=0 = TIP)  -> matches HairTool UV
    alpha=np.zeros((RES,RES),np.float32)
    nx_acc=np.zeros((RES,RES),np.float32); w_acc=np.zeros((RES,RES),np.float32)
    diff_acc=np.zeros((RES,RES),np.float32)
    dens=np.zeros((RES,RES),np.float32)

    N=900                                              # MANY more strands → reads as hair, not ribbons
    for i in range(N):
        root_x=(i+0.5)/N*RES + np.random.uniform(-0.4,0.4)*(RES/N)
        amp=np.random.uniform(2,13)*(RES/512.0)        # lateral sway px
        freq=np.random.uniform(0.5,2.4)
        phase=np.random.uniform(0,6.28)
        length_frac=np.random.uniform(0.5,1.0)         # how far down it reaches
        bottom=int(length_frac*RES)
        base_w=np.random.uniform(0.30,0.62)*(RES/512.0)  # THIN strands (< spacing) → distinct, gappy
        tip_w=max(0.3,base_w*0.16)
        val=np.random.uniform(0.5,1.4)                 # per-strand brightness
        ys=np.arange(0,bottom)
        t=ys/max(1,bottom-1)                           # 0 root .. 1 tip
        cx=root_x+amp*np.sin(freq*t*6.2831+phase)*(0.3+0.7*t)
        width=base_w*(1-t)+tip_w*t
        fade=(1.0-np.clip((t-0.82)/0.18,0,1))          # fade near tip
        fade*= (0.6+0.4*np.clip(t/0.06,0,1))           # tiny soften at very root edge
        for k,y in enumerate(ys):
            wv=width[k]
            if fade[k]<=0.01: continue
            x0=int(cx[k]-3*wv); x1=int(cx[k]+3*wv)+1
            x0=max(0,x0); x1=min(RES,x1)
            if x1<=x0: continue
            xs=np.arange(x0,x1)
            dxn=(xs-cx[k])/wv
            cov=np.exp(-dxn*dxn)*fade[k]
            row=alpha[y,x0:x1]
            np.maximum(row,cov,out=row)
            nxc=np.clip(dxn,-1,1)*cov         # rounded: center 0, edges tilt
            nx_acc[y,x0:x1]+=nxc; w_acc[y,x0:x1]+=cov
            diff_acc[y,x0:x1]+=val*cov
            dens[y,x0:x1]+=cov
    log("strands done")

    # --- ALPHA --- SMOOTH continuous coverage from the density field, so the
    # scissor/density knob sweeps GRADUALLY (no 0.20->0.21 cliff where everything
    # vanishes). 1-exp(-k*dens): gaps→0 (transparent), strand cores→~1 (opaque),
    # soft continuous edges in between = a wide usable threshold range.
    a = 1.0 - np.exp(-2.4 * dens)
    nz = np.random.uniform(0,1,(RES,RES)).astype(np.float32)
    a = np.clip(a - nz*0.05, 0, 1)          # tiny edge noise → wispy, not a smooth blob
    save_rgba("vit_hair_opacity.png", np.stack([a,a,a,a],-1), non_color=True)

    # --- NORMAL --- lateral tilt from rounded strands (X), small Y from vertical, Z out
    wsafe=np.maximum(w_acc,1e-3)
    nx=(nx_acc/wsafe)
    NX_STR=2.2
    nx=nx*NX_STR
    # vertical gradient of density -> slight ny
    gy=(np.roll(dens,-1,0)-np.roll(dens,1,0))*0.5
    ny=gy*0.6
    nz=np.ones_like(nx)
    ln=np.sqrt(nx*nx+ny*ny+nz*nz); nx/=ln; ny/=ln; nz/=ln
    normal=np.stack([nx*0.5+0.5, ny*0.5+0.5, nz*0.5+0.5, np.ones_like(nx)],-1)
    save_rgba("vit_hair_normal.png", normal, non_color=True)

    # --- DIFFUSE --- dark brown, per-strand value, root darker than tip
    val_map=np.divide(diff_acc, np.maximum(dens,1e-3))
    val_map=np.clip(val_map,0,2)
    vv=np.linspace(1.0,0.0,RES)[:,None]   # 1 at top(root) -> 0 bottom(tip)
    root_dark=0.65+0.35*(1.0-vv)          # darker at root
    dark=np.array([0.045,0.028,0.018]); light=np.array([0.16,0.11,0.07])
    tone=np.clip(val_map[...,None]*0.6,0,1)
    diff=(dark*(1-tone)+light*tone)*root_dark
    save_rgba("vit_hair_diffuse.png", np.concatenate([diff,np.ones((RES,RES,1),np.float32)],-1), non_color=False)

    # --- AO --- darker where less dense (deeper between strands) + root area
    def blur(x,k=4):
        o=x.copy()
        for _ in range(k):
            o=(o+np.roll(o,1,0)+np.roll(o,-1,0)+np.roll(o,1,1)+np.roll(o,-1,1))/5.0
        return o
    db=blur(np.clip(dens,0,1),6)
    ao=0.3+0.7*db
    ao=np.clip(ao,0,1)
    save_rgba("vit_hair_ao.png", np.stack([ao,ao,ao,np.ones_like(ao)],-1), non_color=True)

    log("DONE strand atlas")
    open(LOG,"w").write("\n".join(_l))
except Exception as e:
    log("FAIL",repr(e)); traceback.print_exc(); open(LOG,"w").write("\n".join(_l))
finally:
    try: bpy.ops.wm.quit_blender()
    except: pass
