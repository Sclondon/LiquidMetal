extends SceneTree
## Headless check of endless mode: a bot plays the ring with the controls, reading what the
## course has laid (its `plan`: boxes, and what to do about each) as it goes. It steers across the
## ring to keep clear of the breaks and the tall crystals, jumps the cracks and ridges and slides
## under the curtains, and should get GOAL metres in without a splat as the speed climbs, several
## runs one after another, each on a fresh course. Falling crystals are off (they aren't in the
## plan until they land) unless it's asked for them, to see how it gets on.
## Run: godot --headless --fixed-fps 60 --path . -s res://tests/endless_bot.gd [-- <runs> [crystals]]

const GOAL := 2000.0 # metres
const SIDEWAYS := 0.5 # metres across per metre along that it plans on managing
const LEAN := 0.6 # the most it turns off straight ahead (radians)

var main: Node
var runs := 3
var run := 0
var passed := 0
var clock := 0.0
var done := {}
var goal_x := 0.0
var finished := false
var begun := false


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		runs = maxi(int(args[0]), 1)
	main = load("res://scenes/main.tscn").instantiate()
	main.start_mode = "endless"
	main.enemies = false
	main.use_pads = false
	root.add_child(main)
	begun = false


func _begin() -> void:
	main.area.falling_crystals = OS.get_cmdline_user_args().has("crystals")
	done.clear()
	goal_x = 0.0
	clock = 0.0


func _process(delta: float) -> bool:
	if finished:
		return true
	var player: CharacterBody3D = main.player
	var course: Node3D = main.area
	if not begun:
		begun = true
		_begin()
	player.input.set_process(false) # (the bot sets its turn axis itself)
	clock += delta
	if player.dead or course.distance() >= GOAL or clock > 300.0:
		var ok: bool = not player.dead and course.distance() >= GOAL
		if player.dead:
			print("ENDLESS SPLAT at %.0f m (speed %.1f) x=%.2f y=%.2f z=%.2f" % [course.distance(), player.run_speed, player.global_position.x, player.global_position.y, player.global_position.z])
			for thing in course.plan:
				if absf(thing.z0 - player.global_position.z) < 40.0:
					print("  nearby: %s %s z %.1f..%.1f x %.1f..%.1f" % [thing.kind, thing.act, thing.z0, thing.z1, thing.x0, thing.x1])
		print("ENDLESS BOT run %d: %.0f m, zone %d, speed %.1f, %s%s" % [run + 1, course.distance(), course.zone + 1, player.run_speed, "no splats" if ok else ("splatted" if player.dead else "ran out of time"), ", %d crystals fell" % course.crystals_sent if course.falling_crystals else ""])
		passed += 1 if ok else 0
		run += 1
		if run >= runs:
			print("%s endless bot: %d of %d runs to %d m with no splats" % ["PASS" if passed == runs else "FAIL", passed, runs, int(GOAL)])
			finished = true
			return true
		main.start_endless()
		_begin()
		return false
	var x := player.global_position.x
	var z := player.global_position.z
	var along: float = maxf(-player.velocity.z, 4.0) # (forward speed only)
	var pace := along / 14.0

	# Across the ring: the nearest line that's clear of everything for as far ahead as it can
	# manage, setting off for it now or a little further on
	var best_cost := INF
	var best_x := x
	var best_start := 0.0
	for horizon in [75.0, 55.0, 38.0, 24.0]:
		for start in [0.0, 12.0, 24.0]:
			for k in int(course.HALF * 2.0) - 5:
				var to: float = -course.HALF + 3.0 + k
				var cost: float = absf(to - x) + start * 0.2 + absf(to) * 0.03 + (0.0 if absf(to - goal_x) < 0.6 else 1.5)
				if cost < best_cost and _clear(course.plan, x, z, to, start, horizon):
					best_cost = cost
					best_x = to
					best_start = start
		if best_cost < INF:
			break
	goal_x = best_x
	var aim_x := best_x if best_start == 0.0 else x
	# (heading > 0 runs left, toward -x)
	var want := clampf((x - aim_x) * 0.16, -LEAN, LEAN)
	player.input.turn = clampf((player.heading - want) * 4.0, -1.0, 1.0)

	# The things to jump and to slide under, where it's in line with them
	for thing in course.plan:
		if done.has(thing.id) or x < thing.x0 - 0.8 or x > thing.x1 + 0.8:
			continue
		var near: float = thing.z0
		if thing.act == "duck" and z <= near + 3.5 * pace:
			done[thing.id] = true
			if z > thing.z1:
				player.input.duck.emit()
		elif thing.act == "jump" and thing.kind in ["crack", "rift"]:
			# A break: off the lip
			if z <= near + 0.6 + along * 0.04:
				if z < near - 1.0:
					done[thing.id] = true # (past its lip: too late, or already over)
				elif player.is_on_floor():
					done[thing.id] = true
					player.input.jump.emit()
		elif thing.act == "jump" and z <= near + 4.5 * pace:
			done[thing.id] = true
			if z > thing.z1:
				player.input.jump.emit()
	# Coming down short, over a break: the second jump
	if not player.is_on_floor() and player.velocity.y < 0.0 and player.global_position.y < 0.7 and player._air_jumps > 0 and not course.floor_at(x, z - along * 0.1):
		player.input.jump.emit()
	return false


## Is the line from x across to `to` (setting off `start` metres on, then SIDEWAYS across per
## metre along, then straight) clear of every break and tall thing for `horizon` metres?
func _clear(plan: Array, x: float, z: float, to: float, start: float, horizon: float) -> bool:
	for thing in plan:
		if thing.act != "avoid" and thing.act != "hole":
			continue
		var from_d: float = maxf(z - float(thing.z0) - 3.0, 0.0)
		var to_d: float = z - float(thing.z1) + 3.0
		if to_d < 0.0 or from_d > horizon:
			continue
		var a := _line(x, to, start, from_d)
		var b := _line(x, to, start, to_d)
		var room := 1.7
		if maxf(a, b) > float(thing.x0) - room and minf(a, b) < float(thing.x1) + room:
			return false
	return true


func _line(x: float, to: float, start: float, d: float) -> float:
	return move_toward(x, to, maxf(d - start, 0.0) * SIDEWAYS)
