extends Panel

@onready var username_entry: LineEdit = $"../Username entry"

func _ready() -> void:
	var loaded_data := DataManager.load_or_create()
	username_entry.text = str(loaded_data.data.get("player_name", ""))

func _on_quit_button_pressed() -> void:
	get_tree().quit()


func _on_username_entry_text_submitted(new_text: String) -> void:
	var loaded_data := DataManager.load_or_create()
	loaded_data.data["player_name"] = new_text
	loaded_data.save()
