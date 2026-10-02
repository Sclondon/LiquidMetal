shader_type spatial;
render_mode unshaded;
// A boost pad: bright chevrons racing along it the way it boosts you (toward -Z, in its own
// space), on a dark glowing plate with a hard edge.

uniform vec3 color : source_color = vec3(0.2, 1.0, 0.55);

void fragment() {
	vec2 uv = UV; // x across, y along (0 at the far end)
	float edge = step(min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y)), 0.06);
	// Chevrons: a V across the pad, repeating along it and moving
	float v = uv.y * 4.0 + abs(uv.x - 0.5) * 2.2 + TIME * 3.0;
	float chevron = smoothstep(0.55, 0.62, fract(v)) * (1.0 - smoothstep(0.82, 0.9, fract(v)));
	vec3 base = color * 0.12;
	ALBEDO = base + color * (chevron * 1.6 + edge * 1.4);
}
