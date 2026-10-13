shader_type spatial;
render_mode unshaded, fog_disabled, blend_mix, depth_draw_never, cull_back;
// The moon's air: a ball a little bigger than the moon (ring_world.gd), mostly clear. Dust and
// haze drift round it in bands and wisps (three layers of noise sliding at their own speeds), and
// the three suns light it: pale and bright over each sun's day, glowing in that sun's colour
// along the edge of its night, a rim of scattered light where you look through the limb toward
// a sun, and nothing on the night side but a little of the crystal fields' glow.

uniform vec3 tint : source_color = vec3(0.65, 0.4, 1.0); // the zone's crystal: the night side's haze
uniform vec3 sun_0 = vec3(0.0, 0.07, -1.0);
uniform vec3 sun_1 = vec3(0.55, 0.22, -0.8);
uniform vec3 sun_2 = vec3(-0.62, 0.42, -0.66);
uniform vec3 sun_colour_0 = vec3(1.0, 0.95, 0.88);
uniform vec3 sun_colour_1 = vec3(0.55, 0.34, 0.165);
uniform vec3 sun_colour_2 = vec3(0.22, 0.3, 0.4);
uniform float turn = 0.0;
uniform float thickness = 1.0;

varying vec3 local;
varying vec3 world_normal;
varying vec3 world_pos;

float hash(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

float noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

// The ball turned about its axis
vec3 spun(vec3 p, float by) {
	float c = cos(by);
	float s = sin(by);
	return vec3(p.x * c - p.z * s, p.y, p.x * s + p.z * c);
}

void vertex() {
	local = normalize(VERTEX);
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Haze: long bands along the lines of latitude, drawn out round the moon, at one speed; big
	// soft storms at another; fine wisps at a third
	vec3 a = spun(local, turn + TIME * 0.012);
	vec3 b = spun(local, turn - TIME * 0.02 + 2.0);
	vec3 c = spun(local, turn + TIME * 0.035 + 4.0);
	float bands = noise(vec3(a.x * 1.6, a.y * 13.0, a.z * 1.6));
	float storms = noise(b * 3.4 + vec3(0.0, bands * 0.8, 0.0));
	float wisps = noise(vec3(c.x * 9.0, c.y * 30.0, c.z * 9.0) + storms * 2.0);
	float haze = smoothstep(0.3, 0.85, bands * 0.5 + storms * 0.35 + wisps * 0.3);

	vec3 n = normalize(world_normal);
	vec3 to_eye = normalize(CAMERA_POSITION_WORLD - world_pos);
	float facing = clamp(dot(n, to_eye), 0.0, 1.0);
	float limb = pow(1.0 - facing, 3.0); // (you look through more of it at the edge)

	vec3 light = vec3(0.0);
	vec3 suns[3] = { normalize(sun_0), normalize(sun_1), normalize(sun_2) };
	vec3 colours[3] = { sun_colour_0, sun_colour_1, sun_colour_2 };
	for (int k = 0; k < 3; k++) {
		float height = dot(n, suns[k]); // the sun over this spot: 1 overhead, 0 on the horizon
		float day = smoothstep(-0.2, 0.45, height);
		// The edge of night: light that came the long way through the air, deeper in colour
		float dusk = exp(-pow((height + 0.02) / 0.17, 2.0));
		vec3 deep = colours[k] * colours[k] / max(max(colours[k].r, colours[k].g), max(colours[k].b, 0.001));
		// Looking through the limb toward the sun: it scatters at you
		float toward = pow(max(dot(-to_eye, suns[k]), 0.0), 3.0);
		float through = limb * smoothstep(-0.45, 0.1, height) * (0.5 + toward * 2.5);
		light += colours[k] * day * 0.55 + deep * dusk * 0.8 + colours[k] * through * 1.4;
	}
	// How much air you look through here: the haze, and more of it toward the limb
	float air = (0.03 + pow(haze, 1.5) * 0.6) * (1.0 + limb * 2.0);
	float bright = max(light.r, max(light.g, light.b));
	// (dust the colour of the sand, lit; on the night side almost nothing, a breath of the
	// crystal's colour on the limb)
	ALBEDO = light * vec3(0.4, 0.38, 0.45) + tint * limb * 0.1;
	ALPHA = clamp(air * (0.03 + bright * 0.5) * thickness + limb * 0.06, 0.0, 0.7);
}
