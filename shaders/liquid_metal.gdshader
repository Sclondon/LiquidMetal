shader_type spatial;
// The blob: polished chrome whose surface never quite sits still. `agitation` (set by the
// player) makes it ripple harder when turning, dodging or landing. The chrome look comes
// from a painted horizon reflected in it (the same dusk as the sky), so it reads as metal
// on every renderer, web included, not only where the sky's reflections are good.

uniform float agitation : hint_range(0.0, 1.0) = 0.0;
uniform float ripple = 1.0; // how much the surface moves (less on the faceted figure)
uniform vec3 sky_top : source_color = vec3(0.1, 0.12, 0.3);
uniform vec3 horizon : source_color = vec3(1.0, 0.62, 0.55);
uniform vec3 ground : source_color = vec3(0.05, 0.06, 0.1);
uniform vec3 grid_glow : source_color = vec3(0.2, 0.45, 1.0);

void vertex() {
	float t = TIME * (3.0 + agitation * 6.0);
	vec3 p = VERTEX * 5.0;
	// A wobble field over space rather than along the normals, so faceted shapes (whose
	// corners have a normal per face) move as one and don't crack open
	vec3 wobble = vec3(
		sin(p.y * 1.2 + t * 1.3) * sin(p.z + t * 0.7),
		sin(p.x + t) * sin(p.z * 1.3 - t * 0.9),
		sin(p.x * 2.1 - t * 1.7) * sin(p.y + t * 1.1));
	VERTEX += wobble * ripple * (0.018 + agitation * 0.06);
}

void fragment() {
	vec3 r = (INV_VIEW_MATRIX * vec4(reflect(-VIEW, NORMAL), 0.0)).xyz;
	float up = r.y;
	vec3 env = mix(horizon, sky_top, smoothstep(0.0, 0.6, up));
	env = mix(env, mix(ground, grid_glow * 0.5, smoothstep(-0.25, 0.0, up)), step(up, 0.0));
	env += vec3(1.0) * smoothstep(0.012, 0.0, abs(up - 0.02)) * 0.8; // the bright horizon line
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	ALBEDO = vec3(0.25);
	METALLIC = 1.0;
	ROUGHNESS = 0.12;
	EMISSION = env * (0.65 + fresnel * 0.6);
}
