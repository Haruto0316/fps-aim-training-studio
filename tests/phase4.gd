extends SceneTree

const Studio = preload("res://scripts/ui/studio.gd")
const Session = preload("res://scripts/training/static_session.gd")
const Main = preload("res://scenes/studio.tscn")
const Scenario = preload("res://scripts/scenarios/scenario.gd")
const Tracking = preload("res://scripts/scoring/tracking_stats.gd")
const MovementSettings = preload("res://scripts/movement/movement_settings.gd")

var failures: Array[String] = []
var test_dir := "res://.godot/phase4-%d" % OS.get_process_id()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	create_timer(20.0).timeout.connect(func() -> void:
		push_error("Phase 4 smoke test timed out")
		quit(1)
	)
	if DirAccess.make_dir_recursive_absolute(test_dir) != OK:
		push_error("Cannot create test directory")
		quit(1)
		return
	_check(Scenario.load_mobile_drill("missing").is_empty(), "unknown drill is rejected")
	_test_hit_clock()
	var studio: Studio = Main.instantiate()
	studio.best_path = test_dir.path_join("best.json")
	studio.movement = MovementSettings.new(test_dir.path_join("unused-movement-profile.json"))
	root.add_child(studio)
	await process_frame
	await _test_strafe(studio)
	await _test_cover(studio)
	await _test_jump(studio)
	await _test_elimination(studio)
	studio.queue_free()
	for file: String in DirAccess.get_files_at(test_dir):
		DirAccess.remove_absolute(test_dir.path_join(file))
	DirAccess.remove_absolute(test_dir)
	print("Phase 4 tests passed." if failures.is_empty() else "Phase 4 checks failed: %d" % failures.size())
	quit(0 if failures.is_empty() else 1)


func _test_hit_clock() -> void:
	var tracking := Tracking.new()
	_check(tracking.accuracy() == null, "no eligible time returns no tracking result")
	tracking.shot(true, 0, 150000)
	tracking.shot(true, 100000, 150000)
	tracking.shot(true, 200000, 150000)
	tracking.shot(false, 300000, 150000)
	tracking.shot(true, 400000, 150000)
	tracking.shot(true, 1000000, 150000)
	tracking.shot(true, 1100000, 150000)
	_check(tracking.longest_usec == 200000, "misses and long pauses in fire break the hit streak")


func _test_strafe(studio: Studio) -> void:
	_pick(studio, "Strafe Tracking")
	var fields := studio.find_children("*", "SpinBox", true, false)
	var speed_field: SpinBox = fields[4]
	speed_field.get_line_edit().text = "2.4"
	_press(studio, "この条件で開始")
	var session := studio.session
	await _ticks(8)
	_check(is_equal_approx(session.strafe.tuning.speed, 2.4), "UI target speed is applied")
	var previous_x := session.arena.target.position.x
	await _aim_ticks(session, 22)
	_check(absf(session.arena.target.position.x - previous_x) > 0.03, "target strafes in the arena")
	_check(session.tracking.accuracy() > 25.0 and session.stats.shots == 0, "tracking is sampled independently of firing")
	var lock_time := session.tracking.aimed_seconds
	var exposed_time := session.tracking.visible_seconds
	session.camera.look_at(session.camera.global_position + Vector3.RIGHT)
	await _ticks(18)
	_check(is_equal_approx(session.tracking.aimed_seconds, lock_time) and session.tracking.visible_seconds > exposed_time,
		"looking away lowers tracking accuracy")
	exposed_time = session.tracking.visible_seconds
	_escape()
	await _ticks(8)
	_check(session.paused and is_equal_approx(session.tracking.visible_seconds, exposed_time), "paused samples are excluded")
	_escape()
	await _aim_ticks(session, 5)
	_mouse(true)
	await _aim_ticks(session, 55)
	_mouse(false)
	_check(session.stats.hits >= 3 and session.tracking.longest_usec >= 180000, "automatic hits produce a measured streak")
	_check(session.stats.eliminations == 0 and session.arena.target.visible, "tracking target remains available")
	session.duration_usec = session.clock.elapsed(Time.get_ticks_usec()) + 25000
	var result: Dictionary = await session.completed
	_check(result.tracking_accuracy > 0.0 and result.tracking_accuracy < 100.0 and result.longest_streak_seconds > 0.0,
		"tracking result and streak are published")
	_check(studio.session == null and _has_label(studio, "追従精度"), "tracking result is visible on the results page")
	_press(studio, "メニューへ戻る")


func _test_cover(studio: Studio) -> void:
	_pick(studio, "Cover Tracking")
	var fields := studio.find_children("*", "SpinBox", true, false)
	fields[4].get_line_edit().text = "0.1"
	_press(studio, "この条件で開始")
	var session := studio.session
	await _ticks(8)
	_check(is_equal_approx(session.strafe.tuning.speed, 0.1), "cover drill uses the chosen pace")
	_target_x(session, 0.0)
	await _aim_ticks(session, 6)
	var before := session.tracking.visible_seconds
	_mouse(true)
	_mouse(false)
	await _aim_ticks(session, 20)
	_check(is_equal_approx(session.tracking.visible_seconds, before), "cover excludes a fully hidden target from tracking")
	_check(session.stats.shots == 1 and session.stats.hits == 0, "cover intercepts fire")
	_key(KEY_D, true)
	await _aim_ticks(session, 138)
	_key(KEY_D, false)
	await _aim_ticks(session, 6)
	_check(session.player.position.x > 4.5, "WASD movement can open a line of sight around cover")
	_mouse(true)
	_mouse(false)
	await _aim_ticks(session, 7)
	_check(session.tracking.visible_seconds > before and session.stats.hits == 1,
		"emerging restores tracking and hits: %s shots, %s hits, %s seconds, camera %s, target %s" %
		[session.stats.shots, session.stats.hits, session.tracking.visible_seconds,
		session.camera.global_position, session.arena.target.global_position])
	session.abandoned.emit()


func _test_jump(studio: Studio) -> void:
	_pick(studio, "Movement Tracking")
	_press(studio, "この条件で開始")
	var session := studio.session
	await _ticks(8)
	var highest := session.strafe.base_y
	var has_landed := false
	var changed_direction := false
	var previous_direction := session.strafe.direction
	for index in range(260):
		await physics_frame
		var y := session.arena.target.position.y
		highest = maxf(highest, y)
		has_landed = has_landed or (highest > session.strafe.base_y + 0.55 and y < session.strafe.base_y + 0.02)
		changed_direction = changed_direction or session.strafe.direction != previous_direction
	_check(highest > session.strafe.base_y + 0.75 and has_landed and changed_direction, "jumping target rises, lands and reverses")
	session.abandoned.emit()


func _test_elimination(studio: Studio) -> void:
	_pick(studio, "Elimination Training")
	_press(studio, "この条件で開始")
	var session := studio.session
	await _ticks(8)
	_check(session.tracking == null and session.strafe.health == 175, "elimination uses the durable target profile")
	_aim(session)
	_mouse(true)
	for index in range(240):
		await physics_frame
		if session.stats.eliminations > 0:
			break
		_aim(session)
	_mouse(false)
	_check(session.stats.eliminations == 1 and session.stats.hits == 7 and session.stats.score() == 1050,
		"modified HP and elimination bonus apply")
	_check(not session.arena.target.visible, "eliminated target is hidden")
	await create_timer(0.75).timeout
	_check(session.arena.target.visible and session.strafe.health == 175, "durable target respawns with full HP")
	session.abandoned.emit()


func _target_x(session: Session, value: float) -> void:
	session.arena.target.position.x = value
	session.arena.target.force_update_transform()


func _aim_ticks(session: Session, count: int) -> void:
	for index in range(count):
		await physics_frame
		_aim(session)


func _aim(session: Session) -> void:
	session.camera.look_at(session.arena.target.global_position)


func _ticks(count: int) -> void:
	for index in range(count):
		await physics_frame


func _mouse(down: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = down
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _escape() -> void:
	_key(KEY_ESCAPE, true)
	_key(KEY_ESCAPE, false)


func _key(code: Key, down: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = down
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _pick(studio: Studio, name: String) -> void:
	_press(studio, "移動型ドリル")
	_press(studio, name)


func _press(studio: Studio, text: String) -> void:
	for button: Button in studio.find_children("*", "Button", true, false):
		if button.text == text:
			button.pressed.emit()
			return
	_check(false, "button present: " + text)


func _has_label(studio: Studio, text: String) -> bool:
	for label: Label in studio.find_children("*", "Label", true, false):
		if label.text == text:
			return true
	return false


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)
