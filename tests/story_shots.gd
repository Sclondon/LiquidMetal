extends SceneTree
## Screenshots of the story before the menu: a picture part-way through every shot and every card,
## and one of the title menu it ends on. Needs a window:
## godot --path . -s res://tests/story_shots.gd -- <out dir>

var main: Node
var seen := -1
var since := 0.0
var shot := false
var over := false
var t := 0.0


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	main.use_pads = false
	root.add_child(main)


func _shot(name: String) -> void:
	root.get_texture().get_image().save_png("%s/%s.png" % [OS.get_cmdline_user_args()[0], name])


func _process(delta: float) -> bool:
	t += delta
	if seen == -1 and t > 0.5:
		main.story.finished.connect(func(): over = true)
		main.story.skippable = false
		main.start_story()
		seen = 0
		return false
	if seen < 0:
		return false
	if over:
		since += delta
		if since > 1.0:
			_shot("99_menu")
			return true
		return false
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
