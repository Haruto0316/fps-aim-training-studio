extends RefCounted

const Store = preload("res://scripts/persistence/json_store.gd")
const Draft = preload("res://scripts/editor/editor_draft.gd")
const Scenario = preload("res://scripts/scenarios/scenario.gd")
const DIRECTORY := "user://scenarios"
const OBJECT_LIMIT := 256
const ROUTE_LIMIT := 64


static func load_file(path: String) -> Dictionary:
	return validate(Store.read_saved(path))


static func save(data: Dictionary, directory := DIRECTORY) -> Error:
	var document := validate(data)
	if document.is_empty():
		return ERR_INVALID_DATA
	var error := DirAccess.make_dir_recursive_absolute(directory)
	if error != OK:
		return error
	return Store.write(directory.path_join(document.id + ".json"), document, true)


static func catalogue(directory := DIRECTORY) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not DirAccess.dir_exists_absolute(directory):
		return result
	var ids := {}
	for file: String in DirAccess.get_files_at(directory):
		var name := file.trim_suffix(".bak")
		if name.get_extension() != "json" or not valid_id(name.get_basename()):
			continue
		ids[name.get_basename()] = true
	for id: String in ids:
		var entry := load_file(directory.path_join(id + ".json"))
		if not entry.is_empty() and entry.id == id:
			result.append(entry)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.name.naturalnocasecmp_to(b.name) < 0
	)
	return result


static func remove_saved(id: String, directory := DIRECTORY) -> Error:
	if not valid_id(id):
		return ERR_INVALID_PARAMETER
	var path := directory.path_join(id + ".json")
	var has_primary := FileAccess.file_exists(path)
	if FileAccess.file_exists(path + ".bak"):
		var error := DirAccess.remove_absolute(path + ".bak")
		if error != OK:
			return error
		if not has_primary:
			return OK
	return DirAccess.remove_absolute(path)


static func valid_id(id: Variant) -> bool:
	if not id is String or id.length() != 32:
		return false
	for character: String in id:
		if not "0123456789abcdef".contains(character):
			return false
	return true


static func validate(raw: Dictionary) -> Dictionary:
	if raw.get("schema_version") != 1 or raw.get("type") != "custom" or not valid_id(raw.get("id")):
		return {}
	if not raw.get("name") is String or raw.name.strip_edges().is_empty():
		return {}
	for key: String in ["player", "map", "weapon", "scoring"]:
		if not raw.get(key) is Dictionary:
			return {}
	if not raw.get("objects") is Array or raw.objects.size() > OBJECT_LIMIT:
		return {}
	if not _valid_color(raw.map.get("background")):
		return {}
	var catalog := {}
	var objects: Array[Dictionary] = []
	for value: Variant in raw.objects:
		if not value is Dictionary:
			return {}
		var entry := _object(value)
		if entry.is_empty() or catalog.has(entry.id):
			return {}
		catalog[entry.id] = entry.kind
		objects.append(entry)
	for entry: Dictionary in objects:
		if not Draft.is_target(entry.kind):
			continue
		for point: int in entry.route_points:
			if catalog.get(point) != "route_point":
				return {}
		if entry.spawn_area_id != 0 and catalog.get(entry.spawn_area_id) != "spawn_area":
			return {}
	var weapon := {}
	var preset := Store.read(Scenario.TRACKING_CARBINE)
	for key: String in preset:
		weapon[key] = raw.weapon.get(key, preset[key])
	weapon = weapon.duplicate(true)
	if weapon.type != "hitscan" or not Scenario.normalize_weapon(weapon):
		return {}
	weapon.range = Store.number(weapon.get("range"), 80.0, 16.0, 200.0)
	var description: Variant = raw.get("description")
	return {
		"schema_version": 1, "type": "custom", "id": raw.id, "name": raw.name.strip_edges().left(64),
		"description": description.left(300) if description is String else "",
		"duration_seconds": int(Store.number(raw.get("duration_seconds"), 60.0, 5.0, 180.0)),
		"player": {"movement_enabled": raw.player.get("movement_enabled", true) == true},
		"weapon": weapon,
		"map": {
			"background": raw.map.background, "light": Store.number(raw.map.get("light"), 0.85, 0.0, 3.0),
			"width": int(Store.number(raw.map.get("width"), 24, 4, 60)),
			"depth": int(Store.number(raw.map.get("depth"), 24, 4, 60))
		},
		"scoring": {
			"points_per_hit": int(Store.number(raw.scoring.get("points_per_hit"), 100, 1, 10000)),
			"points_per_elimination": int(Store.number(raw.scoring.get("points_per_elimination"), 250, 0, 10000))
		},
		"objects": objects
	}


static func _object(raw: Dictionary) -> Dictionary:
	var id := _id_number(raw.get("id"))
	var kind: Variant = raw.get("kind")
	if id == 0 or not kind is String or not Draft.KINDS.has(kind) or not _valid_color(raw.get("color")):
		return {}
	for key: String in ["position", "rotation", "size"]:
		var bounds := [0.05, 40.0] if key == "size" else ([-180.0, 180.0] if key == "rotation" else [-50.0, 50.0])
		if not _vector_valid(raw.get(key), bounds[0], bounds[1]):
			return {}
	var result := {"id": id, "kind": kind, "color": raw.color}
	for key: String in ["position", "rotation", "size"]:
		result[key] = raw[key].map(func(component: Variant) -> float: return float("%.6f" % float(component)))
	if not Draft.is_target(kind):
		return result.duplicate(true)
	for key: String in ["shape", "behavior", "spawn_rule"]:
		var values: Dictionary = {"shape": Draft.SHAPES, "behavior": Draft.BEHAVIORS, "spawn_rule": Draft.SPAWN_RULES}[key]
		if not raw.get(key) is String or not values.has(raw[key]):
			return {}
		result[key] = raw[key]
	var points: Variant = raw.get("route_points", [])
	if not points is Array or points.size() > ROUTE_LIMIT:
		return {}
	var route: Array[int] = []
	for point: Variant in points:
		var point_id := _id_number(point)
		if point_id == 0 or point_id in route:
			return {}
		route.append(point_id)
	result.route_points = route
	result.route_curve = raw.get("route_curve", false) == true
	result.route_loop = raw.get("route_loop", false) == true
	var area: Variant = raw.get("spawn_area_id", 0)
	result.spawn_area_id = _id_number(area)
	if result.spawn_area_id == 0 and area != 0:
		return {}
	result.health = int(Store.number(raw.get("health"), 25.0, 1.0, 20000.0))
	for key: String in ["speed", "respawn", "amplitude", "spawn_delay"]:
		var limits: Array = {"speed": [3.0, 0.1, 15.0], "respawn": [0.65, 0.0, 30.0],
			"amplitude": [1.5, 0.1, 18.0], "spawn_delay": [1.0, 0.0, 60.0]}[key]
		result[key] = Store.number(raw.get(key), limits[0], limits[1], limits[2])
	return result.duplicate(true)


static func _id_number(value: Variant) -> int:
	var number := Store.number(value, 0.0, 0.0, 1000000000.0)
	return int(number) if number > 0.0 and number == value and floorf(number) == number else 0


static func _vector_valid(value: Variant, minimum: float, maximum: float) -> bool:
	if not value is Array or value.size() != 3:
		return false
	for component: Variant in value:
		if not (component is int or component is float) or not is_finite(float(component)):
			return false
		if component < minimum or component > maximum:
			return false
	return true


static func _valid_color(value: Variant) -> bool:
	return value is String and Color.html_is_valid(value)
