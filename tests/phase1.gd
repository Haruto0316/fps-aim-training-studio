extends SceneTree

const Studio = preload("res://scripts/ui/studio.gd")
const Aim = preload("res://scripts/input/aim_settings.gd")
const Camera = preload("res://scripts/input/aim_camera.gd")
const Clock = preload("res://scripts/scoring/active_clock.gd")
const Stats = preload("res://scripts/scoring/run_stats.gd")
const Store = preload("res://scripts/persistence/json_store.gd")
const Scenario = preload("res://scripts/scenarios/scenario.gd")
const Main = preload("res://scenes/studio.tscn")

var failures: Array[String] = []
var test_path := "res://.godot/phase1-%d" % OS.get_process_id()


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	create_timer(20.0).timeout.connect(func() -> void:
		push_error("Phase 1 smoke test timed out")
		quit(1)
	)
	if DirAccess.make_dir_recursive_absolute(test_path) != OK:
		push_error("Cannot create test directory: " + test_path)
		quit(1)
		return
	_test_data()
	_test_camera_and_score()
	await _test_playthrough()
	for file: String in DirAccess.get_files_at(test_path):
		DirAccess.remove_absolute(test_path.path_join(file))
	DirAccess.remove_absolute(test_path)
	print("Phase 1 tests passed." if failures.is_empty() else "Phase 1 checks failed: %d" % failures.size())
	quit(0 if failures.is_empty() else 1)


func _test_data() -> void:
	var path := test_path.path_join("data.json")
	_check(Store.write(path, {"schema_version": 99}) == OK, "write first JSON")
	_check(Scenario.load_static(path).is_empty(), "reject unsupported scenario schema")
	_check(Store.write(path, {"schema_version": 1, "preset": "unknown", "dpi": 0, "sensitivity": "junk"}) == OK, "overwrite JSON")
	var settings := Aim.new(path)
	_check(settings.values.preset == "generic", "unknown preset falls back")
	_check(settings.values.dpi == 100 and settings.values.sensitivity == settings.defaults.sensitivity, "safe settings limits and defaults")
	var migrated := settings.validate({"schema_version": 1, "preset": "apex", "sensitivity": 2.25})
	_check(migrated.sensitivity_by_preset == {"generic": 0.035, "valorant": 0.5, "apex": 2.25},
		"legacy sensitivity is retained for its selected preset only")
	_check(Store.write(path + ".bak", settings.defaults) == OK, "create recovery fixture")
	var invalid := FileAccess.open(path, FileAccess.WRITE)
	invalid.store_string("{broken")
	invalid.close()
	_check(Store.read(path).is_empty(), "reject malformed JSON")
	_check(Aim.new(path).values.dpi == 800, "restore backup after malformed primary")
	_check(settings.save(settings.defaults) == OK and not FileAccess.file_exists(path + ".bak"), "replace primary and clear stale backup")

	var scenario := Scenario.load_static()
	_check(not scenario.is_empty(), "load built-in scenario")
	var tuned := Scenario.with_options(scenario, 1, {"radius": 100, "x_extent": -5, "y_extent": 1.0})
	_check(tuned.duration_seconds == 5 and tuned.target.radius == 0.65 and tuned.target.x_extent == 0.25, "scenario limits")
	_check(scenario.duration_seconds == 30 and scenario.target.radius == 0.28, "scenario edits use an independent copy")
	_check(Scenario.record_key(tuned) != Scenario.record_key(scenario), "record keys vary by conditions")


func _test_camera_and_score() -> void:
	var settings := Aim.new(test_path.path_join("missing.json"))
	var profile := settings.defaults.duplicate()
	profile.preset = "apex"
	profile.sensitivity = 2.0
	profile.horizontal = 1.5
	profile.vertical = 0.5
	var angular := settings.degrees_per_count(profile)
	_check(angular.is_equal_approx(Vector2(0.044, 0.044)), "Apex uses its game scale on both axes")
	_check(is_equal_approx(settings.cm_per_turn(profile), 914.4 / (800.0 * 0.044)), "cm per turn")
	profile.preset = "generic"
	_check(settings.degrees_per_count(profile).is_equal_approx(Vector2(3.0, 1.0)), "generic axis multipliers remain effective")

	var first := Camera.new()
	var second := Camera.new()
	first.degrees_per_count = angular
	second.degrees_per_count = angular
	first.apply_motion(Vector2(110, -90))
	for index in range(10):
		second.apply_motion(Vector2(11, -9))
	_check(first.rotation.is_equal_approx(second.rotation), "sensitivity independent of event grouping")
	first.apply_motion(Vector2(0, 100000.0))
	_check(is_equal_approx(first.pitch, -89.0), "camera clamps pitch")
	for game: String in ["apex", "valorant"]:
		profile.preset = game
		profile.sensitivity = 1.0 if game == "apex" else 0.3
		first.degrees_per_count = settings.degrees_per_count(profile)
		profile.sensitivity += 0.5
		second.degrees_per_count = settings.degrees_per_count(profile)
		first.yaw = 0.0
		second.yaw = 0.0
		first.apply_motion(Vector2(-1000, 0))
		second.apply_motion(Vector2(-1000, 0))
		var expected := 11.0 if game == "apex" else 34.98
		_check(absf(second.yaw - first.yaw - expected) < 0.0001, game + " +0.5 matches the reference hipfire rotation change")
	first.free()
	second.free()

	var clock := Clock.new()
	clock.start(100)
	clock.pause(300)
	_check(clock.elapsed(800) == 200, "paused clock stays frozen")
	clock.resume(800)
	_check(clock.elapsed(900) == 300, "paused time excluded on resume")
	var stats := Stats.new(100)
	_check(stats.snapshot().reaction_ms == null and stats.accuracy() == 0.0, "zero-shot stats")
	stats.register_shot(false, 500000)
	stats.register_shot(true, 180000)
	stats.register_shot(true, 220000)
	_check(stats.score() == 200 and stats.snapshot().misses == 1, "score and misses")
	_check(is_equal_approx(stats.accuracy(), 200.0 / 3.0) and stats.snapshot().reaction_ms == 200.0, "accuracy and mean reaction")


func _test_playthrough() -> void:
	var studio: Studio = Main.instantiate()
	studio.aim = Aim.new(test_path.path_join("settings.json"))
	studio.best_path = test_path.path_join("best.json")
	root.add_child(studio)
	await process_frame
	_press(studio, "設定")
	var settings_inputs := studio.find_children("*", "SpinBox", true, false)
	_check(settings_inputs.size() == 5, "settings form")
	var base: SpinBox = settings_inputs[0]
	var preset: OptionButton = studio.page.find_child("SensitivityPreset", true, false)
	base.get_line_edit().text = "0.048"
	_select_preset(preset, 1)
	_check(is_equal_approx(base.value, 0.5) and not settings_inputs[1].get_parent().visible, "VALORANT shows its value and uses fixed axis scaling")
	base.get_line_edit().text = "0.315"
	_select_preset(preset, 2)
	base.get_line_edit().text = "1.85"
	_select_preset(preset, 1)
	_check(is_equal_approx(base.value, 0.315) and is_equal_approx(base.get_line_edit().text.to_float(), 0.315), "preset switches restore the edited value immediately")
	_select_preset(preset, 0)
	_check(is_equal_approx(base.value, 0.048) and settings_inputs[1].get_parent().visible, "generic sensitivity and axis options return")
	settings_inputs[3].get_line_edit().text = "70"
	_press(studio, "保存してホームへ")
	var settings := Aim.new(studio.aim.save_path)
	_check(is_equal_approx(settings.values.sensitivity, 0.048) and settings.values.vertical_fov == 70.0, "settings save via UI and reload")
	_check(is_equal_approx(settings.values.sensitivity_by_preset.valorant, 0.315)
		and is_equal_approx(settings.values.sensitivity_by_preset.apex, 1.85), "both other presets survive save and reload")

	_press(studio, "標準練習モード")
	_press(studio, "Static Clicking")
	var options := studio.find_children("*", "SpinBox", true, false)
	options[0].get_line_edit().text = "5"
	_press(studio, "この条件で開始")
	var session := studio.session
	_mouse_motion()
	_check(session.camera.yaw == 0.0, "menu transition motion ignored")
	await process_frame
	await physics_frame
	await process_frame
	_check(session.camera.fov == 70.0 and session.duration_usec == 5000000, "FOV and mode settings applied")
	_check(session.arena.target.visible and session.target_since >= 0, "initial target presented")
	var original_position := session.arena.target.position

	_mouse_motion()
	_check(is_equal_approx(session.camera.yaw, -1.2) and session.camera.pitch == 0.0, "session uses unscaled mouse motion")

	var obstacle_position: Vector3 = session.camera.position.lerp(original_position, 0.5)
	session.arena.box(obstacle_position, Vector3.ONE, Color.WHITE, true)
	var obstacle := session.arena.get_child(-1)
	session.camera.look_at(original_position)
	await _settle_shot()
	_shoot()
	await _settle_shot()
	_check(session.stats.shots == 1 and session.stats.hits == 0, "obstacle occludes the target")
	session.arena.remove_child(obstacle)
	obstacle.queue_free()
	await _settle_shot()
	session.camera.look_at(session.arena.target.position)
	_shoot()
	_shoot()
	await _settle_shot()
	_check(session.stats.hits == 1 and session.stats.shots == 3, "hit and no double hit on the same presentation")
	_check(session.arena.target.visible and not session.arena.target.position.is_equal_approx(original_position), "target relocates after hit")
	session.camera.look_at(session.arena.target.position)
	_shoot()
	await _settle_shot()
	_check(session.stats.hits == 2, "relocated target uses updated physics position")

	_escape()
	_check(session.paused and session.pause_layer.visible and not session.crosshair.visible, "Escape opens pause UI")
	var stopped: int = session.clock.elapsed(Time.get_ticks_usec())
	await create_timer(0.15).timeout
	_check(session.clock.elapsed(Time.get_ticks_usec()) == stopped, "pause time excluded")
	_escape()
	_check(not session.paused and session.crosshair.visible, "Escape resumes")

	var result: Dictionary = await session.completed
	_check(result.score == 200 and result.shots == 4 and result.hits == 2 and result.accuracy == 50.0, "timed run results")
	_check(studio.session == null and _has_label(studio, "自己ベスト更新"), "result page and personal best")
	var persisted := Store.read(studio.best_path)
	_check(persisted.get("scores", {}).get(Scenario.record_key(studio.selected)) == 200, "personal best persists")
	_press(studio, "リトライ")
	_check(studio.session.stats.shots == 0 and studio.session.duration_usec == 5000000, "retry keeps conditions and resets score")
	studio.session.abandoned.emit()
	_check(studio.session == null and _has_label(studio, "エイム練習"), "return to home")
	studio.queue_free()


func _settle_shot() -> void:
	await physics_frame
	await physics_frame
	await process_frame
	await process_frame


func _shoot() -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	_send_pressed_and_released(event)


func _mouse_motion() -> void:
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(400, 400)
	motion.screen_relative = Vector2(25, 0)
	Input.parse_input_event(motion)
	Input.flush_buffered_events()


func _escape() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	_send_pressed_and_released(event)


func _send_pressed_and_released(event: InputEvent) -> void:
	event.pressed = true
	Input.parse_input_event(event)
	var released := event.duplicate()
	released.pressed = false
	Input.parse_input_event(released)
	Input.flush_buffered_events()


func _select_preset(preset: OptionButton, index: int) -> void:
	preset.select(index)
	preset.item_selected.emit(index)


func _press(studio: Studio, caption: String) -> void:
	for button: Button in studio.find_children("*", "Button", true, false):
		if button.text == caption:
			button.pressed.emit()
			return
	_check(false, "button present: " + caption)


func _has_label(studio: Studio, caption: String) -> bool:
	for label: Label in studio.find_children("*", "Label", true, false):
		if label.text == caption:
			return true
	return false


func _check(condition: bool, description: String) -> void:
	if not condition:
		failures.append(description)
		push_error(description)
