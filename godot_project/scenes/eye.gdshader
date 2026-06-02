shader_type spatial;
// Eye shader (v2 — real MetaHuman baked eye textures).
// Composites the real iris disc (T_EyeIris*_BC, centered in UV) over the real
// veined sclera (T_EyeSclera*_BC, full eyeball UV) with their NORMAL maps for
// surface relief (iris fiber + sclera), plus a corneal clearcoat for a wet,
// reflective eye that catches the softbox/reflection-probe.
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D iris_texture : source_color, filter_linear_mipmap;
uniform sampler2D sclera_texture : source_color, filter_linear_mipmap;
uniform sampler2D iris_normal : hint_normal, filter_linear_mipmap;
uniform sampler2D sclera_normal : hint_normal, filter_linear_mipmap;
uniform float iris_radius : hint_range(0.05, 0.5) = 0.27;
uniform float blend_softness : hint_range(0.0, 0.15) = 0.025;
uniform float iris_scale : hint_range(0.5, 4.0) = 1.0;
uniform float roughness_val : hint_range(0.0, 1.0) = 0.03;
uniform float specular_val : hint_range(0.0, 1.0) = 1.0;
uniform float clearcoat_val : hint_range(0.0, 1.0) = 1.0;
uniform float clearcoat_roughness_val : hint_range(0.0, 1.0) = 0.03;
uniform float normal_strength : hint_range(0.0, 2.0) = 0.6;
uniform float sclera_tint : hint_range(0.0, 1.0) = 1.0;  // 1 = full veins, lower = whiter

void fragment() {
	vec2 ctr = UV - vec2(0.5);
	float dist = length(ctr);

	// Iris disc, centered in UV (optionally zoomed).
	vec2 iris_uv = clamp(ctr * iris_scale + vec2(0.5), vec2(0.0), vec2(1.0));
	vec3 iris_rgb = texture(iris_texture, iris_uv).rgb;

	// Real veined sclera at the eyeball's native UV. Mix toward off-white so it
	// doesn't read too pink/gray; sclera_tint controls how much vein detail.
	vec3 sclera_raw = texture(sclera_texture, UV).rgb;
	vec3 sclera_rgb = mix(vec3(0.80, 0.78, 0.76), sclera_raw, sclera_tint);  // not pure white — real sclera is light grey

	float mask = smoothstep(iris_radius, iris_radius + blend_softness, dist);
	ALBEDO = mix(iris_rgb, sclera_rgb, mask);

	// Surface relief: iris fiber normal inside, sclera normal outside.
	vec3 n_iris = texture(iris_normal, iris_uv).rgb;
	vec3 n_scle = texture(sclera_normal, UV).rgb;
	NORMAL_MAP = mix(n_iris, n_scle, mask);
	NORMAL_MAP_DEPTH = normal_strength;

	ROUGHNESS = roughness_val;
	SPECULAR = specular_val;
	METALLIC = 0.0;
	CLEARCOAT = clearcoat_val;
	CLEARCOAT_ROUGHNESS = clearcoat_roughness_val;
}
