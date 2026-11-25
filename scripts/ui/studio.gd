extends Control

const AimForm = preload("res://scripts/ui/aim_settings_form.gd")
const Setting = preload("res://scripts/input/aim_settings.gd")
const Scenario = preload("res://scripts/scenarios/scenario.gd")
const Session = preload("res://scripts/training/static_session.gd")
const Store = preload("res://scripts/persistence/json_store.gd")
const Style = preload("res://scripts/ui/style.gd")
const TargetArt = preload("res://scripts/ui/target_art.gd")
const Preview = preload("res://scripts/ui/drill_preview.gd")
const Humanoid = preload("res://scripts/targets/humanoid_dummy.gd")
const MovementSettings = preload("res://scripts/movement/movement_settings.gd")
const Bindings = preload("res://scripts/input/movement_bindings.gd")
const KeyBindingsForm = preload("res://scripts/ui/key_bindings_form.gd")
const Editor = preload("res://scripts/editor/editor_page.gd")
const EditorDraft = preload("res://scripts/editor/editor_draft.gd")
const Custom = preload("res://scripts/scenarios/custom_scenario.gd")
const Accounts = preload("res://scripts/persistence/local_accounts.gd")
const AccountPage = preload("res://scripts/ui/account_page.gd")
const BEST_PATH := "user://best_scores.json"

var aim := Setting.new()
var movement := MovementSettings.new()
var bindings := Bindings.new()
var standard := Scenario.load_static()
var movement_mode := Scenario.load_movement()
var strafe_mode := Scenario.load_strafe()
var mode_options := {}
var selected: Dictionary
var best_path := BEST_PATH
var best_scores: Dictionary
var page: Control
var session: Session
var editor_draft: EditorDraft
var editor_view_state := {}
var editor_note := ""
var custom_library_dir := Custom.DIRECTORY
var accounts := Accounts.new()
var account_name := ""
var account_directory := ""
var guest_paths: Dictionary
var profile_drafts := {}


func _ready() -> void:
	get_window().min_size = Vector2i(880, 540)
	theme = Style.create_theme()
	guest_paths = {"aim": aim.save_path, "movement": movement.save_path, "bindings": bindings.save_path,
		"best": best_path, "scenarios": custom_library_dir}
	_load_best_scores()
	selected = _default_selection()
	show_home()


func show_home() -> void:
	var body := _new_page("ホーム")
	var split := _split(body, 48)
	var menu := Style.stack(10)
	menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	menu.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	split.add_child(menu)
	menu.add_child(Style.label("エイム練習", 53))
	var description := Style.label("静止・移動ターゲットでエイムを練習し、命中率と反応時間を測ります。", 20, Style.MUTED)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	menu.add_child(description)
	menu.add_child(Style.button("練習モード", show_practice_modes, true))
	menu.add_child(Style.button("設定", show_settings))
	menu.add_child(Style.button("終了", func() -> void: get_tree().quit()))
	var art := TargetArt.new()
	art.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	art.size_flags_stretch_ratio = 1.15
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	split.add_child(art)


func show_account() -> void:
	var body := _new_page("アカウント")
	var panel := AccountPage.new()
	panel.accounts = accounts
	panel.account_name = account_name
	panel.home_requested.connect(show_home)
	panel.account_changed.connect(_change_account)
	body.add_child(panel)


func _change_account(username: String, directory: String) -> void:
	profile_drafts[account_directory] = {
		"modes": mode_options, "selected": selected, "draft": editor_draft,
		"view": editor_view_state, "note": editor_note
	}
	account_name = username
	account_directory = directory
	var paths := guest_paths if directory.is_empty() else {
		"aim": directory.path_join("settings.json"), "movement": directory.path_join("movement.json"),
		"bindings": directory.path_join("key_bindings.json"),
		"best": directory.path_join("best_scores.json"), "scenarios": directory.path_join("scenarios")
	}
	aim = Setting.new(paths.aim)
	movement = MovementSettings.new(paths.movement)
	bindings = Bindings.new(paths.bindings)
	best_path = paths.best
	custom_library_dir = paths.scenarios
	_load_best_scores()
	var previous: Dictionary = profile_drafts.get(directory, {})
	mode_options = previous.get("modes", {})
	selected = previous.get("selected", _default_selection())
	editor_draft = previous.get("draft")
	editor_view_state = previous.get("view", {})
	editor_note = previous.get("note", "")
	show_home()


func _load_best_scores() -> void:
	var saved := Store.read_saved(best_path)
	best_scores = saved.scores if saved.get("schema_version") == 1 and saved.get("scores") is Dictionary else {}


func _default_selection() -> Dictionary:
	for definition in [standard, movement_mode, strafe_mode]:
		if not definition.is_empty():
			return definition.duplicate(true)
	return {}


func show_editor() -> void:
	_clear_screen()
	if editor_draft == null:
		editor_draft = EditorDraft.new()
	var editor := Editor.new()
	editor.draft = editor_draft
	editor.initial_view = editor_view_state.duplicate()
	editor.library_dir = custom_library_dir
	editor.note = editor_note
	editor_note = ""
	editor.home_requested.connect(show_home)
	editor.test_requested.connect(func(document: Dictionary) -> void: _open_round(document, true))
	editor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page = editor
	add_child(editor)


func show_custom_library(message := "") -> void:
	var body := _new_page("カスタム練習", show_practice_modes, null, "戻る")
	if not message.is_empty():
		body.add_child(Style.label(message, 16, Style.ACCENT))
	var documents := Custom.catalogue(custom_library_dir)
	if documents.is_empty():
		body.add_child(Style.label("3D エディターで保存したシナリオがここに表示されます。", 21))
		body.add_child(Style.button("3D エディター", show_editor, true))
		return
	for document: Dictionary in documents:
		var card := _preview_card(body, document, Vector2(240, 90), 12)
		var title := Style.label(document.name, 24)
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.add_child(title)
		if not document.description.is_empty():
			var description := Style.label(document.description, 16, Style.MUTED)
			description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			card.add_child(description)
		var targets: int = document.objects.filter(func(entry: Dictionary) -> bool: return EditorDraft.is_target(entry.kind)).size()
		card.add_child(Style.label("%d 秒   ·   ターゲット %d 体" % [document.duration_seconds, targets], 16, Style.MUTED))
		var actions := HBoxContainer.new()
		actions.add_theme_constant_override("separation", 8)
		card.add_child(actions)
		var play := Style.button("プレイ", _play_custom.bind(document), true)
		play.disabled = targets == 0
		actions.add_child(play)
		actions.add_child(Style.button("編集", _edit_custom.bind(document)))
		actions.add_child(Style.button("複製", _duplicate_custom.bind(document)))
		actions.add_child(Style.button("削除", _delete_custom.bind(document)))
	body.add_child(Style.button("3D エディター", show_editor))


func _play_custom(document: Dictionary) -> void:
	selected = document.duplicate(true)
	_start()


func _edit_custom(document: Dictionary) -> void:
	if editor_draft != null and editor_draft.is_dirty():
		_confirm_custom("未保存の下書きを切り替える", "保存していない編集内容があります。選んだシナリオを開きますか？",
			_load_custom_in_editor.bind(document))
		return
	_load_custom_in_editor(document)


func _load_custom_in_editor(document: Dictionary) -> void:
	editor_draft = EditorDraft.new(false)
	editor_draft.replace(document)
	editor_view_state = {}
	show_editor()


func _duplicate_custom(document: Dictionary) -> void:
	var copy := document.duplicate(true)
	copy.id = EditorDraft.new_id()
	copy.name = document.name.left(58) + "（複製）"
	var error := Custom.save(copy, custom_library_dir)
	show_custom_library("複製しました。" if error == OK else "複製できませんでした  " + error_string(error))


func _delete_custom(document: Dictionary) -> void:
	_confirm_custom("シナリオの削除", "「%s」を保存済み一覧から削除しますか？" % document.name, func() -> void:
		var error := Custom.remove_saved(document.id, custom_library_dir)
		if error == OK and selected.get("id") == document.id:
			selected = standard.duplicate(true)
		show_custom_library("削除しました。" if error == OK else "削除できませんでした  " + error_string(error))
	)


func _confirm_custom(title: String, message: String, action: Callable) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = title
	dialog.dialog_text = message
	add_child(dialog)
	dialog.confirmed.connect(func() -> void:
		action.call()
		dialog.queue_free()
	)
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered()


func show_practice_modes() -> void:
	var body := _new_page("練習モード", show_home)
	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(center)
	var choices := Style.panel(center, 24)
	choices.custom_minimum_size.x = 340
	choices.add_child(Style.button("トラッキング", show_tracking_drills))
	choices.add_child(Style.button("フリック", show_flick_drills))
	choices.add_child(Style.button("カスタム練習", show_custom_library))


func show_tracking_drills() -> void:
	var drills: Array[Dictionary] = []
	for id: String in Scenario.FIXED_TRACKING:
		drills.append(Scenario.load_standard_drill(id))
	for id: String in Scenario.MOBILE_DRILLS:
		drills.append(Scenario.load_mobile_drill(id))
	drills.append(strafe_mode)
	_show_drill_list("トラッキング", drills, show_tracking_drills)


func show_flick_drills() -> void:
	var drills: Array[Dictionary] = [standard, Scenario.load_apex_humanoid()]
	for id: String in Scenario.TARGET_GROUPS:
		drills.append(Scenario.load_standard_drill(id))
	drills.append(movement_mode)
	_show_drill_list("フリック", drills, show_flick_drills)


func _show_drill_list(title: String, drills: Array[Dictionary], return_to_list: Callable) -> void:
	var custom_button := Style.button("カスタム練習", show_custom_library)
	var body := _new_page(title, show_practice_modes, custom_button, "戻る")
	var captions := {"movement_practice": "移動練習", "strafe_elimination": "移動ダミー撃破"}
	body.add_theme_constant_override("separation", 10)
	for definition in drills:
		if definition.is_empty():
			continue
		var card := _preview_card(body, mode_options.get(definition.id, definition), Vector2(176, 66), 9)
		card.add_theme_constant_override("separation", 5)
		card.add_child(Style.button(captions.get(definition.type, definition.name), show_mode.bind(definition, title, return_to_list)))
		var summary := Style.label(definition.description, 17, Style.MUTED)
		summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.add_child(summary)
	if body.get_child_count() == 0:
		body.add_child(Style.label("シナリオを読み込めませんでした。", 17, Style.ACCENT))


func _preview_card(body: VBoxContainer, definition: Dictionary, minimum: Vector2, inset: int) -> VBoxContainer:
	var panel := Style.panel(body, inset)
	var row := _split(panel, 16)
	row.add_child(Preview.new(definition, minimum))
	var card := Style.stack(8)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(card)
	return card


func show_mode(definition: Dictionary, page_title: String, back: Callable) -> void:
	var mobile: bool = definition.player.movement_enabled
	var armed: bool = definition.target.has("health")
	var humanoid: bool = definition.type == Scenario.APEX_HUMANOID
	selected = mode_options.get(definition.id, definition)
	var body := _new_page(page_title, back, null, "戻る")
	body.add_child(Style.label(definition.name, 43))
	var split := _split(body, 22)
	var details := Style.panel(split, 24)
	details.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var practice_type := "移動あり" if mobile else "固定視点"
	details.add_child(Style.label(practice_type + "  /  難易度 " + definition.difficulty, 17, Style.ACCENT))
	var summary := Style.label(definition.description, 21)
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.add_child(summary)
	var preview := Preview.new(selected, Vector2(0, 132))
	details.add_child(preview)
	var best := Style.label("", 22)
	details.add_child(best)
	if mobile:
		var help := "左クリックで射撃、右クリック長押しで ADS。" if armed else "スプリント中に %s または %s を押すとスライドします。" % [
			bindings.label(&"move_crouch"), bindings.label(&"move_crouch_alt")]
		var hint := Style.label(help, 17, Style.MUTED)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		details.add_child(hint)
	if definition.type in Scenario.TARGET_GROUPS:
		var hint := Style.label("ダミーが重ならないよう、数と大きさに応じて最小範囲を調整します。", 17, Style.MUTED)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		details.add_child(hint)
	if humanoid:
		details.add_child(Style.label(_humanoid_region_summary(definition.scoring.hit_regions, "点"), 17, Style.ACCENT))
	var options := Style.panel(split, 20)
	options.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	options.add_theme_constant_override("separation", 6)
	options.add_child(Style.label("練習条件", 24))
	var duration := _field(options, "練習時間（秒）", selected.duration_seconds, Scenario.DURATION_LIMITS + [1])
	var size_key := "height" if humanoid else "radius"
	var size_label := "ダミーの高さ（m）" if humanoid else "ダミーの大きさ（半径 m）"
	var size_limits: Array = Scenario.HUMANOID_HEIGHT_LIMITS if humanoid else Scenario.TARGET_LIMITS.radius
	var dummy_size := _field(options, size_label, selected.target[size_key], size_limits)
	var x_caption := "左右の移動範囲 ±m" if armed else "左右の出現範囲 ±m"
	var x_extent := _field(options, x_caption, selected.target.x_extent, Scenario.TARGET_LIMITS.x_extent)
	var y_extent: SpinBox
	if not humanoid:
		y_extent = _field(options, "上下の出現範囲 ±m", selected.target.y_extent, Scenario.TARGET_LIMITS.y_extent)
	var fire_mode: OptionButton
	var recoil: OptionButton
	var target_speed: SpinBox
	var target_count: SpinBox
	var pattern: OptionButton
	var pattern_ids := Scenario.SMOOTH_PATTERNS.keys()
	var recoil_multipliers := Scenario.RECOIL_PRESETS.values()
	if definition.type in Scenario.MOBILE_DRILLS or definition.type in Scenario.FIXED_TRACKING:
		target_speed = _field(options, "ダミーの速度（m/s）", selected.target.speed, Scenario.SPEED_LIMITS)
	if definition.type in Scenario.TARGET_GROUPS:
		target_count = _field(options, "同時出現数", selected.target.count, Scenario.COUNT_LIMITS)
	if definition.type == "smooth_tracking":
		pattern = OptionButton.new()
		for id: String in pattern_ids:
			pattern.add_item(Scenario.SMOOTH_PATTERNS[id])
		pattern.select(pattern_ids.find(selected.target.behavior))
		Style.field(options, "移動パターン", pattern)
	if armed:
		options.add_child(Style.label("射撃設定", 20))
		fire_mode = OptionButton.new()
		fire_mode.add_item("フルオート")
		fire_mode.add_item("単発")
		fire_mode.select(0 if selected.weapon.fire_mode == "automatic" else 1)
		Style.field(options, "射撃方式", fire_mode)
		recoil = OptionButton.new()
		for preset: String in Scenario.RECOIL_PRESETS:
			recoil.add_item(preset)
		var multiplier: float = selected.weapon.get("recoil_multiplier", 1.0) if selected.weapon.recoil_enabled else 0.0
		recoil.select(recoil_multipliers.find(multiplier))
		Style.field(options, "反動", recoil)
	var refresh := func(_value: float) -> void:
		var target_options := {"x_extent": x_extent.value}
		target_options[size_key] = dummy_size.value
		if y_extent != null:
			target_options.y_extent = y_extent.value
		if target_speed != null:
			target_options.speed = target_speed.value
		if target_count != null:
			target_options.count = target_count.value
		if pattern != null:
			target_options.behavior = pattern_ids[pattern.selected]
		selected = Scenario.with_options(definition, duration.value, target_options)
		if target_count != null:
			x_extent.set_value_no_signal(selected.target.x_extent)
			y_extent.set_value_no_signal(selected.target.y_extent)
		if armed:
			selected.weapon.fire_mode = "automatic" if fire_mode.selected == 0 else "single"
			var multiplier: float = recoil_multipliers[recoil.selected]
			selected.weapon.recoil_enabled = multiplier > 0.0
			if multiplier > 1.0:
				selected.weapon.recoil_multiplier = multiplier
			else:
				selected.weapon.erase("recoil_multiplier")
		mode_options[definition.id] = selected
		preview.scenario = selected
		preview.queue_redraw()
		var record := _best()
		best.text = "自己ベスト  %d 点" % record if record >= 0 else "自己ベスト  —"
	var option_fields: Array[SpinBox] = [duration, dummy_size, x_extent]
	if y_extent != null:
		option_fields.append(y_extent)
	if target_speed != null:
		option_fields.append(target_speed)
	if target_count != null:
		option_fields.append(target_count)
	for field in option_fields:
		field.value_changed.connect(refresh)
	if armed:
		fire_mode.item_selected.connect(func(index: int) -> void: refresh.call(index))
		recoil.item_selected.connect(func(index: int) -> void: refresh.call(index))
	if pattern != null:
		pattern.item_selected.connect(func(index: int) -> void: refresh.call(index))
	refresh.call(0.0)
	body.get_parent().add_sibling(Style.button("この条件で開始", func() -> void:
		for field in option_fields:
			field.apply()
		refresh.call(0.0)
		_start()
	, true))


func show_settings() -> void:
	var body := _new_page("設定", show_home)
	body.add_child(Style.label("マウスと視野角", 40))
	var split := _split(body, 22)
	var form := Style.panel(split, 20)
	form.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.get_parent().size_flags_stretch_ratio = 1.38
	var distance := Style.panel(split, 22)
	distance.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	distance.add_child(Style.label("水平の振り向き距離", 19, Style.MUTED))
	var reading := Style.label("", 32, Style.ACCENT)
	distance.add_child(reading)
	var note := Style.label("ゲーム別プリセットではゲーム内のマウス感度をそのまま入力します。DPI はマウス本体の設定に合わせてください。", 17, Style.MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	distance.add_child(note)
	distance.add_child(Style.button("移動設定", show_movement_settings))
	distance.add_child(Style.button("キー設定", show_key_settings))
	var identity := "ゲスト" if account_name.is_empty() else account_name
	var short_identity := identity.left(14) + "…" if identity.length() > 14 else identity
	var account_button := Style.button("アカウント · " + short_identity, show_account)
	account_button.tooltip_text = identity
	distance.add_child(account_button)
	var settings := AimForm.new(aim, form, reading)
	var status := Style.label("", 17, Style.ACCENT)
	body.add_child(status)
	body.add_child(Style.button("保存してホームへ", func() -> void:
		var error := settings.save()
		if error == OK:
			show_home()
		else:
			status.text = "設定を保存できませんでした（%s）。" % error_string(error)
	, true))


func show_key_settings() -> void:
	var body := _new_page("キー設定", show_settings, null, "戻る")
	var form := KeyBindingsForm.new()
	form.name = "KeyBindingsForm"
	form.bindings = bindings
	form.saved.connect(show_settings)
	body.add_child(form)


func show_movement_settings() -> void:
	var body := _new_page("設定", show_home)
	body.add_child(Style.label("移動設定", 40))
	var split := _split(body, 22)
	var ground := Style.panel(split, 20)
	var motion := Style.panel(split, 20)
	ground.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	motion.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ground.add_theme_constant_override("separation", 6)
	motion.add_theme_constant_override("separation", 6)
	ground.add_child(Style.label("地上と空中", 23))
	motion.add_child(Style.label("ジャンプとスライド", 23))
	var inputs := {}
	for key: String in MovementSettings.FIELDS:
		var field: Array = MovementSettings.FIELDS[key]
		var parent := ground if inputs.size() < 8 else motion
		inputs[key] = _field(parent, field[0], movement.values[key], field.slice(1))
	var status := Style.label("", 17, Style.ACCENT)
	status.hide()
	body.add_child(status)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	body.add_child(actions)
	actions.add_child(Style.button("保存してホームへ", func() -> void:
		var draft := {}
		for key: String in inputs:
			inputs[key].apply()
			draft[key] = inputs[key].value
		var error := movement.save(draft)
		if error == OK:
			show_home()
		else:
			status.text = "移動設定を保存できませんでした（%s）。" % error_string(error)
			status.show()
	, true))
	actions.add_child(Style.button("初期値に戻す", func() -> void:
		for key: String in inputs:
			inputs[key].value = movement.defaults[key]
	))
	actions.add_child(Style.button("マウス設定へ", show_settings))


func _start() -> void:
	_open_round(selected, false)


func _open_round(document: Dictionary, test_run: bool) -> void:
	_clear_screen()
	session = Session.new()
	session.scenario = document.duplicate(true)
	session.editor_test = test_run
	session.movement_tuning = movement.values.duplicate()
	session.bindings = bindings
	session.aim = aim
	if test_run:
		session.completed.connect(_finish_editor_test)
		session.abandoned.connect(func() -> void:
			editor_note = "テストプレイを終了しました。"
			show_editor()
		)
		session.restart_requested.connect(_open_round.bind(document, true))
	else:
		session.completed.connect(_show_result)
		session.abandoned.connect(show_home)
		session.restart_requested.connect(_start)
	add_child(session)


func _finish_editor_test(result: Dictionary) -> void:
	editor_note = "テスト完了  ·  スコア %d    命中率 %.1f%%    撃破 %d" % [result.score, result.accuracy, result.eliminations]
	show_editor()


func _show_result(result: Dictionary) -> void:
	var new_best: bool = result.score > _best() and result.hits > 0
	var save_error := OK
	if new_best:
		var revised := best_scores.duplicate()
		revised[_record_key()] = result.score
		save_error = Store.write(best_path, {"schema_version": 1, "scores": revised})
		if save_error == OK:
			best_scores = revised
	var body := _new_page("練習結果", show_home)
	var title := Style.label(selected.name, 44)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(title)
	var headline := _split(body, 22)
	_result_stat(headline, "スコア", "%d" % result.score, Style.ACCENT)
	_result_stat(headline, "命中率", "%.1f%%" % result.accuracy)
	if result.has("tracking_accuracy"):
		var pursuit := "—" if result.tracking_accuracy == null else "%.1f%%" % result.tracking_accuracy
		_result_stat(headline, "追従精度", pursuit)
	else:
		var reaction := "—" if result.reaction_ms == null else "%.0f ms" % result.reaction_ms
		_result_stat(headline, "平均切替時間" if result.has("switches_completed") else "平均反応時間", reaction)
	var details := Style.panel(body, 18)
	details.add_child(Style.label(
		"練習時間 %d 秒    射撃 %d    命中 %d    ミス %d" %
		[selected.duration_seconds, result.shots, result.hits, result.misses], 20
	))
	if result.has("longest_streak_seconds"):
		details.add_child(Style.label("最長連続命中  %.2f 秒" % result.longest_streak_seconds, 20))
	elif result.has("switches_completed"):
		details.add_child(Style.label("切替成功  %d 回" % result.switches_completed, 20))
	elif selected.type == "custom" or selected.target.has("health"):
		var elimination_time := "—" if result.elimination_ms == null else "%.0f ms" % result.elimination_ms
		details.add_child(Style.label("撃破 %d    平均撃破時間 %s" % [result.eliminations, elimination_time], 20))
	elif result.has("hit_regions"):
		details.add_child(Style.label(_humanoid_region_summary(result.hit_regions, "回"), 20))
	if save_error != OK:
		details.add_child(Style.label("自己ベストを保存できませんでした（%s）。" % error_string(save_error), 17, Style.ACCENT))
	elif new_best:
		details.add_child(Style.label("自己ベスト更新", 17, Style.ACCENT))
	elif _best() >= 0:
		details.add_child(Style.label("自己ベスト  %d 点" % _best(), 17, Style.MUTED))
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	body.add_child(buttons)
	buttons.add_child(Style.button("リトライ", _start, true))
	buttons.add_child(Style.button("メニューへ戻る", show_home))


func _humanoid_region_summary(values: Dictionary, unit: String) -> String:
	var parts: PackedStringArray = []
	for region: String in Humanoid.LABELS:
		parts.append("%s %d%s" % [Humanoid.LABELS[region], values.get(region, 0), unit])
	return "    ".join(parts)


func _best() -> int:
	var current := int(Store.number(best_scores.get(_record_key()), -1.0, 0.0, 1000000000.0))
	var legacy := Scenario.legacy_unlimited_record_key(selected)
	if legacy.is_empty():
		return current
	var previous := int(Store.number(best_scores.get(_with_movement_key(legacy)), -1.0, 0.0, 1000000000.0))
	return maxi(current, previous)


func _record_key() -> String:
	return _with_movement_key(Scenario.record_key(selected))


func _with_movement_key(key: String) -> String:
	if selected.player.movement_enabled:
		return (key + JSON.stringify(movement.values)).sha256_text()
	return key


func _clear_screen() -> void:
	if is_instance_valid(session):
		remove_child(session)
		session.queue_free()
		session = null
	if is_instance_valid(page):
		if page is Editor:
			editor_view_state = page.view_state()
		remove_child(page)
		page.queue_free()
		page = null


func _new_page(title: String, back := Callable(), header_action: Button = null, back_caption := "ホーム") -> VBoxContainer:
	_clear_screen()
	page = ColorRect.new()
	page.color = Style.INK
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(page)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_KEEP_SIZE, 38)
	page.add_child(margin)
	var frame := Style.stack(22)
	margin.add_child(frame)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 20)
	frame.add_child(header)
	var brand := Style.label("FPS AIM TRAINING STUDIO", 17, Style.ACCENT)
	brand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(brand)
	header.add_child(Style.label(title, 18, Style.MUTED))
	if header_action != null:
		header.add_child(header_action)
	if back.is_valid():
		header.add_child(Style.button(back_caption, back))
	var separator := HSeparator.new()
	var rule := StyleBoxLine.new()
	rule.color = Style.EDGE
	separator.add_theme_stylebox_override("separator", rule)
	frame.add_child(separator)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	frame.add_child(scroll)
	var body := Style.stack(18)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	return body


func _split(parent: Control, gutter: int) -> HBoxContainer:
	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", gutter)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(split)
	return split


func _field(parent: Control, caption: String, value: float, limits: Array) -> SpinBox:
	var field := Style.spin(value, limits[0], limits[1], limits[2])
	Style.field(parent, caption, field)
	return field


func _result_stat(parent: Control, caption: String, value: String, color := Style.PAPER) -> void:
	var card := Style.panel(parent, 22)
	card.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_child(Style.label(caption, 17, Style.MUTED))
	card.add_child(Style.label(value, 39, color))
