class_name CameraRecoil
extends Node3D

@export var weapon_manager_path: NodePath = ^"../../GunViewport/WeaponHolder/WeaponManager"

@onready var _manager: WeaponManager = get_node_or_null(
	weapon_manager_path
) as WeaponManager

var _recoil := Vector2.ZERO
var _kick_start := Vector2.ZERO
var _return_time := 0.0
var _return_elapsed := 0.0
var _returning := false


func _ready() -> void:
	if _manager == null:
		push_warning("%s has no WeaponManager and will not recoil." % name)
		return
	_manager.fired.connect(_on_weapon_fired)


func _process(delta: float) -> void:
	if not _returning:
		return

	_return_elapsed += delta
	if _return_time <= 0.0 or _return_elapsed >= _return_time:
		_recoil = Vector2.ZERO
		_returning = false
	else:
		_recoil = _kick_start.lerp(Vector2.ZERO, _return_elapsed / _return_time)
	_apply()


## Kicks the camera by a random amount within the given recoil limits.
func kick(vertical_degrees: float, horizontal_degrees: float, return_time: float) -> void:
	_recoil += Vector2(
		randf_range(-horizontal_degrees, horizontal_degrees),
		randf_range(0.0, vertical_degrees)
	)
	_kick_start = _recoil
	_return_time = return_time
	_return_elapsed = 0.0
	_returning = true
	_apply()


## Current visual offset in degrees, with x as yaw and y as pitch.
func get_recoil_degrees() -> Vector2:
	return _recoil


func _on_weapon_fired(weapon: Weapon) -> void:
	kick(
		weapon.recoil_vertical_degrees,
		weapon.recoil_horizontal_degrees,
		weapon.recoil_return_time
	)


## The pivot is the only place recoil is written, so mouse-look pitch on the
## parent holder keeps defining the true aim.
func _apply() -> void:
	rotation.x = deg_to_rad(_recoil.y)
	rotation.y = deg_to_rad(_recoil.x)
