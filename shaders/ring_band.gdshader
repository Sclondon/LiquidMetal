shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled;
// The moon's ring, away from the runner (ring_world.gd): bands of black sand and crystal dust,
// grooved like a planet's rings, with gaps you see the stars through. The three suns light it:
// low over the ring, they glance off the dust toward the eye (brightest looking sunward) and
// catch the grit as glints, and the moon's shadow falls across the far side. solid: the runner's
// own band (no gaps: it is sand). kerb: the line of crystal along its edges.
// UV: x metres out from the middle of the runner's band, y metres round.

uniform vec3 tint : source_color = vec3(0.65, 0.4, 1.0); // the zone's crystal
uniform vec3 dust : source_color = vec3(0.34, 0.31, 0.36);
uniform float solid = 0.0;
uniform float kerb = 0.0;
uniform vec3 sun_0 = vec3(0.0, 0.07, -1.0);
uniform vec3 sun_1 = vec3(0.55, 0.22, -0.8);
uniform vec3 sun_2 = vec3(-0.62, 0.42, -0.66);
uniform vec3 sun_colour_0 = vec3(1.0, 0.95, 0.88);
uniform vec3 sun_colour_1 = vec3(0.55, 0.34, 0.165);
uniform vec3 sun_colour_2 = vec3(0.22, 0.3, 0.4);
uniform vec3 moon_at = vec3(-1500.0, -150.0, 0.0); // (in the ring's own space)
uniform float moon_radius = 1150.0;

varying vec3 local;
varying vec3 world_pos;

float hash(float n) {
	return fract(sin(n * 127.1) * 43758.5453);
}

float noise(float x) {
	float i = floor(x);
	float f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(hash(i), hash(i + 1.0), f);
}

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// How much of a sun reaches this point: none in the moon's shadow
float lit_by(vec3 sun) {
	vec3 from_moon = local - moon_at;
	float along = dot(from_moon, sun);
	float off = length(from_moon - sun * along);
	return along > 0.0 ? 1.0 : smoothstep(moon_radius * 0.96, moon_radius * 1.06, off);
}

void vertex() {
	local = VERTEX;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float out_m = UV.x;
	// Grooves: wide lanes of thicker and thinner dust, fine lines within them, the odd clean gap
	float lanes = noise(out_m * 0.045 + 3.0) * 0.55 + noise(out_m * 0.19) * 0.3 + noise(out_m * 0.9) * 0.15;
	float fine = 0.75 + 0.25 * noise(out_m * 3.1 + 40.0);
	float gap = smoothstep(0.3, 0.38, lanes);
	float thick = mix(gap * (0.35 + 0.65 * smoothstep(0.3, 0.75, lanes)) * fine, 1.0, max(solid, kerb));
	if (thick < 0.04) {
		discard;
	}
	// Clumps along the band, a little
	thick *= mix(0.85 + 0.15 * noise(UV.y * 0.02 + floor(out_m * 0.1) * 7.0), 1.0, max(solid, kerb));

	vec3 to_eye = normalize(CAMERA_POSITION_WORLD - world_pos);
	float away = length(CAMERA_POSITION_WORLD - world_pos);
	// Each sun: a little on the flat of the ring, much more glancing off toward the eye
	vec3 light = vec3(0.0);
	float glints = 0.0;
	vec3 suns[3] = { normalize(sun_0), normalize(sun_1), normalize(sun_2) };
	vec3 colours[3] = { sun_colour_0, sun_colour_1, sun_colour_2 };
	for (int k = 0; k < 3; k++) {
		float reach = lit_by(suns[k]);
		float toward = max(dot(-to_eye, suns[k]), 0.0);
		light += colours[k] * reach * (0.2 + max(suns[k].y, 0.0) * 0.8 + pow(toward, 3.0) * 1.1 + pow(toward, 24.0) * 2.5);
		glints += reach * (0.3 + toward);
	}
	// Grit catching the light (near enough to make out)
	vec2 cell = floor(vec2(out_m, UV.y) * 0.9);
	float glint = step(0.985, hash2(cell)) * (0.5 + 0.5 * sin(TIME * 3.0 + hash2(cell + 5.0) * 40.0)) * (1.0 - smoothstep(250.0, 900.0, away));

	vec3 colour = mix(dust, tint, 0.22 + 0.2 * noise(out_m * 0.07 + 9.0)) * thick * (0.07 + light * 0.5);
	colour += mix(tint, vec3(1.0), 0.5) * glint * glints * 0.8;
	if (solid > 0.5) {
		// The runner's band: black sand close by (to meet the course's floor), paler with distance
		// as the light glances off it
		colour *= mix(0.3, 1.25, smoothstep(300.0, 1100.0, away));
	}
	if (kerb > 0.5) {
		colour = tint * (0.25 + light * 0.5) * mix(0.5, 1.6, smoothstep(250.0, 900.0, away));
	}
	ALBEDO = colour;
}
