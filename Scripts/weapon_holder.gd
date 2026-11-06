extends Node3D

enum WalkState {
	walking,
	mid_air,
	sliding,
	landing,
	idle
}

@export_group("Bobbing")
## Radians of bob cycle per metre travelled on the ground.
@export var frequency_scale: float = 1.5
## Horizontal sway in metres per unit of horizontal speed.
@export var amplitude_scale: float = 0.01
## Upper limit of the horizontal sway in metres.
@export var max_amplitude: float = 0.15
## Vertical bounce as a share of the horizontal sway.
@export var vertical_amplitude_ratio: float = 0.5
## Roll degrees swaying side to side with the bob.
@export var roll_amplitude_degrees: float = 1.5
## How quickly the pose interpolates between states, in blend units per second.
@export var lerp_speed: float = 10.0
## Horizontal speed below which the viewmodel counts as standing still.
@export var idle_speed: float = 0.1

@export_group("Sway")
## Metres of viewmodel offset per degree per second of look speed.
@export var sway_position_scale: float = 0.0006
## Degrees of viewmodel rotation per degree per second of look speed.
@export var sway_rotation_scale: float = 0.004
## Upper limit of the sway offset in metres.
@export var sway_max_position: float = 0.2
## Upper limit of the sway rotation in degrees.
@export var sway_max_rotation_degrees: float = 2.5
## How quickly the sway follows the look direction and settles back to rest.
@export var sway_smoothing: float = 12.0

@export_group("State Poses")
## Horizontal speed above which a touchdown enters the landing state, and below
## which the landing state ends and bobbing resumes.
@export var landing_speed_threshold: float = 7.317
## Local offset held while recovering from a fast landing.
@export var landing_position_offset: Vector3 = Vector3.ZERO
## Local rotation in degrees held while recovering from a fast landing.
@export var landing_rotation_degrees: Vector3 = Vector3(30.0,0.0,0.0)
## Local offset applied while sliding.
@export var slide_position_offset: Vector3 = Vector3(-0.05, -0.05, 0.0)
## Local rotation in degrees applied while sliding, added to the resting pose.
@export var slide_rotation_degrees: Vector3 = Vector3(-20.0, 10.0, 40.0)
## Local offset applied while airborne.
@export var airborne_position_offset: Vector3 = Vector3(-0.05, -0.05, 0.0)
## Local rotation in degrees applied while airborne, added to the resting pose.
@export var airborne_rotation_degrees: Vector3 = Vector3(-20.0, 0.0, 0.0)

@export var player_path: NodePath = ^"../.."
@export var camera_holder_path: NodePath = ^"Camera holder"

@onready var _player: PlayerMovement = get_node_or_null(player_path) as PlayerMovement

var _resting_position := Vector3.ZERO
var _resting_rotation := Vector3.ZERO
var _bob_distance := 0.0
var _walk_blend := 0.0
var _state_position := Vector3.ZERO
var _state_rotation := Vector3.ZERO
var _walk_state := WalkState.idle
var _landing := false
var _was_on_floor := true
var _camera_holder: Node3D = null
var _last_yaw := 0.0
var _last_pitch := 0.0
var _sway_position := Vector3.ZERO
var _sway_rotation := Vector3.ZERO


func _ready() -> void:
	_resting_position = position
	_resting_rotation = rotation_degrees
	if _player != null:
		_camera_holder = _player.get_node_or_null(camera_holder_path) as Node3D
		_last_yaw = _player.rotation.y
		if _camera_holder != null:
			_last_pitch = _camera_holder.rotation.x


func _physics_process(_delta: float) -> void:
	if _player == null:
		return

	var horizontal_speed := _horizontal_speed()
	var on_floor := _player.is_on_floor()
	if on_floor and not _was_on_floor and horizontal_speed > landing_speed_threshold:
		_landing = true
	elif not on_floor or horizontal_speed <= landing_speed_threshold:
		_landing = false
	_was_on_floor = on_floor

	if not on_floor:
		_walk_state = WalkState.mid_air
	elif _landing:
		_walk_state = WalkState.landing
	elif _player.slide_pose > 0.0:
		_walk_state = WalkState.sliding
	elif horizontal_speed > idle_speed:
		_walk_state = WalkState.walking
	else:
		_walk_state = WalkState.idle


func _process(delta: float) -> void:
	if _player == null:
		return

	var horizontal_speed := _horizontal_speed()
	var target_position := Vector3.ZERO
	var target_rotation := Vector3.ZERO
	var target_walk_blend := 0.0

	match _walk_state:
		WalkState.walking:
			target_walk_blend = 1.0
			_bob_distance += horizontal_speed * delta
		WalkState.landing:
			target_position = landing_position_offset
			target_rotation = landing_rotation_degrees
		WalkState.sliding:
			target_position = slide_position_offset
			target_rotation = slide_rotation_degrees
		WalkState.mid_air:
			target_position = airborne_position_offset
			target_rotation = airborne_rotation_degrees
		WalkState.idle, _:
			pass

	var blend := 1.0 - exp(-lerp_speed * delta)
	_state_position = _state_position.lerp(target_position, blend)
	_state_rotation = _state_rotation.lerp(target_rotation, blend)
	_walk_blend = lerpf(_walk_blend, target_walk_blend, blend)

	var amplitude := minf(horizontal_speed * amplitude_scale, max_amplitude)
	var phase := _bob_distance * frequency_scale
	var bob_position := Vector3(
		sin(phase) * amplitude,
		sin(phase * 2.0) * amplitude * vertical_amplitude_ratio,
		0.0
	)
	var bob_rotation := Vector3(0.0, 0.0, sin(phase) * roll_amplitude_degrees)

	_update_sway(delta)
	_apply_pose(
		_state_position + bob_position * _walk_blend + _sway_position,
		_state_rotation + bob_rotation * _walk_blend + _sway_rotation
	)


## Turns the per-frame look rotation into a lagging viewmodel sway.
func _update_sway(delta: float) -> void:
	if delta <= 0.0:
		return

	var yaw := _player.rotation.y
	var pitch := 0.0
	if _camera_holder != null:
		pitch = _camera_holder.rotation.x
	var yaw_delta := wrapf(yaw - _last_yaw, -PI, PI)
	var pitch_delta := pitch - _last_pitch
	_last_yaw = yaw
	_last_pitch = pitch

	var yaw_speed := rad_to_deg(yaw_delta) / delta
	var pitch_speed := rad_to_deg(pitch_delta) / delta
	var target_position := Vector3.ZERO
	if sway_position_scale > 0.0:
		target_position = (
			Vector3(yaw_speed, -pitch_speed, 0.0)
			.limit_length(sway_max_position / sway_position_scale)
			* sway_position_scale
		)
	var target_rotation := Vector3.ZERO
	if sway_rotation_scale > 0.0:
		target_rotation = (
			Vector3(-pitch_speed, -yaw_speed, 0.0)
			.limit_length(sway_max_rotation_degrees / sway_rotation_scale)
			* sway_rotation_scale
		)

	var blend := 1.0 - exp(-sway_smoothing * delta)
	_sway_position = _sway_position.lerp(target_position, blend)
	_sway_rotation = _sway_rotation.lerp(target_rotation, blend)


## Writes the resting pose plus the current interpolated pose in one place.
func _apply_pose(offset: Vector3, rotation_offset: Vector3) -> void:
	position = _resting_position + offset
	rotation_degrees = _resting_rotation + rotation_offset


func _horizontal_speed() -> float:
	return Vector3(_player.velocity.x, 0.0, _player.velocity.z).length()
