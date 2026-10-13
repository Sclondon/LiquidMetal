extends Node3D
## The war over the ring (endless mode): the Crystaliens' ships, and somebody else's.
## - Far off to either side, two fleets hang facing each other across the ring and trade bolts;
##   now and then one of them is hit and a blast swells and goes out. Each side has two capital
##   ships, very big, further back; once in a while one takes a heavy bolt and goes up like a
##   supernova (and another comes to take its place).
## - Nearer, pairs of ships cross low over the ring ahead, one after the other and shooting at
##   it; sometimes the one in front doesn't make it across.
## - `strafe` brings one down the ring at the runner: endless.gd has it loose the crystals that
##   fall on the course (its `gun` is where they come from), and it goes on over his head.
## All of it is placed from the runner (endless.gd keeps this node level with him along the
## ring), so "200 m ahead" stays 200 m ahead. Drawn only: nothing here can be run into.

const Crystal := preload("res://scripts/crystal.gd")
## The two sides' colours: the Crystaliens', and the others'
const SIDES := [Color(0.6, 0.45, 1.0), Color(1.0, 0.5, 0.18)]
const FLEET := 14 # ships a side, far off
const STRAFE_SPEED := 210.0 # metres a second a strafing ship closes on the runner
const STRAFE_FROM := Vector3(0.0, 46.0, -170.0) # where it is, from the runner, as it fires
const CROSS_SPEED := 170.0

var _rng := RandomNumberGenerator.new()
var _hull: ArrayMesh
var _solid: Array[StandardMaterial3D] = []
var _light: Array[StandardMaterial3D] = []
var _faint: Array[StandardMaterial3D] = [] # the bolts': thin and dim (it's a long way off; it mustn't pull the eye)
var _fleets: Array[MultiMesh] = []
var _far: Array = [] # a side: [{ home, phase }]
var _ships: Array = [] # the near ones: { node, velocity, life, side, prey, gun, dies }
var _bolts: Array = [] # { from, to, age, life, side, wide }
var _blasts: Array = [] # { node, material, age, big }
var _lines := ImmediateMesh.new()
var _clock := 0.0
var _bolt_clock := 0.6
var _cross_clock := 4.0
var _capitals: Array = [] # { node, side, away }: away > 0 while it's gone (seconds till another comes)
var _nova_clock := 12.0


func _ready() -> void:
	_rng.randomize()
	_hull = ship_mesh()
	for side in 2:
		var color: Color = SIDES[side]
		# A hull: dark crystal with its side's colour in it (lit plainly: it's far off, in space)
		var solid := StandardMaterial3D.new()
		solid.albedo_color = color.darkened(0.55)
		solid.emission_enabled = true
		solid.emission = color * 0.45
		solid.roughness = 0.25
		solid.metallic = 0.4
		solid.disable_fog = true
		_solid.append(solid)
		var light := StandardMaterial3D.new()
		light.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		light.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		light.cull_mode = BaseMaterial3D.CULL_DISABLED
		light.albedo_color = color.lerp(Color.WHITE, 0.35)
		light.disable_fog = true
		_light.append(light)
		var faint: StandardMaterial3D = light.duplicate()
		faint.albedo_color = color * 0.3
		_faint.append(faint)
		# The fleet: off to one side of the ring, strung out along it, nose to the other side
		var many := MultiMesh.new()
		many.transform_format = MultiMesh.TRANSFORM_3D
		many.mesh = _hull
		many.instance_count = FLEET
		var ships := []
		var out := -1.0 if side == 0 else 1.0
		for k in FLEET:
			ships.append({ home = Vector3(out * _rng.randf_range(190.0, 520.0), _rng.randf_range(45.0, 250.0), _rng.randf_range(-880.0, -120.0)), phase = _rng.randf() * TAU, size = _rng.randf_range(1.6, 3.4) })
		_far.append(ships)
		_fleets.append(many)
		var fleet := MultiMeshInstance3D.new()
		fleet.multimesh = many
		fleet.material_override = solid
		fleet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		fleet.extra_cull_margin = 2000.0
		add_child(fleet)
	for side in 2:
		var out := -1.0 if side == 0 else 1.0
		for k in 2:
			var capital := MeshInstance3D.new()
			capital.mesh = _hull
			capital.material_override = _solid[side]
			capital.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			capital.extra_cull_margin = 3000.0
			capital.basis = Basis.looking_at(Vector3(-out, 0.0, 0.25 - 0.5 * k), Vector3.UP).scaled(Vector3.ONE * _rng.randf_range(8.0, 11.0))
			capital.position = Vector3(out * _rng.randf_range(420.0, 640.0), _rng.randf_range(130.0, 280.0), -_rng.randf_range(260.0, 520.0) - 420.0 * k)
			add_child(capital)
			_capitals.append({ node = capital, side = side, away = 0.0 })
	var lines := MeshInstance3D.new()
	lines.mesh = _lines
	lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lines.extra_cull_margin = 2000.0
	add_child(lines)
	_place_fleets()


## One of the capital ships that's there just now (null: none is), for its big gun (endless.gd)
func capital() -> Node3D:
	var there: Array = _capitals.filter(func(c): return c.away <= 0.0)
	return there[_rng.randi() % there.size()].node if not there.is_empty() else null


## A ship down the ring at the runner, to be over the place it fires from in `lead` seconds
func strafe(lead: float) -> Node3D:
	var ship := _ship(0, 1.0)
	var from := STRAFE_FROM + Vector3(_rng.randf_range(8.0, 22.0) * (-1.0 if _rng.randf() < 0.5 else 1.0), 0.0, 0.0)
	var velocity := Vector3(0.0, -2.0, STRAFE_SPEED)
	ship.position = from - velocity * lead
	_ships.append({ node = ship, velocity = velocity, life = lead + 2.5, side = 0, prey = null, gun = 0.0, dies = INF })
	return ship


func _process(delta: float) -> void:
	_clock += delta
	_place_fleets()
	# The fleets' fire: a bolt from a ship of one side at a ship of the other
	_bolt_clock -= delta
	if _bolt_clock <= 0.0:
		_bolt_clock = _rng.randf_range(0.5, 1.8)
		var side := _rng.randi() % 2
		var from: Vector3 = _far_spot(side, _rng.randi() % FLEET)
		var to: Vector3 = _far_spot(1 - side, _rng.randi() % FLEET)
		var hit := _rng.randf() < 0.3
		if not hit: # (wide of it, and on past)
			to += (to - from).normalized() * 160.0 + Vector3(_rng.randf_range(-40.0, 40.0), _rng.randf_range(-40.0, 40.0), _rng.randf_range(-40.0, 40.0))
		_bolts.append({ from = from, to = to, age = 0.0, life = from.distance_to(to) / 1400.0, side = side, wide = 0.5, blast = 11.0 if hit else 0.0 })
	# A capital ship's turn: a heavy bolt from the other side, and it goes up
	for capital in _capitals:
		if capital.away > 0.0:
			capital.away -= delta
			if capital.away <= 0.0:
				capital.node.visible = true
	_nova_clock -= delta
	if _nova_clock <= 0.0:
		_nova_clock = _rng.randf_range(16.0, 30.0)
		var capital: Dictionary = _capitals[_rng.randi() % _capitals.size()]
		if capital.away <= 0.0:
			var from: Vector3 = _far_spot(1 - int(capital.side), _rng.randi() % FLEET)
			_bolts.append({ from = from, to = capital.node.position, age = 0.0, life = from.distance_to(capital.node.position) / 900.0, side = 1 - int(capital.side), wide = 1.4, blast = 0.0, nova = capital })
	# A pair across the ring ahead, the second after the first
	_cross_clock -= delta
	if _cross_clock <= 0.0:
		_cross_clock = _rng.randf_range(5.0, 10.0)
		_cross()
	# The near ships
	for k in range(_ships.size() - 1, -1, -1):
		var ship: Dictionary = _ships[k]
		var node: Node3D = ship.node
		ship.life -= delta
		ship.dies -= delta
		if ship.dies <= 0.0:
			_blast(node.position, 9.0, ship.side)
		if ship.life <= 0.0 or ship.dies <= 0.0:
			node.queue_free()
			_ships.remove_at(k)
			continue
		node.position += ship.velocity * delta
		node.basis = Basis.looking_at(ship.velocity, Vector3.UP).rotated(ship.velocity.normalized(), sin(_clock * 1.7 + k) * 0.25)
		var prey = ship.prey
		if prey != null and is_instance_valid(prey) and not prey.is_queued_for_deletion():
			ship.gun -= delta
			if ship.gun <= 0.0:
				ship.gun = _rng.randf_range(0.3, 0.6)
				var at: Vector3 = prey.position + Vector3(_rng.randf_range(-5.0, 5.0), _rng.randf_range(-5.0, 5.0), _rng.randf_range(-5.0, 5.0))
				_bolts.append({ from = node.position, to = at + (at - node.position).normalized() * 30.0, age = 0.0, life = 0.16, side = ship.side, wide = 0.22, blast = 0.0 })
	# Bolts: a short length of light running from where it was fired to where it's going
	_lines.clear_surfaces()
	for side in 2:
		var any := false
		for k in range(_bolts.size() - 1, -1, -1):
			var bolt: Dictionary = _bolts[k]
			if bolt.side != side:
				continue
			bolt.age += delta
			if bolt.age >= bolt.life:
				if bolt.blast > 0.0:
					_blast(bolt.to, bolt.blast, 1 - side)
				if bolt.has("nova"):
					_nova(bolt.nova)
				_bolts.remove_at(k)
				continue
			if not any:
				_lines.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _faint[side])
				any = true
			var head: float = bolt.age / bolt.life
			var a: Vector3 = (bolt.from as Vector3).lerp(bolt.to, maxf(head - 0.12, 0.0))
			var b: Vector3 = (bolt.from as Vector3).lerp(bolt.to, head)
			var along := (b - a).normalized()
			var across := along.cross(Vector3.UP).normalized() * float(bolt.wide)
			var up := along.cross(across).normalized() * float(bolt.wide)
			for wide in [across, up]:
				for corner in [a - wide, a + wide, b + wide, a - wide, b + wide, b - wide]:
					_lines.surface_add_vertex(corner)
		if any:
			_lines.surface_end()
	# Blasts: a ball of light that swells and goes out
	for k in range(_blasts.size() - 1, -1, -1):
		var blast: Dictionary = _blasts[k]
		blast.age += delta
		var done: float = blast.age / float(blast.life)
		if done >= 1.0:
			blast.node.queue_free()
			_blasts.remove_at(k)
			continue
		blast.node.scale = Vector3.ONE * float(blast.big) * (0.25 + 0.75 * sqrt(done))
		blast.material.albedo_color.a = (1.0 - done) * (1.0 - done) * float(blast.peak)


func _place_fleets() -> void:
	for side in 2:
		var facing := Basis.looking_at(Vector3(1.0 if side == 0 else -1.0, 0.0, 0.0), Vector3.UP)
		for k in FLEET:
			_fleets[side].set_instance_transform(k, Transform3D(facing.scaled(Vector3.ONE * float(_far[side][k].size)), _far_spot(side, k)))


## Where a far ship is just now (each drifts slowly about its place)
func _far_spot(side: int, k: int) -> Vector3:
	var ship: Dictionary = _far[side][k]
	var phase: float = ship.phase
	return ship.home + Vector3(sin(_clock * 0.07 + phase) * 30.0, sin(_clock * 0.11 + phase * 2.0) * 8.0, cos(_clock * 0.05 + phase) * 40.0)


## Two ships over the ring ahead, from one side to the other: one running, one after it
func _cross() -> void:
	var way := -1.0 if _rng.randf() < 0.5 else 1.0
	var chased := _rng.randi() % 2
	var velocity := Vector3(way * CROSS_SPEED, _rng.randf_range(-4.0, 4.0), _rng.randf_range(-25.0, 25.0))
	var start := Vector3(-way * 560.0, _rng.randf_range(30.0, 85.0), -_rng.randf_range(130.0, 380.0))
	var prey := _ship(chased, 1.0)
	prey.position = start
	_ships.append({ node = prey, velocity = velocity, life = 6.6, side = chased, prey = null, gun = 0.0, dies = _rng.randf_range(2.2, 4.2) if _rng.randf() < 0.4 else INF })
	var hunter := _ship(1 - chased, 1.0)
	hunter.position = start - velocity.normalized() * 48.0 + Vector3(0.0, 4.0, 0.0)
	_ships.append({ node = hunter, velocity = velocity, life = 6.9, side = 1 - chased, prey = prey, gun = 0.5, dies = INF })


func _ship(side: int, size: float) -> MeshInstance3D:
	var ship := MeshInstance3D.new()
	ship.mesh = _hull
	ship.material_override = _solid[side]
	ship.scale = Vector3.ONE * size
	ship.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Its engine: a point of its side's light at the stern
	var engine := MeshInstance3D.new()
	engine.mesh = Crystal.shard(0.9, 9.0, 0.0, 5)
	engine.material_override = _light[side]
	engine.rotation.x = PI * 0.5
	engine.position.z = 9.5
	engine.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ship.add_child(engine)
	add_child(ship)
	return ship


## A capital ship goes up: a white heart, a great ball of its side's light, and a ring that
## runs out from it flat, far past the ball. Another ship comes for its place in a while.
func _nova(capital: Dictionary) -> void:
	var at: Vector3 = capital.node.position
	capital.node.visible = false
	capital.away = _rng.randf_range(14.0, 22.0)
	_blast(at, 60.0, int(capital.side), 1.1, 1.0, false, Color.WHITE)
	_blast(at, 150.0, int(capital.side), 2.6, 0.8)
	_blast(at, 330.0, int(capital.side), 3.2, 0.7, true)


func _blast(at: Vector3, big: float, side: int, life := 0.8, peak := 0.45, ring := false, tint := Color.TRANSPARENT) -> void:
	var ball: PrimitiveMesh
	if ring:
		var hoop := TorusMesh.new()
		hoop.inner_radius = 0.93
		hoop.outer_radius = 1.0
		hoop.rings = 48
		hoop.ring_segments = 4
		ball = hoop
	else:
		var round := SphereMesh.new()
		round.radius = 1.0
		round.height = 2.0
		round.radial_segments = 16
		round.rings = 8
		ball = round
	var material: StandardMaterial3D = _light[side].duplicate()
	if tint.a > 0.0:
		material.albedo_color = tint
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	var node := MeshInstance3D.new()
	node.mesh = ball
	node.material_override = material
	node.position = at
	if ring:
		node.rotation = Vector3(_rng.randf_range(0.9, 1.5), _rng.randf() * TAU, 0.0)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.extra_cull_margin = 3000.0
	add_child(node)
	_blasts.append({ node = node, material = material, age = 0.0, big = big, life = life, peak = peak })


## A Crystalien ship: a long cut crystal, nose along -Z, with two swept blades for wings and a
## fin, about 17 m long
static func ship_mesh() -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_smooth_group(-1)
	# (a shard's length runs along its own Y: turned to lie along the ship)
	var along := Basis(Vector3.RIGHT, Vector3.FORWARD, Vector3.UP)
	Crystal.add_shard(tool, Transform3D(along, Vector3.ZERO), 1.7, 0.85, 17.0, 0.2)
	for side in [-1.0, 1.0]:
		Crystal.add_shard(tool, Transform3D(along.rotated(Vector3.UP, side * 0.95), Vector3(side * 3.6, -0.1, 3.0)), 1.0, 0.22, 10.0, 0.15)
	Crystal.add_shard(tool, Transform3D(along.rotated(Vector3.RIGHT, 0.9), Vector3(0.0, 1.3, 4.5)), 0.25, 0.8, 5.0, 0.15)
	tool.generate_normals()
	return tool.commit()
