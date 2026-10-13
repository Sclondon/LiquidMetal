class_name SandBlob
extends Node3D
## A lump of wet sand that behaves like a thick jelly: it slumps and spreads
## under its own weight, holds together, runs down into hollows, and parts
## round whoever wades through it or whatever is dropped into it. Place this
## node where the middle of its underside starts; it begins as a block.
##
## It is a few dozen soft balls and no more:
## - Each falls, and is then moved out of whatever it has sunk into: other
##   balls (which also tug at their neighbours, and that is what holds it
##   together), the ground, and any body in it. Its speed is whatever that
##   left it having moved (position-based dynamics, one pass a tick).
## - The ground is read once, as a grid of heights over `reach`, so a ball
##   costs the same whatever it is lying on. It knows the ground as it was
##   then, and only what can be seen from above: walls and slopes, not roofs.
## - Bodies are known roughly: the Player as his capsule, anything else as a
##   ball. They push the sand; the sand does not push back, though it slows
##   whatever is thrown into it.
## - A ball that has all but stopped is stopped, which is what lets a heap
##   stand; and when all of them have, the whole thing sleeps and costs
##   nothing until something comes near.
## They are drawn fat and overlapping, with the sand shader's light leaned
## towards level, so the heap reads as one soft mass.
##
## `cost_usec` is what a tick of it takes. On a desktop 72 balls come to about
## a third of a millisecond awake; allow three to five times that in a phone's
## browser, and keep `count` under 150 or so.

const FALL := 14.0
## How far apart the heights of the ground are read, metres.
const CELL := 0.25
## A rise in the ground taller than this within one move is a wall.
const WALL := 0.14
## How many ticks all of it must lie still before it sleeps.
const SETTLE := 40

## How many balls, and how big each is across its middle (its radius), metres.
@export var count := 72
@export var grain := 0.17
## How wide and long the patch of ground it knows is, centred on this node.
## It cannot leave it.
@export var reach := Vector2(8.0, 8.0)
## How far above and below this node it looks for that ground.
@export var headroom := 3.0
@export var footroom := 4.0
## How hard two balls that overlap push apart, and how hard two that are
## close pull together, each 0..1.
@export var stiffness := 0.5
@export var cohesion := 0.05
## How much of its speed along the ground a ball loses each tick, 0..1.
@export var friction := 0.3
## Slower than this (m/s), a ball that is resting on something stays where it is.
## Higher: stiffer sand, steeper heaps. Lower: runnier.
@export var rest_speed := 0.1
## How much of its speed a body in the sand keeps each tick.
@export var drag := 0.86
## Its colour. Set it before it enters the scene. (Not in Outside's copy,
## where it is always `Sand.WET`.)
@export var colour := Sand.WET

## What the last tick cost, microseconds, smoothed. Zero while it sleeps.
var cost_usec := 0.0
var asleep := false

var _at := PackedVector3Array()
var _was := PackedVector3Array()
var _speed := PackedVector3Array()
## 1 for a ball that is resting on the ground or on another ball.
var _held := PackedByteArray()
## Which balls share a square of ground: the first in each, and the next after each.
var _first := {}
var _next := PackedInt32Array()
var _ground := PackedFloat32Array()
var _columns := 0
var _rows := 0
var _normal := Vector3.UP
var _bodies: Array[PhysicsBody3D] = []
var _body_at := PackedVector3Array()
var _body_was := PackedVector3Array()
var _body_size := PackedVector2Array()
var _low := Vector3.ZERO
var _high := Vector3.ZERO
var _still := 0
var _ticks := 0
var _stale := true
var _balls: MultiMesh


## Whether a point in the world is in the sand: over one of its balls, and no
## higher than the top of it. (Whoever stands in it sinks in further than in
## dry sand: `SandGround` asks.)
func covers(point: Vector3) -> bool:
	var local := point - global_position
	if absf(local.x) > reach.x * 0.5 or absf(local.z) > reach.y * 0.5:
		return false
	var near := grain * grain * 7.0
	for i in count:
		var from := _at[i] - local
		if from.x * from.x + from.z * from.z < near and from.y > -grain * 1.5 and from.y < grain * 3.0:
			return true
	return false


func _ready() -> void:
	add_to_group(&"sand_blobs")
	_at.resize(count)
	_was.resize(count)
	_speed.resize(count)
	_held.resize(count)
	_next.resize(count)
	var ball := SphereMesh.new()
	ball.radius = grain * 1.9
	ball.height = grain * 3.8
	ball.radial_segments = 10
	ball.rings = 5
	ball.material = Sand.surface(colour, 0.8)
	_balls = MultiMesh.new()
	_balls.transform_format = MultiMesh.TRANSFORM_3D
	_balls.mesh = ball
	_balls.instance_count = count
	var drawn := MultiMeshInstance3D.new()
	drawn.multimesh = _balls
	drawn.custom_aabb = AABB(Vector3(-reach.x * 0.5 - 1.0, -footroom - 1.0, -reach.y * 0.5 - 1.0),
			Vector3(reach.x + 2.0, footroom + headroom + 6.0, reach.y + 2.0))
	add_child(drawn)
	# Whatever comes into the patch is watched for.
	var patch := Area3D.new()
	patch.collision_layer = 0
	patch.collision_mask = 1 | 2 | 4
	var box := BoxShape3D.new()
	box.size = Vector3(reach.x, footroom + headroom, reach.y)
	var collider := CollisionShape3D.new()
	collider.shape = box
	collider.position.y = (headroom - footroom) * 0.5
	patch.add_child(collider)
	add_child(patch)
	patch.body_entered.connect(_on_entered)
	patch.body_exited.connect(func(body: Node3D) -> void: _bodies.erase(body))
	reset()


## Puts it back as it started: a block, standing on this node.
func reset() -> void:
	var side := ceili(pow(count, 1.0 / 3.0))
	var gap := grain * 1.8
	var random := RandomNumberGenerator.new()
	random.seed = 11
	for i in count:
		@warning_ignore("integer_division")
		var place := Vector3(i % side, i / (side * side), (i / side) % side)
		# (not quite in rows: a perfect stack would stand for ever)
		var jitter := Vector3(random.randf_range(-1.0, 1.0), 0.0, random.randf_range(-1.0, 1.0)) * grain * 0.15
		_at[i] = (place - Vector3(side - 1, 0.0, side - 1) * 0.5) * gap + Vector3.UP * grain + jitter
		_speed[i] = Vector3.ZERO
		_held[i] = 0
	_low = Vector3.ONE * -side * gap
	_high = Vector3.ONE * side * gap * 2.0
	asleep = false
	_still = 0
	_stale = true


func _on_entered(body: Node3D) -> void:
	if (body is CharacterBody3D or body is RigidBody3D) and not _bodies.has(body):
		_bodies.append(body as PhysicsBody3D)


func _physics_process(delta: float) -> void:
	# The ground is read once, when everything round it has been built.
	_ticks += 1
	if _ticks < 2:
		return
	if _ticks == 2:
		_read_ground()
	var stirred := _read_bodies()
	if asleep and not stirred:
		cost_usec = 0.0
		return
	asleep = false
	var began := Time.get_ticks_usec()
	_still = 0 if _step(delta) or stirred else _still + 1
	asleep = _still >= SETTLE
	_stale = true
	cost_usec = lerpf(cost_usec, float(Time.get_ticks_usec() - began), 0.1)


func _process(_delta: float) -> void:
	if not _stale:
		return
	_stale = false
	# (a little flattened, and sunk a little into what they lie on)
	var squat := Basis.from_scale(Vector3(1.0, 0.75, 1.0))
	for i in count:
		_balls.set_instance_transform(i, Transform3D(squat, _at[i]))


## Reads how high the ground stands under every corner of a grid over the patch.
func _read_ground() -> void:
	_columns = ceili(reach.x / CELL) + 1
	_rows = ceili(reach.y / CELL) + 1
	_ground.resize(_columns * _rows)
	var space := get_world_3d().direct_space_state
	var origin := global_position
	for row in _rows:
		for column in _columns:
			var over := origin + Vector3(column * CELL - reach.x * 0.5, headroom, row * CELL - reach.y * 0.5)
			var query := PhysicsRayQueryParameters3D.create(over, over + Vector3.DOWN * (headroom + footroom), 1)
			var found := -footroom
			# Past anything that might be moved away later, to what will not be.
			for attempt in 4:
				var hit := space.intersect_ray(query)
				if hit.is_empty():
					break
				if hit.collider is StaticBody3D:
					found = (hit.position as Vector3).y - origin.y
					break
				query.exclude = query.exclude + [hit.rid]
			_ground[row * _columns + column] = found


## Notes where every body in the patch is and how big, and says whether any of
## them has moved near the sand.
func _read_bodies() -> bool:
	var stirred := false
	var origin := global_position
	_body_was = _body_at.duplicate()
	_body_at.resize(_bodies.size())
	_body_size.resize(_bodies.size())
	for i in _bodies.size():
		var body := _bodies[i]
		var shaped: CollisionShape3D = null
		for child in body.get_children():
			if child is CollisionShape3D:
				shaped = child
				break
		var middle := (shaped.global_position if shaped else body.global_position) - origin
		# x: how thick it is (a radius); y: how far its middle line runs up and down from its centre.
		var size := Vector2(0.3, 0.0)
		if shaped and shaped.shape is CapsuleShape3D:
			var capsule := shaped.shape as CapsuleShape3D
			size = Vector2(capsule.radius, maxf(capsule.height * 0.5 - capsule.radius, 0.0))
		elif shaped and shaped.shape is SphereShape3D:
			size = Vector2((shaped.shape as SphereShape3D).radius, 0.0)
		elif shaped and shaped.shape is BoxShape3D:
			var box := (shaped.shape as BoxShape3D).size
			size = Vector2(minf(minf(box.x, box.z), box.y) * 0.6, 0.0)
		_body_at[i] = middle
		_body_size[i] = size
		var margin := Vector3.ONE * (size.x + size.y + grain * 2.0)
		var near := AABB(_low - margin, _high - _low + margin * 2.0).has_point(middle)
		if near and (i >= _body_was.size() or _body_was[i].distance_squared_to(middle) > 0.000025):
			stirred = true
	return stirred


## One tick of it. Says whether any of it is still on the move.
func _step(delta: float) -> bool:
	var rest := grain * 1.8
	var hold := grain * 2.7
	var hold_squared := hold * hold
	var half := reach * 0.5 - Vector2.ONE * grain
	# Fall.
	for i in count:
		_was[i] = _at[i]
		var speed := _speed[i]
		speed.y -= FALL * delta
		_speed[i] = speed
		_at[i] += speed * delta
		_held[i] = 0
	# Sort them into squares as wide as they can feel each other across.
	_first.clear()
	for i in count:
		var p := _at[i]
		var key := (floori(p.x / hold) + 512) * 1024 + floori(p.z / hold) + 512
		_next[i] = _first.get(key, -1)
		_first[key] = i
	# Each pair once: apart if they overlap, together if they are only close.
	for i in count:
		var p := _at[i]
		var column := floori(p.x / hold) + 512
		var row := floori(p.z / hold) + 512
		for square in 9:
			@warning_ignore("integer_division")
			var j: int = _first.get((column + square % 3 - 1) * 1024 + row + square / 3 - 1, -1)
			while j >= 0:
				if j > i:
					var q := _at[j]
					var between := q - p
					var far := between.length_squared()
					if far < hold_squared and far > 0.000001:
						far = sqrt(far)
						var move := between * ((far - rest) * (stiffness if far < rest else cohesion) * 0.5 / far)
						p += move
						_at[j] = q - move
						if far < rest * 1.05:
							# Whichever is on top is resting on the other.
							if between.y > far * 0.35:
								_held[j] = 1
							elif between.y < -far * 0.35:
								_held[i] = 1
				j = _next[j]
		_at[i] = p
	# Out of bodies, and out of the ground.
	var touched := PackedInt32Array()
	touched.resize(_body_at.size())
	var moving := false
	_low = Vector3.ONE * 1000.0
	_high = Vector3.ONE * -1000.0
	for i in count:
		var p := _at[i]
		var was := _was[i]
		for b in _body_at.size():
			var middle := _body_at[b]
			var size := _body_size[b]
			var from := p - Vector3(middle.x, middle.y + clampf(p.y - middle.y, -size.y, size.y), middle.z)
			var room := size.x + grain
			var far := from.length_squared()
			if far < room * room and far > 0.000001:
				far = sqrt(far)
				# Aside rather than down: there is ground under it.
				from.y *= 0.3
				p += from.normalized() * (room - far)
				touched[b] += 1
		p.x = clampf(p.x, -half.x, half.x)
		p.z = clampf(p.z, -half.y, half.y)
		var floor_y := _height(p.x, p.z)
		if floor_y - (p.y - grain) > WALL and floor_y - (was.y - grain) > WALL:
			# A wall: it may slide along it, but not go in.
			if _height(was.x, p.z) - (p.y - grain) <= WALL:
				p.x = was.x
			elif _height(p.x, was.z) - (p.y - grain) <= WALL:
				p.z = was.z
			else:
				p.x = was.x
				p.z = was.z
			floor_y = _height(p.x, p.z)
		var grounded := p.y - grain < floor_y
		if grounded:
			# Out along the slope's normal, so it runs downhill.
			p += _normal * ((floor_y + grain - p.y) * _normal.y)
			_held[i] = 1
		var speed := (p - was) / delta
		if grounded:
			speed.x *= 1.0 - friction
			speed.z *= 1.0 - friction
		if _held[i] == 1 and speed.length_squared() < rest_speed * rest_speed:
			p = was
			speed = Vector3.ZERO
		else:
			moving = true
		_at[i] = p
		_speed[i] = speed * 0.99
		_low = _low.min(p)
		_high = _high.max(p)
	# What is in the sand is slowed by it.
	for b in touched.size():
		var body := _bodies[b] as RigidBody3D
		if body and touched[b] >= 2 and not body.freeze:
			body.linear_velocity *= drag
			body.angular_velocity *= drag
	return moving


## How high the ground is at a place in the patch, measured from this node;
## and leaves which way it faces there in `_normal`.
func _height(x: float, z: float) -> float:
	var across := clampf((x + reach.x * 0.5) / CELL, 0.0, _columns - 1.001)
	var along := clampf((z + reach.y * 0.5) / CELL, 0.0, _rows - 1.001)
	var column := int(across)
	var row := int(along)
	across -= column
	along -= row
	var corner := row * _columns + column
	var a := _ground[corner]
	var b := _ground[corner + 1]
	var c := _ground[corner + _columns]
	var d := _ground[corner + _columns + 1]
	var near := lerpf(a, b, across)
	var far := lerpf(c, d, across)
	_normal = Vector3(lerpf(a, c, along) - lerpf(b, d, along), CELL, near - far).normalized()
	return lerpf(near, far, along)
