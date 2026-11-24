extends RefCounted

const KEYS := {
	&"move_forward": [KEY_W],
	&"move_back": [KEY_S],
	&"move_left": [KEY_A],
	&"move_right": [KEY_D],
	&"move_jump": [KEY_SPACE],
	&"move_crouch": [KEY_CTRL],
	&"move_crouch_alt": [KEY_C],
	&"move_sprint": [KEY_SHIFT]
}


static func register() -> void:
	for action: StringName in KEYS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for key: Key in KEYS[action]:
			var event := InputEventKey.new()
			event.physical_keycode = key
			InputMap.action_add_event(action, event)
