extends Area3D
## A boost: a standing ring of aurora light, a few metres across, that you run or jump through
## and are shot forward by (the runner's speed kicked up, easing back off). It stands on its
## position, facing +Z (its light streams back toward -Z, the way it boosts you, unless it's turned
## with rotation.y); `lift` raises it off the ground, for one to be jumped through.
## The light is two hoops of curtain, flaring out behind the opening and flowing opposite ways,
## and a thin veil across the opening (shaders/boost_pad.gdshader).

const RADIUS := 2.3 # of the opening
const DEPTH := 1.2 # how far the curtains run back along the way through
const FLARE := 1.3 # and how far out they spread as they go (so you see them from in front)

## Metres its foot is off the ground
var lift := 0.0


func _ready() -> void:
	# What trips it: a slab filling the opening
	var shape := BoxShape3D.new()
	shape.size = Vector3(RADIUS * 1.8, RADIUS * 2.0, 0.9)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position.y = RADIUS + 0.1 + lift
	add_child(collider)
	var shader: Shader = preload("res://shaders/boost_pad.gdshader")
	# The curtains: hoops of light round the opening
	for k in 2:
		var hoop := MeshInstance3D.new()
		hoop.mesh = _hoop(RADIUS, FLARE * (1.0 if k == 0 else 1.6), DEPTH * (1.0 if k == 0 else 1.5))
		var material := ShaderMaterial.new()
		material.shader = shader
		material.set_shader_parameter("flow", 1.0 if k == 0 else -0.7)
		material.set_shader_parameter("seed", float(k) * 3.7)
		material.set_shader_parameter("strength", 1.0 if k == 0 else 0.6)
		hoop.material_override = material
		hoop.position.y = RADIUS + 0.1 + lift
		hoop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(hoop)
	# The veil across it
	var disc := QuadMesh.new()
	disc.size = Vector2.ONE * RADIUS * 2.0
	var veil := MeshInstance3D.new()
	veil.mesh = disc
	var film := ShaderMaterial.new()
	film.shader = shader
	film.set_shader_parameter("veil", 1.0)
	veil.material_override = film
	veil.position.y = RADIUS + 0.1 + lift
	veil.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(veil)
	body_entered.connect(func(body: Node3D):
		if body.has_method("boost"):
			body.boost()
	)


## A hoop standing in the XY plane, opening out by `flare` over its `depth` along -Z.
## UV: x round it, y from front (0) to back (1)
func _hoop(radius: float, flare: float, depth: float) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides := 40
	for k in sides:
		var corners := []
		for step in [[0, 0.0], [1, 0.0], [1, 1.0], [0, 0.0], [1, 1.0], [0, 1.0]]:
			var angle: float = (k + int(step[0])) * TAU / sides
			var back: float = step[1]
			corners.append([Vector2(float(k + int(step[0])) / sides, back), Vector3(cos(angle), sin(angle), 0.0) * (radius + flare * back) + Vector3(0.0, 0.0, (0.5 - back) * depth)])
		for corner in corners:
			tool.set_uv(corner[0])
			tool.set_normal(Vector3(corner[1].x, corner[1].y, 0.0).normalized())
			tool.add_vertex(corner[1])
	return tool.commit()
