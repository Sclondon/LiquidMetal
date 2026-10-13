extends MeshInstance3D
## The wall a dash leaves behind it: a standing sheet of the runner's own metal along the line of
## the dash (the way a light cycle leaves a wall, but poured, not lit). It runs up out of the
## ground behind him as he goes, stands a couple of seconds with its top edge rippling, then sinks
## back. Anybody else who runs into it while it stands is burst (the arena, and the runner for its
## chasers, ask `hits`). World space. The runner calls `extend` every step of a dash and `stop`
## when it's over.

const LIFE := 2.6 # seconds a length of it stands
const RISE := 0.12 # ...of which this getting up
const SINK := 0.5 # ...and this going back down
const STEP := 0.45 # metres between the points it's laid along
const THICK := 0.34 # how thick the slab is at its foot

var material: Material
## How tall it stands (the runner's size scales it)
var height := 2.0

var _runs: Array = [] # each dash's wall: an Array of { pos, age }
var _open := false
var _mesh := ImmediateMesh.new()
var _clock := 0.0


func _ready() -> void:
	top_level = true
	mesh = _mesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	extra_cull_margin = 400.0


## The dash is here now (at the runner's feet): the wall comes on to it
func extend(at: Vector3) -> void:
	if not _open:
		_runs.append([])
		_open = true
	var run: Array = _runs[-1]
	if run.is_empty() or (run[-1].pos as Vector3).distance_to(at) > STEP:
		run.append({ pos = at, age = 0.0 })


## The dash is over: the next one starts a wall of its own
func stop() -> void:
	_open = false


func clear() -> void:
	_runs.clear()
	_open = false
	_mesh.clear_surfaces()


## Whether something `radius` wide at `point` is in a length of wall that's standing
func hits(point: Vector3, radius: float) -> bool:
	var p := Vector2(point.x, point.z)
	for run in _runs:
		for k in run.size() - 1:
			var a: Dictionary = run[k]
			if a.age < RISE or a.age > LIFE - SINK * 0.5:
				continue
			var from: Vector3 = a.pos
			var to: Vector3 = run[k + 1].pos
			if point.y < from.y - 0.4 or point.y > from.y + height:
				continue
			var near := Geometry2D.get_closest_point_to_segment(p, Vector2(from.x, from.z), Vector2(to.x, to.z))
			if near.distance_to(p) < radius:
				return true
	return false


func _process(delta: float) -> void:
	_clock += delta
	for r in range(_runs.size() - 1, -1, -1):
		var run: Array = _runs[r]
		for point in run:
			point.age += delta
		while not run.is_empty() and run[0].age > LIFE:
			run.pop_front()
		if run.is_empty() and not (_open and r == _runs.size() - 1):
			_runs.remove_at(r)
	_mesh.clear_surfaces()
	for run in _runs:
		if run.size() < 2:
			continue
		# A slab with some body to it (seen end on from behind, by whoever made it, it's still there):
		# its two faces, and its top
		for face in [1.0, -1.0, 0.0]:
			_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, material)
			for k in run.size():
				var point: Dictionary = run[k]
				var at: Vector3 = point.pos
				var next: Vector3 = run[mini(k + 1, run.size() - 1)].pos
				var last: Vector3 = run[maxi(k - 1, 0)].pos
				var across: Vector3 = (next - last).cross(Vector3.UP).normalized()
				var up := smoothstep(0.0, RISE, float(point.age)) * (1.0 - smoothstep(LIFE - SINK, LIFE, float(point.age)))
				# Its top edge: running in little waves, like something poured
				var top := height * up * (1.0 + 0.05 * sin(k * 1.9 + _clock * 7.0) + 0.03 * sin(k * 0.7 - _clock * 4.0))
				var half := across * THICK * 0.5
				var a: Vector3
				var b: Vector3
				var normal := across * float(face)
				if float(face) > 0.0:
					a = at + half + Vector3.DOWN * 0.05
					b = at + half * 0.7 + Vector3.UP * top
				elif float(face) < 0.0:
					a = at - half * 0.7 + Vector3.UP * top
					b = at - half + Vector3.DOWN * 0.05
				else:
					a = at + half * 0.7 + Vector3.UP * top
					b = at - half * 0.7 + Vector3.UP * top
					normal = Vector3.UP
				_mesh.surface_set_normal(normal)
				_mesh.surface_add_vertex(a)
				_mesh.surface_set_normal(normal)
				_mesh.surface_add_vertex(b)
			_mesh.surface_end()
