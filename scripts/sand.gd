class_name Sand
## Sand, and the one shader all of it is drawn with: the ground (`SandGround`),
## the piles under a `SandFall`, the lumps of a `SandBlob`, and any mesh a
## level gives `Sand.surface()` to.
##
## - Grain: every grain is a little lighter or darker than the next. There is
##   no texture; a grain is a cell of space, and its tone a number made from
##   where the cell is. Further off, where a grain would be smaller than a
##   pixel, bigger cells take over for a while and then the grain fades out
##   altogether, as real grain does: far sand is smooth.
## - Glitter: each grain is also a tiny mirror tipped its own way, and shows
##   only when it happens to throw the light straight at the eye.
## - Ripples: the small waves the wind leaves, lying across the wind, lit as
##   ridges, and bending to the lie of the land. They fade out before they
##   would be too fine to draw.
## - Kinds: fine pale drift sand; coarse, darker, pebbly sand; smooth slip
##   faces in the lee of a crest; and, where a `SandGround` has been painted,
##   damp dark sand and hard-packed paths. Which is where comes from broad
##   patches, from the slope and which way it faces the wind, and from paint.
## - Other ground, where it has been painted (`Kind`): white, red and black
##   sand, which are sand in every way but their colour and their glitter;
##   hard dirt, dull and mottled and cracked as dried mud is; and sandstone,
##   bare rock in bands of colour with a joint here and there. Each fades into
##   the next, and sand lies over the edge of the hard kinds in ragged drifts.
## - Snow: the same stuff seen cold. `snow_surface()`, a `SandGround` with
##   `snow` on, or `Kind.SNOW` painted: pale and blue in its hollows, with no
##   ripples and no kinds of grain, and (on a `SandGround`) prints that keep
##   the whole shape of the boot.
## - Light: smooth, or with `Sand.banded` the hard cut between light and
##   shadow that a cel-shaded world has.
##
## It is worked out from where a point is in the world, not from texture
## coordinates, so any mesh can wear it, and two that touch match.
##
## What looked stretched before this was the far grain: a pixel of distant
## ground covers a long thin strip of it, and grains (and glints) sized to the
## length of that strip came out as wide flat dashes on the screen. Grains are
## now sized by the strip's area, and fade as it gets longer and thinner.

const COLOUR := Color(0.83, 0.68, 0.45)
## Wet sand is darker, and shows fewer glints.
const WET := Color(0.66, 0.52, 0.33)

## The other colours sand comes in, hard ground, and snow (see `Kind`).
const WHITE := Color(0.87, 0.83, 0.73)
const RED := Color(0.72, 0.34, 0.19)
const BLACK := Color(0.15, 0.14, 0.145)
const DIRT := Color(0.5, 0.38, 0.26)
const SANDSTONE := Color(0.74, 0.55, 0.38)
const SNOW := Color(0.8, 0.85, 0.93)

## What may be painted on a `SandGround` (see `SandGround.paint`).
## - COARSE, DAMP, PACKED, PALE: sand as it was: pebbly; wet and dark; trodden
##   hard (shallow prints, and he hardly sinks); fine and light.
## - DIRT: hard dirt. It takes no prints, nobody sinks into it, and it does
##   not run on a slope. SANDSTONE: rock, the same and more so.
## - WHITE, RED, BLACK: sand of another colour, and sand in every other way.
## - SNOW: prints in it are crisp, and it does not run.
## (New ones go on the end: levels keep these as numbers.)
enum Kind { COARSE, DAMP, PACKED, PALE, DIRT, SANDSTONE, WHITE, RED, BLACK, SNOW }

## The looks wind ripples can have (the shader's `ripples`; `SandGround.ripples`).
## - SOFT: soft waves wherever sand lies open and flattish, as they always were.
## - MIXED: as a desert is. Soft waves on most open sand and on the backs of
##   dunes; fine forking lines in patches where the ground is level and swept
##   hard, and on trodden sand; bare smooth sand in other patches, round chalk
##   rock, in the lee and on slip faces.
## - FINE: fine forking lines wherever there are ripples.
## - NONE: no ripples.
## (New ones go on the end: levels keep these as numbers.)
enum Ripples { SOFT, MIXED, FINE, NONE }

const SHADER := """
shader_type spatial;
render_mode world_vertex_coords;
//DEFINES

uniform vec3 albedo : source_color = vec3(0.83, 0.68, 0.45);
uniform vec3 glint : source_color = vec3(1.0, 0.95, 0.82);
// 1: light cut into two flat tones, as the rest of the world is when banded.
uniform float banded = 0.0;
uniform float wrap = 0.15;
// How big a grain is, in metres, and how far its tone differs from the next.
uniform float grain_size = 0.006;
uniform float grain = 0.13;
// Patches of lighter and darker sand a metre or two across, and wind ripples:
// how strong their tone and their relief, and how far apart they are, metres.
uniform float patch = 0.05;
uniform float ripple = 0.035;
uniform float ripple_relief = 0.5;
uniform float ripple_gap = 0.3;
// Which look the ripples have (`Sand.Ripples`). 0: soft waves everywhere, as
// they always were; 1: mixed, as a desert is (soft waves on most open sand,
// fine forking lines in patches on flat hard ground, none in others and in the
// lee); 2: fine lines everywhere; 3: none.
uniform float ripples = 0.0;
// How bright a glint is, how nearly a grain must face the light to show one
// (nearer 1: fewer), and how far the grains are tipped from the surface.
uniform float sparkle = 2.2;
uniform float sparkle_aim = 0.97;
uniform float scatter = 1.3;
// Leans every normal towards straight up, so that lumps heaped together are
// lit as one soft mass (0: not at all).
uniform float soft = 0.0;
// How much the kinds of sand differ from place to place (0: all one kind),
// and what each does to the colour.
uniform float variety = 1.0;
uniform vec3 coarse_tint = vec3(0.8, 0.755, 0.71);
uniform vec3 pale_tint = vec3(1.09, 1.09, 1.08);
uniform vec3 damp_tint = vec3(0.6, 0.57, 0.53);
uniform vec3 packed_tint = vec3(0.87, 0.845, 0.8);
// The other things the ground can be: sand of three more colours, hard dirt,
// sandstone and snow. `snow` is how much of everything is snow (a `SandGround`
// adds what has been painted).
uniform vec3 white_sand : source_color = vec3(0.87, 0.83, 0.73);
uniform vec3 red_sand : source_color = vec3(0.72, 0.34, 0.19);
uniform vec3 black_sand : source_color = vec3(0.15, 0.14, 0.145);
uniform vec3 dirt_colour : source_color = vec3(0.5, 0.38, 0.26);
uniform vec3 stone_colour : source_color = vec3(0.74, 0.55, 0.38);
uniform vec3 snow_colour : source_color = vec3(0.8, 0.85, 0.93);
uniform float snow = 0.0;
// The wind: which way it blows over the ground (x, z), how hard (0..1), and
// how far it has carried the sand it is moving, metres.
uniform vec4 wind = vec4(1.0, 0.0, 0.0, 0.0);
// Sand in the air between here and the eye: its colour, and how thick.
uniform vec4 haze = vec4(0.86, 0.78, 0.62, 0.0);
// 0: plain (no ripples in relief, no kinds of grain); 1; 2: everything.
uniform float detail = 2.0;
// For the web, where one sun that casts shadows comes out too bright (see
// `Sand.sky`): the light of the sky, which is then added here and not taken
// from the scene, and how much to turn the sun back up.
uniform vec3 sky = vec3(0.0);
uniform float sun_gain = 1.0;

#ifdef GROUND
// The ground's own shape: how high each corner of its grid stands; which way
// it faces, how sharply it bends and how deep in a hollow it lies; what has
// been painted on it; and what has been pressed into it round the player.
// 1: the fine part of the mesh is drawn as a curved surface through the grid's
// corners, not as its flat triangles (`SandGround.curved`).
uniform float curve = 0.0;
uniform sampler2D height_map : filter_nearest, repeat_disable;
uniform sampler2D form_map : filter_linear, repeat_disable;
uniform sampler2D kind_map : filter_linear, repeat_disable, hint_default_black;
// (dirt, sandstone, white sand, red sand; and black sand, snow)
uniform sampler2D kind_map2 : filter_linear, repeat_disable, hint_default_black;
uniform sampler2D kind_map3 : filter_linear, repeat_disable, hint_default_black;
uniform sampler2D dent_map : filter_linear, repeat_enable;
// One corner of the grid (x, z), the side of a square, and how high zero is.
uniform vec4 field = vec4(-60.0, -60.0, 1.0, 0.0);
uniform vec2 field_cells = vec2(120.0, 120.0);
// Where the fine part of the mesh is gathered.
uniform vec3 focus = vec3(0.0);
// The dents: the side of a square of them, how many squares, how many metres
// the whole range of a square is, and which value is "not pressed"; and where
// the middle of the patch that has them is.
uniform vec4 dent = vec4(0.015, 1024.0, 0.1275, 0.6667);
uniform vec2 dent_at = vec2(0.0);
// The desert beyond the edge: how high it lies, and how far it rolls up and down.
uniform vec2 apron = vec2(0.0, 6.0);
// 1: the ground goes on for ever (`SandGround.far_heights`). Past its edges
// lies one square of open sand over and over, the size of the ground's own, and
// each of the pictures above has it under the ground's own: twice as many rows.
uniform float endless = 0.0;
// Where it stops being drawn (`SandGround.clip`, `SandGround.ring`). x: 1 and
// nothing is drawn past the edges of the ground; y, z: nothing nearer the
// middle of the ground than y metres, or further from it than z (0: no such edge).
uniform vec3 trim = vec3(0.0);

// For a place past the edges of ground that goes on for ever: where in that
// square it is (in squares of the grid), and how many rows down its pictures
// start. For any other place, nothing is changed and the answer is none.
float beyond(inout vec2 square) {
	if (endless > 0.5 && (square.x < 0.0 || square.y < 0.0 || square.x > field_cells.x || square.y > field_cells.y)) {
		square = mod(square, field_cells);
		return field_cells.y + 1.0;
	}
	return 0.0;
}

// Where in the pictures of the ground a place is.
vec2 pictured(vec2 xz) {
	vec2 square = (xz - field.xy) / field.z;
	float rows = beyond(square);
	return (square + vec2(0.5, 0.5 + rows)) / (field_cells + 1.0) * vec2(1.0, endless > 0.5 ? 0.5 : 1.0);
}

// (the corner next to one at the edge: of ground that goes on for ever, the one across the edge)
int lapped(int corner, int last) {
	if (endless < 0.5) {
		return clamp(corner, 0, last);
	}
	return corner < 0 ? corner + last : (corner > last ? corner - last : corner);
}

float ground(vec2 xz) {
	vec2 square = (xz - field.xy) / field.z;
	int rows = int(beyond(square));
	vec2 whole = clamp(floor(square), vec2(0.0), field_cells - 1.0);
	vec2 part = clamp(square - whole, 0.0, 1.0);
	ivec2 corner = ivec2(whole) + ivec2(0, rows);
	float a = texelFetch(height_map, corner, 0).r;
	float d = texelFetch(height_map, corner + ivec2(1, 1), 0).r;
	// (each square is two triangles, split the way the collider splits it)
	if (curve > 0.5) {
		// (curved ground, where the mesh is too coarse to be curved: evenly
		// between the four corners, which notches no crest whichever way it runs)
		float e = texelFetch(height_map, corner + ivec2(1, 0), 0).r;
		float f = texelFetch(height_map, corner + ivec2(0, 1), 0).r;
		return mix(mix(a, e, part.x), mix(f, d, part.x), part.y) + field.w;
	}
	if (part.x > part.y) {
		float b = texelFetch(height_map, corner + ivec2(1, 0), 0).r;
		return a + part.x * (b - a) + part.y * (d - b) + field.w;
	}
	float c = texelFetch(height_map, corner + ivec2(0, 1), 0).r;
	return a + part.y * (c - a) + part.x * (d - c) + field.w;
}

// The same ground as a curved surface through the same corners (a Catmull-Rom
// patch over the sixteen round a place): what the fine part of the mesh is
// drawn as when `curve` is on. Flat triangles two and a half metres across
// show as a line of straight pieces wherever a rounded crest stands against
// the sky; this bends through them. It is above the triangles on a crest and
// under them in a hollow by a few centimetres, no more, as long as the ground
// has no creases in it (at a crease it would rise in a lip).
vec4 spline(float t) {
	float t2 = t * t;
	float t3 = t2 * t;
	return vec4(-0.5 * t3 + t2 - 0.5 * t, 1.5 * t3 - 2.5 * t2 + 1.0, -1.5 * t3 + 2.0 * t2 + 0.5 * t, 0.5 * t3 - 0.5 * t2);
}

float curved(vec2 xz) {
	vec2 square = (xz - field.xy) / field.z;
	int rows = int(beyond(square));
	vec2 whole = clamp(floor(square), vec2(0.0), field_cells - 1.0);
	vec2 part = clamp(square - whole, 0.0, 1.0);
	ivec2 corner = ivec2(whole);
	ivec2 last = ivec2(field_cells);
	vec4 along = spline(part.x);
	vec4 down = spline(part.y);
	ivec4 columns = ivec4(lapped(corner.x - 1, last.x), corner.x, corner.x + 1, lapped(corner.x + 2, last.x));
	float sum = 0.0;
	for (int j = 0; j < 4; j++) {
		int row = lapped(corner.y + j - 1, last.y) + rows;
		sum += down[j] * dot(along, vec4(texelFetch(height_map, ivec2(columns.x, row), 0).r, texelFetch(height_map, ivec2(columns.y, row), 0).r,
				texelFetch(height_map, ivec2(columns.z, row), 0).r, texelFetch(height_map, ivec2(columns.w, row), 0).r));
	}
	return sum + field.w;
}

// How much of the dents shows at a place: all of it near the middle of their
// patch, none at its edge.
float dented(vec2 xz) {
	vec2 off = abs(xz - dent_at) / (dent.x * dent.y * 0.5);
	return 1.0 - smoothstep(0.78, 0.92, max(off.x, off.y));
}
#endif

const mat3 TIPPED = mat3(vec3(0.36, -0.8, 0.48), vec3(0.48, 0.6, 0.64), vec3(-0.8, 0.0, 0.6));

varying vec3 at;
varying vec3 faces;
varying vec3 facet;
varying float spot;
// Which way the ground faces without its ripples.
varying vec3 plain;

// (no sines: they give different numbers on different phones)
vec3 hash3(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.xxy + p.yxx) * p.zyx);
}

float hash2(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

float patches(vec2 p) {
	vec2 whole = floor(p);
	vec2 part = fract(p);
	part = part * part * (3.0 - 2.0 * part);
	return mix(mix(hash2(whole), hash2(whole + vec2(1.0, 0.0)), part.x),
			mix(hash2(whole + vec2(0.0, 1.0)), hash2(whole + vec2(1.0, 1.0)), part.x), part.y);
}

// Ground that has dried and split, or rock and its joints: how far a place is
// from the nearest crack, in a net of them about one apart (0: on a crack).
float cracks(vec2 p) {
	vec2 whole = floor(p);
	vec2 part = fract(p);
	float first = 8.0;
	float second = 8.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 square = vec2(float(i), float(j));
			vec2 point = square + vec2(hash2(whole + square), hash2(whole + square + 71.3)) - part;
			float far = dot(point, point);
			if (far < first) {
				second = first;
				first = far;
			} else if (far < second) {
				second = far;
			}
		}
	}
	return sqrt(second) - sqrt(first);
}

// One wind ripple, at a share of the way from one trough to the next: how
// high it stands there (-1..1), and how it slopes along the wind. Its back
// is long and its lee side shorter, so the lee is the darker.
// (No sines: this is the same on every phone.)
vec2 ripple_of(float share) {
	float back = 0.68;
	float part = share < back ? share / back : (1.0 - share) / (1.0 - back);
	float rate = share < back ? 1.0 / back : -1.0 / (1.0 - back);
	return vec2(part * part * (3.0 - 2.0 * part) * 2.0 - 1.0, 6.0 * part * (1.0 - part) * rate);
}

void vertex() {
#ifdef GROUND
	// The mesh is rings of squares, each ring twice as coarse as the one
	// inside it, and all of it follows `focus`: each ring a whole square of
	// its own at a time, so that no corner ever slides over the ground. (The
	// innermost corners of a ring sit on the ring inside it instead.)
	float square = UV.x;
	float step_by = UV.y > 0.5 ? square * 0.5 : square;
	vec2 xz = VERTEX.xz + floor(focus.xz / step_by + 0.5) * step_by;
	// Past the edge of the ground it runs on as open desert: from the height
	// of the edge to a rolling plain.
	vec2 within = clamp(xz, field.xy, field.xy + field_cells * field.z);
	float past = length(xz - within);
	if (endless > 0.5) {
		// (or, if it goes on for ever, as the same dunes)
		within = xz;
		past = 0.0;
	}
	// (curved where the mesh is finer than the grid of heights; further off its
	// own squares are as coarse as the grid, or coarser, and it is drawn flat)
	float y = curve > 0.5 && step_by < field.z * 0.99 ? curved(within) : ground(within);
	if (past > 0.0) {
		y = mix(y, field.w + apron.x + (patches(xz / 70.0) - 0.5) * apron.y, smoothstep(0.0, 60.0, past));
	}
	if (step_by < 0.2) {
		// (only where the mesh is fine enough to take the shape of a dent. By the
		// side of the squares a corner belongs to, which for the innermost corners
		// of a ring is the ring inside's: Outside's copy asks `square` here, and
		// where there is a dent on the line between two rings the ground comes apart
		// along it. With dents as fine as Outside's there seldom is one so far out.)
		y += (textureLod(dent_map, xz / (dent.x * dent.y), 0.0).r - dent.w) * dent.z * dented(xz) * clamp((0.2 - step_by) * 10.0, 0.0, 1.0);
	}
	VERTEX = vec3(xz.x, y, xz.y);
	vec2 lean = textureLod(form_map, pictured(xz), 0.0).xy;
	NORMAL = normalize(vec3(lean.x, sqrt(max(1.0 - dot(lean, lean), 0.01)), lean.y));
#endif
	at = VERTEX;
	NORMAL = normalize(mix(NORMAL, vec3(0.0, 1.0, 0.0), soft));
	faces = NORMAL;
}

void fragment() {
	// How much sand one pixel covers here: a strip `reach` long, of the same
	// area as a square `size` on a side. Seen square on they are the same;
	// far off across level ground the strip is many times longer than wide.
	vec3 across = dFdx(at);
	vec3 down = dFdy(at);
	float reach = max(max(length(across), length(down)), 0.00001);
	float size = sqrt(max(length(cross(across, down)), 1.0e-10));
	float thin = reach / size;

	vec3 up = normalize(faces);
	float crest = 0.0;
	float hollow = 0.0;
	vec4 painted = vec4(0.0);
	vec4 laid = vec4(0.0);
	vec4 more = vec4(0.0);
	float pressed = 0.0;
	// (how steeply sand that stands above the rest falls away at its edge)
	float brink = 0.0;
#ifdef GROUND
	vec2 where = pictured(at.xz);
	vec4 form = textureLod(form_map, where, 0.0);
	up = normalize(vec3(form.x, sqrt(max(1.0 - dot(form.xy, form.xy), 0.01)), form.y));
	float past = endless > 0.5 ? 0.0 : length(at.xz - clamp(at.xz, field.xy, field.xy + field_cells * field.z));
	if (trim.x > 0.5 && past > 0.0) {
		discard;
	}
	if (trim.z > 0.0) {
		float out_from = length(at.xz - field.xy - field_cells * field.z * 0.5);
		if (out_from > trim.z || out_from < trim.y) {
			discard;
		}
	}
	up = normalize(mix(up, vec3(0.0, 1.0, 0.0), smoothstep(0.0, 60.0, past)));
	form.zw *= 1.0 - smoothstep(0.0, 30.0, past);
	crest = max(form.z, 0.0);
	hollow = max(form.w, 0.0) + max(-form.z, 0.0) * 0.5;
	painted = textureLod(kind_map, where, 0.0);
	laid = textureLod(kind_map2, where, 0.0);
	more = textureLod(kind_map3, where, 0.0);
	float shows = dented(at.xz);
	if (shows > 0.0) {
		// What has been pressed in: darker in the hollow, and lit as the
		// slope of its sides, which is what raises a rim round it.
		vec2 spot_at = at.xz / (dent.x * dent.y);
		float one = 1.0 / dent.y;
		float here = textureLod(dent_map, spot_at, 0.0).r;
		float east = textureLod(dent_map, spot_at + vec2(one, 0.0), 0.0).r;
		float south = textureLod(dent_map, spot_at + vec2(0.0, one), 0.0).r;
		pressed = (here - dent.w) * dent.z * shows;
		// (too far off to tell one dent from the next, they are left unlit)
		float sharp = shows * clamp(2.0 - reach / (dent.x * 2.0), 0.0, 1.0);
		vec2 slope = vec2(east - here, south - here) * dent.z / dent.x * sharp;
		brink = length(slope) * step(0.0, pressed);
		up = normalize(up + vec3(-slope.x, 0.0, -slope.y) * up.y);
	}
#endif
	vec2 blows = wind.xy;
	float steep = 1.0 - up.y;
	float lee = dot(up.xz, blows) / max(length(up.xz), 0.001);
	// Hard ground, where it has been laid: dirt and sandstone. Sand lies over
	// their edges in drifts, so the line between them is a ragged one.
	float dirt = 0.0;
	float stone = 0.0;
	if (laid.r + laid.g > 0.0) {
		float ragged = (patches(at.xz * 1.7 + 5.0) - 0.5) * 0.5 + (patches(at.xz * 6.0 - 2.0) - 0.5) * 0.14;
		dirt = smoothstep(0.36, 0.64, laid.r + ragged);
		stone = smoothstep(0.36, 0.64, laid.g - ragged);
		dirt *= 1.0 - stone;
	}
	float hard = max(dirt, stone);
	float snowy = clamp(snow + more.g, 0.0, 1.0) * (1.0 - hard);
	float black = more.r;
	// A slip face: steep, and turned away from the wind.
	float slip = smoothstep(0.075, 0.125, steep) * smoothstep(-0.1, 0.5, lee) * step(soft, 0.0) * (1.0 - hard) * (1.0 - snowy);

	// Which kind of sand lies here.
	float region = patches(at.xz / 41.0 + 3.7);
	float lesser = patches(at.xz / 15.0 - 9.1);
	float coarse = variety * smoothstep(0.56, 0.74, region * 0.7 + lesser * 0.3 + hollow * 0.45 - crest * 0.5);
	// (where white sand has been laid it is fine drift, and the coarse grains are under it)
	coarse = clamp(coarse * (1.0 - snowy) * (1.0 - smoothstep(0.2, 0.3, laid.b)) + painted.r, 0.0, 1.0) * (1.0 - slip) * (1.0 - hard);
	float pale = variety * smoothstep(0.5, 0.72, (1.0 - region) * 0.6 + lesser * 0.4 + crest * 0.5 - hollow * 0.3);
	pale = clamp(pale * (1.0 - snowy) + painted.a, 0.0, 1.0) * (1.0 - coarse) * (1.0 - hard);
	float damp = painted.g;
	float packed = painted.b * (1.0 - damp * 0.5);

	// Grain. Never drawn much smaller than a pixel: each doubling of the
	// distance doubles the grains, and thins them out, until they are gone.
	float level = log2(max(size * 1.5 / grain_size, 1.0));
	float whole = floor(level);
	// (the grid of grains is tipped over, so that no wall or floor lies along it)
	vec3 cell = TIPPED * at / (grain_size * exp2(whole));
	vec3 near = hash3(floor(cell) + whole * 17.0);
	vec3 far = hash3(floor(cell * 0.5) + (whole + 1.0) * 17.0);
	// (one size fades into the next, so the grain does not jump as he walks)
	float keep = (1.0 - smoothstep(3.0, 7.0, thin)) / (1.0 + 0.5 * level);
	float fine = (mix(near.x, far.x, level - whole) - 0.5) * keep;
	if (coarse > 0.02 && detail > 0.5) {
		// Coarse sand: bigger grains among the small, and a dark pebble here and there.
		float big = grain_size * 3.5;
		float big_level = log2(max(size * 1.5 / big, 1.0));
		float big_whole = floor(big_level);
		vec3 big_cell = TIPPED * at / (big * exp2(big_whole));
		float a = hash3(floor(big_cell) + big_whole * 29.0 + 5.0).x;
		float b = hash3(floor(big_cell * 0.5) + (big_whole + 1.0) * 29.0 + 5.0).x;
		float pebble = mix(a, b, big_level - big_whole);
		float big_keep = (1.0 - smoothstep(3.0, 7.0, thin)) / (1.0 + 0.5 * big_level);
		fine = mix(fine, fine * 0.6 + ((pebble - 0.5) * 1.5 - smoothstep(0.86, 0.9, pebble) * 0.55) * big_keep, coarse);
	}
	fine *= (1.0 - 0.45 * slip) * (1.0 - 0.4 * packed) * (1.0 - 0.45 * hard) * (1.0 - 0.5 * snowy) * (1.0 + 1.6 * black);
	// Sand that has just moved, and stands heaped above the rest: it is the
	// fine dry sand from underneath, smoother and paler than what it lies on.
	float heaped = smoothstep(0.006, 0.04, pressed);
	fine *= 1.0 - 0.6 * heaped;
	// Patches a metre or two across (gone before they are too small to draw).
	float broad = (patches(at.xz * 0.7) - 0.5) * clamp(1.5 - reach * 1.4, 0.0, 1.0);

	// Ripples: waves lying across the wind, steeper on the side away from it,
	// their lines bent by the rise of the ground and a little by chance.
	float rippled = (1.0 - slip) * (1.0 - packed) * (1.0 - 0.75 * coarse) * (1.0 - 0.6 * damp) * (1.0 - smoothstep(0.1, 0.2, steep)) * step(soft, 0.0);
	rippled *= (1.0 - hard) * (1.0 - snowy);
	rippled *= 0.55 + 0.45 * smoothstep(0.25, 0.6, lesser + pale * 0.4);
	vec3 unrippled = up;
	// Which look they have here: soft waves, fine forking lines, or none.
	float waves = 1.0;
	float lines = 0.0;
	if (ripples > 2.5) {
		waves = 0.0;
	} else if (ripples > 1.5) {
		waves = 0.0;
		lines = 1.0;
	} else if (ripples > 0.5) {
		// It differs from place to place, in patches some tens of metres
		// across. Fine lines only where the ground is level and swept hard
		// (and there trodden sand has them too); bare smooth sand in other
		// patches, and round chalk; soft waves on the rest.
		float lay = patches(at.xz / 29.0 + 17.0) + (lesser - 0.5) * 0.2;
		float level_here = 1.0 - smoothstep(0.004, 0.02, steep);
		lines = level_here * max(smoothstep(0.6, 0.7, lay), smoothstep(0.12, 0.3, packed) * smoothstep(0.42, 0.56, lay)) * (1.0 - 0.75 * coarse) * (1.0 - 0.6 * damp) * (1.0 - slip) * (1.0 - hard) * (1.0 - snowy) * step(soft, 0.0);
		waves = (1.0 - lines) * smoothstep(0.24, 0.36, lay) * (1.0 - 0.85 * laid.b);
		// (and fewer where the ground falls away down wind: the lee is sheltered)
		waves *= 1.0 - 0.8 * smoothstep(0.1, 0.6, lee) * smoothstep(0.01, 0.05, steep);
	}
	// (each fades out before it would be too fine to draw)
	waves *= rippled * clamp(ripple_gap * 0.22 / reach - 0.5, 0.0, 1.0);
	lines *= mix(rippled, 1.0, step(0.5, ripples) * step(ripples, 1.5)) * clamp(ripple_gap * 0.17 / reach - 0.5, 0.0, 1.0);
	float wave = 0.0;
	float tilt = 0.0;
	if (waves > 0.0) {
		// Soft waves, rising and falling evenly, a little steeper on the lee side.
		float along = dot(at.xz, blows) + at.y * 0.55;
		float bent = patches(at.xz * 0.23 + 4.0) * 2.4 + patches(at.xz * 0.9) * 0.5;
		float turn = (along / ripple_gap + bent) * TAU;
		wave = sin(turn + 0.5 * sin(turn)) * waves;
		tilt = cos(turn + 0.5 * sin(turn)) * (1.0 + 0.5 * cos(turn)) * waves * ripple_relief;
	}
	if (lines > 0.0) {
		// Fine lines. (Measured along the wind and across it; and over the ground,
		// not up it.)
		vec2 lie = vec2(dot(at.xz, blows), dot(at.xz, vec2(-blows.y, blows.x)));
		float bent = patches(lie * vec2(0.8, 0.21) + 4.0) * 1.7 + patches(lie * vec2(0.3, 0.07) + 9.0) * 2.2;
		// There are two sets of them, one a little closer together than the
		// other, each lying in patches longer across the wind than along it.
		// Where one gives way to the other a ripple runs into the next and
		// ends, or one becomes two: they fork and join.
		float other = smoothstep(0.4, 0.6, patches(lie * vec2(0.8, 0.26) + 31.0) + (patches(lie * vec2(1.9, 0.6)) - 0.5) * 0.3);
		float turn = lie.x / (ripple_gap * 0.8) + bent;
		vec2 one = ripple_of(fract(turn));
		vec2 two = ripple_of(fract(turn * 1.25 + 0.37));
		vec2 both = mix(one, two, other) * lines;
		wave += both.x * 0.7;
		tilt += both.y * 0.09 * ripple_relief;
	}
	if (waves + lines > 0.0) {
		if (detail > 0.5) {
			up = normalize(up - vec3(blows.x, 0.0, blows.y) * tilt);
		} else {
			wave += tilt * 0.6;
		}
	}

	// Sand on the move: pale wisps streaming over the surface where the wind
	// reaches it, most of all at a crest.
	float wisps = 0.0;
	if (wind.z > 0.01 && detail > 0.5) {
		vec2 lie = vec2(dot(at.xz, blows) - wind.w, dot(at.xz, vec2(-blows.y, blows.x)));
		float snake = patches(lie * vec2(0.05, 0.11)) * 3.0;
		float streak = patches(vec2(lie.x * 0.11, lie.y * 0.8 + snake));
		float gusting = patches(vec2(lie.x * 0.035 + 7.0, lie.y * 0.05));
		wisps = smoothstep(0.52, 0.9, streak) * smoothstep(0.25, 0.75, gusting) * wind.z;
		wisps *= (1.0 - slip) * (0.45 + crest * 2.5) * clamp(1.6 - reach * 1.5, 0.0, 1.0) * step(soft, 0.0) * (1.0 - hard);
	}

	// Sand of whatever colour was laid here, or snow.
	vec3 colour = albedo;
	colour = mix(colour, white_sand, laid.b);
	colour = mix(colour, red_sand, laid.a);
	colour = mix(colour, black_sand, black);
	colour = mix(colour, snow_colour, snowy);
	colour *= mix(vec3(1.0), coarse_tint, coarse);
	colour *= mix(vec3(1.0), pale_tint, pale);
	colour *= mix(vec3(1.0), vec3(1.04, 1.03, 1.0), slip);
	// (snow in a hollow is blue: it is lit there by the sky)
	colour *= mix(vec3(1.0), vec3(0.8, 0.88, 1.03), snowy * clamp(-pressed * 60.0, 0.0, 1.0));
	if (hard > 0.01) {
		// Its cracks, which are too fine to draw from far off.
		float rock = step(dirt, stone);
		float gap = 1.0;
		if (detail > 0.5) {
			gap = cracks(at.xz * mix(2.9, 0.85, rock) + 13.0);
		}
		float split = (1.0 - smoothstep(mix(0.015, 0.004, rock), mix(0.07, 0.02, rock), gap)) * clamp(1.6 - reach * 24.0, 0.0, 1.0);
		// (rock is not jointed everywhere: here and there, and faintly)
		split *= mix(1.0, 0.7 * smoothstep(0.35, 0.6, patches(at.xz * 0.45 + 21.0)), rock);
		// Dirt: mottled, a clod here lighter and there darker.
		vec3 ground_colour = dirt_colour * (1.0 + (patches(at.xz * 4.3 + 1.0) - 0.5) * 0.3 * clamp(1.5 - reach * 3.0, 0.0, 1.0) + (lesser - 0.5) * 0.16);
		// Sandstone: laid down in beds, which show as bands that follow the
		// height of the ground and wander over it where it is level.
		float bed = at.y * 5.0 + patches(at.xz * 0.21 + 3.0) * 9.0 + patches(at.xz * 0.9 + 8.0) * 1.2;
		float band = patches(vec2(bed * 2.3, 7.3)) * 0.6 + patches(vec2(bed * 7.9, 1.1)) * 0.4 * clamp(1.5 - reach * 6.0, 0.0, 1.0);
		vec3 rock_colour = stone_colour * mix(vec3(0.66, 0.58, 0.55), vec3(1.2, 1.17, 1.08), smoothstep(0.2, 0.8, band));
		ground_colour = mix(ground_colour, rock_colour, rock) * (1.0 - 0.5 * split);
		colour = mix(colour, ground_colour, hard);
	}
	colour *= mix(vec3(1.0), damp_tint, damp);
	colour *= mix(vec3(1.0), packed_tint, packed);
	float tone = 1.0 + fine * grain * 2.0 + broad * patch * 2.0 + wave * ripple;
	// (far off these are all there is to see: crests catch the light, hollows keep less of it)
	tone += crest * 0.16 - hollow * 0.09;
	// (and a heap is dark under its edge, where it overhangs the ground it is crossing)
	tone *= 1.0 + clamp(pressed * 13.0, -0.45, 0.1) + 0.16 * heaped - 0.28 * clamp(brink * 0.9 - 0.15, 0.0, 1.0);
	colour = colour * tone + glint * wisps * 0.22;
	float distance_off = length(VERTEX);
	float veil = 1.0 - exp(-haze.a * distance_off);
	ALBEDO = colour * (1.0 - veil);
	EMISSION = haze.rgb * veil;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	AO = sky.r + sky.g + sky.b > 0.0 ? 0.0 : 1.0;
	NORMAL = normalize(mat3(VIEW_MATRIX) * up);
	plain = normalize(mat3(VIEW_MATRIX) * unrippled);
	// Which way this grain's mirror faces, and a round spot in the middle of it.
	facet = normalize(NORMAL + mat3(VIEW_MATRIX) * (near * 2.0 - 1.0) * scatter);
	// (dirt and rock have none; black sand and white, and snow, more than most)
	spot = (1.0 - smoothstep(0.28, 0.5, length(fract(cell) - 0.5))) * (1.0 - 0.85 * damp) * (1.0 - veil)
			* (1.0 - 0.92 * hard) * (1.0 + 1.4 * black + 0.5 * laid.b + 0.7 * snowy)
			* (1.0 - smoothstep(4.0, 9.0, thin)) / (1.0 + 0.6 * level * level);
}

float cut(float value, float edge) {
	float pixel = max(fwidth(value), 0.0005);
	return smoothstep(edge - pixel, edge + pixel, value);
}

void light() {
	float reach = clamp(ATTENUATION, 0.0, 1.0);
	float facing = (dot(NORMAL, LIGHT) + wrap) / (1.0 + wrap);
	// (in bands the line between light and shade is drawn from the ground without
	// its ripples, so that it is one clean line and not a row of teeth, and the
	// ripples are shaded on top of it)
	float even = (dot(plain, LIGHT) + wrap) / (1.0 + wrap);
	float hard = cut(even * smoothstep(0.15, 0.6, reach), 0.04) * reach * clamp(1.0 + (facing - even) * 1.6, 0.55, 1.3);
	float smooth_lit = clamp(dot(NORMAL, LIGHT), 0.0, 1.0) * reach;
	float lit = mix(smooth_lit, hard, banded);
	// (only the sun is turned back up, and the sky is added once, with it: a
	// torch or a fire is a light too, and comes here as well)
	vec3 sun = LIGHT_COLOR / PI * (LIGHT_IS_DIRECTIONAL ? sun_gain : 1.0);
	DIFFUSE_LIGHT += lit * sun + (LIGHT_IS_DIRECTIONAL ? sky : vec3(0.0));
	// A glint, where this grain throws the light at the eye; none in shadow.
	float aim = dot(facet, normalize(LIGHT + VIEW));
	float spark = smoothstep(sparkle_aim, sparkle_aim + 0.006, aim) * spot * smoothstep(0.0, 0.25, lit);
	SPECULAR_LIGHT += spark * sparkle * glint * sun;
}
"""

## How much is spent on sand: 0 for a slow phone, 1 for a phone, 2 for a
## desktop. It is chosen when first asked for (a phone or a browser gets 1),
## and a `SandGround` turns it down by itself if frames are coming slowly. Set
## it at any time; everything made of sand follows within a second.
static var quality := -1: get = _get_quality

## Whether its light is cut into two flat tones with a hard line between them
## (as a cel-shaded world is), or smooth. Set it before making any sand, or at
## any time and call `refresh`. (In *Outside* this was the menu's setting,
## `Settings.world_banded`; here it is sand's own, so that sand needs no menu.)
static var banded := false

## For the web. Its renderer draws a light that casts shadows as a second coat
## over the first (the light of the sky), and adds the two together only after
## each has been made ready for the screen, which comes out much too bright:
## pale sand goes white. A level lit by one such sun can turn the sun down to
## make up for it, and say so here before it makes any sand: `sun_gain` is how
## much the sand should turn it back up, and `sky` the light of the sky (its colour
## through `srgb_to_linear`, times its energy), which the sand then adds to the sun's coat itself, so that
## the sum is done properly. Left alone, sand is lit like anything else.
static var sun_gain := 1.0
static var sky := Color.BLACK

## The wind, as `SandWind` last gave it: the way it blows over the ground,
## how hard (0 calm, about 0.35 a breeze, 1 a storm, gusts and all), and how
## far it has carried loose sand since it began, metres. Sand reads these;
## only a `SandWind` should write them.
static var wind_way := Vector2(1.0, 0.0)
static var wind_force := 0.0
static var wind_travel := 0.0
## Sand in the air: its colour, and how thick (see `haze` in the shader).
static var haze := Color(0.86, 0.78, 0.62, 0.0)

static var _shader: Shader
static var _ground_shader: Shader
static var _made: Array[WeakRef] = []


## A sand material. `soft` leans its light towards what falls on level ground
## (see the shader): for lumps drawn heaped together.
static func surface(colour := COLOUR, soft := 0.0) -> ShaderMaterial:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	var material := _dress(_shader, colour)
	material.set_shader_parameter(&"soft", soft)
	if soft > 0.0:
		material.set_shader_parameter(&"variety", 0.0)
	return material


## The material a `SandGround` wears: the same sand, on a mesh that takes its
## shape from the ground's own maps and shows what has been pressed into it.
static func ground_surface(colour := COLOUR) -> ShaderMaterial:
	if _ground_shader == null:
		_ground_shader = Shader.new()
		_ground_shader.code = SHADER.replace("//DEFINES", "#define GROUND")
	return _dress(_ground_shader, colour)


## Snow: the same material, pale, with no ripples and no kinds of grain. (For
## ground that takes crisp prints, see `SandGround.snow`.)
static func snow_surface(colour := SNOW, soft := 0.0) -> ShaderMaterial:
	var material := surface(colour, soft)
	material.set_shader_parameter(&"snow", 1.0)
	return material


## Tells every sand material which way the wind blows and how hard. `SandWind`
## calls this each frame.
static func blow(way: Vector2, force: float, travel: float, air: Color) -> void:
	wind_way = way
	wind_force = force
	wind_travel = travel
	haze = air
	var value := Vector4(way.x, way.y, force, travel)
	var live := false
	for made in _made:
		var material := made.get_ref() as ShaderMaterial
		if material:
			material.set_shader_parameter(&"wind", value)
			material.set_shader_parameter(&"haze", air)
			live = true
	if not live:
		_made.clear()


## Gives every sand material the quality as it is now (a `SandGround` calls this when it changes).
static func refresh() -> void:
	for made in _made:
		var material := made.get_ref() as ShaderMaterial
		if material:
			material.set_shader_parameter(&"detail", float(quality))
			material.set_shader_parameter(&"banded", 1.0 if banded else 0.0)


static func _dress(shader: Shader, colour: Color) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter(&"albedo", colour)
	material.set_shader_parameter(&"white_sand", WHITE)
	material.set_shader_parameter(&"red_sand", RED)
	material.set_shader_parameter(&"black_sand", BLACK)
	material.set_shader_parameter(&"dirt_colour", DIRT)
	material.set_shader_parameter(&"stone_colour", SANDSTONE)
	material.set_shader_parameter(&"snow_colour", SNOW)
	material.set_shader_parameter(&"banded", 1.0 if banded else 0.0)
	material.set_shader_parameter(&"sun_gain", sun_gain)
	material.set_shader_parameter(&"sky", Vector3(sky.r, sky.g, sky.b))
	material.set_shader_parameter(&"detail", float(quality))
	material.set_shader_parameter(&"wind", Vector4(wind_way.x, wind_way.y, wind_force, wind_travel))
	material.set_shader_parameter(&"haze", haze)
	_made.append(weakref(material))
	if _made.size() > 64:
		_made = _made.filter(func(made: WeakRef) -> bool: return made.get_ref() != null)
	return material


static func _get_quality() -> int:
	if quality < 0:
		quality = 1 if OS.has_feature("web") or OS.has_feature("mobile") else 2
	return quality
