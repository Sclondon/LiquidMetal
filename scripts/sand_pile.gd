class_name SandPile
extends StaticBody3D
## A heap of sand that can be walked up: a cone, or with `length` a ridge with
## a half cone at each end. This node is the middle of its foot. Give it sand
## by adding to `volume`; it grows to fit, as far as `cap`.
##
## Its sides stand at `SLOPE`, which he can walk up (the Player manages 46
## degrees). It is made again, mesh and collider, each time it has grown by
## `STEP`, not every frame.

## The angle its sides stand at.
const SLOPE := deg_to_rad(30.0)
## How much wider it must have grown before it is made again, metres.
const STEP := 0.02
const AROUND := 24
## Its outline, from the middle out: how far out (as a share of its radius)
## and how high (as a share of its height). Rounded off on top, and spread at
## the foot, where it runs out a little under the ground.
const PROFILE: Array[Vector2] = [Vector2(0.14, 0.9), Vector2(0.32, 0.7), Vector2(0.62, 0.38),
		Vector2(0.86, 0.15), Vector2(1.0, 0.05), Vector2(1.16, -0.03)]

## How long its ridge is, metres; 0 for a cone. The ridge runs along its X.
@export var length := 0.0
## The widest it gets: how far its foot is from its middle (or its ridge).
@export var cap := 2.4
## Its colour. Set it before it enters the scene. (Not in Outside's copy.)
@export var colour := Sand.COLOUR

## How much sand is in it, cubic metres.
var volume := 0.0: set = _set_volume
## How far out its foot is, and how high it stands, as it is now.
var radius := 0.0
var height := 0.0

var _made := -1.0
var _visual: MeshInstance3D
var _collider: CollisionShape3D
var _material: ShaderMaterial


func _ready() -> void:
	_material = Sand.surface(colour)
	_visual = MeshInstance3D.new()
	add_child(_visual)
	_collider = CollisionShape3D.new()
	# (it is given its shape when there is a pile to stand on: Godot's own physics
	# will not have a hull with no points in it. Outside, which has Jolt, makes it here.)
	add_child(_collider)
	_make()


## Whether it has all the sand it will hold.
func is_full() -> bool:
	return radius >= cap


func _set_volume(to: float) -> void:
	volume = clampf(to, 0.0, _holds(cap))
	# (there is no formula for how wide a ridge of a given volume is: close in on it)
	var low := 0.0
	var high := cap
	for i in 16:
		var middle := (low + high) * 0.5
		if _holds(middle) < volume:
			low = middle
		else:
			high = middle
	radius = high if volume > 0.0 else 0.0
	height = radius * tan(SLOPE) * PROFILE[0].y
	if is_inside_tree() and absf(radius - _made) >= STEP:
		_make()


## How much sand a pile this wide holds: a cone, and a ridge between its halves.
func _holds(wide: float) -> float:
	return tan(SLOPE) * (PI * wide * wide * wide / 3.0 + length * wide * wide)


func _make() -> void:
	_made = radius
	# Too small to trip over: nothing to see, nothing to stand on.
	_visual.visible = radius > 0.04
	_collider.disabled = radius < 0.2
	if not _visual.visible:
		return
	var tall := radius * tan(SLOPE)
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_smooth_group(0)
	# The top: one point, or one at each end of the ridge.
	var half := length * 0.5
	tool.add_vertex(Vector3(-half, tall * PROFILE[0].y * 1.02, 0.0))
	tool.add_vertex(Vector3(half, tall * PROFILE[0].y * 1.02, 0.0))
	var hull := PackedVector3Array([Vector3(-half, tall * PROFILE[0].y, 0.0), Vector3(half, tall * PROFILE[0].y, 0.0)])
	@warning_ignore("integer_division")
	var each_end := AROUND / 2
	for ring in PROFILE.size():
		for i in AROUND:
			# Round the +X end first, then back round the -X end.
			var near_end := i < each_end
			var angle := float(i % each_end) / (each_end - 1) * PI - PI * 0.5
			var out := Vector3(cos(angle), 0.0, sin(angle)) * (1.0 if near_end else -1.0)
			var point := out * radius * PROFILE[ring].x + Vector3(half if near_end else -half, tall * PROFILE[ring].y, 0.0)
			tool.add_vertex(point)
			# He stands on a plainer shape: straight sides from the foot to near the top.
			if ring <= 1:
				hull.append(point)
			elif ring == 4:
				hull.append(Vector3(point.x, 0.0, point.z))
	for i in AROUND:
		var next := (i + 1) % AROUND
		# Each end fans out from its own top; between them, a strip across the ridge.
		var top := 1 if i < each_end else 0
		for corner: int in [top, 2 + i, 2 + next]:
			tool.add_index(corner)
		if i == each_end - 1 or i == AROUND - 1:
			for corner: int in [top, 2 + next, 1 - top]:
				tool.add_index(corner)
		for ring in PROFILE.size() - 1:
			var a := 2 + ring * AROUND + i
			var b := 2 + ring * AROUND + next
			for corner: int in [a, a + AROUND, b + AROUND, a, b + AROUND, b]:
				tool.add_index(corner)
	tool.generate_normals()
	var mesh := tool.commit()
	mesh.surface_set_material(0, _material)
	_visual.mesh = mesh
	var shape := ConvexPolygonShape3D.new()
	shape.points = hull
	_collider.shape = shape
