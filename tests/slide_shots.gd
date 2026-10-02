extends SceneTree
## Frames of the slide from the side: hop, splat, the puddle skimming along, popping back up.
## Needs a window: godot --path . -s res://tests/slide_shots.gd -- <out dir>

var main: Node
var t := 0.0
var ducked := false
var held := true
var times := [1.1, 1.25, 1.4, 1.55, 1.75, 1.95, 2.05, 2.12, 2.2, 2.3, 2.45, 2.7]
var taken := 0


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	main.start_mode = "test"
	main.use_pads = false # (a controller plugged into this machine would steer)
	root.add_child(main)


func _process(delta: float) -> bool:
	t += delta
	var player: CharacterBody3D = main.player
	player.run_speed = 8.0
	var cam: Camera3D = main.cam
	cam.target = null
	var at: Vector3 = player.get_global_transform_interpolated().origin
	cam.global_position = at + player.right() * 3.2 + Vector3.UP * 1.6 + player.forward() * 1.0
	cam.look_at(at + Vector3.UP * 0.4)
	cam.fov = 45.0
	if t >= 1.0 and not ducked:
		ducked = true
		player.input.duck.emit()
		var e := InputEventKey.new()
		e.physical_keycode = KEY_S
		e.pressed = true
		Input.parse_input_event(e) # held down: it sinks in
	if t >= 2.0 and held:
		held = false
		var u := InputEventKey.new()
		u.physical_keycode = KEY_S
		u.pressed = false
		Input.parse_input_event(u)
	if taken < times.size() and t >= times[taken]:
		print("%.2f duck %s held %s S %s melt %.2f sink %.2f pool %.2f fig %s left %.2f" % [t, player.ducking, player.input.duck_held(), Input.is_physical_key_pressed(KEY_S), player._melt, player._sink, player._pool_size, player._figure.visible, player._duck_left])
		root.get_texture().get_image().save_png("%s/slide_%02d.png" % [OS.get_cmdline_user_args()[0], taken])
		taken += 1
	return taken >= times.size()
