class_name Quest
extends Resource
## A quest, as data.
##
## Quests live in `quests/main/` and `quests/side/` as `.tres` files. The quest
## system interprets them; only genuinely unique set-piece behaviour gets a
## script, and it hangs off [member setpiece_script] rather than replacing this.
##
## Design contract for this project (see CLAUDE.md, "Vision and tone"): a quest
## with an obviously correct answer is not finished. [member outcomes] should
## always hold more than one entry, and none of them should be free.

@export_group("Identity")
## Stable identifier. Referenced by save data — never renamed after shipping.
@export var id: StringName = &""
@export var title: String = ""
## One-line noir logline, for the journal header.
@export_multiline var logline: String = ""
## Longer briefing shown when the quest is accepted.
@export_multiline var briefing: String = ""

@export_group("Placement")
@export var is_side_quest: bool = false
## Which act this belongs to; 0 for side content that is always available.
@export_range(0, 4) var act: int = 0
@export var giver_id: StringName = &""
@export var district_id: StringName = &""
## Suggested player level. Advisory — the world does not level-scale.
@export var recommended_level: int = 1

@export_group("Structure")
@export var objectives: Array[QuestObjective] = []
## All of these world flags must be set before the quest can be offered.
@export var prerequisite_flags: Array[StringName] = []
## Flags set when the quest completes, keyed by the outcome that was taken.
@export var flags_on_complete: Array[StringName] = []
## Mutually exclusive with any quest listed here — taking this locks those out.
@export var locks_out: Array[StringName] = []

@export_group("Outcomes")
## Each entry is an ending the player can reach. Two or more, always.
@export var outcomes: Array[StringName] = []
## Free-form author notes on what each outcome costs. Not shown in game.
@export_multiline var outcome_notes: String = ""

@export_group("Advanced")
## Optional script for set-piece behaviour this data model cannot express.
@export var setpiece_script: Script = null


func is_available(world_flags: Dictionary) -> bool:
	for flag in prerequisite_flags:
		if not world_flags.get(flag, false):
			return false
	return true


func required_objectives() -> Array[QuestObjective]:
	return objectives.filter(func(o: QuestObjective) -> bool: return not o.optional)


## Authoring guard — surfaced by tooling, not enforced at runtime.
func design_warnings() -> Array[String]:
	var warnings: Array[String] = []
	if id == &"":
		warnings.append("quest has no id")
	if objectives.is_empty():
		warnings.append("quest '%s' has no objectives" % id)
	if outcomes.size() < 2:
		warnings.append(
			"quest '%s' has %d outcome(s); the tone rules ask for a choice with a price"
			% [id, outcomes.size()]
		)
	return warnings


func _to_string() -> String:
	return "Quest<%s>" % id
