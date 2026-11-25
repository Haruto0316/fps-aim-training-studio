extends SceneTree

const Main = preload("res://scenes/studio.tscn")
const Studio = preload("res://scripts/ui/studio.gd")
const Session = preload("res://scripts/training/static_session.gd")
const Aim = preload("res://scripts/input/aim_settings.gd")
const Scenario = preload("res://scripts/scenarios/scenario.gd")
const Preview = preload("res://scripts/ui/drill_preview.gd")
const Draft = preload("res://scripts/editor/editor_draft.gd")
const Custom = preload("res://scripts/scenarios/custom_scenario.gd")

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	create_timer(20.0).timeout.connect(func() -> void:
		push_error("Practice options test timed out")
		quit(1)
	)
	var studio: Studio = Main.instantiate()
	var test_dir := "user://practice-options-%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(test_dir)
	studio.aim = Aim.new(test_dir.path_join("settings.json"))
	studio.best_path = test_dir.path_join("best.json")
	studio.custom_library_dir = test_dir
	root.add_child(studio)
	await process_frame
	_check(_captions(studio.page) == ["練習モード", "設定", "終了"], "start screen has exactly three actions")
	_press(studio, "設定")
	_check_arrow_steps(studio.page, "home")
	_check_dpi_choices(studio.page)
	studio.show_home()
	_press(studio, "練習モード")
	_check(_captions(studio.page) == ["ホーム", "トラッキング", "フリック", "カスタム練習"], "custom practice is beside both categories")
	_press(studio, "カスタム練習")
	_check(_button(studio, "3D エディター") != null, "custom practice opens directly from the selector")
	_press(studio, "戻る")
	_press(studio, "フリック")
	var flick := ["Static Clicking", "Multi Target", "Target Switching", "移動練習"]
	var flick_listing := flick.duplicate()
	flick_listing.insert(1, "Apex 人型ダミー")
	_check(_captions(studio.page).slice(2) == flick_listing, "flick list includes the Apex humanoid drill")
	_press(studio, "戻る")
	_press(studio, "トラッキング")
	var tracking := ["Smooth Tracking", "Reactive Tracking", "Strafe Tracking", "Cover Tracking", "Movement Tracking", "Elimination Training", "移動ダミー撃破"]
	_check(_captions(studio.page).slice(2) == tracking, "tracking list contains only tracking drills")
	_press(studio, "Smooth Tracking")
	_press(studio, "戻る")
	_check(_captions(studio.page).slice(2) == tracking, "back from drill details returns to its list")
	studio.show_home()
	for mode: String in flick:
		await _check_mode(studio, mode, "フリック")
	for mode: String in tracking:
		await _check_mode(studio, mode, "トラッキング")
	await _check_humanoid(studio)
	await _check_custom(studio)
	studio.queue_free()
	for file: String in DirAccess.get_files_at(test_dir):
		DirAccess.remove_absolute(test_dir.path_join(file))
	DirAccess.remove_absolute(test_dir)
	print("Practice options tests passed." if failures.is_empty() else "Practice options failures: %d" % failures.size())
	quit(0 if failures.is_empty() else 1)


func _check_mode(studio: Studio, mode: String, group: String) -> void:
	_press(studio, "練習モード")
	_press(studio, group)
	var cards := _previews(studio.page)
	_check(cards.size() == (5 if group == "フリック" else 7), "each mode card has a preview")
	_press(studio, mode)
	await process_frame
	await process_frame
	var previews := _previews(studio.page)
	_check(previews.size() == 1, "a preview exists on the mode details: " + mode)
	if not previews.is_empty():
		var preview: Preview = previews[0]
		var age := preview.time
		await _ticks(3)
		_check(preview.time > age and preview.scenario.type == studio.selected.type, "the mode preview animates: " + mode)
	var start := _button(studio, "この条件で開始")
	_check(start.get_global_rect().end.y <= studio.size.y, "start is accessible: " + mode)
	var fields := studio.page.find_children("*", "SpinBox", true, false)
	var radius: SpinBox = fields[1]
	_check(not studio.selected.weapon.has("reload_enabled"), "mode has no reload setting: " + mode)
	radius.get_line_edit().text = "0.47"
	start.pressed.emit()

	var session := studio.session
	await _ticks(8)
	var target := session.arena.target if session.target_group == null else session.target_group.targets[0]
	var collider: CollisionShape3D = target.get_child(0)
	var mesh: MeshInstance3D = target.get_child(1)
	_check(is_equal_approx(collider.shape.radius, 0.47) and is_equal_approx(mesh.mesh.radius, 0.47),
		"configured radius changes appearance and collision: " + mode)
	_check(session.hud_ammo.text == "弾数無制限", "HUD shows unlimited ammo: " + mode)
	if mode == "Static Clicking":
		await _check_pause_settings(studio, session)
	elif mode == "Smooth Tracking":
		var previous_key := Scenario.legacy_unlimited_record_key(studio.selected)
		studio.best_scores[previous_key] = 1300
		_check(studio._best() == 1300, "an unlimited personal best is still displayed")
	session.abandoned.emit()


func _check_pause_settings(studio: Studio, session: Session) -> void:
	_key(KEY_ESCAPE)
	var frozen := session.clock.elapsed(Time.get_ticks_usec())
	var start_gain := session.camera.degrees_per_count
	_press(studio, "設定")
	await process_frame
	await process_frame
	var fields := _check_arrow_steps(session.pause_settings, "pause")
	var base: SpinBox = fields[0]
	var before := base.value
	_click_arrow(base, true)
	_check(is_equal_approx(base.value, before + 0.1), "the up button adds 0.1 (%f → %f)" % [before, base.value])
	_click_arrow(base, false)
	_check(is_equal_approx(base.value, before), "the down button subtracts 0.1")
	base.get_line_edit().text = "0.1735"
	var preset: OptionButton = session.pause_settings.find_child("SensitivityPreset", true, false)
	preset.select(1)
	preset.item_selected.emit(1)
	_key(KEY_ESCAPE)
	_check(session.pause_settings == null and session.paused and session.camera.degrees_per_count == start_gain,
		"Escape cancels the pending edit and returns to the pause menu")
	_check(is_equal_approx(studio.aim.values.sensitivity_by_preset.generic, before), "a canceled preset switch does not edit saved values")
	await process_frame

	_press(studio, "設定")
	fields = session.pause_settings.find_children("*", "SpinBox", true, false)
	base = fields[0]
	preset = session.pause_settings.find_child("SensitivityPreset", true, false)
	preset.select(2)
	preset.item_selected.emit(2)
	base.get_line_edit().text = "1.7354"
	fields[3].get_line_edit().text = "67.5"
	var dpi := _check_dpi_choices(session.pause_settings)
	dpi.select(4)
	dpi.item_selected.emit(4)
	_press(studio, "保存してポーズへ戻る")
	await _ticks(4)
	var saved := Aim.new(studio.aim.save_path)
	_check(session.paused and studio.session == session and session.clock.elapsed(Time.get_ticks_usec()) == frozen,
		"saving settings keeps the same round paused and the timer frozen")
	_check(session.camera.degrees_per_count.is_equal_approx(saved.degrees_per_count(saved.values))
		and session.camera.degrees_per_count != start_gain and is_equal_approx(session.camera.fov, 67.5)
		and saved.values.preset == "apex" and is_equal_approx(saved.values.sensitivity, 1.7354),
		"precise game sensitivity saves and immediately updates the same camera")
	_check(saved.values.dpi == 3200, "pause DPI selection persists")
	_key(KEY_ESCAPE)
	await _ticks(4)
	_check(not session.paused and session.clock.elapsed(Time.get_ticks_usec()) > frozen, "resuming continues the same timer")


func _check_arrow_steps(parent: Node, location: String) -> Array[Node]:
	var fields := parent.find_children("*", "SpinBox", true, false)
	_check(fields.size() == 4, "only sensitivity and FOV use numeric fields at " + location)
	for index in range(3):
		var field: SpinBox = fields[index]
		_check(is_equal_approx(field.custom_arrow_step, 0.1), "arrow step is 0.1 at " + location)
	return fields


func _check_dpi_choices(parent: Node) -> OptionButton:
	var dpi: OptionButton = parent.find_child("MouseDpi", true, false)
	var choices: Array[int] = []
	for index in range(dpi.item_count):
		choices.append(dpi.get_item_id(index))
	_check(choices == [400, 800, 1000, 1600, 3200], "DPI is limited to the five requested values")
	return dpi


func _captions(parent: Node) -> Array:
	return parent.find_children("*", "Button", true, false).map(func(button: Button) -> String: return button.text)


func _click_arrow(field: SpinBox, up: bool) -> void:
	var bounds := field.get_global_rect()
	var arrow_x := bounds.end.x - field.get_theme_constant("buttons_width") * 0.5
	var point := Vector2(arrow_x, bounds.position.y + bounds.size.y * (0.25 if up else 0.75))
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = point
	event.global_position = point
	event.pressed = true
	root.push_input(event, true)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event, true)


func _check_custom(studio: Studio) -> void:
	var draft := Draft.new()
	var target_id := draft.add("moving_target", Vector3(0, 1.5, -5))
	var left := draft.add("route_point", Vector3(-3, 1.5, -5))
	var right := draft.add("route_point", Vector3(3, 2.5, -5))
	draft.edit(target_id, {"route_points": [left, right]})
	var document: Dictionary = draft.document()
	document.weapon.merge({"reload_enabled": true, "magazine": 1, "reload_seconds": 30.0})
	var normalized := Custom.validate(document)
	_check(not normalized.is_empty() and not normalized.weapon.has("reload_enabled")
		and not normalized.weapon.has("magazine") and not normalized.weapon.has("reload_seconds"),
		"old custom configurations still validate and discard obsolete ammo options")
	_check(Custom.save(document, studio.custom_library_dir) == OK, "custom scenario is saved")
	_press(studio, "練習モード")
	_press(studio, "カスタム練習")
	await _ticks(4)
	var previews := _previews(studio.page)
	var preview: Preview = previews[0]
	_check(previews.size() == 1 and preview.paths[target_id].length > 0.0 and preview.time > 0.0,
		"custom preview animates the authored path")
	_press(studio, "プレイ")
	await _ticks(8)
	_check(studio.session.hud_ammo.text == "弾数無制限", "custom practice also has unlimited ammo")


func _check_humanoid(studio: Studio) -> void:
	_press(studio, "練習モード")
	_press(studio, "フリック")
	_press(studio, "Apex 人型ダミー")
	_check(_previews(studio.page).size() == 1, "Apex drill has a preview")
	var fields := studio.page.find_children("*", "SpinBox", true, false)
	fields[1].get_line_edit().text = "2.2"
	_press(studio, "この条件で開始")
	var session := studio.session
	await _ticks(8)
	_check(session.humanoid != null and is_equal_approx(session.scenario.target.height, 2.2)
		and session.hud_ammo.text == "弾数無制限", "Apex starts with the chosen size and unlimited shots")
	var expected := {"head": 200, "upper_body": 100, "lower_body": 50}
	var parts := {}
	for part: CollisionShape3D in session.humanoid.find_children("*", "CollisionShape3D", false, false):
		var region: String = part.get_meta("hit_region")
		if not parts.has(region):
			parts[region] = part
	for region: String in expected:
		var previous := session.stats.score()
		var part: CollisionShape3D = parts[region]
		session.camera.look_at(part.global_position)
		_shoot()
		await _ticks(8)
		_check(session.stats.score() - previous == expected[region] and session.humanoid_hits.get(region) == 1,
			"hitting the physical collider scores its region: " + region)
		_check(session.hud_target.text.contains("+%d 点" % expected[region]), "HUD reports the points for the region")
	session.camera.look_at(session.camera.global_position + Vector3.RIGHT)
	_shoot()
	await _ticks(8)
	session.duration_usec = session.clock.elapsed(Time.get_ticks_usec()) + 25000
	var result: Dictionary = await session.completed
	_check(result.score == 350 and result.hits == 3 and result.shots == 4
		and result.hit_regions == {"head": 1, "upper_body": 1, "lower_body": 1}, "results include each hit region and exclude misses")
	_press(studio, "メニューへ戻る")


func _shoot() -> void:
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		_send(event)


func _previews(parent: Node) -> Array[Node]:
	return parent.find_children("*", "Control", true, false).filter(func(node: Node) -> bool: return node is Preview)


func _ticks(count: int) -> void:
	for index in range(count):
		await physics_frame


func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	_send(event)
	var released := event.duplicate()
	released.pressed = false
	_send(released)


func _send(event: InputEvent) -> void:
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _press(studio: Studio, caption: String) -> void:
	var button := _button(studio, caption)
	if button != null:
		button.pressed.emit()


func _button(studio: Studio, caption: String) -> Button:
	for button: Button in studio.find_children("*", "Button", true, false):
		if button.text == caption and button.is_visible_in_tree() and not button.is_queued_for_deletion():
			return button
	_check(false, "button present: " + caption)
	return null


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)
