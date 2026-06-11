# Bake Godot-ready skin textures from the shipped CharMorph 4K EXRs (CC0).
# Pure python (cv2 + numpy, no Blender).
#
# FACE (tile 1001 → vit_face_*.png @2048): replaces the old stride-decimated bake —
#   • albedo = light/dark blend × CAVITY darkening (pores/creases finally read)
#   • roughness = cavity_rough_coat.G with a touch more contrast (breaks the vinyl sheen)
#   • normal = derived from the 4K displacement at FULL res, then area-downsampled
#     (the old bake decimated 4K→2K first, which aliased away the pore detail)
#
# BODY (tiles 1001-1004 → vit_body_*.png 2×2 atlas @2048): previously the body was a
# FLAT TONE. The body mesh spans tiles 1001 (neck column!) + 1002/1003/1004; the
# atlas puts each tile in a quadrant and _mixamo_retarget.py remaps the UDIM UVs to
# match. Because the neck shares tile 1001 with the face, the neck finally gets the
# SAME texture region/tone as the face — the real fix for the two-tone neck.
#
# Atlas layout (u right, v up in UV space; PNG rows are top-down):
#   1001 → quadrant (col 0, row 0)   1002 → (col 1, row 0)
#   1003 → (col 0, row 1)            1004 → (col 1, row 1)
#   u' = (frac_u + col) * 0.5 ;  v' = (frac_v + row) * 0.5
import os
os.environ["OPENCV_IO_ENABLE_OPENEXR"] = "1"
import cv2
import numpy as np

DATA = r"C:/Users/Sam/AppData/Roaming/Blender Foundation/Blender/4.5/scripts/addons/CharMorph/data/characters/Vitruvian/textures/4K"
OUT = r"H:/Work01/VitruvianGodot/godot_project"
SKIN_TONE = 0.45          # light/dark albedo blend (matches the head export)
CAVITY_DARKEN = 0.38      # how much the cavity map darkens albedo in creases/pores
FACE_SIZE = 2048
TILE_SIZE = 1024          # per-quadrant size in the 2048 body atlas

def lin2srgb(c):
    a = 0.055
    return np.where(c <= 0.0031308, c * 12.92, (1 + a) * np.power(np.clip(c, 0, None), 1 / 2.4) - a)

def exr(name):
    p = os.path.join(DATA, name)
    im = cv2.imread(p, cv2.IMREAD_UNCHANGED)
    assert im is not None, p
    return im[..., :3].astype(np.float32)   # BGR float linear, top-down rows

def down(im, size):
    return cv2.resize(im, (size, size), interpolation=cv2.INTER_AREA)

def u8(im_linear_bgr):
    return (np.clip(lin2srgb(np.clip(im_linear_bgr, 0, 1)), 0, 1) * 255 + 0.5).astype(np.uint8)

def u8_raw(im):
    return (np.clip(im, 0, 1) * 255 + 0.5).astype(np.uint8)

def bake_tile(tile):
    """albedo(linear BGR), rough(gray), normal(BGR=[nz,ny,nx]) for one UDIM tile, full 4K."""
    light = exr("skin_light_col.%d.exr" % tile)
    dark = exr("skin_dark_col.%d.exr" % tile)
    crc = exr("skin_cavity_rough_coat.%d.exr" % tile)   # B=coat? channels: [B,G,R]=(coat?,rough,cavity)?
    # channel semantics (RGB source: R=cavity, G=rough, B=coat) → BGR indices: R=2, G=1, B=0
    cavity = crc[..., 2]
    rough = crc[..., 1]
    alb = light * (1 - SKIN_TONE) + dark * SKIN_TONE
    alb *= (1.0 - CAVITY_DARKEN + CAVITY_DARKEN * cavity)[..., None]
    # roughness: mild S-curve around 0.5 for breakup without changing the mean much
    rg = np.clip(0.5 + (rough - 0.5) * 1.25, 0, 1)
    disp = exr("skin_disp.%d.exr" % tile)[..., 0]
    gy, gx = np.gradient(disp)
    nx, ny, nz = -gx * 6.0, gy * 6.0, np.ones_like(disp)
    ln = np.sqrt(nx * nx + ny * ny + nz * nz)
    nrm = np.dstack([nz / ln * 0.5 + 0.5, ny / ln * 0.5 + 0.5, nx / ln * 0.5 + 0.5])  # BGR
    return alb, rg, nrm

# ---- FACE (tile 1001) ----
alb, rg, nrm = bake_tile(1001)
cv2.imwrite(os.path.join(OUT, "vit_face_bc.png"), down(u8(alb), FACE_SIZE))
cv2.imwrite(os.path.join(OUT, "vit_face_rough.png"), down(u8_raw(np.dstack([rg] * 3)), FACE_SIZE))
cv2.imwrite(os.path.join(OUT, "vit_face_n.png"), down(u8_raw(nrm), FACE_SIZE))
print("[bake] face 1001 -> vit_face_{bc,rough,n}.png @%d (cavity %.2f)" % (FACE_SIZE, CAVITY_DARKEN))

# ---- BODY atlas (tiles 1001-1004) ----
A = TILE_SIZE * 2
alb_at = np.zeros((A, A, 3), np.uint8)
rg_at = np.zeros((A, A, 3), np.uint8)
n_at = np.zeros((A, A, 3), np.uint8)
QUAD = {1001: (0, 0), 1002: (1, 0), 1003: (0, 1), 1004: (1, 1)}  # (col, row) in UV space
for tile, (col, row) in QUAD.items():
    alb, rg, nrm = bake_tile(tile)
    # UV v=0 is the BOTTOM of the tile; PNG row 0 is the TOP. row(uv)=0 → bottom half of PNG.
    y0 = (1 - row) * TILE_SIZE
    x0 = col * TILE_SIZE
    alb_at[y0:y0 + TILE_SIZE, x0:x0 + TILE_SIZE] = down(u8(alb), TILE_SIZE)
    rg_at[y0:y0 + TILE_SIZE, x0:x0 + TILE_SIZE] = down(u8_raw(np.dstack([rg] * 3)), TILE_SIZE)
    n_at[y0:y0 + TILE_SIZE, x0:x0 + TILE_SIZE] = down(u8_raw(nrm), TILE_SIZE)
    print("[bake] body tile", tile, "-> atlas quadrant", (col, row))
cv2.imwrite(os.path.join(OUT, "vit_body_bc.png"), alb_at)
cv2.imwrite(os.path.join(OUT, "vit_body_rough.png"), rg_at)
cv2.imwrite(os.path.join(OUT, "vit_body_n.png"), n_at)
print("[bake] body atlas -> vit_body_{bc,rough,n}.png @%d" % A)
