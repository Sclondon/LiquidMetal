extends SceneTree
## Screenshots of the colosseum in one of the arena's layouts: the view he has, the whole arena
## from up in the stands, a Crystalien bot close up, and the crowd. Needs a window:
## godot --path . -s res://tests/colosseum_shots.gd -- <out dir> <open|blocks|movers|pit>

var main: Node
var t := 0.0
var step := 0
var mode := "blocks"
var bot := {}


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 1:
		mode = args[1]
	main = load("res://scenes/main.tscn").instantiate()
	main.start_mode = "arena"
	main.use_pads = false
	main.arena_mode = mode
	root.add_child(main)


func _shot(name: String) -> void:
	root.get_texture().get_image().save_png("%s/%s_%s.png" % [OS.get_cmdline_user_args()[0], mode, name])


## The camera taken off the runner and put somewhere, looking at something
func _look(from: Vector3, at: Vector3) -> void:
	main.cam.set_process(false)
	main.cam.global_position = from
	main.cam.look_at(at)
	main.cam.fov = 70.0


func _process(delta: float) -> bool:
	t += delta
	var arena: Node = main.area
	if arena.me == 0:
		return false
	arena.runners[arena.me].safe = 1.0 # (left alone)
	match step:
		0:
			if t > 2.2:
				_shot("1_view")
				_look(Vector3(0.0, 26.0, 86.0), Vector3(0.0, -4.0, 0.0))
				step = 1
		1:
			if t > 2.6:
				_shot("2_arena")
				step = 2
		2:
			for r in arena.runners.values():
				if r.bot and r.alive and not r.body.dead:
					bot = r
			var b: CharacterBody3D = bot.body
			_look(b.global_position + b.forward() * 4.5 + b.right() * 1.5 + Vector3.UP * 1.4, b.global_position + Vector3.UP * 1.0)
			if t > 3.2:
				_shot("3_crystalien")
				_look(Vector3(0.0, 9.0, 48.0), Vector3(0.0, 13.0, 78.0))
				arena._colosseum.cheer()
				step = 3
		3:
			if t > 3.8:
				_shot("4_crowd")
				# The sky, with one of everything held in view
				main.sky_show.showcase(true)
				_look(Vector3(0.0, 30.0, 0.0), Vector3(40.0, 75.0, -60.0))
				step = 4
		4:
			if t > 4.3:
				_shot("5_sky")
				_look(Vector3(0.0, 30.0, 0.0), Vector3(-60.0, 60.0, 50.0))
				step = 5
		5:
			if t > 4.8:
				_shot("6_sky")
				return true
	return false
