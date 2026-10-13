shader_type spatial;
// A Crystalien tower, far off: dark stone in broad bands of bright colour of uneven width (the way
// Chris Foss painted machines), thin pale pinstripes between them, rows of small lit windows, and
// light along its edge. Banded by height in the tower's own space (0 at its foot, 1 at its top).

uniform vec3 band_a : source_color = vec3(1.0, 0.6, 0.2);
uniform vec3 band_b : source_color = vec3(0.3, 0.8, 1.0);
uniform vec3 stone : source_color = vec3(0.07, 0.07, 0.1);
uniform float seed = 0.0;
uniform float tall = 100.0; // metres, so the windows come out the same size on every tower

varying float height;
varying vec3 local;

float hash(float n) {
	return fract(sin(n * 127.1 + seed) * 43758.5453);
}

void vertex() {
	height = VERTEX.y;
	local = VERTEX;
}

void fragment() {
	// Bands: the tower cut into uneven slices, each stone, colour a, or colour b
	float slice = floor(height * 9.0 + hash(floor(height * 3.0)) * 2.0);
	float pick = hash(slice);
	vec3 col = pick < 0.45 ? stone : (pick < 0.75 ? band_a * 0.5 : band_b * 0.45);
	// Pinstripes where one slice meets the next
	float seam = abs(fract(height * 9.0 + hash(floor(height * 3.0)) * 2.0) - 0.5);
	col = mix(col, vec3(0.9, 0.88, 0.8) * 0.5, step(0.46, seam));
	// Windows: rows of them in the stone bands, some lit
	float around = atan(local.z, local.x);
	vec2 cell = vec2(floor(around * 26.0), floor(height * tall / 3.2));
	float lit = step(0.72, fract(sin(dot(cell, vec2(12.9, 78.2)) + seed) * 43758.5)) * step(0.3, fract(around * 26.0)) * step(0.35, fract(height * tall / 3.2));
	float rim = pow(1.0 - clamp(dot(normalize(NORMAL), VIEW), 0.0, 1.0), 2.5);
	ALBEDO = col;
	ROUGHNESS = 0.55;
	METALLIC = 0.2;
	EMISSION = col * 0.35 + vec3(1.0, 0.85, 0.55) * lit * float(pick < 0.45) * 0.9 + mix(band_a, vec3(1.0), 0.3) * rim * 0.35;
}
