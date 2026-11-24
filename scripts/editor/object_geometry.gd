extends RefCounted


static func mesh_for(shape: String) -> PrimitiveMesh:
	match shape:
		"sphere":
			var mesh := SphereMesh.new()
			mesh.radial_segments = 24
			mesh.rings = 12
			return mesh
		"capsule":
			var mesh := CapsuleMesh.new()
			mesh.height = 2.0
			mesh.radial_segments = 24
			mesh.rings = 8
			return mesh
	return BoxMesh.new()


static func collision_for(mesh: PrimitiveMesh, size: Vector3) -> Shape3D:
	if mesh is BoxMesh:
		var box := BoxShape3D.new()
		box.size = size
		return box
	var points: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var scale := size / mesh.get_aabb().size
	for index in range(points.size()):
		points[index] *= scale
	var convex := ConvexPolygonShape3D.new()
	convex.points = points
	return convex
