extends Node3D
## The Crystaliens' colosseum on their black sand moon: a round floor of black sand inside a tall
## wall (for running along), banked stands behind it full of Crystaliens watching, and a ring of
## great crystals round the top that light it. arena.gd builds one and asks it for the floor each
## round (flat, or with a pit in the middle); `cheer()` gets the crowd on its feet.
## The sand is the shared sand component (GameCommon godot/sand: sand_ground.gd), black, drawn
## as a disc; it takes the runners' furrows (`ground.trail`). What they stand on is this script's.

const Crystal := preload("res://scripts/crystal.gd")
const WALL_HEIGHT := 8.0
const WALL_COLOR := Color(0.45, 0.8, 1.0)
const STONE_COLOR := Color(0.5, 0.25, 0.9)
const TIERS := 6
const TIER_DEPTH := 2.4
const TIER_RISE := 1.5
const SEGMENTS := 72 # round the wall
const PIT_DEPTH := 14.0

var radius := 70.0

var _floor: Node3D
## The sand itself (a SandGround, only drawn: the floor's collider is made here)
var ground: SandGround
var _crowd_material := ShaderMaterial.new()
var _cheer := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 7
	_build_sand()
	_build_wall()
	_build_stands()
	_build_crowd()
	_build_spires()
	set_floor(0.0)


func _process(delta: float) -> void:
	if _cheer > 0.0:
		_cheer = maxf(_cheer - delta * 0.7, 0.0)
		_crowd_material.set_shader_parameter("cheer", _cheer)


## The crowd jumps up (someone's been burst, a round's been won)
func cheer(amount := 1.0) -> void:
	_cheer = maxf(_cheer, amount)


## The floor: black sand out to the wall, with a round pit in the middle if `pit` (its radius) > 0
func set_floor(pit: float) -> void:
	if _floor:
		_floor.free()
	_floor = Node3D.new()
	add_child(_floor)
	var out := radius + 1.0
	var body := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	ground.ring = Vector2(pit, out) # (the sand's drawn as a disc, or a ring round the pit)
	if pit <= 0.0:
		var shape := CylinderShape3D.new()
		shape.radius = out
		shape.height = 2.0
		collider.shape = shape
		collider.position.y = -1.0
	else:
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(_ring_mesh(pit, out).get_faces())
		shape.backface_collision = true
		collider.shape = shape
		_build_pit(pit)
	body.add_child(collider)
	_floor.add_child(body)


## Black sand, level, out to the wall: coarse furrows (wide and cheap, for things that run fast)
## that fill back in over half a minute, pale dust thrown up, and grains that glint violet
func _build_sand() -> void:
	ground = SandGround.new()
	ground.half = Vector2(radius + 1.0, radius + 1.0)
	ground.cell = 2.0
	ground.solid = false
	ground.colour = Sand.BLACK
	ground.paint(Sand.Kind.BLACK, Vector2.ZERO, radius * 3.0)
	ground.dent_cell = 0.15
	ground.fill_seconds = Vector2(30.0, 6.0)
	ground.spray_colour = Color(0.45, 0.42, 0.55, 0.8)
	ground.beyond = 0.0
	ground.apron = 0.0
	ground.apron_roll = 0.0
	ground.clip = true
	add_child(ground)
	ground.build()
	var sand := ground.material()
	sand.set_shader_parameter(&"sparkle", 3.0)
	sand.set_shader_parameter(&"sparkle_aim", 0.965)
	sand.set_shader_parameter(&"glint", Color(0.75, 0.6, 1.0))


## A flat ring (or disc, from 0) of floor, in bands so the sand's shading has vertices to work with
func _ring_mesh(from: float, to: float) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_normal(Vector3.UP)
	var bands := 6
	for band in bands:
		var inner := lerpf(from, to, float(band) / bands)
		var outer := lerpf(from, to, float(band + 1) / bands)
		for k in SEGMENTS:
			var a := k * TAU / SEGMENTS
			var b := (k + 1) * TAU / SEGMENTS
			var ia := Vector3(cos(a) * inner, 0.0, sin(a) * inner)
			var ib := Vector3(cos(b) * inner, 0.0, sin(b) * inner)
			var oa := Vector3(cos(a) * outer, 0.0, sin(a) * outer)
			var ob := Vector3(cos(b) * outer, 0.0, sin(b) * outer)
			# (clockwise seen from above)
			for corner in [ia, oa, ob, ia, ob, ib]:
				tool.add_vertex(corner)
	return tool.commit()


## The pit: its sides going down into the dark, a glow far below, and a bright lip to see it by
func _build_pit(pit: float) -> void:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in SEGMENTS:
		var a := k * TAU / SEGMENTS
		var b := (k + 1) * TAU / SEGMENTS
		var top_a := Vector3(cos(a) * pit, 0.0, sin(a) * pit)
		var top_b := Vector3(cos(b) * pit, 0.0, sin(b) * pit)
		var down := Vector3.DOWN * PIT_DEPTH
		# (facing in, toward the middle)
		tool.set_color(Color(1, 1, 1, 0.0))
		tool.add_vertex(top_a)
		tool.add_vertex(top_b)
		tool.set_color(Color(1, 1, 1, 1.0))
		tool.add_vertex(top_b + down)
		tool.set_color(Color(1, 1, 1, 0.0))
		tool.add_vertex(top_a)
		tool.set_color(Color(1, 1, 1, 1.0))
		tool.add_vertex(top_b + down)
		tool.add_vertex(top_a + down)
	var sides := MeshInstance3D.new()
	sides.mesh = tool.commit()
	# (vertex alpha: 0 at the lip, 1 at the bottom; used as brightness, the pit glowing from below)
	_floor.add_child(sides)
	var shade := ShaderMaterial.new()
	shade.shader = preload("res://shaders/pit.gdshader")
	sides.material_override = shade
	var glow := MeshInstance3D.new()
	glow.mesh = _ring_mesh(0.0, pit)
	glow.position.y = -PIT_DEPTH
	var hot := StandardMaterial3D.new()
	hot.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hot.albedo_color = Color(0.9, 0.5, 1.0)
	glow.material_override = hot
	_floor.add_child(glow)
	# The lip
	var lip := MeshInstance3D.new()
	lip.mesh = _ring_mesh(pit, pit + 0.35)
	lip.position.y = 0.02
	var bright := StandardMaterial3D.new()
	bright.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bright.albedo_color = Color(0.85, 0.45, 1.0)
	lip.material_override = bright
	_floor.add_child(lip)


func _edge_material(color: Color) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/obstacle.gdshader")
	material.set_shader_parameter("edge_color", color)
	material.set_shader_parameter("glow", 0.55)
	material.set_shader_parameter("grid_size", 1.4)
	return material


## The wall round the floor: tall, for running along (straight lengths, so the runner's wall run
## has flat faces to hold)
func _build_wall() -> void:
	var length := TAU * (radius + 0.4) / SEGMENTS + 0.12
	var size := Vector3(length, WALL_HEIGHT, 0.8)
	var mesh := BoxMesh.new()
	mesh.size = size
	var shape := BoxShape3D.new()
	shape.size = size
	var material := _edge_material(WALL_COLOR)
	for k in SEGMENTS:
		var angle := (k + 0.5) * TAU / SEGMENTS
		var body := StaticBody3D.new()
		body.position = Vector3(cos(angle), 0.0, sin(angle)) * (radius + 0.4) + Vector3.UP * WALL_HEIGHT * 0.5
		body.rotation.y = -angle + PI / 2.0
		var collider := CollisionShape3D.new()
		collider.shape = shape
		body.add_child(collider)
		var view := MeshInstance3D.new()
		view.mesh = mesh
		view.material_override = material
		body.add_child(view)
		add_child(body)
	# Points of crystal standing up along the top of it
	var tips := MultiMesh.new()
	tips.transform_format = MultiMesh.TRANSFORM_3D
	tips.mesh = Crystal.shard(0.55, 3.2, 0.3)
	tips.instance_count = SEGMENTS * 2
	for k in tips.instance_count:
		var angle := (k + 0.5) * TAU / tips.instance_count
		var tall := _rng.randf_range(0.6, 1.4)
		var lean := Basis(Vector3.UP, _rng.randf() * TAU) * Basis(Vector3.RIGHT, _rng.randf_range(-0.2, 0.2))
		tips.set_instance_transform(k, Transform3D(lean.scaled(Vector3(1.0, tall, 1.0)), Vector3(cos(angle), 0.0, sin(angle)) * (radius + 0.4) + Vector3.UP * (WALL_HEIGHT + 0.5 * tall)))
	var tips_view := MultiMeshInstance3D.new()
	tips_view.multimesh = tips
	var tip_material := ShaderMaterial.new()
	tip_material.shader = preload("res://shaders/crystal.gdshader")
	tip_material.set_shader_parameter("horizon", WALL_COLOR)
	tips_view.material_override = tip_material
	add_child(tips_view)


## The stands: steps going up and back from the top of the wall, turned round the arena as one mesh
func _build_stands() -> void:
	var profile: Array[Vector2] = [] # (how far out, how high)
	var out := radius + 0.8
	var up := WALL_HEIGHT
	profile.append(Vector2(out, up))
	for tier in TIERS:
		out += TIER_DEPTH
		profile.append(Vector2(out, up))
		up += TIER_RISE
		profile.append(Vector2(out, up))
	out += 1.5
	profile.append(Vector2(out, up))
	profile.append(Vector2(out, up + 5.0)) # the back wall
	profile.append(Vector2(out + 3.0, up + 5.0))
	profile.append(Vector2(out + 3.0, -2.0))
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_smooth_group(-1)
	for k in SEGMENTS:
		var a := k * TAU / SEGMENTS
		var b := (k + 1) * TAU / SEGMENTS
		for p in profile.size() - 1:
			var p0 := profile[p]
			var p1 := profile[p + 1]
			var a0 := Vector3(cos(a) * p0.x, p0.y, sin(a) * p0.x)
			var b0 := Vector3(cos(b) * p0.x, p0.y, sin(b) * p0.x)
			var a1 := Vector3(cos(a) * p1.x, p1.y, sin(a) * p1.x)
			var b1 := Vector3(cos(b) * p1.x, p1.y, sin(b) * p1.x)
			for corner in [a0, b1, a1, a0, b0, b1]:
				tool.add_vertex(corner)
	tool.generate_normals()
	var view := MeshInstance3D.new()
	view.mesh = tool.commit()
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.05, 0.045, 0.07)
	stone.roughness = 0.6
	stone.cull_mode = BaseMaterial3D.CULL_DISABLED
	view.material_override = stone
	add_child(view)


## The crowd: a Crystalien every couple of metres along every step, one multimesh
func _build_crowd() -> void:
	var places: Array[Transform3D] = []
	for tier in TIERS:
		var out := radius + 0.8 + tier * TIER_DEPTH + TIER_DEPTH * 0.55
		var up := WALL_HEIGHT + tier * TIER_RISE
		var count := int(TAU * out / 2.1)
		for k in count:
			if _rng.randf() < 0.12:
				continue # (an empty seat here and there)
			var angle := (k + _rng.randf_range(-0.2, 0.2)) * TAU / count
			var size := _rng.randf_range(0.85, 1.25)
			# (facing the middle)
			var facing := Basis(Vector3.UP, -angle + PI / 2.0 + _rng.randf_range(-0.25, 0.25)).scaled(Vector3.ONE * size)
			places.append(Transform3D(facing, Vector3(cos(angle) * out, up, sin(angle) * out)))
	var crowd := MultiMesh.new()
	crowd.transform_format = MultiMesh.TRANSFORM_3D
	crowd.use_colors = true
	crowd.use_custom_data = true
	crowd.mesh = Crystal.spectator()
	crowd.instance_count = places.size()
	for i in places.size():
		crowd.set_instance_transform(i, places[i])
		crowd.set_instance_color(i, Crystal.COLORS[_rng.randi() % Crystal.COLORS.size()].lerp(Color.WHITE, _rng.randf() * 0.2))
		crowd.set_instance_custom_data(i, Color(_rng.randf(), _rng.randf(), 0.0, 0.0))
	_crowd_material.shader = preload("res://shaders/crowd.gdshader")
	var view := MultiMeshInstance3D.new()
	view.multimesh = crowd
	view.material_override = _crowd_material
	view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(view)


## Great crystals standing round the top of the stands, lit from inside
func _build_spires() -> void:
	var out := radius + 0.8 + TIERS * TIER_DEPTH + 3.0
	var up := WALL_HEIGHT + TIERS * TIER_RISE + 5.0
	var count := 24
	for k in count:
		var angle := k * TAU / count
		var height := 16.0 if k % 2 == 0 else 10.0
		var spire := MeshInstance3D.new()
		spire.mesh = Crystal.shard(1.6 if k % 2 == 0 else 1.1, height, 0.5)
		spire.position = Vector3(cos(angle) * out, up + height * 0.35, sin(angle) * out)
		spire.rotation = Vector3(_rng.randf_range(-0.12, 0.12), _rng.randf() * TAU, _rng.randf_range(-0.12, 0.12))
		var material := ShaderMaterial.new()
		material.shader = preload("res://shaders/crystal.gdshader")
		material.set_shader_parameter("horizon", Crystal.COLORS[k % Crystal.COLORS.size()])
		spire.material_override = material
		spire.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(spire)
