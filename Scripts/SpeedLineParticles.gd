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

@onready var _player: PlayerMovement = get_node_or_null(player_path) as PlayerMovement

var _amount_ratio := 0.0


func _ready() -> void:
	local_coords = false
	_update_orientation()
	amount_ratio = 0.0


func _process(delta: float) -> void:
	_update_orientation()
	_update_amount(delta)


## Scales the active particle count with speed, using the same fade and speed
## mapping the shader effect used for its alpha.
func _update_amount(delta: float) -> void:
	if _player == null:
		return

	var speed := _player.velocity.length()
	var target_ratio := 0.0
	if max_speed > min_speed:
		target_ratio = clampf(inverse_lerp(min_speed, max_speed, speed), 0.0, 1.0)
	elif speed >= max_speed:
		target_ratio = 1.0

	target_ratio *= max_amount_ratio
	var fade := 1.0 - exp(-fade_speed * delta)
	_amount_ratio = lerpf(_amount_ratio, target_ratio, fade)
	amount_ratio = _amount_ratio


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
