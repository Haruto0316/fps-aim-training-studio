extends SceneTree

const Studio = preload("res://scripts/ui/studio.gd")
const Main = preload("res://scenes/studio.tscn")
const Movement = preload("res://scripts/movement/movement_settings.gd")
const Player = preload("res://scripts/movement/player_body.gd")
const Scenario = preload("res://scripts/scenarios/scenario.gd")

var failures: Array[String] = []
var test_dir := "res://.godot/phase2-%d" % OS.get_process_id()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	create_timer(25.0).timeout.connect(func() -> void:
		push_error("Phase 2 smoke test timed out")
		quit(1)
	)
	if DirAccess.make_dir_recursive_absolute(test_dir) != OK:
		push_error("Cannot create test directory")
		quit(1)
		return

	var studio: Studio = Main.instantiate()
	var movement_path := test_dir.path_join("movement.json")
	studio.movement = Movement.new(movement_path)
	studio.best_path = test_dir.path_join("best.json")
	root.add_child(studio)
	await process_frame

	_press(studio, "設定")
	_press(studio, "移動設定")
	await process_frame
	await process_frame
	var fields := studio.find_children("*", "SpinBox", true, false)
	_check(fields.size() == 15, "movement settings expose all parameters")
	var scroll: ScrollContainer = studio.find_children("*", "ScrollContainer", true, false)[0]
	var save_button := _button(studio, "保存してホームへ")
	_check(save_button.get_global_rect().end.y <= scroll.get_global_rect().end.y, "save button is visible at the default viewport size")
	fields[0].get_line_edit().text = "4.0"
	_press(studio, "保存してホームへ")
	var reloaded := Movement.new(movement_path)
	_check(is_equal_approx(reloaded.values.walk_speed, 4.0), "movement settings saved and reloaded")
	var corrected := reloaded.validated({"walk_speed": 6.0, "sprint_speed": 3.0, "air_control": -1.0, "gravity": "bad"})
	_check(corrected.sprint_speed == 6.0 and corrected.air_control == 0.0 and corrected.gravity == reloaded.defaults.gravity, "movement profile validation")
	_check(Scenario.load_static(Scenario.MOVEMENT_PRACTICE).is_empty(), "movement mode uses its own scenario type")

	_press(studio, "移動練習")
	var key_with_profile := studio._record_key()
	studio.movement.values.walk_speed = 4.1
	_check(key_with_profile != studio._record_key(), "different movement profiles have separate records")
	studio.movement.values.walk_speed = 4.0
	_press(studio, "この条件で開始")
	var session := studio.session
	var player := session.player
	await _ticks(8)
	_check(player.is_on_floor(), "grounded after spawn")
	var origin := player.position

	_key(KEY_W, true)
	await _ticks(5)
	_check(player.position.z < origin.z and -player.velocity.z < 2.0, "W accelerates gradually")
	await _ticks(30)
	_check(is_equal_approx(-player.velocity.z, 4.0), "walking respects saved speed")
	_key(KEY_W, false)
	await _ticks(3)
	_check(player.velocity.z < -1.0 and player.velocity.z > -4.0, "release preserves momentum while braking")
	await _ticks(35)
	_check(player.velocity.length() < 0.2, "ground friction stops the player")

	_key(KEY_SPACE, true)
	_key(KEY_SPACE, false)
	await _ticks(9)
	_check(not player.is_on_floor() and player.position.y > 0.2, "Space taps jump")
	_key(KEY_D, true)
	await _ticks(20)
	_check(player.position.x > origin.x and player.velocity.x > 0.5 and not player.is_on_floor(), "air steering moves right")
	_key(KEY_D, false)
	await _ticks(70)
	_check(player.is_on_floor() and player.position.y < 0.03, "gravity and landing")

	_teleport(player, Vector3(0, 0.005, 1.5))
	_key(KEY_SHIFT, true)
	_key(KEY_W, true)
	await _ticks(50)
	var sprint_speed := -player.velocity.z
	_check(player.sprinting and is_equal_approx(sprint_speed, 8.4), "Shift reaches sprint speed")
	_key(KEY_CTRL, true)
	await _ticks(4)
	_check(player.sliding and player.crouched and -player.velocity.z > sprint_speed, "sprint to slide preserves and boosts momentum")
	var first_slide_speed := -player.velocity.z
	await _ticks(20)
	_check(player.sliding and -player.velocity.z < first_slide_speed and player.eye_height < 1.45, "slide friction and lowered view")

	_key(KEY_ESCAPE, true)
	_key(KEY_ESCAPE, false)
	var pause_position := player.position
	var pause_slide := player.slide_elapsed
	await _ticks(20)
	_check(session.paused and player.position.is_equal_approx(pause_position) and player.slide_elapsed == pause_slide, "pause freezes movement and slide timer")
	_key(KEY_ESCAPE, true)
	_key(KEY_ESCAPE, false)
	_key(KEY_W, false)
	_key(KEY_SHIFT, false)
	await _ticks(135)
	_check(not player.sliding and player.crouched, "slide ends and held crouch remains")
	_key(KEY_CTRL, false)
	await _ticks(28)
	_check(not player.crouched and player.eye_height > 1.60, "release crouch restores stand and view")

	_teleport(player, Vector3(-3.85, 0.005, -1.6))
	player.tuning.eye_speed = 1.0
	_key(KEY_C, true)
	_key(KEY_W, true)
	await _ticks(42)
	_check(player.position.z < -2.25 and session.camera.global_position.y < 1.30, "eye stays below the low beam while lowering")
	await _ticks(23)
	_key(KEY_W, false)
	_key(KEY_C, false)
	await _ticks(25)
	_check(player.position.z < -2.6 and player.crouched, "low beam permits crouch and blocks standing")
	_key(KEY_W, true)
	await _ticks(140)
	_key(KEY_W, false)
	_check(player.position.z < -5.0 and not player.crouched, "stand once clear of the beam")

	player.tuning.eye_speed = reloaded.values.eye_speed
	_teleport(player, Vector3(3.65, 0.005, -1.0))
	_key(KEY_W, true)
	await _ticks(100)
	_check(player.position.y > 0.45 and player.position.z < -3.8 and player.is_on_floor(), "ramp ascent and floor contact")
	await _ticks(50)
	_check(player.position.y > 0.85 and player.is_on_floor(), "reach the elevated platform")
	_key(KEY_W, false)

	_teleport(player, Vector3(5.0, 0.005, 0))
	_key(KEY_D, true)
	await _ticks(70)
	_key(KEY_D, false)
	_check(player.position.x > 5.6 and player.position.x < 5.83, "side wall stops the capsule")

	_teleport(player, Vector3(0, 0.005, 0))
	_key(KEY_D, true)
	await _ticks(15)
	await process_frame
	var motion := InputEventMouseMotion.new()
	motion.screen_relative = Vector2(40, 0)
	_send(motion)
	_check(session.camera.yaw < -0.1 and player.velocity.x > 0.5, "mouse aim responds while strafing")
	session.camera.look_at(session.arena.target.position)
	var aimed_origin := session.camera.global_position
	var click := InputEventMouseButton.new()
	click.pressed = true
	click.button_index = MOUSE_BUTTON_LEFT
	_send(click)
	click = click.duplicate()
	click.pressed = false
	_send(click)
	_check(session.pending_shots.size() == 1 and session.pending_shots[0].origin == aimed_origin, "shot captures the moving camera position")
	await _ticks(6)
	_key(KEY_D, false)
	_check(session.stats.hits == 1 and is_equal_approx(session.arena.target.position.z, session.spawn_eye.z - session.scenario.target.depth), "hit while moving and respawn stays in the target lane")

	session.duration_usec = session.clock.elapsed(Time.get_ticks_usec()) + 25000
	var result: Dictionary = await session.completed
	_check(result.score == 100 and studio.session == null, "moving run reaches results")
	_press(studio, "リトライ")
	_check(studio.session.player.position.is_equal_approx(Vector3.ZERO), "movement retry resets position")
	studio.session.abandoned.emit()

	_press(studio, "標準練習モード")
	_press(studio, "Static Clicking")
	_press(studio, "この条件で開始")
	await _ticks(5)
	var fixed_pos := studio.session.camera.position
	_key(KEY_W, true)
	await _ticks(15)
	_key(KEY_W, false)
	_check(studio.session.player == null and studio.session.camera.position == fixed_pos, "Static Clicking ignores movement keys")
	studio.queue_free()

	for file: String in DirAccess.get_files_at(test_dir):
		DirAccess.remove_absolute(test_dir.path_join(file))
	DirAccess.remove_absolute(test_dir)
	print("Phase 2 tests passed." if failures.is_empty() else "Phase 2 checks failed: %d" % failures.size())
	quit(0 if failures.is_empty() else 1)


func _teleport(player: Player, position: Vector3) -> void:
	player.position = position
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()


func _ticks(count: int) -> void:
	for index in range(count):
		await physics_frame


func _key(key: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = pressed
	_send(event)


func _send(event: InputEvent) -> void:
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _press(studio: Studio, text: String) -> void:
	var button := _button(studio, text)
	if button != null:
		button.pressed.emit()


func _button(studio: Studio, text: String) -> Button:
	for button: Button in studio.find_children("*", "Button", true, false):
		if button.text == text:
			return button
	_check(false, "button present: " + text)
	return null


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)
