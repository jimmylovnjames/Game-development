# Task list — Grok 4.5: quest, dialogue and world-flag runtime

Branch to work from: `claude/godot-cyberpunk-rpg-setup-xqy75h` (commit `9b4a8e3`
or later). **Read [CLAUDE.md](../CLAUDE.md) first** — the tone rules and the
architecture rules in it are binding, not suggestions.

---

## Scope and why it is scoped this way

Another agent is working this repo in parallel, most likely on world generation.
This slice is chosen so the two lines of work do not touch the same files.

**Yours.** The runtime that turns `Quest` `.tres` data into playable content:
flags, objective tracking, dialogue, the journal, and the tests for all of it.

**Not yours — do not edit:**

```
shaders/                              scripts/world/district_blockout.gd
assets/materials/                     tools/screenshot.gd
scenes/main.tscn  (WorldEnvironment, Moonlight, World/*)
worlds/                               scripts/player/player_controller.gd
```

If you need a hook in the player, add it by **connecting to an existing signal**
(`interactable_changed`, `interacted`, `landed`), not by editing the controller.
If a genuinely new signal is needed, say so rather than adding it yourself.

You may add to `scenes/main.tscn` only by appending new child nodes under a new
`Systems` node. Do not touch existing nodes there.

---

## Ground rules

- **Godot 4.7.1**, GDScript, tabs, static types wherever the parser allows.
- **After adding any `class_name`, run `godot --headless --path . --import`.**
  Otherwise scenes silently instantiate *without their script attached* —
  `instantiate()` still returns a node, so this fails quietly. Assert
  `get_script() != null` in tests.
- **Do not hand-edit the `[input]` block of `project.godot`.** Add actions in
  `tools/setup_project_settings.gd` and re-run it; the
  `Object(InputEventKey, …)` encoding is version-specific.
- **Poll physics-critical input** in `_physics_process` via
  `Input.is_action_just_pressed`, never only `_unhandled_input` — otherwise
  `Input.action_press()` cannot drive it and the headless tests can't reach it.
- **Quests are data.** Logic lives in the interpreter, not in the `.tres`.
- **Comments explain why, not what.**
- Every task below must leave `tools/verify_setup.gd` and `tools/soak_test.gd`
  green.

---

## Task 1 — World flag store and save/load

**Files:** `scripts/systems/world_state.gd`, autoload entry in `project.godot`.

World flags outlive every scene, so this is one of the few things that earns an
autoload (CLAUDE.md: "add an autoload only when something genuinely must outlive
every scene").

- `set_flag(name: StringName, value: Variant)`, `get_flag(name, default)`,
  `has_flag(name)`, `clear()`.
- `signal flag_changed(name: StringName, value: Variant)`.
- Save to `user://save_%d.cfg` via `ConfigFile`, with an explicit
  `save_version: int` field and a migration hook. A save that cannot be migrated
  must fail loudly, never silently load half a world.
- Store the world generator seed alongside the flags — CLAUDE.md requires
  deterministic generation to be reproducible from a save.

**Acceptance:** round-trip test — set flags, save, `clear()`, load, assert equal.

---

## Task 2 — Quest log runtime

**Files:** `scripts/quests/quest_log.gd`.

Interprets the existing `Quest` / `QuestObjective` resources
(`scripts/quests/quest.gd`). Read them before designing anything.

- Discover all `.tres` under `res://quests/` at boot; validate each with
  `Quest.design_warnings()` and push a warning for any that fail.
- `offer(quest_id)` / `accept(quest_id)` / `abandon(quest_id)`, gated on
  `Quest.is_available(world_flags)`.
- Track per-objective progress, including `required_count` for counted kinds.
- On completion: apply `flags_on_complete`, honour `locks_out`, and emit the
  chosen outcome.
- Signals: `quest_offered`, `quest_accepted`, `objective_progressed`,
  `objective_completed`, `quest_completed(quest_id, outcome)`.
- Serialise its own state through `WorldState` so quests survive save/load.

**Acceptance:** headless test drives `mq01_the_transit_pass` from offer to each
of its three outcomes and asserts the right flags land.

---

## Task 3 — Objective trackers

**Files:** `scripts/quests/trackers/*.gd`.

One small class per `QuestObjective.Kind` rather than a `match` statement that
grows forever. A tracker takes an objective, watches the world, and reports
progress back to the quest log.

Implement now: `REACH`, `FLAG`, `TALK`, `DELIVER`.
Stub with a clear interface: `ACQUIRE`, `ELIMINATE` — inventory and combat do
not exist yet. Define the signal they will listen for and leave a `TODO` naming
the system that must emit it. Do **not** invent an inventory system here.

- `REACH` binds to an `Area3D` on **physics layer 7 (trigger)** whose name
  matches `target_id`.
- Physics layers are named in `project.godot` — use the names, never bare masks.

---

## Task 4 — Dialogue as data

**Files:** `scripts/dialogue/dialogue_tree.gd`, `dialogue_line.gd`,
`dialogue_choice.gd`, plus one authored `.tres`.

Mirror the quest pattern exactly: `Resource` subclasses, `.tres` data, logic in
the interpreter.

- A line has a speaker id, text, and optional flag requirements to appear.
- A choice can require a flag, set a flag, complete an objective, or select a
  quest outcome.
- **Tone contract:** add an author-only `cost_note` field per choice, the way
  `Quest.outcome_notes` works. Extend the `design_warnings()` pattern to flag
  any dialogue node whose choices are all cost-free. Per CLAUDE.md: the player
  is handed a price list, not a right answer.
- Author the Vex conversation that opens `mq01_the_transit_pass` as the worked
  example. Keep it in the game's register — nobody explains the world, and Vex
  should refuse to say who bought the debt.

**Generate the `.tres` with a throwaway script run through
`godot --headless --script`, not by hand.** Typed arrays of custom resources
serialise as `Array[ExtResource("…")]` and are very easy to get wrong manually.

---

## Task 5 — Interactables and triggers

**Files:** `scripts/characters/npc_interactable.gd`,
`scenes/props/quest_trigger.tscn`, `scenes/characters/npc.tscn`.

The player already probes for these — do not modify it.

- Anything interactable exposes `interact(who)` and sits on **layer 5
  (interactable)**. The player's `InteractRay` finds it and emits
  `interactable_changed`.
- `quest_trigger.tscn` is an `Area3D` on **layer 7 (trigger)** exporting the
  `target_id` its `REACH` objective matches.
- `npc_interactable.gd` opens a `DialogueTree` on interact.

---

## Task 6 — Journal UI

**Files:** `scenes/ui/journal.tscn`, `scripts/ui/journal.gd`.

- Bound to the existing `journal` action (already mapped to `J`).
- Lists active quests: title, logline, objectives with completion state.
- `hidden` objectives stay hidden until started; `optional` ones are marked.
- UI reads state through signals; it never drives the quest log directly.
- Style per `docs/style_bible.md` — cyan on near-black, ink outlines on text.
  Neon is the only saturated thing on screen.

---

## Task 7 — Tests

**Files:** `tools/quest_test.gd`, plus a stage appended to `tools/soak_test.gd`.

Follow the existing pattern in `tools/verify_setup.gd` — `extends SceneTree`,
`_ok`/`_fail` accumulators, non-zero exit on failure.

- Load every quest and dialogue resource; assert zero design warnings.
- Drive `mq01` to each of its three outcomes; assert flags and lockouts.
- Save/load round-trip mid-quest; assert progress survives.
- Extend `tools/verify_setup.gd`'s `_check_quests()` to cover dialogue too.

**Definition of done for the whole slice:**

```bash
godot --headless --path . --import
godot --headless --path . --script tools/verify_setup.gd   # all checks passed
godot --headless --path . --script tools/soak_test.gd      # all stages passed
godot --headless --path . --script tools/quest_test.gd     # all stages passed
```

---

## Things that will bite you

- `class_name` types do not resolve until the class cache is rebuilt. See the
  rule above; it is the single most common way to lose an hour here.
- `instantiate()` succeeds on a scene whose script failed to parse. Always
  assert `get_script() != null`.
- Godot serialises typed `Array[CustomResource]` in a form that is impractical
  to author by hand. Generate `.tres` through the engine.
- `Input.action_press()` does not synthesise an `InputEvent`, so anything read
  only in `_unhandled_input` is unreachable from tests.

## Open question for Jimmy

This split assumes the parallel agent is on world generation. If it is actually
on quests or UI, say so before starting — Tasks 2, 5 and 6 would collide head-on
and should be re-cut.
