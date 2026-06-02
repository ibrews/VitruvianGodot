shader_type spatial;
// Solid hair-colored BACKING shell, rendered just under the strand cards so the
// scalp never shows bald through gaps. Uses a HARD coverage cutoff (no soft
// smoothstep) so it fills densely on the interior but still discards the empty
// background → no silhouette haze. The detailed hair_card.gdshader strands render
// on top (next_pass-style, but as a separate inset mesh) for the strand look.
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec4 hair_color : source_color = vec4(0.20, 0.155, 0.085, 1.0);
uniform sampler2D coverage_atlas : filter_linear_mipmap, repeat_enable;
uniform bool use_red_mask = true;
uniform float cutoff : hint_range(0.0, 1.0) = 0.04;   // low = dense fill
uniform float inset = 0.009;                          // metres pushed toward scalp
uniform float roughness_val : hint_range(0.0, 1.0) = 0.88;

void vertex() {
	// Tuck the shell inside the strand cards along the (outward) card normal.
	VERTEX -= NORMAL * inset;
}

void fragment() {
	float c;
	vec4 atlas = texture(coverage_atlas, UV);
	if (use_red_mask) {
		c = atlas.r;
	} else {
		c = atlas.a;
	}
	if (c < cutoff) {
		discard;   // hard edge: clean discard of empty background, no haze
	}
	ALBEDO = hair_color.rgb;
	ROUGHNESS = roughness_val;
	SPECULAR = 0.12;
	METALLIC = 0.0;
}
