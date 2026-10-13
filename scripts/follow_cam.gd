extends Camera3D
## Chase camera: sits behind and above the blob, swings round after it on turns
## (a little behind, so you see the turn), and leans with it. The right stick orbits it round him,
## all the way round and on round as long as it's held, and up over him or down low; let go and it
## eases back behind.

var target: Node3D # the player
var distance := 6.5
var height := 2.8

var _yaw := 0.0
var _y := 0.0
var _dash_fov := 0.0
var _orbit := 0.0 # radians the right stick has swung it round him (any amount: it goes all the way round)
var _orbit_speed := 0.0 # eased, so it spins up and settles
var _pitch := 0.0 # -1 (down low) .. 1 (up over him), eased
const ORBIT_RATE := 3.2 # radians a second at full tilt
const RETURN_DELAY := 0.6 # seconds after letting go before it swings back behind
var _released_for := 0.0
var _zoom := 1.0 # pulled back as he grows (the arena)


func _ready() -> void:
	near = 0.05
	far = 700.0
	current = true
	# Moved every frame from the player's interpolated position, so not interpolated itself
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


func snap() -> void:
	_yaw = target.heading
	_orbit = 0.0
	_orbit_speed = 0.0
	_pitch = 0.0
	_y = target.global_position.y
	global_position = _desired(target.global_position)


func _desired(at: Vector3) -> Vector3:
	var yaw := _yaw - _orbit
	# Up over him the camera comes in closer and higher; down low, closer to the floor
	var tilt := _pitch * 1.25 # radians above (or below) the usual angle
	var base := atan2(height, distance)
	var angle := clampf(base + tilt, 0.08, 1.45)
	var reach := Vector2(distance, height).length() * _zoom
	var back := Vector3(sin(yaw), 0.0, cos(yaw))
	return Vector3(at.x, _y, at.z) + back * cos(angle) * reach + Vector3.UP * sin(angle) * reach


func _process(delta: float) -> void:
	if target == null:
		return
	var at: Vector3 = target.get_global_transform_interpolated().origin
	_zoom = lerpf(_zoom, target.size if "size" in target else 1.0, 1.0 - exp(-delta * 3.0))
	_yaw = lerp_angle(_yaw, target.heading, 1.0 - exp(-delta * 5.0))
	# The right stick orbits the camera round him (on round for as long as it's held) and up or
	# down; let go and, after a moment, it swings back behind the shorter way
	var want: Vector2 = target.input.look if target.input else Vector2.ZERO
	_orbit_speed = lerpf(_orbit_speed, want.x * ORBIT_RATE, 1.0 - exp(-delta * 8.0))
	_orbit += _orbit_speed * delta
	_pitch = lerpf(_pitch, -want.y, 1.0 - exp(-delta * 6.0))
	if want.length() > 0.0:
		_released_for = 0.0
	else:
		_released_for += delta
		if _released_for > RETURN_DELAY:
			_orbit = lerpf(wrapf(_orbit, -PI, PI), 0.0, 1.0 - exp(-delta * 3.0))
	# Follows jumps only partly, so the ground doesn't bounce around
	_y = lerpf(_y, at.y * 0.6, 1.0 - exp(-delta * 4.0))
	global_position = global_position.lerp(_desired(at), 1.0 - exp(-delta * 12.0))
	# Behind him it looks on ahead; swung round, it looks at him
	var behind := clampf(1.0 - absf(wrapf(_orbit, -PI, PI)) / (PI * 0.5), 0.0, 1.0)
	var ahead := Vector3(-sin(_yaw), 0.0, -cos(_yaw)) * behind * (1.0 - absf(_pitch))
	look_at(at + ahead * 5.0 + Vector3.UP * 0.9)
	rotate_object_local(Vector3.FORWARD, target.steer * 0.07)

	# Portrait phones keep the width in view; wider screens keep the height
	var size := get_viewport().get_visible_rect().size
	if size.x < size.y:
		keep_aspect = Camera3D.KEEP_WIDTH
		fov = 78.0
	else:
		keep_aspect = Camera3D.KEEP_HEIGHT
		fov = 64.0 + target.run_speed * 0.4
	# A kick wider on a dash
	_dash_fov = lerpf(_dash_fov, 12.0 if target.is_dashing() else 0.0, 1.0 - exp(-get_process_delta_time() * 10.0))
	fov += _dash_fov
