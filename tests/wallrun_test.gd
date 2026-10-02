extends SceneTree
## Headless check of wall running in endless mode: jump, dodge into the lane wall, and it should
## run along the wall (off the floor, not falling) for a good while, then kick off with a jump.
## Run: godot --headless --path . -s res://tests/wallrun_test.gd

var main: Node
var t := 0.0
var step := 0
var started := -1.0
var lowest := 99.0
var log := []


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	main.start_mode = "endless"
	root.add_child(main)


func _process(delta: float) -> bool:
	t += delta
	var p: CharacterBody3D = main.player
	p.run_speed = 6.0 # stays in the runway (no obstacles) for the whole test
	match step:
		0:
			if t > 0.8:
				p.input.jump.emit()
				step = 1
		1:
			if t > 0.95:
				p.input.dodge.emit(1.0)
				step = 2
		2:
			if p.wall_running and started < 0.0:
				started = t
			if started >= 0.0:
				lowest = minf(lowest, p.global_position.y)
				if t - started > 0.9:
					log.append("%s wall run started (%.2f s after the dodge), still on it after 0.9 s: %s, lowest %.2f m" % ["PASS" if p.wall_running and lowest > 0.6 else "FAIL", started - 0.95, p.wall_running, lowest])
					p.input.jump.emit()
					step = 3
			elif t > 2.5:
				log.append("FAIL never started a wall run (x %.2f, y %.2f)" % [p.global_position.x, p.global_position.y])
				step = 4
		3:
			if t - started > 1.05:
				log.append("%s jumped off the wall (wall_running %s, x %.2f, rising %s)" % ["PASS" if not p.wall_running else "FAIL", p.wall_running, p.global_position.x, p.velocity.y > 0.0])
				step = 4
		4:
			for line in log:
				print(line)
			print("dead: ", p.dead)
			return true
	return t > 6.0
