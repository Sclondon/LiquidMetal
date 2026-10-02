extends CharacterBody3D
## Mercury, the liquid-metal runner. It runs forward on its own; the input steers it, and
## swipes make it jump, sidestep or melt into a puddle to slide under things. Running
## head-on into something splats it, and it pulls itself back together a moment earlier.

signal splatted
signal dashed
signal drops_changed(total: int)

const GRAVITY := 42.0
const FAST_FALL := 2.6 # gravity multiplier when you swipe down in the air
const DODGE_DIST := 4.5
const DODGE_TIME := 0.2
const DUCK_TIME := 0.75
const SLIDE_LEAD := 0.28 # seconds in the slide pose (hop included) before melting into the puddle
const HOP_TIME := 0.24 # the hop into a slide (just the figure: the collider stays low)
const HOP_HEIGHT := 0.45
# The acrobatics for each move, one picked at random each time (never the same twice running):
# [axis in Mercury's frame, turns (negative: the other way; a dodge's direction flips it)]
const TRICKS := {
	jump = [
		[Vector3.RIGHT, -1.0], # front flip
		[Vector3.RIGHT, 1.0], # back flip
		[Vector3.RIGHT, -2.0], # double front flip
		[Vector3.BACK, 1.0], # side flip
		[Vector3(0.0, 0.8, 0.6), 1.5], # corkscrew
	],
	dash = [
		[Vector3.UP, 1.0], # twirl
		[Vector3.UP, 2.0], # double twirl
		[Vector3.UP, -1.0], # reverse twirl
		[Vector3.BACK, 1.0], # drill roll
	],
	dodge = [
		[Vector3.BACK, -1.0], # barrel roll, toward the dodge
		[Vector3.BACK, -2.0], # double barrel roll
		[Vector3(0.0, 0.45, 0.9), -1.0], # cartwheel
		[Vector3.UP, -1.0], # spin
	],
}
const STAND := { radius = 0.5, height = 1.3 }
const PUDDLE := { radius = 0.3, height = 0.6 }
const BLOB_RADIUS := 0.55
const RESPAWN_DELAY := 0.9
const REWIND := 1.2 # seconds back along your path a splat sends you
const DASH_BOOST := 2.2 # times run speed
const DASH_TIME := 0.35
const DASH_COOLDOWN := 1.2

# Tunables (the HUD's tuning panel changes these live)
var run_speed := 14.0
var turn_rate := 110.0 # degrees a second at full hold
var jump_height := 2.2

var input: Node # RunnerInput
var heading := 0.0 # yaw; 0 runs toward -Z
var steer := 0.0 # smoothed turn input, -1..1
var drops := 0
var ducking := false
var dead := false
var dash_cooldown := 0.0 # seconds until the next dash (the HUD's button shows it)

var _dodge_left := 0.0
var _dodge_dir := 0.0
var _dash_left := 0.0
var _drip_clock := 0.0
var _slide_clock := 0.0 # how long it's been ducking
var _liquid_hold := 0.0
var _puddle_splash := 0.0 # the big puddle's ripple, kicked up as each part's puddle joins it # seconds more to stay as balls of liquid after a move
var _duck_left := 0.0
var _fast_fall := false
var _was_on_floor := true
var _squash := 0.0 # landing / pickup squish, decays
var _agitation := 0.0
var _history: Array = [] # [position, heading] on the floor, every 0.1 s
var _sample_clock := 0.0
var _spawn := Transform3D.IDENTITY

var _shape := CapsuleShape3D.new()
var _collider := CollisionShape3D.new()
var _blob := MeshInstance3D.new() # the puddle it melts into
var _material := ShaderMaterial.new()
var _figure := preload("res://scripts/mercury_model.gd").new()
var _figure_material := ShaderMaterial.new()
var _droplets := preload("res://scripts/droplets.gd").new()
# True reflections: a probe riding along with Mercury, re-capturing the scene every frame
# (Mercury itself is on its own render layer, which the probe leaves out)
const OWN_LAYER := 2
var _probe := ReflectionProbe.new()
var real_reflections := can_reflect()
var _trail := preload("res://scripts/trail.gd").new()
var _feet := CPUParticles3D.new() # metal splashing up at its feet as it runs
# A flip or twirl in progress: the axis (in Mercury's own frame), the turn, how long, how far in
var _spin_axis := Vector3.RIGHT
var _spin_turn := 0.0
var _spin_time := 1.0
var _spin_left := 0.0
var _last_trick := {}
var _hop_left := 0.0
var _melt := 0.0 # 0 = Mercury standing, 1 = a puddle (ducking, or pulling back together)
var _splash := CPUParticles3D.new()


func _ready() -> void:
	floor_snap_length = 0.35
	floor_max_angle = deg_to_rad(50.0)
	_collider.shape = _shape
	add_child(_collider)
	_set_shape(STAND)

	var sphere := SphereMesh.new()
	sphere.radius = BLOB_RADIUS
	sphere.height = BLOB_RADIUS * 2.0
	sphere.radial_segments = 48
	sphere.rings = 24
	_blob.mesh = sphere
	_material.shader = preload("res://shaders/liquid_metal.gdshader")
	_blob.material_override = _material
	_blob.visible = false
	add_child(_blob)

	_figure_material.shader = _material.shader
	_figure_material.set_shader_parameter("ripple", 0.35) # facets: only a shimmer
	# (the same dusk-lit liquid metal as the drops you collect)
	_figure.material = _figure_material
	add_child(_figure)

	# Droplets thrown out by a splat
	var drop := SphereMesh.new()
	drop.radius = 0.09
	drop.height = 0.18
	drop.radial_segments = 8
	drop.rings = 4
	drop.material = _material
	_splash.mesh = drop
	_splash.emitting = false
	_splash.one_shot = true
	_splash.amount = 48
	_splash.lifetime = 0.9
	_splash.explosiveness = 1.0
	_splash.direction = Vector3.UP
	_splash.spread = 75.0
	_splash.initial_velocity_min = 4.0
	_splash.initial_velocity_max = 9.0
	_splash.gravity = Vector3(0, -GRAVITY * 0.6, 0)
	_splash.scale_amount_min = 0.5
	_splash.scale_amount_max = 1.6
	_splash.local_coords = false
	_splash.position.y = 0.5
	add_child(_splash)

	# Blobs that flop off as it moves and rejoin it
	_droplets.material = _figure_material
	_droplets.source = self
	add_child(_droplets)
	_droplets.parts = _figure.parts()
	_droplets.rejoined.connect(func(part): _figure.ripple(part, 0.7))
	_figure.pooled.connect(func(): _puddle_splash = 1.0)
	_material.set_shader_parameter("splash_up", true)
	_material.set_shader_parameter("splash_strength", 0.5) # the puddle's squashed flat: ripple hard

	_trail.material = _figure_material
	add_child(_trail)

	var splash := SphereMesh.new()
	splash.radius = 0.05
	splash.height = 0.1
	splash.radial_segments = 6
	splash.rings = 3
	splash.material = _figure_material
	_feet.mesh = splash
	_feet.amount = 40
	_feet.lifetime = 0.45
	_feet.local_coords = false
	_feet.emitting = false
	_feet.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_feet.emission_box_extents = Vector3(0.25, 0.02, 0.25)
	_feet.direction = Vector3(0, 1, 0.6) # up and back (Mercury runs toward -Z)
	_feet.spread = 35.0
	_feet.initial_velocity_min = 2.0
	_feet.initial_velocity_max = 4.5
	_feet.gravity = Vector3(0, -GRAVITY * 0.7, 0)
	_feet.scale_amount_min = 0.5
	_feet.scale_amount_max = 1.4
	_feet.position.y = 0.05
	add_child(_feet)

	_probe.size = Vector3(90.0, 30.0, 90.0)
	_probe.position = Vector3(0.0, 1.2, 0.0)
	_probe.update_mode = ReflectionProbe.UPDATE_ALWAYS
	_probe.max_distance = 140.0
	_probe.cull_mask = 0xFFFFF & ~(1 << (OWN_LAYER - 1))
	_probe.ambient_mode = ReflectionProbe.AMBIENT_DISABLED
	add_child(_probe)
	_own_layer(self)
	set_real_reflections(real_reflections)

	input.jump.connect(_on_jump)
	input.duck.connect(_on_duck)
	input.dodge.connect(_on_dodge)
	input.dash.connect(_on_dash)


## Live reflection probes need the Forward+ / Mobile renderers: the web build (Compatibility)
## can't, and keeps the painted horizon
static func can_reflect() -> bool:
	return RenderingServer.get_current_rendering_method() != "gl_compatibility"


## Mirror the real scene (a reflection probe) or just the painted horizon (cheaper)
func set_real_reflections(on: bool) -> void:
	on = on and can_reflect()
	real_reflections = on
	_probe.visible = on
	var amount := 1.0 if on else 0.0
	_figure.set_shader("real_reflection", amount)
	_material.set_shader_parameter("real_reflection", amount)


## Mercury and everything it's made of on its own render layer (the probe doesn't see it)
func _own_layer(node: Node) -> void:
	if node is VisualInstance3D and node != _probe:
		node.layers = 1 << (OWN_LAYER - 1)
	for child in node.get_children():
		_own_layer(child)


func forward() -> Vector3:
	return Vector3(-sin(heading), 0.0, -cos(heading))


func right() -> Vector3:
	return Vector3(cos(heading), 0.0, -sin(heading))


## Put the blob at a spot, facing along `facing` (radians), and remember it as the start
func place(spot: Vector3, facing: float) -> void:
	_spawn = Transform3D(Basis(Vector3.UP, facing), spot)
	_respawn_at(spot, facing)
	_history.clear()


func restart() -> void:
	_history.clear()
	_respawn_at(_spawn.origin, _spawn.basis.get_euler().y)


func collect_drop() -> void:
	drops += 1
	_squash = maxf(_squash, 0.18)
	drops_changed.emit(drops)


func _on_jump() -> void:
	if dead:
		return
	if is_on_floor():
		_set_ducking(false)
		if ducking:
			return # wedged under something: no room to spring up
		velocity.y = sqrt(2.0 * GRAVITY * jump_height)
		_squash = -0.25 # a stretch on take-off
		_agitation = 1.0
		_liquid_hold = 0.2
		_droplets.burst(3)
		_trick("jump", 1.0, 0.6)


func _on_duck() -> void:
	if dead:
		return
	_duck_left = DUCK_TIME
	if is_on_floor():
		if not ducking:
			_hop_left = HOP_TIME # a little hop up into the slide
		_set_ducking(true)
	else:
		_fast_fall = true # dive down, then puddle on landing


func _on_dodge(direction: float) -> void:
	if dead:
		return
	_dodge_dir = direction
	_dodge_left = DODGE_TIME
	_trick("dodge", direction, 0.34)
	_agitation = 1.0
	_liquid_hold = 0.3
	_droplets.burst(3, 0.8)


## Pick one of the move's acrobatics (side: a dodge's direction) and start it
func _trick(move: String, side: float, time: float) -> void:
	var options: Array = TRICKS[move]
	var pick := randi() % options.size()
	if options.size() > 1 and pick == _last_trick.get(move, -1):
		pick = (pick + 1 + randi() % (options.size() - 1)) % options.size()
	_last_trick[move] = pick
	var trick: Array = options[pick]
	_spin((trick[0] as Vector3).normalized(), trick[1] * side * TAU, time)


func _spin(axis: Vector3, turn: float, time: float) -> void:
	_spin_axis = axis
	_spin_turn = turn
	_spin_time = time
	_spin_left = time


func is_dashing() -> bool:
	return _dash_left > 0.0


## A burst of speed straight ahead, then a cooldown
func _on_dash() -> void:
	if dead or dash_cooldown > 0.0:
		return
	_dash_left = DASH_TIME
	dash_cooldown = DASH_COOLDOWN
	_agitation = 1.0
	_liquid_hold = DASH_TIME + 0.1
	_trick("dash", 1.0, DASH_TIME + 0.05)
	_droplets.burst(6, 1.3)
	dashed.emit()


func _physics_process(delta: float) -> void:
	if dead:
		return
	steer = move_toward(steer, input.turn, delta * 7.0)
	heading -= steer * deg_to_rad(turn_rate) * delta

	var sideways := 0.0
	if _dodge_left > 0.0:
		var step := minf(delta, _dodge_left)
		sideways = _dodge_dir * DODGE_DIST / DODGE_TIME * step / delta
		_dodge_left -= delta

	if not is_on_floor():
		velocity.y -= GRAVITY * (FAST_FALL if _fast_fall else 1.0) * delta
	dash_cooldown = maxf(dash_cooldown - delta, 0.0)
	var speed := run_speed
	if _dash_left > 0.0:
		speed *= DASH_BOOST
		_dash_left -= delta
	var ground := forward() * speed + right() * sideways
	velocity.x = ground.x
	velocity.z = ground.z
	move_and_slide()

	# Head-on into something: splat (glancing blows just slide along it)
	for i in get_slide_collision_count():
		var hit := get_slide_collision(i)
		var normal := hit.get_normal()
		if normal.y < 0.5 and normal.dot(forward()) < -0.6:
			_splat()
			return
	if global_position.y < -15.0:
		_splat()
		return

	var on_floor := is_on_floor()
	if on_floor and not _was_on_floor:
		_squash = 0.3
		_droplets.burst(5)
		_agitation = 1.0
		_fast_fall = false
		if _duck_left > 0.0:
			_set_ducking(true)
	_was_on_floor = on_floor

	# Melt back up once the duck runs out, unless there's something overhead
	if ducking:
		_duck_left -= delta
		var held := Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)
		if _duck_left <= 0.0 and not held:
			_set_ducking(false)

	_sample_clock += delta
	if on_floor and _sample_clock >= 0.1:
		_sample_clock = 0.0
		_history.append([global_position, heading])
		if _history.size() > 40:
			_history.pop_front()


func _process(delta: float) -> void:
	_squash = move_toward(_squash, 0.0, delta * 1.6)
	_agitation = move_toward(_agitation, absf(steer) * 0.35, delta * 2.0)
	_material.set_shader_parameter("agitation", _agitation)
	_figure_material.set_shader_parameter("agitation", _agitation)
	if dead:
		return

	# Melts down fast (ducking has to be quick), pulls itself back up a little slower
	# A duck slides first, then melts
	_slide_clock = _slide_clock + delta if ducking else 0.0
	var puddle := ducking and _slide_clock > SLIDE_LEAD
	# (each part melts in turn, so this runs over ~0.4 s)
	_melt = move_toward(_melt, 1.0 if puddle else 0.0, delta * (2.6 if puddle else 3.0))
	var melt := smoothstep(0.0, 1.0, _melt)

	# Mercury: stretched by vertical speed in the air, squished on landing, flattening as it melts
	var stretch := Vector3.ONE
	if not is_on_floor():
		var s := clampf(velocity.y / 30.0, -0.2, 0.25)
		stretch = Vector3(1.0 - s * 0.5, 1.0 + s, 1.0 - s * 0.5)
	stretch *= Vector3(1.0 + _squash * 0.5, 1.0 - _squash * 0.8, 1.0 + _squash * 0.5)
	if is_dashing():
		stretch *= Vector3(0.88, 0.92, 1.35) # drawn out along the dash
	_figure.visible = melt < 0.99
	# Faces the way it's going, leaning into sidesteps (the model leans into turns itself), and
	# flipping or twirling about its middle during a move
	var lean := -(_dodge_dir * 0.35 if _dodge_left > 0.0 else 0.0)
	var spin := Basis.IDENTITY
	if _spin_left > 0.0:
		_spin_left = maxf(_spin_left - delta, 0.0)
		spin = Basis(_spin_axis, _spin_turn * smoothstep(0.0, 1.0, 1.0 - _spin_left / _spin_time))
	var turn := Basis(Vector3.UP, heading) * spin * Basis(Vector3.BACK, lean)
	var middle := Vector3.UP * 0.9
	var hop := 0.0
	if _hop_left > 0.0:
		_hop_left = maxf(_hop_left - delta, 0.0)
		hop = sin(PI * (1.0 - _hop_left / HOP_TIME)) * HOP_HEIGHT
	_figure.transform = Transform3D(turn * Basis.from_scale(stretch.lerp(Vector3.ONE, melt)), middle - turn * middle + Vector3.UP * hop)
	_figure.set_puddle(_melt) # the parts melt into puddles one by one
	_figure.animate(delta, run_speed * (DASH_BOOST if is_dashing() else 1.0), not is_on_floor(), velocity.y, steer, ducking)
	# Jumping, dashing or dodging, every part turns into a ball of liquid; back to shards after
	_liquid_hold = maxf(_liquid_hold - delta, 0.0)
	var liquid := not is_on_floor() or is_dashing() or _liquid_hold > 0.0
	_figure.set_liquid(1.0 if liquid else 0.0, delta)

	# Now and then, running, a blob or two shakes loose
	_drip_clock -= delta
	if _drip_clock <= 0.0 and is_on_floor() and melt < 0.1:
		_drip_clock = randf_range(0.15, 0.45)
		_droplets.burst(randi_range(1, 2), 0.7)

	# Splashing at its feet while it runs on the ground, and a track under each foot
	var running := is_on_floor() and melt < 0.5 and not dead
	_feet.emitting = running
	_feet.rotation.y = heading
	var ground := global_position.y if is_on_floor() else NAN
	if melt > 0.5:
		# A puddle smears one wide track along under its middle
		var under: Array[Vector3] = [global_position]
		_trail.step(under, ground, 0.9, delta)
	else:
		_trail.step(_figure.feet(), ground, 0.16, delta)

	# The puddle swells as Mercury sinks into it
	# (once the parts' puddles have slid in together)
	var pooled := smoothstep(0.55, 1.0, _melt)
	_blob.visible = pooled > 0.03
	_puddle_splash = move_toward(_puddle_splash, 0.0, delta * 1.2)
	_material.set_shader_parameter("splash", _puddle_splash)
	_blob.scale = Vector3(1.7, 0.3, 1.7) * maxf(pooled, 0.01)
	_blob.position.y = BLOB_RADIUS * _blob.scale.y
	_blob.rotation = Vector3(0.0, heading, lean)


func _set_shape(size: Dictionary) -> void:
	_shape.radius = size.radius
	_shape.height = size.height
	_collider.position.y = size.height * 0.5


func _set_ducking(on: bool) -> void:
	if on == ducking:
		return
	if not on and not _room_to_stand():
		return
	ducking = on
	_set_shape(PUDDLE if on else STAND)
	_agitation = 1.0


func _room_to_stand() -> bool:
	var probe := CapsuleShape3D.new()
	probe.radius = STAND.radius - 0.05
	probe.height = STAND.height - 0.1
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = probe
	query.transform = Transform3D(Basis.IDENTITY, global_position + Vector3.UP * (STAND.height * 0.5 + 0.05))
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


func _splat() -> void:
	dead = true
	velocity = Vector3.ZERO
	_blob.visible = false
	_figure.visible = false
	_splash.restart()
	_droplets.clear()
	_trail.lift() # break the tracks where it splatted
	_feet.emitting = false
	_spin_left = 0.0
	splatted.emit()
	var back := clampi(_history.size() - int(REWIND / 0.1), 0, _history.size())
	var spot: Vector3 = _spawn.origin
	var facing: float = _spawn.basis.get_euler().y
	if back < _history.size():
		spot = _history[back][0]
		facing = _history[back][1]
		_history.resize(back + 1)
	get_tree().create_timer(RESPAWN_DELAY).timeout.connect(_respawn_at.bind(spot, facing))


func _respawn_at(spot: Vector3, facing: float) -> void:
	global_position = spot
	heading = facing
	steer = 0.0
	velocity = Vector3.ZERO
	_dodge_left = 0.0
	_duck_left = 0.0
	_fast_fall = false
	ducking = false
	_set_shape(STAND)
	reset_physics_interpolation()
	dead = false
	# Pulls itself back together out of a puddle
	_melt = 1.0
	_dash_left = 0.0
	dash_cooldown = 0.0
	_droplets.clear()
	_agitation = 1.0
