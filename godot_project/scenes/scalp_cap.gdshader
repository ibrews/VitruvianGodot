shader_type spatial;
// CROWN HAIR via the scalp dome. On a front-on portrait the flat hair CARDS on
// the crown are edge-on (invisible) — the surface you actually see on top is this
// dome. So we make the DOME read as combed hair:
//   • force an OUTWARD scalp-shell normal (the baked cap normals point inward →
//     that was the dead-dark "brown helmet"); now it lights like a head.
//   • project the strand atlas RADIALLY over the dome (polar UV) so it shows comb
//     striations flowing from the crown out to the hairline — reads as hair, not
//     a smooth shell. The long framing locks (Eve cards) layer over this.
//   • alpha feathers out at the hairline so there is no hard rim.
render_mode cull_disabled, depth_prepass_alpha, diffuse_burley, specular_schlick_ggx;

uniform vec4 hair_color : source_color = vec4(0.075, 0.052, 0.034, 1.0);
uniform sampler2D strand_atlas : filter_linear_mipmap, repeat_enable;
uniform float roughness_val : hint_range(0.0, 1.0) = 0.75;
uniform float specular_val : hint_range(0.0, 1.0) = 0.12;
uniform float anisotropy : hint_range(0.0, 1.0) = 0.5;
// Hairline alpha feather (world-up Y).
uniform float fade_lo = 1.63;
uniform float fade_hi = 1.71;
// Polar strand projection.
uniform vec3 head_center = vec3(0.0, 1.55, 0.0);
uniform float strand_repeats = 34.0;     // strand columns around the dome
uniform float tex_strength : hint_range(0.0, 2.0) = 0.85;
uniform float part_darken : hint_range(0.0, 1.0) = 0.45;
uniform float tonal_variation : hint_range(0.0, 1.0) = 0.4;
// Self-lit fraction: the up-facing crown barely catches the side key, so add part
// of the textured albedo as EMISSION → the comb striations stay visible (a common
// cheat for hard-to-light hair) instead of a dead-dark dome.
uniform float emit : hint_range(0.0, 1.0) = 0.0;

float _hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

void fragment() {
	vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float a = smoothstep(fade_lo, fade_hi, wp.y);
	if (a < 0.01) {
		discard;
	}

	// Outward scalp-shell normal → lights like a head (fixes inward-normal dark).
	vec3 hn = normalize(wp - head_center);

	// Polar strand UV: angle around the vertical axis → U (wraps the atlas columns
	// around the head), height-below-crown → V (samples the textured mid-strand).
	vec2 d = vec2(wp.x - head_center.x, wp.z - head_center.z);
	float ang = atan(d.y, d.x);                          // -PI..PI
	float u = fract(ang / (2.0 * PI) * strand_repeats);
	float down = clamp((fade_hi + 0.06 - wp.y) / 0.20, 0.0, 1.0);
	float v = mix(0.30, 0.78, down);
	float strand = texture(strand_atlas, vec2(u, v)).r;

	// Albedo modulated by strand striations (dark gaps between strands = depth).
	// High contrast so the comb lines actually read on the dim crown.
	vec3 col = hair_color.rgb * (1.0 - tex_strength + tex_strength * (0.12 + 1.7 * strand));

	// Centre part: darken the sagittal (x≈0) crown line where the scalp parts.
	float part = smoothstep(0.0, 0.018, abs(d.x)) ;     // 0 on the part line → 1 away
	col *= mix(1.0 - part_darken, 1.0, clamp(part + (1.0 - down), 0.0, 1.0));

	// Per-lock tonal variation (clump-scale, survives minification).
	col *= 1.0 + tonal_variation * (_hash13(floor(wp * 60.0)) - 0.5);

	NORMAL = normalize((VIEW_MATRIX * vec4(hn, 0.0)).xyz);
	EMISSION = col * emit;
	ALBEDO = col;
	ROUGHNESS = roughness_val;
	SPECULAR = specular_val;
	METALLIC = 0.0;
	ANISOTROPY = anisotropy;
	ANISOTROPY_FLOW = vec2(0.0, 1.0);
	ALPHA = a;
}
