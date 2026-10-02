extends SceneTree
## Close-up screenshots of Mercury running (front, side, a jump, a duck), with the chase
## camera swapped for one that circles it. Needs a window:
## godot --path . -s res://tests/model_shots.gd -- <out dir>

var main: Node
var t := 0.0
var taken := {}
# [time, name, camera offset from the player (in its facing frame: x right, z ahead)]
var shots := [
	[1.1, "front", Vector3(0.6, 1.3, 3.2)],
	[1.4, "three_quarter", Vector3(2.4, 1.4, 2.4)],
	[1.6, "side_1", Vector3(3.3, 1.1, 0.0)],
	[1.8, "side_2", Vector3(3.3, 1.1, 0.0)],
	[2.0, "side_3", Vector3(3.3, 1.1, 0.0)],
	[2.2, "side_4", Vector3(3.3, 1.1, 0.0)],
	[2.4, "side_5", Vector3(3.3, 1.1, 0.0)],
	[2.45, "behind", Vector3(0.0, 1.6, -3.4)],
	[2.6, "jump", Vector3(3.6, 1.6, 1.0)],
	[3.25, "duck", Vector3(2.8, 1.3, 1.0)],
	[3.9, "dash_ball", Vector3(3.0, 1.3, 1.5)],
]


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)


func _process(delta: float) -> bool:
	t += delta
	var player: CharacterBody3D = main.player
	var cam: Camera3D = main.cam
	cam.target = null
	# The camera for the next shot due
	var shot: Array = shots[-1]
	for s in shots:
		if not taken.has(s[1]):
			shot = s
			break
	# Keep it running on the clear stretch before the first hurdle
	if player.global_position.z < 110.0 and not player.dead and player.is_on_floor():
		player.global_position.z += 14.0
		player.reset_physics_interpolation()
	var at: Vector3 = player.get_global_transform_interpolated().origin
	var offset: Vector3 = shot[2]
	cam.global_position = at + player.right() * offset.x + Vector3.UP * offset.y + player.forward() * offset.z
	cam.look_at(at + Vector3.UP * 0.85)
	cam.fov = 45.0
	if t >= 2.5 and not taken.has("j"):
		taken.j = true
		player.input.jump.emit()
	if t >= 3.1 and not taken.has("d"):
		taken.d = true
		player.input.duck.emit()
	if t >= 3.8 and not taken.has("dash_go"):
		taken.dash_go = true
		player.input.dash.emit()
	var out: String = OS.get_cmdline_user_args()[0]
	for s in shots:
		if t >= s[0] and not taken.has(s[1]):
			taken[s[1]] = true
			root.get_texture().get_image().save_png("%s/%s.png" % [out, s[1]])
	return t > 4.0
