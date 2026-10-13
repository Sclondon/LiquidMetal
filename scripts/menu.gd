extends CanvasLayer
## The title menu (ENDLESS RUN / ARENA / TEST AREA / MODEL VIEWER, the difficulty, your bests at
## it) and the game-over card after a splat (how it went, AGAIN / MENU).

signal endless_chosen
signal arena_chosen
signal test_area_chosen
signal viewer_chosen
signal story_chosen
signal menu_chosen
signal again_chosen
signal difficulty_chosen(level: int)

const UI := preload("res://scripts/ui_theme.gd")
const Difficulty := preload("res://scripts/difficulty.gd")

var _title := VBoxContainer.new()
var _over := VBoxContainer.new()
var _bests := Label.new()
var _over_heading: Label
var _result := Label.new()
var _result_more := Label.new()
var _result_best := Label.new()
var _shade := ColorRect.new()
var _difficulty: Button
var _level := Difficulty.DEFAULT


func _ready() -> void:
	layer = 3
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UI.make()
	add_child(root)
	_shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_shade.color = Color(0.02, 0.01, 0.05, 0.5)
	_shade.mouse_filter = Control.MOUSE_FILTER_STOP # nothing behind the menu takes touches
	root.add_child(_shade)

	for box in [_title, _over]:
		box.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
		box.grow_horizontal = Control.GROW_DIRECTION_BOTH
		box.grow_vertical = Control.GROW_DIRECTION_BOTH
		box.alignment = BoxContainer.ALIGNMENT_CENTER
		box.add_theme_constant_override("separation", 5) # (the title's six buttons, bests and tips fit 720 high)
		root.add_child(box)

	var name_box := HBoxContainer.new()
	name_box.alignment = BoxContainer.ALIGNMENT_CENTER
	name_box.add_theme_constant_override("separation", 24)
	name_box.add_child(UI.heading("LIQUID", 76))
	name_box.add_child(UI.heading("METAL", 76, UI.CYAN))
	_title.add_child(name_box)
	_bests.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bests.add_theme_font_size_override("font_size", 22)
	_bests.add_theme_color_override("font_color", UI.PINK)
	_title.add_child(_bests)
	_title.add_child(_spacer(6))
	_title.add_child(_button("ENDLESS RUN", "how far can you get?", func(): endless_chosen.emit()))
	_title.add_child(_button("ARENA", "online: fight the room for top mass", func(): arena_chosen.emit()))
	_title.add_child(_button("TEST AREA", "play around", func(): test_area_chosen.emit()))
	_title.add_child(_button("MODEL VIEWER", "get a good look at Mercury", func(): viewer_chosen.emit()))
	var story := _button("STORY", "", func(): story_chosen.emit())
	story.custom_minimum_size.y = 52
	story.add_theme_font_size_override("font_size", 22)
	_title.add_child(story)
	# The difficulty: press to step through them (left / right on a gamepad or keys step back too)
	_difficulty = _button("", "", func(): _step_difficulty(1))
	_difficulty.custom_minimum_size.y = 84
	_difficulty.add_theme_font_size_override("font_size", 24)
	_difficulty.gui_input.connect(func(event: InputEvent):
		for step in [[&"ui_left", -1], [&"ui_right", 1]]:
			if event.is_action_pressed(step[0]):
				_step_difficulty(step[1])
				_difficulty.accept_event())
	_title.add_child(_difficulty)
	_show_difficulty()
	_title.add_child(_spacer(4))
	var tips := UI.caption("HOLD a side to turn  ·  SWIPE to jump, duck, dodge  ·  DASH to slash", 16)
	tips.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tips.custom_minimum_size.x = 440
	_title.add_child(tips)

	_over_heading = UI.heading("SPLAT!", 84)
	_over.add_child(_over_heading)
	for label in [_result, _result_more, _result_best]:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_over.add_child(label)
	_result.add_theme_font_size_override("font_size", 46)
	_result_more.add_theme_font_size_override("font_size", 24)
	_result_best.add_theme_font_size_override("font_size", 26)
	_result_best.add_theme_color_override("font_color", UI.PINK)
	_over.add_child(_spacer(6))
	_over.add_child(_button("AGAIN", "", func(): again_chosen.emit()))
	_over.add_child(_button("MENU", "", func(): menu_chosen.emit()))
	hide_all()


func show_title(best_run: int, best_mass: int, level: int) -> void:
	_level = level
	_show_difficulty()
	show_bests(best_run, best_mass)
	_shade.visible = true
	_title.visible = true
	_focus_first(_title)
	_over.visible = false
	_pop(_title)


## The best run at the difficulty picked, and the most mass he's had in the arena
func show_bests(best_run: int, best_mass: int) -> void:
	var bits := []
	if best_run > 0:
		bits.append("BEST RUN %d" % best_run)
	if best_mass > 0:
		bits.append("BEST MASS %d" % best_mass)
	_bests.text = "   ·   ".join(bits)
	_bests.visible = not bits.is_empty()


func _step_difficulty(by: int) -> void:
	_level = posmod(_level + by, Difficulty.TIERS.size())
	_show_difficulty()
	difficulty_chosen.emit(_level)


func _show_difficulty() -> void:
	var tier: Dictionary = Difficulty.TIERS[_level]
	_difficulty.text = "<   DIFFICULTY: %s   >\n%s" % [tier.name, tier.note]


## headline: the big result; more: the details; best: the best line (or NEW BEST!)
func show_game_over(headline: String, more: String, best: String) -> void:
	_result.text = headline
	_result_more.text = more
	_result_best.text = best
	_shade.visible = true
	_title.visible = false
	_over.visible = true
	_focus_first(_over)
	_pop(_over)


func hide_all() -> void:
	_shade.visible = false
	_title.visible = false
	_over.visible = false


func is_open() -> bool:
	return _shade.visible


func _pop(box: Control) -> void:
	box.pivot_offset = box.size * 0.5
	box.scale = Vector2(0.9, 0.9)
	box.modulate.a = 0.0
	var tween := create_tween().set_parallel(true)
	tween.tween_property(box, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(box, "modulate:a", 1.0, 0.2)


func _focus_first(box: Control) -> void:
	for child in box.get_children():
		if child is Button:
			child.grab_focus.call_deferred()
			return


func _spacer(height: int) -> Control:
	var gap := Control.new()
	gap.custom_minimum_size.y = height
	return gap


func _button(text: String, sub: String, pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text if sub == "" else "%s\n%s" % [text, sub]
	button.custom_minimum_size = Vector2(440, 84 if sub != "" else 72)
	button.add_theme_font_size_override("font_size", 28)
	button.focus_mode = Control.FOCUS_ALL # (a gamepad moves between them and presses A)
	button.pressed.connect(pressed)
	return button
