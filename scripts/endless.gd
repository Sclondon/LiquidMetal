extends Node3D
## Endless mode's course: the top of the disc-world ring round the Crystaliens' black sand moon
## (ring_world.gd draws the rest of the ring, the moon and its suns' light). The course runs off
## along -Z for ever, built a chunk at a time ahead of the runner and cleared away behind, and it
## is the whole width of the ring: no walls, you can run from one edge to the other, and off
## either edge is a fall.
##
## What's on it:
## - Breaks in the ring: cracks right across to jump, bites out of an edge, holes in the middle,
##   causeways (both sides gone). The floor is made of pieces, so the breaks are really there, in
##   what you stand on and in what's drawn; falling in (or off an edge) splats the runner a few
##   metres down.
## - Crystal formations, each a simple box to run into but drawn as grown crystal: low ridges to
##   jump (amber), curtains and tunnels to slide under (pale blue), tall walls, gates and spires
##   to go round (rose), and palisades standing along the ring to wall-run on (green).
## - Crystals that fall out of the sky ahead of the runner and stay where they land
##   (crystal_fall.gd; `falling_crystals` switches them off).
## - Drops to collect, and boost rings of aurora light (boost_pad.gd).
## It gets denser the further you go, each zone (500 m) adds kinds (ZONE_KINDS), and main.gd
## speeds the runner up. `plan` lists everything laid, as boxes with what to do about each (the
## endless bot test reads it); enemy runners chase along it and feel their own way (ai_input.gd).

const RingWorld := preload("res://scripts/ring_world.gd")
const WIDTH := RingWorld.WIDTH # edge to edge
const HALF := WIDTH * 0.5
const CHUNK := 60.0 # metres built at a time
const AHEAD := 300.0 # built this far ahead of the runner
const BEHIND := 60.0 # and cleared once it's this far behind
const RUNWAY := 45.0 # clear ring at the start
const SLAB := 3.0 # how thick the ring is drawn at its edges and breaks
const DEEP := 8.0 # how deep the floor's colliders go (the far side of a break is a wall)
const FALL := -4.0 # this far below the ring and the runner's splatted
const KINDS := ["ridge", "curtain", "wall", "crack", "bite", "hole", "wallrun"]
# Deeper zones add more: zone 2 gates and fields of spires, zone 3 tunnels and causeways,
# zone 4 rifts (two cracks, one after the other)
const ZONE_KINDS := [[], ["gate", "spires"], ["tunnel", "causeway"], ["rift"]]
const ZONE_LENGTH := 500.0
## Each zone's look: name, sky overhead, horizon glow, fog, and its crystal colour (lines)
const ZONES := [
	# (out in space: black overhead, a thin glow along the horizon, fog that fades to the dark;
	# lines: the zone's crystal colour, on the kerbs, the sand's glints and the moon's fields)
	{ name = "AMETHYST REACH", top = Color(0.012, 0.008, 0.03), horizon = Color(0.6, 0.35, 1.0), fog = Color(0.03, 0.02, 0.07), lines = Color(0.65, 0.4, 1.0), space = 1.0 },
	{ name = "EMERALD DRIFT", top = Color(0.006, 0.02, 0.016), horizon = Color(0.35, 1.0, 0.55), fog = Color(0.015, 0.05, 0.03), lines = Color(0.35, 1.0, 0.55), space = 1.0 },
	{ name = "ICE ARC", top = Color(0.006, 0.014, 0.03), horizon = Color(0.55, 0.85, 1.0), fog = Color(0.02, 0.04, 0.07), lines = Color(0.5, 0.9, 1.0), space = 1.0 },
	{ name = "EMBER ARC", top = Color(0.03, 0.008, 0.006), horizon = Color(1.0, 0.5, 0.2), fog = Color(0.07, 0.025, 0.015), lines = Color(1.0, 0.5, 0.2), space = 1.0 },
	{ name = "THE DARK SIDE", top = Color(0.004, 0.0, 0.012), horizon = Color(0.8, 0.3, 0.9), fog = Color(0.03, 0.01, 0.05), lines = Color(0.9, 0.35, 0.8), space = 1.0 },
]

signal zone_changed(index: int, zone: Dictionary)

var zone := 0
const GAP_EASY := 27.0 # metres between one thing and the next at the start...
const GAP_HARD := 18.0 # ...closing to this by HARD_AT metres in
const HARD_AT := 2500.0
const SIDEWAYS := 0.55 # metres across the ring a runner can be asked to make per metre along
const TUNNEL := 10.0 # metres of low roof
const LOW := 0.95 # how far off the sand a beam is: a slide fits under, a runner on his feet doesn't
const SPEED_UP := 3000.0 # (main.gd's ENDLESS_FAST: the runner's at full speed by here)

const JUMP_COLOR := Color(1.0, 0.65, 0.25)
const DUCK_COLOR := Color(0.45, 0.85, 1.0)
const DODGE_COLOR := Color(1.0, 0.4, 0.65)
const WALL_RUN_COLOR := Color(0.3, 0.95, 0.6) # the tall walls made for running on
const BoostPad := preload("res://scripts/boost_pad.gd")
const Crystal := preload("res://scripts/crystal.gd")
const CrystalFall := preload("res://scripts/crystal_fall.gd")
const Runner := preload("res://scripts/player.gd")
const AiInput := preload("res://scripts/ai_input.gd")
const Difficulty := preload("res://scripts/difficulty.gd")

## What a formation is drawn with: [metres of ground one module covers, its nominal height]
const MODULE := 4.0
const FALL_FROM := 140.0 # metres in before crystals start falling

## Enemy runners on the ring (main turns them off for some tests)
var with_enemies := true
var enemies: Array = []
## Crystals falling out of the sky (tests that need a known course turn them off)
@export var falling_crystals := true

var start_position := Vector3(0.0, 0.0, 0.0)
var start_heading := 0.0
var runner: Node3D # who it builds ahead of
## (the other courses' list of what's on their lane: this one has no lane; see `plan`)
var lane_plan: Array = []
## Everything laid, nearest first: { id, kind, act, z0, z1, x0, x1 } (z0 the near side, z1 the
## far: z1 < z0). act: "jump" (be in the air across it), "duck" (be sliding under it), "avoid"
## (don't be there: something tall), "hole" (don't be there: no floor).
var plan: Array = []

var _chunks: Array = [] # [{ from, end, keep, node }], oldest first
var _holes: Array = [] # [{ z0, z1, x0, x1 }]: where the ring's broken
var _built_to := 0.0 # z the course is built out to (it grows toward -Z)
var _next_feature := 0.0
var _last_kind := ""
var _last_free: Array = [] # where across the ring you could be, coming off the last thing laid
var _no_ring_until := 0.0
var _id := 0
var _rng := RandomNumberGenerator.new()
var _materials := {}
var _ring: Node3D # the rest of the ring, and the moon (ring_world.gd)
var _modules := {} # kind -> [ArrayMesh]: the crystal formations, in lengths to set side by side
var _looks := RandomNumberGenerator.new() # (the scenery's own dice: the course's stay as they were)
var _drop_mesh := SphereMesh.new()
var _fall_clock := 6.0
## How many crystals have been sent down this run
var crystals_sent := 0
var _jolt := 0.0


func _ready() -> void:
	_drop_mesh.radius = 0.28
	_drop_mesh.height = 0.56
	var drop_material := ShaderMaterial.new()
	drop_material.shader = preload("res://shaders/liquid_metal.gdshader")
	drop_material.set_shader_parameter("agitation", 0.6)
	_drop_mesh.material = drop_material
	_looks.seed = 20261012
	_build_modules()
	_ring = RingWorld.new()
	add_child(_ring)
	generate()


func _exit_tree() -> void:
	_shake(0.0)


## Start over: a fresh, random course from the start
func generate(seed := 0) -> void:
	for chunk in _chunks:
		chunk.node.queue_free()
	_chunks.clear()
	_holes.clear()
	plan.clear()
	zone = 0
	_ring.set_color(ZONES[0].lines)
	if seed == 0:
		_rng.randomize()
	else:
		_rng.seed = seed
	for enemy in enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	enemies.clear()
	_built_to = start_position.z + CHUNK
	_next_feature = start_position.z - RUNWAY
	_no_ring_until = _next_feature
	_last_kind = ""
	_last_free = [[-HALF, HALF]]
	_fall_clock = 6.0
	crystals_sent = 0
	_extend()


## Metres run so far
func distance() -> float:
	return maxf(start_position.z - runner.global_position.z, 0.0) if runner else 0.0


## Is there ring to stand on here?
func floor_at(x: float, z: float) -> bool:
	if absf(x) > HALF:
		return false
	for hole in _holes:
		if z < hole.z0 and z > hole.z1 and x > hole.x0 and x < hole.x1:
			return false
	return true


func _physics_process(delta: float) -> void:
	if runner == null:
		return
	var now := int(distance() / ZONE_LENGTH)
	if now != zone:
		zone = now
		var look: Dictionary = ZONES[zone % ZONES.size()]
		_ring.set_color(look.lines)
		zone_changed.emit(zone, look)
	if with_enemies and distance() > 60.0 and enemies.size() < int(Difficulty.tier().endless_enemies) and _rng.randf() < delta * float(Difficulty.tier().endless_rate):
		_spawn_enemy(runner.global_position.z + _rng.randf_range(22.0, 34.0)) # behind him: they chase
	_extend()
	_ring.follow(runner.global_position.z, _chunks[0].from if not _chunks.is_empty() else INF, _built_to)
	# Into a break, or off the edge: a short fall, and that's that
	if runner.global_position.y < FALL and not runner.dead:
		runner._splat()
	# Enemies: gone once well behind (or a while after blowing up, or falling off)
	for i in range(enemies.size() - 1, -1, -1):
		var enemy = enemies[i]
		if not is_instance_valid(enemy) or enemy.global_position.z > runner.global_position.z + BEHIND or (enemy.dead and enemy.get_meta("dead_for", 0.0) > 4.0):
			if is_instance_valid(enemy):
				enemy.queue_free()
			enemies.remove_at(i)
		elif enemy.dead:
			enemy.set_meta("dead_for", enemy.get_meta("dead_for", 0.0) + delta)
		elif enemy.global_position.y < FALL:
			enemy._splat()
	if falling_crystals and not runner.dead and distance() > FALL_FROM:
		_fall_clock -= delta
		if _fall_clock <= 0.0:
			_send_crystals()
	# Clear what's well behind
	while not _chunks.is_empty() and _chunks[0].keep > runner.global_position.z + BEHIND:
		_chunks.pop_front().node.queue_free()
	var behind := runner.global_position.z + BEHIND + CHUNK * 2.0
	while not plan.is_empty() and plan[0].z1 > behind:
		plan.pop_front()
	while not _holes.is_empty() and _holes[0].z1 > behind:
		_holes.pop_front()


func _process(delta: float) -> void:
	if _jolt > 0.0:
		_jolt = maxf(_jolt - delta * 2.2, 0.0)
		_shake(_jolt)


## The camera knocked about (a crystal landing): amount in metres, 0 to settle it
func _shake(amount: float) -> void:
	var viewport := get_viewport()
	var camera := viewport.get_camera_3d() if viewport else null
	if camera:
		camera.h_offset = randf_range(-1.0, 1.0) * amount
		camera.v_offset = randf_range(-1.0, 1.0) * amount


func _extend() -> void:
	var ahead_to := (runner.global_position.z if runner else start_position.z) - AHEAD
	while _built_to > ahead_to:
		_build_chunk(_built_to, _built_to - CHUNK)
		_built_to -= CHUNK


func _zone_at(z: float) -> int:
	return int(maxf(start_position.z - z, 0.0) / ZONE_LENGTH)


## How fast the runner will be going by here (main.gd speeds him up as he goes)
func _speed_at(z: float) -> float:
	var speeds: Vector2 = Difficulty.tier().endless_speed
	return lerpf(speeds.x, speeds.y, clampf((start_position.z - z) / SPEED_UP, 0.0, 1.0))


func _build_chunk(from: float, to: float) -> void:
	var node := Node3D.new()
	add_child(node)
	var chunk := { from = from, end = to, keep = to, node = node }
	_chunks.append(chunk)
	# What's on it, closer together the further in
	while _next_feature > to:
		var kinds := KINDS.duplicate()
		var zone_here := _zone_at(_next_feature)
		for k in mini(zone_here + 1, ZONE_KINDS.size()):
			kinds.append_array(ZONE_KINDS[k])
			kinds.append_array(ZONE_KINDS[k]) # (the new ones come up a bit more)
		var kind: String = kinds[_rng.randi() % kinds.size()]
		while kind == _last_kind:
			kind = kinds[_rng.randi() % kinds.size()]
		_last_kind = kind
		var pieces := _design(kind, _speed_at(_next_feature))
		# Where across the ring it lets you by, and so how much further on it has to be for
		# someone coming off the last thing at its worst spot to get there
		var blocked := []
		var length := 0.0
		for piece in pieces:
			length = maxf(length, piece.far)
			if piece.act == "avoid" or piece.act == "hole":
				blocked.append([piece.x0 - 1.6, piece.x1 + 1.6])
		var free := _open(blocked, -HALF + 1.5, HALF - 1.5)
		var across := 0.0
		for span in _last_free:
			for x in span:
				across = maxf(across, _away(x, free))
		var z := _next_feature - minf(across / SIDEWAYS, 50.0)
		_last_free = free
		_lay(node, kind, pieces, z)
		chunk.keep = minf(chunk.keep, z - length - 4.0)
		var hard := clampf((start_position.z - z) / HARD_AT, 0.0, 1.0)
		var gap := lerpf(GAP_EASY, GAP_HARD, hard) * float(Difficulty.tier().gap_scale) * _rng.randf_range(0.9, 1.15)
		if _extras(node, kind, pieces, z, free):
			gap += 16.0 # (room for the boost to ease off)
		_next_feature = z - length - gap
	_build_floor(node, from, to)


## What a kind of thing is made of: pieces, each { type, act, near, far (metres on from where
## the thing starts), x0, x1, height }. speed: how fast the runner is by then.
func _design(kind: String, speed: float) -> Array:
	var pieces := []
	var crack := clampf(speed * 0.33, 4.5, 7.5) # (a jump covers about 0.65 of his speed)
	match kind:
		"ridge": # a low jagged ridge: jump it (or, where it stops short, go round)
			var span := _span(22.0, 40.0, 0.5)
			pieces.append(_piece("ridge", "jump", 0.0, 0.5, span.x, span.y, 0.8))
		"curtain": # a beam of crystal across, hung between two posts: slide under it
			var span := _span(22.0, 40.0, 0.5)
			pieces.append(_piece("curtain", "duck", 0.0, 0.8, span.x, span.y, 2.3))
		"tunnel": # a low roof to slide the length of
			var span := _span(24.0, 40.0, 0.4)
			pieces.append(_piece("curtain", "duck", 0.0, TUNNEL, span.x, span.y, 2.3))
		"wall": # stretches of tall crystal, one to a third of the ring: round them
			var third := WIDTH / 3.0
			var stands := [_rng.randf() < 0.6, _rng.randf() < 0.6, _rng.randf() < 0.6]
			if not stands.has(true):
				stands[_rng.randi() % 3] = true
			for k in 3:
				if stands[k]:
					var wide := _rng.randf_range(8.0, 13.0)
					var x := -HALF + third * k + _rng.randf_range(2.0, third - wide - 2.0)
					var on := _rng.randf_range(0.0, 8.0)
					pieces.append(_piece("wall", "avoid", on, on + 1.2, x, x + wide, _rng.randf_range(3.2, 4.6)))
		"gate": # a tall wall right across with two or three ways through
			var ways := 2 + _rng.randi() % 2
			var each := WIDTH / ways
			var x := -HALF
			for k in ways:
				var wide := _rng.randf_range(7.0, 9.0)
				var middle := -HALF + each * (k + _rng.randf_range(0.3, 0.7))
				pieces.append(_piece("wall", "avoid", 0.0, 1.4, x, middle - wide * 0.5, 4.6))
				x = middle + wide * 0.5
			pieces.append(_piece("wall", "avoid", 0.0, 1.4, x, HALF, 4.6))
		"spires": # a field of tall single crystals to weave through
			var spots: Array[Vector2] = []
			for tries in 60:
				var spot := Vector2(_rng.randf_range(-HALF + 3.0, HALF - 3.0), _rng.randf_range(1.0, 33.0))
				var clear := true
				for other in spots:
					if spot.distance_to(other) < 8.5:
						clear = false
				if clear:
					spots.append(spot)
				if spots.size() >= 9:
					break
			for spot in spots:
				pieces.append(_piece("spire", "avoid", spot.y - 0.9, spot.y + 0.9, spot.x - 0.9, spot.x + 0.9, 6.0))
		"crack": # a break right across: jump it
			pieces.append(_piece("hole", "jump", 0.0, crack, -HALF, HALF, 0.0))
		"rift": # two of them: jump, land, jump
			var between := maxf(speed * 0.65 - crack + 6.0, 9.0)
			pieces.append(_piece("hole", "jump", 0.0, crack, -HALF, HALF, 0.0))
			pieces.append(_piece("hole", "jump", crack + between, crack * 2.0 + between, -HALF, HALF, 0.0))
		"bite": # a piece gone out of one edge
			var deep := WIDTH * _rng.randf_range(0.35, 0.6)
			var long := _rng.randf_range(14.0, 28.0)
			if _rng.randf() < 0.5:
				pieces.append(_piece("hole", "hole", 0.0, long, -HALF, -HALF + deep, 0.0))
			else:
				pieces.append(_piece("hole", "hole", 0.0, long, HALF - deep, HALF, 0.0))
		"hole": # a hole in the middle: either side of it
			var wide := _rng.randf_range(12.0, 22.0)
			var long := _rng.randf_range(12.0, 22.0)
			var middle := _rng.randf_range(-1.0, 1.0) * (HALF - wide * 0.5 - 7.0)
			pieces.append(_piece("hole", "hole", 0.0, long, middle - wide * 0.5, middle + wide * 0.5, 0.0))
		"causeway": # both sides gone: a strip left to run along
			var wide := _rng.randf_range(12.0, 15.0)
			var long := _rng.randf_range(26.0, 36.0)
			var middle := _rng.randf_range(-12.0, 12.0)
			pieces.append(_piece("hole", "hole", 0.0, long, -HALF, middle - wide * 0.5, 0.0))
			pieces.append(_piece("hole", "hole", 0.0, long, middle + wide * 0.5, HALF, 0.0))
		"wallrun": # a tall palisade standing along the ring, made for running on
			var x := _rng.randf_range(8.0, 19.0) * (-1.0 if _rng.randf() < 0.5 else 1.0)
			pieces.append(_piece("palisade", "avoid", 0.0, 40.0, x - 0.45, x + 0.45, 8.5))
	return pieces


func _piece(type: String, act: String, near: float, far: float, x0: float, x1: float, height: float) -> Dictionary:
	return { type = type, act = act, near = near, far = far, x0 = x0, x1 = x1, height = height }


## A stretch across the ring: all of it (`whole` of the time), or between narrow and wide metres
func _span(narrow: float, wide: float, whole: float) -> Vector2:
	if _rng.randf() < whole:
		return Vector2(-HALF, HALF)
	var width := _rng.randf_range(narrow, wide)
	var x := _rng.randf_range(-HALF, HALF - width)
	# (never a sliver left at an edge: out to the edge instead)
	if x < -HALF + 5.0:
		x = -HALF
	if x + width > HALF - 5.0:
		width = HALF - x
	return Vector2(x, x + width)


## Builds a designed thing at z (it runs on from there toward -Z), and notes it in the plan
func _lay(node: Node3D, kind: String, pieces: Array, z: float) -> void:
	for piece in pieces:
		var z0: float = z - piece.near
		var z1: float = z - piece.far
		var x0: float = piece.x0
		var x1: float = piece.x1
		_id += 1
		plan.append({ id = _id, kind = kind, act = piece.act, z0 = z0, z1 = z1, x0 = x0, x1 = x1 })
		var middle := Vector3((x0 + x1) * 0.5, 0.0, (z0 + z1) * 0.5)
		var height: float = piece.height
		match piece.type:
			"hole":
				_holes.append({ z0 = z0, z1 = z1, x0 = x0, x1 = x1 })
			"ridge":
				_formation(node, Vector3(x1 - x0, height, z0 - z1), middle + Vector3.UP * height * 0.5, JUMP_COLOR, "ridge")
			"curtain": # (its foot is LOW up)
				_formation(node, Vector3(x1 - x0, height - LOW, z0 - z1), middle + Vector3.UP * (LOW + (height - LOW) * 0.5), DUCK_COLOR, "curtain")
				# A post at each end to hang it from (off the ring's edge, where it goes that far)
				for end in [x0, x1]:
					_formation(node, Vector3(0.9, 4.2, 0.9), Vector3(end, 2.1, middle.z), DUCK_COLOR, "post", absf(end) < HALF - 0.5)
					if absf(end) < HALF - 0.5:
						_id += 1
						plan.append({ id = _id, kind = kind, act = "avoid", z0 = z0 + 0.3, z1 = z1 - 0.3, x0 = end - 0.45, x1 = end + 0.45 })
			"wall":
				_formation(node, Vector3(x1 - x0, height, z0 - z1), middle + Vector3.UP * height * 0.5, DODGE_COLOR, "wall")
			"spire":
				_formation(node, Vector3(x1 - x0, height, z0 - z1), middle + Vector3.UP * height * 0.5, DODGE_COLOR, "spire")
			"palisade":
				_formation(node, Vector3(x1 - x0, height, z0 - z1), middle + Vector3.UP * height * 0.5, WALL_RUN_COLOR, "palisade")
				# A line of drops up along it, where only a wall run reaches
				var side := -signf(middle.x)
				for k in 7:
					_drop(node, Vector3(middle.x + side * 1.0, 1.9, z0 - 6.0 - k * 5.0))


## Drops leading up to a thing (and over a crack), and now and then a boost ring past it
func _extras(node: Node3D, kind: String, pieces: Array, z: float, free: Array) -> bool:
	var length := 0.0
	for piece in pieces:
		length = maxf(length, piece.far)
	# The drops: toward a way through, somewhere across the ring
	var way: Array = free[_rng.randi() % free.size()] if not free.is_empty() else [-4.0, 4.0]
	var x := _rng.randf_range(float(way[0]) + 1.0, maxf(float(way[1]) - 1.0, float(way[0]) + 1.0))
	for k in 3:
		_drop(node, Vector3(x, 0.0, z + 9.0 + k * 2.5))
	if kind == "crack":
		for k in 3: # (an arc of them over it)
			_drop(node, Vector3(x, 1.2 + (0.8 if k == 1 else 0.0), z - length * 0.5 + (k - 1) * 2.2))
	# A boost ring: on the sand past it, or up over a crack or a ridge to jump through
	var jumped := kind == "crack" or kind == "ridge"
	if _rng.randf() < (0.5 if jumped else 0.25) and z < _no_ring_until and kind != "rift":
		var pad := BoostPad.new()
		if jumped and _rng.randf() < 0.7:
			var piece: Dictionary = pieces[0]
			pad.lift = 1.5
			pad.position = Vector3(clampf(x, float(piece.x0) + 3.0, float(piece.x1) - 3.0), 0.0, z - length * 0.5)
		else:
			pad.position = Vector3(x, 0.0, z - length - 7.0)
		# (not one hanging over a hole, and nothing boosted into too soon after another)
		if pad.lift > 0.0 or floor_at(pad.position.x, pad.position.z):
			node.add_child(pad)
			_no_ring_until = z - 90.0
			return true
		else:
			pad.free()
	return false


## An enemy runner: the player's own runner with an AI at the controls
func _spawn_enemy(z: float) -> void:
	# Never on top of anything, or over a break: nudged on until it's 8 m clear
	var x: float = clampf((runner.global_position.x if runner else 0.0) + _rng.randf_range(-2.0, 2.0), -HALF + 4.0, HALF - 4.0)
	for tries in 12:
		var clear := _clear_at(x, z, 8.0)
		for other in enemies:
			if is_instance_valid(other) and absf(other.global_position.z - z) < 12.0:
				clear = false
		if clear:
			break
		z += 6.0 # (further back: they spawn behind him)
	if runner and z - runner.global_position.z < 15.0:
		return # (never right on top of him)
	if not _clear_at(x, z, 2.0):
		return
	var ai := AiInput.new()
	ai.course = self
	ai.target = runner
	ai.mind_ground = true
	var enemy := Runner.new()
	enemy.input = ai
	enemy.add_child(ai)
	add_child(enemy)
	ai.body = enemy
	enemy.make_enemy()
	enemy.place(Vector3(x, 0.0, z), 0.0)
	enemy.run_speed = runner.run_speed * float(Difficulty.tier().chase) if runner else 9.0
	enemy.speed = enemy.run_speed
	enemies.append(enemy)


## Ring underfoot here, and nothing laid within `room` metres along it at this point across?
func _clear_at(x: float, z: float, room: float) -> bool:
	if not floor_at(x, z):
		return false
	for thing in plan:
		if z < thing.z0 + room and z > thing.z1 - room and x > thing.x0 - 2.0 and x < thing.x1 + 2.0:
			return false
	return true


# --- Falling crystals --------------------------------------------------------------------

## Time for another: one (or, further in, a few) aimed down the runner's path, far enough on
## that he sees the mark and has to go round what lands
func _send_crystals() -> void:
	var hard := clampf(distance() / HARD_AT, 0.0, 1.0)
	_fall_clock = lerpf(7.0, 2.6, hard) * float(Difficulty.tier().gap_scale) * _rng.randf_range(0.7, 1.3)
	var count := 1
	if zone >= 1 and _rng.randf() < 0.35:
		count = 2
	if zone >= 3 and _rng.randf() < 0.3:
		count = 3
	var warn := 1.6
	var sent := false
	var going: Vector3 = runner.velocity
	going.y = 0.0
	if going.length() < 4.0:
		going = runner.forward() * 4.0
	for k in count:
		var lead := warn + _rng.randf_range(0.8, 1.4)
		var spot: Vector3 = runner.global_position + going * lead
		spot.x += _rng.randf_range(-2.5, 2.5) + (k * _rng.randf_range(5.0, 10.0) * (-1.0 if _rng.randf() < 0.5 else 1.0))
		spot.y = 0.0
		# Onto open ring only: never in or beside anything laid, where it could shut the way through
		for tries in 5:
			if _open_at(spot.x, spot.z) and absf(spot.x) < HALF - 2.5:
				drop_crystal(spot, warn)
				sent = true
				break
			spot.z -= 5.0
	if not sent:
		_fall_clock = 0.4 # (nowhere open just here: again in a moment)


## Open ring for a crystal to land on: floor, no other crystal within 8 m, and nothing laid
## near along the ring, anywhere across it: 14 m clear of whatever has to be gone round (so it
## never shuts the way to or from a gap), 8 m short of or 6 m past what's jumped or slid under
func _open_at(x: float, z: float) -> bool:
	if not floor_at(x, z):
		return false
	for thing in plan:
		if thing.kind == "falling" or thing.kind == "fallen":
			if Vector2(x - (float(thing.x0) + float(thing.x1)) * 0.5, z - (float(thing.z0) + float(thing.z1)) * 0.5).length() < 8.0:
				return false
		elif thing.act == "avoid" or thing.act == "hole":
			if z < thing.z0 + 14.0 and z > thing.z1 - 14.0:
				return false
		elif z < thing.z0 + 8.0 and z > thing.z1 - 6.0:
			return false
	return true


## A crystal out of the sky onto this spot, landing in `warn` seconds (and there to stay). It's
## in the plan from now, as "falling" until it lands and "fallen" after.
func drop_crystal(spot: Vector3, warn := 1.6) -> Node3D:
	var fall := CrystalFall.new()
	fall.warn = warn
	fall.color = ZONES[_zone_at(spot.z) % ZONES.size()].lines
	fall.position = Vector3(spot.x, 0.0, spot.z)
	fall.struck.connect(_on_struck)
	# (it goes when its stretch of the ring does)
	var parent: Node3D = self
	for chunk in _chunks:
		if spot.z <= chunk.from and spot.z > chunk.end:
			parent = chunk.node
	parent.add_child(fall)
	_id += 1
	var half: float = CrystalFall.BLOCK.x * 0.5
	var falling := { id = _id, kind = "falling", act = "avoid", z0 = spot.z + half, z1 = spot.z - half, x0 = spot.x - half, x1 = spot.x + half }
	fall.set_meta("plan", falling)
	crystals_sent += 1
	# (the plan's kept nearest first)
	var at := plan.size()
	while at > 0 and plan[at - 1].z0 < falling.z0:
		at -= 1
	plan.insert(at, falling)
	return fall


func _on_struck(fall: Node3D) -> void:
	var spot := fall.global_position
	fall.get_meta("plan").kind = "fallen"
	# Anyone under it
	var under: Array = enemies.duplicate()
	under.append(runner)
	for body in under:
		if is_instance_valid(body) and not body.dead and body.global_position.y < CrystalFall.BLOCK.y and Vector2(body.global_position.x - spot.x, body.global_position.z - spot.z).length() < CrystalFall.HIT:
			body._splat()
	if runner:
		_jolt = maxf(_jolt, clampf(0.5 - spot.distance_to(runner.global_position) / 120.0, 0.0, 0.4))


# --- The floor ---------------------------------------------------------------------------

## The stretches across the ring that are floor at z: [[x0, x1], ...]
func _floor_spans(z: float) -> Array:
	var gone := []
	for hole in _holes:
		if z < hole.z0 and z > hole.z1:
			gone.append([hole.x0, hole.x1])
	return _open(gone, -HALF, HALF)


## What's left of from..to with the `shut` spans taken out
func _open(shut: Array, from: float, to: float) -> Array:
	shut.sort_custom(func(a, b): return a[0] < b[0])
	var open := []
	var x := from
	for span in shut:
		var a: float = span[0]
		var b: float = span[1]
		if a > x + 0.01:
			open.append([x, minf(a, to)])
		x = maxf(x, b)
		if x >= to:
			break
	if x < to - 0.01:
		open.append([x, to])
	return open


## How far x is from the nearest of the spans (0: in one)
func _away(x: float, spans: Array) -> float:
	var best := WIDTH if not spans.is_empty() else 0.0
	for span in spans:
		var a: float = span[0]
		var b: float = span[1]
		best = minf(best, 0.0 if x >= a and x <= b else minf(absf(x - a), absf(x - b)))
	return best


## A chunk's floor: the ring from `from` to `to` less its breaks, as pieces. Each piece is a
## box to stand on and a slab of sand to see; along every edge with nothing beyond it (the
## ring's two edges, and round each break) runs a low kerb of crystal, drawn only.
func _build_floor(node: Node3D, from: float, to: float) -> void:
	var cuts: Array[float] = [from, to]
	for hole in _holes:
		for z in [hole.z0, hole.z1]:
			if z < from - 0.01 and z > to + 0.01:
				cuts.append(z)
	cuts.sort()
	cuts.reverse()
	var body := StaticBody3D.new()
	node.add_child(body)
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var kerbs: Array[Transform3D] = []
	for k in cuts.size() - 1:
		var near := cuts[k]
		var far := cuts[k + 1]
		if near - far < 0.01:
			continue
		for span in _floor_spans((near + far) * 0.5):
			var x0: float = span[0]
			var x1: float = span[1]
			var shape := BoxShape3D.new()
			shape.size = Vector3(x1 - x0, DEEP, near - far)
			var collider := CollisionShape3D.new()
			collider.shape = shape
			collider.position = Vector3((x0 + x1) * 0.5, -DEEP * 0.5, (near + far) * 0.5)
			body.add_child(collider)
			_slab(tool, x0, x1, near, far)
			_kerb(kerbs, Vector3(x0 + 0.3, 0.0, near), Vector3(x0 + 0.3, 0.0, far))
			_kerb(kerbs, Vector3(x1 - 0.3, 0.0, near), Vector3(x1 - 0.3, 0.0, far))
	# Kerbs across the ring, wherever there's floor on one side of a cut and none on the other
	# (this chunk's far end is the next one's to do, once it knows what breaks start there)
	for k in cuts.size() - 1:
		var z := cuts[k]
		var before := _floor_spans(z + 0.02)
		var after := _floor_spans(z - 0.02)
		for span in _less(before, after):
			_kerb(kerbs, Vector3(span[0], 0.0, z + 0.3), Vector3(span[1], 0.0, z + 0.3))
		for span in _less(after, before):
			_kerb(kerbs, Vector3(span[0], 0.0, z - 0.3), Vector3(span[1], 0.0, z - 0.3))
	var view := MeshInstance3D.new()
	view.mesh = tool.commit()
	view.material_override = _ring.sand
	node.add_child(view)
	if not kerbs.is_empty():
		var many := MultiMesh.new()
		many.transform_format = MultiMesh.TRANSFORM_3D
		many.mesh = _modules.kerb[_looks.randi() % _modules.kerb.size()]
		many.instance_count = kerbs.size()
		for k in kerbs.size():
			many.set_instance_transform(k, kerbs[k])
		var row := MultiMeshInstance3D.new()
		row.multimesh = many
		row.material_override = _crystal_material(ZONES[_zone_at(from) % ZONES.size()].lines, 0.5)
		row.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(row)


## The spans of `a` with those of `b` taken out
func _less(a: Array, b: Array) -> Array:
	var left := []
	for span in a:
		var from: float = span[0]
		var to: float = span[1]
		var shut := []
		for other in b:
			if other[1] > from and other[0] < to:
				shut.append([other[0], other[1]])
		left.append_array(_open(shut, from, to))
	return left


## One piece of the floor into the mesh: its top, and its four sides down SLAB metres
func _slab(tool: SurfaceTool, x0: float, x1: float, near: float, far: float) -> void:
	var a := Vector3(x0, 0.0, near)
	var b := Vector3(x1, 0.0, near)
	var c := Vector3(x1, 0.0, far)
	var d := Vector3(x0, 0.0, far)
	var down := Vector3.DOWN * SLAB
	_quad(tool, a, b, c, d, Vector3.UP)
	_quad(tool, a, b, b + down, a + down, Vector3.BACK)
	_quad(tool, d, c, c + down, d + down, Vector3.FORWARD)
	_quad(tool, a, d, d + down, a + down, Vector3.LEFT)
	_quad(tool, b, c, c + down, b + down, Vector3.RIGHT)


func _quad(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3) -> void:
	# (wound to face along the normal)
	var corners := [a, b, c, a, c, d] if (b - a).cross(c - a).dot(normal) < 0.0 else [a, c, b, a, d, c]
	tool.set_normal(normal)
	for corner in corners:
		tool.add_vertex(corner)


## Lengths of kerb from a to b (a line across or along the ring)
func _kerb(kerbs: Array[Transform3D], a: Vector3, b: Vector3) -> void:
	var length := a.distance_to(b)
	if length < 0.4:
		return
	var count := maxi(1, roundi(length / MODULE))
	var turn := Basis(Vector3.UP, 0.0 if absf(a.x - b.x) > absf(a.z - b.z) else PI * 0.5)
	for k in count:
		var flip := Basis(Vector3.UP, PI) if _looks.randf() < 0.5 else Basis.IDENTITY
		kerbs.append(Transform3D(turn * flip * Basis.from_scale(Vector3(length / (count * MODULE), _looks.randf_range(0.8, 1.3), 1.0)), a.lerp(b, (k + 0.5) / count)))


# --- Crystal formations ------------------------------------------------------------------

## The lengths of crystal the formations are set out from, a few of each kind: each covers
## MODULE metres of ground (along X; a palisade's along Z), standing on its origin
func _build_modules() -> void:
	for kind in ["kerb", "ridge", "wall", "curtain", "palisade", "spire", "post"]:
		var meshes: Array[ArrayMesh] = []
		for variant in 3:
			var tool := SurfaceTool.new()
			tool.begin(Mesh.PRIMITIVE_TRIANGLES)
			tool.set_smooth_group(-1)
			match kind:
				"kerb": # small shards every which way, ankle high
					for k in 7:
						_stand(tool, Vector3(-MODULE * 0.5 + (k + 0.5) * MODULE / 7.0 + _looks.randf_range(-0.15, 0.15), 0.0, _looks.randf_range(-0.12, 0.12)), _looks.randf_range(0.22, 0.6), _looks.randf_range(0.1, 0.19), 0.7, 4)
				"ridge": # a jagged row, knee high
					for k in 6:
						_stand(tool, Vector3(-MODULE * 0.5 + (k + 0.5) * MODULE / 6.0, 0.0, _looks.randf_range(-0.1, 0.1)), _looks.randf_range(0.6, 1.0), _looks.randf_range(0.3, 0.42), 0.4, 5)
				"wall": # tall shards packed shoulder to shoulder, smaller ones at their feet (4 m high)
					for k in 5:
						_stand(tool, Vector3(-MODULE * 0.5 + (k + 0.5) * MODULE / 5.0, 0.0, _looks.randf_range(-0.15, 0.15)), _looks.randf_range(3.2, 4.5), _looks.randf_range(0.5, 0.68), 0.13, 6)
					for k in 3:
						_stand(tool, Vector3(_looks.randf_range(-1.8, 1.8), 0.0, 0.45 if k % 2 == 0 else -0.45), _looks.randf_range(1.0, 1.9), _looks.randf_range(0.25, 0.35), 0.45, 5)
				"curtain": # a beam of crystal lying across, LOW off the sand, small ones growing up out of it
					for k in 2:
						var lying := Transform3D(Basis(Vector3.FORWARD, PI * 0.5 + _looks.randf_range(-0.04, 0.04)), Vector3(-1.0 + k * 2.0, LOW + 0.4, 0.0))
						Crystal.add_shard(tool, lying, 0.4, 0.4, 2.8, 0.72, 6)
					for k in 4:
						var top := _looks.randf_range(1.9, 2.5)
						var lean := Basis(Vector3.RIGHT, _looks.randf_range(-0.35, 0.35)) * Basis(Vector3.FORWARD, _looks.randf_range(-0.45, 0.45))
						var radius := _looks.randf_range(0.16, 0.26)
						Crystal.add_shard(tool, Transform3D(lean, Vector3(-MODULE * 0.5 + (k + 0.5) * MODULE / 4.0, (LOW + 0.6 + top) * 0.5, 0.0)), radius, radius, top - LOW - 0.5, 0.3, 5)
				"palisade": # great flat shards standing in line along the ring (8.5 m high)
					for k in 4:
						var high := _looks.randf_range(7.6, 9.6)
						var lean := Basis(Vector3.RIGHT, _looks.randf_range(-0.07, 0.07))
						Crystal.add_shard(tool, Transform3D(lean, Vector3(0.0, high - high * 0.62, -MODULE * 0.5 + (k + 0.5) * MODULE / 4.0)), 0.42, 0.72, high * 1.24, 0.62, 6)
				"spire": # one great crystal, a few small ones round its foot
					_stand(tool, Vector3.ZERO, _looks.randf_range(5.8, 7.0), 0.95, 0.08, 6)
					for k in 3:
						var out := Vector3.RIGHT.rotated(Vector3.UP, k * TAU / 3.0 + _looks.randf()) * 0.8
						_stand(tool, out, _looks.randf_range(1.2, 2.4), 0.3, 0.5, 5)
				"post": # what a curtain hangs from
					_stand(tool, Vector3.ZERO, _looks.randf_range(4.0, 4.6), 0.45, 0.06, 6)
					_stand(tool, Vector3(0.3, 0.0, 0.3), 1.3, 0.24, 0.4, 5)
			tool.generate_normals()
			meshes.append(tool.commit())
		_modules[kind] = meshes


## A shard standing at `foot`, `high` metres of it showing, leaning up to `lean` radians
func _stand(tool: SurfaceTool, foot: Vector3, high: float, radius: float, lean: float, sides: int) -> void:
	var tilt := Basis(Vector3.RIGHT, _looks.randf_range(-lean, lean)) * Basis(Vector3.FORWARD, _looks.randf_range(-lean, lean)) * Basis(Vector3.UP, _looks.randf() * TAU)
	var length := high * 1.3
	Crystal.add_shard(tool, Transform3D(tilt, foot + tilt * Vector3(0.0, high - length * 0.5, 0.0)), radius, radius, length, 0.5, sides)


## Something to run into: a plain box for the collision, drawn as crystal grown to fill it (a
## row of the kind's modules, each stretched a little to fit and set its own way round).
## solid = false: drawn only.
func _formation(node: Node3D, size: Vector3, center: Vector3, color: Color, kind: String, solid := true) -> void:
	var body := StaticBody3D.new()
	body.position = center
	if solid:
		var shape := BoxShape3D.new()
		shape.size = size
		var collider := CollisionShape3D.new()
		collider.shape = shape
		body.add_child(collider)
	var ground := -center.y # (the modules stand on the sand)
	var places: Array[Transform3D] = []
	match kind:
		"spire", "post":
			places.append(Transform3D(Basis(Vector3.UP, _looks.randf() * TAU), Vector3(0.0, ground, 0.0)))
		"palisade":
			var count := maxi(1, roundi(size.z / MODULE))
			for k in count:
				var flip := Basis(Vector3.UP, PI) if _looks.randf() < 0.5 else Basis.IDENTITY
				places.append(Transform3D(flip * Basis.from_scale(Vector3(1.0, size.y / 8.5 * _looks.randf_range(0.94, 1.06), size.z / (count * MODULE))), Vector3(0.0, ground, -size.z * 0.5 + (k + 0.5) * size.z / count)))
		_:
			var count := maxi(1, roundi(size.x / MODULE))
			var rows := maxi(1, roundi(size.z / 1.3)) if kind == "curtain" else 1
			var tall := (size.y / 4.0) if kind == "wall" else 1.0
			for row in rows:
				for k in count:
					var flip := Basis(Vector3.UP, PI) if _looks.randf() < 0.5 else Basis.IDENTITY
					var at := Vector3(-size.x * 0.5 + (k + 0.5) * size.x / count, ground, 0.0 if rows == 1 else -size.z * 0.5 + (row + 0.5) * size.z / rows)
					places.append(Transform3D(flip * Basis.from_scale(Vector3(size.x / (count * MODULE), tall * _looks.randf_range(0.92, 1.08), 1.0)), at))
	var many := MultiMesh.new()
	many.transform_format = MultiMesh.TRANSFORM_3D
	many.mesh = _modules[kind][_looks.randi() % _modules[kind].size()]
	many.instance_count = places.size()
	for k in places.size():
		many.set_instance_transform(k, places[k])
	var view := MultiMeshInstance3D.new()
	view.multimesh = many
	view.material_override = _crystal_material(color, 0.3)
	body.add_child(view)
	node.add_child(body)


# --- Pieces ------------------------------------------------------------------------------

## clarity: how much shows through it (the things to run into: not much, so you see them coming)
func _crystal_material(color: Color, clarity: float) -> ShaderMaterial:
	var key := "crystal %s %.2f" % [color.to_html(), clarity]
	if not _materials.has(key):
		var material := ShaderMaterial.new()
		material.shader = preload("res://shaders/crystal.gdshader")
		material.set_shader_parameter("horizon", color)
		material.set_shader_parameter("sky_top", color.darkened(0.7))
		material.set_shader_parameter("clarity", clarity)
		_materials[key] = material
	return _materials[key]


func _drop(node: Node3D, at: Vector3) -> void:
	var area := Area3D.new()
	area.position = at + Vector3.UP * 0.7
	var shape := SphereShape3D.new()
	shape.radius = 0.7
	var collider := CollisionShape3D.new()
	collider.shape = shape
	area.add_child(collider)
	var view := MeshInstance3D.new()
	view.mesh = _drop_mesh
	area.add_child(view)
	area.body_entered.connect(func(body: Node3D):
		if body.has_method("collect_drop") and area.visible:
			body.collect_drop()
			area.visible = false
			area.set_deferred("monitoring", false)
	)
	node.add_child(area)
