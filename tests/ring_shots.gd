extends SceneTree
## Screenshots of the endless run on the ring road: the start, a little way on, and the ring and
## the moon from up and to one side. Needs a window:
## godot --path . -s res://tests/ring_shots.gd -- <out dir>

var main: Node
var t := 0.0
var step := 0


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	main.start_mode = "endless"
	main.use_pads = false
	main.enemies = false
	root.add_child(main)


func _shot(name: String) -> void:
	root.get_texture().get_image().save_png("%s/%s.png" % [OS.get_cmdline_user_args()[0], name])


func _process(delta: float) -> bool:
	t += delta
	var p: CharacterBody3D = main.player
	match step:
		0:
			if t > 1.2:
				_shot("1_start")
				step = 1
		1:
			if t > 2.4:
				_shot("2_running")
				# Up and off to the right, looking back across the road at the moon
				main.cam.set_process(false)
				main.cam.global_position = p.global_position + Vector3(70.0, 45.0, 60.0)
				main.cam.look_at(p.global_position + Vector3(-300.0, -30.0, -250.0))
				main.cam.fov = 75.0
				p.set_physics_process(false)
				step = 2
		2:
			if t > 2.8:
				_shot("3_ring_and_moon")
				return true
	return false
