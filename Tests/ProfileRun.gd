extends SceneTree

## Gameplay profiler for Project Hitscan.
##
## Loads level_1, reports whole-frame Engine timings, then microbenchmarks each
## mechanic's real per-frame entry point (and its per-call pieces) with a pinned
## state so the numbers are not polluted by the player drifting through the map.
##
## Run with:
##   godot --headless --path . --script res://Tests/ProfileRun.gd
##
## Values are CPU microseconds per call. Headless hides GPU cost; use
## --gpu-profile for rendering hotspots.

const LEVEL_SCENE := preload("res://Scenes/level_1.tscn")

const ITERATIONS := 4000
const WARMUP := 400

var _level: Node
var _player: PlayerMovement
var _holder: WeaponHolder
var _manager: WeaponManager
var _weapon: Weapon
var _look: Node3D
var _recoil: CameraRecoil
var _speed_fx: Node
var _rows: Array[Dictionary] = []

var _overhead_delta := 0.0
var _overhead_plain := 0.0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	Engine.physics_ticks_per_second = 60
	Engine.max_fps = 60
	GlobalSettings.pointer_locked = true

	_level = LEVEL_SCENE.instantiate()
	root.add_child(_level)
	for _i in 30:
		await process_frame

	_player = _level.get_node("Player") as PlayerMovement
	_holder = _player.get_node("GunViewport/WeaponHolder") as WeaponHolder
	_manager = _holder.get_node("WeaponManager") as WeaponManager
	_weapon = _manager.active_weapon as Weapon
	_look = _player.get_node("Camera holder") as Node3D
	_recoil = _player.get_node("Camera holder/RecoilPivot") as CameraRecoil
	_speed_fx = _player.get_node("Camera holder/Speed lines") as Node

	if _player == null or _holder == null or _manager == null or _weapon == null:
		print("PROFILE ERROR: could not resolve player nodes.")
		quit(1)
		return

	print("")
	print("=== Project Hitscan gameplay profile ===")
	print("scene=%s  weapons=%d  physics=%d Hz" % [
		_level.scene_file_path, _manager._weapons.size(), Engine.physics_ticks_per_second
	])
	print("")

	_release_input()
	await _report_frame_window("idle (no input)", 60, false)
	await _report_frame_window("walking, jumping, sliding, firing", 120, true)
	_pin_state()
	_run_microbenchmarks()
	_report()

	await process_frame
	quit(0)


## Real engine-reported cost for a short, representative live frame.
func _report_frame_window(label: String, frames: int, drive: bool) -> void:
	var process_total := 0.0
	var physics_total := 0.0
	var physics_steps := 0
	var wall_start := Time.get_ticks_usec()
	var physics_before := Engine.get_physics_frames()
	for frame in frames:
		if drive:
			_drive_input(frame)
		else:
			_release_input()
		await process_frame
		process_total += Performance.get_monitor(Performance.TIME_PROCESS)
		physics_total += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
	physics_steps = Engine.get_physics_frames() - physics_before
	var wall := float(Time.get_ticks_usec() - wall_start) / float(frames) / 1_000_000.0

	print("[Whole frame: %s]" % label)
	print("  wall frame time : %8.3f ms  (%5.1f fps)" % [wall * 1000.0, 1.0 / maxf(wall, 0.000001)])
	print("  process total   : %8.3f ms" % (process_total / frames * 1000.0))
	print("  physics total   : %8.3f ms  (%d steps / %d frames)" % [
		physics_total / frames * 1000.0, physics_steps, frames
	])
	print("")


## Freezes the player in a grounded, walking, firing state so every benchmark
## call sees the same branch of every mechanic.
func _pin_state() -> void:
	Engine.max_fps = 0
	Input.action_press("w")
	for _i in 3:
		await process_frame
	_player.velocity = Vector3(0.0, 0.0, -_player.walk_speed)
	_player._sliding = false
	_player._slide_pose = 0.0
	_player._slide_time_left = 0.0
	_player._bunny_hop_fov_kick = 0.0
	_player._landing_kick = 0.0
	_player._landing_kick_velocity = 0.0

	_holder._walk_state = WeaponHolder.WalkState.walking
	_holder._equip_amount = 0.0
	_holder._empty_amount = 0.0
	_manager.state = WeaponManager.State.READY

	_weapon.ammo = _weapon.clip_size
	_weapon.is_reloading = false
	_weapon.reload_elapsed = 0.0

	_recoil.kick(1.0, 0.5, 10.0)
	var sounds := _weapon.get_node_or_null("WeaponSounds") as WeaponSounds
	if sounds != null:
		_player._sounds._sound_fade = 1.0


func _run_microbenchmarks() -> void:
	# Call overhead baselines so the reported cost is the method's own work.
	_overhead_plain = _time_callable(Callable(self, "_noop"), ITERATIONS)
	_overhead_delta = _time_callable(Callable(self, "_noop_delta").bind(0.0), ITERATIONS)

	# --- PlayerMovement: every sub-step of _physics_process except the engine's
	# move_and_slide(), which is not a script cost. ---
	var movement_parts: Array[Dictionary] = [
		{"label": "PlayerMovement._update_input", "fn": Callable(_player, "_update_input"), "plain": true},
		{"label": "PlayerMovement._update_jump_buffer", "fn": Callable(_player, "_update_jump_buffer").bind(0.0)},
		{"label": "PlayerMovement._update_slide", "fn": Callable(_player, "_update_slide").bind(0.0)},
		{"label": "PlayerMovement._apply_horizontal_movement", "fn": Callable(_player, "_apply_horizontal_movement").bind(0.0)},
		{"label": "PlayerMovement._apply_vertical_movement", "fn": Callable(_player, "_apply_vertical_movement").bind(0.0)},
		{"label": "PlayerMovement._update_slide_pose", "fn": Callable(_player, "_update_slide_pose").bind(0.0)},
		{"label": "PlayerMovement._update_slide_camera", "fn": Callable(_player, "_update_slide_camera").bind(0.0)},
		{"label": "PlayerMovement._update_slide_audio", "fn": Callable(_player, "_update_slide_audio").bind(0.0)},
		{"label": "PlayerMovement._push_rigid_bodies", "fn": Callable(_player, "_push_rigid_bodies").bind(Vector3.ZERO)},
		{"label": "PlayerMovement._update_landing", "fn": Callable(_player, "_update_landing"), "plain": true},
		{"label": "PlayerMovement._update_landing_camera", "fn": Callable(_player, "_update_landing_camera").bind(0.0)},
		{"label": "PlayerMovement._apply_camera_roll", "fn": Callable(_player, "_apply_camera_roll"), "plain": true},
		{"label": "PlayerMovement._log_inputs", "fn": Callable(_player, "_log_inputs").bind(0.0)},
	]
	var movement_total := 0.0
	for part in movement_parts:
		var overhead := _overhead_plain if part.get("plain", false) else _overhead_delta
		var cost := _record(part.label, part.fn, overhead)
		movement_total += cost
	_add_summary("PlayerMovement (physics step, excl. move_and_slide)", movement_total)

	# --- Other per-frame mechanics ---
	_record("PlayerLook._process (mouse aim)", Callable(_look, "_process").bind(0.0), _overhead_delta)
	_record("CameraRecoil._process (active kick)", Callable(_recoil, "_process").bind(0.0), _overhead_delta)
	_record("SpeedLineParticles._process", Callable(_speed_fx, "_process").bind(0.0), _overhead_delta)
	_record("WeaponHolder._process (pose)", Callable(_holder, "_process").bind(0.0), _overhead_delta)
	_record("WeaponHolder._physics_process (state)", Callable(_holder, "_physics_process").bind(0.0), _overhead_delta)
	_record("WeaponManager._process (input)", Callable(_manager, "_process").bind(0.0), _overhead_delta)
	_record("Weapon._process (fire timer)", Callable(_weapon, "_process").bind(0.0), _overhead_delta)

	var sounds := _weapon.get_node_or_null("WeaponSounds") as WeaponSounds
	if sounds != null:
		_record(
			"PlayerSounds.update_slide_audio",
			Callable(_player._sounds, "update_slide_audio").bind(0.0, true, 7.3),
			_overhead_delta
		)

	# --- Event-driven paths ---
	_record(
		"WeaponHUD._refresh (on ammo change)",
		Callable(_player.get_node("HUD/Ammo"), "_refresh"),
		_overhead_plain,
		400
	)
	if sounds != null:
		_record(
			"WeaponSounds.play_fire (per shot)",
			Callable(sounds, "play_fire"),
			_overhead_plain,
			400
		)
	if _weapon._muzzle_flash != null:
		_record(
			"MuzzleFlash.play (per shot)",
			Callable(_weapon._muzzle_flash, "play"),
			_overhead_plain,
			400
		)


func _record(
	label: String, fn: Callable, overhead: float, iterations := ITERATIONS
) -> float:
	var us := _time_callable(fn, iterations) - overhead
	us = maxf(us, 0.0)
	_rows.append({"label": label, "us": us})
	return us


func _add_summary(label: String, us: float) -> void:
	_rows.append({"label": label, "us": us})


func _time_callable(fn: Callable, iterations: int) -> float:
	var warmup := mini(WARMUP, maxi(iterations / 4, 1))
	for _i in warmup:
		fn.call()
	var start := Time.get_ticks_usec()
	for _i in iterations:
		fn.call()
	var elapsed := Time.get_ticks_usec() - start
	return float(elapsed) / float(iterations)


func _report() -> void:
	_rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.us > b.us
	)
	var total := 0.0
	print("[Per-call CPU cost, sorted slowest first]")
	print("mechanic                                     time        % of scripted frame")
	print("-------------------------------------------- ----------- --------------------")
	for row in _rows:
		if row.label.begins_with("PlayerMovement (physics step"):
			continue
		total += row.us
	for row in _rows:
		print(
			"%-44s %8.3f us %10.2f%%"
			% [row.label, row.us, (row.us / maxf(total, 0.0001)) * 100.0]
		)
	print("-------------------------------------------- ----------- --------------------")
	print("%-44s %8.3f us %10.2f%%" % ["sum of measured per-frame/event calls", total, 100.0])
	print("")
	print("Note: per-shot/event rows are one-off costs, not added every frame.")


## Reports the amortized cost of the debug input logger, which formats and
## prints a long line every INPUT_LOG_INTERVAL seconds.
func _report_logging_note() -> void:
	pass


func _noop() -> void:
	pass


func _noop_delta(_delta: float) -> void:
	pass


func _release_input() -> void:
	for action in ["w", "a", "s", "d", "space", "lShift", "lControl", "fire"]:
		Input.action_release(action)


func _drive_input(frame: int) -> void:
	Input.action_press("w")
	if frame % 60 == 0:
		Input.action_press("space")
	else:
		Input.action_release("space")
	if frame % 90 >= 40 and frame % 90 < 60:
		Input.action_press("lShift")
	else:
		Input.action_release("lShift")
	if frame % 12 == 0:
		Input.action_press("fire")
	else:
		Input.action_release("fire")
