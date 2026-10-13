shader_type spatial;
render_mode cull_disabled;
// All of Mercury's puddles on the floor drawn as one liquid surface: each puddle is a disc, and
// the discs melt together with a smooth union, so neighbours flow into each other like a fluid
// rather than overlapping. The surface really stands up off the floor (or the wall): the plane is
// finely divided and each vertex is lifted by the liquid's height there, a bead with a rounded,
// surface-tension rim, domed a little across the big ones, with a slow wobble running over it.
// It catches the light like the rest of him (the same painted dusk reflected in it). Drawn on a
// flat plane (PlaneMesh, subdivided), on the floor or turned to lie on a wall; blob centres are
// in the plane's own x / z, and "up" out of the liquid is the plane's own y.

const int MAX_BLOBS = 32;
uniform vec4 blobs[MAX_BLOBS]; // xy: centre (the plane's local x, z), z: unused, w: radius
uniform int count = 0;
uniform vec4 clip = vec4(-1e4, -1e4, 1e4, 1e4); // drawn only inside (min x, min z, max x, max z)
uniform float smoothing = 0.32; // how far apart two puddles still reach for each other
uniform float swell = 0.22; // how far in from the edge it takes to reach full height
uniform float thickness = 0.075; // metres the liquid stands up, once in from the rim
uniform float dome = 0.05; // and how much more the middle of a big puddle bulges
uniform float wobble = 0.006; // the ripple running over it
uniform vec3 sky_top : source_color = vec3(0.1, 0.12, 0.3);
uniform vec3 horizon : source_color = vec3(1.0, 0.62, 0.55);
uniform vec3 ground : source_color = vec3(0.05, 0.06, 0.1);
uniform vec3 grid_glow : source_color = vec3(0.2, 0.45, 1.0);

varying vec2 plane_pos;

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

// How high the liquid stands at p, given the distance field there
float height(vec2 p, float d) {
	if (d >= 0.0) {
		return 0.0;
	}
	float rim = clamp(-d / swell, 0.0, 1.0);
	float bead = 1.0 - (1.0 - rim) * (1.0 - rim); // rounded over at the edge, flat on top
	float bulge = smoothstep(0.0, 1.0, clamp(-d / 0.9, 0.0, 1.0));
	float ripple = sin(p.x * 7.0 + TIME * 2.3) * sin(p.y * 6.0 - TIME * 1.9) + 0.5 * sin((p.x + p.y) * 11.0 + TIME * 3.1);
	return thickness * bead + dome * bulge + wobble * ripple * rim;
}

void vertex() {
	plane_pos = VERTEX.xz;
	VERTEX.y += height(VERTEX.xz, field(VERTEX.xz));
}

void fragment() {
	vec2 p = plane_pos;
	float d = field(p);
	if (d > 0.0 || p.x < clip.x || p.y < clip.y || p.x > clip.z || p.y > clip.w) {
		discard;
	}
	// The surface's slope, from its height either side (per pixel: smoother than the mesh)
	float e = 0.015;
	vec2 px = p + vec2(e, 0.0);
	vec2 pz = p + vec2(0.0, e);
	float h = height(p, d);
	vec2 g = vec2(height(px, field(px)) - h, height(pz, field(pz)) - h) / e;
	vec3 n = normalize((MODEL_MATRIX * vec4(normalize(vec3(-g.x, 1.0, -g.y)), 0.0)).xyz);
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);

	vec3 view_world = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	vec3 r = reflect(-view_world, n);
	vec3 env = mix(horizon, sky_top, smoothstep(0.0, 0.6, r.y));
	env = mix(env, mix(ground, grid_glow * 0.5, smoothstep(-0.25, 0.0, r.y)), step(r.y, 0.0));
	env += vec3(1.0) * smoothstep(0.012, 0.0, abs(r.y - 0.02)) * 0.8;
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	// The rim, where it rolls over, darker underneath: it reads as standing up off the floor
	float rim = 1.0 - clamp(-d / swell, 0.0, 1.0);
	float underside = smoothstep(0.35, 1.0, rim) * 0.45;
	ALBEDO = vec3(0.25);
	METALLIC = 1.0;
	ROUGHNESS = 0.1;
	EMISSION = env * (0.65 + fresnel * 0.6) * (1.0 - underside);
}
