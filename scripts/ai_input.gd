extends Node
## An enemy runner's "controls": the same signals and turn axis the player's input gives, driven
## by an AI instead of touches. The enemy is the player's own runner script, so it moves with all
## the same systems. It chases the player: behind him it runs faster and steers straight at him;
## once it's past him it slows down (so he can catch it and dash through it). It reads the course's
## lane_plan where there is one, and feels ahead with rays for everything else: low things it jumps,
## beams it slides under, tall things it swerves round. On the ring (endless: mind_ground) it
## feels for the ground too: a narrow break ahead it jumps, a wide one it turns away from, and it
## keeps off the edges.

signal jump
signal duck
signal dodge(direction: float)
signal dash

var turn := 0.0
var look := Vector2.ZERO
var brake := 0.0 # (it never brakes)
var use_pads := false
var dash_button_down := false

var body: CharacterBody3D # the enemy it drives
var course: Node # has lane_plan: [{ z, kind, half? }]
var target: CharacterBody3D # the player
## Arena: straight at him whichever side of him it's on (not just from behind)
var always_chase := false
## Endless: the ground has breaks in it and edges to fall off, so it looks where it's putting
## its feet (off everywhere else: the test area and the arena are as they were)
var mind_ground := false

const Difficulty := preload("res://scripts/difficulty.gd")
const PASSED_SPEED := 0.78 # times his run speed, once past him (while behind: the difficulty's chase)
const FEEL := 7.0 # metres ahead it looks for obstacles

var _done := {}
var _hold_line := 0.0 # seconds left of keeping its line (just dodged)
var _swerve := 0.0 # -1 / +1 swerving round something tall, easing off
var _feel_clock := 0.0
var _ground_turn := 0.0 # -1 / +1 turning away from a break or an edge (it overrides the chase)


func duck_held() -> bool:
	return false


func dash_held() -> bool:
	return false


func _physics_process(delta: float) -> void:
	if body == null or body.dead:
		turn = 0.0
		return
	_hold_line = maxf(_hold_line - delta, 0.0)
	_swerve = move_toward(_swerve, 0.0, delta * 1.5)
	_read_lane()
	_feel_ahead(delta)

	# Where to go: at him while it's behind him, otherwise on the way he's going
	var aim: Vector3 = body.global_position + body.forward() * 10.0
	if target and not target.dead:
		var to_him: Vector3 = target.global_position - body.global_position
		var behind: bool = always_chase or to_him.dot(target.forward()) > -1.0 # (it's behind him, or level)
		var chase: float = Difficulty.tier().arena_chase if always_chase else Difficulty.tier().chase
		body.run_speed = target.run_speed * (chase if behind else PASSED_SPEED)
		aim = target.global_position + target.forward() * 2.0 if behind else body.global_position + target.forward() * 10.0
	var to_aim: Vector3 = aim - body.global_position
	var want := atan2(-to_aim.x, -to_aim.z)
	var off := wrapf(want - body.heading, -PI, PI)
	# (+turn is right, which lowers the heading)
	var steer := clampf(-off * float(Difficulty.tier().steer), -1.0, 1.0) # (gentler on easier tiers: wider turns)
	if _hold_line > 0.0:
		steer *= 0.2
	turn = clampf(steer + _swerve, -1.0, 1.0)
	if mind_ground and _ground_turn != 0.0:
		turn = _ground_turn # (the ground comes first)


## Rays out ahead: low wall (jump it), a beam (slide under it), something tall (swerve round it)
func _feel_ahead(delta: float) -> void:
	_feel_clock -= delta
	if _feel_clock > 0.0:
		return
	_feel_clock = 0.08
	var space := body.get_world_3d().direct_space_state
	var from := body.global_position
	var ahead: Vector3 = body.forward() * maxf(FEEL, body.speed * 0.55)
	var knee := _ray(space, from + Vector3.UP * 0.4, ahead)
	var chest := _ray(space, from + Vector3.UP * 1.25, ahead)
	var reach := ahead.length()
	if knee < reach and chest >= reach:
		if body.is_on_floor() and knee < maxf(body.speed * 0.32, 3.0):
			jump.emit()
	elif chest < reach and knee >= reach:
		if chest < maxf(body.speed * 0.25, 2.5):
			duck.emit()
	elif knee < reach and chest < reach:
		# Tall: swerve to whichever side is clearer
		var left := _ray(space, from + Vector3.UP * 1.0, ahead.rotated(Vector3.UP, 0.5))
		var right := _ray(space, from + Vector3.UP * 1.0, ahead.rotated(Vector3.UP, -0.5))
		_swerve = -1.0 if left > right else 1.0
		if knee < 3.5:
			dodge.emit(-1.0 if left > right else 1.0)
			_hold_line = 0.4
	if mind_ground:
		_feel_ground(space)


## Rays down ahead of it: is the ring there? A break it can clear it jumps at the lip; one it
## can't, it turns from, toward whichever side has ground the furthest; and it turns back in
## from an edge
func _feel_ground(space: PhysicsDirectSpaceState3D) -> void:
	_ground_turn = 0.0
	if not body.is_on_floor():
		return
	var from := body.global_position
	var ahead: Vector3 = body.forward()
	var reach := maxf(10.0, body.speed * 0.8)
	var gap_from := -1.0
	var gap_to := -1.0
	var step := 1.0
	while step <= reach + 12.0:
		var ground := _ground(space, from + ahead * step)
		if gap_from < 0.0 and not ground and step <= reach:
			gap_from = step
		elif gap_from >= 0.0 and ground:
			gap_to = step
			break
		step += 1.0
	if gap_from >= 0.0:
		var across := gap_to - gap_from if gap_to > 0.0 else INF
		if across + 3.5 < body.speed * 0.647: # (what a jump covers, less the run-up and some to spare)
			if gap_from <= maxf(2.0, body.speed * 0.12):
				jump.emit()
			return
		var left := _ground_run(space, from, ahead.rotated(Vector3.UP, 0.7), gap_from + 8.0)
		var right := _ground_run(space, from, ahead.rotated(Vector3.UP, -0.7), gap_from + 8.0)
		if left == right: # (no telling: back toward the middle of the ring)
			left = -body.right().x * signf(from.x)
			right = -left
		_ground_turn = -1.0 if left > right else 1.0
		return
	# An edge alongside
	var side: Vector3 = body.right()
	if not _ground(space, from + ahead * 4.0 + side * 3.0):
		_ground_turn = -1.0
	elif not _ground(space, from + ahead * 4.0 - side * 3.0):
		_ground_turn = 1.0


## Is there something to stand on under this point?
func _ground(space: PhysicsDirectSpaceState3D, at: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 1.0, at + Vector3.DOWN * 2.0)
	query.exclude = [body.get_rid()]
	query.collision_mask = 1
	return not space.intersect_ray(query).is_empty()


## How far the ground goes on from here along a line, up to "most" metres
func _ground_run(space: PhysicsDirectSpaceState3D, from: Vector3, along: Vector3, most: float) -> float:
	var step := 2.0
	while step <= most:
		if not _ground(space, from + along * step):
			return step
		step += 2.0
	return most


func _ray(space: PhysicsDirectSpaceState3D, from: Vector3, along: Vector3) -> float:
	var query := PhysicsRayQueryParameters3D.create(from, from + along)
	query.exclude = [body.get_rid()]
	query.collision_mask = 1
	var hit := space.intersect_ray(query)
	if hit.is_empty() or hit.collider == target:
		return INF
	return from.distance_to(hit.position)


## The course's own list of what's on the lane (when running straight down it)
func _read_lane() -> void:
	if course == null or not "lane_plan" in course or absf(wrapf(body.heading, -PI, PI)) > 0.6:
		return
	if absf(body.global_position.x) > 6.0:
		return # not on the lane
	var z := body.global_position.z
	var pace := maxf(body.speed, 4.0) / 14.0
	for k in course.lane_plan.size():
		var obstacle: Dictionary = course.lane_plan[k]
		var oz: float = obstacle.z
		var half: float = obstacle.get("half", 6.0)
		if oz - (half if obstacle.kind == "hurdle_pair" else 0.0) > z + 2.0 or oz < z - 40.0:
			continue
		var actions := []
		match obstacle.kind:
			"hurdle":
				actions = [[oz + 4.5 * pace, "jump"]]
			"beam", "tunnel":
				actions = [[oz + 3.0 * pace, "duck"]]
			"dodge_left", "dodge_both":
				actions = [[oz + 6.0 * pace, "left"]]
			"dodge_right":
				actions = [[oz + 6.0 * pace, "right"]]
			"hurdle_pair":
				actions = [[oz + half + 4.5 * pace, "jump"], [oz - half + 4.5 * pace, "jump"]]
		for a in actions.size():
			var key := "%d:%d" % [k, a]
			if _done.has(key) or z > actions[a][0]:
				continue
			_done[key] = true
			match actions[a][1]:
				"jump":
					jump.emit()
				"duck":
					duck.emit()
				"left", "right":
					dodge.emit(-1.0 if actions[a][1] == "left" else 1.0)
					_hold_line = 0.7
