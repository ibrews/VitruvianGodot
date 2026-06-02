/**
* MIT License
*
* Copyright (c) 2024 Mark McKay
* https://github.com/blackears/eyeball_shader
*
* Permission is hereby granted, free of charge, to any person obtaining a copy
* of this software and associated documentation files (the "Software"), to deal
* in the Software without restriction, including without limitation the rights
* to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
* copies of the Software, and to permit persons to whom the Software is
* furnished to do so, subject to the following conditions:
*
* The above copyright notice and this permission notice shall be included in all
* copies or substantial portions of the Software.
*
* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
* IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
* FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
* AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
* LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
* OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
* SOFTWARE.
*/

shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

group_uniforms color_and_size;
uniform float iris_radius:hint_range(0.0, 1.0, 0.01) = .25;
uniform float iris_margin:hint_range(0.0, 1.0, 0.01) = .02;
uniform float pupil_radius:hint_range(0.0, 1.0, 0.01) = .1;

uniform vec3 eye_white:source_color = vec3(1, 1, 1);
uniform vec3 pupil_color:source_color = vec3(0, 0, 0);
uniform sampler2D texture_iris_color : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D texture_iris_ring_dodge : source_color, filter_linear_mipmap, repeat_disable, hint_default_black;
uniform sampler2D texture_iris_ring_mult : source_color, filter_linear_mipmap, repeat_disable, hint_default_white;


group_uniforms iris_cell_properties;
uniform float eye_cell_scale:hint_range(1.0, 20.0, 0.1) = 17;
uniform float eye_cell_jitter:hint_range(0.0, 1.0, 0.1) = .6;
uniform float iris_pinch:hint_range(0.0, 1.0, 0.01) = .6;
uniform uint iris_cells_num_octaves = 1;
uniform float iris_cells_lacunarity = 2;
uniform float iris_cells_weighted_strength = .5;

group_uniforms other;
uniform uint rand_seed;

uniform vec3 uv1_scale = vec3(1, 1, 1);
uniform vec3 uv1_offset;

#include "res://addons/eyeball_shader/shaders/voronoi.gdshaderinc"
#include "res://addons/eyeball_shader/shaders/blend_modes.gdshaderinc"

void vertex() {
	UV = UV * uv1_scale.xy + uv1_offset.xy;
}

void fragment() {
	
	vec2 uv_norm = UV * 2.0 - vec2(1, 1);
	
	float radial_offset = length(uv_norm);
	
	vec2 iris_uv = normalize(uv_norm) * pow(radial_offset, 1.0 - iris_pinch);
	float eye_cell_lum = voronoi_cell_2d(iris_uv * eye_cell_scale, eye_cell_jitter, rand_seed,
		iris_cells_num_octaves, iris_cells_lacunarity, iris_cells_weighted_strength);
	vec3 iris_col = texture(texture_iris_color, vec2(eye_cell_lum, 0)).xyz;

	vec3 col = mix(pupil_color, eye_white, smoothstep(0, 1, (radial_offset - iris_radius) / iris_margin));
	col = mix(iris_col, col, smoothstep(0, 1, (radial_offset - iris_radius + iris_margin) / iris_margin));
	
	col = mix(pupil_color, col, smoothstep(0, 1, (radial_offset - pupil_radius) / iris_margin));

	if (radial_offset >= pupil_radius && radial_offset <= iris_radius) {
		vec4 dodge_col = texture(texture_iris_ring_dodge, vec2((radial_offset - pupil_radius) / (iris_radius - pupil_radius), 0.0));
		vec4 mult_col = texture(texture_iris_ring_mult, vec2((radial_offset - pupil_radius) / (iris_radius - pupil_radius), 0.0));

		col = blend_color_dodge(vec4(col, 1), dodge_col).rgb;
		col = blend_multiply(vec4(col, 1), mult_col).rgb;
	}
	
	ALBEDO = col;
}
