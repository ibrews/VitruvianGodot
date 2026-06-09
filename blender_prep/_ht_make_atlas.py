import bpy, numpy as np, traceback
OUT = r"H:/Work01/VitruvianGodot/blender_prep/hairtool_out/"
LOG = OUT + "make_atlas.log"
_l=[]
def log(*a):
    s=" ".join(str(x) for x in a); print("HTDRV:",s); _l.append(s)

def save_rgba(name, rgba, non_color=False):
    h,w,_ = rgba.shape
    img = bpy.data.images.new(name, width=w, height=h, alpha=True, float_buffer=False)
    img.colorspace_settings.name = 'Non-Color' if non_color else 'sRGB'
    # blender expects bottom-row-first; our arrays are top-row-first -> flip vertically
    flat = np.flipud(rgba).astype(np.float32).ravel()
    img.pixels = flat
    img.filepath_raw = OUT + name
    img.file_format = 'PNG'
    img.save()
    log("saved", name, (w,h))

try:
    RES = 2048
    src = bpy.data.images.get("HairStripDepth.png")
    if src is None:
        src = bpy.data.images.load(r"C:/Users/Sam/AppData/Roaming/Blender Foundation/Blender/4.5/scripts/addons/hair_tool/" )  # fallback unused
    sw, sh = src.size
    log("src HairStripDepth", sw, sh)
    px = np.array(src.pixels[:], dtype=np.float32).reshape(sh, sw, 4)
    px = np.flipud(px)  # to top-row-first
    H = px[:,:,0]  # grayscale height (R channel)

    # resample to RES via simple nearest/linear using numpy (repeat-free): use np.interp grid
    def resize(a, res):
        yi = np.linspace(0, a.shape[0]-1, res)
        xi = np.linspace(0, a.shape[1]-1, res)
        # bilinear
        y0 = np.floor(yi).astype(int); x0 = np.floor(xi).astype(int)
        y1 = np.clip(y0+1,0,a.shape[0]-1); x1 = np.clip(x0+1,0,a.shape[1]-1)
        wy = (yi-y0)[:,None]; wx = (xi-x0)[None,:]
        a00 = a[np.ix_(y0,x0)]; a01=a[np.ix_(y0,x1)]; a10=a[np.ix_(y1,x0)]; a11=a[np.ix_(y1,x1)]
        top = a00*(1-wx)+a01*wx; bot = a10*(1-wx)+a11*wx
        return top*(1-wy)+bot*wy
    H = resize(H, RES)
    # normalize
    H = (H - H.min())/(max(1e-5, H.max()-H.min()))

    # --- NORMAL MAP (tangent/OpenGL: +X right, +Y up, +Z out) ---
    # gradients; strands run vertically (V/y), detail varies across x -> strong x slope
    def blur(a, k=1):
        out=a.copy()
        for _ in range(k):
            out=(out
                 +np.roll(out,1,0)+np.roll(out,-1,0)
                 +np.roll(out,1,1)+np.roll(out,-1,1))/5.0
        return out
    Hb = blur(H,1)
    gx = (np.roll(Hb,-1,1)-np.roll(Hb,1,1))*0.5
    gy = (np.roll(Hb,-1,0)-np.roll(Hb,1,0))*0.5
    STR_X = 6.0   # strong cross-strand tilt -> catches side light on crown
    STR_Y = 2.0
    nx = -gx*STR_X
    ny =  gy*STR_Y   # +Y up (image top is +V); we flipped to top-first, so invert for OpenGL? keep +up
    nz = np.ones_like(nx)
    ln = np.sqrt(nx*nx+ny*ny+nz*nz)
    nx/=ln; ny/=ln; nz/=ln
    normal = np.stack([nx*0.5+0.5, ny*0.5+0.5, nz*0.5+0.5, np.ones_like(nx)],axis=-1)
    save_rgba("vit_hair_normal.png", normal, non_color=True)

    # --- AO --- darker in valleys; blur height a lot
    Hsm = blur(H,6)
    ao = 0.35 + 0.65*Hsm
    ao = np.clip(ao,0,1)
    aorgba = np.stack([ao,ao,ao,np.ones_like(ao)],axis=-1)
    save_rgba("vit_hair_ao.png", aorgba, non_color=True)

    # --- DIFFUSE --- dark brown hair, strand highlights from height
    dark = np.array([0.035,0.022,0.015])
    light= np.array([0.18,0.12,0.07])
    t = np.clip(H**1.3,0,1)[...,None]
    diff = dark*(1-t)+light*t
    diff = diff*ao[...,None]   # bake AO into diffuse too (so even unlit reads as hair depth)
    diffrgba = np.concatenate([diff, np.ones((RES,RES,1),dtype=np.float32)],axis=-1)
    save_rgba("vit_hair_diffuse.png", diffrgba, non_color=False)

    # --- OPACITY --- mostly opaque ribbons, slight feather where height is very flat/mid (gaps)
    # measure local contrast: strands = high |gx|; flat gap = low contrast -> lower alpha at extreme low contrast only
    contrast = blur(np.abs(gx)+np.abs(gy),2)
    contrast = contrast/ (contrast.max()+1e-6)
    alpha = np.clip(0.55 + 3.0*contrast, 0.0, 1.0)   # keep fairly solid
    alpha = np.maximum(alpha, 0.0)
    oprgba = np.stack([alpha,alpha,alpha,alpha],axis=-1)
    save_rgba("vit_hair_opacity.png", oprgba, non_color=True)

    log("DONE atlas RES", RES)
    open(LOG,"w").write("\n".join(_l))
except Exception as e:
    log("FAIL", repr(e)); traceback.print_exc(); open(LOG,"w").write("\n".join(_l))
finally:
    try: bpy.ops.wm.quit_blender()
    except: pass
