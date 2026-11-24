extends RefCounted

const Arena = preload("res://scripts/training/arena.gd")
const Draft = preload("res://scripts/editor/editor_draft.gd")
const Route = preload("res://scripts/scenarios/route_path.gd")
const Motion = preload("res://scripts/targets/fixed_tracking_motion.gd")
const Stats = preload("res://scripts/scoring/run_stats.gd")
const Hitscan = preload("res://scripts/weapons/hitscan.gd")
const Player = preload("res://scripts/movement/player_body.gd")

var spawn_eye := Vector3.UP * Player.STANDING_EYE
var yaw := 0.0
var targets := {}
var areas := {}
var rng: RandomNumberGenerator
var alive := 0
var ready_count := 0


func _init(arena: Arena, document: Dictionary, random: RandomNumberGenerator) -> void:
	rng = random
	var found_player := false
	for entry: Dictionary in document.objects:
		match entry.kind:
			"player_start":
				if not found_player:
					var feet := Draft.vector(entry.position) - Vector3.UP * (float(entry.size[1]) * 0.5)
					if document.player.movement_enabled:
						feet.x = clampf(feet.x, -document.map.width * 0.5 + 0.4, document.map.width * 0.5 - 0.4)
						feet.z = clampf(feet.z, -document.map.depth * 0.5 + 0.4, document.map.depth * 0.5 - 0.4)
					spawn_eye = feet + Vector3.UP * Player.STANDING_EYE
					yaw = entry.rotation[1]
					found_player = true
			"spawn_area":
				areas[entry.id] = entry
			"route_point":
				pass
			_:
				var is_target := Draft.is_target(entry.kind)
				var body := arena.create_custom_object(entry, is_target)
				if is_target:
					_add_target(body, entry, document.objects)


func _add_target(body: StaticBody3D, entry: Dictionary, objects: Array) -> void:
	var path := Route.new(entry, objects)
	var motion: Motion
	if path.length <= 0.0 and entry.behavior == "reactive":
		motion = Motion.new({
			"behavior": "reactive", "speed": entry.speed, "depth": 0.0, "x_extent": entry.amplitude,
			"y_extent": entry.amplitude, "keep_above_floor": false, "speed_min_factor": 0.55,
			"turn_min": 0.24, "turn_max": 0.75
		})
	targets[body] = {
		"entry": entry, "path": path, "motion": motion, "origin": body.position, "since": -1,
		"ready": false, "health": 0, "first": true,
		"spawn_at": roundi(float(entry.spawn_delay) * 1000000.0) if entry.spawn_rule == "delayed" else 0
	}


func step(now: int, delta: float) -> void:
	for body: StaticBody3D in targets:
		var state: Dictionary = targets[body]
		if state.since < 0:
			if now >= state.spawn_at:
				_spawn(body, state, now)
			continue
		if not state.ready:
			state.ready = true
			ready_count += 1
		var age := (now - int(state.since)) / 1000000.0
		var entry: Dictionary = state.entry
		var next: Vector3 = state.origin
		if state.path.length > 0.0:
			next = state.path.position_at(age * entry.speed)
		elif state.motion != null:
			next = state.motion.step(delta, rng)
		else:
			var wave := sin(age * float(entry.speed) / float(entry.amplitude)) * float(entry.amplitude)
			match entry.behavior:
				"strafe":
					next.x += wave
				"vertical":
					next.y += wave
				"jump":
					next.y += absf(wave)
		if next != body.position:
			body.position = next
			body.force_update_transform()


func _spawn(body: StaticBody3D, state: Dictionary, now: int) -> void:
	var entry: Dictionary = state.entry
	var home := Draft.vector(entry.position)
	var area: Dictionary = areas.get(entry.spawn_area_id, {})
	if state.path.length > 0.0:
		home = state.path.position_at(0.0)
	elif not area.is_empty():
		var unit := Vector3(rng.randf_range(-0.5, 0.5), rng.randf_range(-0.5, 0.5), rng.randf_range(-0.5, 0.5))
		var basis := Basis.from_euler(Draft.vector(area.rotation) * (PI / 180.0))
		home = Draft.vector(area.position) + basis * (Draft.vector(area.size) * unit)
	if state.motion != null:
		state.motion.spawn(home, rng)
	state.origin = home
	state.since = now
	state.ready = false
	state.health = entry.health
	state.first = true
	body.position = home
	body.collision_layer = 2
	body.force_update_transform()
	body.show()
	alive += 1


func shot(world: World3D, sample: Dictionary, weapon: Dictionary, stats: Stats) -> bool:
	var hit := Hitscan.trace(world, sample.origin, sample.direction, weapon.range)
	var body: Variant = hit.get("collider")
	var state: Dictionary = targets.get(body, {})
	if state.is_empty() or state.since < 0 or sample.time < state.since:
		stats.register_shot(false, -1)
		return false
	stats.register_shot(true, int(sample.time) - int(state.since) if state.first else -1)
	state.first = false
	state.health = maxi(0, int(state.health) - int(weapon.damage))
	if state.health == 0:
		stats.register_elimination(int(sample.time) - int(state.since))
		state.since = -1
		ready_count -= int(state.ready)
		state.ready = false
		state.spawn_at = int(sample.time) + roundi(float(state.entry.respawn) * 1000000.0)
		body.hide()
		body.collision_layer = 0
		alive -= 1
	return true
