extends Camera3D
## Chase camera: sits behind and above the blob, swings round after it on turns
## (a little behind, so you see the turn), and leans with it.

var target: Node3D # the player
var distance := 6.5
var height := 2.8

var _yaw := 0.0
var _y := 0.0
var _dash_fov := 0.0
var _look := Vector2.ZERO # the right stick's look-around, eased (x: round him, y: up / down)


func _ready() -> void:
	near = 0.05
	far = 700.0
	current = true
	# Moved every frame from the player's interpolated position, so not interpolated itself
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


func snap() -> void:
	_yaw = target.heading
	_y = target.global_position.y
	global_position = _desired(target.global_position)


func _desired(at: Vector3) -> Vector3:
	var yaw := _yaw - _look.x * PI * 0.5
	var back := Vector3(sin(yaw), 0.0, cos(yaw))
	return Vector3(at.x, _y, at.z) + back * distance + Vector3.UP * (height + _look.y * height * 0.8)


func _process(delta: float) -> void:
	if target == null:
		return
	var at: Vector3 = target.get_global_transform_interpolated().origin
	_yaw = lerp_angle(_yaw, target.heading, 1.0 - exp(-delta * 5.0))
	# The right stick swings the camera round him (up to half way round) and up or down; let go and
	# it eases back behind
	var want: Vector2 = target.input.look if target.input else Vector2.ZERO
	_look = _look.lerp(want, 1.0 - exp(-delta * 6.0))
	# Follows jumps only partly, so the ground doesn't bounce around
	_y = lerpf(_y, at.y * 0.6, 1.0 - exp(-delta * 4.0))
	global_position = global_position.lerp(_desired(at), 1.0 - exp(-delta * 12.0))
	var ahead := Vector3(-sin(_yaw), 0.0, -cos(_yaw)) * (1.0 - _look.length())
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
