extends SceneTree
## Headless check of the touch controls through the real input path: holding the left
## half turns left, the right half turns right, and swipes jump / duck / dodge.
## Run: godot --headless --path . -s res://tests/touch_test.gd

var main: Node
var player: CharacterBody3D
var step := 0
var wait := 0.0
var log := []
var heading0 := 0.0
var x0 := 0.0


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	main.start_mode = "test"
	main.enemies = false
	root.add_child(main)


func _touch(index: int, ui_point: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = root.get_final_transform() * ui_point
	event.pressed = pressed
	Input.parse_input_event(event)


func _drag(index: int, ui_point: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = root.get_final_transform() * ui_point
	Input.parse_input_event(event)


func _check(name: String, ok: bool) -> void:
	log.append("%s %s" % ["PASS" if ok else "FAIL", name])


func _process(delta: float) -> bool:
	player = main.player
	var size := root.get_visible_rect().size
	var left := Vector2(size.x * 0.2, size.y * 0.6)
	var right_side := Vector2(size.x * 0.8, size.y * 0.6)
	wait -= delta
	if wait > 0.0:
		return false
	match step:
		0:
			main.area.generate(4242) # one fixed course, so nothing random is in the way
			player.restart()
			player.run_speed = 5.0 # stay short of the lane's first obstacle for the whole test
			wait = 0.5 # let it settle on the floor
		1:
			heading0 = player.heading
			_touch(0, left, true)
			wait = 0.6
		2:
			_touch(0, left, false)
			_check("hold left turns left", player.heading > heading0 + 0.3)
			heading0 = player.heading
			_touch(0, right_side, true)
			wait = 0.6
		3:
			_touch(0, right_side, false)
			_check("hold right turns right", player.heading < heading0 - 0.3)
			_touch(1, left, true)
			_drag(1, left + Vector2(0, -30))
			_drag(1, left + Vector2(0, -80))
			_touch(1, left + Vector2(0, -80), false)
			wait = 0.15
		4:
			_check("swipe up jumps", not player.is_on_floor() and player.velocity.y > 0.0)
			wait = 0.9
		5:
			_touch(2, right_side, true)
			_drag(2, right_side + Vector2(0, 80))
			_touch(2, right_side + Vector2(0, 80), false)
			wait = 0.1
		6:
			_check("swipe down ducks", player.ducking)
			wait = 1.0
		7:
			x0 = player.global_position.dot(player.right())
			heading0 = player.heading
			_touch(3, right_side, true)
			_drag(3, right_side + Vector2(-90, 0))
			_touch(3, right_side + Vector2(-90, 0), false)
			wait = 0.3
		8:
			var moved: float = player.global_position.dot(player.right()) - x0
			_check("swipe left dodges left about 4.5 m (moved %.2f)" % moved, moved < -4.0 and moved > -5.0)
			_check("a swipe doesn't turn", absf(player.heading - heading0) < 0.01)
			for line in log:
				print(line)
			return true
	step += 1
	return false
