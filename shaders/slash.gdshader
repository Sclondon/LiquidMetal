shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled;
// One stroke of the dash's X: a crescent of bright metal thrown off the blade, on a flat card
// (the runner sets two of them crossed, flying ahead of him). Sharp along its leading edge,
// streaming away behind it, breaking into droplets at its ends; `spent` runs 0..1 over its life
// (it thins out and tears into streaks as it goes).

uniform vec3 color : source_color = vec3(0.8, 0.9, 1.0);
uniform float spent : hint_range(0.0, 1.0) = 0.0;

float hash(float n) {
	return fract(sin(n * 127.1) * 43758.5453);
}

void fragment() {
	// A crescent: the card's middle is the middle of a circle well below it; the blade is an arc of it
	vec2 p = (UV - vec2(0.5, 1.35)) * vec2(2.0, 2.0); // (so the blade crosses the middle of the card)
	float r = length(p);
	float a = atan(p.x, -p.y); // 0 straight up the card
	float arc = 1.0 - smoothstep(0.55, 0.75, abs(a)); // (it tapers to nothing at its two ends)
	float lead = 1.7; // the leading edge's radius
	float thick = mix(0.22, 0.05, spent) * arc;
	float edge = (1.0 - smoothstep(0.0, 0.02, abs(r - lead))) * arc;
	float body = smoothstep(lead - thick * 2.2, lead, r) * (1.0 - step(lead, r)) * arc;
	// Torn into streaks behind the edge, more as it's spent
	float streak = 0.55 + 0.45 * sin(a * 70.0 + hash(floor(a * 23.0)) * 6.0);
	body *= mix(1.0, streak, 0.35 + spent * 0.65);
	// Beads flung off the ends
	float bead = step(0.93, hash(floor(a * 40.0) + floor(r * 30.0) * 7.0)) * smoothstep(0.4, 0.7, abs(a)) * (1.0 - smoothstep(0.7, 0.85, abs(a))) * (1.0 - smoothstep(lead - 0.25, lead + 0.05, r)) * step(lead - 0.3, r);
	float alive = 1.0 - spent * spent;
	ALBEDO = (vec3(1.0) * (edge * 2.2 + bead * 1.5) + color * body * 1.5) * alive;
}
