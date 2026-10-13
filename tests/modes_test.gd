extends SceneTree
## Headless check of the arena's layouts, each for 40 s with the bots playing (he stands still):
## "pit" has a hole the bots keep out of (mostly) and anyone put over it falls and is lost;
## "movers" has blocks that really slide; "open" has nothing in it. Prints how the bots got on.
## Run: godot --headless --fixed-fps 60 --path . -s res://tests/modes_test.gd

const MODES := ["pit", "movers", "open"]

var main: Node
var at := 0
var t := 0.0
var log := []
var falls := 0
var walls := 0
var bursts := 0
var seen := {}
var dropped := false
var fell := false


func _initialize() -> void:
	_start()


func _start() -> void:
	if main:
		main.free()
	main = load("res://scenes/main.tscn").instantiate()
	main.start_mode = "arena"
	main.use_pads = false
	main.arena_mode = MODES[at]
	root.add_child(main)
	t = 0.0
	falls = 0
	walls = 0
	bursts = 0
	seen = {}
	dropped = false
	fell = false


func _check(name: String, ok: bool) -> void:
	log.append("%s %s" % ["PASS" if ok else "FAIL", name])


func _process(delta: float) -> bool:
	var arena: Node = main.area
	if arena.me == 0:
		return false
	var p: CharacterBody3D = main.player
	p.run_speed = 0.0
	if t == 0.0:
		arena.feed.connect(func(text: String):
			if text.ends_with("fell in the pit"):
				falls += 1
			elif text.ends_with("hit a wall"):
				walls += 1
			else:
				bursts += 1)
		for mover in arena._movers:
			seen[mover] = mover.body.position
	t += delta
	var mode: String = MODES[at]
	if mode == "pit" and t > 30.0 and not dropped:
		dropped = true
		falls = -falls # (the bots' count so far, kept; his own fall is checked apart)
		p.global_position = Vector3(2.0, 0.5, 2.0)
	if dropped and not fell and p.dead and arena.my_mass() == 0:
		fell = true
	if t > 40.0:
		match mode:
			"pit":
				_check("pit: he falls in and is lost; the bots fell in %d times in 30 s (%d wall splats, %d bursts)" % [-falls - (1 if fell else 0) if falls > 0 else -falls, walls, bursts],
					arena.pit > 0.0 and fell and absi(falls) <= 4)
			"movers":
				var moved := 0.0
				for mover in arena._movers:
					moved = maxf(moved, mover.body.position.distance_to(seen[mover]))
				_check("movers: %d blocks sliding (one is %.1f m from where it was); %d wall splats, %d bursts in 40 s" % [arena._movers.size(), moved, walls, bursts],
					arena._movers.size() == 9 and moved > 1.0)
			"open":
				_check("open: nothing in the arena (%d stones); %d wall splats, %d bursts in 40 s" % [arena._course.get_child_count(), walls, bursts],
					arena._course.get_child_count() == 0)
		at += 1
		if at >= MODES.size():
			for line in log:
				print(line)
			return true
		_start()
	return false
