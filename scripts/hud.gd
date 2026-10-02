extends CanvasLayer
## Test-area HUD: drop count, the DASH button, and a TUNE panel with
## sliders for the feel (speed, turning, jump, camera) plus a back-to-start button.

var player: CharacterBody3D
var cam: Camera3D
var restart: Callable # a new course, back at the start
var n64: CanvasLayer # the N64 filter, switched in the TUNE panel

var _drops := Label.new()
var _tune_button := Button.new()
var _panel := PanelContainer.new()
var _flash := ColorRect.new()
var _dash := Button.new()


func _ready() -> void:
	var theme := Theme.new()
	theme.default_font_size = 22
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = theme
	add_child(root)

	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.color = Color(0.75, 0.85, 1.0, 0.0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_flash)

	_drops.position = Vector2(20, 14)
	_drops.add_theme_font_size_override("font_size", 30)
	_drops.add_theme_color_override("font_outline_color", Color.BLACK)
	_drops.add_theme_constant_override("outline_size", 6)
	root.add_child(_drops)
	_on_drops(0)
	player.drops_changed.connect(_on_drops)
	player.splatted.connect(_on_splat)

	_tune_button.text = "TUNE"
	_tune_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 14)
	_tune_button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_tune_button.pressed.connect(func(): _panel.visible = not _panel.visible)
	root.add_child(_tune_button)

	# DASH, bottom right, under your right thumb; dim while it recharges
	_dash.text = "DASH"
	_dash.custom_minimum_size = Vector2(130, 130)
	_dash.add_theme_font_size_override("font_size", 28)
	_dash.focus_mode = Control.FOCUS_NONE
	_dash.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 24)
	_dash.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_dash.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_dash.button_down.connect(func(): player.input.dash.emit())
	root.add_child(_dash)

	_build_panel(root)


func _build_panel(root: Control) -> void:
	_panel.visible = false
	_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 14)
	_panel.offset_top = 70
	_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_panel.custom_minimum_size.x = 300
	root.add_child(_panel)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 6)
	_panel.add_child(rows)
	_slider(rows, "Speed", 4.0, 34.0, 1.0, player.run_speed, func(v): player.run_speed = v)
	_slider(rows, "Turn rate", 30.0, 240.0, 5.0, player.turn_rate, func(v): player.turn_rate = v)
	_slider(rows, "Jump height", 0.8, 5.0, 0.1, player.jump_height, func(v): player.jump_height = v)
	_slider(rows, "Camera distance", 3.0, 14.0, 0.5, cam.distance, func(v): cam.distance = v)
	_slider(rows, "Camera height", 1.0, 8.0, 0.25, cam.height, func(v): cam.height = v)
	var back := Button.new()
	back.text = "New course"
	back.pressed.connect(func(): restart.call())
	rows.add_child(back)
	var retro := CheckButton.new()
	retro.text = "N64 filter"
	retro.button_pressed = n64.visible
	retro.toggled.connect(func(on): n64.visible = on)
	rows.add_child(retro)


func _slider(rows: VBoxContainer, title: String, low: float, high: float, step: float, value: float, apply: Callable) -> void:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", 18)
	rows.add_child(label)
	var slider := HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = step
	slider.value = value
	slider.custom_minimum_size.y = 28
	var show := func(v: float):
		label.text = "%s: %s" % [title, str(snappedf(v, step))]
	slider.value_changed.connect(func(v):
		apply.call(v)
		show.call(v)
	)
	show.call(value)
	rows.add_child(slider)


## True when a screen point is on a button or the open panel (so it isn't a steer)
func is_over_ui(point: Vector2) -> bool:
	if _tune_button.get_global_rect().has_point(point) or _dash.get_global_rect().has_point(point):
		return true
	return _panel.visible and _panel.get_global_rect().has_point(point)


func _process(_delta: float) -> void:
	_dash.modulate.a = 0.4 if player.dash_cooldown > 0.0 else 1.0


func _on_drops(total: int) -> void:
	_drops.text = "DROPS %d" % total


func _on_splat() -> void:
	_flash.color.a = 0.35
	create_tween().tween_property(_flash, "color:a", 0.0, 0.4)
