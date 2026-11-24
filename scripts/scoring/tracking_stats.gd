extends RefCounted

const Hitscan = preload("res://scripts/weapons/hitscan.gd")
const WORLD_MASK := 1

var visible_seconds := 0.0
var aimed_seconds := 0.0
var streak_start := -1
var last_hit := -1
var longest_usec := 0


func sample(camera: Camera3D, target: StaticBody3D, radius: float, reach: float, delta: float) -> void:
	var world := camera.get_world_3d()
	var eye := camera.global_position
	var aim := Hitscan.trace(world, eye, -camera.global_basis.z, reach)
	var on_target: bool = aim.get("collider") == target
	if not on_target and not _visible(world, eye, target.global_position, radius, reach):
		return
	visible_seconds += delta
	if on_target:
		aimed_seconds += delta


func shot(hit: bool, timestamp: int, continuity_usec: int) -> void:
	if not hit:
		streak_start = -1
		last_hit = -1
		return
	if last_hit < 0 or timestamp - last_hit > continuity_usec:
		streak_start = timestamp
	last_hit = timestamp
	longest_usec = maxi(longest_usec, timestamp - streak_start)


func accuracy() -> Variant:
	return 100.0 * aimed_seconds / visible_seconds if visible_seconds > 0.0 else null


func _visible(world: World3D, eye: Vector3, center: Vector3, radius: float, reach: float) -> bool:
	if _clear(world, eye, center, reach):
		return true
	# Sample just inside the silhouette so a partially exposed target is eligible.
	var heading := (center - eye).normalized()
	var lateral := heading.cross(Vector3.UP).normalized()
	if lateral.is_zero_approx():
		lateral = Vector3.RIGHT
	var vertical := lateral.cross(heading)
	for direction: Vector3 in [lateral, -lateral, vertical, -vertical]:
		if _clear(world, eye, center + direction * radius * 0.82, reach):
			return true
	return false


func _clear(world: World3D, eye: Vector3, point: Vector3, reach: float) -> bool:
	var offset := point - eye
	var distance := offset.length()
	return distance <= reach and (is_zero_approx(distance)
		or Hitscan.trace(world, eye, offset / distance, distance, WORLD_MASK).is_empty())
