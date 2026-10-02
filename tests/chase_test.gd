extends SceneTree
## Headless check that enemies chase: in endless mode, at running speed, an enemy spawned behind
## the runner closes the gap on it (and lines up on it).
## Run: godot --headless --path . -s res://tests/chase_test.gd

var main: Node
var t := 0.0
var enemy: CharacterBody3D
var start_gap := 0.0
var started := 0.0


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	main.start_mode = "endless"
	main.use_pads = false
	root.add_child(main)


func _process(delta: float) -> bool:
	t += delta
	var p: CharacterBody3D = main.player
	if enemy == null and t > 0.5:
		main.area.with_enemies = false # just the one, for the test
		main.area._spawn_enemy(p.global_position.z + 25.0)
		enemy = main.area.enemies.back()
		enemy.global_position.x = 2.5 # off his line: it has to line up on him too
		start_gap = enemy.global_position.z - p.global_position.z
		started = t
	if enemy == null:
		return false
	var gap := enemy.global_position.z - p.global_position.z
	if t - started > 2.0 or p.dead or gap < 2.0:
		print("%s enemy closed from %.1f m to %.1f m behind in %.1f s (dx now %.2f)" % ["PASS" if gap < start_gap - 6.0 else "FAIL", start_gap, gap, t - started, enemy.global_position.x - p.global_position.x])
		return true
	return false
