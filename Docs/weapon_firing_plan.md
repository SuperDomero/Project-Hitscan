# Weapon Firing & Equip Plan

Status: planning document. No gameplay code has been changed yet.

## 1. Goals And Rules

- The player carries multiple guns, each with its own `Shoot` animation.
- Every gun is semi-auto: one shot per fire press.
- Every gun has a magazine size; there is no manual reload.
- An empty gun reloads only when the player switches away from it.
- Every gun has its **own reload time**; reload durations are per-weapon data, not a shared constant.
- Firing is **blocked for the whole reload**, including after the gun is re-equipped.
- Fire cadence is defined by a **fire rate**, not a cooldown duration.
- A new shot is allowed only when both conditions are true:
  1. the fire-rate interval since the previous shot has elapsed;
  2. the previous `Shoot` animation has finished.
- Switching to a gun plays a **procedural equip animation** on the viewmodel.
- Re-equipping a gun that is still reloading shows an **empty weapon pose** until the reload finishes.
- Each gun has a muzzle flash VFX that fires at the muzzle and follows the weapon.

## 2. Current Relevant Files

| File | Current role |
| --- | --- |
| `Scenes/player.tscn` | Player, camera, `GunViewport`, `WeaponHolder`, viewmodel weapons |
| `Scripts/weapon_holder.gd` | Bob, sway, slide/air/landing poses; writes `WeaponHolder` transform |
| `Scenes/pistol.tscn` | Pistol GLB instance; imported `Shoot` animation animates `slide` and `hammer` bones |
| `Scenes/muzzle_flash.tscn` | One-shot-style muzzle flash particles (currently not configured as one-shot) |
| `Scenes/level_1.tscn` | Contains a stray, fixed-position `MuzzleFlash` instance |

The imported pistol `Shoot` animation is roughly `0.333 s` long, with its first visible key around `0.042 s`. It animates bones inside the gun, not the `WeaponHolder` transform.

## 3. Proposed Architecture

```text
WeaponHolder (Node3D)
├── WeaponManager (Node)          <- new: input, switching, fire-rate gate, reload timers
├── pistol (pistol.tscn)
│   ├── AnimationPlayer            <- imported "Shoot"
│   ├── Muzzle (Marker3D)          <- new: barrel tip
│   │   └── MuzzleFlash (instance) <- new: follows the gun
│   └── Weapon.gd                  <- new: ammo, animation, flash, reload state
└── other_gun (other_gun.tscn)
```

Responsibilities:

- **`Weapon.gd`** (gun scene root): owns ammo, reload state, animation and muzzle flash behaviour. Exposes `try_fire()`, `start_reload()`, `reset_pose()` and signals such as `fired` and `ammo_changed`.
- **`WeaponManager.gd`** (child `Node` under `WeaponHolder`): instantiates guns, tracks the active weapon, handles input, switching and the fire-rate timer.
- **`weapon_holder.gd`**: remains responsible only for the viewmodel transform (bob/sway/state poses plus the procedural equip and empty-pose layers).
- **`MuzzleFlash`**: child of each gun's `Muzzle` marker, so it inherits the weapon transform and stays aligned.

Keeping the manager separate means firing code never writes `WeaponHolder.position` or `rotation`, and `weapon_holder.gd` remains the single writer of the holder transform.

## 4. Weapon Data And State

Per-gun exports on `Weapon.gd`:

```gdscript
@export var clip_size: int = 8
@export var fire_rate_rpm: float = 180.0
@export var fire_animation: StringName = &"Shoot"
@export var reload_time: float = 1.0   # unique per weapon
```

`reload_time` is set individually on every gun scene. There is no global reload constant; a light pistol might use `0.8 s`, a heavy revolver `2.2 s`, and so on. A value of `0` still means an instant reload and is allowed.

Runtime state per weapon instance:

```text
ammo: int
is_empty: bool
is_reloading: bool
reload_elapsed: float
reload_time: float        # copied from the export, per weapon
shot_animation_done: bool
```

Ammo lives on the weapon instance, so switching away and back preserves it. Reloading an empty weapon on holster refills `ammo` after that weapon's own `reload_time`.

## 5. Input

Add to the Input Map:

- `fire` → mouse button 1
- `weapon_1`, `weapon_2`, … (direct slots)
- `weapon_next` / `weapon_prev` (mouse wheel or keys)

Rules:

- Fire must use an input edge (`Input.is_action_just_pressed` or an `InputEventMouseButton` press), never a held check.
- Ignore fire and switching while `GlobalSettings.pointer_locked` is false.
- Ignore fire while the manager is `SWITCHING`, while the weapon is reloading, or while the equip animation is still blocking fire.
- A press during the fire/animation lock is discarded by default. A one-press buffer can be added later if the cadence feels unresponsive.

## 6. Fire-Rate + Animation Gate

`fire_rate_rpm` is the raw cadence in rounds per minute:

```text
seconds_per_shot = 60.0 / fire_rate_rpm
```

The player may fire again only when **both** are true:

```text
time_since_last_shot >= seconds_per_shot
AND
previous Shoot animation has finished
```

Therefore the effective interval is:

```text
effective_interval = max(seconds_per_shot, Shoot_animation_length)
effective_rpm      = 60.0 / effective_interval
```

Examples:

| `fire_rate_rpm` | `seconds_per_shot` | Animation length | Effective interval | Effective RPM |
| --- | --- | --- | --- | --- |
| 180 | 0.333 s | 0.333 s | 0.333 s | 180 |
| 360 | 0.167 s | 0.333 s | 0.333 s | 180 |
| 120 | 0.500 s | 0.333 s | 0.500 s | 120 |

This means the fire rate is the primary cadence control, but the animation can only slow it down, never speed it up.

Implementation notes:

- Start a `time_since_last_shot` timer when a shot is accepted; advance it in `_process` or `_physics_process`.
- Track animation completion with the `AnimationPlayer.animation_finished` signal rather than hardcoding the current `0.333 s` length.
- Set `shot_animation_done = true` only when the finished animation matches this weapon's `fire_animation` and the weapon is still active.
- Because the weapon is semi-auto, holding the fire button must never repeat shots. The fire-rate timer only limits how quickly repeated presses can fire.

## 7. Shot Sequence

On a valid fire press:

1. Manager is `READY`, pointer is locked, and the active weapon can fire.
2. If `ammo == 0`:
   - do not play `Shoot`, do not flash;
   - optionally play a dry-fire click.
3. Otherwise:
   - `ammo -= 1`;
   - reset `time_since_last_shot = 0`;
   - set `shot_animation_done = false`;
   - play `fire_animation` from the start;
   - trigger the muzzle flash;
   - emit `fired` / `ammo_changed` for HUD and optional recoil.
4. When the animation finishes, set `shot_animation_done = true`.
5. When the accepted shot consumed the last round, mark the weapon empty. The final shot still gets its full animation and flash.

There is no automatic reload and no automatic weapon switch.

## 8. Empty Clip And Reload On Holster

Rule: a weapon reloads only when it is empty **and** the player switches away from it.

Recommended flow:

1. Player fires the last round. `ammo` becomes `0`; the last shot animation and flash still play.
2. Further fire presses on that weapon do nothing except optional dry-fire feedback.
3. The player switches to another weapon.
4. If the holstered weapon has `ammo == 0`:
   - set `is_reloading = true`;
   - start its reload timer.
5. When `reload_elapsed >= reload_time`, set `ammo = clip_size` and `is_reloading = false`.

Reload edge cases:

- A weapon with a partially filled clip does **not** reload when holstered, because the rule is specifically “if the clip is empty”.
- If the player switches back before a holstered reload finishes:
  - the weapon is equipped normally;
  - it shows its **empty weapon pose** (see section 9) for as long as the reload is running;
  - firing stays blocked until `reload_elapsed >= reload_time`, then the reload finishes and the pose blends back to normal.
- Reloading continues whether the weapon is holstered or equipped. It is a per-weapon timer, not tied to the active slot.
- Because `reload_time` is unique per weapon, the empty pose on re-equip can last very different amounts of time depending on the gun.
- `reload_time = 0` gives an instantaneous reload on switch-away, so the empty pose is never visible.
- If all weapons are empty or reloading, the player can still switch, but cannot fire.
- A future pickup or refill system can call a `refill()` method without changing this structure.

## 9. Switching And Procedural Equip Animation

### Switch sequence

1. A switch request selects a different weapon slot.
2. The manager enters `SWITCHING` and blocks fire.
3. The old weapon:
   - stops its muzzle flash;
   - stops and resets its `Shoot` animation pose;
   - is hidden;
   - starts its holstered reload if it is empty.
4. The new weapon:
   - is shown;
   - has its animation pose reset;
   - becomes the active weapon;
   - triggers the procedural equip animation on `WeaponHolder`.
5. Fire becomes available again when the equip animation has finished (or reached its fire-ready threshold) **and** the new weapon is not reloading. A gun that is still reloading shows its empty pose instead of becoming fire-ready.

Switching again while already switching should be ignored or queued until the current equip finishes.

### Procedural equip animation

The equip animation is not an authored animation clip. It is an additive viewmodel pose driven by `weapon_holder.gd`:

- Add state fields such as `_equip_offset`, `_equip_rotation`, and `_equip_amount`.
- On equip, set `_equip_amount = 1` and start from a lowered/tilted pose, for example:
  - position offset: `(0.0, -0.25, -0.12)`
  - rotation offset: `(-35°, 10°, 15°)`
- Every frame, move `_equip_amount` toward `0` using the project's smoothing style (`move_toward` with an equip speed, or a spring for a more physical settle).
- Compute the equip pose as `equip_pose * _equip_amount` and combine it with the existing bob, sway and state offsets inside `_apply_pose()`:
  ```gdscript
  _apply_pose(
      _state_position + bob_position * _walk_blend + _sway_position + _equip_position,
      _state_rotation + bob_rotation * _walk_blend + _sway_rotation + _equip_rotation
  )
  ```
- `_apply_pose()` remains the only place that writes the holder position and rotation.
- Expose tunables such as `equip_position_offset`, `equip_rotation_degrees`, `equip_speed` and `equip_fire_threshold` on the `WeaponHolder`.
- `WeaponManager` calls `play_equip()` on the holder when the active weapon changes, or the holder listens to a `weapon_equipped` signal.
- Fire is blocked until the equip amount is below the fire threshold, so the player cannot fire while the gun is still rising into view.
- Bob and sway continue underneath the equip pose, so movement remains responsive during the switch.

### Empty weapon pose while reloading

When the player re-equips a gun that is still reloading, the equip animation plays normally, but the gun must not return to its normal idle pose while the reload is still running. Instead it holds a procedural **empty pose** until the reload finishes.

This is a second additive layer in `weapon_holder.gd`, driven by the active weapon's `is_reloading` state:

- Add `_empty_amount` that targets `1.0` while the active weapon `is_reloading`, and `0.0` otherwise.
- Expose tunables such as `empty_position_offset`, `empty_rotation_degrees`, `empty_blend_speed` on the `WeaponHolder`.
- Suggested empty pose, readable without a dedicated animation clip:
  - lower the gun slightly: position offset around `(0.0, -0.10, 0.05)`;
  - tilt it inward toward the player: rotation offset around `(10°, -18°, -25°)`, so the open/locked side is visible;
  - optional small downward “muzzle drop” so it reads as not ready to fire.
- Blend it in `_apply_pose()` together with bob, sway, state and equip layers:
  ```gdscript
  var empty_weight := _empty_amount * (1.0 - _equip_amount)
  _apply_pose(
      _state_position + bob_position * _walk_blend + _sway_position
          + _equip_position + _empty_position * empty_weight,
      _state_rotation + bob_rotation * _walk_blend + _sway_rotation
          + _equip_rotation + _empty_rotation * empty_weight
  )
  ```
- Layering order: the equip animation still owns the initial raise. The empty pose is fully visible only after the equip layer has settled, and it blends out smoothly the moment `is_reloading` turns false.
- The `(1.0 - _equip_amount)` weight makes the equip layer dominate while it is active, then hand off to the empty pose as the gun finishes rising.
- Optionally, each gun can also have a static “empty” bone pose (e.g. slide locked back) played through its `AnimationPlayer`. That is cosmetic and independent of the holder layer; the holder layer is the required behaviour.
- Firing is blocked by the weapon state (`is_reloading`), not by the pose. The pose only communicates the state to the player.

### Animation pose reset

The imported GLB currently has `animation/import_rest_as_RESET=false`. Enable `import_rest_as_RESET` so a `RESET` animation exists, then play `RESET` when holstering a gun. This prevents `slide`/`hammer` bones from freezing mid-shot when switching during or immediately after a shot.

## 10. Muzzle Flash Integration

Current state:

- `muzzle_flash.tscn` has a `GPUParticles3D` with `amount = 1`, `lifetime = 0.1`, but it is not configured as `one_shot`.
- `level_1.tscn` contains a fixed-position `MuzzleFlash` world node that is not attached to any gun.

Plan:

1. Remove the stray `MuzzleFlash` from `level_1.tscn`.
2. In every gun scene:
   - add a `Muzzle` `Marker3D` at the barrel tip;
   - instance `muzzle_flash.tscn` as a child of `Muzzle`.
3. Configure the flash particles:
   - `one_shot = true`
   - `emitting = false` at rest
   - `local_coords = true` so the flash follows the gun
4. On each accepted shot, call `flash.restart()` (and set `emitting = true` if required by the one-shot setup).
5. On holster, stop the flash so no particles linger on a hidden weapon.
6. If the flash needs exact animation timing, add a method track to the `Shoot` animation. For the current animation, triggering on the accepted fire input is sufficient.

The flash should only play when a round is actually consumed. Empty-clip clicks must not flash.

## 11. Interaction With Existing Viewmodel Animation

- `Shoot` animates bones inside the gun (`slide`, `hammer`, `magazine`), not the `WeaponHolder`.
- Bob, sway, slide, airborne and landing poses are applied to the `WeaponHolder` by `weapon_holder.gd`.
- The procedural equip pose is another additive layer on the `WeaponHolder`.
- The procedural empty/reloading pose is a third additive layer, gated by the active weapon's `is_reloading` state.
- Therefore firing, bobbing, swaying, equipping and the empty pose can all run at the same time without fighting over the holder transform.
- Layer order inside `_apply_pose()`: state pose, then bob, then sway, then equip, then the empty pose (weighted so it fades in as the equip layer fades out).
- If weapon recoil is added later, treat it as another additive layer in `_apply_pose()` rather than animating the holder from `WeaponManager` or the gun's `AnimationPlayer`.

## 12. HUD And Feedback (Optional)

Expose signals from the manager/weapon for later UI work:

- `weapon_changed(weapon)`
- `ammo_changed(current: int, maximum: int)`
- `reload_started(duration: float)` / `reload_finished`
- `fired(weapon)`

Because `reload_time` differs per weapon, `reload_started` should pass that weapon's duration so a HUD reload indicator can be sized correctly. A minimal ammo readout can show `ammo / clip_size`, `EMPTY`, or `RELOADING`. Per-shot audio can be added alongside the muzzle flash trigger.

## 13. Edge Cases

- **Fire pressed while the previous animation is still playing:** rejected by the animation gate.
- **Fire pressed before the fire-rate interval expires:** rejected by the rate gate.
- **Fire pressed while the active weapon is reloading:** rejected, regardless of the equip/pose state.
- **Holding fire:** only the initial press fires; no automatic repeat.
- **Last round:** animation and flash still play; the weapon then becomes empty.
- **Switch away from an empty weapon:** reload starts while holstered, using that weapon's own `reload_time`.
- **Switch back before reload finishes:** weapon equips, holds the empty pose, and cannot fire until the reload completes; the pose then blends out.
- **Switch back after reload finishes:** weapon equips normally with a full clip and no empty pose.
- **Two weapons with different reload times:** each keeps its own timer independently while holstered.
- **Switch away from a partially filled weapon:** no reload.
- **Switch during a shot:** old animation is stopped and reset; its flash is stopped; the new weapon plays its equip animation.
- **Switch during a shot that emptied the weapon:** the holstered reload starts, and re-equipping before it finishes shows the empty pose.
- **Pointer unlocked / menu open:** no firing or switching.
- **Missing `AnimationPlayer` or fire animation:** log a warning and treat the weapon as unable to fire rather than crashing.
- **All weapons empty/reloading:** switching is still allowed, but firing is unavailable.

## 14. Recommended Defaults

| Setting | Default |
| --- | --- |
| `clip_size` | per weapon (pistol: 8) |
| `fire_rate_rpm` | per weapon (pistol: `180`) |
| `reload_time` | per weapon, unique (e.g. pistol `1.0 s`) |
| Equip duration | `0.25–0.35 s` |
| Equip fire threshold | `0.1` (90% settled) |
| Empty pose blend speed | `8–12` (fast but readable) |
| Fire input | left mouse button |
| Weapon slots | number keys, plus wheel next/previous |

## 15. Implementation Order

1. Add `fire` and weapon-switch actions to the Input Map.
2. Add `Weapon.gd` with ammo, fire-rate tracking and animation state.
3. Add `Muzzle` and per-weapon muzzle flash to `pistol.tscn`; configure the flash as one-shot; remove the level-placed flash.
4. Add `WeaponManager.gd` and register the pistol as the first weapon.
5. Implement semi-auto input, the fire-rate + animation gate, and ammo consumption.
6. Implement empty state, dry-fire feedback, per-weapon reload-on-holster timers.
7. Implement switching and the procedural equip layer in `weapon_holder.gd`.
8. Implement the procedural empty/reloading pose and blend it with the equip layer.
9. Add signals, HUD ammo/reload text, audio and optional recoil polish.
10. Playtest cadence, equip timing, per-weapon reload times, switching during shots, and reload edge cases.

## 16. Test Checklist

- [ ] Clicking once fires exactly one shot, one animation and one muzzle flash.
- [ ] Holding the fire button does not repeat fire.
- [ ] Rapid clicking is limited by `fire_rate_rpm`.
- [ ] With a fire rate faster than the animation, the animation completion is the limiting gate.
- [ ] The last shot still plays its animation and flash, then the weapon becomes empty.
- [ ] Empty-clip clicks do not play the shoot animation or flash.
- [ ] Switching away from an empty weapon starts that weapon's own reload timer.
- [ ] Two weapons with different `reload_time` values reload independently and correctly.
- [ ] Switching away from a partially filled weapon does not reload it.
- [ ] Switching back before the reload completes shows the empty weapon pose and blocks fire.
- [ ] When the reload finishes while equipped, the empty pose blends out and fire becomes available.
- [ ] Switching back after the reload completes shows no empty pose.
- [ ] Every switch plays the procedural equip animation and blocks fire until it settles.
- [ ] Switching during a shot resets the old gun's pose and leaves no muzzle flash behind.
- [ ] Bob, sway, slide and landing poses still work while firing, equipping and showing the empty pose.
- [ ] Firing and switching are ignored while the pointer is unlocked.
