extends Node3D
## Mercury, the runner: the Blender model (models/mercury.glb, built by art/build_mercury.py
## after mercury.png) dressed in the liquid-metal shader. Every part floats free of the
## others; the model's own animations run it ("run", a looping stride) and leap ("jump",
## a held pose). Faces -Z.

const MODEL_SCALE := 0.66 # the .glb is ~3.1 m to the horn tip; this makes it ~2 m
const RUN_PACE := 70.0 # run speed (m/s) at which the stride plays at its authored rate: at 14 m/s a cycle takes 6 s
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
var _liquid := 0.0 # 0 = firm, 1 = jelly (jump, dash, dodge)
var _puddle := 0.0 # 0 = standing, 1 = every part melted flat on the floor (the slide's end)
var _ball_home: Array[Vector3] = [] # where each ball sits on its part (the part's centre)
var _ball_shape: Array[Basis] = [] # each ball's stretch from moving, worked out by _bounce
var _puddle_order: Array[float] = [] # 0..1: when in the melt each part goes (head first)
var _pooled: Array[bool] = [] # whether each part's puddle has slid in and joined up

signal pooled # a part's puddle just joined the big one

# Each part bounces on its own: its mesh hangs off the animated node on a spring, so it lags,
# overshoots and settles a little differently from the rest. Legs also squash and stretch.
var _jiggles: Array[MeshInstance3D] = []
var _spring_pos: Array[Vector3] = []
var _spring_vel: Array[Vector3] = []
var _last_pos: Array[Vector3] = []
var _stiffness: Array[float] = []
var _deform: Array[float] = []
var _damping: Array[float] = []
var _reach: Array[float] = [] # how far a part may swing from its pose
var _springs_ready := false
var _clock := 0.0
var _splash: Array[float] = []
# The tips of the shins (left, right): where the feet are
var _feet: Array[MeshInstance3D] = []
var _foot_tips: Array[Vector3] = []
var _hand: MeshInstance3D # the arm that goes down to the floor in the superhero landing
var _hand_tip := Vector3.ZERO
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
		if view.name == "arm_R":
			_hand = jiggle
			_hand_tip = Vector3(0.0, box.position.y, 0.0)
		if view.name.begins_with("shin"):
			var tip := Vector3(0.0, box.position.y, 0.0) # the point at the bottom
			if view.name.ends_with("L"):
				_feet.push_front(jiggle)
				_foot_tips.push_front(tip)
			else:
				_feet.append(jiggle)
				_foot_tips.append(tip)
		var stiffness := 170.0
		var deform := 0.0
		var damping := 0.38
		var reach := 0.1
		if view.name.begins_with("thigh") or view.name.begins_with("shin"):
			stiffness = 140.0
			deform = 2.2
		elif view.name.begins_with("arm"):
			# Loose: soft, springy and free to swing well out of the pose
			stiffness = 28.0
			damping = 0.16
			reach = 0.35
		elif view.name.begins_with("head"):
			stiffness = 100.0
		_stiffness.append(stiffness * randf_range(0.85, 1.15))
		_damping.append(damping)
		_reach.append(reach)
		_ball_home.append(box.get_center())
		_ball_shape.append(Basis.IDENTITY)
		_pooled.append(false)
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

	# The order the slide melts them in (0 first .. 1 last): legs, then the body, then the head,
	# and the arms plop in a beat behind
	for part in _parts:
		var name := String(part.name)
		if name.begins_with("shin"):
			_puddle_order.append(0.0)
		elif name.begins_with("thigh"):
			_puddle_order.append(0.12)
		elif name.begins_with("chest"):
			_puddle_order.append(0.38)
		elif name.begins_with("head"):
			_puddle_order.append(0.6)
		else: # the arms
			_puddle_order.append(1.0)

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


## Where the feet are right now, in the world (left, right), bounce and all
func feet() -> Array[Vector3]:
	var spots: Array[Vector3] = []
	for i in _feet.size():
		spots.append(_feet[i].global_transform * _foot_tips[i])
	return spots


## Where the landing hand's tip is, in the world
func hand() -> Vector3:
	return _hand.global_transform * _hand_tip if _hand else global_position


## Something just joined this part (a droplet back, the balls setting): it ripples
func ripple(part: Node3D, amount := 1.0) -> void:
	var index := _parts.find(part)
	if index >= 0:
		_splash[index] = maxf(_splash[index], amount)


## Every part ripples at once
func ripple_all(amount := 1.0) -> void:
	for i in _splash.size():
		_splash[i] = maxf(_splash[i], amount)


## Set a liquid-metal shader setting on every part, ball and the base material
func set_shader(setting: String, value: Variant) -> void:
	material.set_shader_parameter(setting, value)
	_ball_material.set_shader_parameter(setting, value)
	for own in _part_materials:
		own.set_shader_parameter(setting, value)


## How far into the slide's melt it is: 0 standing, 1 every part a puddle on the floor
func set_puddle(amount: float) -> void:
	_puddle = amount


## Jelly (1) or firm (0): on a jump, dash or dodge every part keeps its shape but goes to jelly,
## wobbling and squashing on softer springs. The player sets the target each frame, after
## animate() and set_puddle().
func set_liquid(target: float, delta: float) -> void:
	var was := _liquid
	_liquid = move_toward(_liquid, target, delta * (8.0 if target > _liquid else 3.0))
	if was > 0.5 and _liquid <= 0.5:
		ripple_all() # firming back up
	_shape_balls()


## The bounce of an elastic ease: shoots past 1 and wobbles back (0 -> 1)
static func _elastic(x: float) -> float:
	if x <= 0.0:
		return 0.0
	if x >= 1.0:
		return 1.0
	return pow(2.0, -9.0 * x) * sin((x * 9.0 - 0.75) * TAU / 3.0) + 1.0


func _shape_balls() -> void:
	var jelly := smoothstep(0.0, 1.0, _liquid)
	var agitation: float = material.get_shader_parameter("agitation")
	var middle := global_transform * Vector3(0.0, 0.9, 0.0)
	var floor := global_position
	var size := global_basis.get_scale().x * MODEL_SCALE
	var hide_eyes := false
	for i in _parts.size():
		# The slide's melt goes part by part, head first: each has its own stretch of it
		var start := _puddle_order[i] * 0.5
		var p := clampf((_puddle - start) / 0.5, 0.0, 1.0)
		if p > 0.95 and not _pooled[i]:
			pooled.emit()
			_splash[i] = 1.0
		_pooled[i] = p > 0.95
		# The shard rounds off into a ball as it starts to melt...
		var collapse := smoothstep(0.0, 0.45, p)
		_part_materials[i].set_shader_parameter("collapse", collapse)
		_part_materials[i].set_shader_parameter("agitation", maxf(agitation, maxf(collapse, jelly)))
		_part_materials[i].set_shader_parameter("ripple", lerpf(0.35, 1.6, maxf(jelly, collapse)))
		var ball := _balls[i]
		ball.visible = collapse > 0.3
		if not ball.visible:
			continue
		if p > 0.5:
			hide_eyes = true
		# ...drops to the floor with a splat (squashing past flat and wobbling back) and slides in
		# under the middle to join the others
		var home: Vector3 = _jiggles[i].global_transform * _ball_home[i]
		var radius := _ball_radius[i] * size * clampf((collapse - 0.3) / 0.7, 0.0, 1.0)
		var fall := smoothstep(0.25, 0.7, p)
		var splat := _elastic(clampf((p - 0.45) / 0.55, 0.0, 1.0))
		var spot := home.lerp(Vector3(lerpf(home.x, middle.x, 0.75), floor.y + radius * 0.3, lerpf(home.z, middle.z, 0.75)), fall)
		var squash := Vector3(1.0 + splat * 0.9, 1.0 - splat * 0.72, 1.0 + splat * 0.9)
		var shape := _ball_shape[i]
		shape = Basis(shape.x.lerp(Vector3.RIGHT, fall), shape.y.lerp(Vector3.UP, fall), shape.z.lerp(Vector3.BACK, fall))
		ball.global_transform = Transform3D(shape * Basis.from_scale(squash * maxf(radius, 0.001)), spot)
	for eye in _eyes:
		eye.visible = not hide_eyes


## Pose for this frame. speed: ground speed; effort: 0 at full speed .. 1 from a standstill (the
## legs pump hard getting up to speed and stretch out long once there); airborne + vertical
## speed; steer -1..1 (leaning into a turn, it glides rather than strides); sliding:
## dropping into a duck
func animate(_delta: float, speed: float, airborne: bool, _vertical_speed: float, steer: float, sliding := false, landing := false, effort := 0.0) -> void:
	var pose := "slide" if sliding else ("jump" if airborne else ("land" if landing else "run"))
	if pose != _pose:
		_pose = pose
		_anim.play(pose, 0.04 if pose == "land" else BLEND) # slammed into
	if pose == "run":
		# Long, slow strides at speed; quick hard pumps when getting up to it; easing right off to a
		# glide while leaning into a turn
		var rate := maxf(speed, 1.0) / RUN_PACE + effort * 1.4
		_anim.speed_scale = rate * (1.0 - absf(steer) * 0.8)
	else:
		_anim.speed_scale = 1.0
	for i in _splash.size():
		_splash[i] = move_toward(_splash[i], 0.0, _delta * 1.6)
		_part_materials[i].set_shader_parameter("splash", _splash[i])
	_model.rotation.z = -steer * 0.6 # leaning right into turns
	_bounce(_delta)


func _bounce(delta: float) -> void:
	if delta <= 0.0:
		return
	_clock += delta
	var root := global_position
	if _springs_ready:
		_root_velocity = (root - _last_root) / delta
	_last_root = root
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
		var jelly := smoothstep(0.0, 1.0, _liquid)
		var k := _stiffness[i] * (1.0 - jelly * 0.35) # jelly: softer
		var damping := 2.0 * sqrt(k) * _damping[i] * (1.0 - jelly * 0.3)
		var velocity := _spring_vel[i] + ((target - _spring_pos[i]) * k + (target_velocity - _spring_vel[i]) * damping) * delta
		var spot := _spring_pos[i] + velocity * delta
		var offset := spot - target
		var reach := _reach[i] * (1.0 + jelly * 0.3) # (not much more: it mustn't come apart)
		if offset.length() > reach:
			offset = offset.normalized() * reach
			spot = target + offset
		_spring_pos[i] = spot
		_spring_vel[i] = velocity
		# A ball of liquid stretches along how it's moving relative to the body (see _shape_balls)
		var relative := velocity - _root_velocity
		var pull := clampf(relative.length() * 0.06, 0.0, 0.6)
		var along := relative.normalized() if relative.length() > 0.05 else Vector3.UP
		var up := Vector3.UP if absf(along.y) < 0.98 else Vector3.RIGHT
		_ball_shape[i] = Basis.looking_at(along, up) * Basis.from_scale(Vector3(1.0 - pull * 0.35, 1.0 - pull * 0.35, 1.0 + pull))
		# Into the part's own space (its scale included), so the mesh sits where the spring is
		var local := part.global_basis.inverse() * offset
		_jiggles[i].position = local
		var shape := Vector3.ONE
		if _deform[i] > 0.0:
			# Legs: stretched when the spring hangs below the joint's path, squashed above it
			var stretch := clampf(-local.y * _deform[i], -0.3, 0.35)
			shape = Vector3(1.0 - stretch * 0.45, 1.0 + stretch, 1.0 - stretch * 0.45)
		if jelly > 0.0:
			# Jelly: every part wobbles, squashing one way as it bulges the other, each in its own time
			var wob := sin(_clock * 17.0 + i * 1.7) * 0.22 * jelly
			var wob2 := sin(_clock * 13.0 + i * 2.9) * 0.16 * jelly
			shape *= Vector3(1.0 + wob, 1.0 - wob + wob2, 1.0 - wob2)
		_jiggles[i].scale = shape
	_springs_ready = true
