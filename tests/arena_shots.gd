extends SceneTree
## Screenshots of the arena's battle room (run here with bots): just in, a bot up close, after
## bursting one, grown big, and the round's end. Needs a window:
## godot --path . -s res://tests/arena_shots.gd -- <out dir>

var main: Node
var t := 0.0
var step := 0
var bot := {}


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	main.start_mode = "arena"
	main.use_pads = false
	main.arena_round = 22.0
	root.add_child(main)


func _shot(name: String) -> void:
	root.get_texture().get_image().save_png("%s/%s.png" % [OS.get_cmdline_user_args()[0], name])


func _process(delta: float) -> bool:
	t += delta
	var p: CharacterBody3D = main.player
	var arena: Node = main.area
	if arena.me == 0:
		return false
	if step != 3:
		arena.runners[arena.me].safe = 1.0 # (left alone while the pictures are set up)
	match step:
		0:
			if t > 1.2:
				_shot("1_in")
				step = 1
		1:
			# A bot brought round in front of him
			if t > 4.0:
				for r in arena.runners.values():
					if r.bot and r.alive:
						bot = r
				bot.mass = 90
				arena._apply_mass(bot)
				step = 2
		2:
			# (kept alongside him, running the way he is)
			bot.safe = 1.0
			bot.body.heading = p.heading
			bot.body.global_position = p.global_position + p.forward() * 3.5 + p.right() * 1.8
			bot.body.reset_physics_interpolation()
			if t > 4.6:
				_shot("2_bot")
				p.input.dash.emit()
				bot.safe = 0.0
				arena.runners[arena.me].safe = 0.0
				step = 3
		3:
			if bot.alive and t < 5.6:
				bot.body.global_position = p.global_position + p.forward() * 1.2
			if not bot.alive and bot.get("shot", 0.0) == 0.0:
				bot.shot = t
			if bot.get("shot", 0.0) > 0.0 and t > bot.shot + 0.25:
				_shot("3_burst")
				# Grown: a big mass, to see the size and the camera pulled back
				arena._room._ents[arena.me].mass = 260
				arena.runners[arena.me].mass = 260
				arena._respawn(arena.runners[arena.me]) # (somewhere clear, facing the middle)
				arena._apply_mass(arena.runners[arena.me])
				step = 4
				t = 6.0
		4:
			p.run_speed = 2.5 # (ambling, so nothing gets in the way)
			if t > 9.0:
				_shot("4_big")
				step = 5
		5:
			if arena.phase == "over":
				step = 6
				t = 0.0
		6:
			if t > 0.8:
				_shot("5_round_over")
				return true
	return false
