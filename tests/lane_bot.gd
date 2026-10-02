extends SceneTree
## Headless check: a bot runs the whole practice lane using only the player's controls,
## on several randomly generated lanes, and reports any splats. Run: godot --headless --path . -s res://tests/lane_bot.gd

const TestArea := preload("res://scripts/test_area.gd")
const RUNS := 5 # a freshly generated lane each run

var main: Node
var player: CharacterBody3D
var input: Node
var splats := 0
var done := {}
var frames := 0
var run := 1
var run_started := 0
var total_splats := 0


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	main.start_mode = "test"
	root.add_child(main)


func _plan() -> Array:
	# [z where to act, action], from the course the area generated
	var actions := []
	for obstacle in main.area.lane_plan:
		var z: float = obstacle.z
		match obstacle.kind:
			"hurdle":
				actions.append([z + 4.5, "jump"])
			"beam":
				actions.append([z + 3.0, "duck"])
			"dodge_left", "dodge_both":
				actions.append([z + 6.0, "left"])
				actions.append([z - 2.0, "right"])
			"dodge_right":
				actions.append([z + 6.0, "right"])
				actions.append([z - 2.0, "left"])
			"hurdle_pair":
				actions.append([z + 6.0 + 4.5, "jump"])
				actions.append([z - 6.0 + 4.5, "jump"])
	return actions


var plan: Array


func _process(_delta: float) -> bool:
	frames += 1
	if player == null:
		player = main.player
		input = player.input
		player.splatted.connect(func():
			splats += 1
			print("SPLAT at z=%.1f x=%.1f y=%.2f" % [player.global_position.z, player.global_position.x, player.global_position.y])
		)
		plan = _plan()
		return false
	var z := player.global_position.z
	for k in plan.size():
		if done.has(k):
			continue
		if z <= plan[k][0] and not OS.get_cmdline_user_args().has("--idle"):
			done[k] = true
			match plan[k][1]:
				"jump": input.jump.emit()
				"duck": input.duck.emit()
				"left": input.dodge.emit(-1.0)
				"right": input.dodge.emit(1.0)
	if z < TestArea.LANE_END - 10.0 or Time.get_ticks_msec() - run_started > 40000:
		var kinds: Array = main.area.lane_plan.map(func(o): return o.kind)
		print("LANE RUN %d: reached z=%.1f, x=%.2f, splats=%d  %s" % [run, z, player.global_position.x, splats, kinds])
		total_splats += splats
		if run >= RUNS:
			print("LANE BOT: %d runs, %d splats" % [RUNS, total_splats])
			return true
		# Next run: a new course, from the start
		run += 1
		splats = 0
		done.clear()
		main.restart()
		plan = _plan()
		run_started = Time.get_ticks_msec()
	return false
