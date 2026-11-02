extends Node3D

@export var frequency_scale: float = 2.0   # How fast bobbing speeds up with velocity
@export var amplitude_scale: float = 0.01  # How far bobbing extends with velocity
@export var max_amplitude: float = 0.15    # Maximum offset limit
@export var lerp_speed: float = 10.0       # Smoothness of stopping/starting transitions

var resting_pos: Vector3 = Vector3.ZERO
var bobbingPos: Vector3 = Vector3.ZERO
var resting_rot: Vector3 = Vector3.ZERO
var bobbingRot: Vector3 = Vector3.ZERO
var bob_time: float = 0.0

var groundState = WalkState.idle

enum WalkState {
	walking,
	midAir,
	sliding,
	idle
}

@export var player_path: NodePath = ^"../.."
@onready var _player = get_node_or_null(player_path)

func _ready() -> void:
	resting_pos = position
	resting_rot = rotation_degrees

func _physics_process(_delta: float) -> void:
	if _player == null:
		return

	var horizontal_velocity := Vector3(_player.velocity.x, 0.0, _player.velocity.z)
	
	if _player.is_on_floor():
		if _player.slide_pose > 0.0:
			groundState = WalkState.sliding
		elif horizontal_velocity.length() > 0.1:
			groundState = WalkState.walking
		else:
			groundState = WalkState.idle
	else:
		groundState = WalkState.midAir

func _process(delta: float) -> void:
	if _player == null:
		return

	var horizontal_speed := Vector3(_player.velocity.x, 0.0, _player.velocity.z).length()
	var target_bob := Vector3.ZERO
	var target_rot = Vector3.ZERO
	
	match groundState:
		WalkState.walking:
			if horizontal_speed > 0.1:
				# 1. Modulate SPEED: Advance bob_time proportionally to current horizontal velocity
				bob_time += delta * horizontal_speed * frequency_scale
				
				# 2. Modulate AMPLITUDE: Scale displacement height/width with current horizontal velocity
				var current_amplitude := minf(horizontal_speed * amplitude_scale, max_amplitude)
				
				# Calculate horizontal (X) sway and vertical (Y) step bounce
				target_bob.x = sin(bob_time) * current_amplitude
				target_bob.y = sin(bob_time * 2.0) * (current_amplitude * 0.5)
			else:
				bob_time = 0.0

		WalkState.sliding:
			bob_time = 0.0
			target_bob = Vector3(-0.05, -0.05, 0.0)
			target_rot = Vector3(-20.0,10.0,40.0)
			
		WalkState.midAir:
			bob_time = 0.0
			target_bob = Vector3(-0.05, -0.05, 0.0)
			target_rot = Vector3(-20.0,0.0,0.0)
		WalkState.idle, _:
			# Reset phase accumulator when not walking
			bob_time = 0.0

	# Smoothly transition bobbing position back to target position
	bobbingPos = bobbingPos.lerp(target_bob, delta * lerp_speed)
	bobbingRot = bobbingRot.lerp(target_rot, delta * lerp_speed)
	position = resting_pos + bobbingPos
	rotation_degrees = resting_rot + bobbingRot
