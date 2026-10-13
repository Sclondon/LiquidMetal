extends Node
## The arena's battle room without a server: the same room the site's server keeps
## (server/liquidMetal/arena.js in scareathon-v3), run here in the game for one player and bots.
## It's what the arena falls back to when the server can't be reached, and what the tests play.
## It speaks the server's messages (see arena_net.gd), so arena.gd doesn't know the difference.
## Keep the rules here and in arena.js the same.

signal message(m: Dictionary)
signal states(data: PackedByteArray) # (never: nobody else is here)
signal failed

const RADIUS := 70.0
const MODES := ["open", "blocks", "movers", "pit"]
const PIT_RADIUS := 14.0
const LAYOUT_TIME := 45.0 # seconds between changes of layout while a round's on
const WARN_TIME := 3.5 # how long the games are told before one comes in
const START_MASS := 10
const DASH_COST := 0.08 # of a runner's mass, gone each time it dashes (at least 1)...
const DASH_FLOOR := 5 # ...but a dash never takes it below this
const SAFE := 2.5
const DROPS := 110
const OVER_TIME := 9.0
const KILL_BONUS := 5
const KILL_SHARE := 0.25
const SPILL_SHARE := 0.6
const DEAD_TIME := 1.5
const BOT_NAMES := ["GALLIUM", "COBALT", "TUNGSTEN", "OSMIUM", "BISMUTH", "IRIDIUM", "NICKEL", "ZINC"]

var online := false
## How many bots share the room (0: an empty room, for tests)
var bots := 5
var round_time := 180.0
## The first round's layout ("": any)
var first_mode := ""

var _ents := {} # id -> { id, name, bot, mass, alive, kills, x, z, safe_until, died_at }
var _drops := {} # id -> [x, z, value]
var _blocks: Array = []
var _movers: Array = []
var _pit := 0.0
var _mode := ""
var _next_layout := 0.0
var _layout_from := 0.0 # seconds into the round the layout came in (its sliding blocks count from it)
## How often the layout changes in a round, seconds (a test may shorten it)
var layout_time := LAYOUT_TIME
var _next_drop := 1
var _phase := "play"
var _until := 0.0
var _clock := 0.0
var _tick := 0.0
var _out: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()


func open(player_name: String) -> void:
	_rng.randomize()
	_until = round_time
	_next_layout = layout_time
	_lay_out(first_mode if first_mode != "" else MODES[_rng.randi() % MODES.size()])
	_lay_drops()
	_add_ent(player_name, false)
	var bot_ids := []
	for i in bots:
		bot_ids.append(_add_ent(BOT_NAMES[i % BOT_NAMES.size()], true).id)
	var welcome := { t = "welcome", you = 1, drops = _drop_list(), ents = _ents.values().map(_describe),
		phase = _phase, ends = round_time * 1000.0, at = 0.0, safe = SAFE * 1000.0 }
	welcome.merge(_layout())
	_out.append(welcome)
	_out.append({ t = "bots", ids = bot_ids })


func close() -> void:
	set_process(false)


func send(m: Dictionary) -> void:
	match str(m.get("t")):
		"take":
			var ent: Dictionary = _ents.get(int(m.e), {})
			if ent.is_empty() or not ent.alive or not _drops.has(int(m.d)) or _phase != "play":
				return
			ent.mass += int(_drops[int(m.d)][2])
			_drops.erase(int(m.d))
			_out.append({ t = "took", e = ent.id, d = int(m.d), m = ent.mass })
		"dash": # (a dash is paid for in mass)
			var ent: Dictionary = _ents.get(int(m.e), {})
			if ent.is_empty() or not ent.alive or _phase != "play" or ent.mass <= DASH_FLOOR:
				return
			ent.mass = maxi(ent.mass - maxi(int(ent.mass * DASH_COST), 1), DASH_FLOOR)
			_out.append({ t = "mass", e = ent.id, m = ent.mass })
		"hit":
			var a: Dictionary = _ents.get(int(m.a), {})
			var v: Dictionary = _ents.get(int(m.v), {})
			if a.is_empty() or v.is_empty() or a.id == v.id or not a.alive or not v.alive or _phase != "play":
				return
			if _clock < a.safe_until or _clock < v.safe_until:
				return
			_kill(v, a, "eat" if m.get("how") == "eat" else "dash")
		"died":
			var ent: Dictionary = _ents.get(int(m.e), {})
			if ent.is_empty() or not ent.alive or _phase != "play":
				return
			# (into the wall somebody's dash left: theirs the credit)
			var by: Dictionary = _ents.get(int(m.get("by", 0)), {}) if m.get("how") == "trail" else {}
			if not by.is_empty() and by.alive and by.id != ent.id:
				if _clock >= ent.safe_until:
					_kill(ent, by, "trail")
				return
			_kill(ent, {}, "pit" if m.get("how") == "pit" else "wall")
		"spawn":
			var ent: Dictionary = _ents.get(int(m.e), {})
			if ent.is_empty() or ent.alive or _clock - ent.died_at < DEAD_TIME:
				return
			ent.alive = true
			ent.mass = START_MASS
			ent.safe_until = _clock + SAFE
			_out.append({ t = "alive", e = ent.id, m = ent.mass })


## Where the runners are (for where a burst one's drops land)
func send_states(data: PackedByteArray) -> void:
	for at in range(1, data.size(), 11):
		var ent: Dictionary = _ents.get(data[at], {})
		if not ent.is_empty():
			ent.x = data.decode_s16(at + 2) / 100.0
			ent.z = data.decode_s16(at + 6) / 100.0


func _process(delta: float) -> void:
	_clock += delta
	_tick += delta
	if _tick >= 0.25:
		_tick = 0.0
		if _phase == "play" and _clock >= _next_layout and _until - _clock > 20.0:
			# The arena changes under them: a warning now, the new layout in a moment
			_next_layout = _clock + layout_time
			var modes := MODES.filter(func(mode): return mode != _mode)
			_lay_out(modes[_rng.randi() % modes.size()])
			_layout_from = _clock - (_until - round_time) + WARN_TIME
			for id in _drops.keys():
				if _in_block(_drops[id][0], _drops[id][1]):
					_drops.erase(id) # (a stone or the pit is coming where it lay)
			_ring_pit_drops()
			var change := { t = "layout", drops = _drop_list() }
			change.merge(_layout())
			change["in"] = WARN_TIME * 1000.0
			_out.append(change)
		if _phase == "play":
			if _clock >= _until:
				_phase = "over"
				_until = _clock + OVER_TIME
				var top := _ents.values().map(_describe)
				top.sort_custom(func(a, b): return a.mass > b.mass)
				_out.append({ t = "over", top = top, next = OVER_TIME * 1000.0 })
			else:
				var fresh := []
				for i in 4:
					if _drops.size() < DROPS:
						var drop := _scatter_drop()
						if not drop.is_empty():
							fresh.append(drop)
				if not fresh.is_empty():
					_out.append({ t = "drops", list = fresh })
		elif _clock >= _until:
			# A new round: everyone back to the start, and the arena laid out another way
			_phase = "play"
			_until = _clock + round_time
			_next_layout = _clock + layout_time
			_layout_from = 0.0
			var others := MODES.filter(func(mode): return mode != _mode)
			_lay_out(others[_rng.randi() % others.size()])
			_lay_drops()
			for ent in _ents.values():
				ent.mass = START_MASS
				ent.alive = true
				ent.kills = 0
				ent.safe_until = _clock + SAFE
			var round := { t = "round", ends = round_time * 1000.0, drops = _drop_list(), ents = _ents.values().map(_describe) }
			round.merge(_layout())
			_out.append(round)
	# What it has to say, in order (never from inside send(): the arena's in the middle of a step)
	while not _out.is_empty():
		message.emit(_out.pop_front())


func _add_ent(ent_name: String, bot: bool) -> Dictionary:
	var id := _ents.size() + 1
	_ents[id] = { id = id, name = ent_name, bot = bot, mass = START_MASS, alive = true, kills = 0, x = 0.0, z = 0.0, safe_until = _clock + SAFE, died_at = 0.0 }
	return _ents[id]


func _describe(ent: Dictionary) -> Dictionary:
	return { id = ent.id, name = ent.name, bot = ent.bot, mass = ent.mass, alive = ent.alive, kills = ent.kills }


func _drop_list() -> Array:
	var list := []
	for id in _drops:
		list.append([id, _drops[id][0], _drops[id][1], _drops[id][2]])
	return list


## Somewhere on the floor at least `margin` in from the wall (and clear of the pit)
func _spot(margin: float) -> Vector2:
	for tries in 40:
		var reach := sqrt(_rng.randf()) * (RADIUS - margin)
		if reach > _pit + 3.0 or _pit == 0.0:
			return Vector2.from_angle(_rng.randf() * TAU) * reach
	return Vector2(RADIUS * 0.5, 0.0)


## A round's layout, by its mode (see layOut in arena.js: blocks, movers and the pit)
func _lay_out(mode: String) -> void:
	_mode = mode
	_blocks = []
	_movers = []
	_pit = PIT_RADIUS if mode == "pit" else 0.0
	var blocks: int = { open = 0, blocks = 26, movers = 8, pit = 14 }[mode]
	var tries := 0
	while _blocks.size() < blocks and tries < 2000:
		tries += 1
		var at := _spot(9.0)
		if _blocks.any(func(b): return Vector2(b[0] - at.x, b[1] - at.y).length() < 11.0):
			continue
		if _blocks.size() % 2 == 0:
			_blocks.append([at.x, at.y, _rng.randf_range(2.0, 5.0), _rng.randf_range(2.5, 5.0), _rng.randf_range(2.0, 5.0), _rng.randf_range(0.0, PI), 0])
		else:
			_blocks.append([at.x, at.y, _rng.randf_range(4.0, 8.0), 0.7, _rng.randf_range(1.0, 2.0), _rng.randf_range(0.0, PI), 1])
	if mode == "movers":
		for i in 9:
			var middle := Vector2.from_angle(i / 9.0 * TAU + _rng.randf_range(-0.2, 0.2)) * _rng.randf_range(0.25, 0.7) * RADIUS
			var along := _rng.randf_range(0.0, PI)
			var travel := Vector2.from_angle(along) * _rng.randf_range(9.0, 16.0)
			_movers.append([middle.x, middle.y, _rng.randf_range(5.0, 9.0), _rng.randf_range(3.0, 4.5), _rng.randf_range(1.5, 2.5),
				PI / 2.0 - along, travel.x, travel.y, _rng.randf_range(5.0, 9.0), _rng.randf()])


func _layout() -> Dictionary:
	return { mode = _mode, radius = RADIUS, blocks = _blocks, movers = _movers, pit = _pit, t0 = _layout_from * 1000.0 }


## A round's drops: scattered, and round a pit a ring of fat ones on its lip
func _lay_drops() -> void:
	_drops.clear()
	for i in DROPS:
		_scatter_drop()
	_ring_pit_drops()


func _ring_pit_drops() -> void:
	if _pit > 0.0:
		for i in 12:
			var at := Vector2.from_angle(i / 12.0 * TAU) * (_pit + 2.6)
			_add_drop(at.x, at.y, 3)


func _in_block(x: float, z: float) -> bool:
	if Vector2(x, z).length() < _pit + 2.5:
		return true
	return _blocks.any(func(b): return Vector2(b[0] - x, b[1] - z).length() < maxf(b[2], b[4]) * 0.75 + 1.2)


func _add_drop(x: float, z: float, value: int) -> Array:
	var id := _next_drop
	_next_drop += 1
	_drops[id] = [x, z, value]
	return [id, x, z, value]


func _scatter_drop() -> Array:
	for tries in 8:
		var at := _spot(3.0)
		if not _in_block(at.x, at.y):
			return _add_drop(at.x, at.y, 1)
	return []


## Burst: most of its mass back on the floor round where it was, some to whoever did it
func _kill(victim: Dictionary, by: Dictionary, how: String) -> void:
	var lost: int = victim.mass
	victim.alive = false
	victim.mass = 0
	victim.died_at = _clock
	var spill := maxi(3, int(lost * SPILL_SHARE))
	var pieces := clampi(ceili(spill / 6.0), 3, 14)
	var spilled := []
	var left := spill
	for i in pieces:
		var value := left if i == pieces - 1 else maxi(1, roundi(float(spill) / pieces))
		if value <= 0:
			break
		left -= value
		var angle := _rng.randf() * TAU
		var reach := _rng.randf_range(1.5, 5.0)
		var at := (Vector2(victim.x, victim.z) + Vector2.from_angle(angle) * reach).limit_length(RADIUS - 2.0)
		if _in_block(at.x, at.y):
			at = Vector2(victim.x, victim.z) # (it got there, so a drop there can be reached)
		if at.length() < _pit + 2.5:
			# Lost down the pit: its drops land on the lip, out the way it came
			at = Vector2.from_angle(atan2(victim.z, victim.x) + _rng.randf_range(-0.5, 0.5)) * (_pit + _rng.randf_range(2.6, 5.0))
		spilled.append(_add_drop(at.x, at.y, value))
	if not by.is_empty():
		by.mass += KILL_BONUS + int(lost * KILL_SHARE)
		by.kills += 1
	_out.append({ t = "kill", a = by.get("id", 0), v = victim.id, am = by.get("mass", 0), how = how, lost = lost, drops = spilled })
