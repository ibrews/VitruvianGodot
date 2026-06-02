# Vitruvian → real-time Godot: researched setup plan (2026-06-02)

Findings from a fan-out, adversarially-verified research pass (23/25 claims
confirmed). Headline: **there is NO turnkey CharMorph "game export"** — its only
documented export is a YAML of morph settings, and the procedural Cycles skin +
refraction-glass eyes don't transfer to a rasterizer. Each problem area needs a
manual Blender bake-and-rebuild. Sources cited inline.

## Resolved locally
- **`Game_Pack` UV exists and is single-tile [0,1]**, head packs in cleanly
  (probed `char.blend`). This is the bake target — no new unwrap needed. (The
  research couldn't confirm it from public docs; our `.blend` has it.)

## 1. SKIN — bake the procedural material to flat PBR (FREE, Cycles native)
Stop hacking textures. Apply CharMorph's real skin material, then Cycles-bake to
the `Game_Pack` UV:
- **Albedo** = Diffuse pass with **Direct + Indirect unchecked** (else lighting
  bleeds in). This resolves the SirMaxim light/dark LUT blend into one map.
- **Roughness** pass (resolves `skin_cavity_rough_coat`).
- **Ambient Occlusion** pass.
- **Normal** pass in **Tangent space** — derived from `skin_disp` displacement
  (plug disp into a Bump/Displacement node so the bake captures it). Tangent
  space is required for a deforming head; Godot StandardMaterial expects it.
- Source: Blender Manual cycles/baking (primary). SimpleBake ($) automates this
  incl. disp→tangent-normal w/ OpenGL/DirectX flip — **but** "auto-converts any
  procedural shader" was REFUTED; native Cycles bake is the safe free path.
- CAVEAT: the LUT-blend may need the colour mix pre-baked first; validate the
  node tree. Our current shader skin already looks good, so this is correctness/
  cleanup, lower priority than eyes/hair.

## 2. EYES — flatten + fake refraction in-shader (FREE)
Vitruvian's eye is a layered refracting glass stack (Sclera_Cornea + AqueosLayer
+ Pupil + Iris) that needs EEVEE ray-tracing — confirmed by the README ("Enable
Screen-Space Reflections and Refractions"). It must be rebuilt:
- **Geometry:** one slightly **egg-shaped eyeball with a cornea dome** (Epic UE
  photoreal-character docs: "distinct dome at the front… almost an egg shape";
  "refraction… handled entirely within the shader, no underlying geometry").
  Merge Vitruvian's eye meshes down to eyeball + (optional) cornea shell.
- **Shader (Godot):** `blackears/godot_eyeball_shader` (MIT, Godot 4.2+, works
  in 4.6) — ships `eyeball_shader.gdshader` + a `cornea.gdshader` glassy shell.
  Iris masked by alpha against sclera; parallax/Depth-Scale fakes the inset iris
  (UE Depth Scale 1.0–1.4, IOR 1.336; Valve EyeRefract parallax ~0.25, packed
  cornea normal RG=normal/B=parallax mask/A=light mult).
- It's an additive-specular approximation, not true refraction — tune to taste.

## 3. HAIR / EYEBROWS / EYELASHES — particle hair → alpha cards
CharMorph grooms are particle hair (guide strands in `hairstyles/*.npz`).
Best-practice real-time path = **alpha-clipped hair cards + a baked atlas**:
- **Hair Tool 4** (joseconseco, Blender 4.2+, **PAID ~$30**): one-click
  curve-hair → mesh haircards AND bakes the atlas (diffuse/AO/normal/opacity/
  root/flow/depth). This is the recommended single tool; same workflow for
  eyebrows + eyelashes (just denser/smaller cards).
- **Free alt:** Daniel Bystedt's "Hair Cards from Curves" (Geometry Nodes,
  3.6+) — deforms *supplied* cards along curves but **does NOT atlas/bake**; you
  bake the alpha atlas separately (Bystedt's Blender Baker, or our own bake).
- Either way: convert CharMorph **particle hair → curves first** (Blender 3.5+
  particle-to-curves), then card-ify.
- Our current procedural ribbon hair (build_vitruvian_hair.py) is the
  zero-addon fallback; it reads OK at portrait distance but isn't true cards.

## Godot 4.6 specifics (verified)
- **No Draco**: Godot can't decode `KHR_draco_mesh_compression` — export GLB
  WITHOUT Draco (use MeshOpt if compression needed). (We already hit this.)
- **Alpha-clipped hair shader**: add explicit `if (ALPHA == 0.00) discard;` in
  `depth_prepass_alpha` materials → ~3× perf (Godot #59015). NOT a universal
  requirement — specific to depth_prepass_alpha.

## Recommended order
1. **Eyes** (free, highest visible payoff) — blackears shader + merge eye geo.
2. **Hair/brows/lashes** — decide Hair Tool 4 ($) vs free Bystedt vs keep ribbons.
3. **Skin bake** (free) — correctness pass, ends texture hacking, real normal.

## Key sources
- Blender Manual — Cycles baking (primary)
- Epic UE photoreal-character eye docs; Valve EyeRefract (primary)
- github.com/blackears/godot_eyeball_shader (MIT, primary)
- joseconseco Hair Tool docs; Bystedt Hair Cards from Curves (primary)
- Godot issues #8576 (no Draco), #59015 (alpha discard)
- CharMorph docs / Vitruvian repo (no game-export path)
