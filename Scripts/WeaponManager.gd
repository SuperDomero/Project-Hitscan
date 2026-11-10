class_name WeaponManager
extends Node

signal weapon_changed(weapon: Weapon)
signal ammo_changed(current: int, maximum: int)
signal reload_started(duration: float)
signal reload_finished
signal fired(weapon: Weapon)
signal dry_fired(weapon: Weapon)

enum State {
	READY,
	SWITCHING
}

const ACTION_FIRE := &"fire"
const ACTION_NEXT := &"weapon_next"
const ACTION_PREV := &"weapon_prev"
const WEAPON_SLOT_ACTIONS: Array[StringName] = [&"weapon_1", &"weapon_2"]

@export var weapon_scenes: Array[PackedScene] = []
@export var weapon_holder_path: NodePath = ^".."
@export var start_weapon_index: int = 0

var state := State.READY

var active_weapon: Weapon:
	get:
		if _current_index < 0 or _current_index >= _weapons.size():
			return null
		return _weapons[_current_index]

@onready var _holder: WeaponHolder = get_node_or_null(
	weapon_holder_path
) as WeaponHolder

var _weapons: Array[Weapon] = []
var _current_index := -1


func _ready() -> void:
	process_priority = 1
	_setup_weapons.call_deferred()


func _setup_weapons() -> void:
	_instantiate_weapons()
	if _weapons.is_empty():
		push_warning("%s has no weapons configured." % name)
		return
	_equip_weapon(clampi(start_weapon_index, 0, _weapons.size() - 1), true)


func _process(_delta: float) -> void:
	if not GlobalSettings.pointer_locked:
		return

	_update_switch_state()
	if Input.is_action_just_pressed(ACTION_FIRE):
		try_fire()
	_update_switch_input()


## Requests a shot from the active weapon. Returns true when a round was fired.
func try_fire() -> bool:
	if state != State.READY:
		return false
	if _holder != null and not _holder.is_fire_allowed():
		return false
	var weapon := active_weapon
	return weapon != null and weapon.try_fire()


func switch_to(index: int) -> bool:
	if state != State.READY:
		return false
	return _equip_weapon(index)


func switch_next() -> bool:
	return switch_to(_wrapped_index(1))


func switch_prev() -> bool:
	return switch_to(_wrapped_index(-1))


func _instantiate_weapons() -> void:
	var parent: Node = _holder
	if parent == null:
		parent = self

	for scene in weapon_scenes:
		if scene == null:
			continue
		var instance := scene.instantiate()
		var weapon := instance as Weapon
		if weapon == null:
			push_warning("%s is not a Weapon scene." % scene.resource_path)
			instance.queue_free()
			continue
		parent.add_child(weapon)
		weapon.hide()
		_register_weapon(weapon)
		_weapons.append(weapon)


func _register_weapon(weapon: Weapon) -> void:
	weapon.fired.connect(_on_weapon_fired)
	weapon.dry_fired.connect(_on_weapon_dry_fired)
	weapon.ammo_changed.connect(_on_weapon_ammo_changed.bind(weapon))
	weapon.reload_started.connect(_on_weapon_reload_started.bind(weapon))
	weapon.reload_finished.connect(_on_weapon_reload_finished.bind(weapon))


func _equip_weapon(index: int, force := false) -> bool:
	if _weapons.is_empty() or index < 0 or index >= _weapons.size():
		return false
	if not force and index == _current_index:
		return false
	if not force and state != State.READY:
		return false

	var previous := active_weapon
	_current_index = index
	if previous != null:
		previous.holster()
		previous.hide()

	var weapon := active_weapon
	weapon.show()
	weapon.equip()
	if _holder != null:
		_holder.play_equip()

	state = State.SWITCHING
	weapon_changed.emit(weapon)
	ammo_changed.emit(weapon.ammo, weapon.clip_size)
	return true


func _update_switch_state() -> void:
	if state != State.SWITCHING:
		return
	if _holder == null or _holder.is_equip_fire_ready():
		state = State.READY


func _update_switch_input() -> void:
	for index in WEAPON_SLOT_ACTIONS.size():
		if Input.is_action_just_pressed(WEAPON_SLOT_ACTIONS[index]):
			switch_to(index)
			return
	if Input.is_action_just_pressed(ACTION_NEXT):
		switch_next()
	elif Input.is_action_just_pressed(ACTION_PREV):
		switch_prev()


func _wrapped_index(step: int) -> int:
	if _weapons.is_empty():
		return -1
	return posmod(_current_index + step, _weapons.size())


func _on_weapon_fired(weapon: Weapon) -> void:
	if weapon == active_weapon:
		fired.emit(weapon)


func _on_weapon_dry_fired(weapon: Weapon) -> void:
	if weapon == active_weapon:
		dry_fired.emit(weapon)


func _on_weapon_ammo_changed(current: int, maximum: int, weapon: Weapon) -> void:
	if weapon == active_weapon:
		ammo_changed.emit(current, maximum)


func _on_weapon_reload_started(duration: float, weapon: Weapon) -> void:
	if weapon == active_weapon:
		reload_started.emit(duration)


func _on_weapon_reload_finished(weapon: Weapon) -> void:
	if weapon == active_weapon:
		reload_finished.emit()
