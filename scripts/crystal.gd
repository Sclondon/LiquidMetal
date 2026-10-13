extends RefCounted
## Crystals, for the Crystaliens (the people of the black sand moon): the meshes they're cut from
## and their colours. A shard is a six-sided crystal with a point at each end; a Crystalien runner
## is Mercury's skeleton with a shard in place of each part (mercury_model.gd, `crystal`); one in
## the crowd is a small figure made of four of them (colosseum.gd).

const COLORS := [
	Color(0.75, 0.35, 1.0), Color(0.3, 0.9, 1.0), Color(1.0, 0.35, 0.75), Color(0.4, 1.0, 0.55),
	Color(1.0, 0.75, 0.25), Color(0.45, 0.5, 1.0), Color(1.0, 0.4, 0.3),
]


## A shard along Y, centred: `radius` across, `length` tip to tip, the middle `waist` of its
## length a straight prism (0: a plain double point). Flat facets.
static func shard(radius: float, length: float, waist := 0.45, sides := 6) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_smooth_group(-1)
	add_shard(tool, Transform3D.IDENTITY, radius, radius, length, waist, sides)
	tool.generate_normals()
	return tool.commit()


## One shard into a mesh being built, placed by `at` (its length along at's Y); rx, rz: its
## half-widths across
static func add_shard(tool: SurfaceTool, at: Transform3D, rx: float, rz: float, length: float, waist := 0.45, sides := 6) -> void:
	var top := at * Vector3(0.0, length * 0.5, 0.0)
	var foot := at * Vector3(0.0, -length * 0.5, 0.0)
	var centre := at.origin
	for k in sides:
		var a := k * TAU / sides
		var b := (k + 1) * TAU / sides
		var upper_a := at * Vector3(cos(a) * rx, length * 0.5 * waist, sin(a) * rz)
		var upper_b := at * Vector3(cos(b) * rx, length * 0.5 * waist, sin(b) * rz)
		var lower_a := at * Vector3(cos(a) * rx, -length * 0.5 * waist, sin(a) * rz)
		var lower_b := at * Vector3(cos(b) * rx, -length * 0.5 * waist, sin(b) * rz)
		_face(tool, centre, top, upper_a, upper_b)
		_face(tool, centre, foot, lower_b, lower_a)
		if waist > 0.0:
			_face(tool, centre, upper_a, lower_a, lower_b)
			_face(tool, centre, upper_a, lower_b, upper_b)


## A triangle, wound so it faces away from `centre`
static func _face(tool: SurfaceTool, centre: Vector3, a: Vector3, b: Vector3, c: Vector3) -> void:
	if (b - a).cross(c - a).dot((a + b + c) / 3.0 - centre) > 0.0:
		var swap := b
		b = c
		c = swap
	tool.add_vertex(a)
	tool.add_vertex(b)
	tool.add_vertex(c)


## A crystal to stand in for one of Mercury's parts: a shard filling the part's box, along its
## longest side. The head gets two smaller ones growing out of it, the chest a third at the back.
static func part(box: AABB, part_name: String) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_smooth_group(-1)
	var axis := box.get_longest_axis_index()
	# (the shard is built along Y: turn it to lie along the box's longest side)
	var turn := Basis.IDENTITY
	var across := Vector2(box.size.x, box.size.z)
	if axis == Vector3.AXIS_X:
		turn = Basis(Vector3.FORWARD, PI / 2.0)
		across = Vector2(box.size.y, box.size.z)
	elif axis == Vector3.AXIS_Z:
		turn = Basis(Vector3.RIGHT, PI / 2.0)
		across = Vector2(box.size.x, box.size.y)
	var length: float = box.size[axis]
	var at := Transform3D(turn, box.get_center())
	if part_name.begins_with("head"):
		add_shard(tool, at, across.x * 0.42, across.y * 0.42, length * 0.9, 0.3)
		for side in [-1.0, 1.0]:
			var horn := Transform3D(turn * Basis(Vector3.RIGHT, 0.5) * Basis(Vector3.FORWARD, side * 0.6), box.get_center() + turn * Vector3(side * across.x * 0.3, length * 0.15, 0.0))
			add_shard(tool, horn, across.x * 0.14, across.y * 0.14, length * 0.8, 0.2)
	elif part_name.begins_with("chest"):
		add_shard(tool, at, across.x * 0.5, across.y * 0.5, length, 0.55)
		for side in [-1.0, 1.0]:
			var spur := Transform3D(turn * Basis(Vector3.FORWARD, side * 0.75), box.get_center() + turn * Vector3(side * across.x * 0.35, length * 0.22, 0.0))
			add_shard(tool, spur, across.x * 0.16, across.y * 0.2, length * 0.6, 0.3)
	else:
		add_shard(tool, at, across.x * 0.5, across.y * 0.5, length, 0.5)
	tool.generate_normals()
	return tool.commit()


## One of the crowd: a body, a head and two arms thrown up, standing on the origin, facing -Z
static func spectator() -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_smooth_group(-1)
	add_shard(tool, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.7, 0.0)), 0.3, 0.24, 1.4, 0.35, 5)
	add_shard(tool, Transform3D(Basis.IDENTITY, Vector3(0.0, 1.6, 0.0)), 0.2, 0.2, 0.6, 0.0, 5)
	for side in [-1.0, 1.0]:
		add_shard(tool, Transform3D(Basis(Vector3.FORWARD, -side * 0.6), Vector3(side * 0.42, 1.25, 0.0)), 0.08, 0.08, 0.9, 0.0, 4)
	tool.generate_normals()
	return tool.commit()
