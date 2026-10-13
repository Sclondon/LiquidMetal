extends "res://scripts/ai_input.gd"
## A bot in the arena's battle room: the enemy AI's controls (and its rays for jumping, sliding
## under and swerving round things), with a mind for the room instead of one target. A few times
## a second it picks what to do: get away from a bigger runner that's close, go for one it can
## burst (and dash when it's lined up with a clear run), or else head for the nearest drops.

const HUNT_RANGE := 16.0
const FLEE_RANGE := 11.0
const DASH_RANGE := 9.0
const EAT := 1.3 # (the arena's: this much bigger and it bursts you just by running into you)

var arena: Node # arena.gd: runners, drops, half
var id := 0

var _think := 0.0
var _aim := Vector3.ZERO
var _prey := 0 # the runner it's after (0: none)
var _rest := 0.0 # seconds before it'll slash again (it isn't relentless)


func _physics_process(delta: float) -> void:
	if body == null or body.dead or arena == null:
		turn = 0.0
		return
	_hold_line = maxf(_hold_line - delta, 0.0)
	_swerve = move_toward(_swerve, 0.0, delta * 1.5)
	_feel_ahead(delta)
	_rest = maxf(_rest - delta, 0.0)
	_think -= delta
	if _think <= 0.0:
		_think = randf_range(0.25, 0.45)
		_choose()

	var here: Vector3 = body.global_position
	var aim := _aim
	var prey: Dictionary = arena.runners.get(_prey, {})
	if not prey.is_empty() and prey.alive and is_instance_valid(prey.body):
		aim = prey.body.global_position + prey.body.forward() * 2.0
	else:
		_prey = 0
	# Near a wall: back toward the middle
	var edge: float = arena.half - 10.0
	if absf(here.x) > edge or absf(here.z) > edge:
		aim = aim.lerp(Vector3.ZERO, 0.75)
		_prey = 0
	var to_aim := aim - here
	var off := wrapf(atan2(-to_aim.x, -to_aim.z) - body.heading, -PI, PI)
	var steer := clampf(-off * 2.2, -1.0, 1.0)
	if _hold_line > 0.0:
		steer *= 0.2
	turn = clampf(steer + _swerve, -1.0, 1.0)
	# Lined up on it, close, nothing in the way: slash
	if _prey != 0 and _rest <= 0.0 and body.dash_cooldown <= 0.0 and absf(off) < 0.22 and to_aim.length() < DASH_RANGE and absf(_swerve) < 0.1:
		var space := body.get_world_3d().direct_space_state
		if _ray(space, here + Vector3.UP * 1.0, body.forward() * 18.0) == INF:
			dash.emit()
			_rest = randf_range(2.0, 4.0)


func _choose() -> void:
	var mine: Dictionary = arena.runners.get(id, {})
	if mine.is_empty():
		return
	var here: Vector3 = body.global_position
	_prey = 0
	var nearest := HUNT_RANGE
	for other_id in arena.runners:
		var other: Dictionary = arena.runners[other_id]
		if other_id == id or not other.alive or other.safe > 0.0 or not is_instance_valid(other.body) or other.body.dead:
			continue
		var gap: float = here.distance_to(other.body.global_position)
		if other.mass >= mine.mass * EAT and gap < FLEE_RANGE:
			# Bigger, and close: the other way
			_aim = here + (here - other.body.global_position).normalized() * 15.0
			_prey = 0
			return
		if gap < nearest and other.mass < mine.mass * EAT and mine.safe <= 0.0:
			nearest = gap
			_prey = other_id
	if _prey != 0:
		return
	# Drops: the nearest (worth more, the bigger it is)
	var best := INF
	for drop in arena.drops.values():
		if drop.taken > 0.0:
			continue
		var cost: float = Vector2(drop.x - here.x, drop.z - here.z).length() / (1.0 + drop.v * 0.4)
		# (not one right behind it: it can't turn on the spot)
		var ahead: float = body.forward().dot(Vector3(drop.x - here.x, 0.0, drop.z - here.z).normalized())
		if ahead < -0.2:
			cost += 12.0
		if cost < best:
			best = cost
			_aim = Vector3(drop.x, 0.0, drop.z)
	if best == INF:
		_aim = Vector3.ZERO
