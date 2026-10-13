shader_type sky;
// The sky: the zone's colours from overhead down to a glowing horizon, a big low sun straight down
// the lane (striped like an old synth record sleeve, sinking into the haze), a ridge of distant
// towers and hills along the horizon with lit windows and a rim of light on their edges, and stars
// overhead. Nothing moves (no TIME): it's baked into the reflections once, not every frame.

uniform vec3 sky_top : source_color = vec3(0.04, 0.05, 0.16);
uniform vec3 horizon : source_color = vec3(0.95, 0.5, 0.48);
uniform vec3 ground_color : source_color = vec3(0.015, 0.015, 0.03);
uniform vec3 sun_dir = vec3(0.0, 0.07, -1.0); // the sun's direction from the eye: low, down the lane (-Z)
uniform float sun_size = 0.16; // its radius (radians, roughly)
uniform float star_amount = 1.0;
uniform float skyline = 1.0; // the towers and hills along the horizon (0: none)
// Out in space (the Crystaliens' moon and the ring road round it): stars all the way down, no
// ground below the horizon, and with ring > 0 the moon's ring arching over, edge on
uniform float space = 0.0;
uniform float ring = 0.0;
uniform vec3 ring_axis = vec3(0.25, 0.45, 0.86); // the ring's plane, by the line through its middle

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise1(float x) {
	float i = floor(x);
	float f = fract(x);
	return mix(hash(vec2(i, 0.0)), hash(vec2(i + 1.0, 0.0)), f * f * (3.0 - 2.0 * f));
}

float hash3(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash3(i), hash3(i + vec3(1.0, 0.0, 0.0)), f.x), mix(hash3(i + vec3(0.0, 1.0, 0.0)), hash3(i + vec3(1.0, 1.0, 0.0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0.0, 0.0, 1.0)), hash3(i + vec3(1.0, 0.0, 1.0)), f.x), mix(hash3(i + vec3(0.0, 1.0, 1.0)), hash3(i + vec3(1.0, 1.0, 1.0)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	return noise3(p) * 0.5 + noise3(p * 2.1 + 7.0) * 0.3 + noise3(p * 4.3 + 19.0) * 0.2;
}

// One layer of stars: the sky cut into cells (`scale` of them across a unit of direction), a star
// in `density` of them, somewhere in its cell, round, `size` of the cell wide, its own colour
// (blue-white through yellow to red) and brightness
vec3 stars(vec3 d, float scale, float density, float size) {
	vec3 g = d * scale;
	vec3 id = floor(g);
	vec3 where = vec3(hash3(id + 1.0), hash3(id + 2.0), hash3(id + 3.0)) - 0.5;
	float away = length(fract(g) - 0.5 - where * 0.6);
	float lit = step(1.0 - density, hash3(id + 17.0)) * (1.0 - smoothstep(size * 0.3, size, away));
	float heat = hash3(id + 31.0);
	vec3 tint = heat < 0.5 ? mix(vec3(0.6, 0.75, 1.0), vec3(1.0), heat * 2.0) : mix(vec3(1.0), vec3(1.0, 0.6, 0.4), (heat - 0.5) * 1.6);
	return tint * lit * (0.25 + 0.75 * pow(hash3(id + 43.0), 3.0));
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float y = d.y;
	float az = atan(d.x, -d.z); // round the horizon, 0 straight down the lane

	// The gradient, with a hot haze hugging the horizon
	vec3 col = mix(horizon, sky_top, pow(smoothstep(-0.02, 0.6, y), 0.55));
	col += horizon * exp(-abs(y) * 22.0) * 0.45;
	// (in space the sky's black nearly to the horizon: only a thin glow along it)
	col = mix(col, sky_top + horizon * exp(-abs(y) * 16.0) * 0.3, space);

	if (space > 0.5) {
		// Deep sky: a river of stars and dust across it, clouds of glowing gas in the zone's
		// colours, and stars of every size and temperature (what moves up there, the comets and
		// the rest, is the sky show's: sky_show.gdshader)
		vec3 across = normalize(vec3(0.55, 0.62, -0.56)); // the line through the river's poles
		float off = dot(d, across);
		float river = exp(-off * off * 14.0);
		float dust = fbm(d * 5.0 + 3.0);
		float lanes = smoothstep(0.34, 0.74, fbm(d * 9.0 + vec3(0.0, 4.0, 0.0) + dust));
		vec3 warm = mix(horizon, vec3(1.0, 0.8, 0.6), 0.45);
		vec3 cool = mix(vec3(horizon.b, horizon.r, horizon.g), vec3(0.4, 0.8, 1.0), 0.5);
		col += mix(cool, warm, dust) * river * (0.05 + 0.2 * dust * dust) * (1.0 - lanes * 0.85);
		// Gas clouds, off the river
		float gas = smoothstep(0.52, 0.85, fbm(d * 2.3 + 11.0));
		float gas_b = smoothstep(0.55, 0.9, fbm(d * 3.1 + 27.0));
		col += horizon * gas * (0.05 + 0.12 * fbm(d * 14.0)) + cool * gas_b * (0.03 + 0.09 * fbm(d * 11.0 + 5.0));
		// Stars: a fine dust of them (thicker in the river), then fewer and brighter
		float crowd = 1.0 + river * 2.5 * (1.0 - lanes);
		col += stars(d, 150.0, 0.22 * crowd, 0.2) * 0.55 * star_amount;
		col += stars(d, 70.0, 0.1 * crowd, 0.2) * 1.2 * star_amount;
		col += stars(d, 30.0, 0.05, 0.16) * 3.0 * star_amount;
	} else {
		// Stars, fading out toward the horizon's glow
		vec2 cell = floor(vec2(az * 260.0 / 3.1416, y * 260.0));
		float star = step(0.9965, hash(cell)) * smoothstep(0.12, 0.45, y);
		col += vec3(0.85, 0.9, 1.0) * star * (0.4 + 0.6 * hash(cell + 7.0)) * star_amount;
	}

	// The sun: a soft glow all round it, the disc warm at the top and the horizon's colour below,
	// cut by bands that thicken toward its foot
	vec3 sd = normalize(sun_dir);
	float s = acos(clamp(dot(d, sd), -1.0, 1.0));
	col += horizon * (exp(-s * 5.0) * 0.55 + exp(-s * 18.0) * 0.5);
	// (out in space it's a plain small star, not the striped sun)
	float size = sun_size * mix(1.0, 0.4, space);
	if (s < size && space > 0.5) {
		col = mix(col, mix(horizon, vec3(1.0, 0.97, 0.9), 0.8) * 2.2, 1.0 - smoothstep(size * 0.9, size, s));
	} else if (s < sun_size && space < 0.5) {
		float v = clamp((y - (sd.y - sun_size)) / (2.0 * sun_size), 0.0, 1.0); // 0 at its foot, 1 at its top
		vec3 disc = mix(horizon * 1.4, vec3(1.0, 0.9, 0.55) * 1.8, v);
		float band = step(fract(v * 9.0), mix(0.55, 0.05, v)) * step(v, 0.55);
		float edge = smoothstep(sun_size, sun_size * 0.97, s);
		col = mix(col, disc, edge * (1.0 - band));
	}

	// The skyline: hills, with blocks of towers rising out of them, the haze in front
	float hills = 0.012 + 0.03 * noise1(az * 3.0) + 0.012 * noise1(az * 11.0);
	float block = floor(az * 70.0);
	float tower = step(0.55, hash(vec2(block, 3.0))) * (0.012 + 0.05 * pow(hash(vec2(block, 9.0)), 2.0));
	tower *= 1.0 - smoothstep(0.6, 1.4, abs(az)); // the city off to either side of the sun, not in front of it
	tower = max(tower, step(0.8, hash(vec2(block, 5.0))) * 0.02 * smoothstep(1.2, 2.2, abs(az)));
	float ridge = max(hills, hills + tower * (1.0 - smoothstep(2.6, 3.0, abs(az))));
	if (y > -0.01 && y < ridge && skyline > 0.5) {
		float depth = clamp((ridge - y) / 0.03, 0.0, 1.0);
		vec3 silhouette = mix(horizon * 0.35, sky_top * 0.6 + ground_color, depth);
		// Lit windows on the towers
		vec2 win = vec2(az * 900.0, y * 520.0);
		float lit = step(0.86, hash(floor(win))) * step(hills + 0.004, y) * step(0.2, fract(win.x)) * step(0.3, fract(win.y));
		silhouette += mix(horizon, vec3(1.0, 0.85, 0.6), 0.5) * lit * 0.9;
		// The rim of light along the top edge
		silhouette += horizon * smoothstep(0.004, 0.0, ridge - y) * 0.8;
		col = silhouette;
	}

	// Below the horizon: the dark ground, a little of the haze reflected in it
	if (y < -0.01 && space < 0.5) {
		col = mix(ground_color + horizon * 0.12, ground_color, smoothstep(-0.01, -0.25, y));
	}
	// The ring: a band of bright lanes with dark gaps between, seen from down on the moon
	if (ring > 0.0) {
		float off = dot(d, normalize(ring_axis)); // how far off the ring's plane this way looks
		float band = smoothstep(0.075, 0.06, abs(off));
		float lanes = 0.35 + 0.65 * noise1(off * 260.0 + 40.0) * step(0.25, noise1(off * 90.0));
		col += mix(horizon, vec3(1.0), 0.45) * band * lanes * ring * 0.55;
	}
	COLOR = col;
}
