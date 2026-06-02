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
render_mode diffuse_burley, specular_schlick_ggx, blend_add;

uniform float shininess:hint_range(0.0, 800.0, .1) = 200;
// Agile Lens addition: intensity scalar + alpha clamp so the additive cornea
// highlight from bright key/catch lights can't blow the whole cornea to a white
// disc (it did, dead-centre, before clamping).
uniform float spec_intensity:hint_range(0.0, 1.0, 0.01) = 0.4;
uniform float alpha_max:hint_range(0.0, 1.0, 0.01) = 0.85;

void light() {
	vec3 half_vec = normalize(VIEW + LIGHT);
	float n_dot_half = max(0.0, dot(NORMAL, half_vec));
	float pf = pow(n_dot_half, shininess * SPECULAR_AMOUNT) * spec_intensity;

	SPECULAR_LIGHT += pf * ATTENUATION;
	ALPHA = min(ALPHA + pf * ATTENUATION, alpha_max);
}

void fragment() {
	ALPHA = 0.0;
}

