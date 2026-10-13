extends MeshInstance3D
## A capital ship's big gun turned on the ring (endless.gd sends them; war.gd has the ships).
## First the line it will take shows on the sand, a strip of light that brightens for `warn`
## seconds; then the beam comes down from the ship onto one end of the line and runs along it to
## the other in `sweep` seconds, and whoever it passes over is burst (`strike` is called with
## where it is and how wide, every step it's on the ground). Then it's gone.
## A rake is a long line down the ring toward the runner; a shot at him is a short one where
## he's about to be. Either way the answer is to be off the line. World space.

signal over

## The ship (the beam comes from where it is)
var ship: Node3D
## The line on the ground, from where the beam lands to where it lifts
var from := Vector3.ZERO
var to := Vector3.ZERO
var warn := 1.5
var sweep := 1.0
var radius := 1.8
var color := Color(1.0, 0.5, 0.2)
var strike: Callable

var _clock := 0.0
var _mesh := ImmediateMesh.new()
var _mark := StandardMaterial3D.new()
var _beam := StandardMaterial3D.new()
var _glow := OmniLight3D.new()


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	mesh = _mesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	extra_cull_margin = 3000.0
	for material in [_mark, _beam]:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.disable_fog = true
	_beam.albedo_color = color.lerp(Color.WHITE, 0.6)
	_glow.light_color = color.lerp(Color.WHITE, 0.4)
	_glow.omni_range = 30.0
	_glow.light_energy = 0.0
	add_child(_glow)


func _physics_process(delta: float) -> void:
	_clock += delta
	var firing := _clock >= warn and _clock < warn + sweep
	var done := _clock >= warn + sweep
	if _clock > warn + sweep + 0.35:
		over.emit()
		queue_free()
		return
	var along := clampf((_clock - warn) / sweep, 0.0, 1.0)
	var spot := from.lerp(to, along)
	if firing and strike.is_valid():
		strike.call(spot, radius)
	_mesh.clear_surfaces()
	# The line on the sand: brightening, quick to flicker as the time comes, then burnt out
	# behind the beam
	var closing := clampf(_clock / warn, 0.0, 1.0)
	_mark.albedo_color = Color(color.r, color.g, color.b, (0.12 + 0.3 * closing) * (0.75 + 0.25 * sin(_clock * (8.0 + 30.0 * closing))) * (1.0 - smoothstep(0.0, 0.35, _clock - warn - sweep)))
	var line := to - from
	var across := (line.cross(Vector3.UP).normalized() if line.length() > 0.1 else Vector3.RIGHT) * radius
	var ahead := line.normalized() * radius if line.length() > 0.1 else Vector3.FORWARD * radius
	var lift := Vector3.UP * 0.06
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _mark)
	for corner in [from - ahead - across, from - ahead + across, to + ahead + across, from - ahead - across, to + ahead + across, to + ahead - across]:
		_mesh.surface_add_vertex(corner + lift)
	_mesh.surface_end()
	# The beam itself, from the ship to the sand
	_glow.light_energy = 0.0
	if (firing or done) and is_instance_valid(ship):
		var fade := 1.0 - smoothstep(0.0, 0.3, _clock - warn - sweep)
		_beam.albedo_color.a = fade
		_glow.position = spot + Vector3.UP * 1.5
		_glow.light_energy = 9.0 * fade
		var top := ship.global_position
		var run := (spot - top).normalized()
		var wide := radius * 0.55 * (0.85 + 0.15 * sin(_clock * 60.0)) * fade
		var side := run.cross(Vector3.UP).normalized() * wide
		var other := run.cross(side).normalized() * wide
		_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _beam)
		for flat in [side, other]:
			for corner in [top - flat * 0.3, top + flat * 0.3, spot + flat, top - flat * 0.3, spot + flat, spot - flat]:
				_mesh.surface_add_vertex(corner)
		_mesh.surface_end()
