extends RefCounted


static func trace(world: World3D, origin: Vector3, direction: Vector3, distance: float, mask := 3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * distance, mask)
	return world.direct_space_state.intersect_ray(query)
