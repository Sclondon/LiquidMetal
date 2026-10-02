extends SceneTree
## Headless check of endless mode: a bot plays it with the controls, reading the obstacles the
## course has laid (its lane_plan) as it goes, and should get a long way in without a splat as
## the speed climbs. Run: godot --headless --path . -s res://tests/endless_bot.gd

const GOAL := 1500.0 # metres

var main: Node
var done := {}
var splatted := false


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	main.start_mode = "endless"
	root.add_child(main)


func _actions(obstacle: Dictionary, pace: float) -> Array:
	# [z where to act, action]; triggers move earlier the faster it runs
	var z: float = obstacle.z
	match obstacle.kind:
		"hurdle":
			return [[z + 4.5 * pace, "jump"]]
		"beam":
			return [[z + 3.0 * pace, "duck"]]
		"dodge_left", "dodge_both":
			return [[z + 6.0 * pace, "left"], [z - 2.0, "right"]]
		"dodge_right":
			return [[z + 6.0 * pace, "right"], [z - 2.0, "left"]]
		"hurdle_pair":
			return [[z + obstacle.half + 4.5 * pace, "jump"], [z - obstacle.half + 4.5 * pace, "jump"]]
	return []


func _process(_delta: float) -> bool:
	var player: CharacterBody3D = main.player
	if player.dead and not splatted:
		splatted = true
		print("ENDLESS SPLAT at %.0f m (speed %.1f) x=%.2f y=%.2f" % [main.area.distance(), player.run_speed, player.global_position.x, player.global_position.y])
		for o in main.area.lane_plan:
			if absf(o.z - player.global_position.z) < 30.0:
				print("  nearby: %s at z %.1f (runner at z %.1f)" % [o.kind, o.z, player.global_position.z])
	if splatted or main.area.distance() >= GOAL or Time.get_ticks_msec() > 150000:
		print("ENDLESS BOT: %.0f m, speed %.1f, %s" % [main.area.distance(), player.run_speed, "splatted" if splatted else "no splats"])
		return true
	var pace: float = maxf(player.speed, player.run_speed) / 14.0
	var z := player.global_position.z
	var plan: Array = main.area.lane_plan
	for k in plan.size():
		var actions := _actions(plan[k], pace)
		for a in actions.size():
			var key := "%d:%d" % [k, a]
			if done.has(key) or z > actions[a][0]:
				continue
			done[key] = true
			match actions[a][1]:
				"jump": player.input.jump.emit()
				"duck": player.input.duck.emit()
				"left": player.input.dodge.emit(-1.0)
				"right": player.input.dodge.emit(1.0)
	return false
