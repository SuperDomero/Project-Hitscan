extends GPUParticles3D

@export var player_path: NodePath = ^"../.."
## Velocity below this keeps the previous spawn orientation.
@export var min_velocity: float = 0.1

@export_group("Amount")
## Speed at which particles start being emitted.
@export var min_speed: float = 8.0
## Speed at which the full amount is emitted.
@export var max_speed: float = 16.0
## Highest fraction of the emitter's amount that can be active.
@export var max_amount_ratio: float = 1.0
## How quickly the amount follows the speed.
@export var fade_speed: float = 6.0

@export_group("Spawn Offset")
## Spawn distance ahead of the camera at full speed, in metres. Negative values
## push the spawn box further ahead.
@export var spawn_offset_at_max_speed: float = -3.5

@export var camera_holder_path: NodePath = ^"Camera holder"

@onready var _player: PlayerMovement = get_node_or_null(player_path) as PlayerMovement

var _camera_holder: Node3D = null
var _particle_material: ParticleProcessMaterial = null
var _base_spawn_offset := 0.0
var _speed_ratio := 0.0
var _amount_ratio := 0.0


func _ready() -> void:
	local_coords = false
	_particle_material = process_material as ParticleProcessMaterial
	if _particle_material != null:
		_base_spawn_offset = _particle_material.emission_shape_offset.z
	if _player != null:
		_camera_holder = _player.get_node_or_null(camera_holder_path) as Node3D
	_update_orientation()
	amount_ratio = 0.0


func _process(delta: float) -> void:
	_update_orientation()
	_update_speed(delta)


## Scales the active particle count and spawn offset with speed, using the same
## fade the shader effect used for its alpha.
func _update_speed(delta: float) -> void:
	if _player == null:
		return

	var speed := _player.velocity.length()
	var target_ratio := 0.0
	if max_speed > min_speed:
		target_ratio = clampf(inverse_lerp(min_speed, max_speed, speed), 0.0, 1.0)
	elif speed >= max_speed:
		target_ratio = 1.0

	var fade := 1.0 - exp(-fade_speed * delta)
	_speed_ratio = lerpf(_speed_ratio, target_ratio, fade)
	_amount_ratio = lerpf(_amount_ratio, target_ratio * max_amount_ratio, fade)
	amount_ratio = _amount_ratio

	if _particle_material != null:
		var distance := -lerpf(_base_spawn_offset, spawn_offset_at_max_speed, _speed_ratio)
		var target := global_position
		if _camera_holder != null:
			target = (
				_camera_holder.global_position
				+ _camera_holder.global_basis * Vector3(0.0, 0.0, -distance)
			)
		else:
			target -= global_basis.z * distance
		var local_offset := global_basis.inverse() * (target - global_position)
		_particle_material.emission_shape_offset = local_offset


## Reorients the emitter so newly spawned particles face the player's velocity.
## Already spawned particles keep the orientation they were spawned with.
func _update_orientation() -> void:
	if _player == null:
		return

	var velocity := _player.velocity
	if velocity.length() < min_velocity:
		return

	var direction := velocity.normalized()
	var up := Vector3.UP
	if absf(direction.dot(up)) > 0.99:
		up = Vector3.BACK
	global_basis = Basis.looking_at(direction, up)
