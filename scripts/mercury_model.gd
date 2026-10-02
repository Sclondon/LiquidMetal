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
var _liquid := 0.0 # 0 = shards, 1 = one gooey mass (jump, dash, dodge)
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
var _splash: Array[float] = []
# The tips of the shins (left, right): where the feet are
var _feet: Array[MeshInstance3D] = []
var _foot_tips: Array[Vector3] = []
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

	# The order the slide melts them in: highest first
	var heights: Array[float] = []
	for jiggle in _jiggles:
		heights.append((jiggle.global_transform * _ball_home[_jiggles.find(jiggle)]).y)
	var low: float = heights.min()
	var high: float = heights.max()
	for h in heights:
		_puddle_order.append(1.0 - (h - low) / maxf(high - low, 0.01))

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


## Shards to liquid (1) and back (0), quickly; the player sets the target each frame, after
## animate() and set_puddle()
func set_liquid(target: float, delta: float) -> void:
	# Melts over ~0.15 s, sets back into shards over ~0.25 s: slow enough to see it happen
	var was := _liquid
	_liquid = move_toward(_liquid, target, delta * (7.0 if target > _liquid else 4.0))
	if was > 0.5 and _liquid <= 0.5:
		ripple_all() # the liquid running back into shards
	_shape_balls()


func _shape_balls() -> void:
	var liquid := smoothstep(0.0, 1.0, _liquid)
	var agitation: float = material.get_shader_parameter("agitation")
	# The middle of the body, and the floor under it
	var middle := global_transform * Vector3(0.0, 0.9, 0.0)
	var floor := global_position
	var size := global_basis.get_scale().x * MODEL_SCALE
	var hide_eyes := liquid > 0.5
	for i in _parts.size():
		# The slide's melt goes part by part, head first: each has its own stretch of it
		var start := _puddle_order[i] * 0.55
		var p := clampf((_puddle - start) / 0.45, 0.0, 1.0)
		# The shard swells and rounds off into a ball (for the jump's liquid, or as the first
		# half of melting into a puddle)...
		if p > 0.95 and not _pooled[i]:
			pooled.emit()
		_pooled[i] = p > 0.95
		var collapse := maxf(liquid, smoothstep(0.0, 0.5, p))
		_part_materials[i].set_shader_parameter("collapse", collapse)
		_part_materials[i].set_shader_parameter("agitation", maxf(agitation, collapse))
		# ...while the true ball grows inside it, taking over once it's round
		var ball := _balls[i]
		ball.visible = collapse > 0.3
		if not ball.visible:
			continue
		if p > 0.5:
			hide_eyes = true
		var home: Vector3 = _jiggles[i].global_transform * _ball_home[i]
		var radius := _ball_radius[i] * size * clampf((collapse - 0.3) / 0.7, 0.0, 1.0)
		# Jump, dash, dodge: the balls draw in to the middle and swell till they run together
		# into one mass of liquid, every part stretched by how it's moving
		var spot := home.lerp(middle, liquid * 0.7)
		radius *= 1.0 + liquid * 0.7
		var shape := _ball_shape[i]
		# The slide: down onto the floor, spread flat, and slid in under the middle to join up
		var flat := smoothstep(0.35, 1.0, p)
		if flat > 0.0:
			var puddle_spot := Vector3(lerpf(home.x, middle.x, 0.75), floor.y + radius * 0.25, lerpf(home.z, middle.z, 0.75))
			spot = spot.lerp(puddle_spot, flat)
			var spread := Basis.from_scale(Vector3(1.0 + flat * 0.9, 1.0 - flat * 0.75, 1.0 + flat * 0.9))
			shape = Basis(shape.x.lerp(spread.x, flat), shape.y.lerp(spread.y, flat), shape.z.lerp(spread.z, flat))
		ball.global_transform = Transform3D(shape.scaled_local(Vector3.ONE * maxf(radius, 0.001)), spot)
	for eye in _eyes:
		eye.visible = not hide_eyes


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
		var damping := 2.0 * sqrt(k) * _damping[i]
		var velocity := _spring_vel[i] + ((target - _spring_pos[i]) * k + (target_velocity - _spring_vel[i]) * damping) * delta
		var spot := _spring_pos[i] + velocity * delta
		var offset := spot - target
		if offset.length() > _reach[i]:
			offset = offset.normalized() * _reach[i]
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
		if _deform[i] > 0.0:
			# Legs: stretched when the spring hangs below the joint's path, squashed above it
			var stretch := clampf(-local.y * _deform[i], -0.3, 0.35)
			_jiggles[i].scale = Vector3(1.0 - stretch * 0.45, 1.0 + stretch, 1.0 - stretch * 0.45)
	_springs_ready = true
