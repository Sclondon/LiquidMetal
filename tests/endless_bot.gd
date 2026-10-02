extends SceneTree
## Headless check of endless mode: a bot plays it with the controls, reading the obstacles the
## course has laid (its lane_plan) as it goes, and should get a long way in without a splat as
## the speed climbs. Run: godot --headless --path . -s res://tests/endless_bot.gd

const GOAL := 1500.0 # metres

var main: Node
var done := {}
var splatted := false
var blown := 0
var last_dodge := 0
var seen := {}


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	main.start_mode = "endless"
	main.enemies = false
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
		for e in main.area.enemies:
			if is_instance_valid(e):
				print("  enemy at dz %.1f dx %.1f dead %s" % [e.global_position.z - player.global_position.z, e.global_position.x - player.global_position.x, e.dead])
		for o in main.area.lane_plan:
			if absf(o.z - player.global_position.z) < 30.0:
				print("  nearby: %s at z %.1f (runner at z %.1f)" % [o.kind, o.z, player.global_position.z])
	if splatted or main.area.distance() >= GOAL or Time.get_ticks_msec() > 150000:
		print("ENDLESS BOT: %.0f m, speed %.1f, %s, enemies blown up %d" % [main.area.distance(), player.run_speed, "splatted" if splatted else "no splats", blown])
		return true
	# An enemy closing in from behind on its line: sidestep and let it by
	for enemy in main.area.enemies:
		if not is_instance_valid(enemy) or enemy.dead:
			continue
		var back: float = enemy.global_position.z - player.global_position.z
		var dx: float = enemy.global_position.x - player.global_position.x
		var busy := false
		for o in main.area.lane_plan:
			if o.z < player.global_position.z + 3.0 and o.z > player.global_position.z - 16.0:
				busy = true
		if not busy and back > 0.0 and back < 6.0 and absf(dx) < 1.3 and player._dodge_left <= 0.0 and Time.get_ticks_msec() - last_dodge > 600:
			last_dodge = Time.get_ticks_msec()
			player.input.dodge.emit(-1.0 if player.global_position.x > 0.0 else 1.0)
	# An enemy ahead in its line: dash through it (the punch launches 0.3 s after the press)
	for enemy in main.area.enemies:
		if not is_instance_valid(enemy) or enemy.dead:
			continue
		var gap: float = player.global_position.z - enemy.global_position.z
		var closing: float = maxf(player.speed - enemy.speed, 1.0)
		if gap > 0.0 and gap < closing * 0.45 + 2.5 and absf(enemy.global_position.x - player.global_position.x) < 1.4 and player.dash_cooldown <= 0.0:
			player.input.dash.emit()
	for enemy in main.area.enemies:
		if is_instance_valid(enemy) and enemy.dead and not seen.has(enemy):
			seen[enemy] = true
			blown += 1
	var pace: float = maxf(Vector2(player.velocity.x, player.velocity.z).length(), player.run_speed) / 14.0
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
