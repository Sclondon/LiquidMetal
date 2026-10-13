shader_type canvas_item;
// Lines of speed, after a boost ring (hud.gd): thin pale streaks running in from the edges of
// the screen toward its middle, none in the middle itself. strength: 1 as the boost hits,
// easing to 0.

uniform float strength : hint_range(0.0, 1.0) = 0.0;

float hash(float n) {
	return fract(sin(n * 91.7) * 43758.5453);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float around = atan(p.y, p.x);
	float out_from = length(p);
	// One streak to a thin wedge, most wedges empty
	float wedge = floor(around * 70.0);
	float there = step(0.7, hash(wedge));
	float across = abs(fract(around * 70.0) - 0.5);
	// Each a dash running outward, over and over, at its own pace
	float run = fract(out_from * 1.2 - TIME * (2.5 + hash(wedge + 3.0) * 2.0) + hash(wedge + 7.0));
	float dash = smoothstep(0.0, 0.25, run) * (1.0 - smoothstep(0.55, 1.0, run));
	float edge = smoothstep(0.5, 1.15, out_from);
	COLOR = vec4(0.85, 0.94, 1.0, there * dash * edge * (1.0 - smoothstep(0.15, 0.5, across)) * strength * 0.7);
}
