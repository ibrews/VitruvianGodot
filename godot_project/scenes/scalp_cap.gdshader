shader_type spatial;
// Dark scalp dome UNDERLAYER beneath the hair cards. The key trick: its ALPHA
// fades out near the hairline (by world height) so the dome has NO hard rim —
// the hard triangulated rim of an opaque cap is exactly what read as the
// "zigzag hairline / glitchy helmet". Shaded as dark hair (anisotropic) so where
// it shows through the cards it reads as hair-in-shadow, not bald skin.
render_mode cull_disabled, depth_prepass_alpha, diffuse_burley, specular_schlick_ggx;

uniform vec4 hair_color : source_color = vec4(0.030, 0.020, 0.014, 1.0);
uniform float roughness_val : hint_range(0.0, 1.0) = 0.9;
uniform float specular_val : hint_range(0.0, 1.0) = 0.15;
uniform float anisotropy : hint_range(0.0, 1.0) = 0.55;
// World-up (Y) band over which the cap fades from transparent (hairline) to
// opaque (crown). Head AABB Y ≈ 1.49–1.746.
uniform float fade_lo = 1.63;
uniform float fade_hi = 1.71;

void fragment() {
	vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float a = smoothstep(fade_lo, fade_hi, wp.y);
	if (a < 0.01) {
		discard;
	}
	ALBEDO = hair_color.rgb;
	ROUGHNESS = roughness_val;
	SPECULAR = specular_val;
	METALLIC = 0.0;
	ANISOTROPY = anisotropy;
	ANISOTROPY_FLOW = vec2(0.0, 1.0);
	ALPHA = a;
}
