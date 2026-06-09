# Hair Tool 4 → Vitruvian scalp hair cards — FINDINGS (worked)

**Status: SUCCESS + PROMOTED to live demo.** Hair Tool 4 generated good card geometry;
a strand atlas (normal+AO+diffuse+opacity) was wired into Godot with ALPHA-SCISSOR
cutout, and the crown now reads as textured strand hair (not the flat-dark helmet).
Compare `out/baseline_a.png` (old helmet) vs `out/live_a.png` (now). Frontal+3/4:
`out/live_{a,b}.png` (live scene) and `out/hairtool_{a,b}.png` (isolated test scene).

**The live committed `vitruvian_lookdev.gd` WAS edited** (HAIR_GLB → cards, `_make_hair`
→ hairtool_card shader, `_make_scalp` → dark flat base, `_load_and_wire` keeps brows
from the legacy GLB). NOT committed — review the diff. To revert: `git checkout
godot_project/scenes/vitruvian_lookdev.gd`. `vitruvian_hair.glb` is still present
(reused for eyebrows; const `HAIR_GLB_LEGACY`).

## v2 — killing the "it just looks like a helmet" read
The first pass used OPAQUE solid ribbons → a continuous shell = helmet. Fixes that worked:
1. **Strand coverage atlas with real alpha** (`_ht_make_strand_atlas.py`): procedural
   vertical strands across U, dense opaque roots at V≈1 → wispy transparent tips at V≈0
   (matches Hair Tool's UV), with consistent normal/AO/diffuse. Replaces the
   HairStripDepth-derived maps from v1. `vit_hair_opacity.png` is the silhouette-breaker.
2. **ALPHA-SCISSOR, not alpha-blend.** With 100k+ overlapping cards, `depth_prepass_alpha`
   blend smeared them into a translucent **glassy visor** and emission made it glow.
   Hard scissor (opaque cutout) punches real strand holes through the shell → ragged
   silhouette, dark scalp shows between locks, zero translucency. THE key fix.
3. **Dark flat scalp base.** The head's `VitScalp` dome was still painted by
   `scalp_cap.gdshader` as a *combed-hair dome* (bright, emit 0.35) → competed with the
   cards and read as a smooth helmet on top. Reconfigured dark + `tex_strength 0` +
   `emit 0`, keeping its fade (1.65→1.68) so it stays crown-only (a plain material with
   no fade blobbed the whole dome over the forehead — don't do that).
4. Brighten **albedo** (hair_color ~2.0) with LOW specular (~0.25) + high roughness so it
   reads as medium-brown hair without the key light + glow blooming it white; small
   `emit` (~0.15) lifts the shadow side off pure black (safe now that it's opaque).

Remaining weakness (geometry-bound, not shader): on the shadow side the dense long cards
still read as a darkish mass, and locks are a bit chunky. Lower-impact next steps:
fewer/clumpier cards (tweak Interpolated-Strands children count in `hairtool_work.blend`
before converting) or a softer atlas. Shader is near its ceiling.

---

## The pipeline that worked

All Blender steps use **windowed** Blender 4.5 (NOT `--background` for the Hair Tool
operators — they register GPU draw handlers; background-mode image math is fine).
Each launch is `timeout`-bounded and ends with `bpy.ops.wm.quit_blender()`.

### 1. Generate interpolated dense strands  (`_ht_drive1.py`)
Open `vitruvian_hairtool.blend`, enable addon, select `VitEveGuides` (CURVES, already
has `.data.surface = cm_vitruvian`), then under a VIEW_3D `temp_override`:

```python
bpy.ops.object.add_hair_system(mode='INTERPOLATED_STRANDS')
```

This is the key operator (`HTOOL_OT_AddHairSystem`, `hair_baking/hair_geometry_nodes.py:1559`).
With the guide curves as input it adds 3 modifiers: **Hair_System_Setup**,
**Interpolated Strands** (`Hair_System_Main`), **Profile** (`Hair_System_Profile`).
`skip_profile_gen=False` (default) auto-adds the Profile mod → card width + UV regions
+ `HT_Default_Material`. Saved → `hairtool_work.blend`.

NOTE: evaluating the CURVES object to mesh fails ("Object does not have geometry data")
*before* convert — that's normal: the profile mesh output is muted for curves until you
convert. Not an error.

### 2. Convert hair system → card mesh  (`_ht_drive2.py`)
Select the curves, VIEW_3D `temp_override`:

```python
bpy.ops.hair_system.convert_to_mesh()    # ribbons_operations.py:235
```

Produces mesh `VitEveGuides_converted`: **107,172 quads / 164k verts**, UV layers
`['UVMap','HairTool_UV']`, material `HT_Default_Material`, packed vertex colours
`ChannelPacked_FRAO` (Factor/Random/AO). The harmless `Error: Attribute is required and
can't be removed` lines during convert do not stop it (`{'FINISHED'}`). Saved →
`hairtool_work2.blend`. Export GLB with `export_scene.gltf(... export_draco...enable=False,
export_yup=True)` — **no Draco** (Godot 4.6 can't decode it).

UVMap layout (`_ht_probe_uv.py`): the atlas is divided into **vertical strand columns**;
each card occupies one narrow U column, V runs root(≈1)→tip(≈0). UVMap is exported as
TEXCOORD_0 (= Godot `UV`).

### 3. The atlas — derived from Hair Tool's own strand texture  (`_ht_make_atlas.py`)
`HT_Default_Material` (`material_operators.py`) is procedural: it samples a bundled
**`HairStripDepth.png`** (1024², a grayscale strand HEIGHT map, packed in `hair_lib.blend`)
through a `Bump` node — that bump is exactly what makes Hair Tool cards light correctly.
`_ht_inspect_mat.py` extracts that PNG (`bpy.data.images['HairStripDepth.png'].save()`).

Rather than fight Hair Tool's very stateful Cycles atlas bake (`object.bake_hair`,
`hair_baking/hair_bake.py:352` — needs a bundled `BakingHair` scene + a bake Collection +
UV-flatten + ortho-cam alignment; high risk to script headlessly), I derived the maps
**from `HairStripDepth.png` with numpy** (Blender `--background`, pure image math), at 2048:
- **`vit_hair_normal.png`** — Sobel of the height, strong cross-strand X tilt (STR_X=6) so
  normals fan left/right across each card → catches the side key light on the crown.
- **`vit_hair_ao.png`** — blurred height.
- **`vit_hair_diffuse.png`** — dark→light brown ramp by height × AO.
- **`vit_hair_opacity.png`** — local strand contrast (optional; render is opaque by default).

### 4. Clip the over-face drape  (`_ht_clip_export.py`)
Interpolated children draped over the forehead/face. Front of head = **−Y**; face skin
sits at Y≈−0.08..−0.10 (`_ht_probe_geo.py`). bmesh-delete faces whose centroid is
`abs(x)<0.09 and y<-0.045 and z<1.71` — removes only the central forward drape, keeps the
true crown (z>1.71), the back (y≥−0.045) and the side framing locks (|x|>0.09). Re-export GLB.

### 5. Godot wiring + verify
- Copy `hairtool_cards.glb` + `vit_hair_{normal,ao,diffuse,opacity}.png` → `godot_project/`.
- New shader **`scenes/hairtool_card.gdshader`**: `cull_disabled`, samples diffuse/AO via UV,
  sets `NORMAL_MAP` from `vit_hair_normal.png` (the crux), AO, anisotropic strand sheen.
  Opaque by default (no alpha-sort issues across 100k+ overlapping cards); `use_alpha`
  toggles scissored edges.
- Isolated test scene **`scenes/vitruvian_hairtool_lookdev.{gd,tscn}}`** = a copy of the
  real lookdev with `HAIR_GLB="res://hairtool_cards.glb"` and `_make_hair()` rewritten to
  use the new shader. The committed lookdev is left alone.
- `rm .godot/imported/<file>-*` → `--headless --import` → render:
  `NO_LOAD_SETTINGS=1 LOOKDEV_CAPTURE=...out/hairtool <godot> --path godot_project
  scenes/vitruvian_hairtool_lookdev.tscn --resolution 1280x1280`.

---

## To promote into the live demo (when approved)
1. Copy `vit_hair_{normal,ao,diffuse,opacity}.png` + `hairtool_cards.glb` (already in
   `godot_project/`) — keep, or re-export from `hairtool_work2.blend`.
2. Either point the real `vitruvian_lookdev.gd` `HAIR_GLB` at `res://hairtool_cards.glb`
   and swap `_make_hair()` to the `hairtool_card.gdshader` block (see the `_hairtool_`
   copy for the exact code), or merge the cards into `vitruvian_hair.glb`.
3. The dark `VitScalp` dome (`scalp_cap.gdshader`) can stay as a gap-filler under the cards.

## Knobs / next polish (optional)
- Density/length: `add_hair_system` set defaults; in the GUI open `hairtool_work.blend`,
  select the curves, and tweak the **Interpolated Strands** generator node (children count)
  + **Profile** width before converting. Or lower poly count by decimating cards.
- `normal_strength` (1.6) and `anisotropy_val` (0.7) in the shader control crown sheen.
- Set `use_alpha=true` (+ tune `alpha_threshold`) for wispier silhouettes if the opaque
  ribbons read too solid.
- The genuine Hair Tool Cycles bake (for a true baked diffuse incl. colour variation/flow)
  is still available via the GUI: select cards → Hair Tool ▸ Bake panel (set path +
  collection + passes) — only the headless scripting of it was deferred as too stateful.

## Files (all untracked)
- Scripts: `blender_prep/_ht_drive1.py`, `_ht_drive2.py`, `_ht_probe_uv.py`,
  `_ht_inspect_mat.py`, `_ht_make_atlas.py`, `_ht_probe_geo.py`, `_ht_clip_export.py`
- Blends: `blender_prep/hairtool_work.blend` (curves+hair system, pre-convert),
  `hairtool_work2.blend` (converted card mesh)
- Artifacts: `blender_prep/hairtool_out/hairtool_cards.glb`,
  `vit_hair_{normal,ao,diffuse,opacity}.png`, `tex_HairStripDepth_png.png`, `*.log`
- Godot (new, isolated): `godot_project/scenes/hairtool_card.gdshader`,
  `scenes/vitruvian_hairtool_lookdev.{gd,tscn}`, `hairtool_cards.glb`, `vit_hair_*.png`
- Renders: `out/hairtool_a.png`, `out/hairtool_b.png`
