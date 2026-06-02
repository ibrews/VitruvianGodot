# Licenses & credits

This repository mixes two licenses, kept deliberately separate so the whole
thing is clean for closed-source / commercial / cloud-render use.

## Tool code & shaders — MIT
See `LICENSE`. © 2026 Agile Lens. The skin/eye shaders derive from
**MatMADNESS HumanShaders** (MIT), which build on
RustyRoboticsBV/GodotStandardLightShader.

## Character assets — CC0 (public domain)
`godot_project/vitruvian_head.glb` and the `vit_*.png` textures are derived from
the **"Vitruvian"** base of the **CharMorph** Blender add-on, which ships
Vitruvian under **CC0 1.0** (public domain). No attribution is legally required,
but credit is good form:

- **Vitruvian** by Sean Buckley & Olaf Delgado-Friedrichs (relicensed from
  "Antonia Polygon"), with contributions credited in the CharMorph data
  (Skin LUT: SirMaxim; original Antonia rigging: Upliner; eyebrow geometry:
  Mindfront; lacrimal/sclera textures: J Hill).
- **CharMorph** add-on — Upliner — https://github.com/Upliner/CharMorph (GPLv3
  add-on; the add-on code is NOT included here, only CC0 output assets).

Because the assets are CC0, this repo ships them directly — there is **no**
"bring your own asset" / private-assets split and no EULA encumbrance. This is
the whole point: it sidesteps the Epic MetaHuman EULA that constrains the
sibling `MetaHumanGodot` pipeline.
