extends SceneTree

const Main = preload("res://scenes/studio.tscn")
const Studio = preload("res://scripts/ui/studio.gd")
const Editor = preload("res://scripts/editor/editor_page.gd")
const Draft = preload("res://scripts/editor/editor_draft.gd")
const Custom = preload("res://scripts/scenarios/custom_scenario.gd")
const Route = preload("res://scripts/scenarios/route_path.gd")
const Session = preload("res://scripts/training/static_session.gd")
const Store = preload("res://scripts/persistence/json_store.gd")

var failures: Array[String] = []
var folder := "res://.godot/phase7-%d" % OS.get_process_id()
var library: String


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	create_timer(20.0).timeout.connect(func() -> void:
		push_error("Phase 7 tests timed out")
		quit(1)
	)
	library = folder.path_join("library")
	if DirAccess.make_dir_recursive_absolute(folder) != OK:
		push_error("Cannot create Phase 7 test directory")
		quit(1)
		return
	_test_route_math()
	var studio := _studio()
	await process_frame
	_press(studio, "練習モード")
	_press(studio, "フリック")
	_press(studio, "カスタム練習")
	_press(studio, "3D エディター")
	var editor: Editor = studio.page
	var ids := _configure_arena(editor)
	await _test_route_editor(editor, ids)
	var before := Custom.validate(editor.draft.document())
	if before.is_empty():
		push_error("Test arena didn't validate")
		quit(1)
		return
	_press(editor, "保存")
	_check(not editor.draft.is_dirty(), "editor saves a named document")
	_check(editor.notice_panel.visible and editor.notice.text == "保存しました。" and editor.save_state.text == "保存済み", "successful save shows its result")
	var saved_path: String = library.path_join(before.id + ".json")
	_check(_same_document(Custom.load_file(saved_path), before), "save round-trips every normalised field")
	var exported := folder.path_join("shared.json")
	_check(editor._export_path(exported) == OK and _same_document(Custom.load_file(exported), before), "exported JSON can be read")
	_check(editor.notice.text.contains("エクスポートしました"), "export displays feedback")
	_test_validation(before)
	await _test_play(studio, editor, before, ids)
	studio.queue_free()
	await process_frame
	studio = _studio()
	await process_frame
	await _test_library(studio, before, exported)
	studio.queue_free()
	await process_frame
	_cleanup(library)
	_cleanup(folder)
	print("Phase 7 tests passed." if failures.is_empty() else "Phase 7 failures: %d" % failures.size())
	quit(0 if failures.is_empty() else 1)


func _studio() -> Studio:
	var studio: Studio = Main.instantiate()
	studio.custom_library_dir = library
	studio.best_path = folder.path_join("best.json")
	root.add_child(studio)
	return studio


func _test_route_math() -> void:
	var draft := Draft.new(false)
	var a := draft.add("route_point", Vector3.ZERO)
	var b := draft.add("route_point", Vector3(3, 0, 0))
	var c := draft.add("route_point", Vector3(3, 2, 0))
	var entry := {"route_points": [a, b, c], "route_curve": false, "route_loop": false}
	var line := Route.new(entry, draft.objects)
	_check(is_equal_approx(line.length, 5.0) and line.position_at(6.0).is_equal_approx(Vector3(3, 1, 0)),
		"linear route follows distance and reverses")
	entry.route_loop = true
	var loop := Route.new(entry, draft.objects)
	_check(loop.length > line.length and loop.position_at(loop.length + 1.0).is_equal_approx(Vector3.RIGHT),
		"loop closes the route and wraps at its total distance")
	entry.route_loop = false
	entry.route_curve = true
	var curve := Route.new(entry, draft.objects)
	_check(curve.length > line.length and absf(curve.position_at(1.5).y) > 0.03, "curved route rounds the corner")


func _configure_arena(editor: Editor) -> Dictionary:
	var draft := editor.draft
	var weapon: Dictionary = draft.config.weapon.duplicate(true)
	weapon.fire_mode = "single"
	draft.edit_config({"name": "Phase 7 Test", "duration_seconds": 5, "weapon": weapon})
	var target: int = draft.objects[1].id
	var first := draft.add("route_point", Vector3(0, 1.65, -5.0))
	var second := draft.add("route_point", Vector3(1.0, 1.65, -5.0))
	var third := draft.add("route_point", Vector3(1.0, 2.2, -5.0))
	draft.edit(target, {"speed": 0.65, "respawn": 0.18})
	var player_start := draft.add("player_start", Vector3(0, 0.425, 0))
	draft.edit(player_start, {"rotation": [0, 15, 0]})
	var wall := draft.add("wall", Vector3(-3.0, 1.25, -4.0))
	draft.edit(wall, {"size": [2.0, 2.5, 0.38]})
	var behind := draft.add("static_target", Vector3(-3.6, 1.65, -5.5))
	var area := draft.add("spawn_area", Vector3(2.4, 2.05, -6.0))
	draft.edit(area, {"size": [0.3, 0.25, 0.3], "rotation": [0, 30, 0]})
	var delayed := draft.add("moving_target", Vector3(8.0, 2.05, -8.0))
	draft.edit(delayed, {"spawn_rule": "delayed", "spawn_delay": 0.60, "spawn_area_id": area, "behavior": "static"})
	return {"target": target, "points": [first, second, third], "behind": behind, "delayed": delayed}


func _test_route_editor(editor: Editor, ids: Dictionary) -> void:
	editor._select(ids.target)
	for index in range(3):
		_press(editor.route_controls, "通過点を登録")
	_check(editor.draft.get_object(ids.target).route_points == ids.points, "point registration preserves order")
	_press(editor.route_controls, "↑")
	var reordered: Array = editor.draft.get_object(ids.target).route_points
	_check(reordered == [ids.points[0], ids.points[2], ids.points[1]], "point order is editable")
	_press(editor, "元に戻す")
	editor.draft.edit(ids.target, {"route_curve": true, "route_loop": true})
	editor.draft.edit(ids.points[2], {"position": [1.2, 2.25, -5.0]})
	var check := _button(editor.route_controls, "移動プレビュー")
	check.button_pressed = true
	var ghost := editor.view.route_ghost
	if ghost == null:
		_check(false, "route preview creates a visible ghost")
		return
	var before := editor.draft.document()
	var origin := ghost.position
	await create_timer(0.18).timeout
	_check(ghost.visible and origin.distance_to(ghost.position) > 0.02 and editor.view.route_lines.get_surface_count() == 1,
		"preview and path are rendered with edited positions")
	_check(editor.draft.document() == before, "preview changes no document data")
	check.button_pressed = false


func _test_validation(document: Dictionary) -> void:
	var bad := document.duplicate(true)
	bad.id = "../../settings.json"
	_check(Custom.validate(bad).is_empty(), "invalid ID can't select a filesystem path")
	bad = document.duplicate(true)
	bad.schema_version = 99
	_check(Custom.validate(bad).is_empty(), "future versions are rejected")
	bad = document.duplicate(true)
	bad.objects[1].route_points = [9999]
	_check(Custom.validate(bad).is_empty(), "dangling waypoints are rejected during import")
	bad = document.duplicate(true)
	bad.objects[1].id = bad.objects[0].id
	_check(Custom.validate(bad).is_empty(), "duplicate object IDs are rejected")
	bad = document.duplicate(true)
	bad.objects[0].size = [0, 1, 2]
	_check(Custom.validate(bad).is_empty(), "degenerate shapes are rejected")


func _test_play(studio: Studio, editor: Editor, before: Dictionary, ids: Dictionary) -> void:
	var edit_history := editor.draft.undo_stack.size()
	var view := editor.view_state()
	_press(editor, "テストプレイ")
	var run := studio.session
	await _ticks(12)
	_check(run.editor_test and run.player != null and is_equal_approx(run.camera.yaw, 15.0), "test uses custom player start")
	var target := _body(run, ids.target)
	var behind := _body(run, ids.behind)
	var delayed := _body(run, ids.delayed)
	_check(not delayed.visible, "delayed target starts hidden")
	var origin := target.position
	await _ticks(16)
	_check(target.position.distance_to(origin) > 0.03, "test uses the edited route")
	_shoot(run, behind)
	await _ticks(16)
	_check(run.stats.shots == 1 and run.stats.hits == 0, "authored wall blocks the shot")
	_shoot(run, target)
	await _ticks(8)
	_check(run.stats.hits == 1 and run.stats.eliminations == 1 and not target.visible,
		"custom hitbox, health and score work")
	await create_timer(0.74).timeout
	_check(target.visible and delayed.visible and delayed.position.distance_to(Vector3(2.4, 2.05, -6.0)) < 0.3,
		"target respawns and delayed target uses its rotated spawn volume")
	run.duration_usec = run.clock.elapsed(Time.get_ticks_usec()) + 30000
	await run.completed
	var reopened: Editor = studio.page
	_check(reopened != null and reopened.status.text.begins_with("テスト完了"), "completed test returns directly to the editor")
	_check(reopened.selected == view.selected and reopened.view.pivot.is_equal_approx(view.pivot)
		and reopened.draft.undo_stack.size() == edit_history, "editor selection, camera and history survive playtest")
	_check(Custom.validate(reopened.draft.document()) == before
		and _same_document(Custom.load_file(library.path_join(before.id + ".json")), before)
		and not FileAccess.file_exists(studio.best_path),
		"playtest doesn't change the draft, saved file or personal best")


func _test_library(studio: Studio, document: Dictionary, exported: String) -> void:
	_press(studio, "練習モード")
	_press(studio, "フリック")
	_press(studio, "カスタム練習")
	_check(Custom.catalogue(library).size() == 1 and _button(studio, "プレイ") != null, "fresh studio lists the saved scenario")
	_press(studio, "プレイ")
	var run := studio.session
	await _ticks(8)
	_check(run.scenario.id == document.id and not run.editor_test and run.custom.targets.size() == 3,
		"saved scenario launches as regular practice")
	_shoot(run, _body(run, int(document.objects[1].id)))
	await _ticks(8)
	run.duration_usec = run.clock.elapsed(Time.get_ticks_usec()) + 25000
	await run.completed
	_check(studio.session == null and FileAccess.file_exists(studio.best_path), "regular custom play writes a best score")
	_press(studio, "メニューへ戻る")
	_press(studio, "練習モード")
	_press(studio, "フリック")
	_press(studio, "カスタム練習")
	_press(studio, "編集")
	var editor: Editor = studio.page
	_check(editor.draft.config.id == document.id and editor.draft.undo_stack.is_empty(), "saved scenario reopens cleanly")
	_check(editor._import_path(exported) and editor.draft.config.id != document.id, "import creates a new independent ID")
	_check(editor.notice.text.contains("インポートしました") and editor.save_state.text == "未保存", "import indicates the copy still needs saving")
	_press(editor, "練習設定")
	var config_dialog: ConfirmationDialog = editor.find_children("*", "ConfirmationDialog", true, false).back()
	var name_field: LineEdit = config_dialog.find_children("*", "LineEdit", true, false)[0]
	name_field.text = "Shared copy"
	config_dialog.confirmed.emit()
	await process_frame
	_check(editor.draft.config.name == "Shared copy", "practice settings rename the imported scenario")
	_check(editor.notice.text.contains("適用しました") and editor.save_state.text == "未保存の変更あり", "applying settings shows feedback and unsaved changes")
	editor.library_dir = exported
	_check(editor._save() != OK and editor.notice.text.contains("保存できませんでした") and editor.draft.is_dirty(), "failed save shows an error and leaves the draft unsaved")
	editor.library_dir = library
	_check(editor._save() == OK and Custom.catalogue(library).size() == 2, "the imported copy becomes playable after saving")
	_press(editor, "読み込み")
	var load_dialog: ConfirmationDialog = editor.find_children("*", "ConfirmationDialog", true, false).back()
	load_dialog.confirmed.emit()
	await process_frame
	_check(editor.draft.config.id == document.id, "editor can switch to a named saved scenario")
	_check(editor.notice.text.contains("読み込みました"), "loading displays feedback")
	var invalid := folder.path_join("invalid.json")
	_check(Store.write(invalid, {"schema_version": 99}) == OK and not editor._import_path(invalid), "bad imports leave the current editor intact")


func _body(run: Session, id: int) -> StaticBody3D:
	for body: StaticBody3D in run.custom.targets:
		if run.custom.targets[body].entry.id == id:
			return body
	return null


func _shoot(run: Session, body: StaticBody3D) -> void:
	run.camera.look_at(body.global_position)
	for down: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		Input.parse_input_event(event)
		Input.flush_buffered_events()


func _ticks(count: int) -> void:
	for index in range(count):
		await physics_frame


func _cleanup(path: String) -> void:
	for file: String in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)


func _same_document(first: Dictionary, second: Dictionary) -> bool:
	return JSON.stringify(first) == JSON.stringify(second)


func _press(parent: Node, title: String) -> void:
	var button := _button(parent, title)
	if button != null:
		button.pressed.emit()


func _button(parent: Node, title: String) -> Button:
	for button: Button in parent.find_children("*", "Button", true, false):
		if button.text == title:
			return button
	_check(false, "button present: " + title)
	return null


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)
