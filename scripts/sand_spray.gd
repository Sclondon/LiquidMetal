class_name SandSpray
extends MultiMeshInstance3D
## Loose sand in the air, all of it drawn at once as one MultiMesh:
##
## - `kick`: grains thrown up from a point, as a foot throws them. Each is a
##   grain or a small clump of them, a centimetre or two across and no
##   particular shape: flung out, pulled straight back down by its weight in an
##   arc, carried a little by the wind on the way, and left lying a moment
##   where it lands before it is lost among the rest of the sand.
## - `ring`: the same, thrown out all round, for a landing.
##
## Sand is heavy. Nothing here floats or hangs: a grain is in the air for a
## third of a second, and what makes a kick look like sand is that there are
## many of them and that they all come down.
##
## Nothing is moved from here. Each grain is given where it starts, how fast,
## and when; the shader works out where it has got to. All this does each
## frame is tell it the time. `SandGround` keeps one and uses it for feet,
## slides and whatever is thrown; add another anywhere and call it yourself.
## (Sand that runs down a slope is not this: it is the ground itself that
## moves. See `SandGround.ooze`.)
##
## What it costs: one draw call, of `COUNT` small squares (most of them a few
## pixels, and those not in use no size at all), and nothing each frame but
## the clock. A kick is a line or two of work for each grain it throws.

const COUNT := 2048
const FALL := 11.0
## How many grains there are to a handful (see `kick`).
const GRAINS := 14.0

const SHADER := """
shader_type spatial;
render_mode world_vertex_coords, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, unshaded;

uniform float clock = 0.0;
uniform float fall = 11.0;
uniform vec3 glint : source_color = vec3(1.0, 0.95, 0.82);
// The wind over the ground (x, z) and how hard: it carries off what is thrown up.
uniform vec3 wind = vec3(1.0, 0.0, 0.0);
// The light on it: it is lit as much from one side as another (it is loose
// grains, not a card), so this is worked out once for all of it, from the
// sun and the sky, and not by the renderer: the two renderers would differ.
uniform vec3 shine = vec3(1.0);
// 1 where the renderer puts what is drawn this way on the screen as it comes
// (the web's): the colour is then made ready for the screen here.
uniform float as_shown = 0.0;

varying vec2 where;
varying float seed;
varying float flash;
varying vec3 tint;

float hash1(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	return fract(p * (p + p));
}

void vertex() {
	vec3 start = MODEL_MATRIX[3].xyz;
	vec3 speed = MODEL_MATRIX[0].xyz;
	float size = MODEL_MATRIX[1].x;
	float life = MODEL_MATRIX[1].y;
	float age = clock - MODEL_MATRIX[1].z;
	// How the ground it was thrown from lies: how much it rises for each
	// metre along x and along z. And how far the wind takes this grain.
	vec2 slope = MODEL_MATRIX[2].xy;
	float drift = MODEL_MATRIX[2].z;
	// (its colour comes with it here, not as a colour: the two renderers read those differently)
	seed = INSTANCE_CUSTOM.x;
	tint = INSTANCE_CUSTOM.yzw;
	where = UV;
	// Thrown, and pulled down, until it meets the ground again.
	float lands = max(2.0 * (speed.y - dot(slope, speed.xz)) / fall, 0.03);
	float flown = clamp(age, 0.0, lands);
	vec3 middle = start + speed * flown;
	middle.y -= 0.5 * fall * flown * flown;
	middle.xz += wind.xy * wind.z * drift * flown * flown;
	middle.y = max(middle.y, start.y + dot(slope, middle.xz - start.xz)) + size * 0.3;
	vec3 going = speed;
	going.y -= fall * flown;
	// (never drawn smaller than a pixel and a bit: from where the game is
	// seen a grain is less than that, and a spray of them would come and go)
	size = max(size, 3.6 * length(CAMERA_POSITION_WORLD - middle) / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y));
	// Lying where it landed it dwindles to nothing.
	float flying = step(age, lands);
	float shown = step(0.0, age) * step(age, life) * (1.0 - smoothstep(lands, life, age) * 0.85);
	// In the air it is drawn out a little along the way it is going, which is
	// what tells the eye how fast; lying, it is as wide as it is long.
	float pace = length(going);
	vec3 along = mix(INV_VIEW_MATRIX[1].xyz, going / max(pace, 0.001), flying);
	vec3 side = cross(along, normalize(CAMERA_POSITION_WORLD - middle));
	side = length(side) > 0.01 ? normalize(side) : INV_VIEW_MATRIX[0].xyz;
	float drawn_out = 1.0 + min(pace * 0.3, 2.0) * flying;
	vec2 corner = UV - 0.5;
	VERTEX = middle + (side * corner.x + along * corner.y * drawn_out) * size * shown;
	NORMAL = INV_VIEW_MATRIX[2].xyz;
	// Now and then one catches the light, for a moment.
	flash = step(0.93, hash1(seed * 91.0 + floor(age * 16.0))) * flying;
}

void fragment() {
	// A chip of no particular shape: a square with each side cut at its own
	// slant, and its own distance from the middle.
	vec2 on = where * 2.0 - 1.0;
	float a = hash1(seed * 13.0 + 1.0);
	float b = hash1(seed * 29.0 + 2.0);
	float c = hash1(seed * 47.0 + 3.0);
	float d = hash1(seed * 71.0 + 4.0);
	float out_from = max(max(on.x + on.y * (a - 0.5) * 1.3, -on.x + on.y * (b - 0.5) * 1.3) / (0.55 + 0.45 * c),
			max(on.y + on.x * (c - 0.5) * 1.3, -on.y + on.x * (d - 0.5) * 1.3) / (0.55 + 0.45 * a));
	// (grains differ: some are dark against the rest)
	vec3 colour = tint * (0.62 + 0.5 * b);
	vec3 lit = mix(colour, glint, flash * 0.45) * shine;
	ALBEDO = mix(lit, pow(lit, vec3(0.4545)), as_shown);
	// (drawn with the things that are seen through, though nothing shows
	// through a grain: the web's renderer colours those as the other does)
	ALPHA = step(out_from, 1.0);
}
"""

static var _shader: Shader

var _material: ShaderMaterial
var _clock := 0.0
var _next := 0
## How many grains are spent of each kick, as a share: turned down with `Sand.quality`.
var thrift := 1.0
var _look := 0.0


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# (they are wherever the sand was last kicked)
	custom_aabb = AABB(Vector3.ONE * -8000.0, Vector3.ONE * 16000.0)
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	_material = ShaderMaterial.new()
	_material.shader = _shader
	_material.set_shader_parameter(&"fall", FALL)
	var card := QuadMesh.new()
	card.size = Vector2.ONE
	card.material = _material
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = card
	multimesh.instance_count = COUNT
	for i in COUNT:
		# (born long ago: not shown)
		multimesh.set_instance_transform(i, Transform3D(Basis(Vector3.ZERO, Vector3(0.0, 1.0, -1000.0), Vector3.ZERO), Vector3.ZERO))
		multimesh.set_instance_custom_data(i, Color(0.0, 0.0, 0.0, 0.0))


func _process(delta: float) -> void:
	_clock += delta
	_look -= delta
	if _look <= 0.0:
		_look = 1.0
		_find_light()
	_material.set_shader_parameter(&"clock", _clock)
	_material.set_shader_parameter(&"wind", Vector3(Sand.wind_way.x, Sand.wind_way.y, Sand.wind_force))


## Throws `count` handfuls of sand (`GRAINS` grains to each) from `at`, a
## point on the ground, at about `velocity`, every grain a little differently:
## `spread` is how far, as a share of the speed. `size` is how coarse it is
## (0.16 is sand; more for a harder kick, which throws up clumps). `normal` is
## which way the ground faces there: on a slope the grains come down on it,
## not through it.
func kick(at: Vector3, velocity: Vector3, count: int, spread := 0.5, colour := Sand.COLOUR, size := 0.16, delay := 0.0, normal := Vector3.UP) -> void:
	var grains := maxi(int(round(count * GRAINS * thrift)), 1)
	var pace := velocity.length()
	var slope := _slope(normal)
	for k in grains:
		var stray := Vector3(randf_range(-1.0, 1.0), randf_range(-0.4, 1.0), randf_range(-1.0, 1.0)) * spread * pace
		var speed := velocity * randf_range(0.45, 1.2) + stray
		speed.y = maxf(speed.y, 0.5)
		_throw(at + Vector3(randf_range(-0.05, 0.05), 0.0, randf_range(-0.05, 0.05)), speed, size, slope, colour, delay + randf_range(0.0, 0.06))


## Throws sand out all round `at`, low and fast: what a landing raises.
## `count` is in handfuls, as for `kick`.
func ring(at: Vector3, speed: float, count: int, colour := Sand.COLOUR, size := 0.2, normal := Vector3.UP) -> void:
	var grains := maxi(int(round(count * GRAINS * thrift)), 3)
	var turn := randf() * TAU
	var slope := _slope(normal)
	for k in grains:
		var angle := turn + TAU * (k + randf_range(-0.5, 0.5)) / grains
		var out := Vector3(cos(angle), 0.0, sin(angle))
		var each := speed * randf_range(0.35, 1.1)
		_throw(at + out * randf_range(0.04, 0.14), out * each + Vector3.UP * each * randf_range(0.5, 1.3), size, slope, colour, randf_range(0.0, 0.05))


# How much the ground rises for each metre along x and along z, where it faces `normal`.
func _slope(normal: Vector3) -> Vector2:
	return Vector2(-normal.x, -normal.z) / maxf(normal.y, 0.3)


# One grain, or (now and then) a clump of them, which is bigger and which the wind moves less.
func _throw(at: Vector3, speed: Vector3, size: float, slope: Vector2, colour: Color, delay: float) -> void:
	var clump := randf() < 0.12
	var across := size * (0.09 if clump else 0.042) * randf_range(0.7, 1.3)
	var lands := maxf(2.0 * (speed.y - slope.dot(Vector2(speed.x, speed.z))) / FALL, 0.03)
	var i := _next
	_next = (_next + 1) % COUNT
	multimesh.set_instance_transform(i, Transform3D(Basis(speed, Vector3(across, lands + randf_range(0.15, 0.4), _clock + delay),
			Vector3(slope.x, slope.y, 1.2 if clump else randf_range(2.5, 4.5))), at))
	multimesh.set_instance_custom_data(i, Color(randf(), colour.r, colour.g, colour.b))


# How bright sand in the open is here: the sun's light, as much of it as falls
# on a heap of loose grains, and the sky's.
func _find_light() -> void:
	var top := get_tree().current_scene if get_tree().current_scene else get_tree().root
	var shine := Color(0.0, 0.0, 0.0)
	for sun: DirectionalLight3D in top.find_children("*", "DirectionalLight3D", true, false):
		if sun.visible:
			shine += sun.light_color.srgb_to_linear() * sun.light_energy * Sand.sun_gain * 0.62
			break
	var sky := Color(0.5, 0.5, 0.5)
	for world: WorldEnvironment in top.find_children("*", "WorldEnvironment", true, false):
		if world.environment and world.environment.ambient_light_source == Environment.AMBIENT_SOURCE_COLOR:
			sky = world.environment.ambient_light_color.srgb_to_linear() * world.environment.ambient_light_energy
		break
	shine += sky
	# (the web's renderer: see `as_shown` in the shader)
	_material.set_shader_parameter(&"as_shown", 1.0 if RenderingServer.get_current_rendering_method() == "gl_compatibility" else 0.0)
	_material.set_shader_parameter(&"shine", Vector3(shine.r, shine.g, shine.b))
