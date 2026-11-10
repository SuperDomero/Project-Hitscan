class_name WeaponHUD
extends Label

@export var weapon_manager_path: NodePath = ^"../../GunViewport/WeaponHolder/WeaponManager"

var _manager: WeaponManager


func _ready() -> void:
	_manager = get_node_or_null(weapon_manager_path) as WeaponManager
	if _manager == null:
		push_warning("%s could not find a WeaponManager." % name)
		return

	_manager.weapon_changed.connect(_on_weapon_changed)
	_manager.ammo_changed.connect(_on_ammo_changed)
	_manager.reload_started.connect(_on_reload_started)
	_manager.reload_finished.connect(_refresh)
	_refresh()


func _on_weapon_changed(_weapon: Weapon) -> void:
	_refresh()


func _on_ammo_changed(_current: int, _maximum: int) -> void:
	_refresh()


func _on_reload_started(_duration: float) -> void:
	_refresh()


func _refresh() -> void:
	var weapon := _manager.active_weapon
	if weapon == null:
		text = ""
	elif weapon.is_reloading:
		text = "RELOADING"
	elif weapon.ammo <= 0:
		text = "EMPTY"
	else:
		text = "%d / %d" % [weapon.ammo, weapon.clip_size]
