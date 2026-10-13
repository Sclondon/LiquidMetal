shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled;
// A boost ring's aurora (boost_pad.gd): curtains of light standing in a hoop. Rays run back along
// the hoop, crowding and thinning as folds drift round it; the colour goes from green at the
// front edge through blue-green to violet and rose at the back, and the whole thing breathes.
// veil = 1: the faint film across the opening instead (a square: UV 0.5 is the middle).
// UV on the hoop: x round it, y front to back.

uniform float flow = 1.0; // which way, and how fast, the folds drift round
uniform float seed = 0.0;
uniform float strength = 1.0;
uniform float veil = 0.0;

float hash(float n) {
	return fract(sin(n * 127.1) * 43758.5453);
}

// (wraps every `period`, so the hoop has no seam)
float noise(float x, float period) {
	float i = floor(x);
	float f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(hash(mod(i, period)), hash(mod(i + 1.0, period)), f);
}

vec3 aurora(float t) {
	vec3 green = vec3(0.15, 1.0, 0.45);
	vec3 teal = vec3(0.1, 0.75, 0.95);
	vec3 violet = vec3(0.6, 0.3, 1.0);
	vec3 rose = vec3(1.0, 0.3, 0.6);
	return t < 0.35 ? mix(green, teal, t / 0.35) : (t < 0.7 ? mix(teal, violet, (t - 0.35) / 0.35) : mix(violet, rose, (t - 0.7) / 0.3));
}

void fragment() {
	if (veil > 0.5) {
		// The film across the opening: a slow swirl, brighter toward the rim
		vec2 p = UV - 0.5;
		float r = length(p) * 2.0;
		float angle = atan(p.y, p.x);
		float swirl = 0.5 + 0.5 * sin(angle * 3.0 + r * 5.0 - TIME * 1.6);
		float film = smoothstep(0.25, 0.95, r) * (1.0 - smoothstep(0.95, 1.0, r)) * (0.35 + 0.65 * swirl);
		ALBEDO = aurora(fract(angle / 6.2832 + 0.5 + TIME * 0.05)) * film * 0.22;
	} else {
		float round_it = UV.x + TIME * 0.06 * flow;
		// Folds: where the curtain doubles back on itself it's brighter and reaches further back
		float fold = noise(round_it * 9.0 + seed, 9.0) * 0.6 + noise(round_it * 27.0 + seed * 2.0 + TIME * 0.5 * flow, 27.0) * 0.4;
		// Rays: fine streaks along the way through, flickering
		float ray = 0.35 + 0.65 * noise(UV.x * 150.0 + seed * 5.0 + sin(TIME * 1.3 + UV.x * 40.0) * 0.6, 150.0);
		float reach = mix(0.35, 1.0, fold);
		float along = UV.y / reach; // 0 at the front edge, 1 where this fold's light gives out
		float bright = smoothstep(0.0, 0.05, UV.y) * pow(clamp(1.0 - along, 0.0, 1.0), 1.1);
		float breathe = 0.8 + 0.2 * sin(TIME * 2.1 + UV.x * 12.566 + seed);
		vec3 colour = aurora(clamp(along * 1.15 + (fold - 0.5) * 0.35, 0.0, 1.0));
		// (the front edge runs hot: nearly white)
		colour = mix(colour, vec3(0.85, 1.0, 0.9), smoothstep(0.06, 0.0, UV.y) * 0.3);
		ALBEDO = colour * bright * ray * ray * (0.4 + fold * 1.4) * breathe * strength * 2.0;
	}
}
