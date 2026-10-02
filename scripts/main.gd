extends Node3D
## Liquid Metal. Builds the scene in code: sky and light, the course, the runner, its input, the
## chase camera, the HUD and the menu. Three modes from the menu: ENDLESS RUN (a lane that never
## ends, faster and harder through its zones; a splat ends the run), ARENA (waves of enemy runners
## in a walled arena; dash through them; a splat ends it) and TEST AREA (the playground, where a
## splat just rewinds you a moment).

const RunnerInput := preload("res://scripts/runner_input.gd")
const Player := preload("res://scripts/player.gd")
const FollowCam := preload("res://scripts/follow_cam.gd")
const TestArea := preload("res://scripts/test_area.gd")
const Hud := preload("res://scripts/hud.gd")
const Endless := preload("res://scripts/endless.gd")
const Menu := preload("res://scripts/menu.gd")
const Arena := preload("res://scripts/arena.gd")

const BEST_FILE := "user://bests.cfg"
const ARENA_SPEED := 13.0
const ENDLESS_SPEED := Vector2(14.0, 26.0) # run speed at the start, and by ENDLESS_FAST metres
const ENDLESS_FAST := 3000.0

## Where it opens: "menu", or straight into "test" or "endless" (the tests use these)
@export var start_mode := "menu"
## False: gamepads ignored (screenshot tests on a machine with a controller plugged in)
@export var use_pads := true
## False: no enemy runners (tests that need a clear lane)
@export var enemies := true
var mode := ""

var area: Node3D
var player: CharacterBody3D
var cam: Camera3D
var n64: CanvasLayer # the N64 filter over the 3D (under the HUD)
var hud: CanvasLayer
var menu: CanvasLayer
var _input: Node
var _best_run := 0 # endless: best score
var _best_wave := 0 # arena: furthest wave
var _smashes := 0 # enemies dashed through this game
var _sky: ProceduralSkyMaterial
var _environment: Environment


func _ready() -> void:
	_build_environment()

	var input := RunnerInput.new()
	input.use_pads = use_pads
	_input = input
	add_child(input)

	player = Player.new()
	player.input = input
	add_child(player)
	player.splatted.connect(_on_splat)
	player.smashed.connect(func(): _smashes += 1)

	cam = FollowCam.new()
	cam.target = player
	add_child(cam)

	n64 = CanvasLayer.new()
	n64.layer = 1
	var screen := ColorRect.new()
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var filter := ShaderMaterial.new()
	filter.shader = preload("res://shaders/n64.gdshader")
	screen.material = filter
	n64.add_child(screen)
	add_child(n64)

	hud = Hud.new()
	hud.layer = 2
	hud.n64 = n64
	hud.player = player
	hud.cam = cam
	hud.restart = restart
	hud.to_menu = show_menu
	add_child(hud)
	input.is_over_ui = hud.is_over_ui

	menu = Menu.new()
	menu.endless_chosen.connect(start_endless)
	menu.test_area_chosen.connect(start_test)
	menu.arena_chosen.connect(start_arena)
	menu.menu_chosen.connect(show_menu)
	menu.again_chosen.connect(restart)
	add_child(menu)
	_load_bests()

	# Lay the HUD out for the screen's shape, so it isn't tiny on a portrait phone
	get_tree().root.size_changed.connect(_fit_ui)
	_fit_ui()

	match start_mode:
		"test":
			start_test()
		"endless":
			start_endless()
		"arena":
			start_arena()
		_:
			show_menu()


func _unhandled_input(event: InputEvent) -> void:
	# Gamepad Start: back to the menu
	if event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_START and mode != "menu":
		show_menu()


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.pressed or event.echo:
		return
	if event.physical_keycode == KEY_R and mode != "menu":
		restart()
	elif event.physical_keycode == KEY_ESCAPE and mode != "menu":
		show_menu()


## The test area: the playground, splats rewind you
func start_test() -> void:
	mode = "test"
	var course := TestArea.new()
	course.runner = player
	course.with_enemies = enemies
	_use_course(course)
	player.rewind_on_splat = true
	player.run_speed = ENDLESS_SPEED.x
	_play()


## Endless: a fresh lane, from the start; a splat ends the run
func start_endless() -> void:
	mode = "endless"
	var course := Endless.new()
	course.runner = player
	course.with_enemies = enemies
	course.zone_changed.connect(_on_zone)
	_use_course(course)
	player.rewind_on_splat = false
	player.run_speed = ENDLESS_SPEED.x
	_play()
	_set_sky(Endless.ZONES[0], 0.0)
	hud.banner("ENDLESS", Endless.ZONES[0].name)


## Arena: waves of enemies in a walled square; a splat ends it
func start_arena() -> void:
	mode = "arena"
	var course := Arena.new()
	course.runner = player
	course.with_enemies = enemies
	course.wave_started.connect(func(wave): hud.banner("WAVE %d" % wave, "%d coming" % mini(wave + 1, 16)))
	course.wave_cleared.connect(func(wave): hud.banner("CLEARED", "wave %d" % wave))
	_use_course(course)
	player.rewind_on_splat = false
	player.run_speed = ARENA_SPEED
	_play()
	_set_sky({ top = Color(0.02, 0.06, 0.04), horizon = Color(0.4, 1.0, 0.6), fog = Color(0.2, 0.35, 0.25) }, 0.0)


## The title menu, over the runner standing at the start of the test area
func show_menu() -> void:
	mode = "menu"
	if area == null or not area is TestArea:
		_use_course(TestArea.new())
	player.place(area.start_position, area.start_heading)
	player.set_physics_process(false)
	_input.set_process_input(false)
	hud.visible = false
	cam.snap()
	_set_sky(Endless.ZONES[0], 0.0)
	menu.show_title(_best_run, _best_wave)


## A freshly generated course, and back to the start of it
func restart() -> void:
	if mode == "endless":
		start_endless()
		return
	if mode == "arena":
		start_arena()
		return
	area.generate()
	player.restart()
	cam.snap()


func _use_course(course: Node3D) -> void:
	if area:
		area.free() # gone now, not at the end of the frame: the new course may overlap it
	area = course
	add_child(area)


func _play() -> void:
	menu.hide_all()
	hud.visible = true
	player.reset_drops()
	_smashes = 0
	player.place(area.start_position, area.start_heading)
	player.set_physics_process(true)
	_input.set_process_input(true)
	cam.snap()


func _process(_delta: float) -> void:
	match mode:
		"endless":
			var metres: float = area.distance()
			if not player.dead:
				player.run_speed = lerpf(ENDLESS_SPEED.x, ENDLESS_SPEED.y, clampf(metres / ENDLESS_FAST, 0.0, 1.0))
			hud.set_stats("%d m" % int(metres), "ZONE %d  ·  %d DROPS  ·  %d SMASHED" % [area.zone + 1, player.drops, _smashes])
		"arena":
			hud.set_stats("WAVE %d" % maxi(area.wave, 1), "%d SMASHED  ·  %d LEFT  ·  %d DROPS" % [_smashes, area.alive_count(), player.drops])
		"test":
			hud.set_stats("TEST AREA", "%d DROPS  ·  %d SMASHED" % [player.drops, _smashes])
		_:
			hud.set_stats("", "")


## Endless: the score, from how far, the drops and the smashes
func _score() -> int:
	return int(area.distance()) + player.drops * 5 + _smashes * 50


func _on_zone(index: int, look: Dictionary) -> void:
	hud.banner("ZONE %d" % (index + 1), look.name)
	_set_sky(look, 2.5)


## The sky's colours (and the fog's), eased over to a new look
func _set_sky(look: Dictionary, time: float) -> void:
	if _sky == null:
		return
	if time <= 0.0:
		_sky.sky_top_color = look.top
		_sky.sky_horizon_color = look.horizon
		_environment.fog_light_color = look.fog
		return
	var tween := create_tween().set_parallel(true)
	tween.tween_property(_sky, "sky_top_color", look.top, time)
	tween.tween_property(_sky, "sky_horizon_color", look.horizon, time)
	tween.tween_property(_environment, "fog_light_color", look.fog, time)


func _on_splat() -> void:
	if mode != "endless" and mode != "arena":
		return
	var playing := mode
	var headline := ""
	var more := ""
	var best := ""
	if mode == "endless":
		var score := _score()
		headline = "%d m" % int(area.distance())
		more = "SCORE %d  ·  %d drops  ·  %d smashed  ·  zone %d" % [score, player.drops, _smashes, area.zone + 1]
		if score > _best_run:
			_best_run = score
			best = "NEW BEST!"
		else:
			best = "BEST %d" % _best_run
	else:
		var wave: int = area.wave
		headline = "WAVE %d" % wave
		more = "%d smashed  ·  %d drops" % [_smashes, player.drops]
		if wave > _best_wave:
			_best_wave = wave
			best = "NEW BEST!"
		else:
			best = "BEST WAVE %d" % _best_wave
	_save_bests()
	_input.set_process_input(false)
	# Let the splat land first
	await get_tree().create_timer(0.9).timeout
	if mode == playing and player.dead:
		hud.visible = false
		menu.show_game_over(headline, more, best)


func _load_bests() -> void:
	var file := ConfigFile.new()
	if file.load(BEST_FILE) == OK:
		_best_run = file.get_value("best", "run", 0)
		_best_wave = file.get_value("best", "wave", 0)


func _save_bests() -> void:
	# Real play only (never a test run)
	if start_mode != "menu" or get_tree().get_script() != null or OS.has_feature("editor"):
		return
	var file := ConfigFile.new()
	file.set_value("best", "run", _best_run)
	file.set_value("best", "wave", _best_wave)
	file.save(BEST_FILE)


func _fit_ui() -> void:
	var window := get_tree().root
	window.content_scale_size = Vector2i(720, 1280) if window.size.x < window.size.y else Vector2i(1280, 720)


func _build_environment() -> void:
	# Dusk: deep blue overhead, a hot pink-orange band at the horizon for the chrome to catch
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.04, 0.05, 0.16)
	sky_material.sky_horizon_color = Color(0.95, 0.5, 0.48)
	sky_material.sky_curve = 0.08
	sky_material.ground_bottom_color = Color(0.02, 0.02, 0.04)
	sky_material.ground_horizon_color = Color(0.45, 0.25, 0.35)
	sky_material.sun_angle_max = 20.0
	_sky = sky_material
	var sky := Sky.new()
	sky.sky_material = sky_material

	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.glow_enabled = true
	environment.glow_intensity = 0.7
	environment.glow_bloom = 0.05
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.5, 0.3, 0.42)
	environment.fog_density = 0.004
	environment.fog_sky_affect = 0.0
	_environment = environment
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38.0, 35.0, 0.0)
	sun.light_energy = 1.2
	sun.light_color = Color(1.0, 0.85, 0.8)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 70.0
	add_child(sun)
