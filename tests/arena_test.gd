extends SceneTree
## Headless check of the arena's battle room, run here with bots (arena_room.gd): he's let into a
## laid-out room with five bots; running over a drop adds to his mass; the bots feed too; dashing
## through a bot bursts it (mass to him, drops on the floor) and it comes back; a wall splats him
## and he comes back small; the layout changes while the round's on; the round ends on the clock
## and a new one starts.
## Run: godot --headless --fixed-fps 60 --path . -s res://tests/arena_test.gd

var main: Node
var t := 0.0
var total := 0.0
var log := []
var step := 0
var bot := {}
var before := 0
var floor_drops := 0
var rounds := { over = 0, started = 0 }
var wall_deaths := 0
var layouts: Array = [] # each layout the arena has had, in turn


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	main.start_mode = "arena"
	main.use_pads = false
	main.arena_round = 45.0
	main.arena_mode = "blocks"
	main.arena_layout_time = 18.0
	root.add_child(main)


func _check(name: String, ok: bool) -> void:
	log.append("%s %s" % ["PASS" if ok else "FAIL", name])


func _process(delta: float) -> bool:
	t += delta
	total += delta
	var p: CharacterBody3D = main.player
	var arena: Node = main.area
	if arena.me != 0 and (layouts.is_empty() or layouts[-1] != arena.mode):
		layouts.append(arena.mode)
	if step > 0 and step < 6:
		p.run_speed = 0.0 # standing in the middle of nowhere, so the test decides what he touches
	match step:
		0:
			if arena.me != 0:
				arena.round_over.connect(func(_top): rounds.over += 1)
				arena.round_started.connect(func(): rounds.started += 1)
				arena.feed.connect(func(text: String):
					if text.ends_with("hit a wall"):
						wall_deaths += 1)
				_check("in the room: %d runners, %d drops, %d blocks" % [arena.runners.size(), arena.drops.size(), arena._course.get_child_count()],
					arena.runners.size() == 6 and arena.drops.size() == 110 and arena.mode == "blocks" and p.is_physics_processing() and not arena.online)
				step = 1
				t = 0.0
		1:
			# Onto a drop
			if t > 0.2 and before == 0:
				before = arena.my_mass()
				var drop: Dictionary = arena.drops.values()[0]
				p.global_position = Vector3(drop.x, 0.0, drop.z)
			elif t > 0.8:
				_check("a drop adds to his mass (%d -> %d)" % [before, arena.my_mass()], arena.my_mass() > before)
				step = 2
				t = 0.0
		2:
			if t > 6.0:
				var fed := 0
				for r in arena.runners.values():
					if r.bot:
						fed += r.mass - 10
				_check("the bots go for drops (%d between them in 6 s)" % fed, fed >= 5)
				for r in arena.runners.values():
					if r.bot and r.alive and not r.body.dead:
						bot = r
				before = arena.my_mass()
				floor_drops = arena.drops.size()
				p.global_position = Vector3(0.0, 0.0, 0.0)
				p.input.dash.emit()
				step = 3
				t = 0.0
		3:
			# A bot held right in front of him while he slashes
			if bot.alive and t < 1.0:
				bot.body.global_position = p.global_position + p.forward() * 1.0
			elif not bot.alive:
				_check("dashing through a bot bursts it (his mass %d -> %d, %d drops spilled)" % [before, arena.my_mass(), arena.drops.size() - floor_drops],
					arena.my_mass() > before and bot.body.dead and arena.smashes == 1 and arena.drops.size() > floor_drops)
				step = 4
				t = 0.0
			elif t > 2.0:
				_check("dashing through a bot bursts it", false)
				step = 4
		4:
			if bot.alive and not bot.body.dead:
				_check("the bot comes back small (%.1f s, mass %d)" % [t, bot.mass], bot.mass == 10)
				p._splat()
				step = 5
				t = 0.0
			elif t > 6.0:
				_check("the bot comes back", false)
				step = 5
		5:
			if t > 0.3 and t < 1.0 and (p.dead and arena.my_mass() == 0):
				before = -1 # (seen down, with nothing)
			if t > 1.0 and not p.dead and arena.runners[arena.me].alive:
				_check("a wall splats him, he comes back small (%.1f s, mass %d)" % [t, arena.my_mass()], before == -1 and arena.my_mass() == 10)
				step = 6
				t = 0.0
			elif t > 8.0:
				_check("a wall splats him, he comes back small", false)
				step = 6
		6:
			p.run_speed = 0.0
			if rounds.started > 0:
				_check("the round ends on the clock and a new one starts, (%.0f s in; %d bot wall splats)" % [total, wall_deaths],
					rounds.over == 1 and arena.phase == "play" and arena.my_mass() == 10 and arena.drops.size() >= 110)
				_check("the layout changed while the round was on, and again for the new round (%s)" % " -> ".join(layouts), layouts.size() >= 3)
				step = 7
	if step == 7 or total > 90.0:
		if step != 7:
			log.append("FAIL stuck at step %d (me %d, phase %s, rounds %s)" % [step, arena.me, arena.phase, rounds])
		for line in log:
			print(line)
		return true
	return false
