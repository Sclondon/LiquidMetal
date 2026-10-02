extends Node
## Turns touches (and the mouse, which Godot emulates as touch) plus the keyboard into
## runner controls:
##   swipe up = jump, swipe down = duck, swipe left/right = dodge,
##   tap and hold the left/right half of the screen = turn that way.
##   the DASH button = a burst of speed.
## Keyboard: Space/W/Up jump, S/Down duck, Left/Right arrows dodge, A/D held turn, Shift/E dash.
## Gamepad: left stick turn, right stick look around (the camera), A / D-pad up jump, B / D-pad
## down duck, X dash, LB / RB or D-pad left / right dodge. A stick only counts once it's been seen
## resting in the middle (some devices report an axis stuck at full tilt).

const STICK_DEADZONE := 0.2

## The right stick, -1..1 each way: the chase camera looks around with it
var look := Vector2.ZERO

## False: gamepads ignored (the screenshot tests, on a machine with a controller plugged in)
var use_pads := true

var _centred := {} # "device:axis" -> true once that axis has been seen at rest

signal jump
signal duck
signal dodge(direction: float) # -1 left, +1 right
signal dash # the DASH button (or Shift / E)

const SWIPE_DIST := 40.0 # UI pixels before a press counts as a swipe
const SWIPE_TIME := 0.4 # a swipe has to get that far within this long
const HOLD_DELAY := 0.09 # a press held this long without swiping starts turning

## Returns true for screen points over the HUD, so pressing a button doesn't steer
var is_over_ui: Callable

## -1 (left) .. +1 (right), read by the player every frame
var turn := 0.0

var _touches := {} # touch index -> { start, pos, time, used }


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			if is_over_ui.is_valid() and is_over_ui.call(event.position):
				return
			_touches[event.index] = { start = event.position, pos = event.position, time = _now(), used = false }
		else:
			var touch = _touches.get(event.index)
			if touch and not touch.used:
				_try_swipe(touch, event.position)
			_touches.erase(event.index)
	elif event is InputEventScreenDrag:
		var touch = _touches.get(event.index)
		if touch:
			touch.pos = event.position
			if not touch.used:
				_try_swipe(touch, event.position)
	elif event is InputEventJoypadButton and event.pressed:
		match event.button_index:
			JOY_BUTTON_A, JOY_BUTTON_DPAD_UP:
				jump.emit()
			JOY_BUTTON_B, JOY_BUTTON_DPAD_DOWN:
				duck.emit()
			JOY_BUTTON_X, JOY_BUTTON_Y:
				dash.emit()
			JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_DPAD_LEFT:
				dodge.emit(-1.0)
			JOY_BUTTON_RIGHT_SHOULDER, JOY_BUTTON_DPAD_RIGHT:
				dodge.emit(1.0)
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_SPACE, KEY_W, KEY_UP:
				jump.emit()
			KEY_S, KEY_DOWN:
				duck.emit()
			KEY_LEFT:
				dodge.emit(-1.0)
			KEY_RIGHT:
				dodge.emit(1.0)
			KEY_SHIFT, KEY_E:
				dash.emit()


func _try_swipe(touch: Dictionary, pos: Vector2) -> void:
	var moved: Vector2 = pos - touch.start
	if moved.length() < SWIPE_DIST or _now() - touch.time > SWIPE_TIME:
		return
	touch.used = true # one gesture per press; it stops turning too
	if absf(moved.x) > absf(moved.y):
		dodge.emit(signf(moved.x))
	elif moved.y < 0.0:
		jump.emit()
	else:
		duck.emit()


func _process(_delta: float) -> void:
	var half := get_viewport().get_visible_rect().size.x * 0.5
	var now := _now()
	var held := 0.0
	for touch in _touches.values():
		if touch.used or now - touch.time < HOLD_DELAY:
			continue
		held += -1.0 if touch.pos.x < half else 1.0
	var keys := 0.0
	if Input.is_physical_key_pressed(KEY_A):
		keys -= 1.0
	if Input.is_physical_key_pressed(KEY_D):
		keys += 1.0
	var stick := 0.0
	look = Vector2.ZERO
	for pad in (Input.get_connected_joypads() if use_pads else []):
		stick += _axis(pad, JOY_AXIS_LEFT_X)
		look += Vector2(_axis(pad, JOY_AXIS_RIGHT_X), _axis(pad, JOY_AXIS_RIGHT_Y))
	turn = clampf(held + keys + stick, -1.0, 1.0)
	look = look.limit_length(1.0)


## A stick axis past its dead zone (0 until it's been seen resting in the middle)
func _axis(pad: int, axis: JoyAxis) -> float:
	var value := Input.get_joy_axis(pad, axis)
	var key := "%d:%d" % [pad, axis]
	if absf(value) < STICK_DEADZONE:
		_centred[key] = true
		return 0.0
	if not _centred.has(key):
		return 0.0
	return signf(value) * (absf(value) - STICK_DEADZONE) / (1.0 - STICK_DEADZONE)

