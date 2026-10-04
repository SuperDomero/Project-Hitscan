class_name DataManager
extends Resource

const SAVE_FILE_PATH: String = "user://save_data.tres"

## Saves this SaveData resource instance to disk
func save() -> Error:
	var error := ResourceSaver.save(self, SAVE_FILE_PATH)
	if error != OK:
		push_error("Failed to save data to ", SAVE_FILE_PATH, ". Error code: ", error)
	return error

## Loads the SaveData resource from disk, or creates a new default instance if missing
static func load_or_create() -> DataManager:
	if ResourceLoader.exists(SAVE_FILE_PATH):
		var res = ResourceLoader.load(SAVE_FILE_PATH)
		if res is DataManager:
			return res
	
	# Return a fresh default SaveData object if no save file exists
	return DataManager.new()
