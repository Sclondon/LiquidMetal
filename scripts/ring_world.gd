extends Node3D
## The endless run's world: a ring road round the Crystaliens' black sand moon. The ring is a
## flat band of black sand a kilometre and a half out from the moon's middle, and the lane runs
## along the top of it. The lane itself is straight (the course is built along -Z), so the ring
## and the moon are kept abreast of the runner: the ring is always touching the lane where he is
## and curving away round the moon ahead and behind, and the moon turns as he goes, so it reads as
## running round it. endless.gd owns one and tells it where the runner is.

const RADIUS := 1500.0 # the moon's middle to the middle of the road
const WIDTH := 90.0 # across the road
const MOON := 1250.0 # the moon's radius
const SEGMENTS := 360

var _sand: ShaderMaterial
var _moon_material := ShaderMaterial.new()
var _rim_material := ShaderMaterial.new()


func _ready() -> void:
	# The road: black sand, the same as the colosseum's floor
	_sand = Sand.surface(Sand.BLACK) # (the shared sand: GameCommon godot/sand)
	_sand.set_shader_parameter(&"sparkle", 3.0)
	_sand.set_shader_parameter(&"sparkle_aim", 0.965)
	var road := MeshInstance3D.new()
	road.mesh = _band(RADIUS - WIDTH * 0.5, RADIUS + WIDTH * 0.5, 0.0)
	road.material_override = _sand
	road.position = Vector3(-RADIUS, -0.02, 0.0)
	road.extra_cull_margin = RADIUS
	add_child(road)
	# Its edges: a low kerb of crystal each side, lit from inside
	_rim_material.shader = preload("res://shaders/crystal.gdshader")
	for edge in [RADIUS - WIDTH * 0.5, RADIUS + WIDTH * 0.5]:
		var rim := MeshInstance3D.new()
		rim.mesh = _band(edge - 0.8, edge + 0.8, 0.0)
		rim.material_override = _rim_material
		rim.position = Vector3(-RADIUS, 0.25, 0.0)
		rim.extra_cull_margin = RADIUS
		add_child(rim)
	# The underside and the drop off the edge are just space; the moon sits in the middle
	var ball := SphereMesh.new()
	ball.radius = MOON
	ball.height = MOON * 2.0
	ball.radial_segments = 96
	ball.rings = 48
	var moon := MeshInstance3D.new()
	moon.mesh = ball
	_moon_material.shader = preload("res://shaders/moon.gdshader")
	moon.material_override = _moon_material
	moon.position = Vector3(-RADIUS, -120.0, 0.0) # (a little below the road, so more of it shows over the edge)
	moon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(moon)


## Kept abreast of the runner (z: where he is along the lane)
func follow(z: float) -> void:
	position.z = z
	_moon_material.set_shader_parameter("turn", -z / RADIUS)


## The zone's colour: what the sand glints with, and the kerbs' crystal
func set_color(color: Color) -> void:
	_sand.set_shader_parameter(&"glint", color.lerp(Color.WHITE, 0.3))
	_rim_material.set_shader_parameter("horizon", color)
	_rim_material.set_shader_parameter("sky_top", color.darkened(0.7))
	_moon_material.set_shader_parameter("crystal", color)


## A flat band round the moon's middle, from `inner` to `outer`, at height y
func _band(inner: float, outer: float, y: float) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_normal(Vector3.UP)
	for k in SEGMENTS:
		var a := k * TAU / SEGMENTS
		var b := (k + 1) * TAU / SEGMENTS
		var ia := Vector3(cos(a) * inner, y, sin(a) * inner)
		var ib := Vector3(cos(b) * inner, y, sin(b) * inner)
		var oa := Vector3(cos(a) * outer, y, sin(a) * outer)
		var ob := Vector3(cos(b) * outer, y, sin(b) * outer)
		for corner in [ia, oa, ob, ia, ob, ib]:
			tool.add_vertex(corner)
	return tool.commit()
