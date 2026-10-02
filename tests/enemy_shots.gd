extends SceneTree
## Screenshots of an enemy runner up close in endless mode, then one blowing up. Needs a window:
## godot --path . -s res://tests/enemy_shots.gd -- <out dir>

var main: Node
var t := 0.0
var enemy: Node3D
var taken := 0
var boom := -1.0


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	main.start_mode = "endless"
	main.use_pads = false
	root.add_child(main)


func _process(delta: float) -> bool:
	t += delta
	var p: CharacterBody3D = main.player
	p.run_speed = 6.0
	if enemy == null and t > 0.5:
		main.area._spawn_enemy(p.global_position.z - 30.0)
		enemy = main.area.enemies.back()
		enemy.run_speed = 6.0
	if enemy == null:
		return false
	var cam: Camera3D = main.cam
	cam.target = null
	var at: Vector3 = enemy.global_position
	cam.global_position = at + Vector3(1.6, 1.3, 3.2)
	cam.look_at(at + Vector3.UP * 0.9)
	cam.fov = 50.0
	var out: String = OS.get_cmdline_user_args()[0]
	if taken == 0 and t > 2.0:
		root.get_texture().get_image().save_png(out + "/enemy.png")
		taken = 1
		enemy.blow_up(Vector3(0, 0, -12))
		boom = t
	elif taken == 1 and t > boom + 0.12:
		root.get_texture().get_image().save_png(out + "/boom1.png")
		taken = 2
	elif taken == 2 and t > boom + 0.6:
		root.get_texture().get_image().save_png(out + "/boom2.png")
		return true
	return t > 10.0
