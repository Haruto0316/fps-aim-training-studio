extends RefCounted

const Store = preload("res://scripts/persistence/json_store.gd")
const DIRECTORY := "user://accounts"
const RECORD := "account.json"
const ITERATIONS := 600000
const MIN_PASSWORD := 12
const MAX_PASSWORD := 128
const MAX_NAME := 32
const INVALID_LOGIN := "ユーザー名またはパスワードが違います。"

var directory: String


func _init(path := DIRECTORY) -> void:
	directory = path


func register(username: String, password: String) -> Dictionary:
	username = username.strip_edges()
	if not _valid_name(username):
		return {"message": "ユーザー名は2〜32文字の文字・数字・_・-で入力し、先頭には文字か数字を使ってください。"}
	if password.length() < MIN_PASSWORD or password.length() > MAX_PASSWORD:
		return {"message": "パスワードは%d〜%d文字で入力してください。" % [MIN_PASSWORD, MAX_PASSWORD]}
	var destination := _account_path(username)
	if DirAccess.dir_exists_absolute(destination):
		return {"message": "このユーザー名はすでに登録されています。"}
	var crypto := Crypto.new()
	var salt := crypto.generate_random_bytes(16)
	if salt.size() != 16:
		return _write_error(ERR_CANT_CREATE)
	var verifier := _derive(crypto, password.to_utf8_buffer(), salt, ITERATIONS)
	if verifier.size() != 32:
		return _write_error(ERR_UNAVAILABLE)
	var error := DirAccess.make_dir_recursive_absolute(directory)
	if error != OK:
		return _write_error(error)
	# Publish the directory only after the verifier is written. A duplicate never replaces an existing account.
	var staging := directory.path_join(".pending-" + salt.hex_encode())
	error = DirAccess.make_dir_absolute(staging)
	if error != OK:
		return _write_error(error)
	var temporary_record := staging.path_join(RECORD)
	error = Store.write(temporary_record, {
		"schema_version": 1, "username": username, "salt": salt.hex_encode(),
		"iterations": ITERATIONS, "verifier": verifier.hex_encode()
	})
	if error == OK:
		error = DirAccess.rename_absolute(staging, destination)
	if error != OK:
		if FileAccess.file_exists(temporary_record):
			DirAccess.remove_absolute(temporary_record)
		DirAccess.remove_absolute(staging)
		if DirAccess.dir_exists_absolute(destination):
			return {"message": "このユーザー名はすでに登録されています。"}
		return _write_error(error)
	return {"username": username, "directory": destination}


func login(username: String, password: String) -> Dictionary:
	username = username.strip_edges()
	if not _valid_name(username) or password.is_empty() or password.length() > MAX_PASSWORD:
		return {"message": INVALID_LOGIN}
	var path := _account_path(username)
	var record := Store.read(path.path_join(RECORD))
	if record.get("schema_version") != 1 or not record.get("username") is String \
		or record.username.to_lower() != username.to_lower() or record.get("iterations") != ITERATIONS:
		return {"message": INVALID_LOGIN}
	if not record.get("salt") is String or not record.get("verifier") is String:
		return {"message": INVALID_LOGIN}
	var salt: PackedByteArray = record.salt.hex_decode()
	var trusted: PackedByteArray = record.verifier.hex_decode()
	if salt.size() != 16 or trusted.size() != 32:
		return {"message": INVALID_LOGIN}
	var crypto := Crypto.new()
	var received := _derive(crypto, password.to_utf8_buffer(), salt, ITERATIONS)
	if not crypto.constant_time_compare(trusted, received):
		return {"message": INVALID_LOGIN}
	return {"username": record.username, "directory": path}


func _account_path(username: String) -> String:
	return directory.path_join(username.to_lower().sha256_text())


static func _valid_name(username: String) -> bool:
	return username.length() <= MAX_NAME and RegEx.create_from_string(
		"\\A[\\p{L}\\p{N}][\\p{L}\\p{M}\\p{N}_-]{1,31}\\z"
	).search(username) != null


static func _write_error(error: Error) -> Dictionary:
	return {"message": "アカウントを保存できませんでした（%s）。" % error_string(error)}


static func _derive(crypto: Crypto, password: PackedByteArray, salt: PackedByteArray, iterations: int) -> PackedByteArray:
	# PBKDF2-HMAC-SHA256 with one 32-byte output block.
	var key := password
	if key.size() > 64:
		var hash := HashingContext.new()
		hash.start(HashingContext.HASH_SHA256)
		hash.update(key)
		key = hash.finish()
	var block := salt.duplicate()
	block.append_array(PackedByteArray([0, 0, 0, 1]))
	var digest := crypto.hmac_digest(HashingContext.HASH_SHA256, key, block)
	if digest.size() != 32:
		return PackedByteArray()
	var verifier := digest.duplicate()
	for iteration in range(1, iterations):
		digest = crypto.hmac_digest(HashingContext.HASH_SHA256, key, digest)
		if digest.size() != 32:
			return PackedByteArray()
		for index in range(32):
			verifier[index] ^= digest[index]
	return verifier
