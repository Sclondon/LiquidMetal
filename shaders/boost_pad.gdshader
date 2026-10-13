shader_type spatial;
render_mode unshaded;
// A boost pad: a plate of pale crystal set in the ground, cut in facets, with light running
// through it in arrowheads the way it boosts you (toward -Z, in its own space).

uniform vec3 color : source_color = vec3(0.55, 0.9, 1.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 uv = UV; // x across, y along (0 at the far end)
	// Facets
	vec2 q = uv * vec2(4.0, 5.0);
	q.x += q.y * 0.5;
	vec2 f = fract(q);
	float shade = hash(floor(q) + step(1.0, f.x + f.y) * 7.3);
	// Arrowheads of light moving along it
	float v = uv.y * 3.0 + abs(uv.x - 0.5) * 2.2 + TIME * 2.2;
	float arrow = smoothstep(0.45, 0.7, fract(v)) * (1.0 - smoothstep(0.8, 0.95, fract(v)));
	float edge = 1.0 - smoothstep(0.0, 0.07, min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y)));
	ALBEDO = color * (0.12 + 0.2 * shade + arrow * (0.7 + 0.5 * shade) + edge * 0.5);
}
