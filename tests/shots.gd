extends SceneTree
## Saves a few screenshots of the test area while the lane bot plays.
## Run (needs a window): godot --path . -s res://tests/shots.gd -- <out dir>

var main: Node
var player: CharacterBody3D
var t := 0.0
var shots := [[1.0, "start"], [1.25, "dash"], [2.55, "jump"], [4.0, "duck"], [5.6, "dodge"], [7.2, "turn"]]
var acted := {}


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	main.start_mode = "test"
	root.add_child(main)


func _process(delta: float) -> bool:
	t += delta
	player = main.player
	var input: Node = player.input
	var z := player.global_position.z
	if z < 105.0 + 4.5 and not acted.has("j"):
		acted.j = true
		input.jump.emit()
	if z < 84.0 + 3.0 and not acted.has("d"):
		acted.d = true
		input.duck.emit()
	if z < 63.0 + 6.0 and not acted.has("l"):
		acted.l = true
		input.dodge.emit(-1.0)
	if t > 1.1 and not acted.has("dash_go"):
		acted.dash_go = true
		input.dash.emit()
	if t > 6.2:
		input.turn = -1.0
	var out: String = OS.get_cmdline_user_args()[0]
	for shot in shots:
		if t >= shot[0] and not acted.has(shot[1]):
			acted[shot[1]] = true
			root.get_texture().get_image().save_png("%s/%s.png" % [out, shot[1]])
	return t > 7.5
