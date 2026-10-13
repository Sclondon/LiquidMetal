class_name SandFall
extends Node3D
## Sand pouring straight down from where this node is placed: out of a spout,
## or with `width` out of a slot that long, lying along the node's X. Where it
## lands it heaps up into a `SandPile` that can be walked up. `running` turns
## it on and off; what is already in the air carries on down.
##
## Nothing is moved from here: the stream is one MultiMesh, and the shader
## works out where each grain has got to from how long ago it was poured. All
## this does each frame is tell it the time, and how far down the pile now is.

## How many grains are in the air at once, besides the body of the stream.
const GRAINS := 160
## Sand leaves the mouth at `PUSH` m/s and gathers speed at `PULL` m/s².
const PUSH := 0.9
const PULL := 14.0
## How long a grain goes on rolling down the pile after it lands, seconds.
const SLIDE := 0.7

const SHADER := """
shader_type spatial;
render_mode world_vertex_coords, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, specular_disabled;

uniform vec3 tint : source_color = vec3(0.83, 0.68, 0.45);
uniform vec3 glint : source_color = vec3(1.0, 0.95, 0.82);
// The time now, and when it was last turned on and off.
uniform float clock = 0.0;
uniform float on_at = 0.0;
uniform float off_at = -1.0;
uniform float push = 0.9;
uniform float pull = 14.0;
uniform float slide = 0.7;
// How far below the mouth the sand lands, how long every grain's round trip
// takes, half the length of the slot, and half the thickness of the stream.
uniform float drop = 5.0;
uniform float period = 2.0;
uniform float half_width = 0.0;
uniform float thickness = 0.06;
// The pile it lands on: how far out its foot is, and how steep its sides.
uniform float pile = 0.0;
uniform float slope = 0.577;

// 1: the body of the stream, one tall card; 0: a grain.
varying float body;
varying vec2 where;
varying float seed;
varying float fade;
varying float fallen;

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

// Whether sand was coming out at the time `born`.
float pours(float born) {
	if (off_at < on_at) {
		return float(born >= on_at || born <= off_at);
	}
	return float(born >= on_at && born <= off_at);
}

// How long sand takes to fall `far` metres.
float time_to(float far) {
	return (sqrt(push * push + 2.0 * pull * far) - push) / pull;
}

void vertex() {
	vec2 corner = UV - 0.5;
	where = UV;
	seed = INSTANCE_CUSTOM.y;
	fade = 1.0;
	vec3 mouth = MODEL_MATRIX[3].xyz;
	vec3 along = normalize(MODEL_MATRIX[0].xyz);
	vec3 across = normalize(MODEL_MATRIX[2].xyz);
	vec3 up = vec3(0.0, 1.0, 0.0);
	// Level, and square to the camera.
	vec3 side = normalize(cross(up, INV_VIEW_MATRIX[2].xyz));
	if (INSTANCE_CUSTOM.x < 0.0) {
		// The body of the stream: as long as the slot, turned to the camera
		// across its thickness, and as tall as the drop.
		body = 1.0;
		fallen = UV.y * drop;
		VERTEX = mouth + (along * half_width + side * thickness * 1.4) * corner.x * 2.0 - up * fallen;
	} else {
		body = 0.0;
		fallen = 0.0;
		float age = fract(clock / period + INSTANCE_CUSTOM.x) * period;
		float shown = pours(clock - age);
		vec3 chance = INSTANCE_CUSTOM.yzw;
		float landed = time_to(drop);
		vec3 middle;
		vec3 tall = up;
		vec2 size;
		if (age < landed) {
			// Falling: a streak, longer the faster it goes, straying a little as it falls.
			vec2 stray = (chance.yz - 0.5) * (thickness * 2.4 + 0.1 * age);
			middle = mouth + along * ((chance.x * 2.0 - 1.0) * half_width + stray.x) + across * stray.y
					- up * (push * age + 0.5 * pull * age * age);
			size = vec2(0.04, 0.04 + (push + pull * age) * 0.018) * (0.6 + chance.y * 0.8);
		} else {
			// Landed: it runs out down the side of the pile, slowing, and is gone.
			float since = age - landed;
			float run = pile * (1.0 - exp(-since * 3.5)) * (0.35 + 0.65 * chance.y);
			float angle = chance.z * TAU;
			vec2 way = vec2(cos(angle) * (half_width > 0.0 ? 0.2 : 1.0), sin(angle));
			way = normalize(way);
			middle = mouth + along * ((chance.x * 2.0 - 1.0) * half_width + way.x * run) + across * way.y * run
					- up * (drop + run * slope * 0.95 - 0.05);
			tall = INV_VIEW_MATRIX[1].xyz;
			size = vec2(0.05);
			fade = 1.0 - since / slide;
			shown *= step(since, slide);
		}
		VERTEX = middle + (side * corner.x * size.x - tall * corner.y * size.y) * shown;
	}
	NORMAL = INV_VIEW_MATRIX[2].xyz;
}

void fragment() {
	vec3 colour = tint;
	float alpha;
	if (body > 0.5) {
		// Threads of sand, thick and thin, each carried down as it was poured:
		// the pattern belongs to the moment the sand left, so it falls with it.
		float born = clock - time_to(fallen);
		float threads = patches(vec2(where.x * (5.0 + half_width * 16.0), born * 7.0));
		float fine = patches(vec2(where.x * (19.0 + half_width * 60.0), born * 26.0));
		// (it comes apart as it falls)
		float thin = 0.12 + 0.03 * fallen;
		float edge = clamp(min(where.x, 1.0 - where.x) * (half_width + thickness * 1.4) * 2.0 / 0.05, 0.0, 1.0);
		alpha = smoothstep(thin, thin + 0.4, threads * 0.65 + fine * 0.35) * edge * pours(born) * 0.92;
		colour *= 0.82 + 0.3 * fine;
	} else {
		alpha = (1.0 - smoothstep(0.35, 1.0, length(where * 2.0 - 1.0))) * fade * 0.9;
		colour *= 0.8 + 0.35 * seed;
		// Now and then one catches the light.
		float flash = step(0.88, hash2(vec2(seed * 91.0, floor(clock * 9.0 + seed * 7.0))));
		colour = mix(colour, glint * 1.7, flash);
	}
	ALBEDO = colour;
	ALPHA = alpha;
}

void light() {
	// Lit as much from one side as another: it is a cloud of grains, not a card.
	DIFFUSE_LIGHT += clamp(ATTENUATION, 0.0, 1.0) * LIGHT_COLOR / PI;
}
"""

static var _shader: Shader

## How long the slot is, metres, along this node's X; 0 for a spout.
@export var width := 0.0
## Whether sand is coming out.
@export var running := true: set = _set_running
## How fast the pile under it fills, cubic metres a second.
@export var rate := 0.25
## How far out the foot of the pile gets before it stops growing.
@export var pile_cap := 2.4
## As far down as it looks for something to land on.
@export var max_drop := 14.0
## The colour of the sand, and of the heap it makes. Set it before it enters
## the scene. (Not in Outside's copy, where it is always `Sand.COLOUR`.)
@export var colour := Sand.COLOUR

## The heap it has made, once it has found the ground.
var pile: SandPile

var _clock := 0.0
var _on_at := 0.0
var _off_at := -1000.0
var _floor_drop := 0.0
var _ticks := 0
var _puff_in := 0.0
var _material: ShaderMaterial
var _dust: Dust


func _ready() -> void:
	if not running:
		_on_at = -1001.0
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	_material = ShaderMaterial.new()
	_material.shader = _shader
	_material.set_shader_parameter(&"tint", colour)
	_material.set_shader_parameter(&"push", PUSH)
	_material.set_shader_parameter(&"pull", PULL)
	_material.set_shader_parameter(&"slide", SLIDE)
	_material.set_shader_parameter(&"half_width", width * 0.5)
	_material.set_shader_parameter(&"slope", tan(SandPile.SLOPE))
	_material.set_shader_parameter(&"on_at", _on_at)
	_material.set_shader_parameter(&"off_at", _off_at)
	_floor_drop = max_drop
	_material.set_shader_parameter(&"drop", _floor_drop)
	_material.set_shader_parameter(&"period", _time_to(_floor_drop) + SLIDE)
	var card := QuadMesh.new()
	card.size = Vector2.ONE
	card.material = _material
	var grains := MultiMesh.new()
	grains.transform_format = MultiMesh.TRANSFORM_3D
	grains.use_custom_data = true
	grains.mesh = card
	grains.instance_count = GRAINS + 1
	var random := RandomNumberGenerator.new()
	random.seed = hash(name)
	for i in GRAINS + 1:
		grains.set_instance_transform(i, Transform3D.IDENTITY)
		# When in the round it is poured, and three numbers of its own. The
		# last one is the body of the stream.
		grains.set_instance_custom_data(i, Color(-1.0 if i == GRAINS else (i + random.randf()) / GRAINS, random.randf(), random.randf(), random.randf()))
	var stream := MultiMeshInstance3D.new()
	stream.multimesh = grains
	stream.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# (the shader puts the grains where they are, so say how far they may be)
	var reach := width * 0.5 + pile_cap + 1.0
	stream.custom_aabb = AABB(Vector3(-reach, -max_drop - 1.0, -reach), Vector3(reach * 2.0, max_drop + 2.0, reach * 2.0))
	add_child(stream)
	_dust = Dust.new()
	add_child(_dust)
	(_dust.multimesh.mesh.material as ShaderMaterial).set_shader_parameter(&"tint", colour.lightened(0.25))


## Empties the pile.
func reset() -> void:
	if pile:
		pile.volume = 0.0


func _set_running(to: bool) -> void:
	if to == running:
		return
	running = to
	if not is_node_ready():
		return
	if running:
		_on_at = _clock
	else:
		_off_at = _clock
	_material.set_shader_parameter(&"on_at", _on_at)
	_material.set_shader_parameter(&"off_at", _off_at)


func _physics_process(_delta: float) -> void:
	# The ground is looked for once, when everything round it has been built.
	_ticks += 1
	if _ticks == 2:
		_find_floor()
		set_physics_process(false)


func _find_floor() -> void:
	var from := global_position
	var hit := get_world_3d().direct_space_state.intersect_ray(
			PhysicsRayQueryParameters3D.create(from + Vector3.DOWN * 0.05, from + Vector3.DOWN * max_drop, 1))
	if hit.is_empty():
		return
	_floor_drop = from.y - (hit.position as Vector3).y
	_material.set_shader_parameter(&"period", _time_to(_floor_drop) + SLIDE)
	pile = SandPile.new()
	pile.length = width
	pile.cap = pile_cap
	pile.colour = colour
	pile.top_level = true
	add_child(pile)
	pile.global_transform = Transform3D(Basis(Vector3.UP, global_rotation.y), hit.position)


func _process(delta: float) -> void:
	_clock += delta
	var drop := _floor_drop - (pile.height if pile else 0.0)
	_material.set_shader_parameter(&"clock", _clock)
	_material.set_shader_parameter(&"drop", drop)
	if pile == null:
		return
	_material.set_shader_parameter(&"pile", pile.radius)
	# What is landing now left the mouth a moment ago.
	if not _poured(_clock - _time_to(drop)):
		return
	pile.volume += rate * delta
	_puff_in -= delta
	if _puff_in <= 0.0:
		_puff_in = randf_range(0.1, 0.2)
		var along := global_basis.x * randf_range(-0.5, 0.5) * width
		_dust.puff(pile.global_position + along + Vector3.UP * (pile.height - 0.05), Vector3.ZERO, randf_range(0.3, 0.5))


## Whether sand was coming out at the time `born` (the shader asks the same).
func _poured(born: float) -> bool:
	if _off_at < _on_at:
		return born >= _on_at or born <= _off_at
	return born >= _on_at and born <= _off_at


## How long sand takes to fall `far` metres.
func _time_to(far: float) -> float:
	return (sqrt(PUSH * PUSH + 2.0 * PULL * far) - PUSH) / PULL
