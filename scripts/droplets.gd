extends Node3D
## Little blobs of Mercury's metal that flop off as it moves and rejoin it: flung out from a
## body part, they fly free for a moment, then get pulled back to the part they came from and
## merge in. Purely for looks (no collisions). The player calls burst() on steps, landings,
## dodges and dashes.

signal rejoined(part: Node3D) # a blob merged back in

const MAX := 32
const FREE_TIME := 0.45 # seconds of free flight before the pull back starts
const PULL := 28.0 # spring strength of the pull back
const GRAVITY := 22.0

var material: Material
var source: CharacterBody3D # the player: its velocity is the droplets' starting velocity
var parts: Array[Node3D] = [] # where they come off, and go back to

var _live: Array[Dictionary] = []
var _pool: Array[MeshInstance3D] = []


func _ready() -> void:
	top_level = true # world space: they're left behind and caught up with, not carried along
	var sphere := SphereMesh.new()
	sphere.radius = 0.05
	sphere.height = 0.1
	sphere.radial_segments = 10
	sphere.rings = 6
	for i in MAX:
		var view := MeshInstance3D.new()
		view.mesh = sphere
		view.material_override = material
		view.visible = false
		view.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		add_child(view)
		_pool.append(view)


## Fling `count` blobs off random body parts; strength scales how hard
func burst(count: int, strength := 1.0) -> void:
	if parts.is_empty():
		return
	for i in count:
		if _pool.is_empty():
			return
		var part: Node3D = parts[randi() % parts.size()]
		var offset := Vector3(randf_range(-0.12, 0.12), randf_range(-0.12, 0.12), randf_range(-0.12, 0.12))
		var fling := Vector3(randf_range(-4.0, 4.0), randf_range(2.0, 5.5), randf_range(-1.5, 1.5))
		# Thrown back against the run a little, so they trail behind before catching up
		fling -= source.forward() * randf_range(1.0, 3.0)
		var view: MeshInstance3D = _pool.pop_back()
		view.visible = true
		var size := randf_range(0.5, 1.1)
		view.scale = Vector3.ONE * size
		view.global_position = part.global_position + offset
		_live.append({
			view = view, part = part, offset = offset, size = size, age = 0.0,
			velocity = source.velocity + fling * strength,
		})


## Everything back in at once (a splat, a respawn)
func clear() -> void:
	for drop in _live:
		drop.view.visible = false
		_pool.append(drop.view)
	_live.clear()


func _process(delta: float) -> void:
	for i in range(_live.size() - 1, -1, -1):
		var drop: Dictionary = _live[i]
		drop.age += delta
		var view: MeshInstance3D = drop.view
		var home: Vector3 = drop.part.global_position + drop.offset * 0.3
		var velocity: Vector3 = drop.velocity
		if drop.age < FREE_TIME:
			velocity.y -= GRAVITY * delta
		else:
			# Pulled home, harder the longer it's been out; damped so it doesn't orbit
			var pull: float = PULL * (1.0 + (drop.age - FREE_TIME) * 4.0)
			velocity += (home - view.global_position) * pull * delta
			velocity = velocity.lerp(source.velocity, 1.0 - exp(-delta * 4.0))
		# Moved, but not through anything: off a wall or the floor it skids and bounces a little
		var to: Vector3 = view.global_position + velocity * delta
		var ray := PhysicsRayQueryParameters3D.create(view.global_position, to)
		ray.exclude = [source.get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(ray)
		if not hit.is_empty():
			var normal: Vector3 = hit.normal
			to = hit.position + normal * 0.04
			velocity = velocity.slide(normal) * 0.6 + normal * maxf(-velocity.dot(normal), 0.0) * 0.25
		drop.velocity = velocity
		view.global_position = to
		# Stretched along its motion, like a drop of liquid
		var relative := velocity - source.velocity
		if relative.length_squared() > 0.01:
			view.look_at(view.global_position + relative, Vector3.UP if absf(relative.normalized().y) < 0.99 else Vector3.RIGHT)
		var stretch := clampf(relative.length() * 0.08, 0.0, 1.2)
		view.scale = Vector3(1.0, 1.0, 1.0 + stretch) * drop.size
		# Rejoined: close enough (or out too long), it merges back in
		if (drop.age > FREE_TIME and view.global_position.distance_to(home) < 0.12) or drop.age > 2.2:
			rejoined.emit(drop.part)
			view.visible = false
			_pool.append(view)
			_live.remove_at(i)
