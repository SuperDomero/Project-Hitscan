---
name: movement-camera-style
description: Use when writing, modifying, or extending player movement, sliding, look controls, camera effects, or player audio (slide loop, landing sound) in Project Hitscan (Godot 4). Covers PlayerMovement.gd, PlayerLook.gd, GlobalSettings, tick-based friction, slide mechanics, FOV/roll/landing-kick camera effects, AudioStreamPlayer3D wiring, and the exact code conventions this project uses.
---

# Project Hitscan — Movement & Camera Style

Godot 4.7, GDScript, `CharacterBody3D` + **Jolt Physics** (`project.godot:75`).
The whole feel is authored as flat, tunable `@export` constants on the player
script, with camera effects derived from simulation state. Match this style
exactly when adding anything.

## Files and where things live

| Concern | File |
| --- | --- |
| Movement, slide, slide camera | `Scripts/PlayerMovement.gd` (on the `Player` node in `level_1.tscn`) |
| Mouse look / pitch / pointer lock | `Scripts/PlayerLook.gd` (on the `Camera holder` node) |
| Sensitivity / FOV / pointer state | `Scripts/GlobalSettings.gd` (static `class_name`) |
| Node hierarchy | `Scenes/player.tscn` |

Scene hierarchy (names matter, they are fetched by `NodePath`/`find_child`):

```
Player (CharacterBody3D)                    <- PlayerMovement.gd, yaw here
├── Player model (Node3D)
├── CollisionShape3D (CapsuleShape3D, duplicated at runtime)
├── Camera holder (Node3D)                  <- PlayerLook.gd, pitch here, roll here
│   ├── Camera3D
│   └── AudioListener3D
├── PlayerSoundSource (AudioStreamPlayer3D)  <- looping slide loop
└── LandingSoundSource (AudioStreamPlayer3D) <- one-shot landing
```

- Yaw is applied to the **player** root (`_player.rotation.y` in `PlayerLook.gd:36`).
- Pitch is applied to the **Camera holder** (`rotation.x`, clamped ±90°, `PlayerLook.gd:31`).
- Camera roll and body camera-drop are applied to the **Camera holder**
  (`_apply_camera_roll`, `_set_pose_geometry`). Never rotate the `Camera3D` itself.
- `PlayerMovement` caches nodes in `_ready` via exported `NodePath`s
  (`collision_shape_path`, `model_path`, `camera_path`, `sound_source_path`,
  `landing_sound_path`) and finds the camera with
  `_camera_holder.find_child("Camera3D", true, false)`. Optional audio nodes use
  `get_node_or_null(...)` and are null-checked, so the player still works without them.
- Audio streams are wired in the scene (`player.tscn`), never loaded in code. Imported
  audio that needs to loop sets `edit/loop_mode` in the `.import` file.

## Code conventions (non-negotiable)

- GDScript, fully typed. `const ACTION_W := &"w"` style `StringName` action constants,
  never raw string literals in `Input` calls (`PlayerMovement.gd:3-9`).
- Private state prefixed `_` (`_sliding`, `_wish_direction`, `_slide_pose`).
- Group tuning vars with `@export_group("Name")`; give each a leading `##` doc
  comment when meaning is not obvious (`PlayerMovement.gd:28-59`).
- Defaults carry absurdly precise decimals (`7.317`, `1.2522`, `0.546`). These are
  hand-tuned — **do not round, retune, or "clean up" numbers unless asked.**
- `_physics_process` is a fixed pipeline; keep the order and append new steps:
  `_update_input → _update_slide → _apply_horizontal_movement →
  _apply_vertical_movement → _update_slide_pose → _update_slide_camera →
  _update_slide_audio → move_and_slide → _update_landing →
  _update_landing_camera → _apply_camera_roll → _log_inputs` (`PlayerMovement.gd:131-143`).
- Helper names are verb-led and return the value they compute
  (`_horizontal_velocity()`, `_set_horizontal_velocity()`, `_steer_slide()`).
- Do not add comments to code you write beyond `##` doc comments on nontrivial
  methods — this project is comment-light.

## Movement model

Simulation is Quake/Source-flavoured and **tick-based**::

```gdscript
const TICKS_PER_SECOND: float = 20.0
horizontal *= pow(ground_friction_per_tick, delta * TICKS_PER_SECOND)
```

All friction/retention values are **per-tick multipliers**; always convert to
per-frame with `pow(value, delta * TICKS_PER_SECOND)`. Never apply them linearly.

Derived quantities are computed from the tunables, not hardcoded:

```gdscript
@onready var jump_velocity: float = sqrt(2.0 * gravity * jump_height)
```

Key tunables (`PlayerMovement.gd:14-59`): walk `7.317`, sneak `3.295`, gravity
`32.0`, jump_height `1.2522`, terminal_velocity `78.4`, ground accel `40.0`,
air accel `8.0`, ground friction/tick `0.546`.

Wish direction is camera-relative and flattenned:

```gdscript
_wish_direction = global_basis * Vector3(input.x, 0.0, -input.y)
_wish_direction.y = 0.0
```

Analog input length is preserved (`_target_speed = speed * input.length()`), and
movement uses `move_toward` with ground vs air acceleration. When there is no
wish direction on the floor, apply ground friction. This is deliberate: air
strafing and momentum preservation are part of the feel — keep `air_acceleration`
low and friction velocity-proportional.

## Slide model (the signature mechanic)

State is a small machine: `_sliding`, `_slide_time_left`, `_slide_cooldown`,
`_slide_buffer`, plus pose/steer/roll interpolants.

- Entry needs floor, not sneaking, and speed ≥ `slide_entry_speed` (`3.885`).
- **Land buffer**: `Input.is_action_just_pressed(ACTION_SLIDE)` sets
  `_slide_buffer = slide_land_buffer` (`0.5`), so pressing in mid-air slides on
  landing (`PlayerMovement.gd:142-149`).
- **Boost**: on entry, add `horizontal.normalized() * slide_boost_speed` (`12.914`),
  clamped to `slide_max_speed` (`18.77`); gated by `slide_boost_cooldown` (`2.0`).
- Slide ends on `slide_duration` (`1.0`) expiry or leaving the floor.
- While sliding, friction is `slide_friction_per_tick` (`0.96`) and heading is
  steered toward the look direction at `slide_steer_speed` (`90°`/s) — see
  `_steer_slide`, which also outputs `_slide_steer ∈ [-1, 1]` for the camera lean.
- Jumping cancels the slide (`PlayerMovement.gd:210`).

**Slide pose** sinks the whole body, not just the camera:

```gdscript
_capsule.height = lerpf(_standing_height, _crouch_height, pose)
var sink := (_standing_height - _capsule.height) * -0.5
_collision_shape.position.y = sink
_model.position.y = _model_stand_y + sink
_camera_holder.position.y = _camera_stand_y + sink * slide_camera_drop_ratio
```

Standing up is refused while blocked, tested by swapping the pose geometry and
calling `test_move(...)` (`_has_room_to_stand`, `PlayerMovement.gd:253-257`).

## Camera effect style

Camera effects are **derived from simulation state each physics tick**, never
driven by animation or tween nodes. Add new effects in `_update_slide_camera`
(or a sibling `_update_*` called from `_physics_process`) and keep them
`move_toward`-smoothed:

- **FOV punch**: `_camera.fov = GlobalSettings.field_of_view - slide_camera_fov_shrink * _slide_pose`.
  Note: `slide_camera_fov_shrink` is `-30.0`, so despite the name/comment this
  *widens* FOV by 30° at full slide depth — a speed-rush effect. The base FOV
  always comes from `GlobalSettings.field_of_view` (70.0); never hardcode FOV.
- **Speed-weighted lean/roll**: `_update_slide_camera` only *computes* `_slide_roll`
  (grows with a `speed_weight` via `inverse_lerp` between
  `slide_camera_roll_slow_speed` (`4.0`) and `..._fast_speed` (`14.0`), scaled by
  `slide_camera_roll_degrees` (`4.0`) and `_slide_steer`, smoothed at
  `slide_camera_roll_speed` (`90°`/s). It does **not** write `rotation.z`.
- **Single roll application**: `_apply_camera_roll` is the *only* place that writes
  `_camera_holder.rotation.z`, combining every roll source so they layer instead of
  overwriting: `rotation.z = deg_to_rad(-(_slide_roll + _landing_kick))`. The negation
  means a positive roll degrees value banks the camera *right* (up vector tilts right).
- **Landing kick (Valve-style)**: `_start_landing_kick` sets `_landing_kick` to
  `landing_camera_kick_degrees` (`3.0`) on touchdown; `_update_landing_camera`
  integrates a damped spring (`landing_camera_kick_stiffness` `200`,
  `landing_camera_kick_damping` `28`) back toward centre. It is layered on top of the
  slide roll through `_apply_camera_roll`.
- **Camera drop**: `slide_camera_drop_ratio` (`1.0`) = camera follows the full body sink.
- General pattern for a new effect: an `@export_group(...)` variable, a
  `move_toward(current, target, speed * delta)` smooth into a state field, then write
  the node transform in the appropriate `_apply_*` function (`_apply_camera_roll`
  for roll). Never write the same property from two places.

Look is separate: `PlayerLook.gd` consumes `InputEventMouseMotion` only while
`GlobalSettings.pointer_locked`, applies `GlobalSettings.mouse_sensitivity`
(`0.0025`) to yaw, and to pitch with optional `invert_mouse_y` sign flip. Add new
input-driven camera behaviour there; add state-driven effects in `PlayerMovement`.

## Audio style

Audio is node-based: every sound gets its own `AudioStreamPlayer3D` wired in
`player.tscn` with its stream assigned, referenced by an exported `NodePath` on
`PlayerMovement`. Optional sources are fetched with `get_node_or_null` and
null-checked. One-shots and loops use **separate players** so a one-shot never
cuts off a loop. An `AudioListener3D` sits on the `Camera holder`. Streams are
assigned in the scene, never `load()`ed in code; a looping import sets
`edit/loop_mode` in the `.import` (enum: `0` detect, `1` disabled, `2` forward).

- **Slide loop** (`PlayerSoundSource`, `_update_slide_audio`, `PlayerMovement.gd:301`):
  a looping friction WAV. Playback is gated by a `_sound_fade` envelope
  (`move_toward` toward `1` while `_sliding` else `0`, at `slide_audio_fade_speed`);
  the player starts when the fade becomes audible and stops at silence. Pitch and
  volume rise with horizontal speed via
  `inverse_lerp(slide_audio_slow_speed, slide_audio_fast_speed, _horizontal_speed())`:
  pitch `slide_audio_min_pitch`→`slide_audio_max_pitch`, volume
  `slide_audio_quiet_db`→`slide_audio_loud_db` plus `linear_to_db(_sound_fade)`.
- **Landing one-shot** (`LandingSoundSource`, `_update_landing` / `_play_landing`,
  `PlayerMovement.gd:333`): fired on the airborne→floor edge via `_was_on_floor`
  (initialised `true` so spawning on the floor does not fire). Pitch is `1.0` plus
  `landing_slide_pitch_bonus` when `_slide_buffer > 0` (a landing that turns into a
  slide), plus `randf_range(-landing_pitch_variation, landing_pitch_variation)`.

The landing sound and the landing camera kick are both fired from the same
`_update_landing` edge check, so they stay in sync.

## When adding a feature

1. Put a new tunable in the right `@export_group` with a precise default.
2. Compute state in a `_update_*` helper and call it from `_physics_process` in
   the established order.
3. Smooth toward targets with `move_toward(..., speed * delta)`; convert any
   per-tick constant with `pow(v, delta * TICKS_PER_SECOND)`. For springy kicks,
   integrate a stiffness/damping spring into a state field instead.
4. **Write each node property from exactly one function.** Accumulate layered
   effects into state fields, then combine them in a single `_apply_*` step
   (`_apply_camera_roll` owns `rotation.z`; `_set_pose_geometry` owns body/camera
   offsets). Never write the same property from two places.
5. Apply transforms to the same nodes the project already uses (player = yaw,
   holder = pitch/roll/drop, Camera3D = FOV only); use separate audio players for
   separate sounds.
6. Expose runtime state in `_log_inputs` only if useful for tuning.
