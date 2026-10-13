extends SceneTree
## Screenshots of the endless run on the ring: the runner's view on open ring, each kind of
## thing on the course coming up (a break, a ridge, a curtain, a wall, a palisade), a crystal
## about to land and just landed, a boost ring of aurora, a look over the edge, and the ring and
## the moon from up and to one side. Needs a window:
## godot --path . -s res://tests/ring_shots.gd -- <out dir> [seed] [only shots named like this]

var main: Node
var t := 0.0
var step := -1
var shots: Array = [] # [name, set-up, seconds to wait]
var fall: Node3D


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	main.start_mode = "endless"
	main.use_pads = false
	main.enemies = false
	root.add_child(main)
	shots = [
		["01_open_ring", _open, 1.6],
		["02_crack_ahead", _before.bind("crack", 19.0), 0.5],
		["03_bite_ahead", _before.bind("bite", 24.0), 0.5],
		["04_hole_ahead", _before.bind("hole", 22.0), 0.5],
		["05_ridge", _before.bind("ridge", 17.0), 0.5],
		["06_curtain", _before.bind("curtain", 17.0), 0.5],
		["07_wall", _before.bind("wall", 22.0), 0.5],
		["08_palisade", _before.bind("wallrun", 14.0), 0.5],
		["09_crystal_coming", _crystal, 1.3],
		["10_crystal_landed", func(): pass, 0.42],
		["11_crystal_stays", func(): pass, 1.2],
		["12_aurora_ring", _aurora, 0.45],
		["13_aurora_jump", _aurora_up, 0.5],
		["14_over_the_edge", _edge, 0.4],
		["15_ring_and_moon", _wide, 0.4],
		["16_ring_from_above", _above, 0.4],
		["17_moon", _moon, 0.4],
	]
	# (a third argument: only the shots with that in their name)
	var args := OS.get_cmdline_user_args()
	if args.size() > 2:
		shots = shots.filter(func(shot): return args[2] in shot[0])


func _shot(name: String) -> void:
	root.get_texture().get_image().save_png("%s/%s.png" % [OS.get_cmdline_user_args()[0], name])


func _process(delta: float) -> bool:
	t += delta
	if step < 0:
		# (first frame: the course is up)
		main.area.falling_crystals = false
		var args := OS.get_cmdline_user_args()
		main.area.generate(int(args[1]) if args.size() > 1 else 7)
		step = 0
		t = 0.0
		main.hud.visible = false
		shots[0][1].call()
		return false
	if t < float(shots[step][2]):
		return false
	_shot(shots[step][0])
	step += 1
	t = 0.0
	if step >= shots.size():
		return true
	shots[step][1].call()
	return false


## The runner put down at a spot, already up to speed, the camera behind him
func _put(x: float, z: float) -> void:
	var p: CharacterBody3D = main.player
	main.cam.set_process(true)
	main.cam.fov = 70.0
	p.set_physics_process(true)
	p.place(Vector3(x, 0.0, z), 0.0)
	p.speed = p.run_speed
	main.area._physics_process(0.0) # (the course built out from here)
	main.cam.snap()


func _open() -> void:
	_put(0.0, main.area.start_position.z)


## `back` metres short of the first of a kind of thing still ahead, in line with it
func _before(kind: String, back: float) -> void:
	var p: CharacterBody3D = main.player
	p.set_physics_process(false)
	for tries in 30:
		for thing in main.area.plan:
			if thing.kind == kind and thing.z0 < p.global_position.z - 30.0:
				var x: float = clampf((float(thing.x0) + float(thing.x1)) * 0.5, -20.0, 20.0)
				if kind in ["bite", "hole", "wallrun"]: # (beside it, not into it)
					x = clampf(float(thing.x1) + 5.0 if float(thing.x1) < 14.0 else float(thing.x0) - 5.0, -24.0, 24.0)
				_put(x, float(thing.z0) + back)
				return
		# (none in what's built: on along the ring until there is)
		p.global_position.z -= 150.0
		main.area._physics_process(0.0)
	print("no %s found" % kind)


func _clear_spot() -> Vector3:
	# Open ring: between the next two things laid
	var p: CharacterBody3D = main.player
	var last := p.global_position.z
	for thing in main.area.plan:
		if thing.z0 < p.global_position.z - 40.0 and last - float(thing.z0) > 20.0 and last < p.global_position.z - 10.0:
			return Vector3(0.0, 0.0, last - 3.0)
		last = minf(last, float(thing.z1))
	return Vector3(0.0, 0.0, last - 3.0)


func _crystal() -> void:
	var spot := _clear_spot()
	_put(3.0, spot.z + 18.0)
	main.player.set_physics_process(false)
	fall = main.area.drop_crystal(Vector3(1.0, 0.0, spot.z - 5.0), 1.6)


func _aurora() -> void:
	main.player.set_physics_process(true)
	var p: CharacterBody3D = main.player
	p.set_physics_process(false)
	for tries in 30:
		for pad in _pads():
			if pad.lift == 0.0 and pad.global_position.z < p.global_position.z - 30.0:
				_put(pad.global_position.x + 1.5, pad.global_position.z + 15.0)
				return
		p.global_position.z -= 150.0
		main.area._physics_process(0.0)
	print("no boost ring on the sand found")


func _aurora_up() -> void:
	var p: CharacterBody3D = main.player
	p.set_physics_process(false)
	for tries in 30:
		for pad in _pads():
			if pad.lift > 0.0 and pad.global_position.z < p.global_position.z - 30.0:
				_put(pad.global_position.x + 1.0, pad.global_position.z + 17.0)
				return
		p.global_position.z -= 150.0
		main.area._physics_process(0.0)
	print("no boost ring in the air found")


func _pads() -> Array:
	var pads: Array = main.area.find_children("*", "Area3D", true, false).filter(func(node): return "lift" in node)
	pads.sort_custom(func(a, b): return a.global_position.z > b.global_position.z)
	return pads


## Stopped by the ring's edge, the camera looking out over it at the moon
func _edge() -> void:
	var p: CharacterBody3D = main.player
	_put(-24.0, p.global_position.z - 30.0)
	p.set_physics_process(false)
	main.cam.set_process(false)
	main.cam.global_position = p.global_position + Vector3(7.0, 3.4, 5.0)
	main.cam.look_at(p.global_position + Vector3(-30.0, -4.0, -22.0))


## The runner and the camera left where they're put
func _hold() -> void:
	main.player.set_physics_process(false)
	main.cam.set_process(false)


## Up and off to the right, looking across the ring at the moon
func _wide() -> void:
	var p: CharacterBody3D = main.player
	_hold()
	main.cam.global_position = p.global_position + Vector3(170.0, 90.0, 190.0)
	main.cam.look_at(p.global_position + Vector3(-500.0, 0.0, -700.0))
	main.cam.fov = 75.0


func _above() -> void:
	var p: CharacterBody3D = main.player
	_hold()
	main.cam.global_position = p.global_position + Vector3(30.0, 60.0, 50.0)
	main.cam.look_at(p.global_position + Vector3(-10.0, 0.0, -90.0))
	main.cam.fov = 75.0


## The moon square on, from well out: its three suns' light and its air
func _moon() -> void:
	var p: CharacterBody3D = main.player
	_hold()
	main.cam.global_position = p.global_position + Vector3(1500.0, 500.0, 300.0)
	main.cam.look_at(p.global_position + Vector3(-1500.0, -150.0, 0.0))
	main.cam.fov = 60.0
