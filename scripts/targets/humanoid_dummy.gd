extends StaticBody3D

const LABELS := {"head": "頭", "upper_body": "上半身", "lower_body": "下半身"}


func _init(height: float, paint: Color) -> void:
	collision_layer = 2
	collision_mask = 0
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	hide()
	_add_part("head", height, Vector3(0, 0.919, 0), 0.081, 0.162, paint.lightened(0.28))
	_add_part("upper_body", height, Vector3(0, 0.65, 0), 0.12, 0.36, paint)
	for side: float in [-1.0, 1.0]:
		_add_part("upper_body", height, Vector3(side * 0.15, 0.63, 0), 0.048, 0.31, paint.darkened(0.05))
		_add_part("lower_body", height, Vector3(side * 0.065, 0.255, 0), 0.057, 0.51, paint.darkened(0.21))


func hit_region(shape_index: int) -> String:
	var part := shape_owner_get_owner(shape_find_owner(shape_index))
	return part.get_meta(&"hit_region")


func _add_part(region: String, scale_m: float, center: Vector3, radius: float, length: float, paint: Color) -> void:
	var capsule := CapsuleShape3D.new()
	capsule.radius = radius * scale_m
	capsule.height = length * scale_m
	var collider := CollisionShape3D.new()
	collider.position = center * scale_m
	collider.shape = capsule
	collider.set_meta(&"hit_region", region)
	add_child(collider)

	var mesh := CapsuleMesh.new()
	mesh.radius = capsule.radius
	mesh.height = capsule.height
	mesh.radial_segments = 24
	mesh.rings = 12
	var material := StandardMaterial3D.new()
	material.albedo_color = paint
	material.emission_enabled = true
	material.emission = paint
	material.emission_energy_multiplier = 0.23
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = collider.position
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
