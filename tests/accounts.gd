extends SceneTree

const Main = preload("res://scenes/studio.tscn")
const Studio = preload("res://scripts/ui/studio.gd")
const Accounts = preload("res://scripts/persistence/local_accounts.gd")
const AccountPage = preload("res://scripts/ui/account_page.gd")
const Aim = preload("res://scripts/input/aim_settings.gd")
const Movement = preload("res://scripts/movement/movement_settings.gd")
const Store = preload("res://scripts/persistence/json_store.gd")
const Custom = preload("res://scripts/scenarios/custom_scenario.gd")
const Draft = preload("res://scripts/editor/editor_draft.gd")
const Bindings = preload("res://scripts/input/movement_bindings.gd")
const PASSWORD := "example password 123"

var failures: Array[String] = []
var test_dir := "user://account-check-%d" % OS.get_process_id()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	create_timer(50.0).timeout.connect(func() -> void:
		push_error("Account test timed out")
		quit(1)
	)
	var crypto := Crypto.new()
	var test_salt := "salt".to_utf8_buffer()
	_check(Accounts._derive(crypto, "password".to_utf8_buffer(), test_salt, 2).hex_encode()
		== "ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43", "PBKDF2 matches an independent test vector")
	_check(Accounts._derive(crypto, "x".repeat(65).to_utf8_buffer(), test_salt, 2).hex_encode()
		== "b5a1700563b197a9ddfcdd1e02aa3bb0882203a3246ba1811de32290e7df8f7a", "long passwords use the HMAC key hash")
	_check(DirAccess.make_dir_recursive_absolute(test_dir) == OK, "create an isolated test directory")
	var studio := _new_studio()
	var guest_key := studio._record_key()
	_check(Store.write(studio.best_path, {"schema_version": 1, "scores": {guest_key: 250}}) == OK, "save a guest score")
	studio._load_best_scores()
	var guest_aim := studio.aim.values.duplicate()
	guest_aim.sensitivity = 0.17
	_check(studio.aim.save(guest_aim) == OK, "save guest sensitivity")
	var guest_movement := studio.movement.values.duplicate()
	guest_movement.walk_speed = 4.0
	_check(studio.movement.save(guest_movement) == OK, "save guest movement")
	var guest_keys := studio.bindings.values.duplicate()
	guest_keys.move_forward = KEY_UP
	_check(studio.bindings.save(guest_keys) == OK, "save guest key assignment")
	var guest_draft := Draft.new()
	studio.editor_draft = guest_draft
	var guest_document := guest_draft.document()
	_check(Custom.save(guest_document, studio.custom_library_dir) == OK, "save a guest scenario")

	_button(studio, "設定").pressed.emit()
	_button(studio, "アカウント · ゲスト").pressed.emit()
	var form := _account_form(studio)
	form.change_form.pressed.emit()
	form.username.text = "../User"
	_submit(form, PASSWORD)
	await _wait_for(form)
	_check(form.status.visible and studio.account_name.is_empty(), "path-like usernames are rejected")
	form.username.text = "練習_Player"
	_submit(form, "short")
	await _wait_for(form)
	_check(form.status.text.contains("12"), "short passwords are rejected")
	form.password.text = PASSWORD
	form.confirmation.text = "separate phrase"
	form.submit.pressed.emit()
	_check(form.job == null and form.status.text.contains("一致"), "registration requires matching passwords")
	_submit(form, PASSWORD)
	_check(form.submit.disabled and form.password.text.is_empty(), "registration runs off the UI thread and clears the password field")
	await _wait_for(form)
	if studio.account_name != "練習_Player":
		push_error("Registration did not sign in: " + form.status.text)
		quit(1)
		return
	var profile_dir := studio.account_directory
	var record_path := profile_dir.path_join(Accounts.RECORD)
	var record := Store.read(record_path)
	_check(record.verifier.length() == 64 and record.salt.length() == 32
		and not FileAccess.get_file_as_string(record_path).contains(PASSWORD), "only the salted verifier is stored")
	_check(studio._best() == -1 and studio.aim.values.sensitivity == studio.aim.defaults.sensitivity
		and studio.movement.values.walk_speed == studio.movement.defaults.walk_speed
		and studio.bindings.values.move_forward == KEY_W
		and studio.editor_draft == null and Custom.catalogue(studio.custom_library_dir).is_empty(), "new account starts with an independent profile")
	var aim := studio.aim.values.duplicate()
	aim.sensitivity = 0.62
	_check(studio.aim.save(aim) == OK, "save account sensitivity")
	var movement := studio.movement.values.duplicate()
	movement.walk_speed = 5.0
	_check(studio.movement.save(movement) == OK, "save account movement")
	var account_keys := studio.bindings.values.duplicate()
	account_keys.move_forward = KEY_I
	_check(studio.bindings.save(account_keys) == OK, "save account key assignment")
	_check(Store.write(studio.best_path, {"schema_version": 1, "scores": {guest_key: 650}}) == OK, "save account score")
	var account_draft := Draft.new()
	_check(Custom.save(account_draft.document(), studio.custom_library_dir) == OK, "save account scenario")

	_button(studio, "設定").pressed.emit()
	_button(studio, "アカウント · 練習_Player").pressed.emit()
	_button(studio, "ログアウト").pressed.emit()
	_check(studio.account_name.is_empty() and studio._best() == 250 and studio.aim.values.sensitivity == 0.17
		and studio.movement.values.walk_speed == 4.0 and studio.editor_draft == guest_draft
		and studio.bindings.values.move_forward == KEY_UP
		and Custom.catalogue(studio.custom_library_dir)[0].id == guest_document.id, "logout restores guest data and draft")
	studio.free()
	studio = _new_studio()
	_button(studio, "設定").pressed.emit()
	_button(studio, "アカウント · ゲスト").pressed.emit()
	form = _account_form(studio)
	form.username.text = "練習_player"
	form.change_form.pressed.emit()
	_submit(form, "different credential")
	await _wait_for(form)
	_check(form.status.text.contains("すでに") and Store.read(record_path) == record, "case-insensitive duplicate leaves registration intact")
	form.change_form.pressed.emit()
	_submit(form, "wrong passphrase")
	await _wait_for(form)
	_check(studio.account_name.is_empty() and form.status.text == Accounts.INVALID_LOGIN, "incorrect password leaves guest active")
	_submit(form, PASSWORD)
	await _wait_for(form)
	_check(studio.account_name == "練習_Player" and studio.account_directory == profile_dir, "registered account logs in after restarting the studio")
	_check(studio._best() == 650 and studio.aim.values.sensitivity == 0.62 and studio.movement.values.walk_speed == 5.0
		and studio.bindings.values.move_forward == KEY_I
		and Custom.catalogue(studio.custom_library_dir)[0].id == account_draft.config.id, "login reloads the registered account's data")
	await _check_concurrent_registration(studio.accounts)
	var account_scenarios := studio.custom_library_dir
	studio.free()
	for folder: String in [test_dir.path_join("guest-scenarios"), account_scenarios, profile_dir, test_dir.path_join("accounts"), test_dir]:
		for file: String in DirAccess.get_files_at(folder):
			DirAccess.remove_absolute(folder.path_join(file))
		DirAccess.remove_absolute(folder)
	print("Account tests passed." if failures.is_empty() else "Account test failures: %d" % failures.size())
	quit(0 if failures.is_empty() else 1)


func _check_concurrent_registration(accounts: Accounts) -> void:
	var first := Thread.new()
	var second := Thread.new()
	var first_started := first.start(accounts.register.bind("same-name", PASSWORD)) == OK
	var second_started := second.start(accounts.register.bind("SAME-NAME", "another example password")) == OK
	while first.is_alive() or second.is_alive():
		await process_frame
	var result_a: Dictionary = first.wait_to_finish() if first_started else {}
	var result_b: Dictionary = second.wait_to_finish() if second_started else {}
	_check(first_started and second_started and result_a.has("directory") != result_b.has("directory"),
		"concurrent registration publishes one account")
	var winner := result_a if result_a.has("directory") else result_b
	if not winner.has("directory"):
		return
	var loser := result_b if winner == result_a else result_a
	_check(loser.get("message", "").contains("すでに"), "the competing registration reports a duplicate")
	var directory: String = winner.directory
	_check(Store.read(directory.path_join(Accounts.RECORD)).get("username") == winner.username,
		"the competing registration cannot overwrite the installed account")
	DirAccess.remove_absolute(directory.path_join(Accounts.RECORD))
	DirAccess.remove_absolute(directory)


func _new_studio() -> Studio:
	var studio: Studio = Main.instantiate()
	studio.accounts = Accounts.new(test_dir.path_join("accounts"))
	studio.aim = Aim.new(test_dir.path_join("guest-aim.json"))
	studio.movement = Movement.new(test_dir.path_join("guest-movement.json"))
	studio.bindings = Bindings.new(test_dir.path_join("guest-key-bindings.json"))
	studio.best_path = test_dir.path_join("guest-best.json")
	studio.custom_library_dir = test_dir.path_join("guest-scenarios")
	root.add_child(studio)
	return studio


func _account_form(studio: Studio) -> AccountPage:
	return studio.page.find_children("*", "CenterContainer", true, false)[0]


func _submit(form: AccountPage, password: String) -> void:
	form.password.text = password
	form.confirmation.text = password
	form.submit.pressed.emit()


func _wait_for(form: AccountPage) -> void:
	while is_instance_valid(form) and form.job != null:
		await process_frame


func _button(studio: Studio, caption: String) -> Button:
	for button: Button in studio.page.find_children("*", "Button", true, false):
		if button.text == caption:
			return button
	_check(false, "button is available: " + caption)
	return null


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)
