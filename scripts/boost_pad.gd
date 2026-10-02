extends Area3D
## A boost pad on the floor: run over it and you're shot forward (the runner's speed kicked up,
## easing back off). Faces -Z (the way it boosts) unless rotated.

const SIZE := Vector3(3.0, 0.1, 3.5)


func _ready() -> void:
	var shape := BoxShape3D.new()
	shape.size = Vector3(SIZE.x, 1.2, SIZE.z)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position.y = 0.6
	add_child(collider)
	var plane := PlaneMesh.new()
	plane.size = Vector2(SIZE.x, SIZE.z)
	var view := MeshInstance3D.new()
	view.mesh = plane
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/boost_pad.gdshader")
	view.material_override = material
	view.position.y = 0.015
	add_child(view)
	body_entered.connect(func(body: Node3D):
		if body.has_method("boost"):
			body.boost()
	)
