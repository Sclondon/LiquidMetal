extends MeshInstance3D
## What moves in the sky over the Crystaliens' moon (shaders/sky_show.gdshader: flaring stars,
## comets, shooting stars, the odd supernova, and the things nobody can explain), on a great ball
## kept round the camera. The sky itself (sky.gdshader) is painted once and never changes, so its
## light on the world needn't be worked out again every frame; this is added over it.
## main.gd owns one: `reach` is how far off the ball is (beyond everything else in the scene, short
## of the camera's far plane), `set_tint` the zone's colour.

var cam: Camera3D
## How far off the sky is, metres
var reach := 650.0

var _material := ShaderMaterial.new()


func _ready() -> void:
	var ball := SphereMesh.new()
	ball.radius = 1.0
	ball.height = 2.0
	ball.radial_segments = 48
	ball.rings = 24
	mesh = ball
	_material.shader = preload("res://shaders/sky_show.gdshader")
	material_override = _material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 16000.0
	layers = 1 << 2 # (its own layer: not in the runner's reflections)
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


func _process(_delta: float) -> void:
	if cam:
		global_transform = Transform3D(Basis.from_scale(Vector3.ONE * reach), cam.global_position)


func set_tint(color: Color) -> void:
	_material.set_shader_parameter("tint", color)


## Hold a comet, a supernova and the figure in view (for pictures)
func showcase(on: bool) -> void:
	_material.set_shader_parameter("showcase", 1.0 if on else 0.0)
