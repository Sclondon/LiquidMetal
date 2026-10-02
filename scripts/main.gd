extends Node3D
## Liquid Metal. Builds the scene in code: sky and light, the course, the runner, its input, the
## chase camera, the HUD and the menu. Two modes from the menu: ENDLESS RUN (a lane that never
## ends, faster the further you get; a splat ends the run) and TEST AREA (the playground, where
## a splat just rewinds you a moment).

const RunnerInput := preload("res://scripts/runner_input.gd")
const Player := preload("res://scripts/player.gd")
const FollowCam := preload("res://scripts/follow_cam.gd")
const TestArea := preload("res://scripts/test_area.gd")
const Hud := preload("res://scripts/hud.gd")
const Endless := preload("res://scripts/endless.gd")
const Menu := preload("res://scripts/menu.gd")

const BEST_FILE := "user://best_run.txt"
const ENDLESS_SPEED := Vector2(14.0, 26.0) # run speed at the start, and by ENDLESS_FAST metres
const ENDLESS_FAST := 3000.0

## Where it opens: "menu", or straight into "test" or "endless" (the tests use these)
@export var start_mode := "menu"
var mode := ""

var area: Node3D
var player: CharacterBody3D
var cam: Camera3D
var n64: CanvasLayer # the N64 filter over the 3D (under the HUD)
var hud: CanvasLayer
var menu: CanvasLayer
var _input: Node
var _best := 0


func _ready() -> void:
	_build_environment()

	var input := RunnerInput.new()
	_input = input
	add_child(input)

	player = Player.new()
	player.input = input
	add_child(player)
	player.splatted.connect(_on_splat)

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
	menu.menu_chosen.connect(show_menu)
	add_child(menu)
	_best = _load_best()

	# Lay the HUD out for the screen's shape, so it isn't tiny on a portrait phone
	get_tree().root.size_changed.connect(_fit_ui)
	_fit_ui()

	match start_mode:
		"test":
			start_test()
		"endless":
			start_endless()
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
	_use_course(TestArea.new())
	player.rewind_on_splat = true
	player.run_speed = ENDLESS_SPEED.x
	_play()


## Endless: a fresh lane, from the start; a splat ends the run
func start_endless() -> void:
	mode = "endless"
	var course := Endless.new()
	course.runner = player
	_use_course(course)
	player.rewind_on_splat = false
	player.run_speed = ENDLESS_SPEED.x
	_play()


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
	menu.show_title(_best)


## A freshly generated course, and back to the start of it
func restart() -> void:
	if mode == "endless":
		start_endless()
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
	hud.show_distance(mode == "endless")
	player.reset_drops()
	player.place(area.start_position, area.start_heading)
	player.set_physics_process(true)
	_input.set_process_input(true)
	cam.snap()


func _process(_delta: float) -> void:
	if mode != "endless" or player.dead:
		return
	var metres: float = area.distance()
	player.run_speed = lerpf(ENDLESS_SPEED.x, ENDLESS_SPEED.y, clampf(metres / ENDLESS_FAST, 0.0, 1.0))
	hud.set_distance(int(metres))


func _on_splat() -> void:
	if mode != "endless":
		return
	var metres := int(area.distance())
	var new_best := metres > _best
	if new_best:
		_best = metres
		if get_tree().current_scene == self: # real play (a test script builds its own): keep it
			_save_best(_best)
	_input.set_process_input(false)
	# Let the splat land first
	await get_tree().create_timer(0.9).timeout
	if mode == "endless" and player.dead:
		hud.visible = false
		menu.show_game_over(metres, player.drops, _best, new_best)


func _load_best() -> int:
	var file := FileAccess.open(BEST_FILE, FileAccess.READ)
	return int(file.get_as_text()) if file else 0


func _save_best(metres: int) -> void:
	var file := FileAccess.open(BEST_FILE, FileAccess.WRITE)
	if file:
		file.store_string(str(metres))


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
