extends SceneTree

const Main = preload("res://scenes/studio.tscn")
const Studio = preload("res://scripts/ui/studio.gd")
const Editor = preload("res://scripts/editor/editor_page.gd")
const Draft = preload("res://scripts/editor/editor_draft.gd")

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	create_timer(15.0).timeout.connect(func() -> void:
		push_error("Phase 6 tests timed out")
		quit(1)
	)
	_test_history()
	var studio: Studio = Main.instantiate()
	root.add_child(studio)
	await process_frame
	_button(studio, "3D エディター").pressed.emit()
	await process_frame
	await process_frame
	var editor: Editor = studio.page
	_check(editor != null and editor.view.size.x >= 270 and editor.view.size.y >= 260, "editor presents an interactive viewport")
	_check(editor.objects.item_count == 3 and editor.view.nodes.size() == 3 and editor.undo_button.disabled,
		"starter floor, target and cover are rendered without a history step")
	await _test_pointer(editor)
	_test_properties(editor)
	var before := editor.draft.objects.duplicate(true)
	var history_size := editor.draft.undo_stack.size()
	_button(editor, "ホーム").pressed.emit()
	_button(studio, "3D エディター").pressed.emit()
	var reopened: Editor = studio.page
	_check(not is_instance_valid(editor) or not editor.is_inside_tree(), "old editor page is detached")
	_check(reopened.draft.objects == before and reopened.draft.undo_stack.size() == history_size,
		"live draft and undo history survive returning to the home menu")
	studio.queue_free()
	await process_frame
	print("Phase 6 tests passed." if failures.is_empty() else "Phase 6 checks failed: %d" % failures.size())
	quit(0 if failures.is_empty() else 1)


func _test_history() -> void:
	var draft := Draft.new(false)
	var first := draft.add("enemy", Vector3(0, 1.5, -4))
	var clone := draft.duplicate_object(first)
	var extra := draft.add("spawn_area", Vector3.ZERO)
	_check(first != clone and clone != extra and draft.objects.size() == 3, "independent IDs")
	draft.edit(clone, {"position": [2.0, 1.5, -4.0], "behavior": "jump"})
	_check(draft.get_object(clone).behavior == "jump" and draft.get_object(first).behavior == "strafe",
		"duplicate configuration can be edited independently")
	draft.remove(clone)
	draft.undo()
	_check(draft.objects[1].id == clone and draft.get_object(clone).position[0] == 2.0, "undo restores deletion at the original index")
	draft.undo()
	_check(draft.get_object(clone).behavior == "strafe", "undo restores prior attributes")
	draft.redo()
	_check(draft.get_object(clone).behavior == "jump", "redo reapplies edits")
	draft.edit(clone, {"health": 250})
	_check(draft.redo_stack.is_empty(), "a new edit clears stale redo actions")
	var document := {"map": draft.map, "objects": draft.objects}
	_check(JSON.parse_string(JSON.stringify(document)).objects.size() == 3, "draft uses JSON-ready coordinates and attributes")


func _test_pointer(editor: Editor) -> void:
	var view := editor.view
	var target_id: int = editor.draft.objects[1].id
	var target: MeshInstance3D = view.nodes[target_id]
	var origin := target.position
	var point := view.camera.unproject_position(origin)
	_check(view.pick_at(point) == target_id, "click picking selects the visible sphere before the floor")
	_mouse(editor, point, MOUSE_BUTTON_LEFT, true)
	await process_frame
	_check(editor.selected == target_id, "root input reaches the 3D viewport")
	_mouse(editor, point, MOUSE_BUTTON_LEFT, false)

	_button(editor, "Y").pressed.emit()
	var projected := view.camera.unproject_position(origin + Vector3.UP) - point
	_mouse(editor, point, MOUSE_BUTTON_LEFT, true)
	_motion(editor, point + projected * 0.62, projected * 0.62, MOUSE_BUTTON_MASK_LEFT)
	_motion(editor, point + projected * 1.03, projected * 0.41, MOUSE_BUTTON_MASK_LEFT)
	_mouse(editor, point + projected * 1.03, MOUSE_BUTTON_LEFT, false)
	var moved := Draft.vector(editor.draft.get_object(target_id).position)
	_check(is_equal_approx(moved.x, origin.x) and is_equal_approx(moved.z, origin.z)
		and is_equal_approx(moved.y, snappedf(origin.y + 1.03, 0.5)), "axis drag snaps only the selected coordinate")
	_check(editor.draft.undo_stack.size() == 1, "one drag has one undo action")
	_button(editor, "元に戻す").pressed.emit()
	_check(target.position.is_equal_approx(origin), "undo restores the preview transform")
	_button(editor, "やり直す").pressed.emit()
	_check(target.position.is_equal_approx(moved), "redo restores the dragged position")

	_button(editor, "XZ").pressed.emit()
	point = view.camera.unproject_position(moved)
	var along_floor := view.camera.unproject_position(moved + Vector3(1.2, 0, -0.8))
	_mouse(editor, point, MOUSE_BUTTON_LEFT, true)
	_motion(editor, along_floor, along_floor - point, MOUSE_BUTTON_MASK_LEFT)
	_check(not target.position.is_equal_approx(moved), "planar drag previews a physical displacement")
	_key(KEY_ESCAPE)
	_mouse(editor, along_floor, MOUSE_BUTTON_LEFT, false)
	_check(target.position.is_equal_approx(moved) and editor.draft.undo_stack.size() == 1, "cancelling a drag does not edit history")

	var yaw := view.yaw
	var pivot := view.pivot
	var distance := view.distance
	point = view.size * 0.5
	_motion(editor, point, Vector2(31, -15), MOUSE_BUTTON_MASK_RIGHT)
	_motion(editor, point, Vector2(20, 7), MOUSE_BUTTON_MASK_MIDDLE)
	_mouse(editor, point, MOUSE_BUTTON_WHEEL_UP, true)
	_check(view.yaw != yaw and view.pivot != pivot and view.distance < distance, "orbit, pan and zoom respond to mouse input")


func _test_properties(editor: Editor) -> void:
	editor.add_menu.select(Draft.KINDS.keys().find("enemy"))
	_button(editor, "追加").pressed.emit()
	var id := editor.selected
	_check(editor.objects.item_count == 4 and editor.draft.get_object(id).kind == "enemy", "add an AI dummy from the object menu")
	var node: MeshInstance3D = editor.view.nodes[id]
	_check(node.mesh is CapsuleMesh and node.get_aabb().size.y > node.get_aabb().size.x
		and (node.scale * node.get_aabb().size).is_equal_approx(Vector3(0.75, 1.55, 0.75)),
		"capsule preview has the configured dimensions")
	_spin(editor.vector_fields.rotation[1], "45")
	_spin(editor.vector_fields.size[0], "1.30")
	_spin(editor.number_fields.health, "250")
	_spin(editor.number_fields.speed, "5.8")
	_spin(editor.number_fields.spawn_delay, "2")
	_pick_choice(editor, "behavior", "jump")
	_pick_choice(editor, "shape", "box")
	_pick_choice(editor, "spawn_rule", "delayed")
	editor.color_field.color = Color("#77cdaa")
	editor.color_field.popup_closed.emit()
	var values := editor.draft.get_object(id)
	_check(values.health == 250 and is_equal_approx(values.speed, 5.8) and values.behavior == "jump"
		and values.spawn_rule == "delayed" and values.spawn_delay == 2.0, "AI and spawn details reach the draft")
	_check(node.mesh is BoxMesh and is_equal_approx(node.rotation_degrees.y, 45.0)
		and is_equal_approx(node.scale.x, 1.3) and values.color == "#77cdaa", "shape, rotation, scale and color reach the 3D preview")
	_button(editor, "複製").pressed.emit()
	var copy_id := editor.selected
	_check(copy_id != id and editor.draft.get_object(copy_id).health == 250, "duplicate retains the edited properties")
	_button(editor, "削除").pressed.emit()
	_check(editor.draft.get_object(copy_id).is_empty() and not editor.view.nodes.has(copy_id), "deleted object disappears in the scene")
	_button(editor, "元に戻す").pressed.emit()
	_check(editor.view.nodes.has(copy_id), "deletion undo recreates the mesh")
	_button(editor, "マップ設定").pressed.emit()
	_spin(editor.number_fields.light, "1.4")
	_spin(editor.number_fields.width, "30")
	_check(is_equal_approx(editor.view.light.light_energy, 1.4) and editor.draft.map.width == 30,
		"map controls update viewport light and grid bounds")


func _spin(field: SpinBox, text: String) -> void:
	field.get_line_edit().text = text
	field.apply()


func _pick_choice(editor: Editor, key: String, value: String) -> void:
	var row: Array = editor.choice_fields[key]
	var index: int = row[1].find(value)
	row[0].select(index)
	row[0].item_selected.emit(index)


func _mouse(editor: Editor, point: Vector2, button: MouseButton, down: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = down
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if down and button == MOUSE_BUTTON_LEFT else 0
	event.position = editor.view.get_global_transform_with_canvas() * point
	event.global_position = event.position
	root.push_input(event, true)


func _motion(editor: Editor, point: Vector2, offset: Vector2, mask: MouseButtonMask) -> void:
	var event := InputEventMouseMotion.new()
	var transform_2d := editor.view.get_global_transform_with_canvas()
	event.position = transform_2d * point
	event.global_position = event.position
	event.relative = transform_2d.basis_xform(offset)
	event.button_mask = mask
	root.push_input(event, true)


func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	root.push_input(event)


func _button(node: Node, caption: String) -> Button:
	for button: Button in node.find_children("*", "Button", true, false):
		if button.text == caption:
			return button
	_check(false, "button present: " + caption)
	return null


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)
