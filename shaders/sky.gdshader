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

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise1(float x) {
	float i = floor(x);
	float f = fract(x);
	return mix(hash(vec2(i, 0.0)), hash(vec2(i + 1.0, 0.0)), f * f * (3.0 - 2.0 * f));
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float y = d.y;
	float az = atan(d.x, -d.z); // round the horizon, 0 straight down the lane

	// The gradient, with a hot haze hugging the horizon
	vec3 col = mix(horizon, sky_top, pow(smoothstep(-0.02, 0.6, y), 0.55));
	col += horizon * exp(-abs(y) * 22.0) * 0.45;

	// Stars, fading out toward the horizon's glow
	vec2 cell = floor(vec2(az * 260.0 / 3.1416, y * 260.0));
	float star = step(0.9965, hash(cell)) * smoothstep(0.12, 0.45, y);
	col += vec3(0.85, 0.9, 1.0) * star * (0.4 + 0.6 * hash(cell + 7.0)) * star_amount;

	// The sun: a soft glow all round it, the disc warm at the top and the horizon's colour below,
	// cut by bands that thicken toward its foot
	vec3 sd = normalize(sun_dir);
	float s = acos(clamp(dot(d, sd), -1.0, 1.0));
	col += horizon * (exp(-s * 5.0) * 0.55 + exp(-s * 18.0) * 0.5);
	if (s < sun_size) {
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
	if (y > -0.01 && y < ridge) {
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
	if (y < -0.01) {
		col = mix(ground_color + horizon * 0.12, ground_color, smoothstep(-0.01, -0.25, y));
	}
	COLOR = col;
}
