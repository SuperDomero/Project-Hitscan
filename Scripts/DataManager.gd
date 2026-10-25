class_name DataManager
extends Resource

const SAVE_FILE_PATH: String = "user://save_data.tres"
const SAVE_TEMP_PATH: String = "user://save_data.tmp.tres"
const INVALID_SAVE_PATH: String = "user://save_data.invalid.bak"

@export var data: Dictionary = {}


## Saves this SaveData resource instance to disk atomically.
func save() -> Error:
	var error := ResourceSaver.save(self, SAVE_TEMP_PATH)
	if error != OK:
		push_error("Failed to write save data to ", SAVE_TEMP_PATH, ". Error code: ", error)
		_remove_if_exists(SAVE_TEMP_PATH)
		return error

	error = DirAccess.rename_absolute(SAVE_TEMP_PATH, SAVE_FILE_PATH)
	if error != OK:
		push_error("Failed to replace save file ", SAVE_FILE_PATH, ". Error code: ", error)
		_remove_if_exists(SAVE_TEMP_PATH)
		return error

	take_over_path(SAVE_FILE_PATH)
	return OK


## Loads the SaveData resource from disk, or creates a new default instance if missing.
static func load_or_create() -> DataManager:
	if not FileAccess.file_exists(SAVE_FILE_PATH):
		return DataManager.new()

	var res := ResourceLoader.load(SAVE_FILE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	if res is DataManager:
		return res

	push_error(
		"Save file ", SAVE_FILE_PATH, " is not a valid DataManager. "
		+ "Moving it to ", INVALID_SAVE_PATH, " and starting with fresh data."
	)
	_backup_invalid_save()
	return DataManager.new()


static func _backup_invalid_save() -> void:
	_remove_if_exists(INVALID_SAVE_PATH)
	var error := DirAccess.rename_absolute(SAVE_FILE_PATH, INVALID_SAVE_PATH)
	if error != OK:
		push_error("Failed to back up invalid save file. Error code: ", error)


static func _remove_if_exists(path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var error := DirAccess.remove_absolute(path)
	if error != OK:
		push_error("Failed to remove ", path, ". Error code: ", error)
