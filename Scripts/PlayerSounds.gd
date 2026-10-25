class_name PlayerSounds
extends Node

@export_group("Slide Audio")
## Speeds between which the slide sound rises in pitch and volume.
@export var slide_audio_slow_speed: float = 1.885
@export var slide_audio_fast_speed: float = 12.77
@export var slide_audio_min_pitch: float = 0.85
@export var slide_audio_max_pitch: float = 1.35
@export var slide_audio_quiet_db: float = -32.0
@export var slide_audio_loud_db: float = -18.0
## Fraction of full volume the sound fades in or out per second.
@export var slide_audio_fade_speed: float = 8.0

@export_group("Landing Audio")
## Extra pitch added to the landing sound when the landing starts a slide.
@export var landing_slide_pitch_bonus: float = 0.25
## Random pitch variation applied to every landing, in both directions.
@export var landing_pitch_variation: float = 0.3

@export var sound_source_path: NodePath = ^"../PlayerSoundSource"
@export var landing_sound_path: NodePath = ^"../LandingSoundSource"

@onready var _sound_source: AudioStreamPlayer3D = get_node_or_null(sound_source_path)
@onready var _landing_source: AudioStreamPlayer3D = get_node_or_null(landing_sound_path)

var _sound_fade := 0.0


## Plays the looping slide sound while sliding, fading it in and out with the
## slide and pitching and raising its volume with the horizontal speed.
func update_slide_audio(delta: float, sliding: bool, horizontal_speed: float) -> void:
	if _sound_source == null:
		return

	var fade_target := 1.0 if sliding else 0.0
	_sound_fade = move_toward(_sound_fade, fade_target, slide_audio_fade_speed * delta)

	var audible := _sound_fade > 0.001
	if audible and not _sound_source.playing:
		_sound_source.play()
	elif not audible and _sound_source.playing:
		_sound_source.stop()
		return
	if not audible:
		return

	var speed_weight := clampf(
		inverse_lerp(slide_audio_slow_speed, slide_audio_fast_speed, horizontal_speed),
		0.0,
		1.0
	)
	_sound_source.pitch_scale = lerpf(slide_audio_min_pitch, slide_audio_max_pitch, speed_weight)
	_sound_source.volume_db = (
		lerpf(slide_audio_quiet_db, slide_audio_loud_db, speed_weight)
		+ linear_to_db(_sound_fade)
	)


## Pitches the landing up when it begins a slide, plus a small random offset.
func play_landing(slide_landing: bool) -> void:
	if _landing_source == null:
		return
	var pitch := 1.0 + (landing_slide_pitch_bonus if slide_landing else 0.0)
	pitch += randf_range(-landing_pitch_variation, landing_pitch_variation)
	_landing_source.pitch_scale = maxf(pitch, 0.01)
	_landing_source.play()
