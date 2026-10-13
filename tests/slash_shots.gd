extends SceneTree
## Screenshots of the dash's slash, in the model viewer (Mercury running on the spot): three dashes
## in a row (left blade, right blade, then the X), each caught raised, mid-sweep, late and at its
## end, from in front and to one side. Needs a window:
## godot --path . -s res://tests/slash_shots.gd -- <out dir>

var main: Node
var t := 0.0
var taken := {}
const DASHES := [2.0, 3.6, 5.2] # when each dash is pressed (after the shaders have warmed up)
const NAMES := ["left", "right", "x"]
# After each press: [seconds, label] (the kick's two steps take 0.3 s, then the sweep 0.18 s)
const MOMENTS := [[0.2, "raised"], [0.34, "early"], [0.4, "mid"], [0.46, "late"], [0.7, "end"]]


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
	viewer._yaw = PI - 0.75
	viewer._pitch = 0.15
	viewer._dist = 4.2
	for d in DASHES.size():
		var key := "dash%d" % d
		if t >= DASHES[d] and not taken.has(key):
			taken[key] = true
			main.player.input.dash.emit()
		for m in MOMENTS:
			var name := "%s_%s" % [NAMES[d], m[1]]
			if t >= DASHES[d] + float(m[0]) and not taken.has(name):
				taken[name] = true
				root.get_texture().get_image().save_png("%s/%s.png" % [out, name])
	return t > 6.0
