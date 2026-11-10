class_name Weapon
extends Node3D

signal fired(weapon: Weapon)
signal dry_fired(weapon: Weapon)
signal ammo_changed(current: int, maximum: int)
signal reload_started(duration: float)
signal reload_finished

const RESET_ANIMATION: StringName = &"RESET"

@export_group("Ammo")
@export var clip_size: int = 8

@export_group("Fire")
## Rounds per minute the weapon can cycle. Animation length can only slow this down.
@export var fire_rate_rpm: float = 180.0
@export var fire_animation: StringName = &"Shoot"
## Playback speed multiplier for the Shoot animation.
@export var animation_speed: float = 1.0
## Seconds this weapon takes to reload when holstered empty.
@export var reload_time: float = 1.0

@export_group("Recoil")
## Maximum upward camera kick per shot, in degrees.
@export var recoil_vertical_degrees: float = 1.6
## Maximum sideways camera kick per shot, in degrees.
@export var recoil_horizontal_degrees: float = 0.5
## Seconds the camera takes to lerp from the kick back to the centre.
@export var recoil_return_time: float = 0.12

@export_group("Presentation")
@export var muzzle_flash_path: NodePath = ^"Muzzle/MuzzleFlash"
@export var sounds_path: NodePath = ^"WeaponSounds"

@onready var _animation_player: AnimationPlayer = find_child(
	"AnimationPlayer", true, false
) as AnimationPlayer
@onready var _muzzle_flash: MuzzleFlash = get_node_or_null(
	muzzle_flash_path
) as MuzzleFlash
@onready var _sounds: WeaponSounds = get_node_or_null(
	sounds_path
) as WeaponSounds

var ammo: int = 0
var is_reloading := false
var reload_elapsed := 0.0
var shot_animation_done := true
var is_active := false

var _time_since_last_shot := INF


func _ready() -> void:
	ammo = clip_size
	_time_since_last_shot = _seconds_per_shot()
	if _animation_player == null:
		push_warning("%s has no AnimationPlayer and cannot fire." % name)
	elif not _animation_player.has_animation(fire_animation):
		push_warning(
			"%s has no '%s' animation and cannot fire." % [name, fire_animation]
		)
	else:
		_animation_player.animation_finished.connect(_on_animation_finished)


func _process(delta: float) -> void:
	_time_since_last_shot += delta
	if not is_reloading:
		return

	reload_elapsed += delta
	if reload_elapsed >= reload_time:
		_finish_reload()


## Fires one round when the rate gate, animation gate and ammo state all allow it.
func try_fire() -> bool:
	if not can_fire():
		if ammo <= 0 and not is_reloading:
			if _sounds != null:
				_sounds.play_dry_fire()
			dry_fired.emit(self)
		return false

	ammo -= 1
	_time_since_last_shot = 0.0
	shot_animation_done = false
	_play_fire_animation()
	if _muzzle_flash != null:
		_muzzle_flash.play()
	if _sounds != null:
		_sounds.play_fire()

	fired.emit(self)
	ammo_changed.emit(ammo, clip_size)
	return true


func can_fire() -> bool:
	return (
		is_active
		and not is_reloading
		and ammo > 0
		and shot_animation_done
		and _time_since_last_shot >= _seconds_per_shot()
		and _has_fire_animation()
	)


func start_reload() -> bool:
	if is_reloading or ammo > 0:
		return false

	is_reloading = true
	reload_elapsed = 0.0
	reload_started.emit(reload_time)
	if reload_time <= 0.0:
		_finish_reload()
	return true


func refill() -> void:
	is_reloading = false
	reload_elapsed = 0.0
	ammo = clip_size
	ammo_changed.emit(ammo, clip_size)


func set_active(active: bool) -> void:
	is_active = active


func equip() -> void:
	is_active = true
	shot_animation_done = true
	reset_pose()


func holster() -> void:
	is_active = false
	stop_flash()
	reset_pose()
	if ammo <= 0:
		start_reload()


## Restores the imported bind pose so bones do not stay frozen mid-shot.
func reset_pose() -> void:
	shot_animation_done = true
	if _animation_player == null:
		return
	_animation_player.speed_scale = 1.0
	if _animation_player.has_animation(RESET_ANIMATION):
		_animation_player.play(RESET_ANIMATION)
	else:
		_animation_player.stop()


func stop_flash() -> void:
	if _muzzle_flash != null:
		_muzzle_flash.stop()


func _finish_reload() -> void:
	is_reloading = false
	reload_elapsed = reload_time
	ammo = clip_size
	ammo_changed.emit(ammo, clip_size)
	reload_finished.emit()


func _on_animation_finished(animation_name: StringName) -> void:
	if animation_name == fire_animation and is_active:
		shot_animation_done = true


func _play_fire_animation() -> void:
	_animation_player.speed_scale = maxf(animation_speed, 0.01)
	_animation_player.play(fire_animation)


func _seconds_per_shot() -> float:
	if fire_rate_rpm <= 0.0:
		return INF
	return 60.0 / fire_rate_rpm


func _has_fire_animation() -> bool:
	return _animation_player != null and _animation_player.has_animation(fire_animation)
