extends Node3D

signal completed(result: Dictionary)
signal abandoned
signal restart_requested

const Arena = preload("res://scripts/training/arena.gd")
const Aim = preload("res://scripts/input/aim_settings.gd")
const AimForm = preload("res://scripts/ui/aim_settings_form.gd")
const AimCamera = preload("res://scripts/input/aim_camera.gd")
const Hitscan = preload("res://scripts/weapons/hitscan.gd")
const Stats = preload("res://scripts/scoring/run_stats.gd")
const Clock = preload("res://scripts/scoring/active_clock.gd")
const Scenario = preload("res://scripts/scenarios/scenario.gd")
const Style = preload("res://scripts/ui/style.gd")
const Crosshair = preload("res://scripts/ui/crosshair.gd")
const Player = preload("res://scripts/movement/player_body.gd")
const Bindings = preload("res://scripts/input/movement_bindings.gd")
const Weapon = preload("res://scripts/weapons/training_weapon.gd")
const Strafe = preload("res://scripts/targets/strafe_target.gd")
const Tracking = preload("res://scripts/scoring/tracking_stats.gd")
const TargetGroup = preload("res://scripts/targets/target_group.gd")
const FixedMotion = preload("res://scripts/targets/fixed_tracking_motion.gd")
const CustomRound = preload("res://scripts/training/custom_round.gd")

var scenario: Dictionary
var movement_tuning: Dictionary
var aim: Aim
var fov: float
var camera: AimCamera
var player: Player
var spawn_eye: Vector3
var jump_pressed := false
var crouch_pressed := false
var movement_status: Label
var arena: Arena
var weapon: Weapon
var strafe: Strafe
var target_group: TargetGroup
var fixed_motion: FixedMotion
var tracking: Tracking
var custom: CustomRound
var editor_test := false
var weapon_rng := RandomNumberGenerator.new()
var trigger_held := false
var auto_fire_ready := false
var ads := false
var respawn_at := 0
var first_target_hit := true
var hud_ammo: Label
var hud_target: Label
var target_meter: ProgressBar
var clock := Clock.new()
var stats: Stats
var rng := RandomNumberGenerator.new()
var duration_usec: int
var target_since := -1
var spawn_pending := true
var paused := false
var finished := false
var aim_ready := false
var pending_shots: Array[Dictionary] = []
var hud_time: Label
var hud_score: Label
var hud_accuracy: Label
var fps: Label
var timer_track: ProgressBar
var pause_layer: Control
var pause_center: CenterContainer
var pause_menu: VBoxContainer
var pause_settings: VBoxContainer
var resume_button: Button
var settings_button: Button
var crosshair: Crosshair
var last_hit := -1000000
var last_shot := -1000000
var previous_accumulation := true


func _ready() -> void:
	duration_usec = scenario.duration_seconds * 1000000
	stats = Stats.new(scenario.scoring.points_per_hit, scenario.scoring.get("points_per_elimination", 0))
	var is_custom: bool = scenario.type == "custom"
	var target: Dictionary = scenario.get("target", {})
	if scenario.type in Scenario.FIXED_TRACKING:
		fixed_motion = FixedMotion.new(target)
	elif target.has("health"):
		strafe = Strafe.new(target)
	if is_custom or target.has("health"):
		weapon = Weapon.new(scenario.weapon)
	if target.get("track_aim", false):
		tracking = Tracking.new()
	arena = Arena.new()
	add_child(arena)
	arena.build(scenario)
	camera = AimCamera.new()
	if is_custom:
		custom = CustomRound.new(arena, scenario, rng)
		spawn_eye = custom.spawn_eye
		camera.apply_angles(Vector2(custom.yaw, 0))
	else:
		spawn_eye = Scenario.player_position(scenario)
	if scenario.type in Scenario.TARGET_GROUPS:
		target_group = TargetGroup.new(arena, scenario.target, spawn_eye, scenario.type == "target_switching", rng)
	camera.position = spawn_eye
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_apply_aim_settings()
	add_child(camera)
	camera.make_current()
	if scenario.player.movement_enabled:
		Bindings.register()
		player = Player.new()
		player.tuning = movement_tuning
		if custom != null:
			player.world_mask |= Arena.PLAY_AREA_LAYER
		player.position = spawn_eye - Vector3.UP * Player.STANDING_EYE
		add_child(player)
		player.reset_physics_interpolation()
	_build_hud()
	previous_accumulation = Input.use_accumulated_input
	Input.use_accumulated_input = false
	_capture(true)
	get_window().focus_exited.connect(_on_focus_lost)


func _exit_tree() -> void:
	_capture(false)
	Input.use_accumulated_input = previous_accumulation


func _capture(enabled: bool) -> void:
	aim_ready = false
	jump_pressed = false
	crouch_pressed = false
	trigger_held = false
	if ads:
		_set_ads(false)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if enabled else Input.MOUSE_MODE_VISIBLE


func _input(event: InputEvent) -> void:
	if finished:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if pause_settings != null:
			_close_pause_settings()
		else:
			_set_paused(not paused)
		get_viewport().set_input_as_handled()
		return
	if paused or not aim_ready:
		return
	if event is InputEventMouseMotion:
		camera.apply_motion(event.screen_relative)
	elif event is InputEventKey and event.pressed and not event.echo:
		if player != null:
			jump_pressed = jump_pressed or event.is_action_pressed(&"move_jump")
			crouch_pressed = crouch_pressed or event.is_action_pressed(&"move_crouch")
			crouch_pressed = crouch_pressed or event.is_action_pressed(&"move_crouch_alt")
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			trigger_held = event.pressed
			if event.pressed:
				_queue_shot(clock.elapsed(Time.get_ticks_usec()))
			get_viewport().set_input_as_handled()
		elif _has_ads() and event.button_index == MOUSE_BUTTON_RIGHT:
			_set_ads(event.pressed)
			get_viewport().set_input_as_handled()


func _apply_aim_settings() -> void:
	fov = aim.values.vertical_fov
	camera.fov = fov
	camera.degrees_per_count = aim.degrees_per_count(aim.values)


func _set_ads(active: bool) -> void:
	ads = active
	camera.fov = rad_to_deg(2.0 * atan(tan(deg_to_rad(fov) * 0.5) / weapon.tuning.ads_zoom)) if ads else fov
	camera.gain = weapon.tuning.ads_sensitivity if ads else 1.0
	crosshair.ads = ads
	crosshair.queue_redraw()


func _has_ads() -> bool:
	return strafe != null or fixed_motion != null or custom != null


func _queue_shot(timestamp: int, held_repeat := false) -> void:
	if clock.started_at < 0 or timestamp >= duration_usec:
		return
	var direction := -camera.global_basis.z
	if weapon != null:
		# Keep the trigger held across respawns without firing at the empty lane.
		var can_auto := custom.ready_count > 0 if custom != null else not spawn_pending and auto_fire_ready
		if weapon.automatic and not can_auto:
			return
		if not weapon.try_fire(timestamp, held_repeat):
			return
		direction = weapon.aim_direction(camera.global_basis, ads, weapon_rng)
	pending_shots.append({"origin": camera.global_position, "direction": direction, "time": timestamp})
	if weapon != null:
		last_shot = timestamp
		var kick := weapon.recoil(ads)
		if not kick.is_zero_approx():
			camera.apply_angles(kick)


func _physics_process(delta: float) -> void:
	if finished:
		return
	var elapsed := clock.elapsed(Time.get_ticks_usec())
	if tracking != null and aim_ready and not paused and not spawn_pending and auto_fire_ready and elapsed < duration_usec:
		tracking.sample(camera, arena.target, scenario.target.radius, scenario.weapon.range, delta)
	if weapon != null and aim_ready and not paused and trigger_held and weapon.automatic:
		_queue_shot(elapsed, true)
	for shot: Dictionary in pending_shots:
		if custom != null:
			if custom.shot(get_world_3d(), shot, scenario.weapon, stats):
				last_hit = shot.time
			continue
		if target_group != null:
			_resolve_group_shot(shot)
			continue
		var hit := false
		if target_since >= 0 and shot.time >= target_since and not spawn_pending:
			var impact := Hitscan.trace(get_world_3d(), shot.origin, shot.direction, scenario.weapon.range)
			hit = impact.get("collider") == arena.target
		var reaction := int(shot.time) - target_since if first_target_hit else -1
		stats.register_shot(hit, reaction)
		if tracking != null:
			tracking.shot(hit, shot.time, roundi(weapon.interval_usec * 1.5))
		if hit:
			last_hit = shot.time
			first_target_hit = false
			_apply_target_hit(shot.time)
	pending_shots.clear()
	if clock.started_at >= 0 and elapsed >= duration_usec:
		finished = true
		_capture(false)
		var result := stats.snapshot()
		if tracking != null:
			result.tracking_accuracy = tracking.accuracy()
			result.longest_streak_seconds = tracking.longest_usec / 1000000.0
		if target_group != null and target_group.switching:
			result.switches_completed = stats.reactions
		completed.emit(result)
		return
	if (strafe != null or fixed_motion != null) and not paused and not spawn_pending:
		if fixed_motion != null:
			arena.target.position = fixed_motion.step(delta, rng)
		else:
			arena.target.position = strafe.step(arena.target.position, spawn_eye.x, delta, rng)
		arena.target.force_update_transform()
		# Allow one physics step to publish the respawned collider before resuming fire.
		auto_fire_ready = true
	if player != null and aim_ready and not paused:
		_step_player(delta)
		if custom != null and player.position.y < spawn_eye.y - 18.0:
			player.position = spawn_eye - Vector3.UP * Player.STANDING_EYE
			player.velocity = Vector3.ZERO
			player.reset_physics_interpolation()
	if custom != null and not paused and clock.started_at >= 0:
		custom.step(elapsed, delta)


func _resolve_group_shot(shot: Dictionary) -> void:
	var impact := Hitscan.trace(get_world_3d(), shot.origin, shot.direction, scenario.weapon.range)
	var body: Variant = impact.get("collider")
	var reaction := target_group.reaction_at(body, shot.time)
	var hit := reaction >= 0
	if hit:
		# The first marked target starts the sequence without counting as a switch.
		if target_group.switching and target_group.switch_count == 0:
			reaction = -1
		target_group.accept(body)
		last_hit = shot.time
	stats.register_shot(hit, reaction)


func _apply_target_hit(timestamp: int) -> void:
	if tracking != null:
		return
	if strafe != null:
		if not strafe.hit(weapon.tuning.damage):
			return
		stats.register_elimination(timestamp - target_since)
		respawn_at = timestamp + roundi(strafe.tuning.respawn_seconds * 1000000.0)
	arena.target.hide()
	spawn_pending = true


func _step_player(delta: float) -> void:
	var axes := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	var yaw := Basis(Vector3.UP, deg_to_rad(camera.yaw))
	var direction := yaw * Vector3(axes.x, 0.0, axes.y)
	var crouch := Input.is_action_pressed(&"move_crouch") or Input.is_action_pressed(&"move_crouch_alt")
	player.step(delta, direction, Input.is_action_pressed(&"move_sprint"), crouch, crouch_pressed, jump_pressed)
	jump_pressed = false
	crouch_pressed = false


func _process(delta: float) -> void:
	if finished:
		return
	var now := Time.get_ticks_usec()
	if not paused:
		# Ignore the menu's transition motion until the next gameplay frame.
		aim_ready = true
		if player != null:
			camera.global_position = player.view_position(delta)
			var velocity := player.get_real_velocity()
			movement_status.text = "%s  %.1f m/s" % [player.mode_label(), Vector2(velocity.x, velocity.z).length()]
		if clock.started_at < 0:
			clock.start(now)
		if custom == null and (target_group != null or spawn_pending):
			var active_time := clock.elapsed(now)
			if active_time >= respawn_at and active_time < duration_usec:
				if target_group != null:
					target_group.present(active_time)
				else:
					_spawn_target(active_time)
	var elapsed := clock.elapsed(now)
	var remaining := maxi(0, duration_usec - elapsed)
	hud_time.text = "%02d" % ceili(remaining / 1000000.0)
	hud_score.text = "%d" % stats.score()
	hud_accuracy.text = "%.1f%%" % stats.accuracy()
	timer_track.value = remaining
	fps.text = "%d FPS" % Engine.get_frames_per_second()
	var feedback := clampf(1.0 - (elapsed - last_hit) / 140000.0, 0.0, 1.0)
	var shot_flash := clampf(1.0 - (elapsed - last_shot) / 75000.0, 0.0, 1.0)
	if feedback != crosshair.feedback or shot_flash != crosshair.shot_flash:
		crosshair.feedback = feedback
		crosshair.shot_flash = shot_flash
		crosshair.queue_redraw()
	_update_weapon_hud(elapsed)


func _update_weapon_hud(elapsed: int) -> void:
	hud_ammo.text = "弾数無制限  ADS" if ads else "弾数無制限"
	if custom != null:
		hud_target.text = "出現中 %d / %d    撃破 %d" % [custom.alive, custom.targets.size(), stats.eliminations]
		return
	if tracking != null:
		var precision: Variant = tracking.accuracy()
		target_meter.value = 0.0 if precision == null else precision
		hud_target.text = "追従精度  —" if precision == null else "追従精度  %.1f%%" % precision
		return
	if strafe == null:
		return
	target_meter.value = strafe.health
	if spawn_pending:
		hud_target.text = "再出現まで %.1f 秒" % (maxi(0, respawn_at - elapsed) / 1000000.0)
	else:
		hud_target.text = "ダミー耐久値  %d / %d" % [strafe.health, strafe.tuning.health]


func _spawn_target(timestamp: int) -> void:
	var options: Dictionary = scenario.target
	var origin := spawn_eye
	if fixed_motion != null:
		arena.target.position = fixed_motion.spawn(origin, rng)
	else:
		var x := origin.x + rng.randf_range(-options.x_extent, options.x_extent)
		var y := origin.y + rng.randf_range(-options.y_extent, options.y_extent)
		y = maxf(y, options.radius + 0.055)
		if strafe != null and strafe.jumps:
			y = minf(y, 4.85 - options.radius - options.jump_height)
		arena.target.position = Vector3(x, y, origin.z - options.depth)
	if strafe != null:
		strafe.spawn(1.0 if rng.randf() < 0.5 else -1.0)
		strafe.reset_motion(arena.target.position.y, rng)
	if strafe != null or fixed_motion != null:
		arena.target.force_update_transform()
	arena.target.show()
	target_since = timestamp
	first_target_hit = true
	auto_fire_ready = false
	spawn_pending = false


func _on_focus_lost() -> void:
	if not finished:
		_set_paused(true)


func _set_paused(value: bool) -> void:
	if finished or paused == value:
		return
	paused = value
	var now := Time.get_ticks_usec()
	if paused:
		clock.pause(now)
	else:
		clock.resume(now)
	pause_layer.visible = paused
	crosshair.visible = not paused
	_capture(not paused)
	if paused:
		resume_button.grab_focus()


func _open_pause_settings() -> void:
	pause_menu.get_parent().hide()
	pause_settings = Style.panel(pause_center, 18)
	pause_settings.add_theme_constant_override("separation", 7)
	pause_settings.add_child(Style.label("マウスと視野角", 26))
	var reading := Style.label("", 19, Style.ACCENT)
	var settings := AimForm.new(aim, pause_settings, reading)
	pause_settings.add_child(reading)
	var status := Style.label("", 15, Style.ACCENT)
	status.hide()
	pause_settings.add_child(status)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	pause_settings.add_child(actions)
	var save := Style.button("保存してポーズへ戻る", func() -> void:
		var error := settings.save()
		if error == OK:
			_apply_aim_settings()
			_close_pause_settings()
		else:
			status.text = "設定を保存できませんでした（%s）。" % error_string(error)
			status.show()
	, true)
	actions.add_child(save)
	actions.add_child(Style.button("キャンセル", _close_pause_settings))
	settings.inputs[0].get_line_edit().grab_focus()


func _close_pause_settings() -> void:
	var panel := pause_settings.get_parent()
	panel.hide()
	panel.queue_free()
	pause_settings = null
	pause_menu.get_parent().show()
	settings_button.grab_focus()


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var hud := Control.new()
	hud.theme = Style.create_theme()
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(hud)

	var layout := MarginContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_KEEP_SIZE, 24)
	layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(layout)
	var column := Style.stack(8)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(column)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(row)
	var title := Style.label(scenario.name, 23)
	if custom != null:
		title.custom_minimum_size.x = 220
		title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)
	if player != null:
		movement_status = _hud_stat(row, "移動", "地上  0.0 m/s")
	hud_time = _hud_stat(row, "残り秒数", "00")
	hud_score = _hud_stat(row, "スコア", "0")
	hud_accuracy = _hud_stat(row, "命中率", "0.0%")

	timer_track = ProgressBar.new()
	timer_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	timer_track.max_value = duration_usec
	timer_track.value = duration_usec
	timer_track.show_percentage = false
	timer_track.custom_minimum_size.y = 4
	timer_track.add_theme_stylebox_override("background", Style.flat(Color("#334854"), Color.TRANSPARENT, 2))
	timer_track.add_theme_stylebox_override("fill", Style.flat(Style.ACCENT, Color.TRANSPARENT, 2))
	column.add_child(timer_track)
	_build_weapon_hud(column)
	var gap := Control.new()
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(gap)
	var footer := HBoxContainer.new()
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(footer)
	var controls := "左クリック  射撃"
	if _has_ads():
		controls += "    右クリック  ADS"
	controls += "    Esc  ポーズ"
	if target_group != null and target_group.switching:
		controls = "▼ のダミーを狙う    " + controls
	if player != null:
		controls = "WASD  移動    Space  ジャンプ    Shift  スプリント    Ctrl / C  しゃがみ\n" + controls
	var help := Style.label(controls, 17, Style.MUTED)
	help.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(help)
	fps = Style.label("FPS", 17, Style.MUTED)
	footer.add_child(fps)

	crosshair = Crosshair.new()
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.add_child(crosshair)
	pause_layer = ColorRect.new()
	pause_layer.color = Color(0.04, 0.07, 0.09, 0.8)
	pause_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.add_child(pause_layer)
	pause_center = CenterContainer.new()
	pause_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_layer.add_child(pause_center)
	pause_menu = Style.panel(pause_center, 28)
	pause_menu.custom_minimum_size.x = 315
	pause_menu.add_child(Style.label("ポーズ", 32))
	resume_button = Style.button("練習に戻る", func() -> void: _set_paused(false), true)
	resume_button.name = "Resume"
	pause_menu.add_child(resume_button)
	settings_button = Style.button("設定", _open_pause_settings)
	pause_menu.add_child(settings_button)
	pause_menu.add_child(Style.button("リトライ", func() -> void: restart_requested.emit()))
	var exit_label := "エディターへ戻る" if editor_test else "メニューへ戻る"
	pause_menu.add_child(Style.button(exit_label, func() -> void: abandoned.emit()))
	pause_layer.hide()


func _build_weapon_hud(column: VBoxContainer) -> void:
	var strip := HBoxContainer.new()
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(strip)
	if custom != null:
		hud_target = Style.label("", 16)
		strip.add_child(hud_target)
	elif strafe != null or tracking != null:
		_build_target_meter(strip)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.add_child(gap)
	hud_ammo = Style.label("", 20)
	strip.add_child(hud_ammo)


func _build_target_meter(strip: HBoxContainer) -> void:
	var target_status := Style.stack(2)
	strip.add_child(target_status)
	hud_target = Style.label("ダミー耐久値" if tracking == null else "追従精度", 16)
	target_status.add_child(hud_target)
	target_meter = ProgressBar.new()
	target_meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	target_meter.max_value = strafe.tuning.health if tracking == null else 100.0
	target_meter.show_percentage = false
	target_meter.custom_minimum_size = Vector2(190, 5)
	target_meter.add_theme_stylebox_override("background", Style.flat(Style.EDGE, Color.TRANSPARENT, 2))
	target_meter.add_theme_stylebox_override("fill", Style.flat(Style.ACCENT, Color.TRANSPARENT, 2))
	target_status.add_child(target_meter)


func _hud_stat(row: HBoxContainer, heading: String, initial: String) -> Label:
	var cell := Style.stack(0)
	cell.custom_minimum_size.x = 105
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(cell)
	cell.add_child(Style.label(heading, 14, Style.MUTED))
	var value := Style.label(initial, 27)
	cell.add_child(value)
	return value
