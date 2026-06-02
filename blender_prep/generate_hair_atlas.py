# Procedural hair-strand coverage atlas (free, no addon). Several vertical strand
# clumps on black; R channel = per-strand coverage so the repo's hair_card.gdshader
# (use_red_mask=true) cuts cards into fine strands instead of solid ribbons.
# V (rows) = along hair length: row 0 = TIP (sparser/finer), bottom = ROOT (denser).
# Run: python generate_hair_atlas.py
import numpy as np, os, struct, zlib, math, random

W = H = 1024
NCOLS = 4                      # 4 clump variants across U
STRANDS_PER_COL = 26
OUT = r"H:\Work01\VitruvianGodot\godot_project\vit_hair_atlas.png"

cov = np.zeros((H, W), np.float32)
ys = np.arange(H, dtype=np.float32)
v = ys / (H - 1)               # 0=top(tip) .. 1=bottom(root)
rng = random.Random(7)

col_w = W // NCOLS
for c in range(NCOLS):
    x0 = c * col_w
    for _ in range(STRANDS_PER_COL):
        # strand base x within the column, gentle sine wave, taper to tip (top)
        bx = x0 + rng.uniform(0.12, 0.88) * col_w
        amp = rng.uniform(2.0, 10.0)
        ph = rng.uniform(0, 6.28)
        freq = rng.uniform(1.5, 3.5)
        # half-width: thin at tip (v=0) → thicker at root (v=1)
        w_root = rng.uniform(1.2, 2.6)
        x_center = bx + amp * np.sin(ph + v * freq * math.pi)
        half_w = (0.25 + 0.75 * v) * w_root
        # length: some strands stop short of the tip for a soft, uneven top edge
        top = rng.uniform(0.0, 0.35)
        x_idx = np.arange(W, dtype=np.float32)[None, :]
        dist = np.abs(x_idx - x_center[:, None])             # H×W distance to strand
        s = np.clip(1.0 - dist / half_w[:, None], 0.0, 1.0)   # soft core
        s = s ** 1.5
        s[v < top, :] = 0.0
        # slight along-length brightness variation
        s *= (0.7 + 0.3 * np.sin(v * 9.0 + ph))[:, None]
        cov = np.maximum(cov, s)

cov = np.clip(cov, 0, 1)
print("[atlas] coverage mean %.3f max %.3f" % (cov.mean(), cov.max()))

# write PNG: R = coverage, G/B small (so luma fallback also works), no alpha needed
rgb = np.zeros((H, W, 3), np.uint8)
c8 = (cov * 255 + 0.5).astype(np.uint8)
rgb[..., 0] = c8
rgb[..., 1] = (c8 * 0.5).astype(np.uint8)
rgb[..., 2] = (c8 * 0.3).astype(np.uint8)

def _chunk(tag, data):
    return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xffffffff)
raw = np.hstack([np.zeros((H, 1), np.uint8), rgb.reshape(H, W * 3)]).tobytes()
with open(OUT, "wb") as f:
    f.write(b"\x89PNG\r\n\x1a\n" + _chunk(b"IHDR", struct.pack(">IIBBBBB", W, H, 8, 2, 0, 0, 0))
            + _chunk(b"IDAT", zlib.compress(raw, 6)) + _chunk(b"IEND", b""))
print("[atlas] wrote", OUT)
