# blender_prep

Scripts that turn CharMorph's Vitruvian data into the Godot-ready head.

## Prerequisites
1. **Blender 4.5** (or 4.4+).
2. **CharMorph** add-on (https://github.com/Upliner/CharMorph, `CharMorph.zip`)
   extracted to your Blender `scripts/addons/CharMorph/`.
3. **Vitruvian data** (~1.12 GB) from
   `https://api.github.com/repos/seenbuklee/CharMorph-Vitruvian/releases/latest`
   (`character.zip`, CC0) extracted to
   `CharMorph/data/characters/Vitruvian/`. (Or use the add-on's in-Blender
   "Download" button.)

## Build the head
```
blender --background \
  ".../CharMorph/data/characters/Vitruvian/char.blend" \
  --python export_vitruvian_head.py
```
Outputs `vitruvian_head.glb` + `vit_*.png` to `out/vitruvian_spike/` (edit the
`OUT` constant). Copy those into `../godot_project/`.

## Probes (diagnostics)
- `vitruvian_probe.py` — Godot-side surface dumper lives in the godot project;
  this dir's `vitruvian_probe.py` / `vitruvian_eye_probe.py` inspect the
  Blender mesh: UDIM tile→poly map, eye material-index classification, bounds.

## Key gotchas learned
- Vitruvian uses **UDIM** (Godot has none) → split per tile.
- **No tangent-space normal map** — detail is in `skin_disp` displacement; we
  derive a TS normal via numpy gradient.
- Camera-facing eye direction is **-Y**; iris sits behind the sclera → push it
  toward the camera and drop the clear cornea/aqueous shells.
- Blender's `Image.save()` on a fresh 8-bit image writes black → we use a tiny
  pure-Python zlib PNG writer instead.
