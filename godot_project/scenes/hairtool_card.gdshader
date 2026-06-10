shader_type spatial;
// ────────────────────────────────────────────────────────────────────────────
// Hair Tool card shader — lit crown + wispy strand silhouette (NOT a helmet).
//
// The cards carry a baked atlas: a NORMAL map whose normals fan left/right ACROSS
// each card (so the crown — tangent to the skull — catches the side key light),
// AO, a strand DIFFUSE, and a strand COVERAGE/opacity map (dense opaque roots at
// V=1 → wispy transparent tips at V=0). UVMap (TEXCOORD_0) indexes each card into
// its strand column.
//
// ALPHA SCISSOR (opaque cutout), NOT alpha-blend: with 100k+ densely overlapping
// cards, blending smears them into a translucent glassy dome (a "visor"). Hard
// scissor punches real strand-shaped HOLES through the shell → dark scalp shows
// between locks, ragged silhouette, zero translucency / depth-sort fighting.
// ────────────────────────────────────────────────────────────────────────────
// alpha_to_coverage: resolve the card-edge alpha across MSAA samples → SMOOTH,
// anti-aliased strand edges instead of the hard jagged scissor cutout (the "PS1"
// look). Still writes depth (order-independent, no glassy-visor blending).
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx, alpha_to_coverage;

uniform sampler2D tex_diffuse : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_normal : filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_ao : filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_opacity : filter_linear_mipmap, repeat_enable;

// COLOR — root→tip gradient tint multiplied over the baked diffuse. Set both equal
// for a flat tint. brightness scales everything (use to lift/darken overall).
uniform vec4 root_color : source_color = vec4(0.50, 0.40, 0.28, 1.0);
uniform vec4 tip_color  : source_color = vec4(0.62, 0.50, 0.36, 1.0);
uniform float brightness : hint_range(0.0, 8.0) = 3.4;
uniform float diffuse_mix : hint_range(0.0, 1.0) = 1.0;  // 0 = ignore baked diffuse, pure tint

uniform float normal_strength : hint_range(0.0, 4.0) = 1.0;
uniform bool flip_green = false;
uniform float ao_strength : hint_range(0.0, 1.0) = 0.6;
uniform float roughness_val : hint_range(0.0, 1.0) = 0.76;
uniform float specular_val : hint_range(0.0, 1.0) = 0.25;
uniform float anisotropy_val : hint_range(-1.0, 1.0) = 0.4;
uniform float tonal_variation : hint_range(0.0, 1.0) = 0.7;
uniform float clump_count : hint_range(4.0, 80.0) = 28.0;     // # of tonal clumps across U
uniform float tip_lighten : hint_range(0.0, 1.0) = 0.18;

// self-emission lifts shadow-side hair off pure black; backlight = light passing
// THROUGH hair (translucency) — the single biggest "real hair" cue.
uniform float emit : hint_range(0.0, 1.0) = 0.15;
uniform vec4 backlight_color : source_color = vec4(0.18, 0.10, 0.05, 1.0);
uniform float backlight_strength : hint_range(0.0, 1.0) = 0.0;

// alpha / coverage
uniform float density : hint_range(0.0, 2.0) = 1.0;   // >1 fuller, <1 wispier
uniform float scissor : hint_range(0.0, 1.0) = 0.35;  // cutout threshold

float hash(vec2 p) { return fract(sin(dot(p, vec2(41.3, 289.1))) * 43758.5453); }

void fragment() {
	vec2 uv = UV;

	// coverage → ALPHA (resolved by alpha_to_coverage for smooth edges). A LOW
	// scissor still hard-discards fully-transparent gaps so the dark scalp shows
	// between locks (ragged silhouette) without depth-sort fighting.
	float cov = texture(tex_opacity, uv).r;
	// sharpen the coverage a touch so AtC has a crisp ramp to anti-alias
	cov = smoothstep(0.12, 0.55, cov);
	ALPHA = clamp(cov * density, 0.0, 1.0);
	ALPHA_SCISSOR_THRESHOLD = scissor;

	vec3 diff = texture(tex_diffuse, uv).rgb;
	float ao = texture(tex_ao, uv).r;

	// root(V≈1)→tip(V≈0) colour gradient, then mix over baked diffuse
	vec3 grad = mix(tip_color.rgb, root_color.rgb, uv.y);
	vec3 base = mix(vec3(0.5), diff, diffuse_mix) * grad * brightness;

	// per-clump tonal variation keyed off the card's U column
	float col_id = floor(uv.x * clump_count);
	float vary = (hash(vec2(col_id, 3.0)) - 0.5) * 2.0 * tonal_variation;
	base *= (1.0 + vary);

	// sun-bleached tips (V≈0 tip)
	base *= mix(1.0 + tip_lighten, 1.0, smoothstep(0.0, 0.6, uv.y));

	ALBEDO = base;
	EMISSION = base * emit;
	// Backlight tinted FROM the hair albedo (not a fixed warm colour) so light passing
	// through the mass doesn't hue-shift the hair golden in profile/backlit angles.
	vec3 bl_tint = mix(grad, backlight_color.rgb, 0.25);
	BACKLIGHT = bl_tint * backlight_strength;
	AO = mix(1.0, ao, ao_strength);
	AO_LIGHT_AFFECT = 1.0;

	vec3 n = texture(tex_normal, uv).xyz * 2.0 - 1.0;
	if (flip_green) n.y = -n.y;
	n.xy *= normal_strength;
	NORMAL_MAP = normalize(n) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 1.0;

	// Specular AA: where the strand normal map changes fast on screen (minified cards),
	// raise roughness so GGX can't alias into white/blue glitter sparks in the dark mass.
	vec3 nvar = fwidth(n);
	float spec_aa = clamp((nvar.x + nvar.y) * 3.0, 0.0, 0.45);
	ROUGHNESS = clamp(roughness_val + spec_aa, 0.0, 1.0);
	SPECULAR = specular_val;
	METALLIC = 0.0;

	// anisotropic strand-flow highlight (flow runs along V = strand axis)
	ANISOTROPY = anisotropy_val;
	ANISOTROPY_FLOW = vec2(0.0, 1.0);
}
