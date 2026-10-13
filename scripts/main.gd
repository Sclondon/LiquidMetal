extends Node3D
## Liquid Metal. Builds the scene in code: sky and light, the course, the runner, its input, the
## chase camera, the HUD and the menu. Four modes from the menu: ENDLESS RUN (a lane that never
## ends, faster and harder through its zones; a splat ends the run), ARENA (an online battle room:
## everyone in it fights for the most mass; see arena.gd) and TEST AREA (the playground, where a
## splat just rewinds you a moment), plus the MODEL VIEWER (viewer.gd: a good look at Mercury).

const RunnerInput := preload("res://scripts/runner_input.gd")
const Player := preload("res://scripts/player.gd")
const FollowCam := preload("res://scripts/follow_cam.gd")
const TestArea := preload("res://scripts/test_area.gd")
const Hud := preload("res://scripts/hud.gd")
const Endless := preload("res://scripts/endless.gd")
const Menu := preload("res://scripts/menu.gd")
const Arena := preload("res://scripts/arena.gd")
const Difficulty := preload("res://scripts/difficulty.gd")
const Viewer := preload("res://scripts/viewer.gd")
const Flags := preload("res://scripts/flags.gd")
const SkyShow := preload("res://scripts/sky_show.gd")

const BEST_FILE := "user://bests.cfg"
const ARENA_SPEED := 13.0
## The arena's battle room lives on the site's server (--server=<url> or ?server= for another;
## --offline or ?offline for a room of bots run here)
const ARENA_SERVER := "https://scareathon-v3-production.up.railway.app"
const NAMES := ["CHROME", "SILVER", "ALLOY", "INGOT", "RIVET", "SOLDER", "PEWTER", "STEEL"]
# (endless: run speed at the start, and by ENDLESS_FAST metres, is the difficulty's endless_speed)
const ENDLESS_FAST := 3000.0

## Where it opens: "menu", or straight into "test", "endless", "arena" or "viewer" (the tests use these)
@export var start_mode := "menu"
## False: gamepads ignored (screenshot tests on a machine with a controller plugged in)
@export var use_pads := true
## False: no enemy runners (tests that need a clear lane)
@export var enemies := true
## The arena's rounds, in seconds, when the room's run here (0: the usual; a test's are short)
@export var arena_round := 0.0
## The arena's first layout when the room's run here ("": any): "open" / "blocks" / "movers" / "pit"
@export var arena_mode := ""
var mode := ""

var area: Node3D
var player: CharacterBody3D
var cam: Camera3D
var n64: CanvasLayer # the N64 filter over the 3D (under the HUD)
var hud: CanvasLayer
var menu: CanvasLayer
var viewer: CanvasLayer
var _input: Node
var _bests := {} # best/<key> in the file: "run" (endless score, per difficulty) and "mass" (arena)
var _name := "" # in the arena (made up the first time, and kept)
var _board_clock := 0.0
var _smashes := 0 # enemies dashed through this game
var _test_enemies := true # the test area's enemies (the TUNE panel switches them)
var _sky: ShaderMaterial # shaders/sky.gdshader
var _sun: DirectionalLight3D
var sky_show: MeshInstance3D # what moves in the sky: comets and the rest (sky_show.gd)
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
	sky_show = SkyShow.new()
	sky_show.cam = cam
	add_child(sky_show)

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
	hud.set_enemies = _set_test_enemies
	add_child(hud)
	input.is_over_ui = hud.is_over_ui

	menu = Menu.new()
	menu.endless_chosen.connect(start_endless)
	menu.test_area_chosen.connect(start_test)
	menu.arena_chosen.connect(start_arena)
	menu.viewer_chosen.connect(start_viewer)
	menu.menu_chosen.connect(show_menu)
	menu.difficulty_chosen.connect(_on_difficulty)
	menu.again_chosen.connect(restart)
	add_child(menu)
	viewer = Viewer.new()
	viewer.player = player
	viewer.cam = cam
	viewer.input = input
	viewer.back_chosen.connect(show_menu)
	add_child(viewer)
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
		"viewer":
			start_viewer()
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
	course.with_enemies = enemies and _test_enemies
	_use_course(course)
	player.rewind_on_splat = true
	player.run_speed = Difficulty.tier().endless_speed.x
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
	player.run_speed = Difficulty.tier().endless_speed.x
	_play()
	# (the moon and the far side of the ring are a long way off)
	cam.far = 6000.0
	sky_show.reach = 5600.0 # (out past the moon)
	_environment.fog_density = 0.0016
	_set_sky(Endless.ZONES[0], 0.0)
	hud.banner("THE RING ROAD", Endless.ZONES[0].name)


## Arena: the online battle room (or, when the server can't be had, the same room with bots)
func start_arena() -> void:
	mode = "arena"
	var course := Arena.new()
	course.runner = player
	course.with_enemies = enemies
	course.player_name = Flags.value("name", _name)
	course.round_time = arena_round
	course.first_mode = arena_mode
	# (the tests start straight in: they play a room run here unless told a server)
	if not Flags.all().has("offline"):
		course.server = Flags.value("server", ARENA_SERVER if start_mode == "menu" else "")
	course.status.connect(func(text, sub): hud.banner(text, sub))
	course.feed.connect(hud.feed)
	course.round_over.connect(_on_round_over)
	course.player_placed.connect(func(): cam.snap())
	course.round_started.connect(func(): hud.banner("NEW ROUND", "grow  ·  dash  ·  burst"))
	_use_course(course)
	player.rewind_on_splat = false
	player.run_speed = ARENA_SPEED
	_play()
	player.set_physics_process(false) # (the arena lets him go once he's in the room)
	# The Crystaliens' moon: black sky, stars all the way down, its ring overhead
	_set_sky({ top = Color(0.012, 0.008, 0.03), horizon = Color(0.55, 0.3, 1.0), fog = Color(0.1, 0.06, 0.18), space = 1.0, ring = 1.0 }, 0.0)


## The title menu, over the runner standing at the start of the test area
func show_menu() -> void:
	_leave_viewer()
	mode = "menu"
	if area == null or not area is TestArea:
		_use_course(TestArea.new())
	player.place(area.start_position, area.start_heading)
	player.set_physics_process(false)
	_input.set_process_input(false)
	hud.visible = false
	cam.snap()
	_set_sky(Endless.ZONES[0], 0.0)
	menu.show_title(_best("run"), int(_bests.get("mass", 0)), Difficulty.level)


## The model viewer: Mercury running on the spot at the (empty) test area's start, the camera
## circling it
func start_viewer() -> void:
	mode = "viewer"
	var course := TestArea.new()
	course.runner = player
	course.with_enemies = false
	_use_course(course)
	menu.hide_all()
	hud.visible = false
	player.rewind_on_splat = true
	player.reset_drops()
	player.place(area.start_position, 0.0)
	player.set_physics_process(true)
	# (the viewer's buttons drive it, not touches, keys or sticks)
	_input.set_process_input(false)
	_input.set_process(false)
	_input.turn = 0.0
	_input.look = Vector2.ZERO
	_set_sky(Endless.ZONES[0], 0.0)
	viewer.open(area.start_position)


func _leave_viewer() -> void:
	viewer.close()
	cam.target = player
	_input.set_process(true)


## The TUNE panel's switch: the test area's enemies on, or off (and the ones there gone)
func _set_test_enemies(on: bool) -> void:
	_test_enemies = on
	if not area is TestArea:
		return
	area.with_enemies = enemies and on
	if not on:
		for enemy in area.enemies:
			if is_instance_valid(enemy):
				enemy.queue_free()
		area.enemies.clear()


## A freshly generated course, and back to the start of it
func restart() -> void:
	if mode == "viewer":
		return
	if mode == "endless":
		start_endless()
		return
	if mode == "arena":
		return # (the room's not his to restart)
	area.generate()
	player.restart()
	cam.snap()


func _use_course(course: Node3D) -> void:
	if area is Arena:
		_keep_mass()
		player.leave_brawl()
	if area:
		area.free() # gone now, not at the end of the frame: the new course may overlap it
	area = course
	add_child(area)


func _play() -> void:
	_leave_viewer()
	menu.hide_all()
	hud.visible = true
	hud.enemies_switch.visible = mode == "test"
	hud.set_arena(mode == "arena")
	cam.far = 700.0
	sky_show.reach = 650.0
	_environment.fog_density = 0.004
	player.reset_drops()
	_smashes = 0
	player.place(area.start_position, area.start_heading)
	player.set_physics_process(true)
	_input.set_process_input(true)
	cam.snap()


func _process(delta: float) -> void:
	match mode:
		"endless":
			var metres: float = area.distance()
			if not player.dead:
				player.run_speed = lerpf(Difficulty.tier().endless_speed.x, Difficulty.tier().endless_speed.y, clampf(metres / ENDLESS_FAST, 0.0, 1.0))
			hud.set_stats("%d m" % int(metres), "ZONE %d  ·  %d DROPS  ·  %d SMASHED" % [area.zone + 1, player.drops, _smashes])
		"arena":
			if area.me == 0:
				hud.set_stats("ARENA", "finding the room...")
				return
			var rows: Array = area.standings()
			var place := 1
			for k in rows.size():
				if rows[k].me:
					place = k + 1
			var clock := "%d:%02d" % [int(area.time_left) / 60, int(area.time_left) % 60]
			hud.set_stats("%d" % area.my_mass(), "#%d of %d  ·  %d BURST  ·  %s" % [place, rows.size(), area.smashes, clock if area.phase == "play" else "next round"])
			_board_clock -= delta
			if _board_clock <= 0.0:
				_board_clock = 0.25
				hud.set_board(rows, "ONLINE" if area.online else "BOTS")
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
	var light: Color = (look.horizon as Color).lerp(Color.WHITE, 0.6) # the key light, warmed by the horizon
	# (out in space: no skyline, stars below the horizon too, and maybe the ring)
	_sky.set_shader_parameter("space", look.get("space", 0.0))
	_sky.set_shader_parameter("skyline", 1.0 - float(look.get("space", 0.0)))
	_sky.set_shader_parameter("ring", look.get("ring", 0.0))
	sky_show.visible = float(look.get("space", 0.0)) > 0.5
	sky_show.set_tint(look.horizon)
	if time <= 0.0:
		_sky.set_shader_parameter("sky_top", look.top)
		_sky.set_shader_parameter("horizon", look.horizon)
		_environment.fog_light_color = look.fog
		_sun.light_color = light
		return
	var tween := create_tween().set_parallel(true)
	tween.tween_property(_sky, "shader_parameter/sky_top", look.top, time)
	tween.tween_property(_sky, "shader_parameter/horizon", look.horizon, time)
	tween.tween_property(_environment, "fog_light_color", look.fog, time)
	tween.tween_property(_sun, "light_color", light, time)


func _on_splat() -> void:
	if mode != "endless":
		return # (the arena brings him back itself)
	var playing := mode
	var headline := ""
	var more := ""
	var best := ""
	var tier := Difficulty.tier_name()
	var score := _score()
	headline = "%d m" % int(area.distance())
	more = "SCORE %d  ·  %d drops  ·  %d smashed  ·  zone %d" % [score, player.drops, _smashes, area.zone + 1]
	if score > _best("run"):
		_bests[Difficulty.best_key("run")] = score
		best = "NEW %s BEST!" % tier
	else:
		best = "%s BEST %d" % [tier, _best("run")]
	_save_bests()
	_input.set_process_input(false)
	# Let the splat land first
	await get_tree().create_timer(0.9).timeout
	if mode == playing and player.dead:
		hud.visible = false
		menu.show_game_over(headline, more, best)


## The arena's round is up: who won, and the standings stay up till the next one
func _on_round_over(top: Array) -> void:
	_keep_mass()
	if top.is_empty():
		return
	var winner: Dictionary = top[0]
	var mine: bool = int(winner.id) == area.me
	hud.banner("YOU WIN!" if mine else "ROUND OVER", "%d mass" % int(winner.mass) if mine else "%s wins with %d" % [winner.name, int(winner.mass)])


## The most mass he's had in the arena: kept as his best
func _keep_mass() -> void:
	if area is Arena and area.peak > int(_bests.get("mass", 0)):
		_bests["mass"] = area.peak
		_save_bests()


## This difficulty's best endless score ("run")
func _best(what: String) -> int:
	return _bests.get(Difficulty.best_key(what), 0)


## Picked on the title menu: its bests come up, and it's remembered for next time
func _on_difficulty(level: int) -> void:
	Difficulty.level = level
	menu.show_bests(_best("run"), int(_bests.get("mass", 0)))
	_save_bests()


func _load_bests() -> void:
	_name = "%s %d" % [NAMES.pick_random(), randi_range(10, 99)]
	var file := ConfigFile.new()
	if file.load(BEST_FILE) != OK:
		return
	_name = str(file.get_value("settings", "name", _name))
	if file.has_section("best"):
		for key in file.get_section_keys("best"):
			_bests[key] = file.get_value("best", key, 0)
	# (the tests start straight into a mode: they always play NORMAL)
	if start_mode == "menu":
		Difficulty.level = clampi(file.get_value("settings", "difficulty", Difficulty.DEFAULT), 0, Difficulty.TIERS.size() - 1)


func _save_bests() -> void:
	# Real play only (never a test run)
	if start_mode != "menu" or get_tree().get_script() != null or OS.has_feature("editor"):
		return
	var file := ConfigFile.new()
	for key in _bests:
		file.set_value("best", key, _bests[key])
	file.set_value("settings", "difficulty", Difficulty.level)
	file.set_value("settings", "name", _name)
	file.save(BEST_FILE)


func _fit_ui() -> void:
	var window := get_tree().root
	window.content_scale_size = Vector2i(720, 1280) if window.size.x < window.size.y else Vector2i(1280, 720)


func _build_environment() -> void:
	# Dusk: deep blue overhead, a hot band at the horizon for the chrome to catch, a low sun down
	# the lane and a skyline under it (shaders/sky.gdshader; its colours follow the zone)
	var sky_material := ShaderMaterial.new()
	sky_material.shader = preload("res://shaders/sky.gdshader")
	_sky = sky_material
	var sky := Sky.new()
	sky.sky_material = sky_material
	sky.radiance_size = Sky.RADIANCE_SIZE_128

	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.8
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_white = 6.0 # (the bright neon and the sun's disc roll off instead of clipping)
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

	# The key light: from high up behind the camera (its shine off the floor goes away from you, not
	# back into your eyes), softer than before, tinted by the zone's horizon
	_sun = DirectionalLight3D.new()
	_sun.rotation_degrees = Vector3(-52.0, 25.0, 0.0)
	_sun.light_energy = 0.95
	_sun.light_color = Color(1.0, 0.85, 0.8)
	_sun.light_specular = 0.6
	_sun.shadow_enabled = true
	_sun.shadow_blur = 1.5
	_sun.directional_shadow_max_distance = 70.0
	add_child(_sun)
