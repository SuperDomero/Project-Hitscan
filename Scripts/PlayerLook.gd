extends Node3D

@export var player_path: NodePath = NodePath("..")
@export var pitch_limit_degrees: float = 90.0

@onready var _player: Node3D = get_node(player_path)
@onready var _camera: Camera3D = find_child("Camera3D", true, false) as Camera3D


func _ready() -> void:
	GlobalSettings.set_pointer_locked(true)
	if _camera != null:
		_camera.fov = GlobalSettings.field_of_view


func _unhandled_input(event: InputEvent) -> void:
	if not GlobalSettings.pointer_locked:
		return
	var mouse_motion := event as InputEventMouseMotion
	if mouse_motion == null:
		return
	_apply_look(mouse_motion.relative)


func _apply_look(relative: Vector2) -> void:
	var pitch_sensitivity := GlobalSettings.mouse_sensitivity
	if GlobalSettings.invert_mouse_y:
		pitch_sensitivity = -pitch_sensitivity

	var pitch_limit := deg_to_rad(pitch_limit_degrees)
	rotation.x = clampf(
		rotation.x - relative.y * pitch_sensitivity,
		-pitch_limit,
		pitch_limit
	)
	_player.rotation.y -= relative.x * GlobalSettings.mouse_sensitivity
