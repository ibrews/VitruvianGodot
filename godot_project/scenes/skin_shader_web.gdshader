/* WebGL2 fallback for the Forward+-only MatMADNESS skin material. */
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D texture_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D texture_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D texture_roughness : hint_roughness_r, filter_linear_mipmap, repeat_enable;
uniform sampler2D ambient_occlusion_texture : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float normal_strength : hint_range(0.0, 4.0) = 1.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.9;
uniform float roughness_floor : hint_range(0.0, 1.0) = 0.30;
uniform float specular : hint_range(0.0, 1.0) = 0.35;
uniform bool use_ambient_occlusion = false;
uniform float ao_strength : hint_range(0.0, 2.0) = 0.5;
uniform vec3 uv1_scale = vec3(1.0);
uniform vec3 uv1_offset = vec3(0.0);

// These parameters belong to the Forward+ material. Keeping them in the Web
// fallback lets both paths share the same material setup code.
uniform bool double_specularity = false;
uniform float metallic = 0.0;
uniform vec4 metallic_texture_channel = vec4(1.0, 0.0, 0.0, 0.0);
uniform bool use_subsurface_scattering = false;
uniform bool use_noise = false;
uniform float subsurface_scattering_strength = 0.0;
uniform float skin_smoothness = 1.0;
uniform float skin_fallof_smoothness = 1.0;
uniform float sss_depth_scale = 1.0;
uniform bool old_lightwarp_fallof = false;
uniform bool tinted_shadow_penumbra = false;
uniform bool use_micro_detail = false;
uniform float micro_normal_strength = 0.0;
uniform bool translucency = false;
uniform bool use_scatter_map = false;

void vertex() {
	UV = UV * uv1_scale.xy + uv1_offset.xy;
}

void fragment() {
	vec4 base = texture(texture_albedo, UV) * albedo;
	ALBEDO = base.rgb;
	NORMAL_MAP = texture(texture_normal, UV).rgb;
	NORMAL_MAP_DEPTH = normal_strength;
	float authored_roughness = texture(texture_roughness, UV).g;
	ROUGHNESS = clamp(max(authored_roughness * roughness, roughness_floor), 0.0, 1.0);
	SPECULAR = specular;
	if (use_ambient_occlusion) {
		AO = mix(1.0, texture(ambient_occlusion_texture, UV).r, ao_strength);
		AO_LIGHT_AFFECT = 0.35;
	}
}
