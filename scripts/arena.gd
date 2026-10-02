extends Node3D
## Arena battle: a square floor walled in by tall green walls (made for wall running), with a few
## blocks for cover, low slabs to jump, and boost pads. Enemy runners come in waves from the edges
## and chase him; he has to keep moving and dash through them. Wave n sends n + 1 of them (up to
## MAX_AT_ONCE at a time). main.gd keeps the score and shows the banners; this builds the arena and
## runs the waves.

signal wave_started(wave: int)
signal wave_cleared(wave: int)

const HALF := 45.0 # a 90 m square
const WALL_COLOR := Color(0.2, 1.0, 0.45)
const BLOCK_COLOR := Color(1.0, 0.2, 0.75)
const SLAB_COLOR := Color(1.0, 0.5, 0.1)
const MAX_AT_ONCE := 6
const Runner := preload("res://scripts/player.gd")
const AiInput := preload("res://scripts/ai_input.gd")
const BoostPad := preload("res://scripts/boost_pad.gd")

var start_position := Vector3(0.0, 0.0, 30.0)
var start_heading := 0.0
var runner: CharacterBody3D
var with_enemies := true
var lane_plan: Array = [] # (no lane here: the enemies feel their way)
var enemies: Array = []
var wave := 0

var _to_send := 0 # this wave's enemies still to come in
var _send_clock := 0.0
var _between := 0.0 # the pause between waves
var _fighting := false
var _course: Node3D
var _materials := {}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_build_floor()
	generate()


func generate(seed := 0) -> void:
	if _course:
		_course.queue_free()
	for enemy in enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	enemies.clear()
	wave = 0
	_to_send = 0
	_fighting = false
	_between = 1.5
	_course = Node3D.new()
	add_child(_course)
	if seed == 0:
		_rng.randomize()
	else:
		_rng.seed = seed
	# The walls: tall, green, for running along
	for side in [-1.0, 1.0]:
		_block(Vector3(HALF * 2.0 + 1.2, 8.0, 0.6), Vector3(0.0, 4.0, side * (HALF + 0.3)), WALL_COLOR)
		_block(Vector3(0.6, 8.0, HALF * 2.0 + 1.2), Vector3(side * (HALF + 0.3), 4.0, 0.0), WALL_COLOR)
	# Cover and things to jump, scattered (clear of the middle, where he starts)
	var placed := 0
	while placed < 14:
		var spot := Vector3(_rng.randf_range(-HALF + 8.0, HALF - 8.0), 0.0, _rng.randf_range(-HALF + 8.0, HALF - 8.0))
		if spot.distance_to(start_position) < 14.0:
			continue
		if placed % 2 == 0:
			var size := Vector3(_rng.randf_range(2.0, 5.0), _rng.randf_range(2.5, 5.0), _rng.randf_range(2.0, 5.0))
			_block(size, spot + Vector3.UP * size.y * 0.5, BLOCK_COLOR, _rng.randf_range(0.0, PI))
		else:
			var size := Vector3(_rng.randf_range(4.0, 8.0), 0.7, _rng.randf_range(1.0, 2.0))
			_block(size, spot + Vector3.UP * 0.35, SLAB_COLOR, _rng.randf_range(0.0, PI))
		placed += 1
	for k in 4:
		var pad := BoostPad.new()
		var angle := k * TAU / 4.0 + PI / 4.0
		pad.position = Vector3(cos(angle), 0.0, sin(angle)) * HALF * 0.55
		pad.rotation.y = -angle + PI / 2.0 # (boosting round the arena)
		_course.add_child(pad)


func _physics_process(delta: float) -> void:
	if runner == null or not with_enemies or runner.dead:
		return
	for i in range(enemies.size() - 1, -1, -1):
		var enemy = enemies[i]
		if not is_instance_valid(enemy):
			enemies.remove_at(i)
		elif enemy.dead:
			enemy.set_meta("dead_for", enemy.get_meta("dead_for", 0.0) + delta)
			if enemy.get_meta("dead_for") > 4.0:
				enemy.queue_free()
				enemies.remove_at(i)
	var alive := enemies.filter(func(e): return is_instance_valid(e) and not e.dead).size()
	# Between waves: a breather, then the next one
	if _fighting and _to_send == 0 and alive == 0:
		_fighting = false
		wave_cleared.emit(wave)
		_between = 2.5
	if not _fighting:
		_between -= delta
		if _between <= 0.0:
			wave += 1
			_to_send = mini(wave + 1, 16)
			_fighting = true
			wave_started.emit(wave)
		return
	# Sending this wave in, a few at a time
	_send_clock -= delta
	if _to_send > 0 and alive < MAX_AT_ONCE and _send_clock <= 0.0:
		if _spawn_enemy():
			_to_send -= 1
			_send_clock = 0.8


## One in from near a wall, as far from him as it can find, facing in
func _spawn_enemy() -> bool:
	var space := get_world_3d().direct_space_state
	var probe := SphereShape3D.new()
	probe.radius = 0.8
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = probe
	query.collision_mask = 1 | 2
	query.exclude = [runner.get_rid()]
	for tries in 12:
		var angle := _rng.randf() * TAU
		var spot := Vector3(cos(angle), 0.0, sin(angle)) * (HALF - 5.0)
		spot.x = clampf(spot.x, -HALF + 4.0, HALF - 4.0)
		spot.z = clampf(spot.z, -HALF + 4.0, HALF - 4.0)
		if spot.distance_to(runner.global_position) < 25.0:
			continue
		query.transform = Transform3D(Basis.IDENTITY, spot + Vector3.UP * 1.2)
		if not space.intersect_shape(query, 1).is_empty():
			continue
		var ai := AiInput.new()
		ai.course = self
		ai.target = runner
		ai.always_chase = true
		var enemy := Runner.new()
		enemy.input = ai
		enemy.add_child(ai)
		add_child(enemy)
		ai.body = enemy
		enemy.make_enemy()
		var inward := -spot
		enemy.place(spot, atan2(-inward.x, -inward.z))
		enemy.run_speed = runner.run_speed * 1.2
		enemy.speed = enemy.run_speed * 0.5
		enemies.append(enemy)
		return true
	return false


func alive_count() -> int:
	return enemies.filter(func(e): return is_instance_valid(e) and not e.dead).size() + _to_send


# --- Pieces ------------------------------------------------------------------------------

func _material(color: Color) -> ShaderMaterial:
	if not _materials.has(color):
		var material := ShaderMaterial.new()
		material.shader = preload("res://shaders/obstacle.gdshader")
		material.set_shader_parameter("edge_color", color)
		_materials[color] = material
	return _materials[color]


func _block(size: Vector3, center: Vector3, color: Color, yaw := 0.0) -> void:
	var body := StaticBody3D.new()
	body.position = center
	body.rotation.y = yaw
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
	_course.add_child(body)


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
	material.set_shader_parameter("line_color", Color(0.2, 1.0, 0.5))
	view.material_override = material
	body.add_child(view)
	add_child(body)
