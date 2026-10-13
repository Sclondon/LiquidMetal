extends SceneTree
## Headless check of the ring's hazards and its boost, each on a fresh endless course:
## running off the edge splats you, so does running into a break; a falling crystal lands, splats
## whoever's under it and stays as something solid that's in the plan; an aurora ring boosts you;
## and an enemy runner left to itself keeps on the ring (jumps a crack, stays off the edge).
## Run: godot --headless --fixed-fps 60 --path . -s res://tests/ring_test.gd

const BoostPad := preload("res://scripts/boost_pad.gd")

var main: Node
var t := 0.0
var step := -1
var log: Array[String] = []
var fall: Node3D
var boosted := false
var enemy: CharacterBody3D
var crack := {}


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	main.start_mode = "endless"
	main.enemies = false
	main.use_pads = false
	root.add_child(main)


func _check(name: String, ok: bool, note := "") -> void:
	log.append("%s %s%s" % ["PASS" if ok else "FAIL", name, "" if note == "" else " (%s)" % note])


## A fresh course, nothing falling on it, the runner at the start
func _fresh() -> void:
	main.start_endless()
	main.area.falling_crystals = false
	main.player.input.set_process(false)
	main.player.input.turn = 0.0
	t = 0.0
	step += 1


## The first crack still ahead of z
func _crack_after(z: float) -> Dictionary:
	for thing in main.area.plan:
		if thing.kind == "crack" and thing.z0 < z - 20.0:
			return thing
	return {}


func _process(delta: float) -> bool:
	t += delta
	var p: CharacterBody3D = main.player
	match step:
		-1:
			_fresh()
			p.heading = PI * 0.5 # straight at the left edge
		0: # off the edge
			if p.dead or t > 8.0:
				_check("off the edge splats", p.dead and absf(p.global_position.x) > main.area.HALF and p.global_position.y < -1.0, "x %.1f y %.1f after %.1f s" % [p.global_position.x, p.global_position.y, t])
				_fresh()
				# On along the ring (the course builds on ahead of him) to the first crack
				p.set_physics_process(false)
		1:
			crack = _crack_after(p.global_position.z)
			if crack.is_empty() and t < 20.0:
				p.global_position.z -= 100.0
			else:
				p.place(Vector3(0.0, 0.0, float(crack.get("z0", 0.0)) + 14.0), 0.0)
				p.set_physics_process(true)
				step = 2
				t = 0.0
		2: # into a break
			if p.dead or t > 6.0:
				_check("into a break splats", p.dead and not crack.is_empty() and p.global_position.z < float(crack.z0) + 0.5 and p.global_position.y < -0.3, "z %.1f (crack %.1f..%.1f) y %.1f after %.1f s" % [p.global_position.z, crack.get("z0", 0.0), crack.get("z1", 0.0), p.global_position.y, t])
				_fresh()
				p.set_physics_process(false)
				fall = main.area.drop_crystal(p.global_position + Vector3(4.0, 0.0, -20.0), 1.0)
		3: # a crystal falls on open ring
			if t > 1.3:
				var spot := fall.global_position
				var query := PhysicsRayQueryParameters3D.create(spot + Vector3(0.0, 2.0, 12.0), spot + Vector3(0.0, 2.0, -12.0))
				var hit := p.get_world_3d().direct_space_state.intersect_ray(query)
				var planned := false
				for thing in main.area.plan:
					if thing.kind == "fallen" and thing.act == "avoid" and absf(float(thing.x0 + thing.x1) * 0.5 - spot.x) < 0.1:
						planned = true
				_check("a falling crystal lands and stays as an obstacle", fall.landed and not hit.is_empty() and absf(hit.position.z - spot.z) < 2.0 and planned and not p.dead, "landed %s, solid %s, in the plan %s" % [fall.landed, not hit.is_empty(), planned])
				fall = main.area.drop_crystal(p.global_position, 0.8)
				step = 4
				t = 0.0
		4: # and one on his head
			if t > 1.1:
				_check("a crystal landing on the runner splats him", p.dead)
				_fresh()
				var pad := BoostPad.new()
				pad.position = p.global_position + Vector3(0.0, 0.0, -24.0)
				main.area.add_child(pad)
				p.boosted.connect(func(): boosted = true)
		5: # through an aurora ring
			if boosted or t > 5.0 or p.dead:
				_check("an aurora ring boosts", boosted and p.speed > p.run_speed + 5.0, "speed %.1f against a run speed of %.1f" % [p.speed, p.run_speed])
				_fresh()
				p.set_physics_process(false)
		6: # an enemy on its own: over a crack
			crack = _crack_after(p.global_position.z)
			if crack.is_empty() and t < 20.0:
				p.global_position.z -= 100.0
			else:
				# (it comes up behind him, in line with him: wherever across the ring there's room for it)
				for x in [0.0, 10.0, -10.0, 16.0, -16.0, 5.0, -5.0, 13.0, -13.0]:
					p.global_position = Vector3(x, 0.0, float(crack.get("z1", 0.0)) - 14.0)
					main.area._physics_process(0.0)
					main.area._spawn_enemy(float(crack.get("z0", 0.0)) + 16.0)
					if not main.area.enemies.is_empty():
						break
				enemy = main.area.enemies.back() if not main.area.enemies.is_empty() else null
				step = 7
				t = 0.0
		7:
			if enemy == null or not is_instance_valid(enemy) or enemy.dead or enemy.global_position.z < float(crack.z1) - 6.0 or t > 8.0:
				var ok: bool = enemy != null and is_instance_valid(enemy) and not enemy.dead and enemy.global_position.z < float(crack.z1) - 6.0
				_check("an enemy jumps a crack", ok, "no enemy" if enemy == null or not is_instance_valid(enemy) else "z %.1f past a crack at %.1f..%.1f, y %.1f, dead %s" % [enemy.global_position.z, crack.z0, crack.z1, enemy.global_position.y, enemy.dead])
				_fresh()
				p.set_physics_process(false)
				# The runner out over the edge (held there), an enemy sent after him
				p.global_position = Vector3(-main.area.HALF - 14.0, 0.0, p.global_position.z - 30.0)
				main.area._spawn_enemy(p.global_position.z + 26.0)
				enemy = main.area.enemies.back() if not main.area.enemies.is_empty() else null
				if enemy:
					enemy.global_position.x = -main.area.HALF + 8.0
		8: # an enemy keeps off the edge
			if enemy == null or not is_instance_valid(enemy) or enemy.dead or t > 4.0:
				var ok: bool = enemy != null and is_instance_valid(enemy) and not enemy.dead and absf(enemy.global_position.x) < main.area.HALF and enemy.global_position.y > -0.5
				_check("an enemy keeps off the edge", ok, "no enemy" if enemy == null or not is_instance_valid(enemy) else "x %.1f y %.1f dead %s after %.1f s" % [enemy.global_position.x, enemy.global_position.y, enemy.dead, t])
				for line in log:
					print(line)
				return true
	return false
