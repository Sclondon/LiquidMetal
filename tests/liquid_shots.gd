extends SceneTree
## Frames of Mercury turning liquid on a jump: shards swelling into balls, the balls stretching
## as they move, and setting back on landing; then a duck: the slide, then the melt. Needs a window:
## godot --path . -s res://tests/liquid_shots.gd -- <out dir>

var main: Node
var t := 0.0
var jumped := false
var ducked := false
var times := [1.0, 1.04, 1.08, 1.12, 1.2, 1.35, 1.55, 1.68, 1.8, 1.95, 2.05, 2.12, 2.2, 2.3, 2.45, 2.55, 2.65, 2.8, 3.0]
var taken := 0


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	main.start_mode = "test"
	root.add_child(main)


func _process(delta: float) -> bool:
	t += delta
	var player: CharacterBody3D = main.player
	var cam: Camera3D = main.cam
	cam.target = null
	player.run_speed = 6.0 # stays on the clear stretch before the lane's first obstacle
	var at: Vector3 = player.get_global_transform_interpolated().origin
	cam.global_position = at + player.right() * 3.0 + Vector3.UP * 1.3 + player.forward() * 1.2
	cam.look_at(at + Vector3.UP * 0.9)
	cam.fov = 45.0
	if t >= 0.98 and not jumped:
		jumped = true
		player.input.jump.emit()
	if t >= 2.02 and not ducked:
		ducked = true
		player.input.duck.emit()
	if taken < times.size() and t >= times[taken]:
		root.get_texture().get_image().save_png("%s/liquid_%d.png" % [OS.get_cmdline_user_args()[0], taken])
		taken += 1
	return taken >= times.size()
