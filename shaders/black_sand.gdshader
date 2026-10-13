shader_type spatial;
// Black sand: the floor of the Crystaliens' moon (the colosseum, and the ring road round it).
// Dark and matte, mottled, with wind ripples across it and grains that glint as you move past.
// Drawn in world space, so a floor that follows the runner doesn't slide. Optionally a glowing
// grid over it (line_amount; the endless lane keeps its zone's lines).

uniform vec3 sand : source_color = vec3(0.05, 0.046, 0.06);
uniform vec3 sheen : source_color = vec3(0.55, 0.35, 1.0); // what the grains glint with
uniform float ripple_size = 1.6; // metres between ripples
uniform vec3 line_color : source_color = vec3(0.6, 0.3, 1.0);
uniform float line_amount = 0.0;
uniform float cell = 4.0;

varying vec3 world;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world.xz;
	// Patches of finer and coarser sand
	float patch = noise(p * 0.07) * 0.6 + noise(p * 0.31) * 0.4;
	// Ripples lying across the wind, wandering a little, fading out in some patches
	float wander = noise(p * 0.09) * 5.0;
	float wave = sin((p.x * 0.35 + p.y) * 6.2832 / ripple_size + wander);
	float ripples = wave * smoothstep(0.35, 0.7, patch);
	vec3 col = sand * (0.55 + patch * 0.9 + ripples * 0.3);
	// Grains that catch the light: which ones changes as the eye moves
	vec2 grain = floor(p * 26.0);
	float catchlight = hash(grain + floor(dot(VIEW, vec3(7.0, 3.0, 5.0)) * 4.0));
	float glint = step(0.9965, catchlight) * (0.4 + 0.6 * hash(grain + 3.0));
	float near = 1.0 - smoothstep(6.0, 34.0, length(VERTEX)); // (only close by: far off they'd just shimmer)
	ALBEDO = col;
	EMISSION = sheen * glint * near * 0.9;
	// The lane's grid, when it has one
	if (line_amount > 0.0) {
		vec2 g = abs(fract(p / cell - 0.5) - 0.5) * cell;
		float line = 1.0 - smoothstep(0.03, 0.09, min(g.x, g.y));
		EMISSION += line_color * line * line_amount;
	}
	ROUGHNESS = 0.95;
	SPECULAR = 0.08;
}
