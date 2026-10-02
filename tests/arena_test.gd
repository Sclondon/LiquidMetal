extends SceneTree
## Headless check of arena mode: wave 1 sends two enemies, they close in on him; blow them up and
## it's cleared, and wave 2 sends three. Run: godot --headless --path . -s res://tests/arena_test.gd

var main: Node
var t := 0.0
var log := []
var step := 0
var first_gap := 0.0
var started := {}
var cleared := []


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	main.start_mode = "arena"
	main.use_pads = false
	root.add_child(main)


func _check(name: String, ok: bool) -> void:
	log.append("%s %s" % ["PASS" if ok else "FAIL", name])


func _alive() -> Array:
	return main.area.enemies.filter(func(e): return is_instance_valid(e) and not e.dead)


func _gap() -> float:
	var best := INF
	for e in _alive():
		best = minf(best, e.global_position.distance_to(main.player.global_position))
	return best


func _process(delta: float) -> bool:
	t += delta
	var p: CharacterBody3D = main.player
	p.run_speed = 4.0 # slow, in the middle: the enemies come to him
	if step == 0:
		main.area.wave_started.connect(func(w): started[w] = true)
		main.area.wave_cleared.connect(func(w): cleared.append(w))
		step = 1
	elif step == 1 and _alive().size() >= 2:
		_check("wave 1 sends two enemies", started.has(1) and _alive().size() == 2)
		first_gap = _gap()
		step = 2
		t = 0.0
	elif step == 2 and t > 1.5:
		_check("they close in on him (%.1f m -> %.1f m)" % [first_gap, _gap()], _gap() < first_gap - 3.0)
		for e in _alive():
			e.blow_up(Vector3.ZERO)
		step = 3
		t = 0.0
	elif step == 3 and started.has(2) and _alive().size() >= 3:
		_check("wave 1 cleared, wave 2 sends three", cleared.has(1) and _alive().size() == 3)
		step = 4
	if step == 4 or t > 15.0:
		if step != 4:
			log.append("FAIL stuck at step %d (alive %d, started %s, cleared %s, dead %s)" % [step, _alive().size(), started, cleared, p.dead])
		for line in log:
			print(line)
		return true
	return false
