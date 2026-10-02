extends Node
## An enemy runner's "controls": the same signals and turn axis the player's input gives, driven
## by an AI instead of touches. The enemy is the player's own runner script, so it moves with all
## the same systems. It chases the player: behind him it runs faster and steers straight at him;
## once it's past him it slows down (so he can catch it and dash through it). It reads the course's
## lane_plan where there is one, and feels ahead with rays for everything else: low things it jumps,
## beams it slides under, tall things it swerves round.

signal jump
signal duck
signal dodge(direction: float)
signal dash

var turn := 0.0
var look := Vector2.ZERO
var use_pads := false
var dash_button_down := false

var body: CharacterBody3D # the enemy it drives
var course: Node # has lane_plan: [{ z, kind, half? }]
var target: CharacterBody3D # the player

const CHASE_SPEED := 1.35 # times his run speed, while behind him
const PASSED_SPEED := 0.78 # once past him
const FEEL := 7.0 # metres ahead it looks for obstacles

var _done := {}
var _hold_line := 0.0 # seconds left of keeping its line (just dodged)
var _swerve := 0.0 # -1 / +1 swerving round something tall, easing off
var _feel_clock := 0.0


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
		var behind: bool = to_him.dot(target.forward()) > -1.0 # (it's behind him, or level)
		body.run_speed = target.run_speed * (CHASE_SPEED if behind else PASSED_SPEED)
		aim = target.global_position + target.forward() * 2.0 if behind else body.global_position + target.forward() * 10.0
	var to_aim: Vector3 = aim - body.global_position
	var want := atan2(-to_aim.x, -to_aim.z)
	var off := wrapf(want - body.heading, -PI, PI)
	# (+turn is right, which lowers the heading)
	var steer := clampf(-off * 2.5, -1.0, 1.0)
	if _hold_line > 0.0:
		steer *= 0.2
	turn = clampf(steer + _swerve, -1.0, 1.0)


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
			"beam":
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
