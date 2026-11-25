extends VBoxContainer

const Bindings = preload("res://scripts/input/movement_bindings.gd")
const Style = preload("res://scripts/ui/style.gd")

signal saved

var bindings: Bindings
var draft: Dictionary
var selected_action := &""
var buttons := {}
var status: Label
var cancel_button: Button


func _ready() -> void:
	set_process_input(false)
	draft = bindings.values.duplicate()
	add_theme_constant_override("separation", 12)
	add_child(Style.label("キー設定", 40))
	add_child(Style.label("変更したい操作のキーをクリックし、新しいキーを押します。", 17, Style.MUTED))
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 18)
	add_child(columns)
	var directions := Style.panel(columns, 14)
	var actions := Style.panel(columns, 14)
	for panel: VBoxContainer in [directions, actions]:
		panel.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.add_theme_constant_override("separation", 6)
	for action: StringName in Bindings.ACTIONS:
		var panel := directions if buttons.size() < 4 else actions
		var button := Style.button("", _capture_key.bind(action))
		button.custom_minimum_size = Vector2(134, 35)
		buttons[action] = button
		Style.field(panel, Bindings.ACTIONS[action][0], button)
	status = Style.label("", 17, Style.ACCENT)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(status)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 8)
	add_child(footer)
	footer.add_child(Style.button("保存して設定へ戻る", _save, true))
	footer.add_child(Style.button("初期配置に戻す", _restore_defaults))
	cancel_button = Style.button("入力をキャンセル", func() -> void: _end_capture("キー入力をキャンセルしました。"))
	footer.add_child(cancel_button)
	_end_capture("")


func _capture_key(action: StringName) -> void:
	selected_action = action
	set_process_input(true)
	status.text = "「%s」に割り当てるキーを押してください。" % Bindings.ACTIONS[action][0]
	_refresh_buttons()


func _input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	get_viewport().set_input_as_handled()
	if not event.pressed or event.echo:
		return
	var key := Bindings.key_from_event(event)
	if not Bindings.is_bindable(key):
		return
	var label: String = Bindings.ACTIONS[selected_action][0]
	var other: Variant = draft.find_key(key)
	if other != null and other != selected_action:
		draft[other] = draft[selected_action]
		draft[selected_action] = key
		_end_capture("「%s」と「%s」のキーを入れ替えました。" % [label, Bindings.ACTIONS[other][0]])
	else:
		draft[selected_action] = key
		_end_capture("「%s」を %s に設定しました。" % [label, Bindings.key_label(key)])


func _end_capture(message: String) -> void:
	selected_action = &""
	set_process_input(false)
	status.text = message
	_refresh_buttons()


func _refresh_buttons() -> void:
	for action: StringName in buttons:
		var label := Bindings.key_label(draft[action])
		var button: Button = buttons[action]
		button.text = "キー入力待ち…" if action == selected_action else label
		button.accessibility_name = "%s  %s" % [Bindings.ACTIONS[action][0], button.text]
	cancel_button.disabled = selected_action.is_empty()


func _restore_defaults() -> void:
	draft = Bindings.defaults()
	_end_capture("初期配置に戻しました。保存すると反映されます。")


func _save() -> void:
	var error := bindings.save(draft)
	if error == OK:
		saved.emit()
	else:
		_end_capture("キー設定を保存できませんでした（%s）。" % error_string(error))
