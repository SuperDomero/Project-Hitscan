extends CharacterBody3D

const ACTION_FORWARD := &"w"
const ACTION_BACK := &"s"
const ACTION_LEFT := &"a"
const ACTION_RIGHT := &"d"
const ACTION_JUMP := &"space"
const ACTION_SLIDE := &"lShift"
const ACTION_SNEAK := &"lControl"

const TICKS_PER_SECOND: float = 20.0
const INPUT_LOG_INTERVAL: float = 5.0

@export_group("Speeds")
@export var walk_speed: float = 7.317
@export var sneak_speed: float = 3.295

@export_group("Vertical")
@export var gravity: float = 32.0
@export var jump_height: float = 1.2522
@export var terminal_velocity: float = 78.4

@export_group("Acceleration")
@export var ground_acceleration: float = 40.0
@export var air_acceleration: float = 8.0
@export var ground_friction_per_tick: float = 0.546

@export_group("Slide")
## Minimum horizontal speed needed to enter a slide.
@export var slide_entry_speed: float = 3.885
## Instant speed gain on the first frame of a slide.
@export var slide_boost_speed: float = 12.914
@export var slide_max_speed: float = 18.77
@export var slide_duration: float = 1.0
@export var slide_friction_per_tick: float = 0.96
## Degrees per second the slide may bend towards the look direction.
@export var slide_steer_speed: float = 90.0
## Time before the next slide is allowed to grant its speed boost again.
@export var slide_boost_cooldown: float = 2.0
## Seconds a slide press is remembered, so pressing in mid air slides on landing.
@export var slide_land_buffer: float = 0.5

@export_group("Slide Pose")
## Height of the collision pill while sliding, also used to sink the body.
@export var slide_capsule_height: float = 1.3
@export var slide_pose_speed: float = 4.0

@export_group("Slide Camera")
## Share of the body sink the camera follows, 1.0 drops with the full pose.
@export var slide_camera_drop_ratio: float = 1.0
## Field of view degrees lost at full slide depth.
@export var slide_camera_fov_shrink: float = 12.0
## Roll degrees at full slide steering, leaning into the turn.
@export var slide_camera_roll_degrees: float = 4.0
## Slide speeds between which the lean grows, none below and full above.
@export var slide_camera_roll_slow_speed: float = 4.0
@export var slide_camera_roll_fast_speed: float = 14.0
## Roll degrees per second the camera catches up with the steering.
@export var slide_camera_roll_speed: float = 90.0

@export var collision_shape_path: NodePath = ^"CollisionShape3D"
@export var model_path: NodePath = ^"Player model"
@export var camera_path: NodePath = ^"Camera holder"

@onready var jump_velocity: float = sqrt(2.0 * gravity * jump_height)
@onready var _collision_shape: CollisionShape3D = get_node(collision_shape_path)
@onready var _model: Node3D = get_node(model_path)
@onready var _camera_holder: Node3D = get_node(camera_path)
@onready var _camera: Camera3D = _camera_holder.find_child("Camera3D", true, false) as Camera3D

var _move_input := Vector2.ZERO
var _wish_direction := Vector3.ZERO
var _target_speed := 0.0
var _sneaking := false
var _sliding := false
var _slide_time_left := 0.0
var _slide_cooldown := 0.0
var _slide_buffer := 0.0
var _slide_pose := 0.0
var _slide_steer := 0.0
var _slide_roll := 0.0
var _capsule := CapsuleShape3D.new()
var _standing_height := 0.0
var _crouch_height := 0.0
var _model_stand_y := 0.0
var _camera_stand_y := 0.0
var _input_log_accumulator := 0.0


func _ready() -> void:
	_capsule = _collision_shape.shape.duplicate() as CapsuleShape3D
	_collision_shape.shape = _capsule
	_standing_height = _capsule.height
	_crouch_height = minf(slide_capsule_height, _standing_height)
	_model_stand_y = _model.position.y
	_camera_stand_y = _camera_holder.position.y


func _physics_process(delta: float) -> void:
	_update_input()
	_update_slide(delta)
	_apply_horizontal_movement(delta)
	_apply_vertical_movement(delta)
	_update_slide_pose(delta)
	_update_slide_camera(delta)
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

	var speed := walk_speed
	if _sneaking and not _sliding:
		speed = sneak_speed

	_target_speed = speed * input.length()
	_wish_direction = global_basis * Vector3(input.x, 0.0, -input.y)
	_wish_direction.y = 0.0
	if not _wish_direction.is_zero_approx():
		_wish_direction = _wish_direction.normalized()


func _update_slide(delta: float) -> void:
	_slide_cooldown = maxf(_slide_cooldown - delta, 0.0)
	_slide_buffer = maxf(_slide_buffer - delta, 0.0)

	if _sliding:
		_slide_time_left -= delta
		if _slide_time_left <= 0.0 or not is_on_floor():
			_sliding = false
		return

	if Input.is_action_just_pressed(ACTION_SLIDE):
		_slide_buffer = slide_land_buffer

	var can_enter := is_on_floor() and not _sneaking and _horizontal_speed() >= slide_entry_speed
	if _slide_buffer <= 0.0 or not can_enter:
		return

	_start_slide()


func _start_slide() -> void:
	_sliding = true
	_slide_buffer = 0.0
	_slide_time_left = slide_duration
	if _slide_cooldown > 0.0:
		return
	_slide_cooldown = slide_boost_cooldown

	var horizontal := _horizontal_velocity()
	var boosted := horizontal + horizontal.normalized() * slide_boost_speed
	_set_horizontal_velocity(boosted.limit_length(slide_max_speed))


func _apply_horizontal_movement(delta: float) -> void:
	var horizontal := _horizontal_velocity()

	if _sliding:
		horizontal = _steer_slide(horizontal, delta)
		horizontal *= pow(slide_friction_per_tick, delta * TICKS_PER_SECOND)
	elif _wish_direction.is_zero_approx():
		if is_on_floor():
			horizontal *= pow(ground_friction_per_tick, delta * TICKS_PER_SECOND)
	else:
		var acceleration := air_acceleration
		if is_on_floor():
			acceleration = ground_acceleration
		horizontal = horizontal.move_toward(_wish_direction * _target_speed, acceleration * delta)

	_set_horizontal_velocity(horizontal)


## Bends the slide towards the look direction, at a limited turn rate, and
## records how hard it is turning for the camera roll.
func _steer_slide(horizontal: Vector3, delta: float) -> Vector3:
	var turn := 0.0
	var heading := horizontal.normalized()
	var look := -global_basis.z
	look.y = 0.0
	look = look.normalized()
	if not heading.is_zero_approx() and not look.is_zero_approx():
		var angle := heading.angle_to(look)
		if heading.cross(look).y < 0.0:
			angle = -angle
		var max_turn := deg_to_rad(slide_steer_speed) * delta
		turn = clampf(angle, -max_turn, max_turn)
		horizontal = heading.rotated(Vector3.UP, turn) * horizontal.length()

	var steer := 0.0
	if slide_steer_speed > 0.0:
		steer = -rad_to_deg(turn) / (slide_steer_speed * delta)
	_slide_steer = clampf(steer, -1.0, 1.0)
	return horizontal


func _apply_vertical_movement(delta: float) -> void:
	if is_on_floor():
		velocity.y = 0.0
		if Input.is_action_just_pressed(ACTION_JUMP):
			_sliding = false
			velocity.y = jump_velocity
	else:
		velocity.y = maxf(velocity.y - gravity * delta, -terminal_velocity)


## Sinks the body into the slide pose and back out, keeping the feet planted.
func _update_slide_pose(delta: float) -> void:
	var target_pose := 1.0 if _sliding else 0.0
	var pose := move_toward(_slide_pose, target_pose, slide_pose_speed * delta)
	if pose < _slide_pose and not _has_room_to_stand():
		return
	_slide_pose = pose
	_set_pose_geometry(pose)


func _set_pose_geometry(pose: float) -> void:
	_capsule.height = lerpf(_standing_height, _crouch_height, pose)
	var sink := (_standing_height - _capsule.height) * -0.5
	_collision_shape.position.y = sink
	_model.position.y = _model_stand_y + sink
	_camera_holder.position.y = _camera_stand_y + sink * slide_camera_drop_ratio


## Narrows the field of view while sliding and banks the camera into the turn.
func _update_slide_camera(delta: float) -> void:
	if _camera != null:
		_camera.fov = GlobalSettings.field_of_view - slide_camera_fov_shrink * _slide_pose

	var speed_weight := clampf(
		inverse_lerp(
			slide_camera_roll_slow_speed, slide_camera_roll_fast_speed, _horizontal_speed()
		),
		0.0,
		1.0
	)
	var roll_target := slide_camera_roll_degrees * _slide_pose * _slide_steer * speed_weight
	_slide_roll = move_toward(_slide_roll, roll_target, slide_camera_roll_speed * delta)
	_camera_holder.rotation.z = deg_to_rad(-_slide_roll)


## Standing up stays blocked while the standing shape does not fit in the
## space the crouched shape currently occupies.
func _has_room_to_stand() -> bool:
	_set_pose_geometry(0.0)
	var has_room := not test_move(global_transform, Vector3.ZERO)
	_set_pose_geometry(_slide_pose)
	return has_room


func _horizontal_velocity() -> Vector3:
	return Vector3(velocity.x, 0.0, velocity.z)


func _set_horizontal_velocity(horizontal: Vector3) -> void:
	velocity.x = horizontal.x
	velocity.z = horizontal.z


func _horizontal_speed() -> float:
	return _horizontal_velocity().length()


func _log_inputs(delta: float) -> void:
	_input_log_accumulator += delta
	if _input_log_accumulator < INPUT_LOG_INTERVAL:
		return
	_input_log_accumulator = 0.0
	print(
		"input=", _move_input,
		" slide=", _sliding,
		" sneak=", _sneaking,
		" jump=", Input.is_action_pressed(ACTION_JUMP),
		" | wish=", _wish_direction,
		" target_speed=", _target_speed,
		" velocity=", velocity,
		" on_floor=", is_on_floor(),
		" slide_time=", _slide_time_left,
		" slide_buffer=", snappedf(_slide_buffer, 0.01),
		" boost_ready=", _slide_cooldown <= 0.0,
		" pose=", _slide_pose
	)
