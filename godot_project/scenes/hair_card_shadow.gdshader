shader_type spatial;
// Hair-card shader, SHADOW-CASTING variant (explainer match scenes).
// Same strand-mask logic as hair_card.gdshader, but uses depth_prepass_alpha
// instead of alpha_to_coverage so the alpha-tested cards WRITE DEPTH and thus
// cast (and self-shadow) under shadow-enabled lights. cull_disabled keeps both
// faces of the flat cards visible.
render_mode cull_disabled, depth_prepass_alpha, diffuse_burley, specular_schlick_ggx;

uniform vec4 hair_color : source_color = vec4(0.20, 0.13, 0.075, 1.0);
uniform sampler2D coverage_atlas : filter_linear_mipmap, repeat_enable;
uniform bool invert_mask = false;
uniform bool use_red_mask = false;
uniform float alpha_threshold : hint_range(0.0, 1.0) = 0.13;
uniform float root_darkening : hint_range(0.0, 1.0) = 0.42;
uniform float roughness_val : hint_range(0.0, 1.0) = 0.72;
uniform float specular_val : hint_range(0.0, 1.0) = 0.12;

void fragment() {
	vec4 atlas = texture(coverage_atlas, UV);
	float strand_val;
	if (use_red_mask) {
		strand_val = atlas.r;
	} else if (invert_mask) {
		strand_val = dot(atlas.rgb, vec3(0.299, 0.587, 0.114));
	} else {
		strand_val = atlas.a;
	}
	float a = smoothstep(alpha_threshold - 0.05, alpha_threshold + 0.05, strand_val);
	if (a <= 0.003) {
		discard;
	}
	float darken = mix(1.0 - root_darkening, 1.0, strand_val);
	ALBEDO = hair_color.rgb * darken;
	ROUGHNESS = roughness_val;
	SPECULAR = specular_val;
	METALLIC = 0.0;
	ALPHA = a;
}
