import cv2, os, sys, glob, numpy as np
d = sys.argv[1] if len(sys.argv) > 1 else r"H:/Work01/VitruvianGodot/out/cine_mov"
out = sys.argv[2] if len(sys.argv) > 2 else r"H:/Work01/VitruvianGodot/out/vitruvian_showcase.mp4"
fps = int(sys.argv[3]) if len(sys.argv) > 3 else 30
files = sorted(glob.glob(os.path.join(d, "frame*.png")))
if not files:
    print("no frames in", d); sys.exit(2)
img = cv2.imread(files[0]); h, w = img.shape[:2]
print("assembling", len(files), "frames", w, "x", h, "@", fps, "fps")

TITLE = "VITRUVIAN"
SUB = "real-time digital human  -  stock Godot 4.6  -  CC0 / EULA-free  -  no MetaHuman, no Unreal"
N = len(files)

def overlay(im, i):
    t = i / fps
    # persistent lower-left caption (small, semi-transparent)
    cap = "VITRUVIAN  -  real-time  -  stock Godot 4.6  -  CC0 / EULA-free"
    o = im.copy()
    cv2.rectangle(o, (0, h-42), (w, h), (0, 0, 0), -1)
    im = cv2.addWeighted(o, 0.45, im, 0.55, 0)
    cv2.putText(im, cap, (24, h-15), cv2.FONT_HERSHEY_SIMPLEX, 0.62, (235, 235, 235), 1, cv2.LINE_AA)
    # opening title card fade (first 2.5s)
    if t < 2.5:
        a = 1.0 - max(0.0, (t - 1.5) / 1.0)        # hold then fade
        a = min(1.0, t / 0.5) * a
        ov = im.copy()
        cv2.putText(ov, TITLE, (int(w*0.5 - 175), int(h*0.46)), cv2.FONT_HERSHEY_DUPLEX, 2.4, (245, 245, 245), 3, cv2.LINE_AA)
        cv2.putText(ov, SUB, (int(w*0.5 - 470), int(h*0.46)+46), cv2.FONT_HERSHEY_SIMPLEX, 0.62, (200, 210, 230), 1, cv2.LINE_AA)
        im = cv2.addWeighted(ov, a, im, 1.0 - a, 0)
    return im

vw = None
for cc in ("avc1", "mp4v"):
    vw = cv2.VideoWriter(out, cv2.VideoWriter_fourcc(*cc), fps, (w, h))
    if vw.isOpened():
        print("codec", cc); break
poster_idx = int(0.74 * N)   # a strong profile/closeup beat
for i, f in enumerate(files):
    im = overlay(cv2.imread(f), i)
    vw.write(im)
    if i == poster_idx:
        cv2.imwrite(os.path.join(os.path.dirname(out), "vitruvian_poster.png"), im)
vw.release()
print("wrote", out, os.path.getsize(out) // 1024, "KB")
