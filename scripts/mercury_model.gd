extends Node3D
## Mercury, the runner: the Blender model (models/mercury.glb, built by art/build_mercury.py
## after mercury.png) dressed in the liquid-metal shader. Every part floats free of the
## others; the model's own animations run it ("run", a looping stride), leap ("jump", a held
## pose), stand still ("idle", breathing) and hold the T ("tpose", the model viewer's). Faces -Z.
## Bundles of chrome tubes, like muscles, join the floating parts at the neck, shoulders, hips and
## knees: drawn fresh each frame between the parts' bouncing meshes, so they stretch and bend
## with them.

const MODEL_SCALE := 0.66 # the .glb is ~3.1 m to the horn tip; this makes it ~2 m
# The stride: the legs always pump at the same quick rate; what changes with speed is how long
# each lunge is held (the run animation lunges at 0 s and 0.6 s of its 1.2 s)
const PUMP_RATE := 1.6 # the animation's speed between lunges
const LUNGES := [0.0, 0.6]
const LUNGE_WINDOW := Vector2(-0.03, 0.06) # around each lunge: the stretch that's held
const HOLD_SLOW := 0.06 # held lunge length (s) from a standstill...
const HOLD_FAST := 0.9 # ...up to this at TOP_SPEED
const TOP_SPEED := 26.0
const BLEND := 0.08 # seconds to blend between run and jump: snappy

var material: Material
## A Crystalien: the same skeleton and moves, a crystal in place of each part, no tube muscles
var crystal := false

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
var _head_jiggle: Node3D
var _arm_pump := 0.0
var _kick_left := 0.0 # a dash kicking off: one quick switch of legs
var _kick_rate := 0.0 # how fast the kick's two steps play
var _cock := 0.0
var _punch := 0.0
var _punch_with := "both" # "L", "R" or "both" (the X slash)
var _slash := 1.0 # 0..1 through the slash's sweep (1: done, held at its end)
const SLASH_TIME := 0.18 # seconds for the blade to sweep from over the shoulder to down across
var _stretch: Array[float] = []
var _arm_length := 1.0 # an arm blade's length in the model (from its mesh)
# The slash's trail: a thin fading arc behind each slashing blade, along its outer third
const TRAIL_LIFE := 0.16
var _trail_points := {} # "L"/"R" -> [{ inner, outer, age }]
var _trail_mesh := ImmediateMesh.new()
var _trail_view := MeshInstance3D.new()
var _trail_material := StandardMaterial3D.new()
# The tube muscles: [from part, point on it, to part, point on it, radius, how many in the bundle,
# how far apart]. Points are where on each part's mesh they attach, as Blender has them (x right,
# y ahead, z up, from the part's own joint); "_S": once for each side (S = -1 left, +1 right).
const TUBES := [
	["chest", Vector3(0.0, 0.0, 0.5), "head", Vector3(0.0, -0.03, -0.14), 0.058, 3, 0.07], # the neck
	["chest", Vector3(0.21, 0.0, 0.38), "arm_S", Vector3(0.0, 0.0, -0.12), 0.048, 2, 0.07], # shoulders
	["chest", Vector3(0.07, 0.0, 0.05), "thigh_S", Vector3(0.0, 0.0, -0.08), 0.058, 2, 0.07], # hips
	["thigh_S", Vector3(0.0, 0.0, -0.56), "shin_S", Vector3(0.0, -0.02, 0.0), 0.045, 2, 0.08], # knees: into the ball joint
]
const TUBE_RINGS := 10 # along each tube
const TUBE_SIDES := 7 # round it
var _tube_links: Array = [] # [from mesh, from point, to mesh, to point, radius, count, spread] (Godot points)
var _tube_mesh := ImmediateMesh.new()
var _tube_view := MeshInstance3D.new()
var _tubes_hidden := false
var _turned: Array[Vector3] = [] # per part: its own extra turn (euler), kept here, not read back off a scaled basis # per part: drawn out along its length (the punching arm)
## The slash trail's colour (enemies: red)
var trail_color := Color(0.75, 0.88, 1.0)
## Something nearby to look at (the player picks it; INF: nothing)
var look_point := Vector3.INF
var _look_yaw := 0.0
## 0..1: the inside hand reaching down to the floor on a sharp turn (the player sets it)
var turn_support := 0.0
var _turn_sign := 0.0 # which way it last turned
var _straight_for := 0.0
var _switch_step := 0.0 # seconds left of stepping across after turning the other way
var _splash: Array[float] = []
# The tips of the shins (left, right): where the feet are
var _feet: Array[MeshInstance3D] = []
var _foot_tips: Array[Vector3] = []
# The superhero landing's hand on the floor: "R" or "L" (the player picks one each landing)
var land_side := "R"
var _hands := {} # "L"/"R" -> the arm's bouncing mesh
var _hand_tip := Vector3.ZERO
var _last_root := Vector3.ZERO
var _root_velocity := Vector3.ZERO
var _anim: AnimationPlayer
var _pose := "run"
## A pose held whatever it's doing ("tpose" in the model viewer; "": none)
var force_pose := ""
const IDLE_BLEND := 0.3 # seconds to settle into standing (or set off from it)


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
		if crystal:
			view.mesh = preload("res://scripts/crystal.gd").part(view.mesh.get_aabb(), view.name)
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
		if view.name.begins_with("arm_"):
			_arm_length = box.size.y * MODEL_SCALE
			_hands[String(view.name).right(1)] = jiggle
			_hand_tip = Vector3(0.0, box.position.y, 0.0)
		if view.name.begins_with("head"):
			_head_jiggle = jiggle
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
			# Loose and bouncy, but kept close to the body
			stiffness = 40.0
			damping = 0.2
			reach = 0.22
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
		_stretch.append(1.0)
		_turned.append(Vector3.ZERO)
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

	# The shoulder pads go with their arm's bouncing (and slashing) blade
	for part in _parts:
		var name := String(part.name)
		if name.begins_with("pad_") and _hands.has(name.right(1)):
			part.reparent(_hands[name.right(1)], false)

	# The eyes go with the head's bouncing mesh
	for eye in _eyes:
		var head: Node = eye.get_parent()
		var index := _parts.find(head)
		if index >= 0:
			eye.reparent(_jiggles[index], false)

	_anim = _model.find_child("AnimationPlayer", true, false)
	_anim.get_animation("run").loop_mode = Animation.LOOP_LINEAR
	_anim.get_animation("idle").loop_mode = Animation.LOOP_LINEAR
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


## An arm's mesh ("L" / "R") as it is right now (the crash flings copies of them at the wall)
func arm_mesh(side: String) -> MeshInstance3D:
	return _hands.get(side)


## Where the landing hand's tip is, in the world
func hand(side := "") -> Vector3:
	var arm: Node3D = _hands.get(side if side != "" else land_side)
	return arm.global_transform * _hand_tip if arm else global_position


## Something just joined this part (a droplet back, the balls setting): it ripples
func ripple(part: Node3D, amount := 1.0) -> void:
	var index := _parts.find(part)
	if index >= 0:
		_splash[index] = maxf(_splash[index], amount)


## Every part ripples at once
func ripple_all(amount := 1.0) -> void:
	for i in _splash.size():
		_splash[i] = maxf(_splash[i], amount)


## A dash kicking off: a quick switch of legs into the other lunge, held till the twirl
func kick(time: float) -> void:
	_kick_left = time
	# Two quick steps: on through the next lunge to the one after it
	var at := fmod(_anim.current_animation_position, 1.2)
	var to_next := fmod((0.6 if at < 0.6 else 1.2) - at + 1.2, 1.2)
	_kick_rate = (to_next + 0.6) / maxf(time - 0.04, 0.05)


## The dash's slash: cock 0..1 the blade raised over the shoulder, punch 0..1 the slash on (it
## sweeps through once as it comes on, held at its end through the dash, easing off after)
func set_punch(cock: float, punch: float, with := "both") -> void:
	if punch > 0.0 and _punch <= 0.0:
		_slash = 0.0 # a new slash: from the top
		for side in _trail_points:
			_trail_points[side].clear()
	_cock = cock
	_punch = punch
	_punch_with = with


## Whether an arm ("L" / "R") is the one slashing (both, for the X)
func _punching(side: String) -> bool:
	return _punch_with == "both" or _punch_with == side


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
	var hide_eyes := jelly > 0.35 # (the head's surface wobbles off them as jelly)
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
	_tubes_hidden = hide_eyes or jelly > 0.2 # (melting or gone to jelly: the parts come apart)


## Pose for this frame. speed: ground speed; effort: 0 at full speed .. 1 from a standstill (the
## legs pump hard getting up to speed and stretch out long once there); airborne + vertical
## speed; steer -1..1 (leaning into a turn, it glides rather than strides); sliding:
## dropping into a duck
## standing: stopped (braked to a halt, or not running at all): it stands, breathing
func animate(_delta: float, speed: float, airborne: bool, _vertical_speed: float, steer: float, sliding := false, landing := false, effort := 0.0, standing := false) -> void:
	var pose := "slide" if sliding else ("jump" if airborne else ("land" if landing else ("idle" if standing else "run")))
	if force_pose != "":
		pose = force_pose
		steer = 0.0
	if pose != _pose:
		var from := _pose
		_pose = pose
		if pose == "land":
			_anim.play("land_" + land_side, 0.04) # slammed into
		else:
			_anim.play(pose, IDLE_BLEND if pose in ["idle", "tpose"] or from in ["idle", "tpose"] else BLEND)
			if pose == "run" and from == "land":
				# Out of the landing's step straight into the stride: on that leg's lunge
				_anim.seek(0.6 if land_side == "R" else 0.0, true)
	if pose == "run":
		# A quick pump of the legs into each lunge, then the lunge held, gliding: barely at all from
		# a standstill, longer and longer the faster it goes. Turning, it steps (quickly) into a lunge
		# and holds it for as long as the turn lasts.
		var turning := absf(steer) > 0.3
		# Switching from one turn to the other: let go of the held lunge and step across into the
		# other leg's
		_switch_step = maxf(_switch_step - _delta, 0.0)
		if turning:
			if _turn_sign != 0.0 and signf(steer) != _turn_sign:
				_switch_step = 0.35
			_turn_sign = signf(steer)
			_straight_for = 0.0
		else:
			# Run straight a moment and the last turn's forgotten: the next one isn't a switch
			_straight_for += _delta
			if _straight_for > 0.25:
				_turn_sign = 0.0
		var fast := clampf((speed - 4.0) / (TOP_SPEED - 4.0), 0.0, 1.0) * (1.0 - effort * 0.5)
		var hold := lerpf(HOLD_SLOW, HOLD_FAST, fast)
		# Near a standstill the legs pump much faster, working up to speed
		var rate := PUMP_RATE * (1.0 + absf(steer) * 0.3 + effort * 2.5)
		var at := fmod(_anim.current_animation_position, _anim.current_animation_length)
		for lunge in LUNGES:
			var d: float = at - lunge
			if d > LUNGE_WINDOW.x and d < LUNGE_WINDOW.y:
				rate = (LUNGE_WINDOW.y - LUNGE_WINDOW.x) / hold # crawl through it: held for `hold` s
				var inside: bool = lunge == (0.6 if steer > 0.0 else 0.0) # (the inside leg forward)
				if turning and inside and d > 0.0 and _switch_step <= 0.0:
					rate = 0.0 # into the turn: held right there till it straightens out
		if _kick_left > 0.0:
			_kick_left -= _delta
			rate = _kick_rate if _kick_left > 0.04 else 0.0
		if _punch > 0.3:
			rate = 0.0 # held in the lunge while the punch carries him
		_anim.speed_scale = rate
	else:
		_anim.speed_scale = 1.0
	for i in _splash.size():
		_splash[i] = move_toward(_splash[i], 0.0, _delta * 1.6)
		_part_materials[i].set_shader_parameter("splash", _splash[i])
	# Into a turn: the body swung round to face into it (stepping that way) and leaning into it,
	# the head turned further still, looking round the corner
	_model.rotation = Vector3(0.0, -steer * 0.4, -steer * 0.5) * (0.0 if pose == "slide" else 1.0)
	# The stride's phase (0..1 over the cycle: left lunge at 0, right at 0.5) drives the little
	# extras: the head turning a touch with each stride, and the arms pumping when slow
	var phase := 0.0
	if _anim.current_animation == "run":
		phase = _anim.current_animation_position / maxf(_anim.current_animation_length, 0.01)
	var stride := sin(phase * TAU) if pose == "run" else 0.0
	if _head_jiggle:
		# Turning his head to look at what's near (an obstacle coming, a drop to grab)
		var want := 0.0
		if look_point != Vector3.INF:
			var local := _model.global_basis.inverse() * (look_point - _head_jiggle.global_position)
			want = clampf(atan2(-local.x, -local.z), -1.0, 1.0)
		_look_yaw = lerpf(_look_yaw, want, 1.0 - exp(-_delta * 5.0))
		_turned[_jiggles.find(_head_jiggle)] = Vector3(0.0, -steer * 0.7 + stride * 0.16 + _look_yaw, 0.0)
	# Slow (getting up to speed): the arms pump hard, each against its leg; gone by full speed
	var pump := clampf(maxf(effort, (10.0 - speed) / 6.0), 0.0, 1.0) * (1.0 if pose == "run" else 0.0)
	_arm_pump = lerpf(_arm_pump, pump, 1.0 - exp(-_delta * 6.0))
	for side in _hands:
		var arm: Node3D = _hands[side]
		var swing := stride * (1.0 if side == "L" else -1.0) # the left arm forward on the right lunge
		var out := 0.0
		if (side == "R") == (steer > 0.0): # the inside arm on a turn: down and out to the floor
			out = steer * 0.65 * turn_support
		var turn := Vector3(swing * 1.0 * _arm_pump * (1.0 - turn_support) + 0.5 * absf(out), 0.0, out)
		if (_cock > 0.0 or _punch > 0.0) and _punching(side):
			turn = Vector3.ZERO # (the wind-up and the slash are aimed in _bounce)
		var index := _jiggles.find(arm)
		if index >= 0:
			_turned[index] = turn
			_stretch[index] = 1.0
	_bounce(_delta)


func _bounce(delta: float) -> void:
	if delta <= 0.0:
		return
	delta = minf(delta, 1.0 / 30.0) # a long frame would throw the springs out
	if _punch > 0.0 and _slash < 1.0:
		_slash = minf(_slash + delta / SLASH_TIME, 1.0)
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
		_jiggles[i].position = local * (1.0 - _punch if _hands.values().has(_jiggles[i]) else 1.0) # (slashing: the blade held firm to its swing)
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
		if _stretch[i] != 1.0:
			var thin := 1.0 / sqrt(_stretch[i])
			shape *= Vector3(thin, _stretch[i], thin)
		var turned := Basis.from_euler(_turned[i])
		var slashing_arm: bool = _hands.values().has(_jiggles[i]) and _punching(_hands.find_key(_jiggles[i]))
		if slashing_arm and (_cock > 0.0 or _punch > 0.0):
			# The slash: the blade raised high over its own shoulder (wound up: further back the longer
			# it's held), then swept down and across the body to the far side. Left and right take
			# turns; the X swings both at once, crossing in front.
			var side: String = _hands.find_key(_jiggles[i])
			var s := 1.0 if side == "R" else -1.0
			var fwd: Vector3 = ((get_parent() as Node3D).call("forward") if get_parent().has_method("forward") else -global_basis.z)
			fwd = fwd.normalized()
			var right := fwd.cross(Vector3.UP).normalized()
			var wound := clampf(_cock - 1.0, 0.0, 0.5) * 2.0
			var raised := (Vector3.UP * 0.85 + right * s * 0.55 - fwd * (0.15 + 0.45 * wound)).normalized()
			var across := (fwd * 0.75 - right * s * 0.65 - Vector3.UP * 0.55).normalized()
			var sweep := 1.0 - pow(1.0 - _slash, 3.0) # (fast through the middle, slowing into the end)
			var dir := raised.slerp(across, sweep) if _punch > 0.0 else raised
			# (on through the whole sweep; once it's done, eased back to the run with the slash)
			var weight := minf(_cock, 1.0) if _punch <= 0.0 else (1.0 if _slash < 1.0 else _punch)
			var wy := -dir # (the blade hangs along -y)
			var wx := wy.cross(fwd if absf(wy.dot(fwd)) < 0.95 else Vector3.UP).normalized()
			var aim := (_parts[i].global_basis.orthonormalized().inverse() * Basis(wx, wy, wx.cross(wy))).orthonormalized()
			turned = Basis(Quaternion(turned.orthonormalized()).slerp(Quaternion(aim), weight))
		_jiggles[i].basis = turned * Basis.from_scale(shape) # (keeps the head's look)
	_springs_ready = true
	_draw_trail(delta)
	_draw_tubes()


## The tube muscles: each a bundle of chrome tubes from one part's mesh to the next, bowing out a
## little and thickest in the middle, like a muscle
func _draw_tubes() -> void:
	if _tube_view.get_parent() == null:
		var by_name := {}
		for i in _parts.size():
			by_name[String(_parts[i].name)] = _jiggles[i]
		for tube in TUBES:
			for s in ([-1.0, 1.0] if String(tube[2]).ends_with("_S") else [1.0]):
				var from: String = String(tube[0]).replace("_S", "_L" if s < 0.0 else "_R")
				var to: String = String(tube[2]).replace("_S", "_L" if s < 0.0 else "_R")
				if not by_name.has(from) or not by_name.has(to):
					continue
				var a: Vector3 = tube[1]
				var b: Vector3 = tube[3]
				# (Blender's x, y, z to the mesh's own: x, z, -y; the side mirrors x)
				_tube_links.append([by_name[from], Vector3(a.x * s, a.z, -a.y), by_name[to], Vector3(b.x * s, b.z, -b.y), tube[4], tube[5], tube[6]])
		_tube_view.mesh = _tube_mesh
		_tube_view.material_override = material
		_tube_view.top_level = true
		_tube_view.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		add_child(_tube_view)
	_tube_mesh.clear_surfaces()
	_tube_view.visible = not _tubes_hidden and not crystal
	if _tubes_hidden or _tube_links.is_empty():
		return
	var scale_now := global_basis.get_scale().x * MODEL_SCALE
	_tube_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for link in _tube_links:
		var a: Vector3 = (link[0] as Node3D).global_transform * (link[1] as Vector3)
		var b: Vector3 = (link[2] as Node3D).global_transform * (link[3] as Vector3)
		var along := b - a
		if along.length() < 0.01:
			continue
		var dir := along.normalized()
		var u := dir.cross(Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT).normalized()
		var v := dir.cross(u)
		var count: int = link[5]
		for k in count:
			var angle := TAU * k / count + 0.6
			var spread: Vector3 = (u * cos(angle) + v * sin(angle)) * float(link[6]) * scale_now
			_tube(a + spread * 0.5, b + spread * 0.5, spread.normalized() * along.length() * 0.12, float(link[4]) * scale_now)
	_tube_mesh.surface_end()


## One tube: from a to b, bowed out by bow at its middle, radius r (narrower at the ends)
func _tube(a: Vector3, b: Vector3, bow: Vector3, r: float) -> void:
	var rings: Array = []
	var frames: Array = []
	for i in TUBE_RINGS + 1:
		var t := float(i) / TUBE_RINGS
		var at := a.lerp(b, t) + bow * 4.0 * t * (1.0 - t)
		var tangent := (b - a) + bow * 4.0 * (1.0 - 2.0 * t)
		tangent = tangent.normalized()
		var side := tangent.cross(Vector3.UP if absf(tangent.y) < 0.95 else Vector3.RIGHT).normalized()
		var up := tangent.cross(side)
		var radius := r * (0.55 + 0.45 * sin(PI * t))
		var ring: Array = []
		var normals: Array = []
		for j in TUBE_SIDES:
			var angle := TAU * j / TUBE_SIDES
			var n := side * cos(angle) + up * sin(angle)
			ring.append(at + n * radius)
			normals.append(n)
		rings.append(ring)
		frames.append(normals)
	for i in TUBE_RINGS:
		for j in TUBE_SIDES:
			var n := (j + 1) % TUBE_SIDES
			for c in [[i, j], [i + 1, j], [i + 1, n], [i, j], [i + 1, n], [i, n]]:
				_tube_mesh.surface_set_normal(frames[c[0]][c[1]])
				_tube_mesh.surface_add_vertex(rings[c[0]][c[1]])


## The slash's trail: while a blade's sweeping, its path from partway up to the tip is laid down
## as a ribbon that fades out behind it
func _draw_trail(delta: float) -> void:
	if _trail_view.get_parent() == null:
		_trail_view.mesh = _trail_mesh
		_trail_view.top_level = true
		_trail_view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_trail_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_trail_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_trail_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_trail_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_trail_material.vertex_color_use_as_albedo = true
		add_child(_trail_view)
	_trail_material.albedo_color = trail_color
	for side in _hands:
		if not _trail_points.has(side):
			_trail_points[side] = []
		var points: Array = _trail_points[side]
		for p in points:
			p.age += delta
		while not points.is_empty() and points[0].age > TRAIL_LIFE:
			points.pop_front()
		if _punch > 0.0 and _slash < 1.0 and _punching(side):
			var arm: MeshInstance3D = _hands[side]
			var tip: Vector3 = arm.global_transform * _hand_tip
			var root: Vector3 = arm.global_transform * (_hand_tip * 0.68)
			points.append({ inner = root, outer = tip, age = 0.0 })
	_trail_mesh.clear_surfaces()
	for side in _trail_points:
		var points: Array = _trail_points[side]
		if points.size() < 2:
			continue
		_trail_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, _trail_material)
		for p in points:
			var fade: float = 1.0 - float(p.age) / TRAIL_LIFE
			_trail_mesh.surface_set_color(Color(1.0, 1.0, 1.0, 0.0))
			_trail_mesh.surface_add_vertex(p.inner)
			_trail_mesh.surface_set_color(Color(1.0, 1.0, 1.0, fade * fade * 0.75))
			_trail_mesh.surface_add_vertex(p.outer)
		_trail_mesh.surface_end()
