extends CharacterBody3D
## Mercury, the liquid-metal runner. It runs forward on its own; the input steers it, and
## swipes make it jump, sidestep or melt into a puddle to slide under things. Running
## head-on into something splats it, and it pulls itself back together a moment earlier.

signal splatted
signal dashed
signal boosted
signal drops_changed(total: int)

const GRAVITY := 42.0
const FAST_FALL := 2.6 # gravity multiplier when you swipe down in the air
const DODGE_DIST := 4.5
const DODGE_TIME := 0.2
const DUCK_TIME := 0.75
# Wall running: touch a wall in the air (jump, then dodge into it) and it runs along it, feet on
# the wall, sinking slowly; jump to kick off it; it drops off when the wall ends or time runs out
const WALL_RUN_MAX := 1.6
const WALL_GRAVITY := 0.12 # of normal gravity, while on the wall
const WALL_LIFT := 2.5 # m/s up as it catches the wall
var wall_running := false
var _wall_normal := Vector3.ZERO # out of the wall
var _wall_time := 0.0
var _wall_lost := 0.0 # seconds without touching the wall (a short grace before dropping off)
var _wall_cooldown := 0.0
var _wall_roll := 0.0 # the figure turned onto its side, smoothed
var _wall_tween: Tween # the puddle splatted against something
var _arm_puddles: Array[MeshInstance3D] = []
var _dabs: Array[MeshInstance3D] = [] # little puddles left at the landing's contact points
var _support := 0.0 # the hand down on a sharp turn, smoothed
var _dab_hand := 0.0 # seconds till the landing hand's puddle # the arms, splatting a beat after the body
var _since_dodge := 99.0 # seconds since a dodge began (and which way: _dodge_dir)
const JUMP_BUFFER := 0.2 # seconds a jump pressed in the air is kept for the landing
# The slide: a quick hop, then SPLAT, the whole figure squashed flat into one puddle that skims
# along the floor, wobbling, eyes glinting at the front; then it pops back up out of it, tall
const HOP_TIME := 0.16 # the hop into a slide (just the figure: the collider is already low)
const HOP_HEIGHT := 0.32
const SPLAT_RATE := 11.0 # figure -> puddle: flattens in about a tenth of a second
const POP_RATE := 7.0 # puddle -> figure
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
const BOOST := 10.0 # m/s a boost pad adds

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
var rewind_on_splat := true # false (endless mode): a splat ends the run, no coming back
var dash_cooldown := 0.0
var speed := 0.0 # actual speed: builds up to run_speed (the legs pump hard getting there)
const ACCELERATION := 9.0 # m/s per second
var _pool_size := 0.0 # the puddle's size, on a wobbly spring
var _pool_velocity := 0.0 # seconds until the next dash (the HUD's button shows it)

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
var _puddle_eyes: Array[MeshInstance3D] = []
var _puddled := false # flat as a puddle (past the splat)
var _clock := 0.0
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
# Metal splashing up at each foot while it's on the ground: carried along with Mercury (local
# coordinates) and short-lived, so it stays at the feet instead of trailing off behind
var _foot_splash: Array[CPUParticles3D] = []
# A flip or twirl in progress: the axis (in Mercury's own frame), the turn, how long, how far in
var _spin_axis := Vector3.RIGHT
var _spin_turn := 0.0
var _spin_time := 1.0
var _spin_left := 0.0
var _last_trick := {}
var _hop_left := 0.0
var _jump_buffer := 0.0
# The splat on landing: particles of metal thrown up and out from the feet, and skittering along the floor
var _land_spray := CPUParticles3D.new()
var _land_skid := CPUParticles3D.new()
const LAND_HOLD := 0.73 # the superhero landing: held 0.4 s, then 0.33 s stepping out of it
const LAND_PLANTED := 0.4 # the part with the hand and knee down
var _land_hold := 0.0
var _air_time := 0.0
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
	# Its eyes glint at the front of the puddle
	var eye_material := StandardMaterial3D.new()
	eye_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	eye_material.albedo_color = Color(1.0, 0.1, 0.08)
	for side in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var eye_mesh := BoxMesh.new()
		eye_mesh.size = Vector3(0.12, 0.025, 0.04)
		eye.mesh = eye_mesh
		eye.material_override = eye_material
		eye.visible = false
		eye.set_meta("side", side)
		add_child(eye)
		_puddle_eyes.append(eye)

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
	_material.set_shader_parameter("splash_strength", 0.1)

	_trail.material = _figure_material
	add_child(_trail)

	var splash := SphereMesh.new()
	splash.radius = 0.035
	splash.height = 0.07
	splash.radial_segments = 6
	splash.rings = 3
	splash.material = _figure_material
	for f in 2:
		var spray := CPUParticles3D.new()
		spray.mesh = splash
		spray.amount = 14
		spray.lifetime = 0.28
		spray.local_coords = true
		spray.emitting = false
		spray.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		spray.emission_sphere_radius = 0.08
		spray.direction = Vector3(0, 1, 0.35)
		spray.spread = 50.0
		spray.initial_velocity_min = 1.2
		spray.initial_velocity_max = 2.8
		spray.gravity = Vector3(0, -GRAVITY * 0.6, 0)
		spray.scale_amount_min = 0.4
		spray.scale_amount_max = 1.1
		add_child(spray)
		_foot_splash.append(spray)

	_land_spray.mesh = splash
	_land_spray.amount = 44
	_land_spray.lifetime = 0.55
	_land_spray.one_shot = true
	_land_spray.explosiveness = 1.0
	_land_spray.emitting = false
	_land_spray.local_coords = false
	_land_spray.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	_land_spray.emission_ring_axis = Vector3.UP
	_land_spray.emission_ring_radius = 0.35
	_land_spray.emission_ring_inner_radius = 0.2
	_land_spray.emission_ring_height = 0.0
	_land_spray.direction = Vector3.UP
	_land_spray.spread = 70.0
	_land_spray.initial_velocity_min = 3.0
	_land_spray.initial_velocity_max = 6.5
	_land_spray.gravity = Vector3(0, -GRAVITY * 0.8, 0)
	_land_spray.scale_amount_min = 0.7
	_land_spray.scale_amount_max = 1.8
	_land_spray.position.y = 0.05
	add_child(_land_spray)
	# ...and a burst skittering out low along the floor all round
	_land_skid.mesh = splash
	_land_skid.amount = 36
	_land_skid.lifetime = 0.45
	_land_skid.one_shot = true
	_land_skid.explosiveness = 1.0
	_land_skid.emitting = false
	_land_skid.local_coords = false
	_land_skid.direction = Vector3(1, 0.15, 0)
	_land_skid.spread = 180.0
	_land_skid.flatness = 0.9 # fanned out flat, every way round
	_land_skid.initial_velocity_min = 4.0
	_land_skid.initial_velocity_max = 8.0
	_land_skid.damping_min = 6.0
	_land_skid.damping_max = 10.0
	_land_skid.gravity = Vector3(0, -GRAVITY * 0.5, 0)
	_land_skid.scale_amount_min = 0.5
	_land_skid.scale_amount_max = 1.3
	_land_skid.position.y = 0.06
	add_child(_land_skid)

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
	# (only partly for the puddle: lying flat it would mirror nothing but the dark floor and vanish)
	_material.set_shader_parameter("real_reflection", amount * 0.35)


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


func reset_drops() -> void:
	drops = 0
	drops_changed.emit(drops)


func collect_drop() -> void:
	drops += 1
	_squash = maxf(_squash, 0.18)
	drops_changed.emit(drops)


func _on_jump() -> void:
	if dead:
		return
	if wall_running:
		# Kick off the wall: up, and a dodge away from it
		_end_wall_run()
		velocity.y = sqrt(2.0 * GRAVITY * jump_height)
		_dodge_dir = signf(_wall_normal.dot(right()))
		_dodge_left = DODGE_TIME
		_agitation = 1.0
		_droplets.burst(4)
		_trick("jump", 1.0, 0.6)
		return
	if not is_on_floor():
		_jump_buffer = JUMP_BUFFER # pressed just before landing: jump as it touches down
		return
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
	_since_dodge = 0.0
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


func _end_wall_run() -> void:
	wall_running = false
	_wall_cooldown = 0.35


## A boost pad: shot forward, the speed kicked up and easing back down to running speed
func boost() -> void:
	if dead:
		return
	speed = maxf(speed, run_speed) + BOOST
	_agitation = 1.0
	_droplets.burst(5, 1.3)
	boosted.emit()


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

	if wall_running:
		velocity.y -= GRAVITY * WALL_GRAVITY * delta
	elif not is_on_floor():
		velocity.y -= GRAVITY * (FAST_FALL if _fast_fall else 1.0) * delta
	_wall_cooldown = maxf(_wall_cooldown - delta, 0.0)
	_since_dodge += delta
	dash_cooldown = maxf(dash_cooldown - delta, 0.0)
	# Builds back up to running speed (sliding as a puddle and landing hard slow it)
	speed = move_toward(speed, run_speed, ACCELERATION * delta) # (a slide keeps its speed)
	var going := speed
	if _dash_left > 0.0:
		going *= DASH_BOOST
		_dash_left -= delta
	var ground := forward() * going + right() * sideways
	if wall_running:
		ground -= _wall_normal * 2.0 # pressed against the wall, to stay on it
	velocity.x = ground.x
	velocity.z = ground.z
	move_and_slide()

	# Head-on into something: splat (glancing blows just slide along it). A wall alongside, in
	# the air, is one to run on.
	var side_wall := Vector3.ZERO
	for i in get_slide_collision_count():
		var hit := get_slide_collision(i)
		var normal := hit.get_normal()
		if normal.y < 0.5 and normal.dot(forward()) < -0.6:
			_splat(hit.get_position(), normal)
			return
		if absf(normal.y) < 0.3 and absf(normal.dot(forward())) < 0.5:
			side_wall = Vector3(normal.x, 0.0, normal.z).normalized()
	if wall_running:
		_wall_time += delta
		if side_wall != Vector3.ZERO:
			_wall_normal = side_wall
			_wall_lost = 0.0
		else:
			_wall_lost += delta
		if is_on_floor() or _wall_lost > 0.12 or _wall_time > WALL_RUN_MAX:
			_end_wall_run()
	elif side_wall != Vector3.ZERO and _since_dodge < 0.45 and _dodge_dir == -signf(side_wall.dot(right())) and _wall_cooldown <= 0.0 and not ducking:
		# (only from a side dodge into the wall)
		wall_running = true
		_wall_normal = side_wall
		_wall_time = 0.0
		_wall_lost = 0.0
		_fast_fall = false
		_dodge_left = 0.0
		velocity.y = maxf(velocity.y, WALL_LIFT)
		_agitation = 1.0
		_droplets.burst(5)
	if global_position.y < -15.0:
		_splat()
		return

	var on_floor := is_on_floor()
	_jump_buffer = maxf(_jump_buffer - delta, 0.0)
	if on_floor and not _was_on_floor and _jump_buffer > 0.0:
		_jump_buffer = 0.0
		_was_on_floor = true
		_on_jump()
		return
	_air_time = 0.0 if on_floor and _was_on_floor else _air_time + delta
	if on_floor and not _was_on_floor:
		if _air_time > 0.35: # a real jump, not a bump: the superhero landing
			_land_hold = LAND_HOLD
			_figure.land_side = "R" if randf() < 0.5 else "L"
			# Little puddles where it touches down: both feet, then the hand
			var feet := _figure.feet()
			for f in feet.size():
				_dab(feet[f], f)
			_dab_hand = 0.12
			speed *= 0.6 # the landing costs speed: pump back up
		_land_splat()
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

	_clock += delta
	# The slide: hop, then splat flat; up again when the duck's done
	_slide_clock = _slide_clock + delta if ducking else 0.0
	var puddle := ducking and _slide_clock > HOP_TIME * 0.8
	_melt = move_toward(_melt, 1.0 if puddle else 0.0, delta * (SPLAT_RATE if puddle else POP_RATE))
	var melt := _melt * _melt # eases in: slow to start, then slapped flat
	if _melt > 0.7 and not _puddled:
		# The puddle spreads out under him (with a little overshoot), while he holds the dive
		_puddled = true
		_pool_velocity += 2.5
		_puddle_splash = 1.0
	elif _melt < 0.3 and _puddled:
		# Back up out of the dive, a few drops flung off
		_puddled = false
		_squash = -0.2
		_droplets.burst(3, 0.8)

	# Mercury: stretched by vertical speed in the air, squished on landing, flattening as it melts
	var stretch := Vector3.ONE
	if not is_on_floor():
		var s := clampf(velocity.y / 30.0, -0.2, 0.25)
		stretch = Vector3(1.0 - s * 0.5, 1.0 + s, 1.0 - s * 0.5)
	stretch *= Vector3(1.0 + _squash * 0.5, 1.0 - _squash * 0.8, 1.0 + _squash * 0.5)
	if is_dashing():
		stretch *= Vector3(0.88, 0.92, 1.35) # drawn out along the dash
	_figure.visible = true
	# Faces the way it's going, leaning into sidesteps (the model leans into turns itself), and
	# flipping or twirling about its middle during a move
	var lean := -(_dodge_dir * 0.35 if _dodge_left > 0.0 else 0.0)
	var spin := Basis.IDENTITY
	if _spin_left > 0.0:
		_spin_left = maxf(_spin_left - delta, 0.0)
		spin = Basis(_spin_axis, _spin_turn * smoothstep(0.0, 1.0, 1.0 - _spin_left / _spin_time))
	# On a wall: turned onto its side, feet on the wall and body standing out from it
	var wall_side := signf(_wall_normal.dot(right())) # +1: the wall's on the left
	_wall_roll = lerpf(_wall_roll, wall_side * 1.25 if wall_running else 0.0, 1.0 - exp(-delta * 14.0))
	var turn := Basis(Vector3.UP, heading) * spin * Basis(Vector3.BACK, lean + _wall_roll)
	var middle := Vector3.UP * 0.9
	var hop := 0.0
	if _hop_left > 0.0:
		_hop_left = maxf(_hop_left - delta, 0.0)
		hop = sin(PI * (1.0 - _hop_left / HOP_TIME)) * HOP_HEIGHT
	# Splatting: squashed flat and spread wide, about its feet (so it stays on the floor)
	var flat := Vector3(1.0, 1.0 - melt * 0.25, 1.0) # held low in the dive
	var body := turn * Basis.from_scale(stretch * flat)
	var pivot := middle.lerp(Vector3.ZERO, maxf(melt, absf(_wall_roll) / 1.25))
	_figure.transform = Transform3D(body, pivot - body * pivot + Vector3.UP * hop * (1.0 - melt))
	_figure.animate(delta, run_speed * (DASH_BOOST if is_dashing() else 1.0), not is_on_floor() and not wall_running, velocity.y, steer, ducking, _land_hold > 0.0 and not ducking, clampf(1.0 - speed / maxf(run_speed, 0.1), 0.0, 1.0))
	_land_hold = maxf(_land_hold - delta, 0.0)
	# Jumping, dashing or dodging, every part turns into a ball of liquid; back to shards after
	_liquid_hold = maxf(_liquid_hold - delta, 0.0)
	var liquid := (not is_on_floor() and not wall_running) or is_dashing() or _liquid_hold > 0.0
	_figure.set_liquid(1.0 if liquid else 0.0, delta)

	# Now and then, running, a blob or two shakes loose
	_drip_clock -= delta
	if _drip_clock <= 0.0 and is_on_floor() and melt < 0.1:
		_drip_clock = randf_range(0.15, 0.45)
		_droplets.burst(randi_range(1, 2), 0.7)

	# Splashing at its feet while it runs on the ground, and a track under each foot
	var running := is_on_floor() and melt < 0.5 and not dead
	var foot_spots := _figure.feet()
	for f in mini(foot_spots.size(), _foot_splash.size()):
		var spray := _foot_splash[f]
		var at := to_local(foot_spots[f])
		spray.position = Vector3(at.x, 0.05, at.z)
		spray.rotation.y = heading
		spray.emitting = running and foot_spots[f].y - global_position.y < 0.15 # only while it's down
	var ground := global_position.y if is_on_floor() else NAN
	if melt > 0.5:
		# A puddle smears one wide track along under its middle
		# (laid from under the back of the puddle, so its front end never shows ahead of it)
		var under: Array[Vector3] = [global_position - forward() * 0.6]
		_trail.step(under, ground, 0.55, delta)
	else:
		var contacts := _figure.feet()
		var width := 0.16
		# The landing puddles carried along under what made them
		var feet_now := _figure.feet()
		for dab in _dabs:
			var follow: int = dab.get_meta("follow", -1)
			if dab.visible and follow >= 0:
				var at: Vector3 = _figure.hand() if follow == 2 else feet_now[mini(follow, feet_now.size() - 1)]
				dab.global_position = Vector3(at.x, global_position.y + 0.01, at.z)
		if _dab_hand > 0.0:
			_dab_hand -= delta
			if _dab_hand <= 0.0:
				_dab(_figure.hand(), 2)
		# A sharp turn at speed: the inside hand down on the floor, holding it up
		var sharp := absf(steer) > 0.85 and is_on_floor() and speed > 8.0 and _land_hold <= 0.0 and not ducking
		_support = move_toward(_support, 1.0 if sharp else 0.0, delta * 5.0)
		_figure.turn_support = _support
		if _support > 0.6:
			var hand := _figure.hand("R" if steer > 0.0 else "L")
			contacts.append(Vector3(hand.x, global_position.y, hand.z))
			for c in contacts.size():
				contacts[c].y = global_position.y
		if _land_hold > LAND_HOLD - LAND_PLANTED and is_on_floor():
			# The superhero landing: both feet and the hand planted, three tracks dragged along the
			# floor (pinned down: in the pose they hover just off it, which would break them up)
			contacts.append(_figure.hand())
			for c in contacts.size():
				contacts[c].y = global_position.y
			width = 0.24
		_trail.step(contacts, ground, width, delta)

	# The puddle: one long drop of metal skimming along, on a wobbly spring (it overshoots on the
	# splat and as it gathers back up), stretched out the faster it goes
	var pooled_target := 1.0 if _puddled else 0.0
	# (stepped in small fixed slices: a stiff spring blows up on a long frame otherwise)
	var left := delta
	while left > 0.0:
		var step := minf(left, 1.0 / 240.0)
		left -= step
		_pool_velocity += ((pooled_target - _pool_size) * 300.0 - _pool_velocity * 10.0) * step
		_pool_size = maxf(_pool_size + _pool_velocity * step, 0.0)
	var pooled := minf(_pool_size, 1.3)
	var wobble := clampf((_pool_size - pooled_target) * 1.2, -0.5, 0.5) # past full: thinner and wider; short: taller
	var ripple := sin(_clock * 15.0) * 0.05 * pooled
	_blob.visible = pooled > 0.03
	_puddle_splash = move_toward(_puddle_splash, 0.0, delta * 1.2)
	_material.set_shader_parameter("splash", _puddle_splash)
	var long := 1.0 + clampf(speed / 20.0, 0.0, 1.0) * 0.8
	_blob.scale = Vector3(1.25 * (1.0 + wobble * 0.5 + ripple), 0.32 * maxf(1.0 - wobble - ripple, 0.3), 1.4 * long * (1.0 + wobble * 0.3 - ripple)) * maxf(pooled, 0.01)
	_blob.position.y = BLOB_RADIUS * _blob.scale.y
	_blob.rotation = Vector3(0.0, heading, lean)
	# Eyes peeking out of the front of it
	for eye in _puddle_eyes:
		eye.visible = false # (his own eyes are still up on his head)
		var side: float = eye.get_meta("side")
		var front := BLOB_RADIUS * _blob.scale.z * 0.62
		var spot := Vector3(side * 0.09, BLOB_RADIUS * _blob.scale.y * 1.5, -front * 0.95)
		eye.position = Basis(Vector3.UP, heading) * spot
		eye.rotation = Vector3(0.0, heading + side * 0.3, -side * 0.35)


## Landing: a splash of metal particles thrown up from the feet and fanned out along the floor
## A little puddle on the floor under a contact point of the superhero landing (follow: 0 / 1 the
## left / right foot, 2 the hand), carried along under it as it slides
func _dab(at: Vector3, follow := -1, delay := 0.0) -> void:
	var dab: MeshInstance3D = null
	for d in _dabs:
		if not d.visible:
			dab = d
			break
	if dab == null:
		dab = MeshInstance3D.new()
		dab.mesh = _blob.mesh
		dab.material_override = _material
		dab.top_level = true
		dab.visible = false
		add_child(dab)
		_dabs.append(dab)
	var spot := Vector3(at.x, global_position.y + 0.01, at.z)
	# Taken now (shown, too small to see), so another dab this frame doesn't take the same one
	dab.visible = true
	dab.set_meta("follow", follow)
	dab.global_transform = Transform3D(Basis.from_scale(Vector3.ONE * 0.001), spot)
	var size := randf_range(0.5, 0.75)
	var tween := create_tween()
	if delay > 0.0:
		tween.tween_interval(delay)
	tween.tween_callback(func():
		dab.global_transform = Transform3D(Basis(Vector3.UP, randf() * TAU).scaled_local(Vector3(0.05, 0.02, 0.05)), spot)
	)
	tween.tween_property(dab, "scale", Vector3(size, 0.08, size * randf_range(0.8, 1.3)), 0.25).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tween.tween_interval(0.5)
	tween.tween_property(dab, "scale", Vector3(0.01, 0.01, 0.01), 0.6).set_ease(Tween.EASE_IN)
	tween.tween_callback(func(): dab.visible = false)


func _land_splat() -> void:
	_land_spray.restart()
	_land_skid.restart()


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


## Hit something: flattened into a puddle up against it (point, normal: where and which way it
## faces), that slides slowly down it; without one (fallen off the world), a splash
func _splat(point := Vector3.INF, normal := Vector3.ZERO) -> void:
	dead = true
	velocity = Vector3.ZERO
	_figure.visible = false
	if normal == Vector3.ZERO:
		_blob.visible = false
		_splash.restart()
	else:
		_wall_puddle(point, normal)
	_droplets.clear()
	_trail.lift() # break the tracks where it splatted
	for spray in _foot_splash:
		spray.emitting = false
	_spin_left = 0.0
	splatted.emit()
	if not rewind_on_splat:
		return
	var back := clampi(_history.size() - int(REWIND / 0.1), 0, _history.size())
	var spot: Vector3 = _spawn.origin
	var facing: float = _spawn.basis.get_euler().y
	if back < _history.size():
		spot = _history[back][0]
		facing = _history[back][1]
		_history.resize(back + 1)
	get_tree().create_timer(RESPAWN_DELAY).timeout.connect(_respawn_at.bind(spot, facing))


func _wall_puddle(point: Vector3, normal: Vector3) -> void:
	var flat := Vector3(normal.x, 0.0, normal.z).normalized()
	var across := flat.cross(Vector3.UP).normalized()
	# The puddle's thin axis (its y) along the wall's normal
	var facing := Basis(across, flat, across.cross(flat))
	# On the thing hit, as high up it as goes (up to chest height), smaller on something small
	var centre := _on_surface(Vector3(point.x, global_position.y + 0.3, point.z), Vector3(point.x, global_position.y + 0.8, point.z), flat)
	var reach := 1.0
	for probe in [Vector3.UP * 0.55, Vector3.DOWN * 0.3]:
		if _on_surface(centre, centre + probe, flat) == centre:
			reach = 0.6 # the surface runs out close by: a smaller splat
	for eye in _puddle_eyes:
		eye.visible = false
	_blob.visible = true
	_blob.global_transform = Transform3D(facing.scaled_local(Vector3(0.3, 0.1, 0.3)), centre)
	_material.set_shader_parameter("splash", 1.0)
	_puddle_splash = 1.0
	if _wall_tween:
		_wall_tween.kill()
	_wall_tween = create_tween()
	# Slapped flat against it, spreading with a wobble, then sliding slowly down
	# Round sometimes; otherwise an oval at any angle
	var round := randf() < 0.4
	_blob.global_basis = Basis(flat, randf_range(-PI, PI)) * _blob.global_basis
	_wall_tween.tween_property(_blob, "scale", (Vector3(1.7, 0.05, 1.7) if round else Vector3(1.45, 0.05, 1.95)) * Vector3(reach, 1.0, reach), 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	_wall_tween.parallel().tween_property(_blob, "global_position", centre + Vector3.DOWN * 0.45, RESPAWN_DELAY + 1.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	# ...then the arms, one after the other, slapping into the wall either side of it
	if _arm_puddles.is_empty():
		for i in 2:
			var arm := MeshInstance3D.new()
			arm.mesh = _blob.mesh
			arm.material_override = _material
			arm.top_level = true
			arm.visible = false
			add_child(arm)
			_arm_puddles.append(arm)
	# Never the same twice: either arm first, high or low, near or flung wide, at any angle, big or
	# small, quick or late, and sliding down the wall at its own pace (now and then into the body's)
	var first := -1.0 if randf() < 0.5 else 1.0
	for i in 2:
		var arm := _arm_puddles[i]
		var side := first if i == 0 else -first
		var spot := _on_surface(centre, centre + across * side * randf_range(0.55, 1.35) + Vector3.UP * randf_range(-0.35, 0.7), flat)
		var tilt := Basis(flat, randf_range(-PI, PI)) * facing # stretched out at any angle
		arm.global_transform = Transform3D(tilt.scaled_local(Vector3(0.05, 0.05, 0.05)), spot)
		var delay := randf_range(0.06, 0.2) + i * randf_range(0.04, 0.25)
		var size := randf_range(0.75, 1.3)
		var drip := randf_range(0.15, 0.9)
		# The arm itself flies off the body into the wall and turns into the splat where it lands
		var flyer := MeshInstance3D.new()
		var from: Node3D = _figure.arm_mesh("L" if side * across.x < 0.0 else "R")
		if from == null:
			from = _figure.arm_mesh("L" if i == 0 else "R")
		flyer.mesh = from.mesh
		flyer.material_override = _figure_material
		flyer.top_level = true
		add_child(flyer)
		flyer.global_transform = from.global_transform
		var splat := create_tween()
		splat.tween_property(flyer, "global_position", spot, delay).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		splat.parallel().tween_property(flyer, "scale", flyer.scale * Vector3(1.3, 0.6, 1.3), delay)
		splat.tween_callback(func():
			flyer.queue_free()
			arm.visible = true
			_droplets.burst(randi_range(1, 4), randf_range(0.4, 0.9))
		)
		var arm_shape := Vector3(0.75, 0.09, 0.75) if randf() < 0.4 else Vector3(0.5, 0.09, randf_range(0.8, 1.4)) # round sometimes
		splat.tween_property(arm, "scale", Vector3(arm_shape.x * size, 0.05, arm_shape.z * size), randf_range(0.2, 0.4)).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		splat.tween_property(arm, "global_position", spot + Vector3.DOWN * drip, RESPAWN_DELAY + randf_range(0.3, 1.4)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_droplets.clear()


## A spot on the surface that was hit, as near `wanted` as the surface goes (stepping back toward
## `centre` until there's something there to splat on)
func _on_surface(centre: Vector3, wanted: Vector3, normal: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	for k in 6:
		var spot := wanted.lerp(centre, k / 5.0)
		var ray := PhysicsRayQueryParameters3D.create(spot + normal * 0.4, spot - normal * 0.4)
		ray.exclude = [get_rid()]
		var hit := space.intersect_ray(ray)
		if not hit.is_empty():
			return hit.position + normal * 0.04
	return centre


func _respawn_at(spot: Vector3, facing: float) -> void:
	for arm in _arm_puddles:
		arm.visible = false
	if _wall_tween:
		_wall_tween.kill()
		_wall_tween = null
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
	wall_running = false
	_wall_roll = 0.0
	_puddled = true
	_pool_size = 1.0
	speed = 0.0 # from a standstill: pumping hard
	_dash_left = 0.0
	dash_cooldown = 0.0
	_droplets.clear()
	_agitation = 1.0
