extends MeshInstance3D
## The two tracks Mercury's feet leave: a ribbon of liquid metal on the floor under each foot
## for as long as it's down, broken when it lifts and started again where it lands, tapering
## and fading away behind. World space. The player calls step() every frame.

const LIFE := 1.6 # seconds a bit of track lasts
const STEP := 0.15 # metres between the points a track is laid along
const CONTACT := 0.14 # a foot this close to the floor is touching it

var material: Material

var _strips: Array = [[], []] # per foot: strips, each an Array of { pos, age, width }
var _down: Array[bool] = [false, false]
var _mesh := ImmediateMesh.new()


func _ready() -> void:
	top_level = true
	mesh = _mesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


## feet: where each foot is; floor: the height of the ground under them (NAN: in the air)
func step(feet: Array[Vector3], floor: float, width: float, delta: float) -> void:
	for f in mini(feet.size(), 2):
		var foot := feet[f]
		var touching := not is_nan(floor) and foot.y - floor < CONTACT
		var strips: Array = _strips[f]
		if touching:
			var spot := Vector3(foot.x, floor + 0.012, foot.z)
			if not _down[f]:
				strips.append([]) # landed: a new piece of track
			var strip: Array = strips.back()
			if strip.size() < 2 or strip[strip.size() - 2].pos.distance_to(spot) > STEP:
				strip.append({ pos = spot, age = 0.0, width = width })
			else:
				strip.back().pos = spot # the end of the track stays right under the foot
		_down[f] = touching
	_age(delta)
	_draw()


## Every foot off the ground: the next touch starts a fresh piece of track
func lift() -> void:
	_down = [false, false]


func clear() -> void:
	_strips = [[], []]
	_down = [false, false]
	_mesh.clear_surfaces()


func _age(delta: float) -> void:
	for strips in _strips:
		for i in range(strips.size() - 1, -1, -1):
			var strip: Array = strips[i]
			for point in strip:
				point.age += delta
			while not strip.is_empty() and strip[0].age > LIFE:
				strip.pop_front()
			if strip.is_empty() and i < strips.size() - 1:
				strips.remove_at(i)


func _draw() -> void:
	_mesh.clear_surfaces()
	for strips in _strips:
		for strip in strips:
			if strip.size() < 2:
				continue
			_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, material)
			for i in strip.size():
				var point: Dictionary = strip[i]
				var before: Vector3 = strip[maxi(i - 1, 0)].pos
				var after: Vector3 = strip[mini(i + 1, strip.size() - 1)].pos
				var along := Vector3(after.x - before.x, 0.0, after.z - before.z)
				if along.length_squared() < 1e-6:
					along = Vector3.FORWARD
				var side := along.normalized().cross(Vector3.UP)
				# Narrows to nothing as it ages, and to a point at the very start
				var fade: float = 1.0 - point.age / LIFE
				var start := minf(float(i) / 2.0, 1.0)
				var half: float = point.width * 0.5 * fade * (0.4 + 0.6 * start)
				_mesh.surface_set_normal(Vector3.UP)
				_mesh.surface_add_vertex(point.pos + side * half)
				_mesh.surface_set_normal(Vector3.UP)
				_mesh.surface_add_vertex(point.pos - side * half)
			_mesh.surface_end()
