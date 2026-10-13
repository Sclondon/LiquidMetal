shader_type spatial;
// The colosseum's crowd: Crystaliens in the stands, drawn as one multimesh. Each has its own
// colour (COLOR) and its own timing (INSTANCE_CUSTOM: x where it is in its bob, y how quick it
// is); they bob and sway, and jump when the arena cheers (cheer: 0 quiet .. 1 on their feet).

uniform float cheer : hint_range(0.0, 1.0) = 0.0;

varying vec3 tint;

void vertex() {
	float phase = INSTANCE_CUSTOM.x * 6.2832;
	float rate = 2.2 + INSTANCE_CUSTOM.y * 2.5;
	float hop = pow(max(0.0, sin(TIME * rate + phase)), 3.0);
	float sway = sin(TIME * rate * 0.5 + phase);
	VERTEX.y += hop * (0.12 + cheer * 0.9);
	VERTEX.x += sway * 0.07 * VERTEX.y;
	tint = COLOR.rgb;
}

void fragment() {
	vec3 n = normalize(NORMAL);
	float rim = pow(1.0 - clamp(dot(n, VIEW), 0.0, 1.0), 2.0);
	float facet = 0.5 + 0.5 * dot(n, normalize(vec3(0.35, 0.8, 0.45)));
	ALBEDO = tint * 0.3;
	EMISSION = tint * (0.2 + 0.5 * facet + rim * 1.1 + cheer * 0.5);
	ROUGHNESS = 0.2;
}
