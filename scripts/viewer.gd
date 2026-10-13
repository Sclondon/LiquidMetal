extends CanvasLayer
## The model viewer (MODEL VIEWER on the title menu): Mercury, the real runner with all its liquid,
## running on the spot at the test area's start while the camera circles it. Drag (or the right
## stick) to orbit, all the way round and up over it; the wheel, a pinch or LB / RB to zoom. A
## slider sets how fast it runs (0: it stands still, breathing), buttons make it jump, duck, dodge
## and dash, T-POSE holds it in the T, and SPIN turns the slow turntable on and off. BACK (or Esc /
## Start) goes to the menu.

const UI := preload("res://scripts/ui_theme.gd")
const STICK_DEADZONE := 0.2

signal back_chosen

var player: CharacterBody3D
var cam: Camera3D
var input: Node # the runner's input: the buttons here fire its signals

var _anchor := Vector3.ZERO # the spot it runs on
var _yaw := PI - 0.7 # round it (PI: straight in front of its face)
var _pitch := 0.22 # radians up from level
var _dist := 4.6
var _spin := true
var _touches := {} # index -> position, for dragging and pinching
var _spin_button: Button
var _tpose_button: Button
var _speed_label := Label.new()
var _slider := HSlider.new()
var _root := Control.new()


func _ready() -> void:
	layer = 3
	visible = false
	set_process(false)
	set_physics_process(false)
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UI.make()
	add_child(_root)

	var title := UI.heading("MERCURY", 52)
	title.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 0)
	title.offset_top = 14
	title.grow_horizontal = Control.GROW_DIRECTION_BOTH
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(title)
	var hint := UI.caption("DRAG to orbit  ·  WHEEL / PINCH to zoom", 16)
	hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 0)
	hint.offset_top = 82
	hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(hint)

	# The controls, along the bottom
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 14)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_root.add_child(panel)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 8)
	panel.add_child(rows)
	var speed_row := HBoxContainer.new()
	speed_row.add_theme_constant_override("separation", 12)
	_speed_label.add_theme_font_size_override("font_size", 18)
	_speed_label.custom_minimum_size.x = 150
	speed_row.add_child(_speed_label)
	_slider.min_value = 0.0
	_slider.max_value = 26.0
	_slider.step = 1.0
	_slider.value = 8.0
	_slider.custom_minimum_size.x = 360
	_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_slider.value_changed.connect(_set_speed)
	speed_row.add_child(_slider)
	rows.add_child(speed_row)
	var moves := HBoxContainer.new()
	moves.add_theme_constant_override("separation", 8)
	moves.alignment = BoxContainer.ALIGNMENT_CENTER
	rows.add_child(moves)
	moves.add_child(_button("JUMP", func(): input.jump.emit()))
	moves.add_child(_button("DUCK", func(): input.duck.emit()))
	moves.add_child(_button("< DODGE", func(): input.dodge.emit(-1.0)))
	moves.add_child(_button("DODGE >", func(): input.dodge.emit(1.0)))
	moves.add_child(_button("DASH", func(): input.dash.emit()))
	_tpose_button = _button("T-POSE", func(): _set_tpose(_tpose_button.button_pressed))
	_tpose_button.toggle_mode = true
	moves.add_child(_tpose_button)
	_spin_button = _button("SPIN", func(): _spin = not _spin)
	_spin_button.toggle_mode = true
	moves.add_child(_spin_button)
	moves.add_child(_button("BACK", func(): back_chosen.emit()))


func _button(text: String, pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 56)
	button.add_theme_font_size_override("font_size", 20)
	button.focus_mode = Control.FOCUS_ALL
	button.pressed.connect(pressed)
	return button


## Into the viewer: it runs on this spot
func open(spot: Vector3) -> void:
	_anchor = spot
	_touches.clear()
	_spin = true
	_spin_button.button_pressed = true
	visible = true
	set_process(true)
	set_physics_process(true)
	cam.target = null # (the viewer moves it)
	_set_speed(_slider.value)


func close() -> void:
	_set_tpose(false)
	visible = false
	set_process(false)
	set_physics_process(false)
	_touches.clear()
	if input:
		input.brake = 0.0


## Held in the T (standing still for it), or back to what the slider says
func _set_tpose(on: bool) -> void:
	if _tpose_button:
		_tpose_button.set_pressed_no_signal(on)
	player._figure.force_pose = "tpose" if on else ""
	if on:
		player.run_speed = 0.0
		input.brake = 1.0
	elif visible:
		_set_speed(_slider.value)


func _set_speed(value: float) -> void:
	player.run_speed = value
	# (at 0 the brake's held on: it slows to a stop and stands)
	if player._figure.force_pose != "":
		return # (held in the T)
	input.brake = 1.0 if value < 0.5 else 0.0
	_speed_label.text = "SPEED %d m/s" % int(value) if value >= 0.5 else "STOPPED"


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = event.position
		else:
			_touches.erase(event.index)
	elif event is InputEventScreenDrag and _touches.has(event.index):
		if _touches.size() == 1:
			_yaw -= event.relative.x * 0.008
			_pitch = clampf(_pitch + event.relative.y * 0.006, -0.15, 1.45)
			_spin = false
			_spin_button.button_pressed = false
		elif _touches.size() == 2:
			# A pinch: the gap between the two fingers, before and after
			var other: Vector2 = Vector2.ZERO
			for index in _touches:
				if index != event.index:
					other = _touches[index]
			var before: float = (_touches[event.index] as Vector2).distance_to(other)
			var after: float = (event.position as Vector2).distance_to(other)
			if before > 1.0 and after > 1.0:
				_dist = clampf(_dist * before / after, 1.6, 14.0)
		_touches[event.index] = event.position
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_dist = maxf(_dist * 0.9, 1.6)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_dist = minf(_dist * 1.1, 14.0)


func _process(delta: float) -> void:
	# The right stick orbits; LB / RB zoom in and out
	for pad in Input.get_connected_joypads():
		var stick := Vector2(Input.get_joy_axis(pad, JOY_AXIS_RIGHT_X), Input.get_joy_axis(pad, JOY_AXIS_RIGHT_Y))
		if stick.length() > STICK_DEADZONE:
			_yaw -= stick.x * 2.4 * delta
			_pitch = clampf(_pitch + stick.y * 1.6 * delta, -0.15, 1.45)
			_spin = false
			_spin_button.button_pressed = false
		if Input.is_joy_button_pressed(pad, JOY_BUTTON_LEFT_SHOULDER):
			_dist = maxf(_dist * (1.0 - delta * 1.5), 1.6)
		if Input.is_joy_button_pressed(pad, JOY_BUTTON_RIGHT_SHOULDER):
			_dist = minf(_dist * (1.0 + delta * 1.5), 14.0)
	if _spin:
		_yaw += delta * 0.45
	var at: Vector3 = player.get_global_transform_interpolated().origin + Vector3.UP * 0.95
	var round_it := Vector3(sin(_yaw) * cos(_pitch), sin(_pitch), cos(_yaw) * cos(_pitch))
	cam.global_position = at + round_it * _dist
	cam.look_at(at)
	cam.fov = 45.0


## Running on the spot: pulled back onto it every step (a dodge still shows, then eases back)
func _physics_process(delta: float) -> void:
	if player.dead:
		return
	var p := player.global_position
	player.global_position = Vector3(lerpf(p.x, _anchor.x, 1.0 - exp(-delta * 2.5)), p.y, _anchor.z)
	player.heading = 0.0
	player.reset_physics_interpolation()
