# Procedural hair-card alpha atlases (free, no addon).
#
# Writes TWO atlases (R channel = coverage; the repo hair_card.gdshader reads R):
#   vit_hair_atlas.png  — NCOLS hair CLUMP cards. Each column is a tapered clump:
#       wide feathered ROOT (bottom, v=1) narrowing to a wispy converging TIP
#       (top, v=0), built from individual fingers of differing length so the
#       silhouette is jagged/feathered (not a solid lozenge) and has internal
#       gaps. The clump SHAPE survives minification at portrait distance — that
#       is what makes the cards read as clumped strands instead of a helmet.
#   vit_lash_atlas.png  — NCOLS single tapered LASH strokes (one bold curved lash
#       per column, soft point at the tip) for the eyelash cards.
#
# V (rows): row 0 = TIP (top), bottom row = ROOT. Cards map root->V1, tip->V0.
# Run: python generate_hair_atlas.py
import numpy as np, os, struct, zlib, math, random

W = H = 1024
NCOLS = 4
HAIR_OUT = r"H:\Work01\VitruvianGodot\godot_project\vit_hair_atlas.png"
LASH_OUT = r"H:\Work01\VitruvianGodot\godot_project\vit_lash_atlas.png"


def _write_png(cov, out):
    cov = np.clip(cov, 0, 1)
    rgb = np.zeros((H, W, 3), np.uint8)
    c8 = (cov * 255 + 0.5).astype(np.uint8)
    rgb[..., 0] = c8                                   # R = coverage (shader reads R)
    rgb[..., 1] = (c8 * 0.45).astype(np.uint8)         # faint G/B so luma fallback still works
    rgb[..., 2] = (c8 * 0.28).astype(np.uint8)

    def _chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xffffffff)
    raw = np.hstack([np.zeros((H, 1), np.uint8), rgb.reshape(H, W * 3)]).tobytes()
    with open(out, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + _chunk(b"IHDR", struct.pack(">IIBBBBB", W, H, 8, 2, 0, 0, 0))
                + _chunk(b"IDAT", zlib.compress(raw, 6)) + _chunk(b"IEND", b""))
    print("[atlas] wrote %s  mean %.3f max %.3f" % (out, cov.mean(), cov.max()))


# ── HAIR CLUMP atlas ──────────────────────────────────────────────────────────
def build_hair():
    cov = np.zeros((H, W), np.float32)
    ys = np.arange(H, dtype=np.float32)
    v = ys / (H - 1)                       # 0=top(tip) .. 1=bottom(root)
    x_idx = np.arange(W, dtype=np.float32)[None, :]
    rng = random.Random(11)
    col_w = W / NCOLS

    for c in range(NCOLS):
        cx = (c + 0.5) * col_w
        # A COMBED CLUMP per card: enough overlapping strands to read as a continuous
        # lock of hair (cards must survive the shader's alpha test — too sparse and
        # they vanish, leaving only the dark scalp = "helmet"), with internal
        # striations + feathered edges so the anisotropic specular reads as strands.
        N_FING = 16
        root_spread = 0.72 * col_w
        for i in range(N_FING):
            f = i / (N_FING - 1)           # 0..1 across the clump
            lateral = (f - 0.5)
            root_x = cx + lateral * root_spread + rng.uniform(-3, 3)
            # outer strands shorter → clump tapers to a feathered point at the tip.
            top_v = abs(lateral) * 1.35 + rng.uniform(0.0, 0.16)
            top_v = min(top_v, 0.92)
            conv = 0.7
            amp = rng.uniform(2.0, 6.0)
            ph = rng.uniform(0, 6.28)
            freq = rng.uniform(1.0, 2.4)
            # medium strands that overlap into a readable lock: ~4px root → ~1.2px tip
            hw_root = rng.uniform(3.0, 4.6)
            hw_tip = rng.uniform(1.0, 1.6)

            denom = max(1e-3, 1.0 - top_v)
            u = np.clip((1.0 - v) / denom, 0.0, 1.0)
            x_center = (root_x * (1 - conv * u) + cx * (conv * u)
                        + amp * np.sin(ph + u * freq * math.pi))
            hw = hw_root * (1 - u) + hw_tip * u
            dist = np.abs(x_idx - x_center[:, None])
            s = np.clip(1.0 - dist / hw[:, None], 0.0, 1.0) ** 1.2
            tip_fade = np.clip(1.0 - 0.6 * u, 0.28, 1.0)
            s *= tip_fade[:, None]
            s[v < top_v, :] = 0.0
            s *= (0.82 + 0.18 * np.sin(u * 8.0 + ph))[:, None]
            cov = np.maximum(cov, s)
    # Mild root fade so the very base feathers slightly (not a hard band).
    root_fade = np.clip((1.0 - v) / 0.10 + 0.5, 0.0, 1.0)
    cov *= root_fade[:, None]
    _write_png(cov, HAIR_OUT)


# ── LASH atlas ────────────────────────────────────────────────────────────────
def build_lash():
    cov = np.zeros((H, W), np.float32)
    ys = np.arange(H, dtype=np.float32)
    v = ys / (H - 1)
    x_idx = np.arange(W, dtype=np.float32)[None, :]
    rng = random.Random(23)
    col_w = W / NCOLS
    u = 1.0 - v                            # 0 at root(bottom) .. 1 at tip(top)
    for c in range(NCOLS):
        cx = (c + 0.5) * col_w
        curve = rng.uniform(-0.16, 0.16) * col_w
        # one bold lash FILLING most of the column so the card reads as a solid
        # tapered lash: half-width ~38% of the column at root → fine point at tip.
        hw = (0.38 * col_w) * (1 - u) ** 1.3 + 4.0 * u
        x_center = cx + curve * (u ** 2) * 3.0
        dist = np.abs(x_idx - x_center[:, None])
        s = np.clip(1.0 - dist / hw[:, None], 0.0, 1.0) ** 0.8
        s *= np.clip(1.0 - 0.35 * u, 0.3, 1.0)[:, None]    # gentle fade toward the tip point
        cov = np.maximum(cov, s)
    _write_png(cov, LASH_OUT)


build_hair()
build_lash()
print("[atlas] done")
