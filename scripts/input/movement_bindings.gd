extends RefCounted

const Store = preload("res://scripts/persistence/json_store.gd")
const SAVE_PATH := "user://key_bindings.json"
const PAUSE := &"pause_training"
const ACTIONS := {
	&"move_forward": ["前進", KEY_W],
	&"move_back": ["後退", KEY_S],
	&"move_left": ["左移動", KEY_A],
	&"move_right": ["右移動", KEY_D],
	&"move_jump": ["ジャンプ", KEY_SPACE],
	&"move_sprint": ["スプリント", KEY_SHIFT],
	&"move_crouch": ["しゃがみ・スライド", KEY_CTRL],
	&"move_crouch_alt": ["しゃがみ・スライド（予備）", KEY_C],
	PAUSE: ["ポーズ", KEY_ESCAPE]
}

var save_path: String
var values: Dictionary


func _init(path := SAVE_PATH) -> void:
	save_path = path
	var record := Store.read_saved(path)
	values = _validated(record.keys_by_action) if record.get("schema_version") == 1 and record.get("keys_by_action") is Dictionary else defaults()


static func defaults() -> Dictionary:
	var result := {}
	for action: StringName in ACTIONS:
		result[action] = ACTIONS[action][1]
	return result


static func key_from_event(event: InputEventKey) -> Key:
	return event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode


static func is_bindable(key: int) -> bool:
	return key != KEY_NONE and key != KEY_UNKNOWN and not OS.get_keycode_string(key as Key).is_empty()


static func key_label(key: Key) -> String:
	if DisplayServer.get_name() == "headless":
		return OS.get_keycode_string(key)
	var displayed := DisplayServer.keyboard_get_keycode_from_physical(key)
	return OS.get_keycode_string(displayed if is_bindable(displayed) else key)


func label(action: StringName) -> String:
	return key_label(values[action])


func save(revised: Dictionary) -> Error:
	var validated := _validated(revised)
	var error := Store.write(save_path, {"schema_version": 1, "keys_by_action": validated})
	if error == OK:
		values = validated
	return error


func register() -> void:
	for action: StringName in ACTIONS:
		if action == PAUSE:
			continue
		if InputMap.has_action(action):
			Input.action_release(action)
			InputMap.action_erase_events(action)
		else:
			InputMap.add_action(action)
		var event := InputEventKey.new()
		event.physical_keycode = values[action]
		InputMap.action_add_event(action, event)


static func _validated(raw: Dictionary) -> Dictionary:
	var result := defaults()
	var assigned := {}
	for action: StringName in ACTIONS:
		var value: Variant = raw.get(action)
		var key: int = result[action]
		if (value is int or value is float) and value > 0 and value <= KEY_UNKNOWN and value == int(value) and is_bindable(value):
			key = int(value)
		if assigned.has(key):
			return defaults()
		result[action] = key
		assigned[key] = true
	return result
