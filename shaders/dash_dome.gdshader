shader_type canvas_item;
// The DASH button: a half-round of liquid metal standing on the bottom edge of the screen, as
// wide as the screen. Drawn on a rectangle: the dome is the half-ellipse that fills it. It's a
// bead of mercury: its swell mirrors a painted sky (dark above, a bright band at the horizon, a
// dark floor), slow waves run over it, and its rim catches the light.
//   ready: 1 when a dash is to be had, 0 just after one (it goes dull and comes back up)
//   press: 1 as it's pressed, easing off (a ring runs out from the middle and it flares)

uniform float ready : hint_range(0.0, 1.0) = 1.0;
uniform float press : hint_range(0.0, 1.0) = 0.0;
uniform vec3 glint : source_color = vec3(0.85, 0.92, 1.0);

void fragment() {
	// x: -1 .. 1 across it; y: 0 at the bottom edge .. 1 at its crown
	vec2 p = vec2(UV.x * 2.0 - 1.0, 1.0 - UV.y);
	float r2 = dot(p, p);
	float swell = sqrt(max(1.0 - r2, 0.0));
	// Which way the surface faces there, stirred by waves and by the ring a press sends out
	float wave = sin(p.x * 9.0 + TIME * 1.3) * 0.05 + sin(p.x * 23.0 - TIME * 2.1 + p.y * 7.0) * 0.025;
	float ring = sin((sqrt(r2) - (1.0 - press) * 1.1) * 26.0) * press * 0.25;
	vec3 n = normalize(vec3(p.x + wave + ring * p.x, p.y + wave * 0.6 + ring, swell + 0.12));
	// What it mirrors: looking up the screen is looking up the sky
	float up = n.y * 0.9 + n.z * 0.25;
	vec3 sky = mix(vec3(0.02, 0.03, 0.08), vec3(0.25, 0.3, 0.5), smoothstep(0.2, 1.0, up));
	vec3 band = vec3(0.95, 0.97, 1.0) * exp(-pow((up - 0.42) * 11.0, 2.0));
	vec3 floor_dark = vec3(0.05, 0.05, 0.09) * (1.0 - smoothstep(0.0, 0.35, up));
	vec3 metal = sky + band * 1.1 + floor_dark;
	// A second, thinner streak lower down, and the rim alight
	metal += glint * exp(-pow((up - 0.12) * 16.0, 2.0)) * 0.5;
	float rim = smoothstep(0.86, 1.0, sqrt(r2));
	metal += glint * rim * 0.3;
	// Dull while it gathers itself, flaring as it's pressed
	metal *= mix(0.4, 1.0, ready);
	metal += glint * press * 0.45;
	float inside = 1.0 - smoothstep(0.985, 1.0, sqrt(r2));
	COLOR = vec4(metal, inside * mix(0.7, 0.94, ready));
}
