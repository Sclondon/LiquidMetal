extends Node3D
## Arena: an online battle room in the Crystaliens' colosseum (colosseum.gd: black sand, a round
## wall, a crowd of them in the stands). Everyone who opens it drops into the same room and
## fights for the most mass before the round's clock runs out. Run over drops of metal to grow;
## dash through another runner to burst it (or just run into one a good deal smaller than you);
## a burst runner spills most of its mass back onto the floor and comes back small. Bots fill the
## seats players haven't, so the room's never empty: they're Crystaliens (other players are Mercury,
## each in a colour of their own). Every round the room lays the arena out another way (its "mode"):
## open sand, blocks for cover, blocks that slide back and forth, or a pit in the middle.
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

const BLOCK_COLOR := Color(0.6, 0.35, 0.95)
const SLAB_COLOR := Color(1.0, 0.65, 0.25)
const MOVER_COLOR := Color(1.0, 0.35, 0.5)
const MODE_NAMES := { open = ["OPEN SAND", "nowhere to hide"], blocks = ["THE STONES", "use the cover"],
	movers = ["SLIDING STONES", "they don't stop for you"], pit = ["THE PIT", "mind the middle"] }
const Colosseum := preload("res://scripts/colosseum.gd")
const Crystal := preload("res://scripts/crystal.gd")
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

var half := 70.0 # metres from the middle to the round wall (the room's)
var mode := "" # this round's layout: "open" / "blocks" / "movers" / "pit"
var pit := 0.0 # the pit's radius (0: none)
var start_position := Vector3(0.0, 0.0, 30.0)
var start_heading := 0.0
var runner: CharacterBody3D # the player
var with_enemies := true # false: no bots (tests; only when the room's run here)
var lane_plan: Array = [] # (no lane here)
## The site's server ("https://..."); empty: the room's run here, with bots
var server := ""
var player_name := "RUNNER"
var round_time := 0.0 # a room run here: its rounds, in seconds (0: the usual)
var first_mode := "" # a room run here: its first layout ("": any)

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
var _colosseum: Node3D
var _movers: Array = [] # [{ body, home, travel, period, start }]
var _round_clock := 0.0 # seconds into the round (the sliding blocks are placed by it)
var _layout_from := 0.0 # seconds into the round this layout came in (its blocks slide from then)
var _coming := {} # a change of layout the room has warned of ("layout"), and
var _coming_in := 0.0 # the seconds left before it comes in
var _risen := 1.0 # 0..1: this layout's stones up out of the sand
var _leaving: Array = [] # the last layout's stones, going down: { node, sunk 0..1 }
var _pads_laid := false
var layout_time := 0.0 # a room run here: seconds between changes of layout (0: the usual)
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
	_colosseum = Colosseum.new()
	_colosseum.radius = half
	add_child(_colosseum)
	_colosseum.ground.focus = runner # (the sand keeps its marks round him)
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
	room.first_mode = first_mode
	if layout_time > 0.0:
		room.layout_time = layout_time
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
			_lay_out(m, false)
			_round_clock = float(m.get("at", 0.0)) / 1000.0
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
			status.emit(MODE_NAMES[mode][0], "ONLINE  ·  grow  ·  dash  ·  burst" if online else "grow  ·  dash  ·  burst")
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
		"mass":
			var r := _r(m.e)
			if not r.is_empty():
				r.mass = int(m.m)
				_apply_mass(r)
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
		"layout":
			# The arena's about to change: a warning (and where the pit will open), then it does
			_coming = m
			_coming_in = float(m.get("in", 3500.0)) / 1000.0
			var next := str(m.get("mode", "blocks"))
			status.emit(MODE_NAMES.get(next, MODE_NAMES.blocks)[0], "the arena's changing")
			_colosseum.warn_pit(float(m.get("pit", 0.0)))
			_colosseum.cheer(0.6)
		"over":
			phase = "over"
			time_left = float(m.next) / 1000.0
			_colosseum.cheer()
			round_over.emit(m.top)
		"round":
			phase = "play"
			time_left = float(m.ends) / 1000.0
			smashes = 0
			_lay_out(m)
			_round_clock = 0.0
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
	if r.bot:
		# A Crystalien: its crystal's colour
		var color: Color = Crystal.COLORS[id % Crystal.COLORS.size()]
		r.tint = { top = color.darkened(0.75), horizon = color, ground = color.darkened(0.9), glow = color, trail = color.lightened(0.3) }
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
	body.crystal = r.bot # (the bots are Crystaliens; other players are Mercury)
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


## Somewhere on the sand that's clear of things and of the other runners, facing in: [spot, heading]
func _spawn_spot() -> Array:
	var space := get_world_3d().direct_space_state
	var probe := SphereShape3D.new()
	probe.radius = 1.2
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = probe
	query.collision_mask = 1
	var spot := Vector3.ZERO
	for tries in 20:
		var out := lerpf(maxf(pit + 10.0, half * 0.35), half - 8.0, sqrt(_rng.randf()))
		var angle := _rng.randf() * TAU
		spot = Vector3(cos(angle) * out, 0.0, sin(angle) * out)
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
		_room.send({ t = "died", e = id, how = "pit" if r.body.global_position.y < -1.5 else "wall" })


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
		var fell: bool = m.get("how") == "pit"
		if fell:
			_colosseum.gasp()
		feed.emit("%s fell in the pit" % v.name if fell else "%s hit a wall" % v.name)
		if v.id == me:
			status.emit("GONE" if fell else "SPLAT", "lost %d" % int(m.lost))
		return
	feed.emit("%s ran into %s's wall" % [v.name, a.name] if m.get("how") == "trail" else "%s burst %s" % [a.name, v.name])
	# The crowd: up on its feet, a wave round from where it happened, lit in the winner's colour
	# (louder the more mass went)
	_colosseum.cheer(clampf(0.55 + float(m.lost) / 120.0, 0.55, 1.0))
	if is_instance_valid(v.body):
		_colosseum.wave(v.body.global_position)
	_colosseum.flash(Color(0.85, 0.92, 1.0) if a.id == me or not a.bot else a.tint.horizon)
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
	if phase == "play":
		_round_clock += delta
	if not _coming.is_empty():
		_coming_in -= delta
		if _coming_in <= 0.0:
			var change := _coming
			_coming = {}
			_lay_out(change)
			_set_drops(change.drops)
	_risen = minf(_risen + delta / 1.1, 1.0)
	for i in range(_leaving.size() - 1, -1, -1):
		var going: Dictionary = _leaving[i]
		going.sunk = minf(going.sunk + delta / 1.0, 1.0)
		(going.node as Node3D).position.y = -smoothstep(0.0, 1.0, float(going.sunk)) * 7.0
		if going.sunk >= 1.0:
			going.node.queue_free()
			_leaving.remove_at(i)
	var sunk := (1.0 - smoothstep(0.0, 1.0, _risen)) * 6.5
	for stone in _course.get_children():
		if stone is StaticBody3D:
			stone.position.y = float(stone.get_meta("y", stone.position.y)) - sunk
	for mover in _movers:
		var swing := sin(TAU * (maxf(_round_clock - _layout_from, 0.0) / float(mover.period) + float(mover.start)))
		mover.body.position = mover.home + mover.travel * swing + Vector3.DOWN * sunk
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
		if not body.dead and body.global_position.y < -3.0:
			body._splat() # down the pit
		if body.dead:
			r.down -= delta
			if r.down <= 0.0:
				_respawn(r)
			continue
		out.append_array(body.net_state(r.id))
		if body.is_on_floor():
			_colosseum.ground.trail(r.id, body.global_position, 0.32 * body.size, 0.05) # a furrow in the sand
		if not r.alive:
			# Up again here: the room has to say so too before it counts
			r.ask -= delta
			if r.ask <= 0.0:
				r.ask = 1.0
				_room.send({ t = "spawn", e = r.id })
			continue
		if phase != "play":
			continue
		# A dash is paid for in mass (the room takes it)
		var dashing: bool = body.is_dashing()
		if dashing and not r.get("dashing", false):
			_room.send({ t = "dash", e = r.id })
		r.dashing = dashing
		_try_drops(r)
		if r.safe <= 0.0 and r.wait <= 0.0:
			_try_hits(r)
		if r.safe <= 0.0 and r.wait <= 0.0:
			# Run into the wall somebody else's dash left: burst, and theirs the credit
			for other in runners.values():
				if other.id != r.id and is_instance_valid(other.body) and other.body.wall_hits(body.global_position + Vector3.UP * 0.5, 0.45 * body.size):
					r.wait = 0.6
					_room.send({ t = "died", e = r.id, how = "trail", by = other.id })
					break
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
	r.body.set_size(1.0 + 3.0 * grown) # (10: his own size; 100: twice it; a few hundred: a giant)
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

## What's in the arena this round, as the room laid it out (m: its welcome or round message):
## the floor (with the pit, if there is one), the blocks (cover) and slabs (to jump)
## [[x, z, width, height, depth, turn, kind], ...], the sliding blocks [[x, z, width, height,
## depth, turn, travel x, travel z, seconds there and back, start 0..1], ...], and four boost pads
func _lay_out(m: Dictionary, rise := true) -> void:
	if _course:
		# What was there goes down into the sand (and is gone once it's under)
		_leaving.append({ node = _course, sunk = 0.0 })
	_course = Node3D.new()
	add_child(_course)
	_movers.clear()
	_coming = {}
	_risen = 0.0 if rise else 1.0 # (and what's coming, comes up out of it)
	_layout_from = float(m.get("t0", 0.0)) / 1000.0
	mode = str(m.get("mode", "blocks"))
	if not MODE_NAMES.has(mode):
		mode = "blocks"
	pit = float(m.get("pit", 0.0))
	half = float(m.get("radius", m.get("half", half)))
	_colosseum.set_floor(pit)
	for b in m.get("blocks", []):
		var size := Vector3(float(b[2]), float(b[3]), float(b[4]))
		_block(size, Vector3(float(b[0]), size.y * 0.5, float(b[1])), SLAB_COLOR if int(b[6]) == 1 else BLOCK_COLOR, float(b[5]))
	for b in m.get("movers", []):
		var size := Vector3(float(b[2]), float(b[3]), float(b[4]))
		var home := Vector3(float(b[0]), size.y * 0.5, float(b[1]))
		var body := _block(size, home, MOVER_COLOR, float(b[5]), true)
		_movers.append({ body = body, home = home, travel = Vector3(float(b[6]), 0.0, float(b[7])), period = maxf(float(b[8]), 1.0), start = float(b[9]) })
	if _pads_laid:
		return
	_pads_laid = true # (the boosts stay where they are through every layout)
	for k in 4:
		var pad := BoostPad.new()
		var angle := k * TAU / 4.0 + PI / 4.0
		pad.position = Vector3(cos(angle), 0.0, sin(angle)) * half * 0.55
		pad.rotation.y = -angle + PI / 2.0 # (boosting round the arena)
		pad.collision_mask = 1 | 2 # (the room's runners are all on layer 2)
		# (used, it's gone, and opens again somewhere else round the arena)
		pad.respawn = func(ring: Node3D):
			var at := randf() * TAU
			ring.position = Vector3(cos(at), 0.0, sin(at)) * half * randf_range(0.4, 0.7)
			ring.rotation.y = -at + PI / 2.0
		add_child(pad)


func _material(color: Color) -> ShaderMaterial:
	if not _materials.has(color):
		var material := ShaderMaterial.new()
		material.shader = preload("res://shaders/obstacle.gdshader")
		material.set_shader_parameter("edge_color", color)
		_materials[color] = material
	return _materials[color]


## A stone in the arena: a box to run into (or jump, if it's low), drawn as a stand of crystals
## that fills it: tall ones side by side for a block, a low jagged ridge for a slab (no higher
## than it can be jumped)
func _block(size: Vector3, center: Vector3, color: Color, yaw := 0.0, moving := false) -> PhysicsBody3D:
	var body: PhysicsBody3D = AnimatableBody3D.new() if moving else StaticBody3D.new()
	body.position = center
	body.rotation.y = yaw
	var shape := BoxShape3D.new()
	shape.size = size
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	var low := size.y < 1.0
	var growth := SurfaceTool.new()
	growth.begin(Mesh.PRIMITIVE_TRIANGLES)
	growth.set_smooth_group(-1)
	# Along its longer side, a crystal every so often, each about as thick as the box is deep
	var long_x := size.x >= size.z
	var length := maxf(size.x, size.z)
	var depth := minf(size.x, size.z)
	var count := maxi(2, roundi(length / maxf(depth * 0.8, 0.9)))
	for k in count:
		var along := (float(k) + 0.5) / count - 0.5 + _rng.randf_range(-0.12, 0.12) / count
		var spot := Vector3(along * length, 0.0, _rng.randf_range(-0.1, 0.1) * depth) if long_x else Vector3(_rng.randf_range(-0.1, 0.1) * depth, 0.0, along * length)
		var lean := Basis(Vector3.UP, _rng.randf() * TAU) * Basis(Vector3.RIGHT, _rng.randf_range(-0.14, 0.14))
		var thick := depth * _rng.randf_range(0.5, 0.62)
		if low:
			# Squat, pointed, the tips just over the top of the box
			var tall := size.y * _rng.randf_range(1.5, 2.1)
			Crystal.add_shard(growth, Transform3D(lean, spot + Vector3.UP * (size.y * 0.5 - tall * 0.34)), thick, thick, tall, 0.25)
		else:
			# Standing from the ground to about the top of the box (a point above it, a point buried)
			var tall := size.y * _rng.randf_range(1.05, 1.3)
			Crystal.add_shard(growth, Transform3D(lean, spot + Vector3.UP * (tall * 0.36 - size.y * 0.5)), thick, thick, tall * 1.25, 0.55)
			# ...and a smaller one or two grown against its foot
			for extra in _rng.randi_range(0, 2):
				var beside := spot + Vector3(_rng.randf_range(-0.5, 0.5), 0.0, _rng.randf_range(-0.5, 0.5)).normalized() * thick * 0.9
				var small := size.y * _rng.randf_range(0.3, 0.55)
				var out := Basis(Vector3.UP, _rng.randf() * TAU) * Basis(Vector3.RIGHT, _rng.randf_range(0.2, 0.5))
				Crystal.add_shard(growth, Transform3D(out, beside + Vector3.UP * (small * 0.3 - size.y * 0.5)), thick * 0.35, thick * 0.35, small, 0.4)
	growth.generate_normals()
	var shards := MeshInstance3D.new()
	shards.mesh = growth.commit()
	shards.material_override = _material(color)
	body.add_child(shards)
	body.set_meta("y", center.y) # (where it stands once it's risen)
	_course.add_child(body)
	return body


func _crystal_material(color: Color) -> ShaderMaterial:
	var key := "crystal %s" % color
	if not _materials.has(key):
		var material := ShaderMaterial.new()
		material.shader = preload("res://shaders/crystal.gdshader")
		material.set_shader_parameter("horizon", color)
		material.set_shader_parameter("sky_top", color.darkened(0.7))
		_materials[key] = material
	return _materials[key]
