extends Node
## The arena's battle room without a server: the same room the site's server keeps
## (server/liquidMetal/arena.js in scareathon-v3), run here in the game for one player and bots.
## It's what the arena falls back to when the server can't be reached, and what the tests play.
## It speaks the server's messages (see arena_net.gd), so arena.gd doesn't know the difference.
## Keep the rules here and in arena.js the same.

signal message(m: Dictionary)
signal states(data: PackedByteArray) # (never: nobody else is here)
signal failed

const HALF := 70.0
const START_MASS := 10
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

var _ents := {} # id -> { id, name, bot, mass, alive, kills, x, z, safe_until, died_at }
var _drops := {} # id -> [x, z, value]
var _blocks: Array = []
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
	while _blocks.size() < 26:
		var x := snappedf(_rng.randf_range(-HALF + 9.0, HALF - 9.0), 0.01)
		var z := snappedf(_rng.randf_range(-HALF + 9.0, HALF - 9.0), 0.01)
		if _blocks.any(func(b): return Vector2(b[0] - x, b[1] - z).length() < 11.0):
			continue
		if _blocks.size() % 2 == 0:
			_blocks.append([x, z, _rng.randf_range(2.0, 5.0), _rng.randf_range(2.5, 5.0), _rng.randf_range(2.0, 5.0), _rng.randf_range(0.0, PI), 0])
		else:
			_blocks.append([x, z, _rng.randf_range(4.0, 8.0), 0.7, _rng.randf_range(1.0, 2.0), _rng.randf_range(0.0, PI), 1])
	for i in DROPS:
		_scatter_drop()
	_add_ent(player_name, false)
	var bot_ids := []
	for i in bots:
		bot_ids.append(_add_ent(BOT_NAMES[i % BOT_NAMES.size()], true).id)
	_out.append({ t = "welcome", you = 1, half = HALF, blocks = _blocks, drops = _drop_list(), ents = _ents.values().map(_describe),
		phase = _phase, ends = round_time * 1000.0, safe = SAFE * 1000.0 })
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
			_kill(ent, {}, "wall")
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
			# A new round: everyone back to the start, the floor relaid
			_phase = "play"
			_until = _clock + round_time
			_drops.clear()
			for i in DROPS:
				_scatter_drop()
			for ent in _ents.values():
				ent.mass = START_MASS
				ent.alive = true
				ent.kills = 0
				ent.safe_until = _clock + SAFE
			_out.append({ t = "round", ends = round_time * 1000.0, drops = _drop_list(), ents = _ents.values().map(_describe) })
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


func _in_block(x: float, z: float) -> bool:
	return _blocks.any(func(b): return Vector2(b[0] - x, b[1] - z).length() < maxf(b[2], b[4]) * 0.75 + 1.2)


func _add_drop(x: float, z: float, value: int) -> Array:
	var id := _next_drop
	_next_drop += 1
	_drops[id] = [x, z, value]
	return [id, x, z, value]


func _scatter_drop() -> Array:
	for tries in 8:
		var x := _rng.randf_range(-HALF + 3.0, HALF - 3.0)
		var z := _rng.randf_range(-HALF + 3.0, HALF - 3.0)
		if not _in_block(x, z):
			return _add_drop(x, z, 1)
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
		var x := clampf(victim.x + cos(angle) * reach, -HALF + 2.0, HALF - 2.0)
		var z := clampf(victim.z + sin(angle) * reach, -HALF + 2.0, HALF - 2.0)
		if _in_block(x, z):
			x = victim.x # (it got there, so a drop there can be reached)
			z = victim.z
		spilled.append(_add_drop(x, z, value))
	if not by.is_empty():
		by.mass += KILL_BONUS + int(lost * KILL_SHARE)
		by.kills += 1
	_out.append({ t = "kill", a = by.get("id", 0), v = victim.id, am = by.get("mass", 0), how = how, lost = lost, drops = spilled })
