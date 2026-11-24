extends CenterContainer

const Accounts = preload("res://scripts/persistence/local_accounts.gd")
const Style = preload("res://scripts/ui/style.gd")

signal home_requested
signal account_changed(username: String, directory: String)

var accounts: Accounts
var account_name: String
var registering := false
var job: Thread
var form: VBoxContainer
var heading: Label
var guidance: Label
var username: LineEdit
var password: LineEdit
var confirmation: LineEdit
var confirmation_row: Control
var status: Label
var submit: Button
var change_form: Button
var back: Button


func _ready() -> void:
	set_process(false)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	form = Style.panel(self, 22)
	form.custom_minimum_size.x = 448
	if not account_name.is_empty():
		form.add_child(Style.label("ログイン中", 25))
		var name := Style.label(account_name, 22, Style.ACCENT)
		name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		form.add_child(name)
		form.add_child(Style.button("ログアウト", func() -> void: account_changed.emit("", ""), true))
		form.add_child(Style.button("ホームへ戻る", func() -> void: home_requested.emit()))
		return
	heading = Style.label("", 32)
	form.add_child(heading)
	guidance = Style.label("", 16, Style.MUTED)
	guidance.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	form.add_child(guidance)
	username = _line("ユーザー名", Accounts.MAX_NAME)
	password = _line("パスワード", Accounts.MAX_PASSWORD, true)
	confirmation = _line("パスワードの確認", Accounts.MAX_PASSWORD, true)
	confirmation_row = confirmation.get_parent()
	status = Style.label("", 15, Style.ACCENT)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	form.add_child(status)
	submit = Style.button("", _submit, true)
	form.add_child(submit)
	var links := HBoxContainer.new()
	links.add_theme_constant_override("separation", 8)
	form.add_child(links)
	change_form = Style.button("", func() -> void: _set_form(not registering))
	change_form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	links.add_child(change_form)
	back = Style.button("ホームへ戻る", func() -> void: home_requested.emit())
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	links.add_child(back)
	username.text_submitted.connect(func(_text: String) -> void: password.grab_focus())
	password.text_submitted.connect(func(_text: String) -> void:
		if registering:
			confirmation.grab_focus()
		else:
			_submit()
	)
	confirmation.text_submitted.connect(func(_text: String) -> void: _submit())
	_set_form(false)


func _line(caption: String, max_length: int, secret := false) -> LineEdit:
	var input := LineEdit.new()
	input.custom_minimum_size = Vector2(232, 37)
	input.max_length = max_length
	input.secret = secret
	input.context_menu_enabled = not secret
	input.accessibility_name = caption
	Style.field(form, caption, input)
	return input


func _set_form(create_account: bool) -> void:
	registering = create_account
	heading.text = "アカウント登録" if registering else "ログイン"
	guidance.text = "このPCで使うユーザー名と%d文字以上のパスワードを登録します。" % Accounts.MIN_PASSWORD \
		if registering else "このPCに登録したアカウントで練習を続けます。"
	confirmation_row.visible = registering
	submit.text = "登録してログイン" if registering else "ログイン"
	change_form.text = "ログインに戻る" if registering else "新規登録"
	status.hide()
	password.clear()
	confirmation.clear()
	username.grab_focus()


func _submit() -> void:
	if job != null:
		return
	if registering and password.text != confirmation.text:
		_show_status("確認用のパスワードが一致しません。")
		confirmation.grab_focus()
		return
	var operation: Callable = accounts.register if registering else accounts.login
	job = Thread.new()
	var error := job.start(operation.bind(username.text, password.text))
	password.clear()
	confirmation.clear()
	if error != OK:
		job = null
		_show_status("処理を開始できませんでした（%s）。" % error_string(error))
		return
	_set_busy(true)
	_show_status("登録しています…" if registering else "確認しています…")


func _process(_delta: float) -> void:
	if job.is_alive():
		return
	var result: Dictionary = job.wait_to_finish()
	job = null
	_set_busy(false)
	if result.has("directory"):
		account_changed.emit(result.username, result.directory)
	else:
		_show_status(result.message)
		password.grab_focus()


func _set_busy(busy: bool) -> void:
	set_process(busy)
	username.editable = not busy
	password.editable = not busy
	confirmation.editable = not busy
	submit.disabled = busy
	change_form.disabled = busy
	back.disabled = busy


func _show_status(message: String) -> void:
	status.text = message
	status.show()


func _exit_tree() -> void:
	if job != null:
		job.wait_to_finish()
		job = null
