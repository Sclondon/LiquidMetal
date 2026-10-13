extends MultiMeshInstance3D
## What a Crystalien leaves behind it where it runs: little crystals that sprout from the ground
## at its heels, stand a moment, and shrink back in. (Mercury leaves tracks of liquid metal:
## trail.gd; a Crystalien has nothing liquid about it.) World space; the runner calls step()
## every frame.

const Crystal := preload("res://scripts/crystal.gd")
const COUNT := 40
const EVERY := 0.8 # metres run between sprouts
const LIFE := 1.5 # seconds one stands

var material: Material

var _births: PackedFloat32Array = []
var _places: Array[Transform3D] = []
var _next := 0
var _run := 0.0
var _last := Vector3.INF
var _clock := 0.0


func _ready() -> void:
	top_level = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = Crystal.shard(0.07, 0.5, 0.3, 5)
	multimesh.instance_count = COUNT
	material_override = material
	extra_cull_margin = 200.0
	for i in COUNT:
		_births.append(-100.0)
		_places.append(Transform3D.IDENTITY)
		multimesh.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * 0.001), Vector3.DOWN * 100.0))


## feet: where its feet are; floor: the ground's height under it (NAN: it's in the air)
func step(feet: Array[Vector3], floor: float, delta: float) -> void:
	_clock += delta
	if not is_nan(floor) and not feet.is_empty():
		var here := (feet[0] + feet[feet.size() - 1]) * 0.5
		if _last != Vector3.INF:
			_run += here.distance_to(_last)
		_last = here
		while _run > EVERY:
			_run -= EVERY
			var foot := feet[_next % feet.size()]
			var lean := Basis(Vector3.UP, randf() * TAU) * Basis(Vector3.RIGHT, randf_range(-0.45, 0.45))
			_places[_next] = Transform3D(lean.scaled(Vector3.ONE * randf_range(0.7, 1.5)), Vector3(foot.x, floor + 0.08, foot.z))
			_births[_next] = _clock
			_next = (_next + 1) % COUNT
	else:
		_last = Vector3.INF
	# Up out of the ground quickly, a moment standing, back down
	for i in COUNT:
		var age := _clock - _births[i]
		if age > LIFE + 0.1:
			continue
		var grown := smoothstep(0.0, 0.12, age) * (1.0 - smoothstep(LIFE * 0.55, LIFE, age))
		var place := _places[i]
		multimesh.set_instance_transform(i, Transform3D(place.basis.scaled(Vector3.ONE * maxf(grown, 0.001)), place.origin + Vector3.DOWN * (1.0 - grown) * 0.2))


func clear() -> void:
	_last = Vector3.INF
