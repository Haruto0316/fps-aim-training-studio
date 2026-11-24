extends RefCounted

const Draft = preload("res://scripts/editor/editor_draft.gd")

var curve := Curve3D.new()
var length: float
var loop: bool


func _init(entry: Dictionary, objects: Array) -> void:
	var positions := {}
	for object: Dictionary in objects:
		if object.kind == "route_point":
			positions[object.id] = Draft.vector(object.position)
	var points: Array[Vector3] = []
	for id: int in entry.get("route_points", []):
		if positions.has(id) and (points.is_empty() or not points.back().is_equal_approx(positions[id])):
			points.append(positions[id])
	if points.size() < 2:
		return
	loop = entry.get("route_loop", false)
	if loop and points.back().is_equal_approx(points.front()):
		points.pop_back()
	if points.size() < 2:
		return
	curve.bake_interval = 0.15
	curve.up_vector_enabled = false
	var count := points.size()
	for index in range(count + int(loop)):
		var current := index % count
		var tangent := Vector3.ZERO
		if entry.get("route_curve", false):
			var before := posmod(current - 1, count) if loop else maxi(0, current - 1)
			var after := (current + 1) % count if loop else mini(count - 1, current + 1)
			tangent = (points[after] - points[before]) / 6.0
		curve.add_point(points[current], -tangent, tangent)
	length = curve.get_baked_length()


func position_at(distance: float) -> Vector3:
	if length <= 0.0:
		return Vector3.ZERO
	var offset := fposmod(distance, length) if loop else pingpong(distance, length)
	return curve.sample_baked(offset)
