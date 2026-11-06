extends ColorRect

@export_group("Speed Lines")
## Speed at which the effect starts to appear.
@export var min_speed: float = 8.0
## Speed at which the effect reaches full intensity and length.
@export var max_speed: float = 16.0
## Highest opacity the lines can reach.
@export var max_intensity: float = 1.0
## How quickly the effect fades in and out.
@export var fade_speed: float = 6.0

@export var player_path: NodePath = ^"../.."
@export var camera_holder_path: NodePath = ^"Camera holder"

@onready var _player: PlayerMovement = get_node_or_null(player_path) as PlayerMovement

var _shader_material: ShaderMaterial = null
var _camera: Camera3D = null
var _intensity := 0.0
var _speed_ratio := 0.0
var _camera_velocity := Vector3.ZERO


func _ready() -> void:
	_shader_material = material as ShaderMaterial
	if _player == null:
		return
	var camera_holder := _player.get_node_or_null(camera_holder_path)
	if camera_holder != null:
		_camera = camera_holder.find_child("Camera3D", true, false) as Camera3D


func _process(delta: float) -> void:
	if _player == null or _shader_material == null:
		return

	var speed := _player.velocity.length()
	var target_ratio := 0.0
	if max_speed > min_speed:
		target_ratio = clampf(inverse_lerp(min_speed, max_speed, speed), 0.0, 1.0)
	elif speed >= max_speed:
		target_ratio = 1.0

	var fade := 1.0 - exp(-fade_speed * delta)
	_speed_ratio = lerpf(_speed_ratio, target_ratio, fade)
	_intensity = lerpf(_intensity, target_ratio * max_intensity, fade)

	var target_velocity := Vector3.ZERO
	if _camera != null:
		target_velocity = _camera.global_transform.basis.inverse() * _player.velocity
	_camera_velocity = _camera_velocity.lerp(target_velocity, fade)

	_shader_material.set_shader_parameter("intensity", _intensity)
	_shader_material.set_shader_parameter("speed_ratio", _speed_ratio)
	_shader_material.set_shader_parameter("camera_velocity", _camera_velocity)
