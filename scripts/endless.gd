extends Node3D
## Endless mode's course: a lane of Tron obstacles running off to the horizon along -Z, built a
## chunk at a time ahead of the runner and cleared away behind. The obstacles come closer
## together the further you get (main.gd speeds the runner up too). Walls line the lane.
## Same obstacle kinds and colours as the test area's practice lane; lane_plan lists what's
## been laid, in order (the endless bot test reads it).

const WIDTH := 10.0 # between the walls
const CHUNK := 60.0 # metres built at a time
const AHEAD := 260.0 # built this far ahead of the runner
const BEHIND := 40.0 # and cleared once it's this far behind
const RUNWAY := 40.0 # clear lane at the start
const KINDS := ["hurdle", "beam", "dodge_left", "dodge_right", "dodge_both", "hurdle_pair"]
const GAP_EASY := 28.0 # metres between obstacles at the start...
const GAP_HARD := 18.0 # ...closing to this by HARD_AT metres in
const HARD_AT := 2500.0

const JUMP_COLOR := Color(1.0, 0.5, 0.1)
const DUCK_COLOR := Color(0.1, 0.85, 1.0)
const DODGE_COLOR := Color(1.0, 0.2, 0.75)
const WALL_COLOR := Color(0.45, 0.5, 0.6)

var start_position := Vector3(0.0, 0.0, 0.0)
var start_heading := 0.0
var runner: Node3D # who it builds ahead of
var lane_plan: Array = []

var _chunks: Array = [] # [{ end, node }], oldest first
var _built_to := 0.0 # z the course is built out to (it grows toward -Z)
var _next_obstacle := 0.0
var _last_kind := ""
var _rng := RandomNumberGenerator.new()
var _materials := {}
var _floor: StaticBody3D
var _drop_mesh := SphereMesh.new()


func _ready() -> void:
	_drop_mesh.radius = 0.28
	_drop_mesh.height = 0.56
	var drop_material := ShaderMaterial.new()
	drop_material.shader = preload("res://shaders/liquid_metal.gdshader")
	drop_material.set_shader_parameter("agitation", 0.6)
	_drop_mesh.material = drop_material
	_build_floor()
	generate()


## Start over: a fresh, random course from the start
func generate(seed := 0) -> void:
	for chunk in _chunks:
		chunk.node.queue_free()
	_chunks.clear()
	lane_plan.clear()
	if seed == 0:
		_rng.randomize()
	else:
		_rng.seed = seed
	_built_to = start_position.z + 20.0
	_next_obstacle = start_position.z - RUNWAY
	_last_kind = ""
	_extend()


## Metres run so far
func distance() -> float:
	return maxf(start_position.z - runner.global_position.z, 0.0) if runner else 0.0


func _physics_process(_delta: float) -> void:
	if runner == null:
		return
	_extend()
	# The floor goes along with the runner (its grid is drawn in world space, so it doesn't slide)
	_floor.global_position.z = snappedf(runner.global_position.z, 20.0)
	# Clear what's well behind
	while not _chunks.is_empty() and _chunks[0].end > runner.global_position.z + BEHIND:
		_chunks.pop_front().node.queue_free()


func _extend() -> void:
	var ahead_to := (runner.global_position.z if runner else start_position.z) - AHEAD
	while _built_to > ahead_to:
		_build_chunk(_built_to, _built_to - CHUNK)
		_built_to -= CHUNK


func _build_chunk(from: float, to: float) -> void:
	var node := Node3D.new()
	add_child(node)
	_chunks.append({ end = to, node = node })
	# Walls down both sides
	for side in [-1.0, 1.0]:
		# (tall enough to wall-run along)
		_block(node, Vector3(0.6, 4.5, CHUNK), Vector3(side * (WIDTH * 0.5 + 0.3), 2.25, (from + to) * 0.5), WALL_COLOR)
	# Obstacles, closer together the further in
	while _next_obstacle > to:
		var z := _next_obstacle
		var kind: String = KINDS[_rng.randi() % KINDS.size()]
		while kind == _last_kind:
			kind = KINDS[_rng.randi() % KINDS.size()]
		_last_kind = kind
		lane_plan.append({ z = z, kind = kind, half = _pair_half(z) })
		_obstacle(node, kind, z)
		for k in 3:
			_drop(node, Vector3(_rng.randf_range(-2.0, 2.0) if k == 0 else 0.0, 0.0, z + 8.0 + k * 2.5))
		var hard := clampf((start_position.z - z) / HARD_AT, 0.0, 1.0)
		var gap := lerpf(GAP_EASY, GAP_HARD, hard) * _rng.randf_range(0.9, 1.15)
		if kind == "hurdle_pair":
			gap += 10.0 # room to land off the second hurdle before the next thing
		_next_obstacle -= gap


## Half the distance between a hurdle pair's hurdles at this point in the run
func _pair_half(z: float) -> float:
	return lerpf(6.0, 9.5, clampf((start_position.z - z) / HARD_AT, 0.0, 1.0))


func _obstacle(node: Node3D, kind: String, z: float) -> void:
	match kind:
		"hurdle":
			_block(node, Vector3(WIDTH, 0.8, 0.4), Vector3(0.0, 0.4, z), JUMP_COLOR)
		"hurdle_pair": # jump, land, jump (further apart as it speeds up: a jump goes further)
			var half := _pair_half(z)
			_block(node, Vector3(WIDTH, 0.8, 0.4), Vector3(0.0, 0.4, z + half), JUMP_COLOR)
			_block(node, Vector3(WIDTH, 0.8, 0.4), Vector3(0.0, 0.4, z - half), JUMP_COLOR)
		"beam": # bottom at 0.8 m: only a puddle fits under
			_block(node, Vector3(WIDTH, 0.5, 0.6), Vector3(0.0, 1.05, z), DUCK_COLOR)
		"dodge_left": # the gap is on the left
			_block(node, Vector3(WIDTH * 0.62, 1.8, 0.6), Vector3(WIDTH * 0.19, 0.9, z), DODGE_COLOR)
		"dodge_right":
			_block(node, Vector3(WIDTH * 0.62, 1.8, 0.6), Vector3(-WIDTH * 0.19, 0.9, z), DODGE_COLOR)
		"dodge_both": # the middle blocked: either side
			_block(node, Vector3(WIDTH * 0.3, 1.8, 0.6), Vector3(0.0, 0.9, z), DODGE_COLOR)


# --- Pieces ------------------------------------------------------------------------------

func _material(color: Color) -> ShaderMaterial:
	if not _materials.has(color):
		var material := ShaderMaterial.new()
		material.shader = preload("res://shaders/obstacle.gdshader")
		material.set_shader_parameter("edge_color", color)
		_materials[color] = material
	return _materials[color]


func _block(node: Node3D, size: Vector3, center: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.position = center
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
	node.add_child(body)


func _drop(node: Node3D, at: Vector3) -> void:
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
	area.body_entered.connect(func(body: Node3D):
		if body.has_method("collect_drop") and area.visible:
			body.collect_drop()
			area.visible = false
			area.set_deferred("monitoring", false)
	)
	node.add_child(area)


func _build_floor() -> void:
	_floor = StaticBody3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(400.0, 2.0, 600.0)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position.y = -1.0
	_floor.add_child(collider)
	var plane := PlaneMesh.new()
	plane.size = Vector2(400.0, 600.0)
	var view := MeshInstance3D.new()
	view.mesh = plane
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/grid_floor.gdshader")
	view.material_override = material
	_floor.add_child(view)
	add_child(_floor)
	# The lane's edges, glowing strips along the foot of the walls
	for side in [-1.0, 1.0]:
		var strip := MeshInstance3D.new()
		var strip_mesh := PlaneMesh.new()
		strip_mesh.size = Vector2(0.25, 600.0)
		strip.mesh = strip_mesh
		var glow := StandardMaterial3D.new()
		glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		glow.albedo_color = Color(0.6, 0.85, 1.0)
		strip.material_override = glow
		strip.position = Vector3(side * WIDTH * 0.5, 0.012, 0.0)
		_floor.add_child(strip)
