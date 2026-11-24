extends RefCounted


static func read(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > 1024 * 1024:
		return {}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK or not parser.data is Dictionary:
		return {}
	return parser.data


static func read_saved(path: String) -> Dictionary:
	var data := read(path)
	return read(path + ".bak") if data.is_empty() else data


static func write(path: String, data: Dictionary, full_precision := false) -> Error:
	var staging := "%s.%d.%d.tmp" % [path, OS.get_process_id(), Time.get_ticks_usec()]
	var file := FileAccess.open(staging, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	var stored := file.store_string(JSON.stringify(data, "\t", true, full_precision) + "\n")
	file.flush()
	var error := file.get_error()
	file.close()
	if not stored and error == OK:
		error = ERR_FILE_CANT_WRITE
	if error == OK and FileAccess.file_exists(path):
		error = DirAccess.rename_absolute(path, path + ".bak")
	if error == OK:
		error = DirAccess.rename_absolute(staging, path)
	if error == OK and FileAccess.file_exists(path + ".bak"):
		DirAccess.remove_absolute(path + ".bak")
	if error != OK:
		DirAccess.remove_absolute(staging)
	return error


static func number(value: Variant, fallback: float, low: float, high: float) -> float:
	if (value is int or value is float) and is_finite(float(value)):
		return clampf(float(value), low, high)
	return fallback
