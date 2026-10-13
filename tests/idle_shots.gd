extends SceneTree
## Screenshots of Mercury standing still, in the model viewer: idle (speed 0, breathing) from the
## front and the side, the knees from behind, a close-up of the head, then held in the T-pose. Needs a window:
## godot --path . -s res://tests/idle_shots.gd -- <out dir>

var main: Node
var t := 0.0
var taken := {}
# [time, name, yaw round it (PI: its face), pitch, distance]
const SHOTS := [[2.6, "idle_front", PI - 0.35, 0.12, 4.4], [3.4, "idle_side", PI * 0.5, 0.1, 4.4], [3.7, "knees_back", 0.5, 0.05, 2.4], [4.0, "head", PI - 0.4, 0.55, 2.6], [5.2, "tpose_front", PI, 0.1, 4.4], [5.8, "tpose_quarter", PI - 0.8, 0.3, 4.4]]


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	main.start_mode = "viewer"
	main.enemies = false
	main.use_pads = false
	root.add_child(main)


func _process(delta: float) -> bool:
	t += delta
	var out: String = OS.get_cmdline_user_args()[0]
	var viewer: CanvasLayer = main.viewer
	viewer._spin = false
	if t > 0.5 and not taken.has("stop"):
		taken.stop = true
		viewer._slider.value = 0.0
	if t > 4.2 and not taken.has("t"):
		taken.t = true
		viewer._set_tpose(true)
	var shot: Array = SHOTS[-1]
	for s in SHOTS:
		if not taken.has(s[1]):
			shot = s
			break
	viewer._yaw = shot[2]
	viewer._pitch = shot[3]
	viewer._dist = shot[4]
	for s in SHOTS:
		if t >= s[0] and not taken.has(s[1]):
			taken[s[1]] = true
			root.get_texture().get_image().save_png("%s/%s.png" % [out, s[1]])
	return t > 6.0
