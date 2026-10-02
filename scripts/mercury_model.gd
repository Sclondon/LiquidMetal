extends Node3D
## Mercury, the runner: the Blender model (models/mercury.glb, built by art/build_mercury.py
## after mercury.png) dressed in the liquid-metal shader. Every part floats free of the
## others; the model's own animations run it ("run", a looping stride) and leap ("jump",
## a held pose). Faces -Z.

const MODEL_SCALE := 0.66 # the .glb is ~3.1 m to the horn tip; this makes it ~2 m
const RUN_PACE := 14.0 # run speed (m/s) at which the stride plays at its authored rate (1.2 s a cycle)
const BLEND := 0.08 # seconds to blend between run and jump: snappy

var material: Material

var _model: Node3D
var _parts: Array[Node3D] = []
var _eyes: Array[Node3D] = []
# Each part's own copy of the metal (so it can collapse to its own centre), and the ball of
# liquid it turns into on a jump, dash or dodge
var _part_materials: Array[ShaderMaterial] = []
var _balls: Array[MeshInstance3D] = []
var _ball_radius: Array[float] = []
var _ball_material := ShaderMaterial.new()
var _liquid := 0.0 # 0 = shards, 1 = balls

# Each part bounces on its own: its mesh hangs off the animated node on a spring, so it lags,
# overshoots and settles a little differently from the rest. Legs also squash and stretch.
var _jiggles: Array[MeshInstance3D] = []
var _spring_pos: Array[Vector3] = []
var _spring_vel: Array[Vector3] = []
var _last_pos: Array[Vector3] = []
var _stiffness: Array[float] = []
var _deform: Array[float] = []
var _springs_ready := false
var _splash: Array[float] = []
var _last_root := Vector3.ZERO
var _root_velocity := Vector3.ZERO
var _anim: AnimationPlayer
var _pose := "run"


func _ready() -> void:
	_model = preload("res://models/mercury.glb").instantiate()
	_model.scale = Vector3.ONE * MODEL_SCALE
	add_child(_model)

	# Chrome everywhere but the eyes, which glow red
	var eye_material := StandardMaterial3D.new()
	eye_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	eye_material.albedo_color = Color(1.0, 0.1, 0.08)
	_ball_material.shader = material.shader
	_ball_material.set_shader_parameter("agitation", 1.0) # balls of liquid: always wobbling
	var ball_mesh := SphereMesh.new()
	ball_mesh.radius = 1.0
	ball_mesh.height = 2.0
	ball_mesh.radial_segments = 20
	ball_mesh.rings = 10
	for view in _model.find_children("*", "MeshInstance3D", true, false):
		var original: Material = view.mesh.surface_get_material(0)
		if original and original.resource_name == "Eye":
			view.material_override = eye_material
			_eyes.append(view)
			continue
		var box: AABB = view.mesh.get_aabb()
		var own: ShaderMaterial = material.duplicate()
		own.set_shader_parameter("collapse_center", box.get_center())
		_part_materials.append(own)
		_parts.append(view)
		# The mesh moves to a child on a spring; the animated node keeps only the pose
		var jiggle := MeshInstance3D.new()
		jiggle.mesh = view.mesh
		jiggle.material_override = own
		view.mesh = null
		view.add_child(jiggle)
		_jiggles.append(jiggle)
		var stiffness := 170.0
		var deform := 0.0
		if view.name.begins_with("thigh") or view.name.begins_with("shin"):
			stiffness = 140.0
			deform = 2.2
		elif view.name.begins_with("arm"):
			stiffness = 70.0 # floaty
		elif view.name.begins_with("head"):
			stiffness = 100.0
		_stiffness.append(stiffness * randf_range(0.85, 1.15))
		own.set_shader_parameter("ball_radius", clampf(box.size.length() * 0.24, 0.1, 0.3))
		_deform.append(deform)
		_splash.append(0.0)
		var ball := MeshInstance3D.new()
		ball.mesh = ball_mesh
		ball.material_override = _ball_material
		ball.position = box.get_center()
		ball.scale = Vector3.ONE * 0.001 # sized each frame once it shows
		ball.visible = false
		jiggle.add_child(ball)
		_balls.append(ball)
		_ball_radius.append(clampf(box.size.length() * 0.24, 0.1, 0.3))

	# The eyes go with the head's bouncing mesh
	for eye in _eyes:
		var head: Node = eye.get_parent()
		var index := _parts.find(head)
		if index >= 0:
			eye.reparent(_jiggles[index], false)

	_anim = _model.find_child("AnimationPlayer", true, false)
	_anim.get_animation("run").loop_mode = Animation.LOOP_LINEAR
	_anim.play("run")


## The metal body parts (where droplets come off and go back to)
func parts() -> Array[Node3D]:
	return _parts


## Something just joined this part (a droplet back, the balls setting): it ripples
func ripple(part: Node3D, amount := 1.0) -> void:
	var index := _parts.find(part)
	if index >= 0:
		_splash[index] = maxf(_splash[index], amount)


## Every part ripples at once
func ripple_all(amount := 1.0) -> void:
	for i in _splash.size():
		_splash[i] = maxf(_splash[i], amount)


## Shards to balls of liquid (1) and back (0), quickly; the player sets the target each frame
func set_liquid(target: float, delta: float) -> void:
	# Melts over ~0.15 s, sets back into shards over ~0.25 s: slow enough to see it happen
	var was := _liquid
	_liquid = move_toward(_liquid, target, delta * (7.0 if target > _liquid else 4.0))
	if was > 0.5 and _liquid <= 0.5:
		ripple_all() # the balls running back together into shards
	var melt := smoothstep(0.0, 1.0, _liquid)
	var agitation: float = material.get_shader_parameter("agitation")
	for i in _parts.size():
		# The shard itself swells and rounds off onto its ball...
		_part_materials[i].set_shader_parameter("collapse", melt)
		_part_materials[i].set_shader_parameter("agitation", maxf(agitation, melt))
		# ...while the true ball grows inside it, only reaching full size as the shard does
		_balls[i].visible = melt > 0.3
	for eye in _eyes:
		eye.visible = melt < 0.5


## Pose for this frame. speed: ground speed; airborne + vertical speed; steer -1..1; sliding:
## dropping into a duck
func animate(_delta: float, speed: float, airborne: bool, _vertical_speed: float, steer: float, sliding := false) -> void:
	var pose := "slide" if sliding else ("jump" if airborne else "run")
	if pose != _pose:
		_pose = pose
		_anim.play(pose, BLEND)
	_anim.speed_scale = maxf(speed, 1.0) / RUN_PACE if pose == "run" else 1.0
	for i in _splash.size():
		_splash[i] = move_toward(_splash[i], 0.0, _delta * 1.6)
		_part_materials[i].set_shader_parameter("splash", _splash[i])
	_model.rotation.z = -steer * 0.25 # lean into turns
	_bounce(_delta)


func _bounce(delta: float) -> void:
	if delta <= 0.0:
		return
	var root := global_position
	if _springs_ready:
		_root_velocity = (root - _last_root) / delta
	_last_root = root
	var melt := smoothstep(0.0, 1.0, _liquid)
	for i in _parts.size():
		var part: Node3D = _parts[i]
		var target := part.global_position
		if not _springs_ready:
			_spring_pos.append(target)
			_spring_vel.append(Vector3.ZERO)
			_last_pos.append(target)
			continue
		var target_velocity := (target - _last_pos[i]) / delta
		_last_pos[i] = target
		if target_velocity.length() > 80.0: # a teleport (respawn): snap, don't fling
			_spring_pos[i] = target
			_spring_vel[i] = Vector3.ZERO
			continue
		# A bouncy spring (well under critical damping) toward where the animation has the part,
		# damped relative to the part's own velocity so running fast doesn't drag it behind
		var k := _stiffness[i]
		var damping := 2.0 * sqrt(k) * 0.38
		var velocity := _spring_vel[i] + ((target - _spring_pos[i]) * k + (target_velocity - _spring_vel[i]) * damping) * delta
		var spot := _spring_pos[i] + velocity * delta
		var offset := spot - target
		if offset.length() > 0.1:
			offset = offset.normalized() * 0.1
			spot = target + offset
		_spring_pos[i] = spot
		_spring_vel[i] = velocity
		# The ball of liquid (when there is one) stretches along how it's moving relative to the
		# body and squashes back as it settles
		if _balls[i].visible:
			var radius := _ball_radius[i] * part.global_basis.get_scale().x * clampf((melt - 0.3) / 0.7, 0.0, 1.0)
			var relative := velocity - _root_velocity
			var stretch := clampf(relative.length() * 0.045, 0.0, 0.45)
			var along := relative.normalized() if relative.length() > 0.05 else Vector3.UP
			var up := Vector3.UP if absf(along.y) < 0.98 else Vector3.RIGHT
			var shape := Basis.looking_at(along, up) * Basis.from_scale(Vector3(1.0 - stretch * 0.35, 1.0 - stretch * 0.35, 1.0 + stretch))
			_balls[i].global_basis = shape.scaled_local(Vector3.ONE * maxf(radius, 0.001))
		# Into the part's own space (its scale included), so the mesh sits where the spring is
		var local := part.global_basis.inverse() * offset
		_jiggles[i].position = local
		if _deform[i] > 0.0:
			# Legs: stretched when the spring hangs below the joint's path, squashed above it
			var stretch := clampf(-local.y * _deform[i], -0.3, 0.35)
			_jiggles[i].scale = Vector3(1.0 - stretch * 0.45, 1.0 + stretch, 1.0 - stretch * 0.45)
	_springs_ready = true
