class_name SandWind
extends MultiMeshInstance3D
## Wind over sand. Add one to a level and set `weather` (calm, a breeze or a
## storm), or `strength` to anything between, and `direction`. It comes in
## gusts. What it does:
##
## - Streamers: ribbons of blown sand snaking downwind over the ground,
##   following its rise and fall. Where the ground drops away under them (a
##   crest) they carry on out into the air and sink slowly: the plume off the
##   top of a dune.
## - Grains in the air round the camera, most of them near the ground,
##   streaked by their speed and bright where they are seen against the sun.
## - Haze: sand in the air between the eye and what it looks at, thicker in a
##   gust. On sand that is drawn by the sand shader itself (`Sand.haze`); for
##   everything else the level's own fog is thickened, if it has one, and the
##   sky is turned the colour of the sand.
## - It tells every sand material which way it blows (`Sand.blow`): ripples
##   lie across it, pale wisps stream over the surface, footprints fill in
##   faster, and whatever is kicked up is carried off downwind.
##
## Streamers and grains are one MultiMesh, placed by its shader: one draw
## call, and nothing to do each frame but tell it the time. They are kept in
## a box round the camera and come round again as they leave it. It needs to
## know the lie of the land to follow it: it finds the level's `SandGround`
## by itself; with none, it blows over level ground at `floor_height`.

enum Weather { CALM, BREEZE, STORM }

const STREAMERS := 220
const GRAINS := 360
## Sheets of haze, one behind another, for a level with no fog of its own.
const VEILS := 8
## How many pieces a ribbon is made of along its length.
const PIECES := 8
const STRENGTHS: Array[float] = [0.0, 0.35, 1.0]

const SHADER := """
shader_type spatial;
render_mode world_vertex_coords, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, unshaded;

uniform vec3 tint : source_color = vec3(0.93, 0.83, 0.64);
uniform float clock = 0.0;
// How far the wind has carried things, metres; which way it blows (x, z);
// and how hard, 0..1.
uniform float travel = 0.0;
uniform vec3 wind = vec3(1.0, 0.0, 0.0);
// How many of each are out, 0..1.
uniform vec2 amount = vec2(0.0);
uniform vec3 eye = vec3(0.0);
// The way to the sun, and how bright what it lights is.
uniform vec3 sun_way = vec3(0.0, 1.0, 0.0);
uniform vec3 light : source_color = vec3(1.0);
// Sand in the air, where the level has no fog to thicken: its colour, and how thick.
uniform vec4 veil : source_color = vec4(0.9, 0.82, 0.66, 0.0);
uniform sampler2D height_map : filter_nearest, repeat_disable;
// (as the sand shader's: a corner of the ground, the side of a square of
// it, and how high zero is; with no ground, the side is zero)
uniform vec4 field = vec4(0.0);
uniform vec2 field_cells = vec2(1.0);
uniform float endless = 0.0;

varying vec2 where;
varying float grain;
varying vec3 chance;
varying float fade;
varying float long;
varying vec3 at;

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

float ground(vec2 xz) {
	if (field.z <= 0.0) {
		return field.w;
	}
	vec2 square = (xz - field.xy) / field.z;
	int rows = 0;
	if (endless > 0.5 && (square.x < 0.0 || square.y < 0.0 || square.x > field_cells.x || square.y > field_cells.y)) {
		// (past the edges of ground that goes on for ever: see the sand's own shader)
		square = mod(square, field_cells);
		rows = int(field_cells.y) + 1;
	}
	vec2 whole = clamp(floor(square), vec2(0.0), field_cells - 1.0);
	vec2 part = clamp(square - whole, 0.0, 1.0);
	ivec2 corner = ivec2(whole) + ivec2(0, rows);
	float a = texelFetch(height_map, corner, 0).r;
	float b = texelFetch(height_map, corner + ivec2(1, 0), 0).r;
	float c = texelFetch(height_map, corner + ivec2(0, 1), 0).r;
	float d = texelFetch(height_map, corner + ivec2(1, 1), 0).r;
	return mix(mix(a, b, part.x), mix(c, d, part.x), part.y) + field.w;
}

void vertex() {
	grain = INSTANCE_CUSTOM.x;
	chance = INSTANCE_CUSTOM.yzw;
	where = UV;
	vec2 way = wind.xy;
	vec2 side = vec2(-way.y, way.x);
	float out_now = fract(chance.x * 7.31 + chance.y * 3.17 + chance.z * 5.3);
	vec3 to_eye;
	if (grain > 1.5) {
		// A sheet of haze, square to the eye, so far off: it dims whatever is
		// behind it by as much as the air between it and the sheet before it.
		float off = 7.0 * pow(1.62, chance.x * 8.0);
		float before = chance.x > 0.01 ? 7.0 * pow(1.62, chance.x * 8.0 - 1.0) : 0.0;
		VERTEX = eye - INV_VIEW_MATRIX[2].xyz * off + (INV_VIEW_MATRIX[0].xyz * (UV.x - 0.5) + INV_VIEW_MATRIX[1].xyz * (UV.y - 0.5)) * off * 5.0;
		fade = 1.0 - exp(-veil.a * (off - before));
		long = off;
		to_eye = vec3(0.0);
	} else if (grain < 0.5) {
		// A streamer. It keeps to a box round the eye, drifting downwind at a
		// pace of its own, and comes in again upwind when it leaves.
		float box = 64.0;
		vec2 from = chance.xy * box + way * travel * (0.55 + 0.5 * chance.z);
		vec2 off = mod(from - eye.xz + box * 0.5, box) - box * 0.5;
		long = mix(3.5, 9.0, chance.z);
		vec2 place = eye.xz + off - way * UV.y * long;
		float run = dot(place, way);
		// (it snakes)
		place += side * (sin(run * 0.8 + chance.x * 40.0 + clock * (0.9 + chance.y)) * 0.25
				+ sin(run * 0.27 + chance.y * 17.0 - clock * 0.5) * 0.7);
		// It lies on the ground; but where the ground has fallen away faster
		// than blown sand sinks, it is still up where the ground upwind left it.
		float under = ground(place);
		float carried = max(under, max(ground(place - way * 1.5) - 0.2, ground(place - way * 4.0) - 0.55));
		float aloft = carried - under;
		float wide = mix(0.14, 0.42, chance.y) * (1.0 + aloft * 1.3);
		// (flat on the ground; on edge in the air, to be seen from the side)
		vec3 broad = normalize(mix(vec3(side.x, 0.0, side.y), vec3(0.0, 1.0, 0.0), clamp(aloft * 1.6, 0.0, 0.8)));
		VERTEX = vec3(place.x, carried + 0.035 + 0.05 * chance.x + aloft * 0.15, place.y) + broad * (UV.x - 0.5) * wide;
		float edge = max(abs(off.x), abs(off.y)) / (box * 0.5);
		fade = (1.0 - smoothstep(0.7, 0.95, edge)) * sin(UV.y * PI) * (1.0 - smoothstep(1.2, 3.2, aloft)) * (1.0 + min(aloft, 1.0) * 1.4);
		fade *= step(out_now, amount.x) * (0.6 + 0.4 * wind.z);
		to_eye = eye - VERTEX;
	} else {
		// A few grains in the air: most of them near the ground, each a
		// streak along the way it is going.
		vec3 box = vec3(16.0, 1.0, 16.0);
		vec3 from = chance * box;
		from.xz += way * travel * (1.5 + chance.x) + side * sin(clock * (0.6 + chance.y) + chance.z * 30.0) * 0.5;
		vec2 off = mod(from.xz - eye.xz + box.xz * 0.5, box.xz) - box.xz * 0.5;
		vec2 place = eye.xz + off;
		float high = 0.04 + 3.6 * chance.y * chance.y * chance.y + 0.12 * sin(clock * (1.3 + chance.z * 2.0) + chance.x * 50.0);
		vec3 middle = vec3(place.x, ground(place) + max(high, 0.03), place.y);
		to_eye = eye - middle;
		float far = length(to_eye);
		vec3 going = normalize(vec3(way.x, 0.25 * cos(clock * (1.3 + chance.z * 2.0) + chance.x * 50.0), way.y));
		vec3 across = normalize(cross(going, to_eye));
		long = 0.02 + (0.03 + 0.11 * wind.z) * (0.5 + chance.x);
		float wide = 0.012 + 0.012 * chance.z;
		// (never thinner than a pixel or so)
		wide = max(wide, far * 0.0016);
		VERTEX = middle + going * (0.5 - UV.y) * long + across * (UV.x - 0.5) * wide;
		float edge = max(abs(off.x), abs(off.y)) / (box.x * 0.5);
		fade = (1.0 - smoothstep(0.6, 0.95, edge)) * smoothstep(0.4, 1.2, far) * step(out_now, amount.y) * (0.012 + 0.012 * chance.z) / wide;
	}
	// Seen against the sun, sand in the air is bright.
	if (grain < 1.5) {
		fade *= 1.0 + 1.6 * pow(max(dot(normalize(-to_eye), sun_way), 0.0), 3.0);
	}
	at = VERTEX;
}

void fragment() {
	float alpha;
	vec3 colour = tint * light;
	if (grain > 1.5) {
		// (thicker and thinner in drifts that go by on the wind)
		vec2 lie = vec2(dot(at.xz, wind.xy) - travel, dot(at.xz, vec2(-wind.y, wind.x)));
		alpha = fade * (0.85 + 0.3 * patches(lie * vec2(0.02, 0.035)));
		colour = veil.rgb;
	} else if (grain < 0.5) {
		float across = 1.0 - abs(where.x * 2.0 - 1.0);
		float threads = patches(vec2(where.x * 5.0 + chance.x * 30.0, where.y * long * 1.6 + clock * 2.5 + chance.y * 9.0));
		float fine = patches(vec2(where.x * 14.0 + chance.y * 11.0, where.y * long * 6.0 + clock * 6.0));
		alpha = across * across * (0.2 + 0.8 * smoothstep(0.25, 0.8, threads * 0.65 + fine * 0.35)) * fade * 0.75;
	} else {
		vec2 from_middle = where * 2.0 - 1.0;
		alpha = (1.0 - smoothstep(0.3, 1.0, abs(from_middle.x))) * (1.0 - from_middle.y * from_middle.y) * fade * 0.6;
		colour *= 0.7 + 0.3 * chance.x;
	}
	ALBEDO = colour;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
"""

static var _shader: Shader

## Calm, a breeze or a storm. Setting it sets `strength`; the wind then rises
## or drops to it over a few seconds.
@export var weather := Weather.BREEZE:
	set(value):
		weather = value
		strength = STRENGTHS[value]
## How hard it blows, 0..1: 0 calm, 0.35 a breeze, 1 a storm.
@export_range(0.0, 1.0) var strength := 0.35
## The way it blows, over the ground (x, z).
@export var direction := Vector2(1.0, 0.0)
## How much it comes and goes, 0..1.
@export_range(0.0, 1.0) var gusty := 0.6
## The colour of sand in the air.
@export var colour := Color(0.86, 0.76, 0.58)
## The colour of the ribbons of sand it blows along the ground, and of the
## grains in the air. (Not in Outside's copy, where they are always this.)
@export var streamers := Color(0.93, 0.83, 0.64):
	set(value):
		streamers = value
		if _material:
			_material.set_shader_parameter(&"tint", streamers)
## Where level ground is, for a level with no `SandGround`.
@export var floor_height := 0.0

## How hard it is blowing this moment, gusts and all.
var force := 0.0
## What a frame of it costs here, microseconds (not counting the drawing).
var cost_usec := 0.0

var _material: ShaderMaterial
var _risen := 0.0
var _clock := 0.0
var _travel := 0.0
var _ground: SandGround
var _environment: Environment
var _sky := Color.BLACK
var _fog := 0.0
var _fog_colour := Color.BLACK
var _sun: DirectionalLight3D
var _looked := false


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	custom_aabb = AABB(Vector3.ONE * -8000.0, Vector3.ONE * 16000.0)
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	_material = ShaderMaterial.new()
	_material.shader = _shader
	_material.set_shader_parameter(&"tint", streamers)
	# A ribbon: a strip, so that it can lie along ground that is not flat.
	var points := PackedVector3Array()
	var places := PackedVector2Array()
	var corners := PackedInt32Array()
	for i in PIECES + 1:
		for x: float in [0.0, 1.0]:
			points.append(Vector3(x - 0.5, 0.0, float(i) / PIECES - 0.5))
			places.append(Vector2(x, float(i) / PIECES))
		if i < PIECES:
			corners.append_array([i * 2, i * 2 + 1, i * 2 + 3, i * 2, i * 2 + 3, i * 2 + 2])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	arrays[Mesh.ARRAY_TEX_UV] = places
	arrays[Mesh.ARRAY_INDEX] = corners
	var ribbon := ArrayMesh.new()
	ribbon.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	ribbon.surface_set_material(0, _material)
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = ribbon
	multimesh.instance_count = STREAMERS + GRAINS + VEILS
	var random := RandomNumberGenerator.new()
	random.seed = 5
	for i in STREAMERS + GRAINS + VEILS:
		multimesh.set_instance_transform(i, Transform3D.IDENTITY)
		if i < VEILS:
			# (first, and the furthest first: they are drawn in this order, back to front,
			# and what is blowing about is drawn over them)
			multimesh.set_instance_custom_data(i, Color(2.0, float(VEILS - 1 - i) / VEILS, 0.0, 0.0))
			continue
		multimesh.set_instance_custom_data(i, Color(0.0 if i < VEILS + STREAMERS else 1.0, random.randf(), random.randf(), random.randf()))
	_risen = strength


func _exit_tree() -> void:
	# (the air is left as it was found)
	if _environment:
		_environment.background_color = _sky
		_environment.fog_density = _fog
		_environment.fog_light_color = _fog_colour
	Sand.blow(Sand.wind_way, 0.0, Sand.wind_travel, Color(colour, 0.0))


## Sets the weather (the same as setting `weather`).
func calm() -> void:
	weather = Weather.CALM


func breeze() -> void:
	weather = Weather.BREEZE


func storm() -> void:
	weather = Weather.STORM


## How fast it is blowing loose sand along the ground, metres a second.
func speed() -> float:
	return 1.5 + 9.0 * force


func _process(delta: float) -> void:
	var began := Time.get_ticks_usec()
	if not _looked:
		_look_round()
	_clock += delta
	_risen = move_toward(_risen, strength, delta * 0.3)
	# Gusts: it comes and goes over ten seconds or so, and flutters within that.
	var gust := 0.5 + 0.34 * sin(_clock * 0.47) * sin(_clock * 0.131 + 1.0) + 0.16 * sin(_clock * 1.7 + 2.0 * sin(_clock * 0.37))
	force = clampf(_risen * lerpf(1.0, 0.35 + 1.3 * gust, gusty), 0.0, 1.0)
	_travel += speed() * delta
	var way := direction.normalized() if direction.length() > 0.001 else Vector2(1.0, 0.0)
	# Sand in the air. The sand draws its own; anything else gets the level's fog, if it has any.
	var thick := force * force * force * 0.022
	var own_fog := _environment != null and _fog > 0.0 and _environment.fog_enabled
	var air := colour.srgb_to_linear()
	# (the sand could draw its own haze, see `Sand.haze`; the sheets do it for everything)
	air.a = 0.0
	_material.set_shader_parameter(&"veil", Color(colour.lightened(0.15), 0.0 if own_fog else thick))
	Sand.blow(way, force, _travel, air)
	if _environment:
		var dulled := clampf(force * force * 1.1, 0.0, 0.85)
		if _environment.background_mode == Environment.BG_COLOR:
			_environment.background_color = _sky.lerp(colour.lightened(0.15), dulled)
		if own_fog:
			_environment.fog_density = _fog + thick
			_environment.fog_light_color = _fog_colour.lerp(colour, dulled)
	var camera := get_viewport().get_camera_3d()
	_material.set_shader_parameter(&"clock", _clock)
	_material.set_shader_parameter(&"travel", _travel)
	_material.set_shader_parameter(&"wind", Vector3(way.x, way.y, force))
	var spent := 1.0 if Sand.quality >= 2 else (0.6 if Sand.quality == 1 else 0.3)
	_material.set_shader_parameter(&"amount", Vector2(smoothstep(0.02, 0.45, force), smoothstep(0.1, 1.0, force)) * spent)
	visible = force > 0.04
	if camera:
		_material.set_shader_parameter(&"eye", camera.global_position)
	if _sun:
		_material.set_shader_parameter(&"sun_way", _sun.global_basis.z)
		_material.set_shader_parameter(&"light", Color(0.55, 0.57, 0.62) + _sun.light_color * 0.5)
	cost_usec = lerpf(cost_usec, float(Time.get_ticks_usec() - began), 0.1)


# Finds the ground to blow over, the air to thicken and the sun, once the
# level has made them.
func _look_round() -> void:
	_looked = true
	var top := get_tree().current_scene if get_tree().current_scene else get_tree().root
	_ground = get_tree().get_first_node_in_group(&"sand_grounds") as SandGround
	if _ground and _ground.is_built():
		_ground.lend(_material)
	else:
		_material.set_shader_parameter(&"field", Vector4(0.0, 0.0, 0.0, floor_height))
		# (a ground that is made later is looked for again)
		_looked = _ground == null
	for found: WorldEnvironment in top.find_children("*", "WorldEnvironment", true, false):
		if found.environment:
			_environment = found.environment
			_sky = _environment.background_color
			_fog = _environment.fog_density if _environment.fog_enabled else 0.0
			_fog_colour = _environment.fog_light_color
			break
	for found: DirectionalLight3D in top.find_children("*", "DirectionalLight3D", true, false):
		_sun = found
		break
