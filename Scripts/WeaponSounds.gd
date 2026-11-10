class_name WeaponSounds
extends Node

@export_group("Fire")
## Stream played for every round that leaves the barrel.
@export var fire_stream: AudioStream
## Volume offset in decibels applied to the fire sound.
@export_range(-40.0, 12.0, 0.1) var fire_volume_db: float = 0.0
## Random pitch spread applied to each shot, in both directions.
@export_range(0.0, 0.5, 0.01) var fire_pitch_variation: float = 0.03

@export_group("Dry Fire")
## Stream played when the trigger is pulled with an empty clip.
@export var dry_fire_stream: AudioStream
## Volume offset in decibels applied to the dry fire sound.
@export_range(-40.0, 12.0, 0.1) var dry_fire_volume_db: float = 0.0
## Random pitch spread applied to each dry fire, in both directions.
@export_range(0.0, 0.5, 0.01) var dry_fire_pitch_variation: float = 0.03

var _fire_player: AudioStreamPlayer
var _dry_fire_player: AudioStreamPlayer


func _ready() -> void:
	_fire_player = _create_player("FireSound", fire_stream, fire_volume_db)
	_dry_fire_player = _create_player(
		"DryFireSound", dry_fire_stream, dry_fire_volume_db
	)


func play_fire() -> void:
	_play(_fire_player, fire_pitch_variation)


func play_dry_fire() -> void:
	_play(_dry_fire_player, dry_fire_pitch_variation)


func is_fire_playing() -> bool:
	return _fire_player != null and _fire_player.playing


func is_dry_fire_playing() -> bool:
	return _dry_fire_player != null and _dry_fire_player.playing


## Creates a non-positional player: the local viewmodel gun should sound the
## same no matter where the shared world places it.
func _create_player(
	player_name: String, stream: AudioStream, volume_db: float
) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = player_name
	player.stream = stream
	player.volume_db = volume_db
	add_child(player)
	return player


func _play(player: AudioStreamPlayer, pitch_variation: float) -> void:
	if player == null or player.stream == null:
		return
	if pitch_variation > 0.0:
		player.pitch_scale = 1.0 + randf_range(-pitch_variation, pitch_variation)
	else:
		player.pitch_scale = 1.0
	player.play()
