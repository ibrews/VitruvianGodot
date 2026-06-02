shader_type spatial;
// Hair card alpha-clipped shader.
// Two atlas types are supported via invert_mask:
//   invert_mask=false (default): strand data is in ALPHA channel (RGB=1.0 everywhere).
//                                background alpha=0, strand core alpha up to 1.0.
//   invert_mask=true:            strand data is in RGB luminance (strands on BLACK bg).
//                                background luma~0, strand pixels luma>0.
// Use depth_prepass_alpha so alpha-tested geometry writes depth correctly.
// CULL_DISABLED so cards render from both sides.
// alpha_to_coverage: with MSAA on, the strand edge alpha is resolved into
// coverage samples → smooth antialiased strand edges instead of hard jaggies.
render_mode cull_disabled, alpha_to_coverage, diffuse_burley, specular_schlick_ggx;

uniform vec4 hair_color : source_color = vec4(0.22, 0.14, 0.08, 1.0);
uniform sampler2D coverage_atlas : filter_linear_mipmap, repeat_enable;
// invert_mask=false → read alpha channel (legacy RootUVSeedCoverage atlases)
// invert_mask=true  → read RGB luminance (legacy Texture2D_0 strand atlas)
uniform bool invert_mask = false;
// use_red_mask=true → read the RED channel: this is the real MetaHuman
// CardsAtlas_Attribute per-strand COVERAGE (thin strands on black) → cuts the
// cards into individual strands instead of opaque ribbons. Takes precedence.
uniform bool use_red_mask = false;
// Threshold: fraction of coverage to keep. Higher = sparser/wispier strands.
// For alpha-channel atlases: 0.60 shows only dense strand cores (good for fine wisps).
// For luma atlases: 0.05 shows any non-black strand pixel.
uniform float alpha_threshold : hint_range(0.0, 1.0) = 0.60;
uniform float root_darkening : hint_range(0.0, 1.0) = 0.40;
uniform float roughness_val : hint_range(0.0, 1.0) = 0.55;
uniform float specular_val : hint_range(0.0, 1.0) = 0.30;

void fragment() {
	vec4 atlas = texture(coverage_atlas, UV);

	float strand_val;
	if (use_red_mask) {
		// MetaHuman CardsAtlas_Attribute: R = per-strand coverage (strands on black)
		strand_val = atlas.r;
	} else if (invert_mask) {
		// Strand-on-black atlas (Texture2D_0): luminance is the strand signal
		strand_val = dot(atlas.rgb, vec3(0.299, 0.587, 0.114));
	} else {
		// RootUVSeedCoverage atlas: RGB=1.0 everywhere, strand data is in alpha
		strand_val = atlas.a;
	}

	// Soft transition around the threshold so alpha_to_coverage + MSAA can
	// antialias the strand edges (a hard cutoff is what causes the jaggies).
	float a = smoothstep(alpha_threshold - 0.07, alpha_threshold + 0.07, strand_val);
	if (a <= 0.003) {
		discard;
	}

	// Modulate brightness by strand density: sparser (lower val) = root/darker
	float darken = mix(1.0 - root_darkening, 1.0, strand_val);
	ALBEDO = hair_color.rgb * darken;
	ROUGHNESS = roughness_val;
	SPECULAR = specular_val;
	METALLIC = 0.0;
	ALPHA = a;
}
