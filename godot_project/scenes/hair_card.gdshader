shader_type spatial;
// Hair card alpha-clipped shader.
// Two atlas types are supported via invert_mask:
//   invert_mask=false (default): strand data is in ALPHA channel (RGB=1.0 everywhere).
//                                background alpha=0, strand core alpha up to 1.0.
//   invert_mask=true:            strand data is in RGB luminance (strands on BLACK bg).
//                                background luma~0, strand pixels luma>0.
// depth_prepass_alpha: a depth prepass is run using the alpha test, then the
// colour pass alpha-BLENDS the result → soft, properly antialiased wispy strand
// edges (alpha_to_coverage only had 4 MSAA coverage levels and dithered/"glitched"
// badly where many transparent cards overlap, which read as the helmet).
// CULL_DISABLED so cards render from both sides.
render_mode cull_disabled, depth_prepass_alpha, diffuse_burley, specular_schlick_ggx;

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
// Anisotropic strand-flow specular — THE thing that makes a hair mass read as
// combed hair (a sharp highlight band running across the strand flow) instead of
// a uniform plastic helmet. Flow runs along V (root→tip), i.e. the strand axis.
uniform float anisotropy : hint_range(0.0, 1.0) = 0.0;
// Per-clump tonal variation (some locks lighter/darker) — breaks the flat shell.
uniform float tonal_variation : hint_range(0.0, 1.0) = 0.0;
// Sun-bleach the tips lighter than the roots (V=0 tip … V=1 root).
uniform float tip_lighten : hint_range(0.0, 1.0) = 0.0;
// Break the alpha edge with high-freq noise → the card/fringe boundary becomes
// irregular wispy hairs instead of a hard triangulated zigzag hairline.
uniform float edge_break : hint_range(0.0, 1.0) = 0.0;

float _hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float _hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

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

	// Break the coverage with fine noise so the alpha boundary is irregular (wispy
	// hairs at the fringe) rather than a hard triangulated contour.
	if (edge_break > 0.0) {
		float n = _hash12(UV * vec2(140.0, 30.0));
		strand_val += (n - 0.5) * edge_break;
	}

	// Wide soft transition around the threshold → wispy, feathered strand edges
	// that fade to transparent (this is what opens gaps between clumps and lets
	// the dark scalp read as depth instead of a solid shell).
	float a = smoothstep(alpha_threshold - 0.14, alpha_threshold + 0.14, strand_val);
	// Skip fully-transparent fragments (perf + avoids depth_prepass artefacts, Godot #59015).
	if (a <= 0.01) {
		discard;
	}

	// Base colour, darkened where coverage is thin (root/gaps read darker).
	float darken = mix(1.0 - root_darkening, 1.0, strand_val);
	vec3 col = hair_color.rgb * darken;

	// Tips lighter than roots (UV.y: 1=root, 0=tip).
	col *= mix(1.0, 1.0 + tip_lighten, clamp(1.0 - UV.y, 0.0, 1.0));

	// Per-lock tonal variation keyed on world position → some clumps lighter/darker.
	if (tonal_variation > 0.0) {
		vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
		float tn = _hash13(floor(wp * 220.0));
		col *= 1.0 + tonal_variation * (tn - 0.5);
	}

	ALBEDO = col;
	ROUGHNESS = roughness_val;
	SPECULAR = specular_val;
	METALLIC = 0.0;
	ANISOTROPY = anisotropy;
	ANISOTROPY_FLOW = vec2(0.0, 1.0);   // highlight runs across the strand axis (V)
	ALPHA = a;
}
