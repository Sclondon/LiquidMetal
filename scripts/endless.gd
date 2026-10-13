extends Node3D
## Endless mode's course: the ring road round the Crystaliens' black sand moon (ring_world.gd
## draws the ring and the moon). A lane of crystal obstacles runs off along -Z on top of the ring,
## built a chunk at a time ahead of the runner and cleared away behind. The obstacles come closer
## together the further you get (main.gd speeds the runner up too). Walls line the lane.
## Same obstacle kinds and colours as the test area's practice lane; lane_plan lists what's
## been laid, in order (the endless bot test reads it).

const WIDTH := 10.0 # between the walls
const CHUNK := 60.0 # metres built at a time
const AHEAD := 260.0 # built this far ahead of the runner
const BEHIND := 40.0 # and cleared once it's this far behind
const RUNWAY := 40.0 # clear lane at the start
const KINDS := ["hurdle", "beam", "dodge_left", "dodge_right", "dodge_both", "hurdle_pair"]
# Deeper zones add more: zone 2 zigzags, zone 3 tunnels (slide the length of them), zone 4 pillars
const ZONE_KINDS := [[], ["zigzag"], ["tunnel"], ["pillars"]]
const ZONE_LENGTH := 500.0
## Each zone's look: name, sky overhead, horizon glow, fog, the floor grid's lines
const ZONES := [
	# (out in space: black overhead, a thin glow along the horizon, fog that fades to the dark;
	# lines: the zone's crystal colour, on the kerbs, the sand's glints and the moon's fields)
	{ name = "AMETHYST REACH", top = Color(0.012, 0.008, 0.03), horizon = Color(0.6, 0.35, 1.0), fog = Color(0.03, 0.02, 0.07), lines = Color(0.65, 0.4, 1.0), space = 1.0 },
	{ name = "EMERALD DRIFT", top = Color(0.006, 0.02, 0.016), horizon = Color(0.35, 1.0, 0.55), fog = Color(0.015, 0.05, 0.03), lines = Color(0.35, 1.0, 0.55), space = 1.0 },
	{ name = "ICE ARC", top = Color(0.006, 0.014, 0.03), horizon = Color(0.55, 0.85, 1.0), fog = Color(0.02, 0.04, 0.07), lines = Color(0.5, 0.9, 1.0), space = 1.0 },
	{ name = "EMBER ARC", top = Color(0.03, 0.008, 0.006), horizon = Color(1.0, 0.5, 0.2), fog = Color(0.07, 0.025, 0.015), lines = Color(1.0, 0.5, 0.2), space = 1.0 },
	{ name = "THE DARK SIDE", top = Color(0.004, 0.0, 0.012), horizon = Color(0.8, 0.3, 0.9), fog = Color(0.03, 0.01, 0.05), lines = Color(0.9, 0.35, 0.8), space = 1.0 },
]

signal zone_changed(index: int, zone: Dictionary)

var zone := 0
var _floor_material: ShaderMaterial
const GAP_EASY := 28.0 # metres between obstacles at the start...
const GAP_HARD := 18.0 # ...closing to this by HARD_AT metres in
const HARD_AT := 2500.0
const TUNNEL := 10.0 # metres of low roof
const KERB := 1.1 # how high the lane's ordinary walls are drawn

const JUMP_COLOR := Color(1.0, 0.65, 0.25)
const DUCK_COLOR := Color(0.45, 0.85, 1.0)
const DODGE_COLOR := Color(1.0, 0.4, 0.65)
const WALL_COLOR := Color(0.4, 0.45, 0.6)
const WALL_RUN_COLOR := Color(0.3, 0.95, 0.6) # the tall walls made for running on
const BoostPad := preload("res://scripts/boost_pad.gd")
const RingWorld := preload("res://scripts/ring_world.gd")
const Crystal := preload("res://scripts/crystal.gd")
const Runner := preload("res://scripts/player.gd")
const AiInput := preload("res://scripts/ai_input.gd")
const Difficulty := preload("res://scripts/difficulty.gd")

## Enemy runners on the lane (main turns them off for some tests)
var with_enemies := true
var enemies: Array = []

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
var _ring: Node3D # the ring road and the moon (ring_world.gd)
var _scenery_meshes: Array[ArrayMesh] = []
var _looks := RandomNumberGenerator.new() # (the scenery's own dice: the course's stay as they were)
var _drop_mesh := SphereMesh.new()


func _ready() -> void:
	_drop_mesh.radius = 0.28
	_drop_mesh.height = 0.56
	var drop_material := ShaderMaterial.new()
	drop_material.shader = preload("res://shaders/liquid_metal.gdshader")
	drop_material.set_shader_parameter("agitation", 0.6)
	_drop_mesh.material = drop_material
	for k in 4:
		_scenery_meshes.append(Crystal.shard(1.0, 3.0 + k * 1.5, 0.35 + 0.1 * k))
	_ring = RingWorld.new()
	add_child(_ring)
	_build_floor()
	generate()


## Start over: a fresh, random course from the start
func generate(seed := 0) -> void:
	for chunk in _chunks:
		chunk.node.queue_free()
	_chunks.clear()
	lane_plan.clear()
	zone = 0
	_ring.set_color(ZONES[0].lines)
	if seed == 0:
		_rng.randomize()
	else:
		_rng.seed = seed
	for enemy in enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	enemies.clear()
	_built_to = start_position.z + 20.0
	_next_obstacle = start_position.z - RUNWAY
	_last_kind = ""
	_extend()


## Metres run so far
func distance() -> float:
	return maxf(start_position.z - runner.global_position.z, 0.0) if runner else 0.0


func _physics_process(_delta: float) -> void:
	if runner:
		var now := int(distance() / ZONE_LENGTH)
		if now != zone:
			zone = now
			var look: Dictionary = ZONES[zone % ZONES.size()]
			_ring.set_color(look.lines)
			zone_changed.emit(zone, look)
	if runner and with_enemies and distance() > 60.0 and enemies.size() < int(Difficulty.tier().endless_enemies) and _rng.randf() < _delta * float(Difficulty.tier().endless_rate):
		_spawn_enemy(runner.global_position.z + _rng.randf_range(22.0, 34.0)) # behind him: they chase
	if runner == null:
		return
	_extend()
	# The floor goes along with the runner (its grid is drawn in world space, so it doesn't slide)
	_floor.global_position.z = snappedf(runner.global_position.z, 20.0)
	_ring.follow(runner.global_position.z)
	# Enemies: gone once well behind (or a while after blowing up); a new one now and then ahead
	for i in range(enemies.size() - 1, -1, -1):
		var enemy = enemies[i]
		if not is_instance_valid(enemy) or enemy.global_position.z > runner.global_position.z + BEHIND or (enemy.dead and enemy.get_meta("dead_for", 0.0) > 4.0):
			if is_instance_valid(enemy):
				enemy.queue_free()
			enemies.remove_at(i)
		elif enemy.dead:
			enemy.set_meta("dead_for", enemy.get_meta("dead_for", 0.0) + _delta)
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
	# Crystals growing out of the sand either side of the lane
	var crystal_color: Color = ZONES[int(maxf(start_position.z - from, 0.0) / ZONE_LENGTH) % ZONES.size()].lines
	for k in 7:
		var crystal := MeshInstance3D.new()
		crystal.mesh = _scenery_meshes[_looks.randi() % _scenery_meshes.size()]
		var side := -1.0 if k % 2 == 0 else 1.0
		var grown := _looks.randf_range(0.6, 2.2)
		crystal.position = Vector3(side * _looks.randf_range(9.0, 36.0), grown * 0.8, _looks.randf_range(to, from))
		crystal.rotation = Vector3(_looks.randf_range(-0.35, 0.35), _looks.randf() * TAU, _looks.randf_range(-0.35, 0.35))
		crystal.scale = Vector3.ONE * grown
		crystal.material_override = _crystal_material(crystal_color.lerp(Color.WHITE, _looks.randf() * 0.3))
		crystal.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(crystal)
	# Walls down both sides (tall enough to wall-run along); now and then a stretch of taller,
	# green ones, made for it, with a line of drops along one up where only a wall run reaches
	var tall := from < start_position.z - RUNWAY and _rng.randf() < 0.35
	for side in [-1.0, 1.0]:
		var height := 8.0 if tall else 4.5
		# (the ordinary ones are only a low kerb of crystal to look at, so the moon and the ring show
		# over them; they still hold him in the lane as high as before)
		_block(node, Vector3(0.6, height, CHUNK), Vector3(side * (WIDTH * 0.5 + 0.3), height * 0.5, (from + to) * 0.5), WALL_RUN_COLOR if tall else WALL_COLOR, height if tall else KERB)
	if tall:
		var side := -1.0 if _rng.randf() < 0.5 else 1.0
		for k in 8:
			_drop(node, Vector3(side * (WIDTH * 0.5 - 0.6), 1.9, from - 8.0 - k * 5.0))
	# Obstacles, closer together the further in
	while _next_obstacle > to:
		var z := _next_obstacle
		var kinds := KINDS.duplicate()
		var zone_here := int((start_position.z - z) / ZONE_LENGTH)
		for k in mini(zone_here + 1, ZONE_KINDS.size()):
			kinds.append_array(ZONE_KINDS[k])
			kinds.append_array(ZONE_KINDS[k]) # (the new ones come up a bit more)
		var kind: String = kinds[_rng.randi() % kinds.size()]
		while kind == _last_kind:
			kind = kinds[_rng.randi() % kinds.size()]
		_last_kind = kind
		var extra := 0.0
		if kind == "zigzag": # a dodge one way, then the other
			lane_plan.append({ z = z, kind = "dodge_left", half = 0.0 })
			lane_plan.append({ z = z - 14.0, kind = "dodge_right", half = 0.0 })
			_obstacle(node, "dodge_left", z)
			_obstacle(node, "dodge_right", z - 14.0)
			extra = 14.0
		else:
			lane_plan.append({ z = z, kind = kind, half = _pair_half(z) })
			_obstacle(node, kind, z)
			if kind == "tunnel":
				extra = TUNNEL
		for k in 3:
			_drop(node, Vector3(_rng.randf_range(-2.0, 2.0) if k == 0 else 0.0, 0.0, z + 8.0 + k * 2.5))
		# Now and then a boost pad, just past the obstacle
		if _rng.randf() < 0.22:
			var pad := BoostPad.new()
			pad.position = Vector3(_rng.randf_range(-2.5, 2.5), 0.0, z - 5.0)
			node.add_child(pad)
		var hard := clampf((start_position.z - z) / HARD_AT, 0.0, 1.0)
		var gap := lerpf(GAP_EASY, GAP_HARD, hard) * float(Difficulty.tier().gap_scale) * _rng.randf_range(0.9, 1.15)
		if kind == "hurdle_pair":
			gap += 10.0
		gap += 4.0 + extra # (room for a boost to settle; and past a long one) # room to land off the second hurdle before the next thing
		_next_obstacle -= gap


## Half the distance between a hurdle pair's hurdles at this point in the run
func _pair_half(z: float) -> float:
	return lerpf(6.0, 9.5, clampf((start_position.z - z) / HARD_AT, 0.0, 1.0))


## An enemy runner: the player's own runner with an AI at the controls
func _spawn_enemy(z: float) -> void:
	# Never on top of an obstacle: nudged on until it's 8 m clear of them all
	for tries in 12:
		var clear := true
		for o in lane_plan:
			var half: float = 6.0 if o.kind == "hurdle_pair" else 0.0
			if absf(z - o.z) < 8.0 + half:
				clear = false
		for other in enemies:
			if is_instance_valid(other) and absf(other.global_position.z - z) < 12.0:
				clear = false
		if clear:
			break
		z += 6.0 # (further back: they spawn behind him)
	if runner and z - runner.global_position.z < 15.0:
		return # (never right on top of him)
	var ai := AiInput.new()
	ai.course = self
	ai.target = runner
	var enemy := Runner.new()
	enemy.input = ai
	enemy.add_child(ai)
	add_child(enemy)
	ai.body = enemy
	enemy.make_enemy()
	enemy.place(Vector3(_rng.randf_range(-2.0, 2.0), 0.0, z), 0.0)
	enemy.run_speed = runner.run_speed * float(Difficulty.tier().chase) if runner else 9.0
	enemy.speed = enemy.run_speed
	enemies.append(enemy)


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
		"tunnel": # a low roof to slide the length of (from z on)
			_block(node, Vector3(WIDTH, 0.5, TUNNEL), Vector3(0.0, 1.05, z - TUNNEL * 0.5), DUCK_COLOR)
		"pillars": # two tall pillars: through the middle (or squeeze down a side)
			for side in [-1.0, 1.0]:
				_block(node, Vector3(2.4, 5.0, 1.0), Vector3(side * 2.95, 2.5, z), DODGE_COLOR) # (a 3.5 m gap between)
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


func _crystal_material(color: Color) -> ShaderMaterial:
	var key := "crystal %s" % color.to_html()
	if not _materials.has(key):
		var material := ShaderMaterial.new()
		material.shader = preload("res://shaders/crystal.gdshader")
		material.set_shader_parameter("horizon", color)
		material.set_shader_parameter("sky_top", color.darkened(0.7))
		_materials[key] = material
	return _materials[key]


## seen: how much of its height is drawn, from the ground up (0: all of it)
func _block(node: Node3D, size: Vector3, center: Vector3, color: Color, seen := 0.0) -> void:
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
	if seen > 0.0 and seen < size.y:
		mesh.size.y = seen
		view.position.y = (seen - size.y) * 0.5
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
	material.shader = preload("res://shaders/black_sand.gdshader")
	view.material_override = material
	_floor_material = material
	view.visible = false # (the ring road draws the ground: ring_world.gd)
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
		strip.visible = false
		_floor.add_child(strip)
