extends CanvasLayer
## The story, told before the title menu the first time (and from its STORY button after). One
## long look at Mercury through a long lens, very close, that starts at his feet and climbs him as
## it turns round him, and only at the end reaches his face: he lifts his head and his eye burns.
## Cut into that climb, glimpses of where he is: three suns over the sand, the crowd, one of them
## breaking, the pit, his own metal crawling back into him. A few words lie over the pictures,
## and they explain nothing: he was made; this is a place where things are made to break; what
## breaks, he takes in, which he can't bear and can't do without.
## main.gd sets the stage (the colosseum with its pit open, him standing clear of it) and hands
## over the camera; this runs the shots and says when it's done. Any key or touch skips it.

signal finished

const UI := preload("res://scripts/ui_theme.gd")
const AiInput := preload("res://scripts/ai_input.gd")
const Crystal := preload("res://scripts/crystal.gd")
## The shots, in order.
##   him: the long lens on Mercury. `turn` degrees round him (0 behind, 180 in front), `at` the
##     height on him it looks at (and is level with), each a pair: start and end. `fov` the lens.
##   eye / look: a glimpse of somewhere else: where the camera is and what it looks at (pairs),
##     relative to the middle of the arena.
##   say: words laid over it.  do: something that happens in it.  slow: how slowly time runs.
const STORY := [
	{ him = 4.2, turn = [140.0, 162.0], at = [0.12, 0.42], fov = 8.0, say = "poured" },
	{ scene = 3.0, eye = [Vector3(0.0, 1.5, 58.0), Vector3(0.0, 2.3, 54.0)], look = [Vector3(-4.0, 34.0, -60.0), Vector3(-4.0, 40.0, -60.0)], fov = 66.0, say = "under three suns" },
	{ him = 3.2, turn = [165.0, 190.0], at = [0.5, 0.82], fov = 8.0 },
	{ scene = 2.8, eye = [Vector3(48.0, 12.0, -8.0), Vector3(48.0, 12.5, 4.0)], look = [Vector3(82.0, 13.0, 20.0), Vector3(80.0, 13.0, 34.0)], fov = 30.0, do = "cheer", say = "they come to watch things break" },
	{ him = 3.2, turn = [195.0, 222.0], at = [0.9, 1.12], fov = 8.0, do = "shiver" },
	{ scene = 2.6, eye = [Vector3(-21.0, 1.1, 24.5), Vector3(-21.5, 1.3, 25.0)], look = [Vector3(-25.0, 1.1, 20.0), Vector3(-25.0, 1.3, 20.0)], fov = 30.0, do = "shatter", slow = 0.22, say = "what breaks" },
	{ him = 3.6, turn = [226.0, 254.0], at = [1.16, 1.36], fov = 9.0, do = "gather", say = "he keeps" },
	{ scene = 2.4, eye = [Vector3(0.0, 10.0, 21.0), Vector3(0.0, 7.5, 18.0)], look = [Vector3(0.0, -7.0, 0.0), Vector3(0.0, -9.0, 0.0)], fov = 46.0 },
	{ him = 3.4, turn = [300.0, 338.0], at = [1.2, 1.36], fov = 8.0, do = "shiver", say = "he hates the taste" },
	{ him = 6.0, turn = [174.0, 180.0], at = [1.36, 1.5], fov = 7.0, do = "rise", say = "he is never empty" },
]

var cam: Camera3D
var player: CharacterBody3D
var colosseum: Node3D # (for its crowd)
## False: keys and touches don't skip it (the screenshot script: a stray key press would)
var skippable := true

var _black := ColorRect.new()
var _line: Label
var _skip: Label
var _at := -1
var _clock := 0.0
var _last_tick := 0
var _done := true
var _did := false
var _victim: CharacterBody3D # the Crystalien that breaks
var _lens := CameraAttributesPractical.new()


func _ready() -> void:
	layer = 4
	visible = false
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.theme = UI.make()
	add_child(root)
	# The bars of a wide picture, top and bottom
	for top in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color.BLACK
		bar.set_anchors_preset(Control.PRESET_TOP_WIDE if top else Control.PRESET_BOTTOM_WIDE)
		bar.custom_minimum_size.y = 84
		if not top:
			bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
			bar.offset_top = -84
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(bar)
	# The words: small, low, over the picture
	_line = Label.new()
	_line.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_line.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_line.offset_top = -170
	_line.offset_bottom = -108
	_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_line.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_line.add_theme_font_size_override("font_size", 27)
	_line.add_theme_color_override("font_color", Color(0.9, 0.92, 1.0))
	_line.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.8))
	_line.add_theme_constant_override("outline_size", 8)
	_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_line)
	_black.color = Color(0.0, 0.0, 0.0, 0.0)
	_black.set_anchors_preset(Control.PRESET_FULL_RECT)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_black)
	_skip = UI.caption("any key to skip", 15)
	_skip.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 24)
	_skip.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_skip.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_skip.modulate.a = 0.4
	_skip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_skip)
	root.gui_input.connect(func(event: InputEvent):
		if skippable and (event is InputEventMouseButton or event is InputEventScreenTouch) and event.pressed:
			stop())
	# A long lens: what's behind him goes soft
	_lens.dof_blur_far_enabled = true
	_lens.dof_blur_far_transition = 14.0
	_lens.dof_blur_amount = 0.09


func playing() -> bool:
	return not _done


## stage: what main.gd built for it (the Crystalien that breaks is put in it, and goes with it)
func play(stage: Node3D) -> void:
	visible = true
	_done = false
	_at = -1
	_last_tick = Time.get_ticks_msec()
	_black.color.a = 0.0
	# One of them, standing off to one side, for the glimpse of it breaking
	var mind := AiInput.new()
	mind.brake = 1.0 # (standing)
	_victim = player.get_script().new()
	_victim.input = mind
	_victim.crystal = true
	_victim.add_child(mind)
	stage.add_child(_victim)
	var color: Color = Crystal.COLORS[4]
	_victim.make_brawler({ top = color.darkened(0.75), horizon = color, ground = color.darkened(0.9), glow = color, trail = color })
	_victim.place(Vector3(-25.0, 0.0, 20.0), 0.6)
	_next()


## Over (it ran out, or was skipped)
func stop() -> void:
	if _done:
		return
	_done = true
	visible = false
	Engine.time_scale = 1.0
	cam.attributes = null
	player.look_up(0.0)
	player.eye_glow(0.0)
	finished.emit()


func _unhandled_input(event: InputEvent) -> void:
	if _done or not skippable:
		return
	if (event is InputEventKey or event is InputEventJoypadButton) and event.pressed:
		get_viewport().set_input_as_handled()
		stop()


func _next() -> void:
	_at += 1
	_clock = 0.0
	_did = false
	if _at >= STORY.size():
		stop()
		return
	var beat: Dictionary = STORY[_at]
	Engine.time_scale = float(beat.get("slow", 1.0))
	_line.text = "  ".join(str(beat.get("say", "")).split("")) # (spaced out, letter by letter)
	_line.modulate.a = 0.0


func _process(_delta: float) -> void:
	if _done:
		return
	# (its own clock: one glimpse runs the world slowly, and the cuts mustn't slow with it)
	var tick := Time.get_ticks_msec()
	_clock += (tick - _last_tick) / 1000.0
	_last_tick = tick
	var beat: Dictionary = STORY[_at]
	var length: float = beat.get("him", beat.get("scene", 3.0))
	var t := clampf(_clock / length, 0.0, 1.0)
	var eased := smoothstep(0.0, 1.0, t)
	_line.modulate.a = smoothstep(0.5, 1.2, _clock) * (1.0 - smoothstep(length - 0.6, length - 0.1, _clock))
	cam.fov = beat.fov
	if beat.has("him"):
		# The long lens: a long way back, level with the part of him it's on, turning round him
		var turn := deg_to_rad(lerpf(beat.turn[0], beat.turn[1], eased))
		var height: float = lerpf(beat.at[0], beat.at[1], eased) * player.size
		var middle := player.global_position
		var back: float = 7.5 * player.size
		cam.global_position = middle + Vector3(sin(turn) * back, height + 0.05, cos(turn) * back)
		cam.look_at(middle + Vector3.UP * height)
		cam.attributes = _lens
		_lens.dof_blur_far_distance = back + 1.2
	else:
		cam.attributes = null
		cam.global_position = (beat.eye[0] as Vector3).lerp(beat.eye[1], eased)
		cam.look_at((beat.look[0] as Vector3).lerp(beat.look[1], eased))
	if beat.get("do", "") == "rise":
		# The end: his head comes up, his eye catches and burns, and it cuts on that
		player.look_up(smoothstep(1.2, 3.4, _clock))
		player.eye_glow(smoothstep(2.6, 4.6, _clock))
		_black.color = Color(1.0, 0.9, 0.85, smoothstep(length - 0.5, length, _clock))
	if not _did and _clock > length * 0.28:
		_did = true
		match beat.get("do", ""):
			"cheer":
				colosseum.cheer(1.0)
				colosseum.wave(Vector3(80.0, 0.0, 30.0))
			"shiver":
				player.shiver()
			"gather":
				player.gather()
			"shatter":
				_victim.blow_up(Vector3(5.0, 3.0, -2.0))
				colosseum.cheer(0.8)
	if _clock >= length:
		_next()
