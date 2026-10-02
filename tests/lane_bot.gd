extends SceneTree
## Headless check: a bot runs the whole practice lane using only the player's controls
## and reports any splats. Run: godot --headless --path . -s res://tests/lane_bot.gd

const TestArea := preload("res://scripts/test_area.gd")

var main: Node
var player: CharacterBody3D
var input: Node
var splats := 0
var done := {}
var frames := 0


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)


func _plan() -> Array:
	# [z where to act, action]
	var actions := []
	var pattern := ["hurdle", "beam", "dodge_left", "hurdle", "dodge_right", "beam", "hurdle_pair", "dodge_both"]
	var z := TestArea.LANE_START
	var i := 0
	while z > TestArea.LANE_END:
		match pattern[i % pattern.size()]:
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
		z -= TestArea.LANE_STEP
		i += 1
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
	if z < TestArea.LANE_END - 10.0 or Time.get_ticks_msec() > 60000:
		print("LANE RUN: reached z=%.1f, x=%.2f, splats=%d, drops=%d" % [z, player.global_position.x, splats, player.drops])
		return true
	return false
