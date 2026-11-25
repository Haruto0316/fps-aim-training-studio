extends Control

signal home_requested
signal test_requested(document: Dictionary)

const Style = preload("res://scripts/ui/style.gd")
const Draft = preload("res://scripts/editor/editor_draft.gd")
const EditorView = preload("res://scripts/editor/editor_view.gd")
const Custom = preload("res://scripts/scenarios/custom_scenario.gd")
const Route = preload("res://scripts/scenarios/route_path.gd")
const Store = preload("res://scripts/persistence/json_store.gd")
const AXIS_TEXT := ["X", "Y", "Z"]

var draft: Draft
var view: EditorView
var objects: ItemList
var add_menu: OptionButton
var inspector: VBoxContainer
var undo_button: Button
var redo_button: Button
var duplicate_button: Button
var delete_button: Button
var selection_title: Label
var selected := 0
var axis_buttons: Array[Button] = []
var vector_fields := {}
var number_fields := {}
var choice_fields := {}
var color_field: ColorPickerButton
var library_dir := Custom.DIRECTORY
var initial_view := {}
var note := ""
var status: Label
var save_state: Label
var notice_panel: PanelContainer
var notice: Label
var notice_timer: Timer
var route_controls: VBoxContainer
var route_row := -1
var preview_route := false


func _ready() -> void:
	_build_page()
	view.update_map(draft.map)
	for entry in draft.objects:
		view.update_object(entry.id, entry)
	draft.changed.connect(_on_changed)
	draft.replaced.connect(_on_replaced)
	_rebuild_list()
	_rebuild_inspector()
	_update_actions()
	if not initial_view.is_empty():
		view.pivot = initial_view.pivot
		view.yaw = initial_view.yaw
		view.pitch = initial_view.pitch
		view.distance = initial_view.distance
		view._update_camera()
		_select(initial_view.selected)
	if not note.is_empty():
		_notify(note)


func _build_page() -> void:
	var background := ColorRect.new()
	background.color = Style.INK
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margins := MarginContainer.new()
	margins.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_KEEP_SIZE, 16)
	background.add_child(margins)
	var layout := Style.stack(10)
	margins.add_child(layout)
	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 8)
	layout.add_child(toolbar)
	var title := Style.label("3D シナリオエディター", 26)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(title)
	undo_button = Style.button("元に戻す", _undo)
	redo_button = Style.button("やり直す", _redo)
	duplicate_button = Style.button("複製", _duplicate_selected)
	delete_button = Style.button("削除", _delete_selected)
	for button: Button in [undo_button, redo_button, duplicate_button, delete_button,
			Style.button("ホーム", func() -> void: home_requested.emit())]:
		toolbar.add_child(button)

	var files := HBoxContainer.new()
	files.add_theme_constant_override("separation", 6)
	layout.add_child(files)
	for button: Button in [
		Style.button("新規", _new_document), Style.button("保存", _save),
		Style.button("読み込み", _choose_saved), Style.button("インポート", _file_dialog.bind(false)),
		Style.button("エクスポート", _file_dialog.bind(true)), Style.button("練習設定", _configure),
		Style.button("テストプレイ", _test_play, true)
	]:
		button.custom_minimum_size.y = 36
		files.add_child(button)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 10)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(columns)
	_build_object_list(columns)
	_build_view(columns)
	_build_inspector_panel(columns)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	layout.add_child(footer)
	status = Style.label(draft.config.name, 15, Style.MUTED)
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	footer.add_child(status)
	save_state = Style.label("", 15)
	footer.add_child(save_state)
	_update_save_state()
	_build_notice()


func _build_notice() -> void:
	var overlay := CenterContainer.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	overlay.offset_top = 12
	overlay.offset_bottom = 12
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.add_child(overlay)
	var content := Style.panel(overlay, 12)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	notice_panel = content.get_parent()
	notice = Style.label("", 19)
	notice.custom_minimum_size.x = 360
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(notice)
	notice_panel.hide()
	notice_timer = Timer.new()
	notice_timer.one_shot = true
	notice_timer.wait_time = 3.5
	notice_timer.timeout.connect(notice_panel.hide)
	add_child(notice_timer)


func _notify(message: String, warning := false) -> void:
	status.text = message
	notice.text = message
	var color := Style.ACCENT if warning else Color("#91e2c4")
	var surface := Style.flat(Style.INK, color, 10)
	surface.content_margin_left = 14
	surface.content_margin_right = 14
	surface.content_margin_top = 10
	surface.content_margin_bottom = 10
	notice_panel.add_theme_stylebox_override("panel", surface)
	notice.add_theme_color_override("font_color", color)
	notice_panel.show()
	notice_timer.start()


func _update_save_state() -> void:
	var dirty := draft.is_dirty()
	var saved := not dirty and FileAccess.file_exists(library_dir.path_join(draft.config.id + ".json"))
	save_state.text = "未保存の変更あり" if dirty else ("保存済み" if saved else "未保存")
	save_state.add_theme_color_override("font_color", Style.MUTED if saved else Style.ACCENT)


func _build_object_list(parent: Control) -> void:
	var panel := Style.panel(parent, 12)
	panel.custom_minimum_size.x = 205
	panel.add_child(Style.label("オブジェクト", 19))
	add_menu = OptionButton.new()
	for key: String in Draft.KINDS:
		add_menu.add_item(Draft.KINDS[key][0])
	panel.add_child(add_menu)
	panel.add_child(Style.button("追加", _add_object, true))
	objects = ItemList.new()
	objects.size_flags_vertical = Control.SIZE_EXPAND_FILL
	objects.allow_reselect = true
	objects.item_selected.connect(func(index: int) -> void: _select(objects.get_item_metadata(index)))
	panel.add_child(objects)
	panel.add_child(Style.button("マップ設定", func() -> void:
		_select(0)
		_notify("マップ設定を表示しました。")
	))


func _build_view(parent: Control) -> void:
	var middle := Style.stack(6)
	middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(middle)
	var commands := HBoxContainer.new()
	commands.add_theme_constant_override("separation", 5)
	middle.add_child(commands)
	var axis_group := ButtonGroup.new()
	for label: String in ["XZ", "X", "Y", "Z"]:
		var axis_index := axis_buttons.size() - 1
		var button := Style.button(label, _set_axis.bind(axis_index))
		button.toggle_mode = true
		button.button_group = axis_group
		button.custom_minimum_size.y = 34
		commands.add_child(button)
		axis_buttons.append(button)
	axis_buttons[0].button_pressed = true
	var space := Control.new()
	space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	commands.add_child(space)
	var snap := CheckButton.new()
	snap.text = "スナップ 0.5 m"
	snap.button_pressed = true
	snap.toggled.connect(func(enabled: bool) -> void:
		view.snap = enabled
		_notify("0.5 m スナップを有効にしました。" if enabled else "スナップを無効にしました。")
	)
	commands.add_child(snap)
	view = EditorView.new()
	view.custom_minimum_size = Vector2(270, 260)
	view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	view.picked.connect(_select)
	view.moved.connect(func(id: int, position: Vector3) -> void:
		draft.edit(id, {"position": Draft.coordinates(position)})
		_notify("オブジェクトを移動しました。")
	)
	middle.add_child(view)
	var help := Style.label("左ドラッグ  移動    右ドラッグ  回転    中ドラッグ  パン\nホイール  ズーム    F  選択に寄る    X / Y / Z  軸を切替", 14, Style.MUTED)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	middle.add_child(help)


func _build_inspector_panel(parent: Control) -> void:
	var panel := Style.panel(parent, 12)
	panel.custom_minimum_size.x = 278
	selection_title = Style.label("", 20)
	panel.add_child(selection_title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	panel.add_child(scroll)
	inspector = Style.stack(10)
	inspector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(inspector)


func _rebuild_inspector() -> void:
	route_controls = null
	for child in inspector.get_children():
		inspector.remove_child(child)
		child.queue_free()
	vector_fields.clear()
	number_fields.clear()
	choice_fields.clear()
	var entry := draft.get_object(selected)
	if entry.is_empty():
		view.show_route(null, {}, false)
		selection_title.text = "マップ設定"
		_add_color("背景色", 0, draft.map.background, "background")
		_add_number("照明の強さ", "light", 0, draft.map.light, [0.0, 3.0, 0.05])
		_add_number("編集範囲の幅（m）", "width", 0, draft.map.width, [4, 60, 1])
		_add_number("編集範囲の奥行（m）", "depth", 0, draft.map.depth, [4, 60, 1])
		return
	selection_title.text = Draft.KINDS[entry.kind][0]
	_add_vector("位置（m）", "position", entry, [-50.0, 50.0, 0.01])
	_add_vector("回転（°）", "rotation", entry, [-180.0, 180.0, 1.0])
	_add_vector("サイズ（m）", "size", entry, [0.05, 40.0, 0.01])
	_add_color("色", entry.id, entry.color, "color")
	if Draft.is_target(entry.kind):
		_add_choice("形状", "shape", entry, Draft.SHAPES)
		_add_number("耐久値", "health", entry.id, entry.health, [1, 20000, 1])
		_add_choice("行動パターン", "behavior", entry, Draft.BEHAVIORS)
		_add_number("移動速度（m/s）", "speed", entry.id, entry.speed, [0.1, 15.0, 0.1])
		_add_number("移動範囲 ±m", "amplitude", entry.id, entry.amplitude, [0.1, 18.0, 0.1])
		_add_choice("出現条件", "spawn_rule", entry, Draft.SPAWN_RULES)
		_add_number("出現の遅延（秒）", "spawn_delay", entry.id, entry.spawn_delay, [0.0, 60.0, 0.1])
		_add_number("再出現まで（秒）", "respawn", entry.id, entry.respawn, [0.0, 30.0, 0.05])
		route_controls = Style.stack(6)
		inspector.add_child(route_controls)
	_refresh_route()


func _add_vector(label: String, key: String, entry: Dictionary, limits: Array) -> void:
	inspector.add_child(Style.label(label, 16, Style.MUTED))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	inspector.add_child(row)
	var fields: Array[SpinBox] = []
	for index in range(3):
		var column := Style.stack(2)
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(column)
		column.add_child(Style.label(AXIS_TEXT[index], 13, EditorView.AXIS_COLORS[index]))
		var field := _spin(entry[key][index], limits, 78)
		column.add_child(field)
		fields.append(field)
		field.value_changed.connect(func(value: float) -> void:
			var current := draft.get_object(entry.id)
			if not current.is_empty():
				var values: Array = current[key]
				values[index] = value
				draft.edit(entry.id, {key: values})
		)
	vector_fields[key] = fields


func _add_color(label: String, id: int, html: String, key: String) -> void:
	var field := ColorPickerButton.new()
	color_field = field
	field.color = Color.html(html)
	field.edit_alpha = false
	field.custom_minimum_size = Vector2(90, 30)
	_add_row(label, field)
	field.popup_closed.connect(func() -> void:
		_edit(id, {key: "#" + field.color.to_html(false)})
	)


func _add_number(label: String, key: String, id: int, value: float, limits: Array) -> void:
	var field := _spin(value, limits, 90)
	number_fields[key] = field
	_add_row(label, field)
	field.value_changed.connect(func(next: float) -> void: _edit(id, {key: next}))


func _add_choice(label: String, key: String, entry: Dictionary, choices: Dictionary) -> void:
	var field := OptionButton.new()
	var ids := choices.keys()
	for id: String in ids:
		field.add_item(choices[id])
	field.select(ids.find(entry[key]))
	choice_fields[key] = [field, ids]
	_add_row(label, field)
	field.item_selected.connect(func(index: int) -> void: draft.edit(entry.id, {key: ids[index]}))


func _add_row(label: String, field: Control) -> void:
	var row := HBoxContainer.new()
	inspector.add_child(row)
	var caption := Style.label(label, 15, Style.MUTED)
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(caption)
	row.add_child(field)


func _spin(value: float, limits: Array, width: float) -> SpinBox:
	var field := Style.spin(value, limits[0], limits[1], limits[2])
	field.custom_minimum_size = Vector2(width, 31)
	field.add_theme_font_size_override("font_size", 15)
	field.get_line_edit().add_theme_font_size_override("font_size", 15)
	return field


func _edit(id: int, patch: Dictionary) -> void:
	if id == 0:
		draft.edit_map(patch)
	else:
		draft.edit(id, patch)


func _on_changed(id: int) -> void:
	if id == -1:
		status.text = draft.config.name
	elif id == 0:
		view.update_map(draft.map)
	else:
		var entry := draft.get_object(id)
		view.update_object(id, entry)
		if selected == id and entry.is_empty():
			_select(0)
		_rebuild_list()
	if selected == id:
		_sync_inspector()
	_refresh_route()
	_update_actions()
	_update_save_state()


func _sync_inspector() -> void:
	var entry := draft.map if selected == 0 else draft.get_object(selected)
	for key: String in vector_fields:
		var fields: Array = vector_fields[key]
		for index in range(3):
			fields[index].set_value_no_signal(entry[key][index])
	for key: String in number_fields:
		number_fields[key].set_value_no_signal(entry[key])
	for key: String in choice_fields:
		var info: Array = choice_fields[key]
		info[0].select(info[1].find(entry[key]))
	color_field.color = Color.html(entry.background if selected == 0 else entry.color)


func _rebuild_list() -> void:
	var scroll := objects.get_v_scroll_bar()
	var old_scroll := scroll.value
	objects.clear()
	for entry in draft.objects:
		var index := objects.add_item("%s  %d" % [Draft.KINDS[entry.kind][0], entry.id])
		objects.set_item_metadata(index, entry.id)
		if entry.id == selected:
			objects.select(index)
	scroll.set_value_no_signal(old_scroll)


func _select(id: int) -> void:
	if selected == id:
		return
	selected = id
	route_row = -1
	preview_route = false
	view.select_object(id)
	_rebuild_list()
	_rebuild_inspector()
	if route_controls == null:
		_refresh_route()
	_update_actions()


func view_state() -> Dictionary:
	return {"selected": selected, "pivot": view.pivot, "yaw": view.yaw, "pitch": view.pitch, "distance": view.distance}


func _on_replaced() -> void:
	view.cancel_drag()
	view.select_object(0)
	selected = 0
	route_row = -1
	preview_route = false
	for id: int in view.nodes.keys():
		view.update_object(id, {})
	for entry: Dictionary in draft.objects:
		view.update_object(entry.id, entry)
	view.update_map(draft.map)
	view.focus_selection()
	_rebuild_list()
	_rebuild_inspector()
	_refresh_route()
	_update_actions()
	status.text = draft.config.name
	_update_save_state()


func _refresh_route() -> void:
	if route_controls == null:
		var waypoint := draft.get_object(selected)
		if waypoint.get("kind") == "route_point":
			for target: Dictionary in draft.objects:
				if selected in target.get("route_points", []):
					view.show_route(Route.new(target, draft.objects), target, false)
					return
		view.show_route(null, {}, false)
		return
	for child in route_controls.get_children():
		route_controls.remove_child(child)
		child.queue_free()
	var entry := draft.get_object(selected)
	var choices := OptionButton.new()
	var current: Array = []
	var spawn_choice := OptionButton.new()
	spawn_choice.add_item("配置位置", 0)
	var spawn_index := 0
	for object: Dictionary in draft.objects:
		if object.kind == "route_point":
			if object.id in entry.route_points:
				continue
			choices.add_item("通過点 %d" % object.id, object.id)
		elif object.kind == "spawn_area":
			spawn_choice.add_item("出現エリア %d" % object.id, object.id)
			if entry.spawn_area_id == object.id:
				spawn_index = spawn_choice.item_count - 1
	for id: int in entry.route_points:
		var waypoint := draft.get_object(id)
		if not waypoint.is_empty() and waypoint.kind == "route_point":
			current.append(id)
	if choices.item_count > 0:
		choices.select(0)
	spawn_choice.select(spawn_index)
	spawn_choice.item_selected.connect(func(index: int) -> void:
		draft.edit(entry.id, {"spawn_area_id": spawn_choice.get_item_id(index)})
	)
	route_controls.add_child(Style.label("出現位置", 15, Style.MUTED))
	route_controls.add_child(spawn_choice)
	route_controls.add_child(Style.label("移動ルート", 18))
	var list := ItemList.new()
	list.custom_minimum_size.y = 84
	for id: int in current:
		list.add_item("通過点 %d" % id)
	if route_row >= current.size():
		route_row = current.size() - 1
	if route_row >= 0:
		list.select(route_row)
	list.item_selected.connect(func(index: int) -> void: route_row = index)
	route_controls.add_child(list)
	var row := HBoxContainer.new()
	route_controls.add_child(row)
	for item: Array in [["↑", -1], ["↓", 1], ["外す", 0]]:
		var control := Button.new()
		control.text = item[0]
		control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		control.pressed.connect(_change_route.bind(entry.id, current, item[1]))
		row.add_child(control)
	route_controls.add_child(choices)
	var attach := Style.button("通過点を登録", func() -> void:
		current.append(choices.get_selected_id())
		route_row = current.size() - 1
		draft.edit(entry.id, {"route_points": current})
		_notify("通過点をルートに追加しました。")
	)
	attach.disabled = choices.item_count == 0 or current.size() >= Custom.ROUTE_LIMIT
	route_controls.add_child(attach)
	if choices.item_count == 0:
		route_controls.add_child(Style.label("通過点は左のメニューから追加", 14, Style.MUTED))
	for item: Array in [["曲線", "route_curve"], ["ループ（オフで往復）", "route_loop"]]:
		var check := CheckButton.new()
		check.text = item[0]
		check.button_pressed = entry[item[1]]
		var key: String = item[1]
		check.toggled.connect(func(value: bool) -> void:
			draft.edit(entry.id, {key: value})
			_notify("ルートの設定を変更しました。")
		)
		route_controls.add_child(check)
	var path := Route.new(entry, draft.objects)
	var preview := CheckButton.new()
	preview.text = "移動プレビュー"
	preview.button_pressed = preview_route
	preview.disabled = path.length <= 0.0
	preview.toggled.connect(func(value: bool) -> void:
		preview_route = value
		view.show_route(path, entry, value)
		_notify("移動プレビューを開始しました。" if value else "移動プレビューを停止しました。")
	)
	route_controls.add_child(preview)
	view.show_route(path, entry, preview_route)


func _change_route(id: int, points: Array, offset: int) -> void:
	if route_row < 0 or route_row >= points.size():
		_notify("ルート一覧で通過点を選んでください。", true)
		return
	var destination := route_row + offset
	if offset == 0:
		points.remove_at(route_row)
	elif destination >= 0 and destination < points.size():
		var point: Variant = points.pop_at(route_row)
		points.insert(destination, point)
		route_row = destination
	else:
		_notify("通過点はこれ以上移動できません。", true)
		return
	draft.edit(id, {"route_points": points})
	_notify("通過点をルートから外しました。" if offset == 0 else "通過点の順番を変更しました。")


func _new_document() -> void:
	_replace_document(Draft.new().document(), "新しい下書きを作成しました。")


func _save() -> Error:
	var error := Custom.save(draft.document(), library_dir)
	if error == OK:
		draft.mark_saved()
		_update_save_state()
		_notify("保存しました。")
	else:
		_notify("保存できませんでした（%s）。" % error_string(error), true)
	return error


func _choose_saved() -> void:
	var entries := Custom.catalogue(library_dir)
	if entries.is_empty():
		_notify("保存済みのシナリオがありません。", true)
		return
	var dialog := ConfirmationDialog.new()
	dialog.title = "保存済みシナリオ"
	dialog.ok_button_text = "読み込み"
	var list := ItemList.new()
	list.custom_minimum_size = Vector2(430, 225)
	for entry in entries:
		list.add_item(entry.name)
	list.select(0)
	dialog.add_child(list)
	_confirm(dialog, func() -> void:
		var selection := list.get_selected_items()
		if not selection.is_empty():
			_replace_document(entries[selection[0]], "シナリオを読み込みました。")
		else:
			_notify("読み込むシナリオを選んでください。", true)
	)


func _replace_document(document: Dictionary, loaded_note: String) -> void:
	var apply := func() -> void:
		draft.replace(document)
		_notify(loaded_note)
	if draft.is_dirty():
		var dialog := ConfirmationDialog.new()
		dialog.title = "シナリオを切り替える"
		dialog.dialog_text = "保存していない編集内容があります。現在の下書きを置き換えますか？"
		_confirm(dialog, apply)
	else:
		apply.call()


func _file_dialog(export_file: bool) -> void:
	var dialog := FileDialog.new()
	dialog.title = "シナリオをエクスポート" if export_file else "シナリオをインポート"
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE if export_file else FileDialog.FILE_MODE_OPEN_FILE
	dialog.add_filter("*.json", "シナリオ JSON")
	if export_file:
		dialog.current_file = "scenario-" + draft.config.id.left(8) + ".json"
	add_child(dialog)
	dialog.file_selected.connect(func(path: String) -> void:
		if export_file:
			_export_path(path)
		else:
			_import_path(path)
		dialog.queue_free()
	)
	dialog.canceled.connect(_cancel_dialog.bind(dialog))
	dialog.popup_centered_ratio(0.75)


func _export_path(path: String) -> Error:
	var document := Custom.validate(draft.document())
	var error := ERR_INVALID_DATA if document.is_empty() else Store.write(path, document, true)
	_notify("JSON をエクスポートしました。" if error == OK else "エクスポートできませんでした（%s）。" % error_string(error), error != OK)
	return error


func _import_path(path: String) -> bool:
	var document := Custom.load_file(path)
	if document.is_empty():
		_notify("シナリオ JSON が無効か、未対応の形式です。", true)
		return false
	document.id = Draft.new_id()
	_replace_document(document, "インポートしました。「保存」で一覧に登録できます。")
	return true


func _test_play() -> void:
	view.cancel_drag()
	var document := Custom.validate(draft.document())
	if document.is_empty():
		_notify("練習設定やオブジェクトを確認してください。", true)
		return
	if not document.objects.any(func(entry: Dictionary) -> bool: return Draft.is_target(entry.kind)):
		_notify("テストプレイにはターゲットを1体以上配置してください。", true)
		return
	test_requested.emit(document)


func _configure() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "カスタム練習設定"
	dialog.ok_button_text = "適用"
	var fields := Style.stack(8)
	fields.custom_minimum_size.x = 450
	dialog.add_child(fields)
	var name_field := LineEdit.new()
	name_field.max_length = 64
	name_field.text = draft.config.name
	var description := LineEdit.new()
	description.max_length = 300
	description.text = draft.config.description
	var duration := _spin(draft.config.duration_seconds, [5, 180, 1], 95)
	var damage := _spin(draft.config.weapon.damage, [1, 1000, 1], 95)
	var rpm := _spin(draft.config.weapon.rounds_per_minute, [60, 1500, 1], 95)
	var hit_score := _spin(draft.config.scoring.points_per_hit, [1, 10000, 1], 95)
	var bonus := _spin(draft.config.scoring.points_per_elimination, [0, 10000, 1], 95)
	var move := CheckButton.new()
	move.text = "プレイヤーの移動を有効にする"
	move.button_pressed = draft.config.player.movement_enabled
	var auto := CheckButton.new()
	auto.text = "フルオート"
	auto.button_pressed = draft.config.weapon.fire_mode == "automatic"
	for item: Array in [["シナリオ名", name_field], ["説明", description], ["時間（秒）", duration],
			["ダメージ", damage], ["連射速度（発／分）", rpm], ["命中点", hit_score], ["撃破ボーナス", bonus]]:
		var row := HBoxContainer.new()
		fields.add_child(row)
		var label := Style.label(item[0], 16)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		row.add_child(item[1])
		item[1].custom_minimum_size.x = 220 if item[1] is LineEdit else 95
	fields.add_child(move)
	fields.add_child(auto)
	_confirm(dialog, func() -> void:
		for field: SpinBox in [duration, damage, rpm, hit_score, bonus]:
			field.apply()
		var weapon: Dictionary = draft.config.weapon.duplicate(true)
		weapon.merge({"damage": int(damage.value), "rounds_per_minute": int(rpm.value),
			"fire_mode": "automatic" if auto.button_pressed else "single"}, true)
		var name_value := name_field.text.strip_edges()
		draft.edit_config({
			"name": draft.config.name if name_value.is_empty() else name_value, "description": description.text,
			"duration_seconds": int(duration.value), "player": {"movement_enabled": move.button_pressed},
			"weapon": weapon, "scoring": {"points_per_hit": int(hit_score.value), "points_per_elimination": int(bonus.value)}
		})
		_notify("練習設定を適用しました。")
	)


func _confirm(dialog: ConfirmationDialog, action: Callable) -> void:
	add_child(dialog)
	dialog.confirmed.connect(func() -> void:
		action.call()
		dialog.queue_free()
	)
	dialog.canceled.connect(_cancel_dialog.bind(dialog))
	dialog.popup_centered()


func _cancel_dialog(dialog: AcceptDialog) -> void:
	_notify("操作をキャンセルしました。")
	dialog.queue_free()


func _add_object() -> void:
	if draft.objects.size() >= Custom.OBJECT_LIMIT:
		_notify("オブジェクトの上限は %d 個です。" % Custom.OBJECT_LIMIT, true)
		return
	var kind: String = Draft.KINDS.keys()[add_menu.selected]
	var position := view.pivot
	position.y = float(Draft.KINDS[kind][1][1]) * 0.5
	if Draft.is_target(kind):
		position.y = maxf(position.y, 1.5)
	if kind == "floor":
		position.y *= -1.0
	if view.snap:
		position.x = snappedf(position.x, 0.5)
		position.z = snappedf(position.z, 0.5)
	_select(draft.add(kind, position))
	_notify("%sを追加しました。" % Draft.KINDS[kind][0])


func _duplicate_selected() -> void:
	if draft.objects.size() >= Custom.OBJECT_LIMIT:
		_notify("オブジェクトの上限は %d 個です。" % Custom.OBJECT_LIMIT, true)
		return
	if selected != 0:
		var copy := draft.duplicate_object(selected)
		if copy != 0:
			_select(copy)
			_notify("オブジェクトを複製しました。")


func _delete_selected() -> void:
	if selected != 0:
		draft.remove(selected)
		_notify("オブジェクトを削除しました。")


func _undo() -> void:
	view.cancel_drag()
	if draft.undo_stack.is_empty():
		return
	draft.undo()
	_notify("操作を元に戻しました。")


func _redo() -> void:
	view.cancel_drag()
	if draft.redo_stack.is_empty():
		return
	draft.redo()
	_notify("操作をやり直しました。")


func _set_axis(index: int) -> void:
	view.cancel_drag()
	view.axis = index
	view.select_object(selected)
	axis_buttons[index + 1].set_pressed_no_signal(true)
	_notify("移動方向を %s に切り替えました。" % ("XZ 平面" if index < 0 else AXIS_TEXT[index] + " 軸"))


func _update_actions() -> void:
	undo_button.disabled = draft.undo_stack.is_empty()
	redo_button.disabled = draft.redo_stack.is_empty()
	duplicate_button.disabled = selected == 0
	delete_button.disabled = selected == 0


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if get_viewport().gui_get_focus_owner() is LineEdit:
		return
	if event.ctrl_pressed:
		match event.keycode:
			KEY_Z:
				if event.shift_pressed:
					_redo()
				else:
					_undo()
			KEY_Y:
				_redo()
			KEY_D:
				_duplicate_selected()
			_:
				return
	else:
		match event.keycode:
			KEY_DELETE:
				_delete_selected()
			KEY_ESCAPE:
				view.cancel_drag()
			KEY_F:
				view.focus_selection()
			KEY_X, KEY_Y, KEY_Z:
				var index := [KEY_X, KEY_Y, KEY_Z].find(event.keycode)
				_set_axis(-1 if view.axis == index else index)
			_:
				return
	get_viewport().set_input_as_handled()
