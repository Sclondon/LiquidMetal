extends MeshInstance3D
## The wall a dash leaves behind it, along the line of the dash (the way a light cycle leaves a
## wall). Anybody else who runs into it while it stands is burst (the arena, and the runner for
## its chasers, ask `hits`). World space. The runner calls `extend` every step of a dash and
## `stop` when it's over.
## - Mercury's: a thin, smooth blade of his own metal. It runs up out of the ground behind him,
##   stands a moment, then lets go: it collapses into blobs of goo that drop, splat and are gone.
##   The line is drawn as one curve through the points it was laid along, so a dash on the turn
##   leaves a bend, not corners.
## - A Crystalien's (`crystal`): a row of tall crystals that shoot up one after another along
##   the line, stand, and draw back down into the ground.

const Crystal := preload("res://scripts/crystal.gd")
const LIFE := 1.7 # seconds a length of it stands
const RISE := 0.12 # ...of which this getting up
const SINK := 0.22 # ...and this going (the blade letting go; crystals take twice as long drawing down)
const STEP := 0.45 # metres between the points it's laid along
const THICK := 0.06 # how thick the blade is at its foot (it comes to an edge at the top)
const FINE := 4 # lengths drawn between each two points, along the curve through them
const TALLER := 1.15 # a Crystalien's crystals stand this much taller than Mercury's blade
const ROOTED := 0.32 # how much of a crystal's length is under the ground (its lower point never shows)
const MOST := 120 # crystals standing at once
const GRAVITY := 20.0

var material: Material
## How tall it stands (the runner's size scales it)
var height := 2.0
## A Crystalien's: a row of crystals, not a blade of metal (set before it's in the tree)
var crystal := false

var _runs: Array = [] # each dash's wall: an Array of { pos, age, turn, size, let_go }
var _open := false
var _mesh := ImmediateMesh.new()
var _row: MultiMesh
var _blob := SphereMesh.new()
var _blobs: Array = [] # goo on its way down: { node, velocity, floor, down }


func _ready() -> void:
	top_level = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	extra_cull_margin = 400.0
	if crystal:
		_row = MultiMesh.new()
		_row.transform_format = MultiMesh.TRANSFORM_3D
		_row.mesh = Crystal.shard(0.5, 1.0, 0.5, 6) # (one metre tall: stretched to what's wanted)
		_row.instance_count = MOST
		_row.visible_instance_count = 0
		var row := MultiMeshInstance3D.new()
		row.multimesh = _row
		row.material_override = material
		row.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		row.extra_cull_margin = 400.0
		add_child(row)
	else:
		mesh = _mesh
		_blob.radius = 0.5
		_blob.height = 1.0
		_blob.radial_segments = 10
		_blob.rings = 5


## The dash is here now (at the runner's feet): the wall comes on to it
func extend(at: Vector3) -> void:
	if not _open:
		_runs.append([])
		_open = true
	var run: Array = _runs[-1]
	if run.is_empty() or (run[-1].pos as Vector3).distance_to(at) > STEP:
		run.append({ pos = at, age = 0.0, turn = randf() * TAU, lean = randf_range(-0.22, 0.22), size = randf_range(0.75, 1.25), let_go = false })


## The dash is over: the next one starts a wall of its own
func stop() -> void:
	_open = false


func clear() -> void:
	_runs.clear()
	_open = false
	_mesh.clear_surfaces()
	if _row:
		_row.visible_instance_count = 0
	for blob in _blobs:
		blob.node.queue_free()
	_blobs.clear()


## Whether something `radius` wide at `point` is in a length of wall that's standing
func hits(point: Vector3, radius: float) -> bool:
	var p := Vector2(point.x, point.z)
	var tall := height * (TALLER if crystal else 1.0)
	for run in _runs:
		for k in run.size() - 1:
			var a: Dictionary = run[k]
			if a.age < RISE or a.age > LIFE - SINK * 0.5:
				continue
			var from: Vector3 = a.pos
			var to: Vector3 = run[k + 1].pos
			if point.y < from.y - 0.4 or point.y > from.y + tall:
				continue
			var near := Geometry2D.get_closest_point_to_segment(p, Vector2(from.x, from.z), Vector2(to.x, to.z))
			if near.distance_to(p) < radius:
				return true
	return false


func _process(delta: float) -> void:
	var end := LIFE + (SINK if crystal else 0.0)
	for r in range(_runs.size() - 1, -1, -1):
		var run: Array = _runs[r]
		for point in run:
			point.age += delta
			if not crystal and not point.let_go and point.age > LIFE - SINK:
				point.let_go = true
				_let_go(point.pos)
		while not run.is_empty() and run[0].age > end:
			run.pop_front()
		if run.is_empty() and not (_open and r == _runs.size() - 1):
			_runs.remove_at(r)
	if crystal:
		_draw_crystals()
	else:
		_draw_blade()
		_drop_blobs(delta)


## How far up a length of it is, by its age
func _up(age: float) -> float:
	var sink := SINK * (2.0 if crystal else 1.0)
	return smoothstep(0.0, RISE, age) * (1.0 - smoothstep(LIFE - SINK, LIFE - SINK + sink, age))


func _draw_crystals() -> void:
	var count := 0
	for run in _runs:
		for point in run:
			if count >= MOST:
				break
			var up := _up(point.age)
			var tall: float = maxf(height * TALLER * up * float(point.size) / (1.0 - ROOTED), 0.01)
			var wide: float = height * 0.2 * float(point.size)
			var lean := Basis(Vector3.UP, float(point.turn)) * Basis(Vector3.RIGHT, float(point.lean))
			# (its foot a little under the ground, so the lean never shows a gap)
			_row.set_instance_transform(count, Transform3D(lean * Basis.from_scale(Vector3(wide, tall, wide)), (point.pos as Vector3) + lean.y * tall * (0.5 - ROOTED)))
			count += 1
	_row.visible_instance_count = count


func _draw_blade() -> void:
	_mesh.clear_surfaces()
	for run in _runs:
		if run.size() < 2:
			continue
		# The line it stands on: the curve through its points, and how far up it is at each
		var line: Array[Vector3] = []
		var ups: Array[float] = []
		var last_point: int = run.size() - 1
		for k in last_point:
			var before: Vector3 = run[maxi(k - 1, 0)].pos
			var from: Vector3 = run[k].pos
			var to: Vector3 = run[k + 1].pos
			var after: Vector3 = run[mini(k + 2, last_point)].pos
			for step in (FINE + 1 if k == last_point - 1 else FINE):
				var along := float(step) / FINE
				line.append(from.cubic_interpolate(to, before, after, along))
				ups.append(_up(lerpf(run[k].age, run[k + 1].age, along)))
		# A blade: two faces leaning in to one edge along the top
		for face in [1.0, -1.0]:
			_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, material)
			for k in line.size():
				var at: Vector3 = line[k]
				var across: Vector3 = (line[mini(k + 1, line.size() - 1)] - line[maxi(k - 1, 0)]).cross(Vector3.UP).normalized()
				var foot: Vector3 = at + across * THICK * 0.5 * float(face) + Vector3.DOWN * 0.05
				var top: Vector3 = at + Vector3.UP * height * ups[k]
				var normal: Vector3 = across * float(face)
				_mesh.surface_set_normal(normal)
				_mesh.surface_add_vertex(foot if float(face) > 0.0 else top)
				_mesh.surface_set_normal(normal)
				_mesh.surface_add_vertex(top if float(face) > 0.0 else foot)
			_mesh.surface_end()


## A length of the blade lets go: a blob of goo from somewhere up it
func _let_go(at: Vector3) -> void:
	var node := MeshInstance3D.new()
	node.mesh = _blob
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.position = at + Vector3.UP * height * randf_range(0.25, 0.95)
	node.scale = Vector3.ONE * height * randf_range(0.11, 0.2)
	add_child(node)
	_blobs.append({ node = node, velocity = Vector3(randf_range(-1.2, 1.2), randf_range(0.0, 1.5), randf_range(-1.2, 1.2)), floor = at.y, down = 0.0, size = node.scale.x })


## The goo: falls, splats flat where it lands, and is gone
func _drop_blobs(delta: float) -> void:
	for k in range(_blobs.size() - 1, -1, -1):
		var blob: Dictionary = _blobs[k]
		var node: MeshInstance3D = blob.node
		var size: float = blob.size
		if blob.down <= 0.0:
			blob.velocity.y -= GRAVITY * delta
			node.position += blob.velocity * delta
			# (drawn out as it falls)
			node.scale = Vector3(size * 0.85, size * (1.0 + minf(absf(blob.velocity.y) * 0.08, 0.7)), size * 0.85)
			if node.position.y <= blob.floor + size * 0.2:
				node.position.y = blob.floor + size * 0.12
				blob.down = 0.001
		else:
			blob.down += delta
			var done: float = blob.down / 0.55
			if done >= 1.0:
				node.queue_free()
				_blobs.remove_at(k)
				continue
			var spread := 1.0 + 1.3 * smoothstep(0.0, 0.25, done)
			var left := 1.0 - smoothstep(0.4, 1.0, done)
			node.scale = Vector3(size * spread * left, size * 0.3 * left, size * spread * left)
