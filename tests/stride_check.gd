extends SceneTree
## Headless check of the stride timing: how long one run cycle takes, slow vs fast.
## Run: godot --headless --path . -s res://tests/stride_check.gd

var main: Node
var anim: AnimationPlayer
var t := 0.0
var phase := 0
var last := 0.0
var cycle_start := -1.0
var results := []


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	main.start_mode = "test"
	root.add_child(main)


func _process(delta: float) -> bool:
	t += delta
	var model: Node = main.player._figure
	anim = model._anim
	if anim.current_animation != "run":
		return t > 20.0
	# drive it directly at a fixed speed and count full cycles
	var speed: float = [6.0, 26.0][phase]
	main.player.run_speed = speed # held at that speed (the walls and obstacles are far off at first)
	main.player.speed = speed
	main.player.global_position.z = 128.0
	var pos := anim.current_animation_position
	if pos < last: # wrapped: a cycle done
		if cycle_start >= 0.0:
			results.append("speed %.0f: a cycle (two lunges) takes %.2f s" % [speed, t - cycle_start])
			phase += 1
			cycle_start = -1.0
			if phase >= 2:
				for r in results:
					print(r)
				return true
		else:
			cycle_start = t
	last = pos
	return t > 30.0
