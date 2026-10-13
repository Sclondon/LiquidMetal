extends SceneTree
## Two copies of the game in the same battle room on a local server (tools/arena_net_test.sh
## starts the server and both copies). Copy "a" is in first, so it runs the bots; copy "b" drops
## in after. Each checks it sees the other and the bots moving; a runs over to b and dashes
## through it, and both agree on what happened; then a leaves and b takes the bots over.
## Run by hand: godot --headless --path . -s res://tests/arena_net_test.gd -- --server=http://127.0.0.1:3112 --role=a

const Flags := preload("res://scripts/flags.gd")

var main: Node
var role := "a"
var t := 0.0
var total := 0.0
var log := []
var step := 0
var other := {}
var seen_at := Vector3.ZERO
var before := 0
var burst := false


func _initialize() -> void:
	role = Flags.value("role", "a")
	main = load("res://scenes/main.tscn").instantiate()
	main.start_mode = "arena"
	main.use_pads = false
	root.add_child(main)


func _check(name: String, ok: bool) -> void:
	log.append("%s [%s] %s" % ["PASS" if ok else "FAIL", role, name])


func _other_player(arena: Node) -> Dictionary:
	for r in arena.runners.values():
		if not r.bot and r.id != arena.me:
			return r
	return {}


func _process(delta: float) -> bool:
	t += delta
	total += delta
	var p: CharacterBody3D = main.player
	var arena: Node = main.area
	if arena.me != 0:
		p.run_speed = 0.0 # both stand where they came in; a is moved by the test
	match step:
		0:
			other = _other_player(arena) if arena.me != 0 else {}
			if not other.is_empty() and other.placed:
				var bots: Array = arena.runners.values().filter(func(r): return r.bot)
				_check("online, in a room with the other player and %d bots (%s)" % [bots.size(), "mine" if role == "a" else "puppets"],
					arena.online and bots.size() == 4 and bots.all(func(r): return r.mine == (role == "a")))
				seen_at = bots[0].body.global_position
				arena.status.connect(func(text: String, _sub: String):
					if text == "BURST":
						burst = true)
				step = 1
				t = 0.0
		1:
			if t > 3.0:
				var bots: Array = arena.runners.values().filter(func(r): return r.bot)
				var moved: float = bots[0].body.global_position.distance_to(seen_at)
				_check("the bots are on the move here (%.0f m in 3 s) and the other player is where they stood (%.1f m off the floor)" % [moved, other.body.global_position.y],
					moved > 5.0 and other.body.visible and absf(other.body.global_position.y) < 0.5)
				before = arena.my_mass()
				step = 2
				t = 0.0
		2:
			if role == "a":
				# Over to b, and a slash through it (again, if the first is too soon after it came in)
				if other.alive and not other.body.dead:
					p.global_position = other.body.global_position + p.forward() * 1.0
					if p.dash_cooldown <= 0.0 and not p.armed():
						p.input.dash.emit()
				if not other.alive:
					_check("a dashes through b: a's mass %d -> %d" % [before, arena.my_mass()], arena.my_mass() > before and arena.smashes == 1)
					step = 3
					t = 0.0
			elif burst:
				_check("b is burst by a (mass %d, down %s)" % [arena.my_mass(), p.dead], p.dead and arena.my_mass() == 0)
				step = 3
				t = 0.0
			if t > 12.0:
				_check("a dashes through b", false)
				step = 3
		3:
			if role == "a" and other.alive and other.mass == 10 and other.placed and not other.body.dead:
				_check("a sees b come back small", true)
				return _done() # a leaves; b takes the bots over
			if role == "b" and not p.dead and arena.runners[arena.me].alive:
				_check("b comes back small (mass %d)" % arena.my_mass(), arena.my_mass() == 10)
				step = 4
				t = 0.0
			if t > 10.0:
				_check("b comes back", false)
				step = 4 if role == "b" else 9
		4:
			# (b) a has gone: its runner too, and the bots are b's now, five of them
			var bots: Array = arena.runners.values().filter(func(r): return r.bot)
			if _other_player(arena).is_empty() and bots.size() == 5 and bots.all(func(r): return r.mine):
				_check("a leaves; b runs the bots now (%d)" % bots.size(), arena.online)
				return _done()
			if t > 10.0:
				_check("a leaves; b runs the bots now", false)
				return _done()
	if step == 9 or total > 50.0:
		log.append("FAIL [%s] stuck at step %d (me %d, online %s, runners %d)" % [role, step, arena.me, arena.online, arena.runners.size()])
		return _done()
	return false


func _done() -> bool:
	for line in log:
		print(line)
	return true
