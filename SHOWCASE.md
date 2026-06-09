# VITRUVIAN — real-time digital human in stock Godot 4.6 (CC0 / EULA-free)

A fully animated, clothed, hair-physics digital human rendered in **stock Godot 4.6
Forward+** — **no MetaHuman, no Unreal, no Epic assets**. The character derives from the
CC0 "Vitruvian" CharMorph base; all shaders are MIT/CC0.

## Deliverables (`out/`)
- **`vitruvian_showcase.mp4`** — 1280×1280, 28 s, H.264. The reel.
- **`vitruvian_showcase_720.mp4`** — lightweight share version.
- **`vitruvian_poster.png`** — hero still.
- **`dist/VitruvianCinematic.exe`** — run the cinematic live (loops).
- **`dist/VitruvianLookDev_v4.exe`** — interactive look-dev tuner (~50 sliders).

The reel: relaxed idle (breathing) → weight-shift → head-turn → hair-toss, under a hero
camera (slow orbit + push-in to the face beats), 3-point + cool rim + hair-kicker lighting,
AgX tonemap, bloom, depth-of-field, volumetric-ish fog.

## What's real-time here
| Feature | Implementation |
|---|---|
| **Rig + animation** | CharMorph **Mixamo** rig (52 `mixamorig:` bones); glTF actions played by Godot `AnimationPlayer` |
| **Skin** | MatMADNESS-derived SSS skin shader (albedo/normal/roughness, subsurface) |
| **Eyes** | procedural iris/pupil/sclera (radial UV) + glassy cornea shell, bone-attached to the head |
| **Hair** | Hair Tool 4 cards + baked normal/AO/diffuse/opacity atlas, alpha-scissor cutout |
| **Hair physics** | spring-damper **jiggle** driven by head-bone angular velocity (the hair lags/swings) |
| **Clothing** | CharMorph Shirt + Pants, auto-weighted to the rig |

## Pipeline (reproducible)
1. `blender_prep/vitruvian_rigged.blend` — CharMorph mixamo rig applied (`_rig_experiment.py`).
2. `blender_prep/_animated_body_export.py` → `godot_project/vitruvian_body.glb`
   (neck-down body + clothing + armature + 4 glTF actions). Head is cut off; the existing
   static head GLB + hair cards attach to `mixamorig_Head` via `BoneAttachment3D` in Godot.
3. `godot_project/scenes/vitruvian_cinematic.gd` — assembles, lights, animates, jiggles, films.
4. Render via **Godot Movie Maker** (deterministic fixed timestep):
   `CINEMA_MOVIE=1 godot --path godot_project scenes/vitruvian_cinematic.tscn --fixed-fps 30 --write-movie out/cine_mov/frame.png`
5. Assemble: `python blender_prep/_assemble_video.py out/cine_mov out/vitruvian_showcase.mp4 30` (cv2).

## Hard-won gotchas
- **Pose bones with GLOBAL-axis rotation** (`pb.matrix = R_global @ rest`), not local — local
  twists the arm instead of lowering it.
- **AnimationPlayer manual-mode + `seek()` does NOT update the skinned mesh in headless**
  (bones move, mesh stays in bind pose). Use NORMAL `play()` + **Movie Maker** fixed timestep.
- The old "helmet" was a baked `VitScalp` dome from the head export — discarded entirely.

## Known next steps
- Hair re-groom (cards still read slightly chunky in extreme close-up).
- Higher-quality Mixamo locomotion (walk/run) — chip spawned; needs an Adobe login.
- ARKit facial blendshapes — the CC0 base ships **0 shape keys**, so expressions would be
  authored from scratch.
