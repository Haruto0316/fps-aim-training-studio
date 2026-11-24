extends RefCounted

var tuning: Dictionary
var center: Vector3
var bounds: Vector2
var offset := Vector2.ZERO
var velocity := Vector2.ZERO
var turn_wait := 0.0
var phase := 0.0


func _init(profile: Dictionary) -> void:
	tuning = profile


func spawn(eye: Vector3, rng: RandomNumberGenerator) -> Vector3:
	center = eye + Vector3.FORWARD * float(tuning.depth)
	var vertical: float = tuning.y_extent
	if tuning.get("keep_above_floor", true):
		vertical = minf(vertical, eye.y - tuning.radius - 0.055)
	bounds = Vector2(tuning.x_extent, vertical)
	offset = Vector2.ZERO
	phase = rng.randf_range(0.0, TAU)
	turn_wait = 0.0
	return step(0.0, rng)


func step(delta: float, rng: RandomNumberGenerator) -> Vector3:
	if tuning.behavior == "reactive":
		turn_wait -= delta
		if turn_wait <= 0.0:
			var speed := rng.randf_range(tuning.speed_min_factor, 1.0) * float(tuning.speed)
			velocity = Vector2.from_angle(rng.randf_range(0.0, TAU)) * speed
			turn_wait = rng.randf_range(tuning.turn_min, tuning.turn_max)
		offset += velocity * delta
		for axis in range(2):
			if absf(offset[axis]) > bounds[axis]:
				offset[axis] = clampf(offset[axis], -bounds[axis], bounds[axis])
				velocity[axis] *= -1.0
	else:
		var amplitude := minf(bounds.x, bounds.y)
		match tuning.behavior:
			"horizontal":
				amplitude = bounds.x
			"vertical":
				amplitude = bounds.y
		phase = fposmod(phase + delta * float(tuning.speed) / amplitude, TAU)
		match tuning.behavior:
			"horizontal":
				offset = Vector2(sin(phase) * bounds.x, 0)
			"vertical":
				offset = Vector2(0, sin(phase) * bounds.y)
			"circle":
				offset = Vector2(cos(phase), sin(phase)) * amplitude
	return center + Vector3(offset.x, offset.y, 0)
