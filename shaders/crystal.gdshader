shader_type spatial;
// A Crystalien's crystal: flat facets lit from within, brighter along their edges where you see
// them side on, with a slow pulse. It takes the same settings the liquid metal does (the runner
// sets them on whatever it's made of); only the colour (horizon) and the agitation mean anything
// to a crystal.

uniform vec3 horizon : source_color = vec3(0.7, 0.35, 1.0);
uniform vec3 sky_top : source_color = vec3(0.1, 0.05, 0.2);
uniform vec3 ground : source_color = vec3(0.03, 0.02, 0.06);
uniform vec3 grid_glow : source_color = vec3(0.6, 0.3, 1.0);
uniform float agitation : hint_range(0.0, 1.0) = 0.0;
uniform float real_reflection = 0.0;
uniform float ripple = 1.0;
uniform float collapse = 0.0;
uniform vec3 collapse_center = vec3(0.0);
uniform float ball_radius = 0.2;
uniform float splash = 0.0;
uniform float splash_strength = 0.035;
uniform bool splash_up = false;

void fragment() {
	vec3 n = normalize(NORMAL);
	float rim = pow(1.0 - clamp(dot(n, VIEW), 0.0, 1.0), 2.5);
	// Each facet its own shade (by which way it faces), so the cut of the stone reads
	float facet = 0.5 + 0.5 * dot(n, normalize(vec3(0.35, 0.8, 0.45)));
	float pulse = 0.85 + 0.15 * sin(TIME * 2.3 + NODE_POSITION_WORLD.x + NODE_POSITION_WORLD.z);
	ALBEDO = mix(sky_top, horizon, facet) * 0.5;
	EMISSION = horizon * (0.25 + 0.55 * facet * facet + rim * 1.5 + agitation * 0.5 + splash * 0.6) * pulse + vec3(1.0) * rim * rim * 0.45;
	ROUGHNESS = 0.12;
	METALLIC = 0.3;
	SPECULAR = 0.9;
}
