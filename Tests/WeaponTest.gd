extends SceneTree

const PLAYER_SCENE := preload("res://Scenes/player.tscn")
const PISTOL_SCENE := preload("res://Scenes/pistol.tscn")
const PLAYER_MOVEMENT := preload("res://Scripts/PlayerMovement.gd")

var _checks := 0
var _failures := 0
var _fired_count := 0
var _dry_fired_count := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await _test_scene_wiring()
	await _test_single_shot()
	await _test_weapon_audio()
	await _test_camera_recoil()
	await _test_fire_blocked_while_sliding_or_landing()
	await _test_fire_rate_gate()
	await _test_animation_gate()
	await _test_actual_animation_finishes()
	await _test_animation_speed()
	await _test_empty_clip()
	await _test_last_round()
	await _test_reload_on_holster()
	await _test_reload_timers_are_independent()
	await _test_reloading_blocks_fire_and_shows_empty_pose()
	await _test_partial_clip_does_not_reload()
	await _test_instant_reload()
	await _test_switch_during_shot()
	await _test_equip_blocks_fire()
	await _test_semi_auto_input()

	await process_frame
	print("")
	print("Weapon tests: %d checks, %d failures." % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_scene_wiring() -> void:
	var fixture := await _new_fixture()
	var weapon := fixture.manager.active_weapon as Weapon
	_check(weapon != null, "pistol is registered as the active weapon")
	_check(
		InputMap.has_action("fire")
		and InputMap.has_action("weapon_1")
		and InputMap.has_action("weapon_2")
		and InputMap.has_action("weapon_next")
		and InputMap.has_action("weapon_prev"),
		"fire and weapon-switch actions exist"
	)

	var animation_player := weapon.find_child(
		"AnimationPlayer", true, false
	) as AnimationPlayer
	_check(animation_player.has_animation(&"Shoot"), "pistol has a Shoot animation")
	_check(animation_player.has_animation(&"RESET"), "pistol has a RESET pose")

	var muzzle := weapon.get_node_or_null("Muzzle") as Marker3D
	_check(muzzle != null, "pistol has a Muzzle marker")
	if muzzle != null:
		_check(muzzle.position.z < 0.0, "muzzle marker sits at the barrel tip")

	var flash := weapon.get_node_or_null("Muzzle/MuzzleFlash") as MuzzleFlash
	_check(flash != null, "muzzle flash is parented to the Muzzle marker")
	var particles := weapon.get_node_or_null(
		"Muzzle/MuzzleFlash/GPUParticles3D"
	) as GPUParticles3D
	_check(particles != null, "muzzle flash has particles")
	var gun_mesh := weapon.find_child("Object_2", true, false) as VisualInstance3D
	_check(gun_mesh != null, "pistol mesh is present")
	if particles != null:
		_check(particles.one_shot, "muzzle flash particles are one-shot")
		_check(particles.local_coords, "muzzle flash follows the weapon")
		_check(particles.lifetime <= 0.2, "muzzle flash is short-lived")
		_check(not particles.emitting, "muzzle flash rests silent")
		if gun_mesh != null:
			_check(
				particles.layers == gun_mesh.layers,
				"muzzle flash uses the same render layer as the viewmodel"
			)

	var world_camera := fixture.player.get_node(
		"Camera holder"
	).find_child("Camera3D", true, false) as Camera3D
	var gun_camera := fixture.player.get_node("GunViewport/Camera3D") as Camera3D
	if gun_mesh != null:
		_check(
			(gun_mesh.layers & world_camera.cull_mask) == 0,
			"viewmodel is hidden from the world camera"
		)
		_check(
			(gun_mesh.layers & gun_camera.cull_mask) != 0,
			"viewmodel is visible to the gun camera"
		)

	var hud := fixture.player.get_node_or_null("HUD/Ammo") as WeaponHUD
	_check(hud != null, "HUD ammo label is wired")
	if hud != null:
		_check(
			hud.text == "%d / %d" % [weapon.ammo, weapon.clip_size],
			"HUD shows the active clip"
		)

	var sounds := weapon.get_node_or_null("WeaponSounds") as WeaponSounds
	_check(sounds != null, "pistol has a WeaponSounds component")
	if sounds != null:
		_check(
			sounds.fire_stream != null
				and sounds.fire_stream.resource_path
				== "res://Sounds/pistol_fire.mp3",
			"pistol fire sound uses pistol_fire"
		)
		_check(
			sounds.dry_fire_stream != null
				and sounds.dry_fire_stream.resource_path
				== "res://Sounds/dry_fire.mp3",
			"pistol dry fire sound uses dry_fire"
		)
		_check(not sounds.is_fire_playing(), "the fire sound rests silent")
		_check(not sounds.is_dry_fire_playing(), "the dry fire sound rests silent")

	_free_fixture(fixture)


func _test_weapon_audio() -> void:
	var fixture := await _new_fixture()
	var weapon := fixture.manager.active_weapon as Weapon
	_prepare_weapon(weapon)
	var sounds := weapon.get_node("WeaponSounds") as WeaponSounds

	_check(weapon.try_fire(), "a ready weapon fires for audio")
	_check(sounds.is_fire_playing(), "firing plays the fire sound")
	_check(not sounds.is_dry_fire_playing(), "firing does not play the dry fire sound")
	_free_fixture(fixture)

	var dry_fixture := await _new_fixture()
	var dry_weapon := dry_fixture.manager.active_weapon as Weapon
	_prepare_weapon(dry_weapon, 0)
	var dry_sounds := dry_weapon.get_node("WeaponSounds") as WeaponSounds

	_check(not dry_weapon.try_fire(), "an empty weapon does not fire")
	_check(dry_sounds.is_dry_fire_playing(), "an empty trigger pull plays the dry fire sound")
	_check(not dry_sounds.is_fire_playing(), "an empty trigger pull does not play the fire sound")
	_free_fixture(dry_fixture)


func _test_camera_recoil() -> void:
	var fixture := await _new_fixture()
	var weapon := fixture.manager.active_weapon as Weapon
	var recoil := fixture.player.get_node(
		"Camera holder/RecoilPivot"
	) as CameraRecoil
	_check(recoil != null, "the camera has a recoil pivot")
	if recoil == null:
		_free_fixture(fixture)
		return

	weapon.recoil_vertical_degrees = 2.0
	weapon.recoil_horizontal_degrees = 1.0
	weapon.recoil_return_time = 0.2
	_prepare_weapon(weapon)

	var holder := fixture.player.get_node("Camera holder") as Node3D
	var yaw_before: float = fixture.player.rotation.y
	var pitch_before: float = holder.rotation.x

	_check(recoil.get_recoil_degrees().is_zero_approx(), "the camera starts centred")
	_check(weapon.try_fire(), "firing for recoil succeeds")

	var kick := recoil.get_recoil_degrees()
	_check(
		kick.y > 0.0 and kick.y <= 2.0,
		"fire kicks the camera up within the vertical range"
	)
	_check(
		kick.x >= -1.0 and kick.x <= 1.0,
		"the sideways kick stays within the horizontal range"
	)
	_check(not recoil.rotation.is_zero_approx(), "the recoil pivot visibly rotates")
	_check(
		is_equal_approx(fixture.player.rotation.y, yaw_before)
		and is_equal_approx(holder.rotation.x, pitch_before),
		"recoil does not move the player's aim"
	)

	recoil._process(0.1)
	_check(
		recoil.get_recoil_degrees().y < kick.y,
		"the kick lerps back toward the centre"
	)
	recoil._process(0.1)
	_check(
		recoil.get_recoil_degrees().is_zero_approx(),
		"the kick reaches the centre after the return time"
	)
	_check(recoil.rotation.is_zero_approx(), "the pivot rotation resets")

	_free_fixture(fixture)


func _test_fire_blocked_while_sliding_or_landing() -> void:
	var fixture := await _new_fixture()
	var weapon := fixture.manager.active_weapon as Weapon
	var holder := fixture.holder as WeaponHolder
	_prepare_weapon(weapon)
	_reset_signal_counters(weapon)

	var starting_ammo: int = weapon.ammo
	holder._walk_state = WeaponHolder.WalkState.sliding
	_check(not fixture.manager.try_fire(), "fire is blocked while sliding")
	_check(weapon.ammo == starting_ammo, "a blocked slide shot keeps the clip")
	_check(_fired_count == 0, "a blocked slide shot emits no fired signal")

	holder._walk_state = WeaponHolder.WalkState.landing
	_check(not fixture.manager.try_fire(), "fire is blocked while landing")
	_check(weapon.ammo == starting_ammo, "a blocked landing shot keeps the clip")
	_check(_fired_count == 0, "a blocked landing shot emits no fired signal")

	holder._walk_state = WeaponHolder.WalkState.idle
	_check(fixture.manager.try_fire(), "fire works again once the slide and landing end")
	_check(weapon.ammo == starting_ammo - 1, "the allowed shot consumes a round")

	_free_fixture(fixture)


func _test_single_shot() -> void:
	var fixture := await _new_fixture()
	var weapon := fixture.manager.active_weapon as Weapon
	_prepare_weapon(weapon)
	_reset_signal_counters(weapon)
	var starting_ammo: int = weapon.ammo
	var flash := weapon.get_node("Muzzle/MuzzleFlash") as MuzzleFlash

	_check(weapon.try_fire(), "a ready weapon fires")
	_check(weapon.ammo == starting_ammo - 1, "firing consumes one round")
	_check(_fired_count == 1, "firing emits fired once")
	_check(not weapon.shot_animation_done, "firing starts the animation gate")
	_check(flash.is_playing(), "firing plays the muzzle flash")
	_check(not weapon.try_fire(), "the animation gate rejects an immediate second shot")

	var hud := fixture.player.get_node("HUD/Ammo") as WeaponHUD
	_check(
		hud.text == "%d / %d" % [weapon.ammo, weapon.clip_size],
		"HUD updates after a shot"
	)

	_free_fixture(fixture)


func _test_fire_rate_gate() -> void:
	var fixture := await _new_fixture()
	var weapon := fixture.manager.active_weapon as Weapon
	_prepare_weapon(weapon)
	weapon.fire_rate_rpm = 120.0
	_check(weapon.try_fire(), "weapon fires at the start of the cadence")
	weapon.shot_animation_done = true

	weapon._process(0.2)
	_check(not weapon.try_fire(), "fire rate rejects a shot before the interval")

	weapon._process(0.31)
	_check(weapon.try_fire(), "fire rate allows a shot after the interval")

	_free_fixture(fixture)


func _test_animation_gate() -> void:
	var fixture := await _new_fixture()
	var weapon := fixture.manager.active_weapon as Weapon
	_prepare_weapon(weapon)
	weapon.fire_rate_rpm = 600.0
	weapon._time_since_last_shot = 999.0
	weapon.shot_animation_done = false
	_check(not weapon.try_fire(), "animation gate blocks fire while Shoot is running")

	weapon.shot_animation_done = true
	_check(weapon.try_fire(), "animation gate allows fire once Shoot finishes")

	_free_fixture(fixture)


func _test_actual_animation_finishes() -> void:
	var fixture := await _new_fixture()
	var weapon := fixture.manager.active_weapon as Weapon
	_prepare_weapon(weapon)
	_check(weapon.try_fire(), "weapon fires before waiting on the clip")

	await create_timer(0.45).timeout
	_check(weapon.shot_animation_done, "Shoot animation_finished reopens the gate")

	weapon.reset_pose()
	var animation_player := weapon.find_child(
		"AnimationPlayer", true, false
	) as AnimationPlayer
	_check(
		animation_player.current_animation == &"RESET",
		"reset_pose plays the imported RESET animation"
	)

	_free_fixture(fixture)


func _test_animation_speed() -> void:
	var fixture := await _new_fixture()
	var weapon := fixture.manager.active_weapon as Weapon
	_prepare_weapon(weapon)
	weapon.animation_speed = 2.0

	var animation_player := weapon.find_child(
		"AnimationPlayer", true, false
	) as AnimationPlayer
	_check(weapon.try_fire(), "weapon fires with a custom animation speed")
	_check(
		animation_player.speed_scale == 2.0,
		"animation_speed is applied to the Shoot animation"
	)

	await create_timer(0.25).timeout
	_check(
		weapon.shot_animation_done,
		"a faster animation reopens the fire gate sooner"
	)

	weapon.reset_pose()
	_check(
		animation_player.speed_scale == 1.0,
		"RESET pose playback is not affected by animation_speed"
	)

	_free_fixture(fixture)


func _test_empty_clip() -> void:
	var fixture := await _new_fixture()
	var weapon := fixture.manager.active_weapon as Weapon
	_prepare_weapon(weapon, 0)
	_reset_signal_counters(weapon)
	weapon.stop_flash()

	_check(not weapon.try_fire(), "an empty weapon does not fire")
	_check(weapon.ammo == 0, "an empty weapon stays empty")
	_check(_fired_count == 0, "an empty weapon emits no fired signal")
	_check(_dry_fired_count == 1, "an empty weapon emits dry_fired")
	var flash := weapon.get_node("Muzzle/MuzzleFlash") as MuzzleFlash
	_check(not flash.is_playing(), "dry fire does not flash")

	_free_fixture(fixture)


func _test_last_round() -> void:
	var fixture := await _new_fixture()
	var weapon := fixture.manager.active_weapon as Weapon
	_prepare_weapon(weapon, 1)
	_reset_signal_counters(weapon)

	_check(weapon.try_fire(), "the last round fires")
	_check(weapon.ammo == 0, "the last round empties the weapon")
	_check(_fired_count == 1, "the last round emits fired")
	_check(not weapon.shot_animation_done, "the last round still plays its animation")
	var flash := weapon.get_node("Muzzle/MuzzleFlash") as MuzzleFlash
	_check(flash.is_playing(), "the last round still flashes")

	_free_fixture(fixture)


func _test_reload_on_holster() -> void:
	var fixture := await _new_fixture(2)
	var weapon := fixture.manager._weapons[0] as Weapon
	weapon.reload_time = 0.5
	_prepare_weapon(weapon, 0)

	_check(fixture.manager.switch_to(1), "switching away from the empty weapon succeeds")
	_check(weapon.is_reloading, "an empty holstered weapon starts reloading")
	_check(weapon.reload_time == 0.5, "the weapon keeps its own reload time")

	weapon._process(0.3)
	_check(weapon.is_reloading, "the holstered reload is still running")
	weapon._process(0.21)
	_check(not weapon.is_reloading, "the holstered reload finishes on its own timer")
	_check(weapon.ammo == weapon.clip_size, "the holstered reload refills the clip")

	_free_fixture(fixture)


func _test_reload_timers_are_independent() -> void:
	var fixture := await _new_fixture(2)
	var first := fixture.manager._weapons[0] as Weapon
	var second := fixture.manager._weapons[1] as Weapon
	first.reload_time = 0.5
	second.reload_time = 2.0
	_prepare_weapon(first, 0)

	_check(fixture.manager.switch_to(1), "switch to the second weapon")
	_check(
		not fixture.manager.switch_to(0),
		"switching is ignored while the equip animation is running"
	)
	_prepare_weapon(second, 0)
	fixture.manager.state = WeaponManager.State.READY
	_check(fixture.manager.switch_to(0), "switch back to the first weapon")

	first._process(0.6)
	second._process(0.5)
	_check(not first.is_reloading, "the short reload finished")
	_check(second.is_reloading, "the long reload is still running")
	_check(first.ammo == first.clip_size, "the short reload has a full clip")
	_check(second.ammo == 0, "the long reload is still empty")

	_free_fixture(fixture)


func _test_reloading_blocks_fire_and_shows_empty_pose() -> void:
	var fixture := await _new_fixture(2)
	var first := fixture.manager._weapons[0] as Weapon
	var second := fixture.manager._weapons[1] as Weapon
	second.reload_time = 2.0
	_prepare_weapon(first)
	fixture.manager.switch_to(1)

	second.ammo = 0
	second.start_reload()
	fixture.manager.state = WeaponManager.State.READY
	fixture.holder._equip_amount = 0.0
	_check(second.is_reloading, "the equipped weapon is still reloading")
	_check(not fixture.manager.try_fire(), "a reloading weapon cannot fire")

	fixture.holder._process(0.2)
	_check(fixture.holder._empty_amount == 1.0, "the empty pose blends in while reloading")

	second._process(2.1)
	fixture.holder._process(0.2)
	_check(second.ammo == second.clip_size, "the reload refills the equipped weapon")
	_check(fixture.holder._empty_amount == 0.0, "the empty pose blends out after reloading")
	_check(fixture.manager.try_fire(), "fire returns after the reload finishes")

	_free_fixture(fixture)


func _test_partial_clip_does_not_reload() -> void:
	var fixture := await _new_fixture(2)
	var weapon := fixture.manager._weapons[0] as Weapon
	_prepare_weapon(weapon, 3)

	fixture.manager.switch_to(1)
	_check(not weapon.is_reloading, "a partially filled weapon does not reload on holster")
	_check(weapon.ammo == 3, "the partial clip is preserved")

	_free_fixture(fixture)


func _test_instant_reload() -> void:
	var fixture := await _new_fixture(2)
	var weapon := fixture.manager._weapons[0] as Weapon
	weapon.reload_time = 0.0
	_prepare_weapon(weapon, 0)

	fixture.manager.switch_to(1)
	_check(not weapon.is_reloading, "a zero reload time finishes instantly")
	_check(weapon.ammo == weapon.clip_size, "an instant reload refills the clip")

	_free_fixture(fixture)


func _test_switch_during_shot() -> void:
	var fixture := await _new_fixture(2)
	var first := fixture.manager._weapons[0] as Weapon
	_prepare_weapon(first, 1)
	var flash := first.get_node("Muzzle/MuzzleFlash") as MuzzleFlash

	_check(first.try_fire(), "the last round fires before the switch")
	_check(flash.is_playing(), "the last round flashes before the switch")
	_check(fixture.manager.switch_to(1), "switching mid-shot is allowed")

	_check(not first.is_active, "the holstered weapon is no longer active")
	_check(first.shot_animation_done, "holstering resets the shot animation gate")
	_check(not flash.is_playing(), "holstering stops the muzzle flash")
	_check(first.is_reloading, "a mid-shot switch with the last round starts reload")
	var animation_player := first.find_child(
		"AnimationPlayer", true, false
	) as AnimationPlayer
	_check(
		animation_player.current_animation == &"RESET",
		"holstering restores the RESET pose"
	)

	_free_fixture(fixture)


func _test_equip_blocks_fire() -> void:
	var fixture := await _new_fixture()
	var weapon := fixture.manager.active_weapon as Weapon
	_prepare_weapon(weapon)
	fixture.holder.play_equip()
	fixture.manager.state = WeaponManager.State.SWITCHING

	_check(not fixture.holder.is_equip_fire_ready(), "the equip pose starts locked")
	_check(not fixture.manager.try_fire(), "fire is blocked during the equip raise")

	fixture.holder._process(0.25)
	_check(not fixture.holder.is_equip_fire_ready(), "the equip pose is still above threshold")
	fixture.holder._process(0.05)
	_check(fixture.holder.is_equip_fire_ready(), "the equip pose settles below threshold")

	fixture.manager._process(0.0)
	_check(fixture.manager.state == WeaponManager.State.READY, "the manager unlocks after equip")
	_check(fixture.manager.try_fire(), "fire works after the equip animation")

	_free_fixture(fixture)


func _test_semi_auto_input() -> void:
	var fixture := await _new_fixture(2)
	var weapon := fixture.manager.active_weapon as Weapon
	_prepare_weapon(weapon)
	fixture.manager.set_process(true)
	weapon.set_process(true)
	fixture.manager.state = WeaponManager.State.READY
	fixture.holder._equip_amount = 0.0

	var starting_ammo: int = weapon.ammo
	Input.action_press(WeaponManager.ACTION_FIRE)
	await _wait_frames(2)
	_check(weapon.ammo == starting_ammo - 1, "one input edge fires one shot")

	await _wait_frames(2)
	_check(weapon.ammo == starting_ammo - 1, "holding fire does not repeat shots")
	Input.action_release(WeaponManager.ACTION_FIRE)
	await _wait_frames(2)

	weapon.shot_animation_done = true
	weapon._time_since_last_shot = 999.0
	Input.action_press(WeaponManager.ACTION_FIRE)
	await _wait_frames(2)
	_check(weapon.ammo == starting_ammo - 2, "a new input edge fires again")
	Input.action_release(WeaponManager.ACTION_FIRE)
	await _wait_frames(2)

	var unlocked_ammo: int = weapon.ammo
	GlobalSettings.set_pointer_locked(false)
	Input.action_press(WeaponManager.ACTION_FIRE)
	await _wait_frames(2)
	_check(weapon.ammo == unlocked_ammo, "fire is ignored while the pointer is unlocked")
	Input.action_release(WeaponManager.ACTION_FIRE)

	var unlocked_weapon := fixture.manager.active_weapon as Weapon
	Input.action_press(WeaponManager.WEAPON_SLOT_ACTIONS[1])
	await _wait_frames(2)
	_check(
		fixture.manager.active_weapon == unlocked_weapon,
		"switching is ignored while the pointer is unlocked"
	)
	Input.action_release(WeaponManager.WEAPON_SLOT_ACTIONS[1])
	GlobalSettings.set_pointer_locked(true)
	await _wait_frames(1)

	_free_fixture(fixture)


func _new_fixture(weapon_count := 1) -> Dictionary:
	var player := PLAYER_SCENE.instantiate()
	var manager := player.get_node(
		"GunViewport/WeaponHolder/WeaponManager"
	) as WeaponManager
	var scenes: Array[PackedScene] = []
	for _index in weapon_count:
		scenes.append(PISTOL_SCENE)
	manager.weapon_scenes = scenes
	player.set_script(PLAYER_MOVEMENT)
	root.add_child(player)

	for _frame in 60:
		await process_frame
		if manager.active_weapon != null:
			break

	var holder := player.get_node("GunViewport/WeaponHolder") as WeaponHolder
	manager.set_process(false)
	holder.set_process(false)
	for weapon in manager._weapons:
		weapon.set_process(false)

	manager.state = WeaponManager.State.READY
	holder._equip_amount = 0.0
	holder._empty_amount = 0.0
	return {"player": player, "manager": manager, "holder": holder}


func _free_fixture(fixture: Dictionary) -> void:
	var player := fixture.player as Node
	if is_instance_valid(player):
		for audio in player.find_children("*", "AudioStreamPlayer", true, false):
			(audio as AudioStreamPlayer).stop()
		player.free()
	fixture.clear()


func _prepare_weapon(weapon: Weapon, ammo := -1) -> void:
	weapon.set_active(true)
	weapon.is_reloading = false
	weapon.reload_elapsed = 0.0
	weapon.shot_animation_done = true
	weapon._time_since_last_shot = 999.0
	if ammo >= 0:
		weapon.ammo = ammo


func _reset_signal_counters(weapon: Weapon) -> void:
	_fired_count = 0
	_dry_fired_count = 0
	weapon.fired.connect(func(_weapon: Weapon) -> void: _fired_count += 1)
	weapon.dry_fired.connect(func(_weapon: Weapon) -> void: _dry_fired_count += 1)


func _wait_frames(count: int) -> void:
	for _frame in count:
		await process_frame


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("  PASS  ", description)
	else:
		_failures += 1
		print("  FAIL  ", description)
