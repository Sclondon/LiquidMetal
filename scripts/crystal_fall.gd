extends Node3D
## A crystal falling out of the sky onto the ring (endless.gd drops them ahead of the runner).
## First a mark on the sand where it will land: a pool of its light closing in for `warn`
## seconds while the crystal streaks down, a tail of light behind it. Then it hits: a flash, a
## burst of shards and black sand, and there it stays, stuck in the ring at a slant, something to
## go round (its collider comes on as it lands). `struck` tells the course, which splats whoever
## was under it and jolts the camera.

signal struck(crystal: Node3D)

const Crystal := preload("res://scripts/crystal.gd")
const LENGTH := 9.0 # tip to tip
const RADIUS := 1.3
const STANDS := 5.2 # how much of it shows above the sand once it's in
const HIT := 2.3 # metres from its middle that it splats a runner as it lands
const FROM := Vector3(12.0, 75.0, -170.0) # where it comes from, from where it lands: low out of the sky ahead
const BLOCK := Vector3(2.6, 5.0, 2.6) # what it stops, once landed
const SHAFT := 14.0 # how tall the light over the mark is

var warn := 1.6
var color := Color(0.65, 0.4, 1.0)
var landed := false

var _clock := 0.0
var _from := FROM
var _mark := MeshInstance3D.new()
var _mark_material := ShaderMaterial.new()
var _shaft := MeshInstance3D.new()
var _shaft_material := ShaderMaterial.new()
var _shard := MeshInstance3D.new()
var _tail := MeshInstance3D.new()
var _collider := CollisionShape3D.new()
var _flash := OmniLight3D.new()


func _ready() -> void:
	_from = FROM.rotated(Vector3.UP, randf_range(-0.35, 0.35))
	# The mark on the sand
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * HIT * 3.2
	_mark.mesh = plane
	_mark_material.shader = preload("res://shaders/crystal_mark.gdshader")
	_mark_material.set_shader_parameter("color", color)
	_mark.material_override = _mark_material
	_mark.position.y = 0.04
	_mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mark)
	# A shaft of its light standing on the mark (the mark alone is hard to see from low down)
	var column := CylinderMesh.new()
	column.top_radius = HIT * 0.75
	column.bottom_radius = HIT * 0.75
	column.height = SHAFT
	column.cap_top = false
	column.cap_bottom = false
	_shaft.mesh = column
	_shaft_material.shader = _mark_material.shader
	_shaft_material.set_shader_parameter("color", color)
	_shaft_material.set_shader_parameter("shaft", SHAFT)
	_shaft.material_override = _shaft_material
	_shaft.position.y = SHAFT * 0.5
	_shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_shaft)
	# The crystal, point first down the line it falls along
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/crystal.gdshader")
	material.set_shader_parameter("horizon", color)
	material.set_shader_parameter("sky_top", color.darkened(0.7))
	material.set_shader_parameter("clarity", 0.35)
	_shard.mesh = Crystal.shard(RADIUS, LENGTH, 0.4)
	_shard.material_override = material
	_shard.basis = _along(_from)
	add_child(_shard)
	# Its tail: a long thin shard of plain light behind it
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	glow.albedo_color = color.lerp(Color.WHITE, 0.4) * 0.55
	glow.disable_fog = true
	_tail.mesh = Crystal.shard(RADIUS * 0.8, 70.0, 0.0)
	_tail.material_override = glow
	_tail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shard.add_child(_tail)
	_tail.position.y = 36.0
	# What it stops once it's down (a plain box: fair to run round)
	var body := StaticBody3D.new()
	var shape := BoxShape3D.new()
	shape.size = BLOCK
	_collider.shape = shape
	_collider.position.y = BLOCK.y * 0.5
	_collider.disabled = true
	body.add_child(_collider)
	add_child(body)
	_flash.light_color = color.lerp(Color.WHITE, 0.5)
	_flash.omni_range = 26.0
	_flash.light_energy = 0.0
	_flash.position.y = 2.5
	add_child(_flash)
	_place(0.0)


## A basis whose Y runs along `way`
func _along(way: Vector3) -> Basis:
	var up := way.normalized()
	var side := up.cross(Vector3.FORWARD).normalized()
	return Basis(side, up, side.cross(up))


func _place(done: float) -> void:
	# (down the line; the point reaches the sand as the mark closes)
	var up := _from.normalized()
	_shard.position = _from * (1.0 - done) + up * (LENGTH * 0.5)
	_mark_material.set_shader_parameter("closing", done)
	_shaft_material.set_shader_parameter("closing", done)


func _process(delta: float) -> void:
	_clock += delta
	if landed:
		_flash.light_energy = maxf(_flash.light_energy - delta * 14.0, 0.0)
		return
	if _clock < warn:
		_place(_clock / warn)
		return
	_land()


func _land() -> void:
	landed = true
	# Stuck in at a slant, the way it came (less steeply: it has to stand as something to dodge)
	var slant := (_from.normalized() + Vector3.UP * 1.6).normalized()
	_shard.basis = _along(slant)
	_shard.position = slant * (STANDS - LENGTH * 0.5)
	_tail.visible = false
	_collider.disabled = false
	_mark_material.set_shader_parameter("closing", 1.0)
	_mark_material.set_shader_parameter("scorch", 1.0)
	_shaft.visible = false
	_flash.light_energy = 5.0
	_burst()
	struck.emit(self)


## Shards thrown out, and a ring of black sand
func _burst() -> void:
	var bits := CPUParticles3D.new()
	bits.mesh = Crystal.shard(0.14, 0.7, 0.2, 4)
	var bit_material := ShaderMaterial.new()
	bit_material.shader = preload("res://shaders/crystal.gdshader")
	bit_material.set_shader_parameter("horizon", color)
	bit_material.set_shader_parameter("sky_top", color.darkened(0.7))
	bit_material.set_shader_parameter("clarity", 0.2)
	bits.material_override = bit_material
	bits.amount = 22
	bits.lifetime = 1.3
	bits.one_shot = true
	bits.explosiveness = 1.0
	bits.direction = Vector3.UP
	bits.spread = 65.0
	bits.initial_velocity_min = 7.0
	bits.initial_velocity_max = 17.0
	bits.gravity = Vector3.DOWN * 30.0
	bits.angular_velocity_min = -400.0
	bits.angular_velocity_max = 400.0
	bits.particle_flag_rotate_y = true
	bits.scale_amount_min = 0.5
	bits.scale_amount_max = 1.6
	bits.position.y = 0.4
	add_child(bits)
	bits.emitting = true
	var sand := CPUParticles3D.new()
	var grain := SphereMesh.new()
	grain.radius = 0.16
	grain.height = 0.32
	grain.radial_segments = 6
	grain.rings = 3
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.09, 0.085, 0.1)
	dark.roughness = 1.0
	grain.material = dark
	sand.mesh = grain
	sand.amount = 60
	sand.lifetime = 1.1
	sand.one_shot = true
	sand.explosiveness = 1.0
	sand.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	sand.emission_ring_axis = Vector3.UP
	sand.emission_ring_radius = 1.6
	sand.emission_ring_inner_radius = 1.0
	sand.emission_ring_height = 0.1
	sand.direction = Vector3.UP
	sand.spread = 50.0
	sand.initial_velocity_min = 5.0
	sand.initial_velocity_max = 13.0
	sand.gravity = Vector3.DOWN * 26.0
	sand.scale_amount_min = 0.4
	sand.scale_amount_max = 1.5
	sand.position.y = 0.2
	add_child(sand)
	sand.emitting = true
