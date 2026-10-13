extends CanvasLayer
## The HUD: a stats panel top left (what the mode's about: metres, mass, drops, smashes), a banner
## for zones and the arena's news, the arena's standings (top right) and a line of who burst whom,
## the round DASH button, and a TUNE panel with sliders for the feel (speed, turning, jump, camera)
## plus restart / menu. The look is ui_theme.gd's: gel and chrome, the year 2001. In the arena the feel sliders and restart are put away: it's a shared room.

const UI := preload("res://scripts/ui_theme.gd")
const DASH_WIDE := 0.6 # how much of the screen's width the DASH dome takes

var player: CharacterBody3D
var cam: Camera3D
var restart: Callable # a new course, back at the start
var to_menu: Callable # back to the title menu
var n64: CanvasLayer # the N64 filter, switched in the TUNE panel
var set_enemies: Callable # the test area's enemies on / off (the TUNE panel's switch)
## The TUNE panel's enemies switch: only shown in the test area (main.gd)
var enemies_switch := CheckButton.new()

var _stats_box := PanelContainer.new()
var _big := Label.new() # e.g. "1234 m" or "WAVE 3"
var _small := Label.new() # e.g. "ZONE 2 · 5 DROPS · 1 SMASHED"
var _banner := Label.new()
var _tune_button := Button.new()
var _panel := PanelContainer.new()
var _flash := ColorRect.new()
var _dash := ColorRect.new() # the DASH dome
var _dash_material := ShaderMaterial.new()
var _dash_press := 0.0
var _speed_lines := ColorRect.new() # streaks in from the edges of the screen after a boost
var _speed_material := ShaderMaterial.new()
var _rush := 0.0
var _board := PanelContainer.new() # the arena's standings
var _board_rows := VBoxContainer.new()
var _feed := Label.new()
var _feed_tween: Tween
var _solo_only: Array[Control] = [] # the TUNE panel's rows that don't belong in a shared room


func _ready() -> void:
	var theme := UI.make()
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = theme
	add_child(root)

	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.color = Color(0.75, 0.85, 1.0, 0.0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_flash)

	# The stats, top left on a glass panel
	_stats_box.position = Vector2(14, 12)
	_stats_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lines := VBoxContainer.new()
	lines.add_theme_constant_override("separation", -2)
	_stats_box.add_child(lines)
	_big.add_theme_font_size_override("font_size", 40)
	_small.add_theme_font_size_override("font_size", 18)
	_small.add_theme_color_override("font_color", UI.LIME)
	lines.add_child(_big)
	lines.add_child(_small)
	root.add_child(_stats_box)
	set_stats("", "")
	# The banner: zones, waves
	_banner = UI.heading("", 34, UI.ORANGE)
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 0)
	_banner.offset_top = 118
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.modulate.a = 0.0
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_banner)
	player.splatted.connect(_on_splat)

	_tune_button.text = "TUNE"
	_tune_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 14)
	_tune_button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_tune_button.pressed.connect(func(): _panel.visible = not _panel.visible)
	root.add_child(_tune_button)

	# The arena's standings, under the TUNE button
	_board.visible = false
	_board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_board.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 14)
	_board.offset_top = 70
	_board.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_board_rows.add_theme_constant_override("separation", 0)
	_board.add_child(_board_rows)
	root.add_child(_board)
	# ...and who burst whom, under the stats
	_feed.position = Vector2(18, 104)
	_feed.add_theme_font_size_override("font_size", 18)
	_feed.add_theme_color_override("font_color", UI.ORANGE)
	_feed.add_theme_color_override("font_outline_color", Color(0.02, 0.01, 0.05))
	_feed.add_theme_constant_override("outline_size", 6)
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_feed.modulate.a = 0.0
	root.add_child(_feed)

	_speed_lines.set_anchors_preset(Control.PRESET_FULL_RECT)
	_speed_lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_speed_material.shader = preload("res://shaders/speed_lines.gdshader")
	_speed_lines.material = _speed_material
	_speed_lines.visible = false
	root.add_child(_speed_lines)
	# DASH: a half-round of liquid metal standing on the middle of the bottom edge, see-through,
	# an arrow on it (shaders/dash_dome.gdshader). Touches on it are the runner input's (any finger, while
	# another steers); a mouse press is taken here.
	_dash.color = Color.WHITE
	_dash_material.shader = preload("res://shaders/dash_dome.gdshader")
	_dash.material = _dash_material
	_dash.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_dash.anchor_left = 0.5 - DASH_WIDE * 0.5
	_dash.anchor_right = 0.5 + DASH_WIDE * 0.5
	_dash.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_dash.mouse_filter = Control.MOUSE_FILTER_PASS
	_dash.gui_input.connect(func(event: InputEvent):
		# (a real mouse only: a finger's press comes through the runner input)
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.device != InputEvent.DEVICE_ID_EMULATION and (not event.pressed or is_over_dash(event.global_position)):
			player.input.dash_button_down = event.pressed
			if event.pressed:
				player.input.dash.emit()
	)
	player.dashed.connect(func(): _dash_press = 1.0)
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
	for row in rows.get_children():
		_solo_only.append(row)
	_slider(rows, "Camera distance", 3.0, 14.0, 0.5, cam.distance, func(v): cam.distance = v)
	_slider(rows, "Camera height", 1.0, 8.0, 0.25, cam.height, func(v): cam.height = v)
	var back := Button.new()
	back.text = "Restart (new course)"
	_solo_only.append(back)
	back.pressed.connect(func():
		_panel.visible = false
		restart.call()
	)
	rows.add_child(back)
	var leave := Button.new()
	leave.text = "Menu"
	leave.pressed.connect(func():
		_panel.visible = false
		to_menu.call()
	)
	rows.add_child(leave)
	var retro := CheckButton.new()
	retro.text = "N64 filter"
	retro.button_pressed = n64.visible
	retro.toggled.connect(func(on): n64.visible = on)
	rows.add_child(retro)
	enemies_switch.text = "Enemies"
	enemies_switch.button_pressed = true
	enemies_switch.toggled.connect(func(on): set_enemies.call(on))
	rows.add_child(enemies_switch)


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
## Through a boost ring: lines of speed, easing off
func rush() -> void:
	_rush = 1.0


## True when a screen point is on the DASH dome (the half-ellipse that fills its rectangle)
func is_over_dash(point: Vector2) -> bool:
	if not visible:
		return false
	var box := _dash.get_global_rect()
	if box.size.x <= 0.0 or box.size.y <= 0.0:
		return false
	var across := (point.x - box.get_center().x) / (box.size.x * 0.5)
	var up := (box.end.y - point.y) / box.size.y
	return up >= 0.0 and across * across + up * up <= 1.0


func is_over_ui(point: Vector2) -> bool:
	if _tune_button.get_global_rect().has_point(point) or is_over_dash(point):
		return true
	return _panel.visible and _panel.get_global_rect().has_point(point)


func _process(_delta: float) -> void:
	# The dome: about an eighth of the screen high (a shallower arc on a wide screen than a tall one)
	var screen := get_viewport().get_visible_rect().size
	var tall := clampf(screen.x * DASH_WIDE * 0.5, 80.0, screen.y * 0.125)
	_dash.offset_top = -tall
	_dash_material.set_shader_parameter("aspect", screen.x * DASH_WIDE * 0.5 / tall)
	_rush = move_toward(_rush, 0.0, _delta * 0.8)
	_speed_lines.visible = _rush > 0.0
	_speed_material.set_shader_parameter("strength", smoothstep(0.0, 0.4, _rush))
	_dash_press = move_toward(_dash_press, 0.0, _delta * 2.5)
	_dash_material.set_shader_parameter("press", _dash_press)
	_dash_material.set_shader_parameter("ready", 1.0 - clampf(player.dash_cooldown / 1.2, 0.0, 1.0))


## What the stats panel shows (empty: hidden)
func set_stats(big: String, small: String) -> void:
	_big.text = big
	_small.text = small
	_small.visible = small != ""
	_stats_box.visible = big != "" or small != ""


## The arena: its standings up, and the TUNE panel's feel sliders and restart put away
func set_arena(on: bool) -> void:
	_board.visible = false
	_feed.modulate.a = 0.0
	for row in _solo_only:
		row.visible = not on
	if not on:
		return
	# (anything tuned in the test area doesn't come into the room)
	player.turn_rate = 110.0
	player.jump_height = 2.2


## The arena's standings: rows of { name, mass, me }, most mass first; title: "ONLINE" or "BOTS"
func set_board(rows: Array, title: String) -> void:
	_board.visible = not _panel.visible
	var count := mini(rows.size(), 8) + 1 # (the title, then a line each: place and name, mass at the right)
	while _board_rows.get_child_count() < count:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 18)
		for side in 2:
			var label := Label.new()
			label.add_theme_font_size_override("font_size", 17)
			line.add_child(label)
		(line.get_child(0) as Label).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		(line.get_child(1) as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_board_rows.add_child(line)
	for k in _board_rows.get_child_count():
		var line: Control = _board_rows.get_child(k)
		line.visible = k < count
		if not line.visible:
			continue
		var mine: bool = k > 0 and rows[k - 1].me
		var color: Color = UI.AQUA if k == 0 else (UI.LIME if mine else UI.CHROME)
		var left: Label = line.get_child(0)
		var right: Label = line.get_child(1)
		left.text = title if k == 0 else "%d  %s" % [k, rows[k - 1].name]
		right.text = "MASS" if k == 0 else str(rows[k - 1].mass)
		left.add_theme_color_override("font_color", color)
		right.add_theme_color_override("font_color", color)


## A line of the arena's news under the stats, fading after a moment
func feed(text: String) -> void:
	_feed.text = text
	if _feed_tween:
		_feed_tween.kill()
	_feed.modulate.a = 1.0
	_feed_tween = create_tween()
	_feed_tween.tween_interval(2.5)
	_feed_tween.tween_property(_feed, "modulate:a", 0.0, 0.6)


## A big line across the middle that pops in and fades (a new zone, the arena's news)
func banner(text: String, sub := "") -> void:
	_banner.text = text if sub == "" else "%s\n%s" % [text, sub]
	_banner.pivot_offset = _banner.size * 0.5
	var tween := create_tween()
	_banner.scale = Vector2(1.2, 1.2)
	tween.tween_property(_banner, "modulate:a", 1.0, 0.15)
	tween.parallel().tween_property(_banner, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_interval(1.4)
	tween.tween_property(_banner, "modulate:a", 0.0, 0.5)


func _on_splat() -> void:
	_flash.color.a = 0.35
	create_tween().tween_property(_flash, "color:a", 0.0, 0.4)
