extends SceneTree
## Frames of Mercury running into a wall in endless mode: the body splats flat against it, then the
## arms. Needs a window: godot --path . -s res://tests/crash_shots.gd -- <out dir>

var main: Node
var t := 0.0
var crashed := -1.0
var cam_spot := Vector3.ZERO
var times := [0.0, 0.05, 0.1, 0.15, 0.25, 0.5]
var taken := 0


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	main.start_mode = "endless"
	main.use_pads = false # (a controller plugged into this machine would steer)
	root.add_child(main)


func _process(delta: float) -> bool:
	t += delta
	var p: CharacterBody3D = main.player
	var cam: Camera3D = main.cam
	if crashed < 0.0:
		if p.dead:
			crashed = t
			cam.target = null
			cam_spot = p.global_position
	else:
		cam.global_position = cam_spot + Vector3(-1.2, 1.6, 4.2)
		cam.look_at(cam_spot + Vector3(0.0, 0.7, -0.6))
		cam.fov = 55.0
		if taken < times.size() and t - crashed >= times[taken]:
			root.get_texture().get_image().save_png("%s/crash_%d.png" % [OS.get_cmdline_user_args()[0], taken])
			taken += 1
	return taken >= times.size() or t > 20.0
