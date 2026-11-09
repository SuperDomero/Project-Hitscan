class_name GlobalSettings
extends RefCounted

static var pointer_locked := false

static var mouse_sensitivity: float = 0.0025
static var invert_mouse_y := false
static var field_of_view: float = 80.0

## Two-frame mouse smoothing: each raw delta is applied half this frame and half
## next frame. This preserves total sensitivity while softening per-frame spikes.
static var mouse_smoothing_enabled := true

static var _raw_mouse_delta := Vector2.ZERO
static var _previous_mouse_delta := Vector2.ZERO


## Queues raw mouse motion for the current frame. Call this from input handling
## instead of applying the motion immediately.
static func feed_mouse_motion(relative: Vector2) -> void:
	_raw_mouse_delta += relative


## Returns the motion to apply this frame. Call this exactly once per frame, from
## _process or later, so the previous frame's half of the delta is carried over.
static func consume_mouse_motion() -> Vector2:
	if not mouse_smoothing_enabled:
		var delta := _raw_mouse_delta
		_raw_mouse_delta = Vector2.ZERO
		_previous_mouse_delta = Vector2.ZERO
		return delta

	var smoothed := (_raw_mouse_delta + _previous_mouse_delta) * 0.5
	_previous_mouse_delta = _raw_mouse_delta
	_raw_mouse_delta = Vector2.ZERO
	return smoothed


## Drops any queued or carried-over motion, so stale deltas are not applied after
## the pointer is locked or unlocked.
static func reset_mouse_smoothing() -> void:
	_raw_mouse_delta = Vector2.ZERO
	_previous_mouse_delta = Vector2.ZERO


static func set_pointer_locked(locked: bool) -> void:
	pointer_locked = locked
	reset_mouse_smoothing()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED if locked else Input.MOUSE_MODE_VISIBLE)


static func toggle_pointer_lock() -> void:
	set_pointer_locked(not pointer_locked)
