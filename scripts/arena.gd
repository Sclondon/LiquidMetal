extends Node3D
## Arena: an online battle room. Everyone who opens it drops into the same walled square and
## fights for the most mass before the round's clock runs out. Run over drops of metal to grow;
## dash through another runner to burst it (or just run into one a good deal smaller than you);
## a burst runner spills most of its mass back onto the floor and comes back small. Bots fill the
## seats players haven't, so the room's never empty.
##
## Each game moves its own runner (and, for one of them, the bots) and sends where it is; the
## others show it as a puppet. What everyone must agree on (mass, drops, who burst whom, the
## clock) is the room's: arena_net.gd (the site's server) or, when that can't be reached,
## arena_room.gd (the same room run here, with bots only). This script lays the arena out, keeps
## the runners and drops as the room describes them, and claims drops and hits for the runners
## this game moves. main.gd shows the score, the standings and the banners.

signal status(text: String, sub: String) # for a banner
signal feed(text: String) # who burst whom
signal round_over(top: Array)
signal round_started
signal player_placed # the player's somewhere new (in, or back after a burst): the camera should jump there

const WALL_COLOR := Color(0.2, 1.0, 0.45)
const BLOCK_COLOR := Color(1.0, 0.2, 0.75)
const SLAB_COLOR := Color(1.0, 0.5, 0.1)
const Runner := preload("res://scripts/player.gd")
const AiInput := preload("res://scripts/ai_input.gd")
const BotInput := preload("res://scripts/bot_input.gd")
const BoostPad := preload("res://scripts/boost_pad.gd")
const ArenaRoom := preload("res://scripts/arena_room.gd")
const ArenaNet := preload("res://scripts/arena_net.gd")

const BASE_SPEED := 13.0
const SEND_EVERY := 1.0 / 15.0 # runner states out, a second
const RESPAWN := 2.5 # seconds burst before coming back
const EAT := 1.3 # this many times its mass, and you burst it just by running into it
const K_STATE := 1
## The other runners' metal: what it mirrors, and its slash's trail
const TINTS := [
	{ top = Color(0.25, 0.02, 0.04), horizon = Color(1.0, 0.25, 0.15), ground = Color(0.08, 0.02, 0.02), glow = Color(1.0, 0.2, 0.1), trail = Color(1.0, 0.3, 0.2) },
	{ top = Color(0.22, 0.12, 0.0), horizon = Color(1.0, 0.75, 0.15), ground = Color(0.08, 0.05, 0.0), glow = Color(1.0, 0.7, 0.1), trail = Color(1.0, 0.8, 0.25) },
	{ top = Color(0.02, 0.2, 0.06), horizon = Color(0.3, 1.0, 0.35), ground = Color(0.01, 0.07, 0.02), glow = Color(0.2, 1.0, 0.3), trail = Color(0.4, 1.0, 0.45) },
	{ top = Color(0.14, 0.03, 0.28), horizon = Color(0.75, 0.35, 1.0), ground = Color(0.05, 0.01, 0.09), glow = Color(0.7, 0.3, 1.0), trail = Color(0.8, 0.45, 1.0) },
	{ top = Color(0.26, 0.03, 0.16), horizon = Color(1.0, 0.35, 0.72), ground = Color(0.09, 0.01, 0.05), glow = Color(1.0, 0.3, 0.7), trail = Color(1.0, 0.45, 0.8) },
	{ top = Color(0.0, 0.16, 0.2), horizon = Color(0.2, 0.95, 0.9), ground = Color(0.0, 0.06, 0.07), glow = Color(0.1, 0.9, 0.9), trail = Color(0.35, 1.0, 0.95) },
	{ top = Color(0.2, 0.18, 0.02), horizon = Color(0.95, 1.0, 0.3), ground = Color(0.07, 0.07, 0.0), glow = Color(0.9, 1.0, 0.2), trail = Color(0.95, 1.0, 0.4) },
]

var half := 70.0 # metres from the middle to each wall (the room's)
var start_position := Vector3(0.0, 0.0, 30.0)
var start_heading := 0.0
var runner: CharacterBody3D # the player
var with_enemies := true # false: no bots (tests; only when the room's run here)
var lane_plan: Array = [] # (no lane here)
## The site's server ("https://..."); empty: the room's run here, with bots
var server := ""
var player_name := "RUNNER"
var round_time := 0.0 # a room run here: its rounds, in seconds (0: the usual)

var online := false
var me := 0 # this player's runner, once in the room
## id -> { id, name, bot, mass, alive, kills, mine, body, tag, tint, safe, down, placed, wait, ask }
##   mine: this game moves it (the player, and the bots when it's the one running them)
##   safe: seconds left it can't hit or be hit; down: seconds till one of mine gets back up
var runners := {}
## id -> { view, x, z, v, taken } (taken: seconds left on a claim the room hasn't answered)
var drops := {}
var phase := "connecting" # then "play" / "over"
var time_left := 0.0
var smashes := 0 # runners the player has burst this round
var peak := 0 # the most mass the player has had

var _room: Node
var _course: Node3D
var _materials := {}
var _drop_mesh := SphereMesh.new()
var _send_clock := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_drop_mesh.radius = 0.28
	_drop_mesh.height = 0.56
	_drop_mesh.radial_segments = 12
	_drop_mesh.rings = 6
	var drop_material := ShaderMaterial.new()
	drop_material.shader = preload("res://shaders/liquid_metal.gdshader")
	drop_material.set_shader_parameter("agitation", 0.6)
	_drop_mesh.material = drop_material
	_build_course([]) # bare, till the room says what's in it
	if server != "":
		var net := ArenaNet.new()
		_use_room(net)
		net.open(player_name, server)
		status.emit("ARENA", "finding the room...")
	else:
		_go_local()


func _exit_tree() -> void:
	if _room:
		_room.close()


## Everyone in the room, most mass first: [{ id, name, mass, kills, bot, me }]
func standings() -> Array:
	var rows := []
	for r in runners.values():
		rows.append({ id = r.id, name = r.name, mass = r.mass, kills = r.kills, bot = r.bot, me = r.id == me })
	rows.sort_custom(func(a, b): return a.mass > b.mass if a.mass != b.mass else a.id < b.id)
	return rows


func my_mass() -> int:
	return runners[me].mass if runners.has(me) else 0


# --- The room ----------------------------------------------------------------------------

func _use_room(room: Node) -> void:
	if _room:
		_room.close()
		_room.queue_free()
	_room = room
	add_child(room)
	room.message.connect(_on_message)
	room.states.connect(_on_states)
	room.failed.connect(_on_failed)
	online = room.online


func _go_local() -> void:
	var room := ArenaRoom.new()
	room.bots = 5 if with_enemies else 0
	if round_time > 0.0:
		room.round_time = round_time
	_use_room(room)
	room.open(player_name)


## The server couldn't be reached, or dropped: on with a room of bots run here
func _on_failed() -> void:
	var was_in := me != 0
	for r in runners.values():
		if r.id != me and is_instance_valid(r.body):
			r.body.queue_free()
	runners.clear()
	me = 0
	phase = "connecting"
	_go_local()
	if was_in:
		status.emit("CONNECTION LOST", "playing on with bots")
	else:
		status.emit("OFFLINE", "couldn't reach the room: bots only")


func _on_message(m: Dictionary) -> void:
	match str(m.get("t")):
		"welcome":
			me = int(m.you)
			half = float(m.half)
			_build_course(m.blocks)
			_set_drops(m.drops)
			for e in m.ents:
				_add_runner(e)
			phase = str(m.phase)
			time_left = float(m.ends) / 1000.0
			smashes = 0
			if not runner.splatted.is_connected(_on_player_down):
				runner.splatted.connect(_on_player_down)
			var mine: Dictionary = runners[me]
			mine.safe = float(m.get("safe", 2500.0)) / 1000.0
			_respawn(mine)
			runner.set_physics_process(true)
			status.emit("ONLINE" if online else "ARENA", "grow  ·  dash  ·  burst")
		"ent":
			_add_runner(m)
			if not bool(m.bot):
				feed.emit("%s dropped in" % m.name)
		"gone":
			var r := _r(m.id)
			if not r.is_empty():
				if not r.bot:
					feed.emit("%s left" % r.name)
				if is_instance_valid(r.body) and r.id != me:
					r.body.queue_free()
				runners.erase(r.id)
		"bots":
			_take_bots(m.ids)
		"took":
			var r := _r(m.e)
			_remove_drop(int(m.d))
			if not r.is_empty():
				r.mass = int(m.m)
				_apply_mass(r)
				if r.mine and not r.body.dead:
					r.body.collect_drop()
		"drops":
			_add_drops(m.list)
		"kill":
			_on_kill(m)
		"alive":
			var r := _r(m.e)
			if not r.is_empty():
				r.alive = true
				r.mass = int(m.m)
				r.safe = 2.5
				if not r.mine:
					r.placed = false # (stood back up where its next state puts it)
				_apply_mass(r)
		"over":
			phase = "over"
			time_left = float(m.next) / 1000.0
			round_over.emit(m.top)
		"round":
			phase = "play"
			time_left = float(m.ends) / 1000.0
			smashes = 0
			_set_drops(m.drops)
			for e in m.ents:
				var r := _r(e.id)
				if r.is_empty():
					continue
				r.mass = int(e.mass)
				r.alive = true
				r.kills = 0
				r.safe = 2.5
				_apply_mass(r)
				if r.mine:
					_respawn(r)
				else:
					r.placed = false
			round_started.emit()


func _r(id: Variant) -> Dictionary:
	return runners.get(int(id), {})


func _add_runner(e: Dictionary) -> void:
	var id := int(e.id)
	if runners.has(id):
		return
	var r := { id = id, name = str(e.name), bot = bool(e.bot), mass = int(e.mass), alive = bool(e.alive), kills = int(e.get("kills", 0)),
		mine = id == me, body = null, tag = null, tint = TINTS[id % TINTS.size()], safe = 0.0, down = 0.0, placed = false, wait = 0.0, ask = 0.0 }
	runners[id] = r
	if id == me:
		r.body = runner
		r.placed = true
		runner.enter_brawl()
	else:
		_new_body(r, false)
	_apply_mass(r)


## A runner's body: one of this game's bots (a real runner with a bot at the controls), or a
## puppet of somebody else's
func _new_body(r: Dictionary, bot_here: bool) -> void:
	var input: Node
	if bot_here:
		var bot := BotInput.new()
		bot.arena = self
		bot.id = r.id
		input = bot
	else:
		input = AiInput.new() # (no body to drive: it does nothing)
	var body := Runner.new()
	body.input = input
	body.add_child(input)
	add_child(body)
	body.make_brawler(r.tint)
	if bot_here:
		input.body = body
		body.splatted.connect(_on_mine_down.bind(r.id))
	else:
		body.make_puppet()
		body.visible = false # till its first state says where it is
	var tag := Label3D.new()
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.font_size = 72
	tag.pixel_size = 0.0065
	tag.outline_size = 20
	tag.no_depth_test = true # (read through the blocks: you know who's coming)
	tag.modulate = (r.tint.horizon as Color).lerp(Color.WHITE, 0.6)
	tag.outline_modulate = Color(0.02, 0.01, 0.05, 0.9)
	tag.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_INHERIT
	body.add_child(tag)
	r.body = body
	r.tag = tag


## The room's bots are this game's to run now: their puppets become real runners
func _take_bots(ids: Array) -> void:
	for raw in ids:
		var r := _r(raw)
		if r.is_empty() or r.mine:
			continue
		var was: CharacterBody3D = r.body
		var had: bool = r.placed and not was.dead
		var spot := was.global_position
		var facing: float = was.heading
		was.queue_free()
		r.mine = true
		r.placed = true
		_new_body(r, true)
		_apply_mass(r)
		if had:
			r.body.revive(spot, facing)
		else:
			_respawn(r)


## One of this game's runners back on its feet, somewhere clear
func _respawn(r: Dictionary) -> void:
	var at := _spawn_spot()
	r.body.revive(at[0], at[1])
	r.down = 0.0
	r.ask = 0.0
	if r.id == me:
		player_placed.emit()


## Somewhere near a wall that's clear of things and of the other runners, facing in: [spot, heading]
func _spawn_spot() -> Array:
	var space := get_world_3d().direct_space_state
	var probe := SphereShape3D.new()
	probe.radius = 1.2
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = probe
	query.collision_mask = 1
	var spot := Vector3.ZERO
	for tries in 20:
		spot = Vector3(_rng.randf_range(-half + 8.0, half - 8.0), 0.0, _rng.randf_range(-half + 8.0, half - 8.0))
		var crowded := false
		for r in runners.values():
			if r.alive and is_instance_valid(r.body) and r.placed and r.body.global_position.distance_to(spot) < 14.0:
				crowded = true
		if crowded and tries < 14:
			continue
		query.transform = Transform3D(Basis.IDENTITY, spot + Vector3.UP * 1.5)
		if space.intersect_shape(query, 1).is_empty():
			break
	return [spot, atan2(spot.x, spot.z)] # (heading 0 runs toward -Z: this faces the middle)


func _on_player_down() -> void:
	_on_mine_down(me)


## One of this game's runners went down: into a wall (the room's told), or burst (it told us)
func _on_mine_down(id: int) -> void:
	var r := _r(id)
	if r.is_empty():
		return
	r.down = RESPAWN
	if r.alive and phase == "play":
		_room.send({ t = "died", e = id })


func _on_kill(m: Dictionary) -> void:
	_add_drops(m.drops)
	var a := _r(m.a)
	var v := _r(m.v)
	var gained := 0
	if not a.is_empty():
		gained = int(m.am) - int(a.mass)
		a.mass = int(m.am)
		a.kills += 1
		_apply_mass(a)
	if v.is_empty():
		return
	v.alive = false
	v.mass = 0
	if is_instance_valid(v.body) and not v.body.dead:
		var push: Vector3 = a.body.velocity if not a.is_empty() and is_instance_valid(a.body) else Vector3.ZERO
		v.body.blow_up(push)
	_apply_mass(v)
	if a.is_empty():
		feed.emit("%s hit a wall" % v.name)
		if v.id == me:
			status.emit("SPLAT", "lost %d" % int(m.lost))
		return
	feed.emit("%s burst %s" % [a.name, v.name])
	if a.id == me:
		smashes += 1
		status.emit("BURST!", "%s  +%d" % [v.name, gained])
	elif v.id == me:
		status.emit("BURST", "by %s" % a.name)


## The other games' runners: where each is and what it's doing
func _on_states(data: PackedByteArray) -> void:
	for at in range(1, data.size() - 10, 11):
		var r := _r(data[at])
		if r.is_empty() or r.mine or not r.alive:
			continue
		var body: CharacterBody3D = r.body
		if not r.placed or body.dead:
			var spot := Vector3(data.decode_s16(at + 2), data.decode_s16(at + 4), data.decode_s16(at + 6)) / 100.0
			body.revive(spot, data.decode_s16(at + 8) / 10000.0)
			body.visible = true
			r.placed = true
		body.net_apply(data, at)


# --- Each step: this game's runners claim drops and hits; states go out ------------------------

func _physics_process(delta: float) -> void:
	if me == 0:
		return
	time_left = maxf(time_left - delta, 0.0)
	for drop in drops.values():
		if drop.taken > 0.0:
			drop.taken -= delta
			if drop.taken <= 0.0:
				drop.view.visible = true # (the room never answered: it's still there)
	var out := PackedByteArray([K_STATE])
	for r in runners.values():
		r.safe = maxf(r.safe - delta, 0.0)
		r.wait = maxf(r.wait - delta, 0.0)
		if r.tag:
			r.tag.visible = r.alive and r.placed
			r.tag.modulate.a = 0.6 if r.safe > 0.0 else 1.0
		if not r.mine:
			continue
		var body: CharacterBody3D = r.body
		if body.dead:
			r.down -= delta
			if r.down <= 0.0:
				_respawn(r)
			continue
		out.append_array(body.net_state(r.id))
		if not r.alive:
			# Up again here: the room has to say so too before it counts
			r.ask -= delta
			if r.ask <= 0.0:
				r.ask = 1.0
				_room.send({ t = "spawn", e = r.id })
			continue
		if phase != "play":
			continue
		_try_drops(r)
		if r.safe <= 0.0 and r.wait <= 0.0:
			_try_hits(r)
	_send_clock -= delta
	if _send_clock <= 0.0 and out.size() > 1:
		_send_clock = SEND_EVERY
		_room.send_states(out)


func _try_drops(r: Dictionary) -> void:
	var here: Vector3 = r.body.global_position
	if here.y > 3.0:
		return
	var reach: float = 1.0 + 0.55 * r.body.size
	for id in drops:
		var drop: Dictionary = drops[id]
		if drop.taken > 0.0:
			continue
		var dx: float = drop.x - here.x
		var dz: float = drop.z - here.z
		if dx * dx + dz * dz < reach * reach:
			drop.taken = 1.0
			drop.view.visible = false
			_room.send({ t = "take", e = r.id, d = id })


## Touching another runner: slashing, it bursts (unless that one's slashing too and bigger); not
## slashing, it bursts only if it's a good deal smaller. The room decides whose claim came first.
func _try_hits(a: Dictionary) -> void:
	var here: Vector3 = a.body.global_position
	var armed: bool = a.body.armed()
	for b in runners.values():
		if b.id == a.id or not b.alive or b.safe > 0.0 or not b.placed or b.body.dead:
			continue
		var there: Vector3 = b.body.global_position
		if absf(there.y - here.y) > 1.8:
			continue
		var reach: float = 0.55 * (a.body.size + b.body.size) + 0.3
		if Vector2(there.x - here.x, there.z - here.z).length() > reach:
			continue
		var other_armed: bool = b.body.armed()
		var how := ""
		if armed and (not other_armed or a.mass >= b.mass):
			how = "dash"
		elif not armed and not other_armed and a.mass >= b.mass * EAT:
			how = "eat"
		if how != "":
			a.wait = 0.4
			_room.send({ t = "hit", a = a.id, v = b.id, how = how })
			return


## Bigger with its mass (and a touch slower), and its tag says how much
func _apply_mass(r: Dictionary) -> void:
	if not is_instance_valid(r.body):
		return
	var grown := 1.0 - exp(-maxf(r.mass - 10.0, 0.0) / 120.0)
	r.body.set_size(1.0 + 0.9 * grown)
	if r.mine:
		r.body.run_speed = BASE_SPEED * lerpf(1.0, 0.86, grown) * (0.94 if r.bot else 1.0)
	if r.id == me:
		peak = maxi(peak, r.mass)
	if r.tag:
		r.tag.text = "%s  %d" % [r.name, r.mass]
		r.tag.position.y = 2.05 * r.body.size + 0.2


# --- Drops ---------------------------------------------------------------------------------

func _set_drops(list: Array) -> void:
	for drop in drops.values():
		drop.view.queue_free()
	drops.clear()
	_add_drops(list)


## [[id, x, z, value], ...]
func _add_drops(list: Array) -> void:
	for entry in list:
		var id := int(entry[0])
		if drops.has(id):
			continue
		var value := int(entry[3])
		var view := MeshInstance3D.new()
		view.mesh = _drop_mesh
		view.scale = Vector3.ONE * (1.0 + 0.45 * log(float(value)) if value > 1 else 1.0)
		view.position = Vector3(float(entry[1]), 0.7, float(entry[2]))
		add_child(view)
		drops[id] = { view = view, x = float(entry[1]), z = float(entry[2]), v = value, taken = 0.0 }


func _remove_drop(id: int) -> void:
	if drops.has(id):
		drops[id].view.queue_free()
		drops.erase(id)


# --- Pieces ------------------------------------------------------------------------------

## The floor, the walls (tall, green, for running along), the room's blocks (cover) and slabs
## (to jump): [[x, z, width, height, depth, turn, kind], ...], and a boost pad toward each corner
func _build_course(blocks: Array) -> void:
	if _course:
		_course.free()
	_course = Node3D.new()
	add_child(_course)
	_build_floor()
	for side in [-1.0, 1.0]:
		_block(Vector3(half * 2.0 + 1.2, 8.0, 0.6), Vector3(0.0, 4.0, side * (half + 0.3)), WALL_COLOR)
		_block(Vector3(0.6, 8.0, half * 2.0 + 1.2), Vector3(side * (half + 0.3), 4.0, 0.0), WALL_COLOR)
	for b in blocks:
		var size := Vector3(float(b[2]), float(b[3]), float(b[4]))
		_block(size, Vector3(float(b[0]), size.y * 0.5, float(b[1])), SLAB_COLOR if int(b[6]) == 1 else BLOCK_COLOR, float(b[5]))
	for k in 4:
		var pad := BoostPad.new()
		var angle := k * TAU / 4.0 + PI / 4.0
		pad.position = Vector3(cos(angle), 0.0, sin(angle)) * half * 0.55
		pad.rotation.y = -angle + PI / 2.0 # (boosting round the arena)
		pad.collision_mask = 1 | 2 # (the room's runners are all on layer 2)
		_course.add_child(pad)


func _material(color: Color) -> ShaderMaterial:
	if not _materials.has(color):
		var material := ShaderMaterial.new()
		material.shader = preload("res://shaders/obstacle.gdshader")
		material.set_shader_parameter("edge_color", color)
		_materials[color] = material
	return _materials[color]


func _block(size: Vector3, center: Vector3, color: Color, yaw := 0.0) -> void:
	var body := StaticBody3D.new()
	body.position = center
	body.rotation.y = yaw
	var shape := BoxShape3D.new()
	shape.size = size
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	var mesh := BoxMesh.new()
	mesh.size = size
	var view := MeshInstance3D.new()
	view.mesh = mesh
	view.material_override = _material(color)
	body.add_child(view)
	_course.add_child(body)


func _build_floor() -> void:
	var body := StaticBody3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(half * 2.0 + 20.0, 2.0, half * 2.0 + 20.0)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position.y = -1.0
	body.add_child(collider)
	var plane := PlaneMesh.new()
	plane.size = Vector2(half * 2.0 + 20.0, half * 2.0 + 20.0)
	var view := MeshInstance3D.new()
	view.mesh = plane
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/grid_floor.gdshader")
	material.set_shader_parameter("line_color", Color(0.2, 1.0, 0.5))
	view.material_override = material
	body.add_child(view)
	_course.add_child(body)
