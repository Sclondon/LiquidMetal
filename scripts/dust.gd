class_name Dust
extends MultiMeshInstance3D
## Puffs of dust, after The Wind Waker: little pale clouds that pop up where a
## foot comes down, swell, and thin out into a ring before they are gone. Each is
## a flat disc turned to face the camera, and all of them are drawn at once.
##
## Add one as a child of whatever raises the dust and call `puff`. It stays put
## in the world while its owner moves on.

const COUNT := 40
const LIFE := 0.55

const SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled, specular_disabled;

uniform vec3 tint : source_color = vec3(0.93, 0.9, 0.84);
uniform float thickness = 0.36;

varying float age;
varying float seed;

void vertex() {
	age = INSTANCE_CUSTOM.x;
	seed = INSTANCE_CUSTOM.y;
	// Face the camera, at the size this puff has grown to.
	float size = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * size, INV_VIEW_MATRIX[1] * size, INV_VIEW_MATRIX[2] * size, MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

float cut(float value, float edge) {
	float pixel = max(fwidth(value), 0.0005);
	return smoothstep(edge - pixel, edge + pixel, value);
}

void fragment() {
	vec2 at = UV * 2.0 - 1.0;
	// A cloud's edge: a circle with a few bumps round it.
	float around = atan(at.y, at.x);
	float rim = 0.84 + 0.11 * sin(around * 5.0 + seed * 40.0) + 0.05 * sin(around * 9.0 - seed * 23.0);
	float from_middle = length(at) / rim;
	// It is whole at first, then a hole opens in the middle of it and eats it away.
	float hole = smoothstep(0.35, 1.0, age) * 1.05;
	float body = cut(1.0 - from_middle, 0.0) * cut(from_middle, hole);
	// A second, lighter tone on the side the light is not.
	float shade = cut(at.y - at.x * 0.4 + 0.25, 0.0);
	ALBEDO = tint * mix(0.82, 1.0, shade);
	ALPHA = body * thickness * (1.0 - smoothstep(0.75, 1.0, age));
}

void light() {
	// Lit as much from one side as another: it is a cloud, not a card.
	DIFFUSE_LIGHT += clamp(ATTENUATION, 0.0, 1.0) * LIGHT_COLOR / PI * 0.7;
}
"""

static var _shader: Shader

## Each puff: where it is, which way it is drifting, how big it gets, how old it is.
var _at := PackedVector3Array()
var _drift := PackedVector3Array()
var _size := PackedFloat32Array()
var _age := PackedFloat32Array()
var _seed := PackedFloat32Array()
var _next := 0


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# (they are scattered about the world, wherever he has been)
	extra_cull_margin = 16384.0
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	var material := ShaderMaterial.new()
	material.shader = _shader
	var disc := QuadMesh.new()
	disc.size = Vector2.ONE
	disc.material = material
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = disc
	multimesh.instance_count = COUNT
	_at.resize(COUNT)
	_drift.resize(COUNT)
	_size.resize(COUNT)
	_age.resize(COUNT)
	_seed.resize(COUNT)
	_age.fill(1.0)
	for i in COUNT:
		multimesh.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO))


## Raises `count` puffs at `at` (a point on the ground, in the world), each
## growing to about `size` across and drifting off along `drift` as it rises.
## With more than one they are thrown `spread` times as wide.
func puff(at: Vector3, drift: Vector3, size: float, count := 1, spread := 1.0) -> void:
	for k in count:
		var i := _next
		_next = (_next + 1) % COUNT
		var out := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)) * (0.0 if count == 1 else 1.0)
		_at[i] = at + out * size * 0.5 * spread + Vector3.UP * size * 0.25
		_drift[i] = drift + out * 0.9 * spread + Vector3.UP * randf_range(0.25, 0.5)
		_size[i] = size * randf_range(0.75, 1.2)
		# (not all at once)
		_age[i] = -randf_range(0.0, 0.08) * (count - 1)
		_seed[i] = randf()


func _process(delta: float) -> void:
	for i in COUNT:
		if _age[i] >= 1.0:
			continue
		_age[i] = minf(_age[i] + delta / LIFE, 1.0)
		var age := maxf(_age[i], 0.0)
		if _age[i] >= 1.0 or _age[i] < 0.0:
			multimesh.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ZERO), _at[i]))
			continue
		# It pops up quickly, then goes on swelling slowly; and slows as it drifts.
		_at[i] += _drift[i] * delta
		_drift[i] *= exp(-5.0 * delta)
		var grown := _size[i] * (0.35 + 0.65 * (1.0 - pow(1.0 - minf(age * 3.0, 1.0), 2.0)) + 0.25 * age)
		multimesh.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * grown), _at[i]))
		multimesh.set_instance_custom_data(i, Color(age, _seed[i], 0.0, 0.0))
