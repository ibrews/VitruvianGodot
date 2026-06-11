shader_type spatial;
// ────────────────────────────────────────────────────────────────────────────
// VitMouth (UDIM tile 1006: cavity walls + gums + teeth + tongue) shading.
// A real open mouth is mostly DARKNESS — the cavity self-occludes everything
// behind the lip line, with the upper teeth catching a little light. The old
// StandardMaterial lit the whole bag like the face → "muppet mouth".
// Darken albedo with DEPTH INTO THE BAG (model-space Z; the head mesh faces +Z),
// so lips/teeth near the aperture keep their colour and the throat falls to black.
// ────────────────────────────────────────────────────────────────────────────
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D tex_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 tint : source_color = vec4(0.58, 0.46, 0.44, 1.0);
// model-space Z of the lip aperture (front of the bag); darkening ramps in behind it
uniform float front_z = 0.050;
uniform float dark_range : hint_range(0.005, 0.12) = 0.026; // m of ramp to full dark
uniform float dark_floor : hint_range(0.0, 1.0) = 0.045;     // deepest-cavity brightness
uniform float rough = 0.45;
uniform float spec = 0.35;

varying vec3 mpos; // model-space position (post blend-shape, pre skinning/node xform)

void vertex() {
	mpos = VERTEX;
}

void fragment() {
	vec3 alb = texture(tex_albedo, UV).rgb * tint.rgb;
	// depth into the mouth bag → occlusion. Starts just behind the lip line.
	float d = clamp((front_z - mpos.z - 0.004) / dark_range, 0.0, 1.0);
	float occ = mix(1.0, dark_floor, d * d * (3.0 - 2.0 * d)); // smoothstep falloff
	ALBEDO = alb * occ;
	// kill specular deep in the cavity too (a wet sparkle at the back reads wrong)
	ROUGHNESS = mix(rough, 0.9, d);
	SPECULAR = spec * occ;
	METALLIC = 0.0;
}
