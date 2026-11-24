extends Camera3D

var degrees_per_count := Vector2.ZERO
var gain := 1.0
var yaw := 0.0
var pitch := 0.0


func apply_motion(unscaled_motion: Vector2) -> void:
	apply_angles(-unscaled_motion * degrees_per_count * gain)


func apply_angles(degrees: Vector2) -> void:
	yaw = wrapf(yaw + degrees.x, -180.0, 180.0)
	pitch = clampf(pitch + degrees.y, -89.0, 89.0)
	rotation = Vector3(deg_to_rad(pitch), deg_to_rad(yaw), 0.0)
