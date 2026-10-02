extends SceneTree
## Screenshots of the UI: the menu, endless with its banner, a later zone, the arena, game over.
## Needs a window: godot --path . -s res://tests/ui_shots.gd -- <out dir>

var main: Node
var t := 0.0
var step := 0


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	main.use_pads = false
	root.add_child(main)


func _shot(name: String) -> void:
	root.get_texture().get_image().save_png("%s/%s.png" % [OS.get_cmdline_user_args()[0], name])


func _process(delta: float) -> bool:
	t += delta
	match step:
		0:
			if t > 1.5:
				_shot("1_menu")
				main.menu.endless_chosen.emit()
				step = 1
		1:
			if t > 2.0:
				_shot("2_endless_banner")
				step = 2
		2:
			if t > 3.0:
				main.area._on_debug_zone() if main.area.has_method("_on_debug_zone") else main.area.emit_signal("zone_changed", 1, main.area.ZONES[1])
				main.area.zone = 1
				step = 3
		3:
			if t > 5.5:
				_shot("3_zone2")
				main.menu.arena_chosen.emit()
				step = 4
		4:
			if t > 8.0:
				_shot("4_arena")
				main.player.run_speed = 40.0
				step = 5
		5:
			if main.menu.is_open() or t > 20.0:
				step = 6
				t = 0.0
		6:
			if t > 0.5:
				_shot("5_game_over")
				return true
	return false
