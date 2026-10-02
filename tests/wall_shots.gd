extends SceneTree
## Frames of a wall run in endless mode (jump, dodge into the wall, run along it, jump off) and
## the superhero landing after. Needs a window: godot --path . -s res://tests/wall_shots.gd -- <dir>

var main: Node
var t := 0.0
var step := 0
var times := [1.15, 1.35, 1.6, 1.85, 2.15, 2.4, 2.6, 2.8, 3.0, 3.2]
var taken := 0


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	main.start_mode = "endless"
	main.use_pads = false # (a controller plugged into this machine would steer)
	root.add_child(main)


func _process(delta: float) -> bool:
	t += delta
	var p: CharacterBody3D = main.player
	p.run_speed = 6.0
	var cam: Camera3D = main.cam
	cam.target = null
	var at: Vector3 = p.get_global_transform_interpolated().origin
	cam.global_position = at + Vector3(-1.8, 1.6, 4.5)
	cam.look_at(at + Vector3(0.8, 0.9, -1.5))
	cam.fov = 55.0
	if step == 0 and t > 0.8:
		p.input.jump.emit()
		step = 1
	elif step == 1 and t > 0.95:
		p.input.dodge.emit(1.0)
		step = 2
	elif step == 2 and t > 2.2:
		p.input.jump.emit()
		step = 3
	if taken < times.size() and t >= times[taken]:
		root.get_texture().get_image().save_png("%s/wall_%02d.png" % [OS.get_cmdline_user_args()[0], taken])
		taken += 1
	return taken >= times.size()
