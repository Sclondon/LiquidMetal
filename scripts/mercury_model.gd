extends Node3D
## Mercury, the runner (after mercury.png): a spiky chrome figure built from faceted
## shards. A crown of spikes with red V eyes, a kite-shaped chest, long blade arms
## swept down and out, and two big blade legs that taper to points. Faces -Z.
## animate() runs it: legs and arms swing with the stride, it tucks in the air and
## leans into turns.

const HIP_Y := 0.9
const SHOULDER := Vector3(0.19, 1.32, 0.0)
const ARM_REST := deg_to_rad(42.0) # how far the arm blades sweep out from the body

var material: Material

var _body := Node3D.new() # bobs and leans; everything hangs off it
var _legs: Array[Node3D] = []
var _arms: Array[Node3D] = []
var _head := Node3D.new()
var _phase := 0.0
var _tuck := 0.0


func _ready() -> void:
	add_child(_body)

	# Chest: a kite, widest across the shoulders, coming to a point at the waist
	_part(_body, _blade(0.6, 0.42, 0.2, 0.18, 0.12), Vector3(0.0, 1.4, 0.0))
	# A small point under it, between the hips
	_part(_body, _blade(0.22, 0.16, 0.12, 0.6, 0.0), Vector3(0.0, HIP_Y + 0.02, 0.0), Vector3(PI, 0.0, 0.0))

	# Head: an upward diamond, a crown of spikes, and the eyes
	_head.position = Vector3(0.0, 1.43, 0.0)
	_body.add_child(_head)
	_part(_head, _blade(0.3, 0.22, 0.17, 0.4, 0.06), Vector3.ZERO, Vector3(PI, 0.0, 0.0))
	_part(_head, _spike(0.42, 0.045), Vector3(0.0, 0.24, 0.0))
	for side in [-1.0, 1.0]:
		_part(_head, _spike(0.22, 0.035), Vector3(side * 0.07, 0.18, 0.0), Vector3(0.0, 0.0, -side * 0.55))
		_part(_head, _spike(0.15, 0.03), Vector3(side * 0.1, 0.1, 0.0), Vector3(0.0, 0.0, -side * 1.0))
	var eye_material := StandardMaterial3D.new()
	eye_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	eye_material.albedo_color = Color(1.0, 0.12, 0.1)
	for side in [-1.0, 1.0]:
		var eye := BoxMesh.new()
		eye.size = Vector3(0.075, 0.018, 0.01)
		var view := MeshInstance3D.new()
		view.mesh = eye
		view.material_override = eye_material
		view.position = Vector3(side * 0.04, 0.115, -0.073)
		view.rotation = Vector3(0.0, side * 0.35, -side * 0.5) # a V, angry
		_head.add_child(view)

	# Spikes off the back of the shoulders, raked up and out
	for side in [-1.0, 1.0]:
		_part(_body, _spike(0.36, 0.05), SHOULDER * Vector3(side, 1.0, 1.0) + Vector3(0.0, 0.0, 0.06), Vector3(0.35, 0.0, -side * 0.85))

	# Arms: one long blade each, hanging from the shoulder
	for side in [-1.0, 1.0]:
		var arm := Node3D.new()
		arm.position = SHOULDER * Vector3(side, 1.0, 1.0)
		_body.add_child(arm)
		_part(arm, _blade(0.8, 0.15, 0.08, 0.22, 0.05), Vector3.ZERO)
		_arms.append(arm)

	# Legs: big blades, wide at the thigh, to a point at the floor
	for side in [-1.0, 1.0]:
		var leg := Node3D.new()
		leg.position = Vector3(side * 0.09, HIP_Y, 0.0)
		_body.add_child(leg)
		_part(leg, _blade(0.92, 0.34, 0.12, 0.3, 0.08), Vector3.ZERO)
		_legs.append(leg)


## Pose for this frame. speed: ground speed; airborne + vertical speed; steer -1..1
func animate(delta: float, speed: float, airborne: bool, vertical_speed: float, steer: float) -> void:
	_phase += delta * speed * 0.55
	_tuck = move_toward(_tuck, 1.0 if airborne else 0.0, delta * 6.0)
	var stride := sin(_phase) * (1.0 - _tuck)
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		# Legs scissor; in the air they fold back together
		_legs[i].rotation = Vector3(stride * side * 0.6 + _tuck * 0.5, 0.0, side * (0.1 + _tuck * 0.05))
		# Arms swing against the legs and sweep out; in the air they flare up and back
		_arms[i].rotation = Vector3(-stride * side * 0.45 - _tuck * 0.7, 0.0, side * (ARM_REST + _tuck * 0.5))
	# Bob twice a stride, lean into the run and into turns
	_body.position.y = absf(sin(_phase)) * 0.05 * (1.0 - _tuck)
	_body.rotation = Vector3(-0.18 - clampf(vertical_speed * 0.01, -0.15, 0.15), 0.0, -steer * 0.25)
	_head.rotation.x = 0.12


# --- Meshes ----------------------------------------------------------------------------

func _part(parent: Node3D, mesh: Mesh, at: Vector3, angles := Vector3.ZERO) -> MeshInstance3D:
	var view := MeshInstance3D.new()
	view.mesh = mesh
	view.material_override = material
	view.position = at
	view.rotation = angles
	parent.add_child(view)
	return view


## A faceted blade hanging from its top (y = 0) down to a point at -length: a small
## diamond at the top, widening to `width` x `thickness` at `widest` of the way down.
func _blade(length: float, width: float, thickness: float, widest: float, top: float) -> ArrayMesh:
	var y := -length * widest
	var ring_top := [Vector3(top * 0.5, 0, 0), Vector3(0, 0, top * 0.25), Vector3(-top * 0.5, 0, 0), Vector3(0, 0, -top * 0.25)]
	var ring_mid := [Vector3(width * 0.5, y, 0), Vector3(0, y, thickness * 0.5), Vector3(-width * 0.5, y, 0), Vector3(0, y, -thickness * 0.5)]
	var tip := Vector3(0, -length, 0)
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_smooth_group(-1) # flat: every facet catches its own light
	for k in 4:
		var n := (k + 1) % 4
		if top > 0.0:
			_tri(tool, ring_top[k], ring_mid[k], ring_mid[n])
			_tri(tool, ring_top[k], ring_mid[n], ring_top[n])
		else:
			_tri(tool, Vector3.ZERO, ring_mid[k], ring_mid[n])
		_tri(tool, ring_mid[k], tip, ring_mid[n])
	if top > 0.0: # cap the top
		_tri(tool, ring_top[0], ring_top[2], ring_top[1])
		_tri(tool, ring_top[0], ring_top[3], ring_top[2])
	tool.generate_normals()
	return tool.commit()


## A four-sided spike pointing up from its base
func _spike(length: float, radius: float) -> ArrayMesh:
	var base := [Vector3(radius, 0, 0), Vector3(0, 0, radius), Vector3(-radius, 0, 0), Vector3(0, 0, -radius)]
	var tip := Vector3(0, length, 0)
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_smooth_group(-1)
	for k in 4:
		_tri(tool, base[k], base[(k + 1) % 4], tip)
	_tri(tool, base[0], base[2], base[1], Vector3.DOWN)
	_tri(tool, base[0], base[3], base[2], Vector3.DOWN)
	tool.generate_normals()
	return tool.commit()


## outward: which way the face should point; by default straight out from the y axis
## (or up, for faces on the axis)
func _tri(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, outward := Vector3.ZERO) -> void:
	# Godot's front faces wind clockwise; flip any triangle facing inward
	var center := (a + b + c) / 3.0
	var normal := (b - a).cross(c - a)
	if outward == Vector3.ZERO:
		outward = Vector3(center.x, 0.0, center.z)
		if outward.length_squared() < 1e-6:
			outward = Vector3.UP
	if normal.dot(outward) > 0.0:
		var swap := b
		b = c
		c = swap
	tool.add_vertex(a)
	tool.add_vertex(b)
	tool.add_vertex(c)
