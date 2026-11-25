extends RefCounted

var shots := 0
var hits := 0
var reaction_total_usec := 0
var reactions := 0
var eliminations := 0
var elimination_total_usec := 0
var points_per_hit: int
var hit_points := 0
var points_per_elimination: int


func _init(points: int, bonus := 0) -> void:
	points_per_hit = points
	points_per_elimination = bonus


func register_shot(hit: bool, reaction_usec: int, points := -1) -> void:
	shots += 1
	if hit:
		hits += 1
		hit_points += points_per_hit if points < 0 else points
		if reaction_usec >= 0:
			reactions += 1
			reaction_total_usec += reaction_usec


func register_elimination(elapsed_usec: int) -> void:
	eliminations += 1
	elimination_total_usec += maxi(0, elapsed_usec)


func score() -> int:
	return hit_points + eliminations * points_per_elimination


func accuracy() -> float:
	return hits * 100.0 / shots if shots > 0 else 0.0


func snapshot() -> Dictionary:
	return {
		"shots": shots,
		"hits": hits,
		"misses": shots - hits,
		"score": score(),
		"accuracy": accuracy(),
		"reaction_ms": reaction_total_usec / (1000.0 * reactions) if reactions > 0 else null,
		"eliminations": eliminations,
		"elimination_ms": elimination_total_usec / (1000.0 * eliminations) if eliminations > 0 else null
	}
