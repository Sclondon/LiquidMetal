shader_type spatial;
// The colosseum's crowd: Crystaliens in the stands, drawn as one multimesh. Each has its own
// colour (COLOR) and its own timing (INSTANCE_CUSTOM: x where it is in its bob, y how quick it
// is, z where round the arena it sits, 0..1). They bob and sway all the time, and they watch:
//   cheer: 0 quiet .. 1 all on their feet, jumping
//   wave_from / wave_reach: a wave going round both ways from one place (where something just
//     happened): those it's passing leap and flare
//   hush: 0..1 they shrink down in their seats (somebody went down the pit)
//   flash / flash_amount: they glow a colour (the colour of whoever just burst somebody)

uniform float cheer : hint_range(0.0, 1.0) = 0.0;
uniform float wave_from = 0.0;
uniform float wave_reach = 2.0; // how far round it's got (0 .. 0.5; past that: no wave)
uniform float hush : hint_range(0.0, 1.0) = 0.0;
uniform vec3 flash : source_color = vec3(1.0);
uniform float flash_amount = 0.0;

varying vec3 tint;
varying float lifted;

void vertex() {
	float phase = INSTANCE_CUSTOM.x * 6.2832;
	float rate = 2.2 + INSTANCE_CUSTOM.y * 2.5;
	float hop = pow(max(0.0, sin(TIME * rate * (1.0 + cheer) + phase)), 3.0);
	float sway = sin(TIME * rate * 0.5 + phase);
	// The wave: how near its front this one sits
	float away = abs(fract(INSTANCE_CUSTOM.z - wave_from + 0.5) - 0.5);
	float in_wave = (1.0 - smoothstep(0.0, 0.035, abs(away - wave_reach))) * step(wave_reach, 0.5);
	lifted = in_wave;
	// Never still: bobbing, and every few seconds each one, in its own time, gets up for a
	// moment by itself (waving at somebody, a better look)
	float turn_of = TIME * (0.16 + INSTANCE_CUSTOM.y * 0.12) + INSTANCE_CUSTOM.x * 7.0;
	float own = step(0.72, fract(sin(floor(turn_of) * 91.7 + INSTANCE_CUSTOM.x * 311.0) * 43758.5)) * sin(fract(turn_of) * 3.1416);
	float up = hop * (0.2 + cheer * 1.1) + in_wave * 1.6 + own * 0.55;
	// Arms and head reach further than the feet: stretched as it leaps, squashed as it hushes
	VERTEX.y *= 1.0 + in_wave * 0.35 + cheer * 0.12 * hop - hush * 0.45;
	VERTEX.y += up;
	VERTEX.x += sway * (0.13 + cheer * 0.1 + own * 0.1) * VERTEX.y;
	VERTEX.z += sin(TIME * rate * 0.37 + phase * 1.7) * 0.06 * VERTEX.y; // (leaning in and back)
	tint = COLOR.rgb;
}

void fragment() {
	vec3 n = normalize(NORMAL);
	float rim = pow(1.0 - clamp(dot(n, VIEW), 0.0, 1.0), 2.0);
	float facet = 0.5 + 0.5 * dot(n, normalize(vec3(0.35, 0.8, 0.45)));
	vec3 col = mix(tint, flash, flash_amount * 0.75);
	ALBEDO = col * 0.3;
	EMISSION = col * (0.2 + 0.5 * facet + rim * 1.1 + cheer * 0.6 + lifted * 1.5 + flash_amount * 0.7) * (1.0 - hush * 0.5);
	ROUGHNESS = 0.2;
}
