extends SceneTree

const Main = preload("res://scenes/studio.tscn")
const Studio = preload("res://scripts/ui/studio.gd")
const Session = preload("res://scripts/training/static_session.gd")
const Scenario = preload("res://scripts/scenarios/scenario.gd")
const Motion = preload("res://scripts/targets/fixed_tracking_motion.gd")
const Arena = preload("res://scripts/training/arena.gd")
const TargetGroup = preload("res://scripts/targets/target_group.gd")

var failures: Array[String] = []
var test_dir := "res://.godot/phase5-%d" % OS.get_process_id()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	create_timer(20.0).timeout.connect(func() -> void:
		push_error("Phase 5 tests timed out")
		quit(1)
	)
	if DirAccess.make_dir_recursive_absolute(test_dir) != OK:
		push_error("Cannot create test directory")
		quit(1)
		return
	_test_motion()
	_test_group_positions()
	var studio: Studio = Main.instantiate()
	studio.best_path = test_dir.path_join("best.json")
	root.add_child(studio)
	await process_frame
	await _test_group(studio)
	await _test_switching(studio)
	await _test_tracking(studio, "Smooth Tracking")
	await _test_tracking(studio, "Reactive Tracking")
	studio.queue_free()
	for file: String in DirAccess.get_files_at(test_dir):
		DirAccess.remove_absolute(test_dir.path_join(file))
	DirAccess.remove_absolute(test_dir)
	print("Phase 5 tests passed." if failures.is_empty() else "Phase 5 checks failed: %d" % failures.size())
	quit(0 if failures.is_empty() else 1)


func _test_motion() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 113
	var scenario := Scenario.load_standard_drill("smooth_tracking")
	var eye := Scenario.player_position(scenario)
	for pattern: String in ["horizontal", "vertical", "circle"]:
		scenario.target.behavior = pattern
		var motion := Motion.new(scenario.target)
		var first := motion.spawn(eye, rng)
		var second := motion.step(0.17, rng)
		_check(first.distance_to(second) > 0.05, "smooth target moves: " + pattern)
		match pattern:
			"horizontal":
				_check(is_equal_approx(first.y, second.y), "horizontal pattern preserves height")
			"vertical":
				_check(is_equal_approx(first.x, second.x), "vertical pattern preserves x")
			"circle":
				_check(is_equal_approx(first.distance_to(motion.center), second.distance_to(motion.center)),
					"circular motion has a constant radius")
	var reactive := Scenario.load_standard_drill("reactive_tracking")
	var motion := Motion.new(reactive.target)
	motion.spawn(Scenario.player_position(reactive), rng)
	var previous := motion.velocity
	var changed_direction := false
	var varied_speed := false
	var stays_in_bounds := true
	for index in range(400):
		motion.step(1.0 / 120.0, rng)
		changed_direction = changed_direction or previous.normalized().dot(motion.velocity.normalized()) < 0.5
		varied_speed = varied_speed or absf(motion.velocity.length() - previous.length()) > 0.1
		stays_in_bounds = stays_in_bounds and absf(motion.offset.x) <= motion.bounds.x and absf(motion.offset.y) <= motion.bounds.y
	_check(changed_direction and varied_speed and stays_in_bounds, "reactive motion changes heading and speed inside its limits")


func _test_group_positions() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5924
	for mode: String in Scenario.TARGET_GROUPS:
		var scenario := Scenario.load_standard_drill(mode)
		var origin := Scenario.player_position(scenario)
		var x_samples := {}
		var y_samples := {}
		var layouts := {}
		var valid := true
		for round_index in range(12):
			var arena := Arena.new()
			root.add_child(arena)
			var tuning: Dictionary = scenario.target
			arena.target = arena.create_target(tuning.radius, Color.html(tuning.color))
			var group := TargetGroup.new(arena, tuning, origin, mode == "target_switching", rng)
			group.present(0)
			layouts[group.spawn_regions.size()] = true
			for body in group.targets:
				x_samples[snappedi(roundi(body.position.x * 100), 5)] = true
				y_samples[snappedi(roundi(body.position.y * 100), 5)] = true
			valid = valid and _valid_group_positions(group, tuning)
			arena.free()
		_check(valid, "each randomized layout remains in bounds and separated: " + mode)
		_check(x_samples.size() > 12 and y_samples.size() > 12 and layouts.size() > 1,
			"rounds randomize both coordinates and the layout: " + mode)


func _valid_group_positions(group: TargetGroup, tuning: Dictionary) -> bool:
	for index in range(group.targets.size()):
		var center := group.targets[index].position
		if absf(center.x - group.eye.x) > tuning.x_extent + 0.001 or absf(center.y - group.eye.y) > tuning.y_extent + 0.001:
			return false
		if center.y < group.radius + 0.054 or not is_equal_approx(center.z, group.eye.z - tuning.depth):
			return false
		for other in range(index):
			if center.distance_to(group.targets[other].position) < (group.radius + 0.045) * 2.0 - 0.001:
				return false
	return true


func _test_group(studio: Studio) -> void:
	_press(studio, "標準練習モード")
	await process_frame
	await process_frame
	var last := _button(studio, "Target Switching")
	var scroll: ScrollContainer = studio.find_children("*", "ScrollContainer", true, false)[0]
	_check(last.get_global_rect().end.y <= scroll.get_global_rect().end.y, "all standard modes are visible at default size")
	_press(studio, "Multi Target")
	_set_number(studio, 1, "0.65")
	_set_number(studio, 4, "8")
	_set_number(studio, 2, "0.25")
	_set_number(studio, 3, "0.15")
	_press(studio, "この条件で開始")
	var session := studio.session
	await _settle()
	var group := session.target_group
	_check(session.player == null and session.hud_ammo.text == "弾数無制限", "Multi Target is fixed-view with unlimited ammo")
	_check(group.targets.size() == 8 and group.presented_at.size() == 8, "configured count is displayed")
	_check(_valid_group_positions(group, session.scenario.target) and session.scenario.target.x_extent >= 2.75,
		"large targets fit without overlap")
	var first := group.targets[0]
	var second := group.targets[1]
	var original_first := first.position
	var original_second := second.position
	var untouched := group.targets[2].position
	_shoot_at(session, first)
	_shoot_at(session, second)
	await _settle()
	_check(session.stats.hits == 2 and session.stats.score() == 200, "independent targets accept successive clicks")
	_check(first.position != original_first and second.position != original_second and group.targets[2].position == untouched,
		"only consumed targets move to different slots")
	_check(group.presented_at.size() == 8 and group.targets.all(func(body: StaticBody3D) -> bool: return body.visible),
		"hits replenish the configured population")
	var replacements := {}
	var valid := true
	group.rng.seed = 279
	for index in range(40):
		var old_position := first.position
		group.accept(first)
		group.present(index)
		valid = valid and first.position != old_position and _valid_group_positions(group, session.scenario.target)
		replacements[first.position.snapped(Vector3.ONE * 0.0001)] = true
	_check(valid and group.targets[2].position == untouched, "replacement keeps other centers and spacing at minimum extents")
	_check(replacements.size() > group.spawn_regions.size(), "repeated replacements use different positions within regions")
	session.abandoned.emit()


func _test_switching(studio: Studio) -> void:
	_pick(studio, "Target Switching")
	_set_number(studio, 4, "3")
	_press(studio, "この条件で開始")
	var session := studio.session
	await _settle()
	var group := session.target_group
	var initial := group.active
	var layout := group.targets.map(func(body: StaticBody3D) -> Vector3: return body.position)
	_check(initial != null and group.targets.size() == 3 and group.cue.visible and group.cue.text == "▼",
		"one of the configured targets is marked")
	var wrong := group.targets[1] if group.targets[0] == initial else group.targets[0]
	_shoot_at(session, wrong)
	await _settle()
	_check(session.stats.hits == 0 and group.active == initial, "an unmarked target is a miss and does not switch")
	_shoot_at(session, initial)
	await _settle()
	_check(session.stats.hits == 1 and session.stats.reactions == 0 and group.active != initial,
		"first hit advances the marker without counting a switch time")
	_check(group.targets.map(func(body: StaticBody3D) -> Vector3: return body.position) == layout,
		"switching the cue keeps the targets stationary")
	await create_timer(0.1).timeout
	_shoot_at(session, group.active)
	await _settle()
	_check(session.stats.hits == 2 and session.stats.reactions == 1 and is_equal_approx(session.stats.accuracy(), 200.0 / 3.0),
		"only correct switches enter the timing and accuracy results")
	session.duration_usec = session.clock.elapsed(Time.get_ticks_usec()) + 25000
	var result: Dictionary = await session.completed
	_check(result.switches_completed == 1 and result.reaction_ms >= 80.0 and _label_present(studio, "平均切替時間"),
		"results show successful switches and their mean time")
	_press(studio, "メニューへ戻る")


func _test_tracking(studio: Studio, title: String) -> void:
	_pick(studio, title)
	await process_frame
	await process_frame
	var start := _button(studio, "この条件で開始")
	_check(start.get_global_rect().end.y <= studio.size.y, "start remains visible: " + title)
	_set_number(studio, 1, "0.44")
	_set_number(studio, 4, "4.0")
	if title == "Smooth Tracking":
		_select(_option(studio, "移動パターン"), 2)
	start.pressed.emit()
	var session := studio.session
	await _settle()
	_check(session.player == null and session.tracking != null and session.fixed_motion != null,
		"tracking uses the fixed camera: " + title)
	_check(is_equal_approx(session.scenario.target.radius, 0.44) and is_equal_approx(session.fixed_motion.tuning.speed, 4.0),
		"radius and speed reach the active session: " + title)
	var first := session.arena.target.position
	for index in range(25):
		await physics_frame
		session.camera.look_at(session.arena.target.global_position)
	_check(first.distance_to(session.arena.target.position) > 0.05 and session.tracking.aimed_seconds > 0.1,
		"physics moves the dummy and records aim: " + title)
	if title == "Smooth Tracking":
		_check(session.fixed_motion.tuning.behavior == "circle", "circle setting applies")
	_check(session.hud_ammo.text == "弾数無制限", "fixed tracking has unlimited ammo")
	session.abandoned.emit()


func _pick(studio: Studio, caption: String) -> void:
	_press(studio, "標準練習モード")
	_press(studio, caption)


func _set_number(studio: Studio, index: int, text: String) -> void:
	var field: SpinBox = studio.find_children("*", "SpinBox", true, false)[index]
	field.get_line_edit().text = text
	field.apply()


func _option(studio: Studio, caption: String) -> OptionButton:
	for field: OptionButton in studio.find_children("*", "OptionButton", true, false):
		var label: Label = field.get_parent().get_child(0)
		if label.text == caption:
			return field
	_check(false, "option present: " + caption)
	return null


func _select(field: OptionButton, index: int) -> void:
	field.select(index)
	field.item_selected.emit(index)


func _settle() -> void:
	await physics_frame
	await physics_frame
	await process_frame
	await process_frame


func _shoot_at(session: Session, target: StaticBody3D) -> void:
	session.camera.look_at(target.global_position)
	for down: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		Input.parse_input_event(event)
	Input.flush_buffered_events()


func _press(studio: Studio, caption: String) -> void:
	_button(studio, caption).pressed.emit()


func _button(studio: Studio, caption: String) -> Button:
	for button: Button in studio.find_children("*", "Button", true, false):
		if button.text == caption:
			return button
	_check(false, "button present: " + caption)
	return null


func _label_present(studio: Studio, caption: String) -> bool:
	for label: Label in studio.find_children("*", "Label", true, false):
		if label.text == caption:
			return true
	return false


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)
