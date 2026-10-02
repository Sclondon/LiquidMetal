extends CanvasLayer
## The title menu (ENDLESS RUN / TEST AREA, with your best run) and the game-over card after
## a splat in endless mode (how far, RUN AGAIN / MENU).

signal endless_chosen
signal test_area_chosen
signal menu_chosen

const CHROME := Color(0.86, 0.9, 1.0)
const GLOW := Color(1.0, 0.45, 0.75)

var _title := VBoxContainer.new()
var _over := VBoxContainer.new()
var _best_label := Label.new()
var _result := Label.new()
var _result_best := Label.new()
var _shade := ColorRect.new()


func _ready() -> void:
	layer = 3
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_shade.color = Color(0.02, 0.01, 0.05, 0.45)
	_shade.mouse_filter = Control.MOUSE_FILTER_STOP # nothing behind the menu takes touches
	root.add_child(_shade)

	for box in [_title, _over]:
		box.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
		box.grow_horizontal = Control.GROW_DIRECTION_BOTH
		box.grow_vertical = Control.GROW_DIRECTION_BOTH
		box.alignment = BoxContainer.ALIGNMENT_CENTER
		box.add_theme_constant_override("separation", 18)
		root.add_child(box)

	_title.add_child(_heading("LIQUID METAL", 88))
	_best_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_best_label.add_theme_font_size_override("font_size", 26)
	_best_label.add_theme_color_override("font_color", CHROME)
	_title.add_child(_best_label)
	_title.add_child(_button("ENDLESS RUN", func(): endless_chosen.emit()))
	_title.add_child(_button("TEST AREA", func(): test_area_chosen.emit()))

	_over.add_child(_heading("SPLAT!", 80))
	for label in [_result, _result_best]:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_color_override("font_color", CHROME)
		_over.add_child(label)
	_result.add_theme_font_size_override("font_size", 40)
	_result_best.add_theme_font_size_override("font_size", 26)
	_over.add_child(_button("RUN AGAIN", func(): endless_chosen.emit()))
	_over.add_child(_button("MENU", func(): menu_chosen.emit()))
	hide_all()


func show_title(best: int) -> void:
	_best_label.text = "BEST  %d m" % best if best > 0 else "HOLD TO TURN · SWIPE TO MOVE"
	_shade.visible = true
	_title.visible = true
	_over.visible = false


func show_game_over(metres: int, drops: int, best: int, new_best: bool) -> void:
	_result.text = "%d m  ·  %d drops" % [metres, drops]
	_result_best.text = "NEW BEST!" if new_best else "BEST  %d m" % best
	_shade.visible = true
	_title.visible = false
	_over.visible = true


func hide_all() -> void:
	_shade.visible = false
	_title.visible = false
	_over.visible = false


func is_open() -> bool:
	return _shade.visible


func _heading(text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", CHROME)
	label.add_theme_color_override("font_outline_color", GLOW)
	label.add_theme_constant_override("outline_size", 10)
	return label


func _button(text: String, pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(380, 84)
	button.add_theme_font_size_override("font_size", 34)
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(pressed)
	return button
