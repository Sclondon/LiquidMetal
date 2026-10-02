extends Node3D
## Liquid Metal — test area. Builds the scene in code: sky and light, the test area,
## the blob, its input, the chase camera and the HUD.

const RunnerInput := preload("res://scripts/runner_input.gd")
const Player := preload("res://scripts/player.gd")
const FollowCam := preload("res://scripts/follow_cam.gd")
const TestArea := preload("res://scripts/test_area.gd")
const Hud := preload("res://scripts/hud.gd")

var player: CharacterBody3D
var cam: Camera3D


func _ready() -> void:
	_build_environment()

	var area := TestArea.new()
	add_child(area)

	var input := RunnerInput.new()
	add_child(input)

	player = Player.new()
	player.input = input
	add_child(player)
	player.place(area.start_position, area.start_heading)

	cam = FollowCam.new()
	cam.target = player
	add_child(cam)
	cam.snap()

	var hud := Hud.new()
	hud.player = player
	hud.cam = cam
	add_child(hud)
	input.is_over_ui = hud.is_over_ui

	# Lay the HUD out for the screen's shape, so it isn't tiny on a portrait phone
	get_tree().root.size_changed.connect(_fit_ui)
	_fit_ui()


func _unhandled_key_input(event: InputEvent) -> void:
	if event.pressed and not event.echo and event.physical_keycode == KEY_R:
		player.restart()
		cam.snap()


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
