extends SceneTree

const Studio = preload("res://scripts/ui/studio.gd")
const Main = preload("res://scenes/studio.tscn")
const Weapon = preload("res://scripts/weapons/training_weapon.gd")
const Strafe = preload("res://scripts/targets/strafe_target.gd")
const Scenario = preload("res://scripts/scenarios/scenario.gd")
const Store = preload("res://scripts/persistence/json_store.gd")

var failures: Array[String] = []
var test_dir := "res://.godot/phase3-%d" % OS.get_process_id()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	create_timer(20.0).timeout.connect(func() -> void:
		push_error("Phase 3 smoke test timed out")
		quit(1)
	)
	if DirAccess.make_dir_recursive_absolute(test_dir) != OK:
		push_error("Cannot create test directory")
		quit(1)
		return
	var definition := Scenario.load_strafe()
	_check(not definition.is_empty(), "load strafe scenario")
	_test_weapon_and_motion(definition)
	await _test_round()
	await _test_continuous_fire()
	for file: String in DirAccess.get_files_at(test_dir):
		DirAccess.remove_absolute(test_dir.path_join(file))
	DirAccess.remove_absolute(test_dir)
	print("Phase 3 tests passed." if failures.is_empty() else "Phase 3 checks failed: %d" % failures.size())
	quit(0 if failures.is_empty() else 1)


func _test_weapon_and_motion(definition: Dictionary) -> void:
	var invalid_path := test_dir.path_join("invalid.json")
	var invalid := definition.duplicate(true)
	invalid.weapon.fire_mode = "unknown"
	_check(Store.write(invalid_path, invalid) == OK and Scenario.load_strafe(invalid_path).is_empty(), "reject unknown firing mode")

	var profile: Dictionary = definition.weapon.duplicate(true)
	var weapon := Weapon.new(profile)
	_check(weapon.try_fire(10000) and weapon.shots_fired == 1, "first shot is accepted")
	_check(not weapon.try_fire(109999) and weapon.shots_fired == 1, "clicks respect cooldown")
	_check(weapon.try_fire(115000, true) and weapon.next_shot_at == 210000, "automatic cadence preserves tick remainder")
	for index in range(40):
		_check(weapon.try_fire(weapon.next_shot_at, true), "sustained fire accepts each scheduled shot")
	_check(weapon.shots_fired == 42, "sustained fire has no ammo limit")

	weapon = Weapon.new(profile)
	_check(weapon.try_fire(0) and weapon.recoil(false) == Vector2.ZERO, "recoil off by default")
	profile.recoil_enabled = true
	_check(weapon.try_fire(weapon.interval_usec), "advance to the second recoil pattern step")
	var light := Vector2(-0.12, 0.48)
	_check(weapon.recoil(false).is_equal_approx(light), "light recoil preserves the old pattern")
	for scale: float in [1.5, 2.0]:
		profile.recoil_multiplier = scale
		_check(weapon.recoil(false).is_equal_approx(light * scale), "recoil preset scales both axes")
		_check(weapon.recoil(true).is_equal_approx(light * scale * 0.65), "ADS reduces the selected recoil")
	profile.recoil_enabled = false
	_check(weapon.recoil(false) == Vector2.ZERO, "off ignores the recoil multiplier")
	profile.spread_degrees = 3.0
	var random := RandomNumberGenerator.new()
	random.seed = 48
	var hip := weapon.aim_direction(Basis.IDENTITY, false, random)
	random.seed = 48
	var ads := weapon.aim_direction(Basis.IDENTITY, true, random)
	_check(is_equal_approx(hip.length(), 1.0) and rad_to_deg(hip.angle_to(Vector3.FORWARD)) <= 3.0 and ads.angle_to(Vector3.FORWARD) < hip.angle_to(Vector3.FORWARD), "spread cone is bounded and narrows under ADS")

	var target := Strafe.new(definition.target)
	target.spawn(1.0)
	var x := 0.0
	var rightmost := 0.0
	for index in range(270):
		x = target.next_x(x, 0.0, 1.0 / 120.0)
		rightmost = maxf(x, rightmost)
	_check(is_equal_approx(rightmost, definition.target.x_extent) and target.direction < 0.0 and x < rightmost - 0.3, "target turns and moves back inside its lane")


func _test_round() -> void:
	var studio: Studio = Main.instantiate()
	studio.best_path = test_dir.path_join("best.json")
	root.add_child(studio)
	await process_frame
	_press(studio, "練習モード")
	_press(studio, "トラッキング")
	_press(studio, "移動ダミー撃破")
	_press(studio, "この条件で開始")
	var session := studio.session
	await _ticks(8)
	_check(session.arena.target.visible and session.strafe.health == 125, "spawn alive with full health")
	var start := session.arena.target.position
	await _ticks(15)
	_check(absf(session.arena.target.position.x - start.x) > 0.02, "target moves in live physics world")

	_mouse(MOUSE_BUTTON_RIGHT, true)
	_check(session.ads and session.camera.fov < session.fov and session.camera.gain == 0.75, "ADS zoom and gain")
	_mouse(MOUSE_BUTTON_RIGHT, false)
	_check(not session.ads and session.camera.fov == session.fov and session.camera.gain == 1.0, "release ADS restores hip view")

	session.camera.look_at(session.arena.target.position)
	_mouse(MOUSE_BUTTON_LEFT, true)
	for index in range(120):
		await physics_frame
		if session.stats.eliminations > 0:
			break
		session.camera.look_at(session.arena.target.position)
	_mouse(MOUSE_BUTTON_LEFT, false)
	_check(session.stats.hits == 5 and session.stats.shots == 5 and session.stats.eliminations == 1, "held trigger tracks and eliminates over five hits")
	_check(session.stats.reactions == 1 and session.stats.score() == 750, "first hit reaction and elimination bonus counted once")
	_check(session.spawn_pending and not session.arena.target.visible, "eliminated target hides before respawn")
	_key(KEY_ESCAPE)
	var frozen := session.clock.elapsed(Time.get_ticks_usec())
	await create_timer(0.72).timeout
	_check(session.paused and session.spawn_pending and session.clock.elapsed(Time.get_ticks_usec()) == frozen, "pause freezes delayed respawn")
	_key(KEY_ESCAPE)
	await create_timer(0.75).timeout
	_check(session.arena.target.visible and session.strafe.health == 125 and session.stats.shots == 5, "respawn restores health and session remains idle")

	session.camera.look_at(session.camera.global_position + Vector3.RIGHT)
	_key(KEY_R)
	_mouse(MOUSE_BUTTON_LEFT, true)
	_mouse(MOUSE_BUTTON_LEFT, false)
	await _ticks(3)
	_check(session.stats.shots == 6, "R does not interrupt firing")
	session.duration_usec = session.clock.elapsed(Time.get_ticks_usec()) + 25000
	var result: Dictionary = await session.completed
	_check(result.eliminations == 1 and result.elimination_ms > result.reaction_ms and session.stats.score() == 750, "result reports elimination timing")
	_check(studio.session == null and int(Store.read(studio.best_path).get("scores", {}).get(studio._record_key(), 0)) == 750, "best score is saved for the configured mode")

	_press(studio, "メニューへ戻る")
	_press(studio, "練習モード")
	_press(studio, "トラッキング")
	_press(studio, "移動ダミー撃破")
	var selectors := studio.find_children("*", "OptionButton", true, false)
	var selector: OptionButton = selectors[0]
	var recoil: OptionButton = selectors[1]
	_check(recoil.selected == 0 and recoil.item_count == 4, "the menu offers off and three recoil levels")
	_check(recoil.get_item_text(1) == "小" and recoil.get_item_text(2) == "中" and recoil.get_item_text(3) == "大",
		"the three recoil levels have the intended labels")
	var off_key := studio._record_key()
	var legacy_light: Dictionary = studio.selected.duplicate(true)
	legacy_light.weapon.recoil_enabled = true
	recoil.select(1)
	recoil.item_selected.emit(1)
	_check(Scenario.record_key(studio.selected) == Scenario.record_key(legacy_light),
		"light recoil keeps the legacy personal-best key")
	var light_key := studio._record_key()
	recoil.select(2)
	recoil.item_selected.emit(2)
	var medium_key := studio._record_key()
	recoil.select(3)
	recoil.item_selected.emit(3)
	_check(medium_key != light_key and studio._record_key() != medium_key,
		"medium and heavy recoil have separate personal-best keys")
	recoil.select(0)
	recoil.item_selected.emit(0)
	_check(studio._record_key() == off_key, "switching off restores the old personal-best key")
	selector.select(1)
	selector.item_selected.emit(1)
	recoil.select(3)
	recoil.item_selected.emit(3)
	_check(studio.selected.weapon.fire_mode == "single" and studio.selected.weapon.recoil_multiplier == 2.0
		and studio._best() < 0, "weapon presets update the scenario")
	_press(studio, "この条件で開始")
	session = studio.session
	await _ticks(8)
	_mouse(MOUSE_BUTTON_LEFT, true)
	await _ticks(35)
	_check(session.stats.shots == 1 and is_equal_approx(session.camera.pitch, 0.96),
		"single mode only fires once per hold and applies heavy recoil")
	_mouse(MOUSE_BUTTON_LEFT, false)
	_mouse(MOUSE_BUTTON_LEFT, true)
	_mouse(MOUSE_BUTTON_LEFT, false)
	await _ticks(4)
	_check(session.stats.shots == 2, "single mode fires again on a fresh click")
	studio.queue_free()


func _test_continuous_fire() -> void:
	var studio: Studio = Main.instantiate()
	studio.best_path = test_dir.path_join("continuous-best.json")
	root.add_child(studio)
	await process_frame
	_press(studio, "練習モード")
	_press(studio, "トラッキング")
	_press(studio, "移動ダミー撃破")
	_press(studio, "この条件で開始")
	var session := studio.session
	await _ticks(8)
	var shots_at_elimination: Array[int] = []
	var shots_during_respawn: Array[int] = []
	session.arena.target.visibility_changed.connect(func() -> void:
		if session.arena.target.visible:
			shots_during_respawn.append(session.stats.shots - shots_at_elimination.back())
			session.camera.look_at(session.arena.target.position)
		else:
			shots_at_elimination.append(session.stats.shots)
	)
	session.camera.look_at(session.arena.target.position)
	_mouse(MOUSE_BUTTON_LEFT, true)
	var checked_third := false
	var checked_after_twenty := false
	for index in range(1050):
		await physics_frame
		if session.stats.eliminations == 2 and session.arena.target.visible and not checked_third:
			_check_mouse_look(studio, "mouse look responds at the third target")
			checked_third = true
		if session.stats.shots > 20 and not checked_after_twenty:
			_check_mouse_look(studio, "mouse look responds after twenty shots")
			checked_after_twenty = true
		if session.stats.eliminations >= 5:
			break
		session.camera.look_at(session.arena.target.position)
	_mouse(MOUSE_BUTTON_LEFT, false)
	_check(checked_third and checked_after_twenty and session.stats.eliminations == 5,
		"one uninterrupted trigger hold defeats five targets without R, got %d" % session.stats.eliminations)
	_check(shots_during_respawn == [0, 0, 0, 0],
		"held trigger spends no shots while waiting for a target: %s" % [shots_during_respawn])
	_check(session.stats.shots == 25 and session.stats.hits == 25,
		"aimed shots hit as soon as the target collider is ready: %d shots, %d hits" % [session.stats.shots, session.stats.hits])
	studio.queue_free()


func _check_mouse_look(studio: Studio, message: String) -> void:
	var camera := studio.session.camera
	var before := camera.yaw
	var event := InputEventMouseMotion.new()
	event.screen_relative = Vector2(10, 0)
	_send(event)
	_check(camera.yaw != before, message)


func _ticks(count: int) -> void:
	for index in range(count):
		await physics_frame


func _mouse(button: MouseButton, down: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = down
	_send(event)


func _key(key: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.pressed = true
	_send(event)
	event = event.duplicate()
	event.pressed = false
	_send(event)


func _send(event: InputEvent) -> void:
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _press(studio: Studio, caption: String) -> void:
	for button: Button in studio.find_children("*", "Button", true, false):
		if button.text == caption:
			button.pressed.emit()
			return
	_check(false, "button present: " + caption)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)
