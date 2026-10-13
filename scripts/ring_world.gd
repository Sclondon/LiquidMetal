extends Node3D
## The endless run's world: a disc-world ring round the Crystaliens' black sand moon, seen from
## on top of it. The runner's own band of the ring (WIDTH across, edge to edge) is one of several
## concentric bands of dust and sand with gaps between, like a planet's rings; the others lie a
## little lower to either side, so you look down across them.
##
## The course itself is straight (endless.gd builds it along -Z, a chunk at a time, with its own
## floor pieces so the breaks in it are real), so the ring and the moon are kept abreast of the
## runner: this node follows him along Z, and the moon turns as he goes, so it reads as running
## round it. Near him the ring is drawn straight, to meet the course's floor; past that it eases
## into the circle, and the whole circle is tipped up ahead of him (RISE) so its far arc stands
## up in view, sweeping round in front of the moon, instead of lying edge-on along the horizon.
## The moon has a layer of drifting haze round it and is lit by the sky's three suns (SUNS: the
## same directions and colours shaders/sky.gdshader draws them with).

const RADIUS := 1500.0 # the moon's middle to the middle of the runner's band
const WIDTH := 56.0 # across the runner's band: all of it is the course
const MOON := 1150.0 # the moon's radius
const MOON_DROP := 150.0 # its middle sits this far below the runner's level
const AIR := 1.04 # the haze layer's radius, times the moon's
const RISE := 0.16 # how steeply the ring climbs ahead (the tangent of its tilt)
const STRAIGHT_AHEAD := 360.0 # drawn straight this far ahead of the runner (the course covers it)
const STRAIGHT_BEHIND := 130.0 # and this far behind
const EASE := 0.34 # radians round over which it eases from straight into the circle
## The other bands: [inner edge, outer edge (metres out from the middle of the runner's band),
## how far below it]
const BANDS := [
	[-46.0, -37.0, 7.0], [-118.0, -60.0, 22.0], [-262.0, -136.0, 48.0],
	[37.0, 44.0, 7.0], [60.0, 136.0, 24.0], [156.0, 300.0, 52.0], [330.0, 390.0, 78.0],
]
## The three suns: the way to each (world space; -Z is down the course), its colour, its strength
const SUNS := [
	[Vector3(0.0, 0.07, -1.0), Color(1.0, 0.95, 0.88), 1.0],
	[Vector3(0.55, 0.22, -0.8), Color(1.0, 0.62, 0.3), 0.55],
	[Vector3(-0.62, 0.42, -0.66), Color(0.55, 0.75, 1.0), 0.4],
]

## The black sand (the course's floor pieces wear the same material)
var sand: ShaderMaterial

var _moon_material := ShaderMaterial.new()
var _air_material := ShaderMaterial.new()
var _far_material := ShaderMaterial.new() # the runner's band, far off
var _band_material := ShaderMaterial.new() # the other bands
var _kerb_material := ShaderMaterial.new()
var _fill_ahead := MeshInstance3D.new() # sand between the course's far end and the far band
var _fill_behind := MeshInstance3D.new()


func _ready() -> void:
	sand = Sand.surface(Sand.BLACK) # (the shared sand: GameCommon godot/sand)
	sand.set_shader_parameter(&"sparkle", 3.0)
	sand.set_shader_parameter(&"sparkle_aim", 0.965)
	var ring_shader: Shader = preload("res://shaders/ring_band.gdshader")
	for material in [_far_material, _band_material, _kerb_material, _moon_material, _air_material]:
		for k in SUNS.size():
			material.set_shader_parameter("sun_%d" % k, (SUNS[k][0] as Vector3).normalized())
			var colour: Color = SUNS[k][1]
			material.set_shader_parameter("sun_colour_%d" % k, Vector3(colour.r, colour.g, colour.b) * float(SUNS[k][2]))
	for material in [_far_material, _band_material, _kerb_material]:
		material.shader = ring_shader
		material.set_shader_parameter("moon_at", Vector3(-RADIUS, -MOON_DROP, 0.0))
		material.set_shader_parameter("moon_radius", MOON)
	_far_material.set_shader_parameter("solid", 1.0)
	_kerb_material.set_shader_parameter("kerb", 1.0)
	# The runner's band, from where the course's floor leaves off, right round
	_add(_band(-WIDTH * 0.5, WIDTH * 0.5, 0.03, true), _far_material)
	for edge in [-WIDTH * 0.5, WIDTH * 0.5]:
		_add(_band(edge - 0.5, edge + 0.5, -0.3, true), _kerb_material)
	for band in BANDS:
		_add(_band(band[0], band[1], band[2], false), _band_material)
	# Sand between the course's floor and the far band, at each end (set in follow)
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE
	for fill in [_fill_ahead, _fill_behind]:
		fill.mesh = plane
		fill.material_override = sand
		fill.top_level = true
		fill.visible = false
		add_child(fill)
	# The moon in the middle, and its air
	var ball := SphereMesh.new()
	ball.radius = MOON
	ball.height = MOON * 2.0
	ball.radial_segments = 96
	ball.rings = 48
	var moon := MeshInstance3D.new()
	moon.mesh = ball
	_moon_material.shader = preload("res://shaders/moon.gdshader")
	moon.material_override = _moon_material
	moon.position = Vector3(-RADIUS, -MOON_DROP, 0.0)
	moon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(moon)
	var air := MeshInstance3D.new()
	air.mesh = ball
	air.scale = Vector3.ONE * AIR
	_air_material.shader = preload("res://shaders/moon_air.gdshader")
	air.material_override = _air_material
	air.position = moon.position
	air.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(air)


## Kept abreast of the runner (z: where he is along the course). from / to: the stretch of the
## course that has its own floor just now (from behind him to ahead: to < from), so the sand
## carries on from each end of it to the far band.
func follow(z: float, from := INF, to := INF) -> void:
	position.z = z
	_moon_material.set_shader_parameter("turn", -z / RADIUS)
	_air_material.set_shader_parameter("turn", -z / RADIUS)
	_fill(_fill_ahead, to, z - STRAIGHT_AHEAD - 1.0)
	_fill(_fill_behind, z + STRAIGHT_BEHIND + 1.0, from)


func _fill(fill: MeshInstance3D, from: float, to: float) -> void:
	fill.visible = from != INF and to != INF and from - to > 0.05
	if fill.visible:
		fill.global_transform = Transform3D(Basis.from_scale(Vector3(WIDTH, 1.0, from - to)), Vector3(0.0, 0.0, (from + to) * 0.5))


## The zone's colour: what the sand glints with, the bands' dust, the moon's crystal fields
func set_color(color: Color) -> void:
	sand.set_shader_parameter(&"glint", color.lerp(Color.WHITE, 0.3))
	for material in [_far_material, _band_material, _kerb_material]:
		material.set_shader_parameter("tint", color)
	_moon_material.set_shader_parameter("crystal", color)
	_air_material.set_shader_parameter("tint", color)


func _add(mesh: ArrayMesh, material: Material) -> void:
	var view := MeshInstance3D.new()
	view.mesh = mesh
	view.material_override = material
	view.extra_cull_margin = RADIUS * 4.0
	view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(view)


## Where a point of the ring is drawn, in this node's space (the runner at the origin, running
## toward -Z): `out` metres out from the middle of his band, `angle` radians round from him
## (ahead is positive), `drop` below his band's level.
static func spot(out: float, angle: float, drop: float) -> Vector3:
	var r := RADIUS + out
	var on_circle := Vector3(r * cos(angle) - RADIUS, r * sin(angle) * RISE, -r * sin(angle))
	var on_straight := Vector3(out, 0.0, -RADIUS * angle)
	var start := (STRAIGHT_AHEAD if angle > 0.0 else STRAIGHT_BEHIND) / RADIUS
	var blend := smoothstep(start, start + EASE, absf(angle))
	return on_straight.lerp(on_circle, blend) - Vector3(0.0, drop, 0.0)


## A band right round the moon, from `inner` to `outer`. skip_near: without the stretch by the
## runner that the course's own floor covers. UV: x metres out, y metres round.
func _band(inner: float, outer: float, drop: float, skip_near: bool) -> ArrayMesh:
	# The angles to cut it at, on round from the runner: close together near him, where it bends
	# out of the straight
	var first := STRAIGHT_AHEAD / RADIUS if skip_near else -PI
	var last := TAU - STRAIGHT_BEHIND / RADIUS if skip_near else PI
	var angles: Array[float] = []
	var angle := first
	while angle < last:
		angles.append(angle)
		angle += 0.008 if absf(wrapf(angle, -PI, PI)) < 0.9 else 0.03
	angles.append(last)
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_normal(Vector3.UP)
	for k in angles.size() - 1:
		var a := angles[k]
		var b := angles[k + 1]
		var corners := [[inner, a], [outer, a], [outer, b], [inner, a], [outer, b], [inner, b]]
		for corner in corners:
			var out: float = corner[0]
			var at: float = corner[1]
			tool.set_uv(Vector2(out, at * RADIUS))
			tool.add_vertex(spot(out, wrapf(at, -PI, PI), drop))
	return tool.commit()
