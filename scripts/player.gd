extends CharacterBody3D
## The liquid-metal blob. It runs forward on its own; the input steers it, and swipes
## make it jump, sidestep or melt into a puddle to slide under things. Running head-on
## into something splats it, and it pulls itself back together a moment earlier.

signal splatted
signal drops_changed(total: int)

const GRAVITY := 42.0
const FAST_FALL := 2.6 # gravity multiplier when you swipe down in the air
const DODGE_DIST := 3.0
const DODGE_TIME := 0.16
const DUCK_TIME := 0.75
const STAND := { radius = 0.5, height = 1.3 }
const PUDDLE := { radius = 0.3, height = 0.6 }
const BLOB_RADIUS := 0.55
const RESPAWN_DELAY := 0.9
const REWIND := 1.2 # seconds back along your path a splat sends you

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

var _dodge_left := 0.0
var _dodge_dir := 0.0
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
var _blob := MeshInstance3D.new()
var _material := ShaderMaterial.new()
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
	add_child(_blob)

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

	input.jump.connect(_on_jump)
	input.duck.connect(_on_duck)
	input.dodge.connect(_on_dodge)


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


func _on_duck() -> void:
	if dead:
		return
	_duck_left = DUCK_TIME
	if is_on_floor():
		_set_ducking(true)
	else:
		_fast_fall = true # dive down, then puddle on landing


func _on_dodge(direction: float) -> void:
	if dead:
		return
	_dodge_dir = direction
	_dodge_left = DODGE_TIME
	_agitation = 1.0


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
	var ground := forward() * run_speed + right() * sideways
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

	# Shape: a tall drop running, a puddle ducking, stretched by vertical speed in the air
	var target := Vector3(1.0, 1.1, 1.0)
	if ducking:
		target = Vector3(1.6, 0.36, 1.6)
	elif not is_on_floor():
		var s := clampf(velocity.y / 22.0, -0.3, 0.35)
		target = Vector3(1.0 - s * 0.5, 1.0 + s, 1.0 - s * 0.5)
	var scale_now := _blob.scale.lerp(target, 1.0 - exp(-delta * 14.0))
	_blob.scale = scale_now
	var squash := Vector3(1.0 + _squash * 0.6, 1.0 - _squash, 1.0 + _squash * 0.6)
	_blob.scale = scale_now * squash
	_blob.position.y = BLOB_RADIUS * _blob.scale.y
	# Faces the way it's going, leaning into turns and sidesteps
	var lean := -steer * 0.22 - (_dodge_dir * 0.35 if _dodge_left > 0.0 else 0.0)
	_blob.rotation = Vector3(-0.12, heading, lean)


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
	_splash.restart()
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
	_blob.visible = true
	_blob.scale = Vector3(1.8, 0.05, 1.8)
	_agitation = 1.0
