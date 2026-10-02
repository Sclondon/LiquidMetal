shader_type canvas_item;
// An N64 look over the whole game: the picture drawn at about 240 lines, then blown up with
// the console's soft bilinear blur rather than as hard pixels, in 16-bit colour (5 bits a
// channel) with an ordered dither, like its framebuffer.

uniform sampler2D screen : hint_screen_texture, filter_nearest;
uniform float lines = 240.0; // the low-res picture's height
uniform float levels = 31.0; // colour steps per channel (5 bits)
uniform float dither = 1.0;

vec3 cell_colour(vec2 cell, vec2 res) {
	return texture(screen, (cell + 0.5) / res).rgb;
}

const float BAYER[16] = { 0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0 };

float bayer4(vec2 p) {
	int index = int(mod(p.x, 4.0)) + int(mod(p.y, 4.0)) * 4;
	return (BAYER[index] + 0.5) / 16.0;
}

vec3 quantised(vec2 cell, vec2 res) {
	vec3 c = cell_colour(cell, res);
	c += (bayer4(cell) - 0.5) * dither / levels;
	return floor(c * levels + 0.5) / levels;
}

void fragment() {
	vec2 size = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 res = floor(vec2(lines * size.x / size.y, lines));
	// Blend the four nearest low-res pixels: the N64's smeary upscale
	vec2 p = SCREEN_UV * res - 0.5;
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec3 a = quantised(i, res);
	vec3 b = quantised(i + vec2(1.0, 0.0), res);
	vec3 c = quantised(i + vec2(0.0, 1.0), res);
	vec3 d = quantised(i + vec2(1.0, 1.0), res);
	COLOR = vec4(mix(mix(a, b, f.x), mix(c, d, f.x), f.y), 1.0);
}
