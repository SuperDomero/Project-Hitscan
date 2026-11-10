class_name MuzzleFlash
extends Node3D

@onready var _particles: GPUParticles3D = find_child(
	"GPUParticles3D", true, false
) as GPUParticles3D


func _ready() -> void:
	if _particles == null:
		return
	_particles.one_shot = true
	_particles.local_coords = true
	_particles.emitting = false


func play() -> void:
	if _particles == null:
		return
	_particles.restart()
	_particles.emitting = true


func stop() -> void:
	if _particles != null:
		_particles.emitting = false


func is_playing() -> bool:
	return _particles != null and _particles.emitting
