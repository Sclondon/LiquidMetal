extends SceneTree
## Screenshots of the story that plays behind the title menu: a picture part-way through every
## shot of one round of it (the menu over it, as it's seen). Needs a window:
## godot --path . -s res://tests/story_shots.gd -- <out dir>

var main: Node
var seen := -1
var since := 0.0
var shot := false
var t := 0.0


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	main.use_pads = false
	root.add_child(main)


func _shot(name: String) -> void:
	root.get_texture().get_image().save_png("%s/%s.png" % [OS.get_cmdline_user_args()[0], name])


func _process(delta: float) -> bool:
	t += delta
	if t < 0.5:
		return false
	if main.story.rounds > 0:
		return true
	var at: int = main.story._at
	if at != seen:
		seen = at
		since = 0.0
		shot = false
	since += delta
	if not shot and since > (4.7 if at == main.story.STORY.size() - 1 else (0.3 if Engine.time_scale < 1.0 else 1.4)):
		shot = true
		_shot("%02d" % at)
	return false
