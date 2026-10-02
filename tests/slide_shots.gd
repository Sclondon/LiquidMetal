extends SceneTree
## Frames of the slide from the side: hop, splat, the puddle skimming along, popping back up.
## Needs a window: godot --path . -s res://tests/slide_shots.gd -- <out dir>

var main: Node
var t := 0.0
var ducked := false
var times := [1.0, 1.08, 1.16, 1.22, 1.3, 1.4, 1.6, 1.8, 1.95, 2.1, 2.4, 2.8]
var taken := 0


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	main.start_mode = "test"
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
	if taken < times.size() and t >= times[taken]:
		print("%.2f duck %s melt %.2f pool %.2f blob %s fig %s" % [t, player.ducking, player._melt, player._pool_size, player._blob.visible, player._figure.visible])
		root.get_texture().get_image().save_png("%s/slide_%02d.png" % [OS.get_cmdline_user_args()[0], taken])
		taken += 1
	return taken >= times.size()
