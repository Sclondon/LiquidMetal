shader_type spatial;
render_mode unshaded, cull_disabled;
// The sides of the arena's pit: black at the lip, glowing brighter the further down they go
// (vertex colour alpha: 0 at the top, 1 at the bottom), with bands of light crawling up.

uniform vec3 glow : source_color = vec3(0.7, 0.3, 1.0);

void fragment() {
	float depth = COLOR.a;
	float bands = 0.75 + 0.25 * sin(depth * 30.0 - TIME * 2.0);
	ALBEDO = glow * depth * depth * bands;
}
