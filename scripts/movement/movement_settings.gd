extends RefCounted

const Store = preload("res://scripts/persistence/json_store.gd")
const DEFAULTS := "res://resources/configurations/movement_defaults.json"
const SAVE_PATH := "user://movement.json"
const FIELDS := {
	"walk_speed": ["歩行速度（m/s）", 1.0, 12.0, 0.1],
	"sprint_speed": ["スプリント速度（m/s）", 1.0, 18.0, 0.1],
	"crouch_speed": ["しゃがみ速度（m/s）", 0.5, 8.0, 0.1],
	"acceleration": ["地上加速度（m/s²）", 1.0, 60.0, 0.1],
	"deceleration": ["地上減速度（m/s²）", 1.0, 50.0, 0.1],
	"ground_friction": ["停止時の地上摩擦（1/s）", 0.0, 15.0, 0.1],
	"air_acceleration": ["空中加速度（m/s²）", 0.0, 40.0, 0.1],
	"air_control": ["空中制御率", 0.0, 1.0, 0.01],
	"jump_speed": ["ジャンプ初速（m/s）", 2.0, 9.0, 0.1],
	"gravity": ["重力（m/s²）", 6.0, 32.0, 0.1],
	"slide_boost": ["スライド初速加算（m/s）", 0.0, 7.0, 0.1],
	"slide_friction": ["スライド摩擦（m/s²）", 0.0, 18.0, 0.1],
	"slide_min_speed": ["スライド終了速度（m/s）", 0.5, 12.0, 0.1],
	"slide_max_seconds": ["スライド上限時間（秒）", 0.15, 3.0, 0.05],
	"eye_speed": ["視点高さの変化速度（m/s）", 1.0, 20.0, 0.1]
}

var defaults := Store.read(DEFAULTS)
var values: Dictionary
var save_path: String


func _init(path := SAVE_PATH) -> void:
	save_path = path
	var saved := Store.read_saved(path)
	var profile: Variant = saved.get("movement")
	values = validated(profile) if saved.get("schema_version") == 1 and profile is Dictionary else defaults.duplicate()


func validated(profile: Dictionary) -> Dictionary:
	var result := {}
	for key: String in FIELDS:
		var field: Array = FIELDS[key]
		result[key] = Store.number(profile.get(key), defaults[key], field[1], field[2])
	result.sprint_speed = maxf(result.walk_speed, result.sprint_speed)
	result.crouch_speed = minf(result.walk_speed, result.crouch_speed)
	return result


func save(profile: Dictionary) -> Error:
	var candidate := validated(profile)
	var error := Store.write(save_path, {"schema_version": 1, "movement": candidate})
	if error == OK:
		values = candidate
	return error
