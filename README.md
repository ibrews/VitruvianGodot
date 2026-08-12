# VitruvianGodot

A **fully CC0 / EULA-free real-time digital human** running in **stock Godot 4.6
Forward+** — rigged body, animation, an expressive FACS face, eyes, and physics
hair, with no Epic MetaHuman EULA and no Unreal. The base character is the
**"Vitruvian"** human (offshoot of Olaf Delgado-Friedrichs' CC0 *Antonia Polygon*)
from the [CharMorph](https://github.com/Upliner/CharMorph-Vitruvian) Blender add-on.
Everything here can be redistributed, cloud-rendered, and shipped in closed-source
commercial products.

A free counterpart to the [MetaHumanGodot](https://github.com/ibrews/MetaHumanGodot)
pipeline — same Godot Forward+ rendering tech (AgX, SSIL, screen-space SSS, the
MatMADNESS `skin_shader_local` stack), only the source character is CC0.

![poster](out/vitruvian_poster.png)

## What's in it
- **Full character** — head + body + clothing (tee/pants), one coherent figure.
- **Real FACS face** — a curated set of the Vitruvian project's **100+ FACS
  blendshapes** (shipped as CharMorph `morphs/L3/*.npz`): `Jaw_Lower`,
  `Mouth_Large_Opened` (jaw + teeth + tongue move together → a genuine open mouth),
  the `Happy/Sad/Angry/Scared/Disgusted/Thinking/Kiss` emotions, brows,
  `Eyes_Closed_Max` (blink), and speech **visemes** (`aa`, `ow`, `p_b_m`, …).
- **Mixamo locomotion** — 6 clips (Idle / Sway / Walk / Turn / Wave / HappyIdle)
  retargeted onto the CharMorph rig and playable by name.
- **Physics hair** — Hair Tool–style scalp cards skinned to a spring-bone chain
  (verlet jiggle) with body-sphere collision; a jaw-length bob.
- **Procedural eyes** — iris/pupil/sclera shader, gaze saccades, off-white sclera,
  optional eyeshadow.
- **Two apps**: an interactive **Look-Dev** tool (animation + expression buttons,
  lighting presets, ~50 material/light sliders, save/load presets) and an
  auto-playing **Cinematic** showcase reel.

## Run it
Download the prebuilt Windows `.exe`s from the
[**Releases**](https://github.com/ibrews/VitruvianGodot/releases) page, **or** run
from source with stock Godot 4.6:
```
Godot_v4.6 --path godot_project scenes/vitruvian_lookdev.tscn      # interactive look-dev
Godot_v4.6 --path godot_project scenes/vitruvian_cinematic.tscn    # cinematic reel
```
Look-Dev controls: orbit = LMB drag · wheel zoom · RMB/MMB pan · `H` toggles the UI.
Click the **animation** + **expression** buttons (smile / jawopen / talk / surprise
/ frown / angry / blink), the **lighting presets**, and tweak the sliders; **Save
settings** writes `look_settings.json` (loaded on startup).

### Progressive Web App

Install the Godot Web export templates, then build the installable offline PWA:

```bash
GODOT_BIN=Godot_v4.6 ./scripts/build-web.sh
```

Serve `dist/` over HTTPS. The Web preset is single-threaded for Safari and iOS,
and uses the WebGL2 Compatibility renderer with a browser-safe skin material.

## Repo layout
```
godot_project/                 Godot 4.6 project (Forward+)
  scenes/
    vitruvian_lookdev.{gd,tscn}    interactive look-dev / capture tool
    vitruvian_cinematic.{gd,tscn}  auto-playing showcase reel
    hair_spring.gd                 spring-bone hair physics + body collision
    skin_shader_local.gdshader     MatMADNESS skin (SSS, micro-detail)
    hairtool_card.gdshader         hair-card shader (alpha_to_coverage)
  vitruvian_head.glb             head: skin+lips (FACS morphs) + VitMouth interior + eyes
  vitruvian_body.glb             rigged Mixamo body + clothing + animations
  vitruvian_hair_rigged.glb      spring-bone-skinned hair cards
  vit_*.png                      face / eye / hair textures (CC0)
  look_settings.json             saved look-dev preset (loaded on launch)
blender_prep/                  Blender 4.5 scripts that build the GLBs
  _export_head_blendshapes.py     head + FACS blendshapes (from morphs/L3) + eyes
  _mixamo_retarget.py             world-space retarget of Mixamo clips + clothing/occlusion
  build_vitruvian_hair.py         procedural Hair Tool card groom
  _hair_springrig.py              skins the hair cards to the spring chain
  _ht_make_strand_atlas.py        bakes the strand opacity/normal/AO atlas
  vitruvian_rigged.blend          rig source used by the retarget
  mixamo/                         the 6 source Mixamo FBX clips
out/                           rendered showcase video + poster (also a Release asset)
dist/                          built .exe demos (shipped as Release assets)
```

## How it's built (`blender_prep/`)
Run with `blender --background <file>.blend --python <script>.py`:
1. **Head** (`_export_head_blendshapes.py` on CharMorph's `char.blend`): isolate the
   head at the jaw (`z > 1.50`), split UDIM tile **1006** (the real mouth bag: gums,
   tongue, teeth — textured by `vit_mouth.png`) into a 2nd `VitMouth` surface, then
   bake a curated set of the **L3 FACS morphs** as shape keys (mapped through a
   tracked original-vertex index). Add procedural eyeballs + a tinted-eyeshadow shell.
2. **Body** (`_mixamo_retarget.py` on `vitruvian_rigged.blend`): retarget the 6 Mixamo
   FBX onto the CharMorph armature via a world-space constraint bake, fit the clothing,
   occlusion-delete the skin hidden under the clothes (**keeping** the neck-column skin
   so the neck flows into the collar), inflate the shirt slightly, and export with the
   animation actions.
3. **Hair** (`build_vitruvian_hair.py` → `_hair_springrig.py`): build tapered scalp
   cards from the CharMorph hairstyle guide strands (clipped to a jaw-length bob, lifted
   off the forehead), then skin them to a 5-bone spring chain for in-engine physics.

In Godot, the face is driven by **native blend shapes** (`set_blend_shape_value`,
which deforms both the skin and the `VitMouth` interior), and the hair runs the
`HairSpring` verlet sim against body collision spheres each frame.

## License
The Vitruvian character, its morphs/FACS blendshapes, and textures are **CC0**
(see CharMorph-Vitruvian + *Antonia Polygon*). Mixamo animations are free for use
under Adobe's license. This project's code is MIT. See `NOTICE.md` for full credits.

## Support

If you like seeing this kind of thing get built and shared, [donations are always welcome](https://www.alexcoulombepresents.com/support) — they buy hardware, render time, and the freedom to keep giving most of this away.
