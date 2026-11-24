extends RefCounted

var tuning: Dictionary
var health: int
var lateral_velocity := 0.0
var direction := 1.0
var base_y := 0.0
var jump_remaining := 0.0
var jump_wait := 0.0
var turn_wait := 0.0
var jumps := false


func _init(profile: Dictionary) -> void:
	tuning = profile
	jumps = tuning.get("behavior") == "jump"


func spawn(initial_direction: float) -> void:
	health = tuning.health
	lateral_velocity = 0.0
	direction = initial_direction


func hit(damage: int) -> bool:
	health = maxi(0, health - damage)
	return health == 0


func reset_motion(height: float, random: RandomNumberGenerator) -> void:
	base_y = height
	jump_remaining = 0.0
	if jumps:
		jump_wait = random.randf_range(tuning.jump_gap_min, tuning.jump_gap_max)
		turn_wait = random.randf_range(tuning.turn_min, tuning.turn_max)


func step(position: Vector3, center: float, delta: float, random: RandomNumberGenerator) -> Vector3:
	if jumps:
		turn_wait -= delta
		if turn_wait <= 0.0:
			direction *= -1.0
			turn_wait = random.randf_range(tuning.turn_min, tuning.turn_max)
		if jump_remaining > 0.0:
			jump_remaining = maxf(0.0, jump_remaining - delta)
		else:
			jump_wait -= delta
			if jump_wait <= 0.0:
				jump_remaining = tuning.jump_seconds
				jump_wait = random.randf_range(tuning.jump_gap_min, tuning.jump_gap_max)
		var t := jump_remaining / float(tuning.jump_seconds)
		position.y = base_y + 4.0 * float(tuning.jump_height) * t * (1.0 - t)
	position.x = next_x(position.x, center, delta)
	return position


func next_x(x: float, center: float, delta: float) -> float:
	var limit: float = center + direction * tuning.x_extent
	var remaining := absf(limit - x)
	var braking_speed := sqrt(2.0 * float(tuning.acceleration) * remaining)
	var speed := minf(tuning.speed, braking_speed)
	lateral_velocity = move_toward(lateral_velocity, direction * speed, tuning.acceleration * delta)
	var next := x + lateral_velocity * delta
	if (limit - next) * direction <= 0.0 or remaining < 0.001:
		direction *= -1.0
		lateral_velocity = 0.0
		return limit
	var extent: float = tuning.x_extent
	return clampf(next, center - extent, center + extent)
