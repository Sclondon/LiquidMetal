extends Node3D
## The trail Mercury leaves: little flat puddles of metal left on the floor behind it as it runs,
## shrinking away after a moment. World space (left where they fall). The player calls drop().

const MAX := 48
const LIFE := 1.4 # seconds a puddle lasts

var material: Material

var _live: Array[Dictionary] = []
var _pool: Array[MeshInstance3D] = []


func _ready() -> void:
	top_level = true
	var disc := SphereMesh.new() # squashed flat into a puddle
	disc.radius = 1.0
	disc.height = 2.0
	disc.radial_segments = 14
	disc.rings = 5
	for i in MAX:
		var view := MeshInstance3D.new()
		view.mesh = disc
		view.material_override = material
		view.visible = false
		view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		view.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		add_child(view)
		_pool.append(view)


## Leave a puddle at a spot on the floor, stretched along the way it was going
func drop(at: Vector3, heading: float, size: float) -> void:
	var view: MeshInstance3D
	if _pool.is_empty():
		# Out of puddles: reuse the oldest
		view = _live.pop_front().view
	else:
		view = _pool.pop_back()
	view.visible = true
	view.global_position = Vector3(at.x, at.y + 0.01, at.z)
	view.rotation = Vector3(0.0, heading + randf_range(-0.3, 0.3), 0.0)
	_live.append({ view = view, age = 0.0, size = size * randf_range(0.7, 1.3) })


func clear() -> void:
	for puddle in _live:
		puddle.view.visible = false
		_pool.append(puddle.view)
	_live.clear()


func _process(delta: float) -> void:
	for i in range(_live.size() - 1, -1, -1):
		var puddle: Dictionary = _live[i]
		puddle.age += delta
		var left: float = 1.0 - puddle.age / LIFE
		if left <= 0.0:
			puddle.view.visible = false
			_pool.append(puddle.view)
			_live.remove_at(i)
			continue
		# Spreads a touch at first, then shrinks away
		var r: float = puddle.size * minf(puddle.age * 8.0 + 0.5, 1.0) * sqrt(left)
		puddle.view.scale = Vector3(r * 0.8, r * 0.12, r * 1.4)
