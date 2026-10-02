extends Node3D
## Mercury, the runner: the Blender model (models/mercury.glb, built by art/build_mercury.py
## after mercury.png) dressed in the liquid-metal shader. Every part floats free of the
## others; the model's own animations run it ("run", a looping stride) and leap ("jump",
## a held pose). Faces -Z.

const MODEL_SCALE := 0.66 # the .glb is ~3.1 m to the horn tip; this makes it ~2 m
const RUN_PACE := 12.0 # run speed (m/s) at which the stride plays at its authored rate
const BLEND := 0.08 # seconds to blend between run and jump: snappy

var material: Material

var _model: Node3D
var _parts: Array[Node3D] = []
var _anim: AnimationPlayer
var _airborne := false


func _ready() -> void:
	_model = preload("res://models/mercury.glb").instantiate()
	_model.scale = Vector3.ONE * MODEL_SCALE
	add_child(_model)

	# Chrome everywhere but the eyes, which glow red
	var eye_material := StandardMaterial3D.new()
	eye_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	eye_material.albedo_color = Color(1.0, 0.1, 0.08)
	for view in _model.find_children("*", "MeshInstance3D", true, false):
		var original: Material = view.mesh.surface_get_material(0)
		var eye: bool = original and original.resource_name == "Eye"
		view.material_override = eye_material if eye else material
		if not eye:
			_parts.append(view)

	_anim = _model.find_child("AnimationPlayer", true, false)
	_anim.get_animation("run").loop_mode = Animation.LOOP_LINEAR
	_anim.play("run")


## The metal body parts (where droplets come off and go back to)
func parts() -> Array[Node3D]:
	return _parts


## Pose for this frame. speed: ground speed; airborne + vertical speed; steer -1..1
func animate(_delta: float, speed: float, airborne: bool, _vertical_speed: float, steer: float) -> void:
	if airborne != _airborne:
		_airborne = airborne
		_anim.play("jump" if airborne else "run", BLEND)
	_anim.speed_scale = maxf(speed, 1.0) / RUN_PACE if not airborne else 1.0
	_model.rotation.z = -steer * 0.25 # lean into turns
