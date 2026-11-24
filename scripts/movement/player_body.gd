extends CharacterBody3D

const BODY_RADIUS := 0.32
const STANDING_HEIGHT := 1.8
const CROUCH_HEIGHT := 1.12
const STANDING_EYE := 1.65
const CROUCH_EYE := 0.98
const EYE_CEILING_MARGIN := 0.10

var tuning: Dictionary
var crouched := false
var sprinting := false
var sliding := false
var slide_elapsed := 0.0
var eye_height := STANDING_EYE
var collider: CollisionShape3D
var standing_shape := CapsuleShape3D.new()
var crouched_shape := CapsuleShape3D.new()
var headroom := PhysicsShapeQueryParameters3D.new()
var ceiling_probe := PhysicsRayQueryParameters3D.new()
var eye_ceiling := STANDING_EYE


var world_mask := 1


func _ready() -> void:
	collision_layer = 4
	collision_mask = world_mask
	floor_snap_length = 0.28
	floor_constant_speed = true
	standing_shape.radius = BODY_RADIUS
	standing_shape.height = STANDING_HEIGHT
	crouched_shape.radius = BODY_RADIUS
	crouched_shape.height = CROUCH_HEIGHT
	collider = CollisionShape3D.new()
	add_child(collider)
	_set_stance(false)
	headroom.shape = standing_shape
	headroom.collision_mask = collision_mask
	ceiling_probe.collision_mask = collision_mask


func step(delta: float, wish: Vector3, sprint: bool, crouch: bool, slide_pressed: bool, jump: bool) -> void:
	var ground := is_on_floor()
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if ground and sprinting and crouch and slide_pressed and horizontal.length() >= tuning.slide_min_speed:
		sliding = true
		slide_elapsed = 0.0
		horizontal += horizontal.normalized() * float(tuning.slide_boost)
	if sliding and (not ground or not crouch or jump):
		sliding = false
	if crouched != (crouch or sliding):
		if crouch or sliding or _can_stand():
			_set_stance(crouch or sliding)

	sprinting = ground and not crouched and sprint and not wish.is_zero_approx()
	if ground and not sliding:
		var speed: float = tuning.crouch_speed if crouched else (tuning.sprint_speed if sprinting else tuning.walk_speed)
		if wish.is_zero_approx():
			var braking: float = tuning.deceleration + tuning.ground_friction * horizontal.length()
			horizontal = horizontal.move_toward(Vector3.ZERO, braking * delta)
		else:
			var rate: float = tuning.acceleration if horizontal.length() <= speed else tuning.deceleration
			horizontal = horizontal.move_toward(wish * speed, rate * delta)
	elif sliding:
		var direction := horizontal.normalized()
		var slope_gravity := Vector3.DOWN.slide(get_floor_normal()) * float(tuning.gravity)
		var speed := maxf(0.0, horizontal.length() + (slope_gravity.dot(direction) - float(tuning.slide_friction)) * delta)
		horizontal = direction * speed
		slide_elapsed += delta
		if speed <= tuning.slide_min_speed or slide_elapsed >= tuning.slide_max_seconds:
			sliding = false
	elif not wish.is_zero_approx():
		var air_speed := maxf(horizontal.length(), tuning.walk_speed)
		horizontal = horizontal.move_toward(wish * air_speed, tuning.air_acceleration * tuning.air_control * delta)

	var lift := -0.1 if ground else velocity.y - float(tuning.gravity) * delta
	if ground and jump:
		lift = tuning.jump_speed
		sprinting = false
	velocity = Vector3(horizontal.x, lift, horizontal.z)
	move_and_slide()
	if not is_on_floor():
		sliding = false
	_update_eye_ceiling()


func view_position(delta: float) -> Vector3:
	var eye_goal := CROUCH_EYE if crouched else STANDING_EYE
	eye_height = minf(move_toward(eye_height, eye_goal, tuning.eye_speed * delta), eye_ceiling)
	return get_global_transform_interpolated().origin + Vector3.UP * eye_height


func mode_label() -> String:
	if not is_on_floor():
		return "空中"
	if sliding:
		return "スライド"
	if crouched:
		return "しゃがみ"
	if sprinting:
		return "スプリント"
	return "地上"


func _set_stance(low: bool) -> void:
	crouched = low
	var capsule := crouched_shape if low else standing_shape
	collider.shape = capsule
	collider.position.y = capsule.height * 0.5


func _can_stand() -> bool:
	var center := global_position + Vector3.UP * (STANDING_HEIGHT * 0.5 + 0.008)
	headroom.transform = Transform3D(Basis.IDENTITY, center)
	return get_world_3d().direct_space_state.intersect_shape(headroom, 1).is_empty()


func _update_eye_ceiling() -> void:
	eye_ceiling = STANDING_EYE
	if not crouched or eye_height <= CROUCH_EYE:
		return
	# The capsule is already low enough to enter, but the camera may still be lowering.
	ceiling_probe.from = global_position + Vector3.UP * CROUCH_EYE
	ceiling_probe.to = global_position + Vector3.UP * (eye_height + EYE_CEILING_MARGIN)
	var roof := get_world_3d().direct_space_state.intersect_ray(ceiling_probe)
	if not roof.is_empty():
		eye_ceiling = maxf(CROUCH_EYE, roof.position.y - global_position.y - EYE_CEILING_MARGIN)
