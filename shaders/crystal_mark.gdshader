shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
// Where a crystal is about to fall (crystal_fall.gd): its light on the sand. A pool of the
// crystal's colour that quickens as it comes, a bright edge closing in from the outside to the
// size of the hit as `closing` goes 0 -> 1, and cracks of light out from the middle. After it
// lands (scorch = 1): just the cracks, glowing on round its foot.

uniform vec3 color : source_color = vec3(0.65, 0.4, 1.0);
uniform float closing = 0.0;
uniform float scorch = 0.0;
// > 0: this is the shaft of light standing on the mark instead (a cylinder this tall, centred)
uniform float shaft = 0.0;

varying float height;

void vertex() {
	height = VERTEX.y;
}

float hash(float n) {
	return fract(sin(n * 127.1) * 43758.5453);
}

void fragment() {
	if (shaft > 0.0) {
		// Brightest at the sand, gone by the top; it quickens with the mark
		float up = clamp(height / shaft + 0.5, 0.0, 1.0);
		float streak = 0.6 + 0.4 * sin(UV.x * 75.0 + sin(UV.x * 31.0) * 3.0);
		float flicker = 0.75 + 0.25 * sin(TIME * mix(8.0, 26.0, closing));
		ALBEDO = mix(color, vec3(1.0), 0.2) * pow(1.0 - up, 2.2) * streak * flicker * (0.12 + 0.3 * closing);
	} else {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float angle = atan(p.y, p.x);
	// Cracks: a dozen rays of uneven length
	float slice = angle / 6.2832 * 14.0;
	float ray = pow(1.0 - abs(fract(slice) - 0.5) * 2.0, 6.0) * step(r, 0.45 + 0.5 * hash(floor(slice)));
	float fade = 1.0 - smoothstep(0.75, 1.0, r);
	// The hit is the inner 0.6 of the mark; the edge closes in to it
	float edge_at = mix(1.0, 0.6, closing);
	float edge = smoothstep(0.07, 0.0, abs(r - edge_at));
	float pool = (1.0 - smoothstep(0.0, edge_at, r)) * (0.25 + 0.75 * closing);
	float beat = 0.7 + 0.3 * sin(TIME * mix(8.0, 26.0, closing));
	float before = (pool * 1.1 * beat + edge * 2.6 + ray * closing * 1.4) * fade;
	float after = ray * 0.5 * fade * (0.7 + 0.3 * sin(TIME * 2.0 + r * 9.0));
	ALBEDO = mix(color, vec3(1.0), 0.25) * mix(before, after, scorch);
	}
}
