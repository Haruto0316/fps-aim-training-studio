extends RefCounted

const Store = preload("res://scripts/persistence/json_store.gd")
const STATIC_CLICKING := "res://resources/scenarios/static_clicking.json"
const MOVEMENT_PRACTICE := "res://resources/scenarios/movement_practice.json"
const STRAFE_ELIMINATION := "res://resources/scenarios/strafe_elimination.json"
const TRACKING_CARBINE := "res://resources/presets/tracking_carbine.json"
const MOBILE_DRILLS := ["strafe_tracking", "cover_tracking", "movement_tracking", "elimination_training"]
const FIXED_TRACKING := ["smooth_tracking", "reactive_tracking"]
const TARGET_GROUPS := ["multi_target", "target_switching"]
const APEX_HUMANOID := "apex_humanoid"
const HUMANOID_HEIGHT_LIMITS := [0.8, 2.6, 0.05]
const STANDARD_DRILLS := ["multi_target", "smooth_tracking", "reactive_tracking", "target_switching"]
const SMOOTH_PATTERNS := {"horizontal": "左右", "vertical": "上下", "circle": "円運動"}
const COUNT_LIMITS := [2, 8, 1]
const SPEED_LIMITS := [0.1, 10.0, 0.1]
const Player = preload("res://scripts/movement/player_body.gd")
const TARGET_LIMITS := {
	"radius": [0.08, 0.65, 0.01],
	"x_extent": [0.25, 4.0, 0.05],
	"y_extent": [0.15, 1.25, 0.05]
}
const DURATION_LIMITS := [5, 180]
const RECOIL_PRESETS := {"なし": 0.0, "小": 1.0, "中": 1.5, "大": 2.0}


static func load_static(path := STATIC_CLICKING) -> Dictionary:
	return _load(path, "static_clicking", false)


static func load_apex_humanoid() -> Dictionary:
	return _load("res://resources/scenarios/apex_humanoid.json", APEX_HUMANOID, false)


static func load_movement(path := MOVEMENT_PRACTICE) -> Dictionary:
	return _load(path, "movement_practice", true)


static func load_strafe(path := STRAFE_ELIMINATION) -> Dictionary:
	return _load_armed(path, "strafe_elimination")


static func load_mobile_drill(id: String) -> Dictionary:
	if id not in MOBILE_DRILLS:
		return {}
	return _load_armed("res://resources/scenarios/%s.json" % id, id)


static func load_standard_drill(id: String) -> Dictionary:
	if id not in STANDARD_DRILLS:
		return {}
	var path := "res://resources/scenarios/%s.json" % id
	return _load_armed(path, id, false) if id in FIXED_TRACKING else _load(path, id, false)


static func _load_armed(path: String, scenario_type: String, movement := true) -> Dictionary:
	var data := _load(path, scenario_type, movement)
	if data.is_empty():
		return data
	var weapon: Dictionary = data.weapon
	if not normalize_weapon(weapon):
		return {}
	var target: Dictionary = data.target
	target.health = int(Store.number(target.get("health"), 125, 1, 20000))
	target.speed = Store.number(target.get("speed"), 3.1, 0.1, 10.0)
	target.acceleration = Store.number(target.get("acceleration"), 18, 0.1, 100.0)
	target.respawn_seconds = Store.number(target.get("respawn_seconds"), 0.65, 0.0, 10.0)
	if scenario_type in MOBILE_DRILLS:
		_validate_mobile_target(target, scenario_type)
	elif scenario_type in FIXED_TRACKING:
		target.track_aim = true
		if scenario_type == "smooth_tracking":
			target.behavior = _smooth_pattern(target.get("behavior"))
		else:
			target.behavior = "reactive"
			target.turn_min = Store.number(target.get("turn_min"), 0.24, 0.15, 5.0)
			target.turn_max = Store.number(target.get("turn_max"), 0.75, target.turn_min, 5.0)
			target.speed_min_factor = Store.number(target.get("speed_min_factor"), 0.55, 0.05, 1.0)
	data.scoring.points_per_elimination = int(Store.number(data.scoring.get("points_per_elimination"), 250, 0, 10000))
	return data


static func normalize_weapon(weapon: Dictionary) -> bool:
	if weapon.get("fire_mode") not in ["single", "automatic"]:
		return false
	var integers := {"damage": [25, 1, 1000], "rounds_per_minute": [600, 60, 1500]}
	for key: String in integers:
		var bounds: Array = integers[key]
		weapon[key] = int(Store.number(weapon.get(key), bounds[0], bounds[1], bounds[2]))
	var scalars := {
		"ads_zoom": [1.5, 1.0, 4.0],
		"ads_sensitivity": [0.75, 0.1, 2.0], "spread_degrees": [0.0, 0.0, 10.0],
		"ads_spread_multiplier": [0.45, 0.0, 1.0], "ads_recoil_multiplier": [0.65, 0.0, 1.0]
	}
	for key: String in scalars:
		var bounds: Array = scalars[key]
		weapon[key] = Store.number(weapon.get(key), bounds[0], bounds[1], bounds[2])
	weapon.recoil_enabled = weapon.get("recoil_enabled", false) == true
	var recoil_multiplier: Variant = weapon.get("recoil_multiplier", 1.0)
	if weapon.recoil_enabled and recoil_multiplier in [RECOIL_PRESETS["中"], RECOIL_PRESETS["大"]]:
		weapon.recoil_multiplier = float(recoil_multiplier)
	else:
		# Keep the existing profile and personal-best key for off and light recoil.
		weapon.erase("recoil_multiplier")
	var pattern: Variant = weapon.get("recoil_degrees", [])
	if not pattern is Array or pattern.size() > 32:
		return false
	for pair: Variant in pattern:
		if not pair is Array or pair.size() != 2:
			return false
		pair[0] = Store.number(pair[0], 0.0, -10.0, 10.0)
		pair[1] = Store.number(pair[1], 0.0, -10.0, 10.0)
	weapon.recoil_degrees = pattern
	return true


static func _validate_mobile_target(target: Dictionary, scenario_type: String) -> void:
	target.track_aim = target.get("track_aim", scenario_type != "elimination_training") == true
	var fallback := "jump" if scenario_type == "movement_tracking" else "strafe"
	var behavior: Variant = target.get("behavior", fallback)
	target.behavior = behavior if behavior in ["strafe", "jump"] else fallback
	if target.behavior != "jump":
		return
	target.jump_height = Store.number(target.get("jump_height"), 0.95, 0.1, 1.5)
	target.jump_seconds = Store.number(target.get("jump_seconds"), 0.65, 0.2, 2.0)
	target.jump_gap_min = Store.number(target.get("jump_gap_min"), 0.45, 0.1, 5.0)
	target.jump_gap_max = Store.number(target.get("jump_gap_max"), 1.05, target.jump_gap_min, 5.0)
	target.turn_min = Store.number(target.get("turn_min"), 0.4, 0.15, 5.0)
	target.turn_max = Store.number(target.get("turn_max"), 1.2, target.turn_min, 5.0)


static func _load(path: String, scenario_type: String, movement: bool) -> Dictionary:
	var data := Store.read(path)
	if data.get("schema_version") != 1 or data.get("type") != scenario_type:
		return {}
	for key: String in ["id", "name", "description", "difficulty"]:
		if not data.get(key) is String or data[key].is_empty():
			return {}
	for key: String in ["player", "map", "target", "weapon", "scoring"]:
		if not data.get(key) is Dictionary:
			return {}
	var spawn: Variant = data.player.get("position")
	if not spawn is Array or spawn.size() != 3:
		return {}
	if data.weapon.has("preset"):
		if data.weapon.preset != "tracking_carbine":
			return {}
		var preset := Store.read(TRACKING_CARBINE)
		if preset.is_empty():
			return {}
		preset.merge(data.weapon, true)
		preset.erase("preset")
		data.weapon = preset
	if data.player.get("movement_enabled") != movement or data.weapon.get("type") != "hitscan":
		return {}
	data.player.position = [
		Store.number(spawn[0], 0.0, -0.5, 0.5),
		Store.number(spawn[1], Player.STANDING_EYE, Player.STANDING_EYE if movement else 1.0, 2.2),
		Store.number(spawn[2], 0.0, -0.5, 0.5)
	]
	for entry: Array in [[data.map, "backdrop_color"], [data.target, "color"]]:
		var color: Variant = entry[0].get(entry[1])
		if not color is String or not Color.html_is_valid(color):
			return {}
	if not _validate_obstacles(data.map.get("obstacles", [])):
		return {}
	data.target.depth = Store.number(data.target.get("depth"), 7.5, 7.5, 9.5)
	for obsolete: String in ["magazine", "reload_seconds", "reload_enabled"]:
		data.weapon.erase(obsolete)
	data.weapon.range = Store.number(data.weapon.get("range"), 80.0, 16.0, 200.0)
	data.scoring.points_per_hit = int(Store.number(data.scoring.get("points_per_hit"), 100.0, 1.0, 10000.0))
	return with_options(data, data.get("duration_seconds"), data.target)


static func _validate_obstacles(obstacles: Variant) -> bool:
	if not obstacles is Array or obstacles.size() > 64:
		return false
	for box: Variant in obstacles:
		if not box is Dictionary:
			return false
		if not _valid_vector(box.get("center"), -12.0, 6.0) or not _valid_vector(box.get("size"), 0.01, 12.0):
			return false
		if not box.get("color") is String or not Color.html_is_valid(box.color):
			return false
		box.pitch = Store.number(box.get("pitch"), 0.0, -45.0, 45.0)
	return true


static func _valid_vector(data: Variant, low: float, high: float) -> bool:
	if not data is Array or data.size() != 3:
		return false
	for component: Variant in data:
		if not (component is float or component is int) or not is_finite(float(component)):
			return false
		if component < low or component > high:
			return false
	return true


static func with_options(base: Dictionary, duration: Variant, target_options: Dictionary) -> Dictionary:
	var scenario := base.duplicate(true)
	scenario.duration_seconds = int(Store.number(duration, 30.0, DURATION_LIMITS[0], DURATION_LIMITS[1]))
	var defaults := {"radius": 0.28, "x_extent": 2.7, "y_extent": 1.0}
	for key: String in TARGET_LIMITS:
		var limits: Array = TARGET_LIMITS[key]
		scenario.target[key] = Store.number(target_options.get(key), defaults[key], limits[0], limits[1])
	if scenario.type == APEX_HUMANOID:
		scenario.target.height = Store.number(target_options.get("height"), 1.8, HUMANOID_HEIGHT_LIMITS[0], HUMANOID_HEIGHT_LIMITS[1])
	if scenario.type in TARGET_GROUPS:
		var target: Dictionary = scenario.target
		target.count = int(Store.number(target_options.get("count"), 4, COUNT_LIMITS[0], COUNT_LIMITS[1]))
		var half_spacing: float = target.radius + 0.045
		var columns := group_columns(target.count)
		var above_floor: float = target.radius + 0.055 + 2.0 * half_spacing - player_position(scenario).y
		target.x_extent = maxf(target.x_extent, _round_extent_up((columns - 1) * half_spacing))
		target.y_extent = maxf(target.y_extent, _round_extent_up(maxf(half_spacing, above_floor)))
	if scenario.type in MOBILE_DRILLS or scenario.type in FIXED_TRACKING:
		scenario.target.speed = Store.number(target_options.get("speed"), base.target.get("speed", 3.1), SPEED_LIMITS[0], SPEED_LIMITS[1])
	if scenario.type == "smooth_tracking":
		scenario.target.behavior = _smooth_pattern(target_options.get("behavior", base.target.get("behavior")))
	return scenario


static func group_columns(count: int) -> int:
	return ceili((count + 1) / 2.0)


static func _round_extent_up(value: float) -> float:
	return snappedf(ceilf(value / 0.05) * 0.05, 0.05)


static func _smooth_pattern(value: Variant) -> String:
	return value if SMOOTH_PATTERNS.has(value) else "horizontal"


static func player_position(scenario: Dictionary) -> Vector3:
	var xyz: Array = scenario.player.position
	return Vector3(xyz[0], xyz[1], xyz[2])


static func record_key(scenario: Dictionary) -> String:
	# Keep identical options together even if the source JSON field order changes.
	if scenario.get("type") == "custom":
		var conditions := scenario.duplicate()
		conditions.erase("name")
		conditions.erase("description")
		return JSON.stringify(conditions).sha256_text()
	return JSON.stringify(scenario).sha256_text()


static func legacy_unlimited_record_key(scenario: Dictionary) -> String:
	if scenario.type != "custom" and not scenario.target.has("health"):
		return ""
	# Unlimited runs with the former default magazine fields used the same firing rules.
	var conditions := scenario.duplicate(true)
	conditions.weapon.merge({"magazine": 20, "reload_seconds": 1.25, "reload_enabled": false})
	return record_key(conditions)
