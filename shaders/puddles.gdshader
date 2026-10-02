shader_type spatial;
render_mode cull_disabled;
// All of Mercury's puddles on the floor drawn as one liquid surface: each puddle is a disc, and
// the discs melt together with a smooth union, so neighbours flow into each other like a fluid
// rather than overlapping. The surface swells up from its edges and catches the light like the
// rest of him (the same painted dusk reflected in it). Drawn on a flat plane on the floor.

const int MAX_BLOBS = 32;
uniform vec4 blobs[MAX_BLOBS]; // xy: centre (world x, z), z: unused, w: radius
uniform int count = 0;
uniform float smoothing = 0.32; // how far apart two puddles still reach for each other
uniform float swell = 0.22; // how far in from the edge it takes to reach full height
uniform vec3 sky_top : source_color = vec3(0.1, 0.12, 0.3);
uniform vec3 horizon : source_color = vec3(1.0, 0.62, 0.55);
uniform vec3 ground : source_color = vec3(0.05, 0.06, 0.1);
uniform vec3 grid_glow : source_color = vec3(0.2, 0.45, 1.0);

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float field(vec2 p) {
	float d = 1e5;
	for (int i = 0; i < MAX_BLOBS; i++) {
		if (i >= count) {
			break;
		}
		vec4 b = blobs[i];
		float di = length(p - b.xy) - b.w;
		// smooth minimum: a fillet of liquid between neighbours
		float h = clamp(0.5 + 0.5 * (d - di) / smoothing, 0.0, 1.0);
		d = mix(d, di, h) - smoothing * h * (1.0 - h);
	}
	return d;
}

void fragment() {
	vec2 p = world_pos.xz;
	float d = field(p);
	if (d > 0.0) {
		discard;
	}
	// The slope at the rim: steep at the very edge, flat across the middle
	float e = 0.02;
	vec2 g = vec2(field(p + vec2(e, 0.0)) - d, field(p + vec2(0.0, e)) - d) / e;
	float rim = 1.0 - clamp(-d / swell, 0.0, 1.0);
	vec3 n = normalize(vec3(g.x * rim * 2.2, 1.0, g.y * rim * 2.2));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);

	vec3 view_world = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	vec3 r = reflect(-view_world, n);
	vec3 env = mix(horizon, sky_top, smoothstep(0.0, 0.6, r.y));
	env = mix(env, mix(ground, grid_glow * 0.5, smoothstep(-0.25, 0.0, r.y)), step(r.y, 0.0));
	env += vec3(1.0) * smoothstep(0.012, 0.0, abs(r.y - 0.02)) * 0.8;
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	ALBEDO = vec3(0.25);
	METALLIC = 1.0;
	ROUGHNESS = 0.12;
	EMISSION = env * (0.65 + fresnel * 0.6) + vec3(1.0) * smoothstep(0.0, 0.04, -d) * (1.0 - smoothstep(0.04, 0.09, -d)) * 0.25;
}
