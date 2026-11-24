extends RefCounted

signal changed(id: int)
signal replaced

const Store = preload("res://scripts/persistence/json_store.gd")

const KINDS := {
	"static_target": ["静止ターゲット", [0.65, 0.65, 0.65], "#ff936d"],
	"moving_target": ["移動ターゲット", [0.75, 0.75, 0.75], "#69d4db"],
	"enemy": ["敵 AI", [0.75, 1.55, 0.75], "#f3b971"],
	"wall": ["壁", [3.0, 2.5, 0.38], "#597785"],
	"box": ["箱", [1.5, 1.25, 1.4], "#567480"],
	"pillar": ["柱", [0.85, 2.8, 0.85], "#667e8e"],
	"floor": ["床", [8.0, 0.24, 8.0], "#293d4a"],
	"platform": ["足場", [3.0, 0.32, 2.2], "#607f87"],
	"step": ["段差", [1.8, 0.42, 1.4], "#567982"],
	"player_start": ["プレイヤー開始位置", [0.55, 0.85, 0.55], "#83e0ae"],
	"spawn_area": ["ターゲット出現エリア", [3.0, 1.8, 1.0], "#6caff3"],
	"route_point": ["ルート通過点", [0.35, 0.35, 0.35], "#d3a1f4"]
}
const BEHAVIORS := {"static": "静止", "strafe": "左右移動", "vertical": "上下移動", "reactive": "不規則", "jump": "ジャンプ"}
const SHAPES := {"sphere": "球", "box": "箱", "capsule": "カプセル"}
const SPAWN_RULES := {"immediate": "即時", "delayed": "遅延"}
const HISTORY_LIMIT := 64

var objects: Array[Dictionary] = []
var map := {"background": "#172934", "light": 0.85, "width": 24, "depth": 24}
var config: Dictionary
var saved_key := ""
var undo_stack: Array[Dictionary] = []
var redo_stack: Array[Dictionary] = []
var next_id := 1


func _init(starter := true) -> void:
	var weapon := Store.read("res://resources/presets/tracking_carbine.json")
	config = {
		"schema_version": 1, "type": "custom", "id": new_id(),
		"name": "新しいシナリオ", "description": "", "duration_seconds": 60,
		"player": {"movement_enabled": true}, "weapon": weapon,
		"scoring": {"points_per_hit": 100, "points_per_elimination": 250}
	}
	if starter:
		var floor_id := add("floor", Vector3(0, -0.12, -3))
		edit(floor_id, {"size": [15.0, 0.24, 14.0]})
		add("static_target", Vector3(0, 1.65, -5))
		add("box", Vector3(2.6, 0.625, -4.2))
		undo_stack.clear()
	mark_saved()


static func new_id() -> String:
	return Crypto.new().generate_random_bytes(16).hex_encode()


func document() -> Dictionary:
	var result := config.duplicate(true)
	result.map = map.duplicate()
	result.objects = objects.duplicate(true)
	var kinds := {}
	for entry: Dictionary in objects:
		kinds[entry.id] = entry.kind
	for entry: Dictionary in result.objects:
		if not is_target(entry.kind):
			continue
		entry.route_points = entry.get("route_points", []).filter(
			func(id: int) -> bool: return kinds.get(id) == "route_point"
		)
		if kinds.get(entry.get("spawn_area_id", 0)) != "spawn_area":
			entry.spawn_area_id = 0
	return result


func mark_saved() -> void:
	saved_key = JSON.stringify(document()).sha256_text()


func is_dirty() -> bool:
	return JSON.stringify(document()).sha256_text() != saved_key


func replace(data: Dictionary) -> void:
	config = data.duplicate(true)
	map = config.map
	config.erase("map")
	objects.assign(config.objects)
	config.erase("objects")
	next_id = 1
	for entry: Dictionary in objects:
		next_id = maxi(next_id, int(entry.id) + 1)
	undo_stack.clear()
	redo_stack.clear()
	mark_saved()
	replaced.emit()


static func coordinates(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


static func vector(value: Array) -> Vector3:
	return Vector3(value[0], value[1], value[2])


static func is_target(kind: String) -> bool:
	return kind in ["static_target", "moving_target", "enemy"]


func get_object(id: int) -> Dictionary:
	var index := _index(id)
	return objects[index].duplicate(true) if index >= 0 else {}


func add(kind: String, position: Vector3) -> int:
	if not KINDS.has(kind):
		return 0
	var defaults: Array = KINDS[kind]
	var entry := {
		"id": next_id, "kind": kind, "position": coordinates(position.clamp(Vector3.ONE * -50, Vector3.ONE * 50)),
		"rotation": [0.0, 0.0, 0.0], "size": defaults[1].duplicate(), "color": defaults[2]
	}
	if is_target(kind):
		entry.merge({
			"shape": "capsule" if kind == "enemy" else "sphere",
			"health": 125 if kind == "enemy" else 25,
			"speed": 3.0, "respawn": 0.65, "amplitude": 1.5,
			"behavior": "static" if kind == "static_target" else "strafe",
			"spawn_rule": "immediate", "spawn_delay": 1.0,
			"route_points": [], "route_curve": false, "route_loop": false, "spawn_area_id": 0
		})
	next_id += 1
	_commit({}, entry, objects.size())
	return entry.id


func duplicate_object(id: int) -> int:
	var copy := get_object(id)
	if copy.is_empty():
		return 0
	copy.id = next_id
	next_id += 1
	var position := vector(copy.position)
	position.x = position.x + 0.5 if position.x <= 49.5 else position.x - 0.5
	copy.position = coordinates(position)
	_commit({}, copy, objects.size())
	return copy.id


func remove(id: int) -> void:
	var index := _index(id)
	if index >= 0:
		_commit(objects[index], {}, index)


func edit(id: int, patch: Dictionary) -> void:
	var index := _index(id)
	if index < 0:
		return
	var before := objects[index]
	var after := before.duplicate(true)
	after.merge(patch, true)
	if before != after:
		_commit(before, after, index)


func edit_map(patch: Dictionary) -> void:
	var after := map.duplicate()
	after.merge(patch, true)
	if after != map:
		_commit(map, after, -1)


func edit_config(patch: Dictionary) -> void:
	var after := config.duplicate(true)
	after.merge(patch, true)
	if after != config:
		_commit(config, after, -2)


func undo() -> void:
	if not undo_stack.is_empty():
		var action: Dictionary = undo_stack.pop_back()
		redo_stack.append(action)
		_apply(action, action.before)


func redo() -> void:
	if not redo_stack.is_empty():
		var action: Dictionary = redo_stack.pop_back()
		undo_stack.append(action)
		_apply(action, action.after)


func _commit(before: Dictionary, after: Dictionary, index: int) -> void:
	var id: int = index + 1 if index < 0 else after.get("id", before.get("id"))
	var action := {"id": id, "index": index, "before": before, "after": after.duplicate(true)}
	undo_stack.append(action)
	if undo_stack.size() > HISTORY_LIMIT:
		undo_stack.pop_front()
	redo_stack.clear()
	_apply(action, after)


func _apply(action: Dictionary, value: Dictionary) -> void:
	var id: int = action.id
	if id == 0:
		map = value.duplicate()
	elif id == -1:
		config = value.duplicate(true)
	else:
		var index := _index(id)
		if value.is_empty():
			if index >= 0:
				objects.remove_at(index)
		elif index < 0:
			objects.insert(mini(action.index, objects.size()), value.duplicate(true))
		else:
			objects[index] = value.duplicate(true)
	changed.emit(id)


func _index(id: int) -> int:
	for index in range(objects.size()):
		if objects[index].id == id:
			return index
	return -1
