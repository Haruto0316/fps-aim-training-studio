extends RefCounted

var tuning: Dictionary
var automatic: bool
var interval_usec: int
var next_shot_at := 0
var shots_fired := 0


func _init(profile: Dictionary) -> void:
	tuning = profile
	automatic = tuning.get("fire_mode") == "automatic"
	var rpm: int = tuning.rounds_per_minute
	interval_usec = ceili(60000000.0 / rpm)


func try_fire(now: int, held_repeat := false) -> bool:
	if now < next_shot_at:
		return false
	# Preserve automatic cadence across physics tick rounding without emitting a backlog.
	var scheduled := next_shot_at if held_repeat and now - next_shot_at < interval_usec else now
	next_shot_at = scheduled + interval_usec
	shots_fired += 1
	return true


func aim_direction(basis: Basis, ads: bool, random: RandomNumberGenerator) -> Vector3:
	var spread: float = tuning.get("spread_degrees", 0.0)
	if ads:
		spread *= float(tuning.ads_spread_multiplier)
	if spread == 0.0:
		return -basis.z
	var disk := Vector2.from_angle(random.randf_range(0.0, TAU)) * sqrt(random.randf())
	var tangent := tan(deg_to_rad(spread))
	return (-basis.z + basis.x * disk.x * tangent + basis.y * disk.y * tangent).normalized()


func recoil(ads: bool) -> Vector2:
	var pattern: Array = tuning.get("recoil_degrees", [])
	if not tuning.get("recoil_enabled", false) or pattern.is_empty() or shots_fired == 0:
		return Vector2.ZERO
	var index := (shots_fired - 1) % pattern.size()
	var pair: Array = pattern[index]
	var multiplier: float = tuning.get("recoil_multiplier", 1.0)
	if ads:
		multiplier *= float(tuning.ads_recoil_multiplier)
	return Vector2(pair[0], pair[1]) * multiplier
