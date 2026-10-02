extends Node
## An enemy runner's "controls": the same signals and turn axis the player's input gives, driven
## by reading the course ahead (its lane_plan) instead of touches. The enemy is the player's own
## runner script, so it moves with all the same systems.

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

var _done := {}
var _target_x := 0.0
var _target_until := -INF


func duck_held() -> bool:
	return false


func dash_held() -> bool:
	return false


func _physics_process(_delta: float) -> void:
	if body == null or body.dead or course == null:
		turn = 0.0
		return
	var z := body.global_position.z
	var pace := maxf(body.speed, 4.0) / 14.0
	for k in course.lane_plan.size():
		var obstacle: Dictionary = course.lane_plan[k]
		var oz: float = obstacle.z
		var half: float = obstacle.get("half", 6.0)
		# (a pair reaches half on past its middle)
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
					var side := -1.0 if actions[a][1] == "left" else 1.0
					dodge.emit(side)
					# keep to that side till it's past
					_target_x = side * 3.0
					_target_until = oz - 2.0
	if z < _target_until:
		_target_x = 0.0
	# Steer to hold its line down the lane (+turn is right; heading > 0 faces left)
	var x := body.global_position.x - _target_x
	turn = clampf(-x * 0.35 + body.heading * 3.0, -1.0, 1.0)
