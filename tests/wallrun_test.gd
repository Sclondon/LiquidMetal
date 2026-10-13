extends SceneTree
## Headless check of wall running in endless mode: beside one of the ring's tall palisades, jump,
## dodge into it, and it should run along the wall (off the floor, not falling) for a good while,
## then kick off with a jump.
## Run: godot --headless --path . -s res://tests/wallrun_test.gd

var main: Node
var t := 0.0
var step := -1
var started := -1.0
var lowest := 99.0
var log := []


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	main.start_mode = "endless"
	main.enemies = false
	root.add_child(main)


func _process(delta: float) -> bool:
	t += delta
	var p: CharacterBody3D = main.player
	p.run_speed = 6.0 # stays alongside the palisade (40 m of it) for the whole test
	match step:
		-1:
			# On along the ring to the first palisade, and down beside the start of it, on its left
			main.area.falling_crystals = false
			p.set_physics_process(false)
			for thing in main.area.plan:
				if thing.kind == "wallrun":
					p.place(Vector3(float(thing.x0) - 3.2, 0.0, float(thing.z0) - 3.0), 0.0)
					p.set_physics_process(true)
					main.cam.snap()
					step = 0
					t = 0.0
					return false
			p.global_position.z -= 100.0
			if t > 20.0:
				print("FAIL no palisade to run on")
				return true
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
	return t > 6.0 and step >= 0
