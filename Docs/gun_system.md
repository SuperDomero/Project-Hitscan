# Weapon System Principles

Design principles for structuring a gun/weapon system. These are
implementation-independent rules, not a description of a particular project or
its tuning values.

---

## 1. Separate orchestration, presentation, and state

A weapon system has three distinct concerns and each belongs to its own owner:

| Concern | Responsibility | Must not do |
| --- | --- | --- |
| **Orchestration** | Read input, own the weapon list, coordinate switching, relay events | Know ammo rules or pose math |
| **Presentation** | Animate the viewmodel, expose readability queries, gate based on player context | Own ammo or fire cadence |
| **Per-weapon state** | Ammo, reload, cadence, animation gating, per-weapon tuning | Read input or touch the camera |

When these are mixed, changing a visual effect can accidentally change gameplay,
and adding a weapon requires editing unrelated code.

---

## 2. One owner per piece of state

- Every mutable value has exactly one writer.
- Aim state and recoil state must never share a writer.
- Presentation transforms are derived, not authoritative.
- If two systems need to agree on a value, one owns it and the other reads it.

**Rule:** if you cannot point to the single function that changes a value, the
ownership is wrong.

---

## 3. Gate before mutating

A request to fire is a proposal, not a command. Validate the full chain of
preconditions first, then mutate.

> No ammo, animation, sound, flash, recoil, or event may occur unless every gate
> passed.

This prevents the classic bug where a blocked shot still consumes a round or
plays a muzzle flash.

---

## 4. Centralize input

- Poll gameplay input in one place, at one layer.
- Downstream systems expose intent-based methods (`try_fire`, `switch_to`), not
  input checks.
- Input edges belong to orchestration; state machines belong to gameplay.
- Context gating (menu open, pointer unlocked, dialogue, death) belongs at the
  input boundary, before any gameplay method is called.

This keeps gameplay callable from tests, AI, or replays without simulating
devices.

---

## 5. Explicit state machines over boolean soup

Prefer a small named state enum over multiple interacting booleans.

- Orchestration: ready vs. transitioning.
- Player context: grounded, airborne, sliding, landing, idle.
- Weapon: ready, reloading, cycling.

Rules:

- Transitions are explicit and centralized.
- A state that blocks an action says so in one query method.
- Derived states are recomputed from authoritative sources, not stored twice.
- A transition is atomic: no half-switched state is observable.

---

## 6. Deterministic update order

Order frames so facts settle before they are consumed:

1. Input polling.
2. Gameplay state changes (fire, reload, switch).
3. Derived state (walk state, gating queries).
4. Presentation (pose, camera effects, HUD).
5. Effects (audio, particles).

Use explicit process priorities or a documented update sequence. Without a fixed
order, results become frame-rate and scene-tree-order dependent.

---

## 7. Communicate through events, not cross-references

- Signals/events describe facts in the past tense: `fired`, `ammo_changed`,
  `reload_started`.
- Publishers do not know their listeners.
- Observers subscribe to the layer that owns the fact.
- Relays must filter to the active entity so background entities do not trigger
  active-entity feedback.
- Never let an observer write back into the publisher's state.

This keeps recoil, HUD, audio, and analytics independently removable.

---

## 8. Gate closest to what it protects

Each condition should live with the state it depends on:

| Gate type | Lives with | Examples |
| --- | --- | --- |
| Input edge | Orchestration | new press, not held |
| Context | Player/presentation | sliding, landing, menu open |
| Lifecycle | Orchestration | switching, equipped |
| Resource | Weapon | ammo available |
| Cadence | Weapon | rate limit, animation still playing |
| Presentation | Weapon/component | required animation or rig present |

The orchestration layer may consult other layers' queries, but it must not
duplicate their rules.

---

## 9. Presentation derives from state

- The viewmodel, HUD, audio, and camera effects are all *views* of gameplay
  state.
- Presentation may lag, blend, or smooth; it must never be the source of truth.
- Recoil, sway, bob, and equip animations must not move the player's aim or
  collision state.
- Visual-only rotation belongs below the aim transform, never above it.
- HUD elements subscribe to state changes; they do not poll every frame.
- Effects are idempotent and bounded: replaying a flash or sound never changes
  gameplay.

---

## 10. Per-weapon data owns per-weapon behavior

- Tuning values (ammo capacity, cadence, reload duration, recoil profile,
  animation speed) live with the weapon, not in a global table or in the
  consumer.
- Consumers read the weapon's values when an event occurs.
- Global defaults exist only as fallbacks; each weapon may override them.
- Adding a weapon should be data + assets + components, not a new branch in a
  shared script.

**Rule:** no `if weapon == ...` logic. If a weapon needs different behavior,
express it as data or a component.

---

## 11. Keep components single-purpose

Split presentation into small, independently testable pieces:

- **Audio component** — owns its streams and players.
- **Muzzle-flash component** — owns particle lifetime and restart.
- **Recoil component** — owns the visual kick and its return.
- **HUD component** — owns formatting and display.

Each component should be removable without breaking the others. Choose
positional vs. non-positional audio based on where the source logically lives,
not on where a shared rig happens to be placed.

---

## 12. Lifecycle symmetry

- Equip and holster are inverses: reset pose, reset timers, reset effects.
- Hidden or holstered weapons still finish their independent timers.
- Reload state is per weapon and survives switching.
- A weapon that becomes empty may reload without changing which weapon is
  active.
- Reset transient flags on equip so a previous animation cannot block the next
  shot.

---

## 13. Switching is transactional

- Refuse a switch unless the system is in a ready state.
- Capture the current weapon, commit the new index, then transition the old and
  new weapons.
- Fire is blocked until the new weapon is presentation-ready.
- Emit the change notification only after both sides have transitioned.
- Repeated requests for the current weapon are no-ops.

---

## 14. Failure is silent to gameplay, visible to developers

- A blocked action returns a result; it does not throw, spam effects, or leave
  partial state.
- Missing optional components produce a warning once, not a crash.
- Missing required assets disable the feature predictably.
- Keep a dry-fire / empty path distinct from a successful fire.

---

## 15. Review checklist

Before merging weapon code, confirm:

- [ ] Each mutable value has one writer.
- [ ] Firing validates every gate before any side effect.
- [ ] A blocked shot changes no state and emits no success event.
- [ ] Input is read in one layer only.
- [ ] States are explicit, not boolean combinations.
- [ ] Update order is documented or enforced by priority.
- [ ] Presentation cannot modify aim, movement, or ammo.
- [ ] Per-weapon differences are data or components, not branches.
- [ ] Observers subscribe; publishers do not reach into observers.
- [ ] Equip and holster are symmetric.
- [ ] The system works without audio, HUD, or effects attached.
