class_name GlobalSettings
extends RefCounted

static var pointer_locked := false

static var mouse_sensitivity: float = 0.0025
static var invert_mouse_y := false
static var field_of_view: float = 70.0


static func set_pointer_locked(locked: bool) -> void:
	pointer_locked = locked
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED if locked else Input.MOUSE_MODE_VISIBLE)


static func toggle_pointer_lock() -> void:
	set_pointer_locked(not pointer_locked)
