shader_type spatial;
render_mode unshaded, fog_disabled;
// The Crystaliens' moon, seen from the ring road that circles it: a ball of black sand, lit from
// one side by the far-off star, dark dune seas and paler uplands across it, and fields of crystal
// that glow on the night side. It turns slowly as you run (turn: radians).

uniform vec3 sand : source_color = vec3(0.07, 0.065, 0.085);
uniform vec3 crystal : source_color = vec3(0.6, 0.35, 1.0);
uniform vec3 crystal_b : source_color = vec3(0.3, 0.85, 1.0);
uniform vec3 star_dir = vec3(0.0, 0.07, -1.0); // where the light comes from
uniform float turn = 0.0;

varying vec3 local;
varying vec3 world_normal;

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

void vertex() {
	local = normalize(VERTEX);
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// The surface turns under the light (the light and the shape stay put)
	float c = cos(turn);
	float s = sin(turn);
	vec3 p = vec3(local.x * c - local.z * s, local.y, local.x * s + local.z * c);
	float seas = noise(p * 2.2) * 0.6 + noise(p * 6.0) * 0.3 + noise(p * 17.0) * 0.1;
	float dunes = 0.5 + 0.5 * sin((p.y * 40.0 + noise(p * 5.0) * 9.0));
	vec3 ground = sand * (0.45 + seas * 1.3) * (0.85 + dunes * 0.15);
	float lit = smoothstep(-0.12, 0.35, dot(world_normal, normalize(star_dir)));
	// Crystal fields: veins of them where the noise runs high, glowing in the dark
	float field = smoothstep(0.66, 0.86, noise(p * 14.0 + 3.0) * 0.7 + noise(p * 41.0) * 0.3) * (0.35 + 0.65 * noise(p * 150.0));
	vec3 glow = mix(crystal, crystal_b, noise(p * 3.0 + 11.0)) * field;
	// A thin haze of dust on the limb
	float limb = pow(1.0 - clamp(dot(normalize(NORMAL), VIEW), 0.0, 1.0), 4.0);
	ALBEDO = ground * (0.4 + lit * 1.5) + glow * (0.8 - lit * 0.45) + crystal * limb * (0.12 + lit * 0.3);
}
