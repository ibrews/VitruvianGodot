/**
* MIT License
*
* Based on algorithms listed in the book OpenGL Shading Language by Randi J Rost
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

/*
* For these methods, 'base' is the bottom image being overlaid and 'blend' is the
* image being laid on top of it.
* 
*/

#include "res://addons/eyeball_shader/shaders/random.gdshaderinc"

const vec4 WHITE = vec4(1.0, 1.0, 1.0, 1.0);
const vec4 LUM_COEFF = vec4(.2125, .7154, .0721, 1.0);

vec4 blend_normal(vec4 base, vec4 blend) {
	return mix(base, blend, blend.a);
}

vec4 blend_average(vec4 base, vec4 blend) {
	return mix(base, (blend + base) / 2.0, blend.a);
}

vec4 blend_dissolve(vec4 base, vec4 blend, vec2 uv, float opacity) {
	float rand_val = random_f2(uv);
	vec4 result = rand_val > opacity ? blend : base;
	return mix(base, result, blend.a);
}

vec4 blend_behind(vec4 base, vec4 blend) {
	return mix(base, blend, blend.a);
}

vec4 blend_erase(vec4 base, vec4 blend) {
	return vec4(base.rgb, (1.0 - blend.a) * base.a);
	//return mix(base, blend, blend.a);
}

vec4 blend_darken(vec4 base, vec4 blend) {
	return mix(base, min(blend, base), blend.a);
}

vec4 blend_lighten(vec4 base, vec4 blend) {
	return mix(base, max(blend, base), blend.a);
}

vec4 blend_multiply(vec4 base, vec4 blend) {
	return mix(base, blend * base, blend.a);
}

vec4 blend_screen(vec4 base, vec4 blend) {
	return mix(base, WHITE - ((WHITE - blend) * (WHITE - base)), blend.a);
}

vec4 blend_color_burn(vec4 base, vec4 blend) {
	return mix(base, WHITE - (WHITE - base) / blend, blend.a);
}

vec4 blend_color_dodge(vec4 base, vec4 blend) {
	return mix(base, base / (WHITE - blend), blend.a);
}

vec4 blend_color_overlay(vec4 base, vec4 blend) {
	float lum = dot(base, LUM_COEFF);
	vec4 result;
	
	if (lum < .45)
	    result = 2.0 * blend * base;
	else if (lum > .55)
		result = WHITE - 2.0 * (WHITE - blend) * (WHITE - base);
	else {
		vec4 result1 = 2.0 * blend * base;
		vec4 result2 = WHITE - 2.0 * (WHITE - blend) * (WHITE - base);
		result = mix(result1, result2, (lum - .45) * 10.0);
	}
	
	return mix(base, result, blend.a);
}

vec4 blend_soft_light(vec4 base, vec4 blend) {
	float lum = dot(base, LUM_COEFF);
	
	return mix(base, 2.0 * base * blend + base * base - 2.0 * base * base * blend, blend.a);
}

vec4 blend_hard_light(vec4 base, vec4 blend) {
	float lum = dot(blend, LUM_COEFF);
	vec4 result;
	
	if (lum < .45)
	    result = 2.0 * blend * base;
	else if (lum > .55)
		result = WHITE - 2.0 * (WHITE - blend) * (WHITE - base);
	else {
		vec4 result1 = 2.0 * blend * base;
		vec4 result2 = WHITE - 2.0 * (WHITE - blend) * (WHITE - base);
		result = mix(result1, result2, (lum - .45) * 10.0);
	}
	
	return mix(base, result, blend.a);
}

vec4 blend_add(vec4 base, vec4 blend) {
	return mix(base, blend + base, blend.a);
}

vec4 blend_subtract(vec4 base, vec4 blend) {
	return mix(base, blend - base, blend.a);
}

vec4 blend_difference(vec4 base, vec4 blend) {
	return mix(base, abs(blend - base), blend.a);
}

vec4 blend_inverse_difference(vec4 base, vec4 blend) {
	return mix(base, WHITE - abs(WHITE - blend - base), blend.a);
}

vec4 blend_exclusion(vec4 base, vec4 blend) {
	return mix(base, base + blend - (2.0 * base * blend), blend.a);
}
