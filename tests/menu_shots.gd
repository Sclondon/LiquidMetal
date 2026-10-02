extends SceneTree
## Screenshots of the title menu, an endless run, and the game-over card. Needs a window:
## godot --path . -s res://tests/menu_shots.gd -- <out dir>

var main: Node
var t := 0.0
var step := 0


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)


func _shot(name: String) -> void:
	root.get_texture().get_image().save_png("%s/%s.png" % [OS.get_cmdline_user_args()[0], name])


func _process(delta: float) -> bool:
	t += delta
	match step:
		0:
			if t > 1.5:
				_shot("menu")
				main.menu.endless_chosen.emit()
				step += 1
		1:
			if t > 5.0:
				_shot("endless")
				print("player ", main.player.global_position, " cam ", main.cam.global_position, " dead ", main.player.dead, " ducking ", main.player.ducking)
				main.player.run_speed = 40.0 # run it into something
				step += 1
		2:
			if main.menu.is_open() or t > 20.0:
				step += 1
				t = 0.0
		3:
			if t > 0.3:
				_shot("game_over")
				return true
	return false
