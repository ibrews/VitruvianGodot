shader_type canvas_item;
// Subtle photographic vignette (full-screen ColorRect, above 3D, below UI).
uniform float amount : hint_range(0.0, 1.0) = 0.30;
uniform float softness : hint_range(0.0, 1.0) = 0.55;

void fragment() {
	vec2 c = UV - vec2(0.5);
	float d = length(c) * 1.41421356;
	float v = smoothstep(1.0 - softness, 1.25, d) * amount;
	COLOR = vec4(0.0, 0.0, 0.0, v);
}
