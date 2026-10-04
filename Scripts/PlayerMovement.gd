extends CharacterBody3D

const ACTION_FORWARD := &"w"
const ACTION_BACK := &"s"
const ACTION_LEFT := &"a"
const ACTION_RIGHT := &"d"
const ACTION_JUMP := &"space"
const ACTION_SPRINT := &"lShift"
const ACTION_SNEAK := &"lControl"

const TICKS_PER_SECOND: float = 20.0
const INPUT_LOG_INTERVAL: float = 5.0

@export_group("Speeds")
@export var walk_speed: float = 4.317
@export var sprint_speed: float = 5.612
@export var sneak_speed: float = 1.295

@export_group("Vertical")
@export var gravity: float = 32.0
@export var jump_height: float = 1.2522
@export var terminal_velocity: float = 78.4

@export_group("Acceleration")
@export var ground_acceleration: float = 40.0
@export var sprint_acceleration: float = 52.0
@export var air_acceleration: float = 8.0
@export var ground_friction_per_tick: float = 0.546

@onready var jump_velocity: float = sqrt(2.0 * gravity * jump_height)

var _move_input := Vector2.ZERO
var _wish_direction := Vector3.ZERO
var _target_speed := 0.0
var _sprinting := false
var _sneaking := false
var _input_log_accumulator := 0.0


func _physics_process(delta: float) -> void:
	_update_input()
	_apply_horizontal_movement(delta)
	_apply_vertical_movement(delta)
	move_and_slide()
	_log_inputs(delta)


func _update_input() -> void:
	_move_input = Vector2(
		Input.get_axis(ACTION_LEFT, ACTION_RIGHT),
		Input.get_axis(ACTION_BACK, ACTION_FORWARD)
	)
	var input := _move_input
	if input.length() > 1.0:
		input = input.normalized()

	_sneaking = Input.is_action_pressed(ACTION_SNEAK)
	_sprinting = Input.is_action_pressed(ACTION_SPRINT) and not _sneaking and input.y > 0.0

	var speed := walk_speed
	if _sprinting:
		speed = sprint_speed
	elif _sneaking:
		speed = sneak_speed

	_target_speed = speed * input.length()
	_wish_direction = global_basis * Vector3(input.x, 0.0, -input.y)
	_wish_direction.y = 0.0
	if not _wish_direction.is_zero_approx():
		_wish_direction = _wish_direction.normalized()


func _apply_horizontal_movement(delta: float) -> void:
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)

	if _wish_direction.is_zero_approx():
		if is_on_floor():
			horizontal *= pow(ground_friction_per_tick, delta * TICKS_PER_SECOND)
	else:
		var acceleration := air_acceleration
		if is_on_floor():
			acceleration = sprint_acceleration if _sprinting else ground_acceleration
		horizontal = horizontal.move_toward(_wish_direction * _target_speed, acceleration * delta)

	velocity.x = horizontal.x
	velocity.z = horizontal.z


func _apply_vertical_movement(delta: float) -> void:
	if is_on_floor():
		velocity.y = 0.0
		if Input.is_action_just_pressed(ACTION_JUMP):
			velocity.y = jump_velocity
	else:
		velocity.y = maxf(velocity.y - gravity * delta, -terminal_velocity)


func _log_inputs(delta: float) -> void:
	_input_log_accumulator += delta
	if _input_log_accumulator < INPUT_LOG_INTERVAL:
		return
	_input_log_accumulator = 0.0
	print(
		"input=", _move_input,
		" sprint=", _sprinting,
		" sneak=", _sneaking,
		" jump=", Input.is_action_pressed(ACTION_JUMP),
		" | wish=", _wish_direction,
		" target_speed=", _target_speed,
		" velocity=", velocity,
		" on_floor=", is_on_floor()
	)
