extends Node3D
## The test area: a big walled grid floor to run around in, its course laid out at random
## (generate(), again on every restart).
## - A practice lane straight ahead of the start: hurdles to jump (orange), beams to
##   duck under (cyan) and half-walls to dodge round (magenta), in a random order and spacing.
## - Off to the sides: a random field of columns and walls, a slalom, a duck tunnel and ramps.
## - Mercury drops to collect, which come back after a few seconds.
## Obstacles are Tron-style blocks (shaders/obstacle.gdshader).

const HALF := 150.0 # the arena is 300 m square
const LANE_WIDTH := 8.0
const LANE_START := 105.0
const LANE_END := -125.0
const LANE_GAP := Vector2(18.0, 28.0) # metres between lane obstacles, picked at random
const LANE_KINDS := ["hurdle", "beam", "dodge_left", "dodge_right", "dodge_both", "hurdle_pair"]

const JUMP_COLOR := Color(1.0, 0.5, 0.1)
const DUCK_COLOR := Color(0.1, 0.85, 1.0)
const DODGE_COLOR := Color(1.0, 0.2, 0.75)
const WALL_COLOR := Color(0.45, 0.5, 0.6)

var start_position := Vector3(0.0, 0.0, 128.0)
var start_heading := 0.0

## What the lane holds, in order: [{ z, kind }] (the lane bot test reads it)
var lane_plan: Array = []

var _materials := {}
var _course: Node3D # everything generate() builds, thrown away on the next one
var _rng := RandomNumberGenerator.new()
var _drops: Array[Area3D] = []
var _drop_mesh := SphereMesh.new()
var _drop_material := ShaderMaterial.new()


func _ready() -> void:
	_drop_mesh.radius = 0.28
	_drop_mesh.height = 0.56
	_drop_material.shader = preload("res://shaders/liquid_metal.gdshader")
	_drop_material.set_shader_parameter("agitation", 0.6)
	_drop_mesh.material = _drop_material

	_build_floor()
	_build_boundary()
	generate()


## Lay out a fresh course (seed 0: a random one)
func generate(seed := 0) -> void:
	if _course:
		_course.queue_free()
	_course = Node3D.new()
	add_child(_course)
	_drops.clear()
	lane_plan.clear()
	if seed == 0:
		_rng.randomize()
	else:
		_rng.seed = seed
	_build_lane()
	_build_field()
	_build_slalom(Vector3(30.0, 0.0, 100.0))
	_build_tunnel(Vector3(-30.0, 0.0, 60.0))
	_build_ramps()
	_build_wall_alley(Vector3(54.0, 0.0, 40.0))
	_build_boost_pads()


func _process(_delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for drop in _drops:
		var mesh := drop.get_child(1) as Node3D
		mesh.position.y = 0.15 * sin(t * 3.0 + drop.position.x * 0.5 + drop.position.z * 0.3)


# --- Pieces -----------------------------------------------------------------------------

func _material(color: Color) -> ShaderMaterial:
	if not _materials.has(color):
		var material := ShaderMaterial.new()
		material.shader = preload("res://shaders/obstacle.gdshader")
		material.set_shader_parameter("edge_color", color)
		_materials[color] = material
	return _materials[color]


## A solid Tron block; running into one head-on splats you. Part of the course unless
## `parent` says otherwise.
func _block(size: Vector3, center: Vector3, color: Color, yaw := 0.0, pitch := 0.0, parent: Node = null) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = center
	body.rotation = Vector3(pitch, yaw, 0.0)
	var shape := BoxShape3D.new()
	shape.size = size
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	var mesh := BoxMesh.new()
	mesh.size = size
	var view := MeshInstance3D.new()
	view.mesh = mesh
	view.material_override = _material(color)
	body.add_child(view)
	(parent if parent else _course).add_child(body)
	return body


func _drop(at: Vector3) -> void:
	var area := Area3D.new()
	area.position = at + Vector3.UP * 0.7
	var shape := SphereShape3D.new()
	shape.radius = 0.7
	var collider := CollisionShape3D.new()
	collider.shape = shape
	area.add_child(collider)
	var view := MeshInstance3D.new()
	view.mesh = _drop_mesh
	area.add_child(view)
	area.body_entered.connect(_on_drop_touched.bind(area))
	_course.add_child(area)
	_drops.append(area)


func _on_drop_touched(body: Node3D, drop: Area3D) -> void:
	if not body.has_method("collect_drop") or not drop.visible:
		return
	body.collect_drop()
	drop.visible = false
	drop.set_deferred("monitoring", false)
	# Comes back in a few seconds (its own timer, so a new course takes it away with the drop)
	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = 6.0
	timer.timeout.connect(func():
		drop.visible = true
		drop.monitoring = true
		timer.queue_free()
	)
	drop.add_child(timer)
	timer.start()


# --- Layout -----------------------------------------------------------------------------

func _build_floor() -> void:
	var body := StaticBody3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(HALF * 2.0 + 20.0, 2.0, HALF * 2.0 + 20.0)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position.y = -1.0
	body.add_child(collider)
	var plane := PlaneMesh.new()
	plane.size = Vector2(HALF * 2.0 + 20.0, HALF * 2.0 + 20.0)
	var view := MeshInstance3D.new()
	view.mesh = plane
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/grid_floor.gdshader")
	view.material_override = material
	body.add_child(view)
	add_child(body)

	# The practice lane's edges, glowing strips on the floor
	for side in [-1.0, 1.0]:
		var strip := MeshInstance3D.new()
		var strip_mesh := PlaneMesh.new()
		strip_mesh.size = Vector2(0.25, LANE_START - LANE_END + 30.0)
		strip.mesh = strip_mesh
		var glow := StandardMaterial3D.new()
		glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		glow.albedo_color = Color(0.6, 0.85, 1.0)
		strip.material_override = glow
		strip.position = Vector3(side * LANE_WIDTH * 0.5, 0.01, (LANE_START + LANE_END) * 0.5 + 10.0)
		add_child(strip)


func _build_boundary() -> void:
	for side in [-1.0, 1.0]:
		_block(Vector3(HALF * 2.0 + 2.0, 4.0, 1.0), Vector3(0.0, 2.0, side * HALF), WALL_COLOR, 0.0, 0.0, self)
		_block(Vector3(1.0, 4.0, HALF * 2.0 + 2.0), Vector3(side * HALF, 2.0, 0.0), WALL_COLOR, 0.0, 0.0, self)


func _build_lane() -> void:
	var z := LANE_START
	var last := ""
	while z > LANE_END:
		var kind: String = LANE_KINDS[_rng.randi() % LANE_KINDS.size()]
		while kind == last: # never the same thing twice running
			kind = LANE_KINDS[_rng.randi() % LANE_KINDS.size()]
		last = kind
		lane_plan.append({ z = z, kind = kind })
		match kind:
			"hurdle":
				_hurdle(z)
			"beam":
				_beam(z)
			"dodge_left": # the gap is on the left
				_block(Vector3(LANE_WIDTH * 2.0 / 3.0, 1.8, 0.6), Vector3(LANE_WIDTH / 6.0, 0.9, z), DODGE_COLOR)
			"dodge_right":
				_block(Vector3(LANE_WIDTH * 2.0 / 3.0, 1.8, 0.6), Vector3(-LANE_WIDTH / 6.0, 0.9, z), DODGE_COLOR)
			"hurdle_pair": # jump, land, jump
				_hurdle(z + 6.0)
				_hurdle(z - 6.0)
			"dodge_both": # middle blocked: either side
				_block(Vector3(LANE_WIDTH / 3.0, 1.8, 0.6), Vector3(0.0, 0.9, z), DODGE_COLOR)
		# A line of drops leading in to each obstacle
		for k in 3:
			_drop(Vector3(0.0, 0.0, z + 8.0 + k * 2.5))
		z -= _rng.randf_range(LANE_GAP.x, LANE_GAP.y)


func _hurdle(z: float) -> void:
	_block(Vector3(LANE_WIDTH, 0.8, 0.4), Vector3(0.0, 0.4, z), JUMP_COLOR)


func _beam(z: float) -> void:
	# Bottom edge at 0.8 m: you only fit under as a puddle
	_block(Vector3(LANE_WIDTH + 1.0, 0.5, 0.6), Vector3(0.0, 1.05, z), DUCK_COLOR)
	for side in [-1.0, 1.0]:
		_block(Vector3(0.4, 1.3, 0.4), Vector3(side * (LANE_WIDTH * 0.5 + 0.7), 0.65, z), DUCK_COLOR)


func _build_field() -> void:
	# Columns, slabs and walls, any size, any angle
	var placed := 0
	while placed < 110:
		var spot := Vector3(_rng.randf_range(-HALF + 8.0, HALF - 8.0), 0.0, _rng.randf_range(-HALF + 8.0, HALF - 8.0))
		# Keep the lane, the start, the slalom, the tunnel and the ramps clear
		if absf(spot.x) < LANE_WIDTH + 6.0 or spot.distance_to(start_position) < 25.0:
			continue
		if Rect2(20.0, 50.0, 20.0, 60.0).has_point(Vector2(spot.x, spot.z)):
			continue
		if Rect2(-40.0, 0.0, 20.0, 80.0).has_point(Vector2(spot.x, spot.z)):
			continue
		if Rect2(44.0, -25.0, 22.0, 75.0).has_point(Vector2(spot.x, spot.z)): # the wall-run alley
			continue
		if Rect2(-80.0, -100.0, 160.0, 40.0).has_point(Vector2(spot.x, spot.z)):
			continue
		var size: Vector3
		match _rng.randi() % 3:
			0: # a column
				var w := _rng.randf_range(1.0, 2.6)
				size = Vector3(w, _rng.randf_range(3.0, 9.0), w)
			1: # a wall
				size = Vector3(_rng.randf_range(5.0, 14.0), _rng.randf_range(1.8, 4.0), _rng.randf_range(0.6, 1.2))
			_: # a low slab to jump
				size = Vector3(_rng.randf_range(3.0, 7.0), _rng.randf_range(0.5, 0.8), _rng.randf_range(1.0, 3.0))
		var color := JUMP_COLOR if size.y < 1.0 else DODGE_COLOR
		_block(size, spot + Vector3.UP * size.y * 0.5, color, _rng.randf_range(0.0, PI))
		if _rng.randf() < 0.3:
			_drop(spot + Vector3(_rng.randf_range(-1.0, 1.0), 0.0, _rng.randf_range(-1.0, 1.0)).normalized() * (size.x * 0.5 + 2.5))
		placed += 1


func _build_slalom(at: Vector3) -> void:
	# Posts, alternating sides, a little off line each time
	for k in 8:
		var offset := (1.8 if k % 2 == 0 else -1.8) + _rng.randf_range(-0.4, 0.4)
		_block(Vector3(0.7, 1.4, 0.7), at + Vector3(offset, 0.7, -k * 6.0), DODGE_COLOR, PI / 4.0)
		_drop(at + Vector3(-offset, 0.0, -k * 6.0))


func _build_tunnel(at: Vector3) -> void:
	# A long low roof (20-30 m): duck in and stay a puddle (you can't stand up under it)
	var length := _rng.randf_range(20.0, 30.0)
	_block(Vector3(6.0, 0.5, length), at + Vector3(0.0, 1.05, -length * 0.5), DUCK_COLOR)
	for side in [-1.0, 1.0]:
		_block(Vector3(0.5, 1.3, length), at + Vector3(side * 3.25, 0.65, -length * 0.5), DUCK_COLOR)
	for k in int(length / 5.0):
		_drop(at + Vector3(0.0, -0.4, -3.0 - k * 5.0))


## Two tall green walls 9 m apart, 60 m long, for wall running (side-dodge into one), with drops
## along each, up where only a wall run reaches
func _build_wall_alley(at: Vector3) -> void:
	for side in [-1.0, 1.0]:
		_block(Vector3(0.6, 8.0, 60.0), at + Vector3(side * 4.8, 4.0, -30.0), Color(0.2, 1.0, 0.45))
		for k in 9:
			_drop(at + Vector3(side * 3.9, 1.9, -8.0 - k * 5.5))


func _build_boost_pads() -> void:
	# At the slalom's mouth, the tunnel's, and leading into the alley
	for spot in [Vector3(30.0, 0.0, 108.0), Vector3(-30.0, 0.0, 66.0), Vector3(54.0, 0.0, 48.0)]:
		var pad := preload("res://scripts/boost_pad.gd").new()
		pad.position = spot
		_course.add_child(pad)


func _build_ramps() -> void:
	# Kickers across the far end: run up and fly
	for k in 4:
		var x := -60.0 + k * 40.0
		var length := 10.0
		var angle := deg_to_rad(_rng.randf_range(12.0, 22.0))
		var center := Vector3(x, sin(angle) * length * 0.5 - 0.25, -80.0)
		_block(Vector3(6.0, 0.5, length), center, JUMP_COLOR, 0.0, angle)
		for j in 4:
			_drop(Vector3(x, 2.2 - j * 0.5, -87.0 - j * 2.0))
