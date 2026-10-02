extends SceneTree
## Headless check of the gamepad: fake button presses and stick moves through the input system.
## Run: godot --headless --path . -s res://tests/pad_test.gd

var main: Node
var t := 0.0
var step := 0
var log := []
var h0 := 0.0
var x0 := 0.0


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	main.start_mode = "test"
	root.add_child(main)


func _button(button: JoyButton, pressed := true) -> void:
	var e := InputEventJoypadButton.new()
	e.button_index = button
	e.pressed = pressed
	Input.parse_input_event(e)


func _axis(axis: JoyAxis, value: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = value
	Input.parse_input_event(e)


func _check(name: String, ok: bool) -> void:
	log.append("%s %s" % ["PASS" if ok else "FAIL", name])


func _process(delta: float) -> bool:
	t += delta
	var p: CharacterBody3D = main.player
	p.run_speed = 5.0
	match step:
		0:
			if t > 0.6:
				_button(JOY_BUTTON_A)
				step = 1
		1:
			if t > 0.75:
				_check("A jumps", not p.is_on_floor() and p.velocity.y > 0.0)
				step = 2
		2:
			if t > 1.8:
				_button(JOY_BUTTON_B)
				step = 3
		3:
			if t > 1.9:
				_check("B ducks", p.ducking)
				step = 4
		4:
			if t > 3.0:
				x0 = p.global_position.dot(p.right())
				_button(JOY_BUTTON_RIGHT_SHOULDER)
				step = 5
		5:
			if t > 3.4:
				_check("RB dodges right", p.global_position.dot(p.right()) - x0 > 4.0)
				_axis(JOY_AXIS_RIGHT_X, 0.0)
				x0 = p.global_position.dot(p.right())
				_axis(JOY_AXIS_RIGHT_X, -1.0)
				step = 6
		6:
			if t > 3.8:
				_check("a right-stick flick dodges", p.global_position.dot(p.right()) - x0 < -4.0)
				_axis(JOY_AXIS_RIGHT_X, 0.0)
				_button(JOY_BUTTON_X)
				step = 7
		7:
			if t > 3.85:
				_check("X dashes", p.is_dashing())
				step = 8
		8:
			if t > 4.5:
				_button(JOY_BUTTON_START)
				step = 9
		9:
			if t > 4.6:
				_check("Start goes to the menu", main.mode == "menu")
				for line in log:
					print(line)
				return true
	return t > 8.0
