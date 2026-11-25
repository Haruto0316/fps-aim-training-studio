extends RefCounted

const Store = preload("res://scripts/persistence/json_store.gd")
const SAVE_PATH := "user://settings.json"
const DEFAULTS := "res://resources/configurations/player_defaults.json"
const PRESETS := "res://resources/presets/sensitivity.json"
const FIELDS := {
	"sensitivity": [0.0001, 100.0, 0.0001],
	"horizontal": [0.1, 4.0, 0.01],
	"vertical": [0.1, 4.0, 0.01],
	"vertical_fov": [40.0, 100.0, 0.5],
	"dpi": [100.0, 32000.0, 1.0]
}

var presets := Store.read(PRESETS)
var defaults := Store.read(DEFAULTS)
var values: Dictionary
var save_path: String


func _init(path := SAVE_PATH) -> void:
	save_path = path
	values = validate(Store.read_saved(path))


func validate(raw: Dictionary) -> Dictionary:
	var result := defaults.duplicate(true)
	if raw.get("schema_version") != defaults.schema_version:
		return result
	if raw.get("preset") is String and presets.has(raw.preset):
		result.preset = raw.preset
	for key: String in FIELDS:
		if key == "sensitivity":
			continue
		var limits: Array = FIELDS[key]
		result[key] = Store.number(raw.get(key), defaults[key], limits[0], limits[1])
	var sensitivity_limits: Array = FIELDS.sensitivity
	var saved: Dictionary = raw.sensitivity_by_preset if raw.get("sensitivity_by_preset") is Dictionary else {}
	var sensitivities: Dictionary = result.sensitivity_by_preset
	for id: String in sensitivities:
		sensitivities[id] = Store.number(saved.get(id), sensitivities[id], sensitivity_limits[0], sensitivity_limits[1])
	# The active scalar also imports the selected preset from older settings files.
	result.sensitivity = Store.number(raw.get("sensitivity"), sensitivities[result.preset], sensitivity_limits[0], sensitivity_limits[1])
	sensitivities[result.preset] = result.sensitivity
	return result


func degrees_per_count(profile: Dictionary) -> Vector2:
	var base: float = profile.sensitivity * presets[profile.preset].degrees_per_count
	return base * Vector2(profile.horizontal, profile.vertical) if profile.preset == "generic" else Vector2.ONE * base


func cm_per_turn(profile: Dictionary) -> float:
	return 360.0 * 2.54 / (profile.dpi * degrees_per_count(profile).x)


func save(profile: Dictionary) -> Error:
	var validated := validate(profile)
	var error := Store.write(save_path, validated)
	if error == OK:
		values = validated
	return error
