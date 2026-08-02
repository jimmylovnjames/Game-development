class_name QuestSystem
extends Node
## Interprets Quest resources. Quests stay data; this node tracks which ones are
## active, which objectives are done, and which outcome was taken.
##
## Objectives never contain their own logic — callers report events
## (`notify_talked`, `notify_reached`, …) and this matches them against the
## active quest list by kind + target_id.

signal quest_started(quest: Quest)
signal quest_completed(quest: Quest, outcome: StringName)
signal objective_completed(quest: Quest, objective: QuestObjective)

const MQ01_PATH := "res://quests/main/mq01_the_transit_pass.tres"

@export var auto_start_mq01: bool = true

var flags: WorldFlags

## quest_id -> { "quest": Quest, "done": Dictionary[StringName, bool], "outcome": StringName }
var _active: Dictionary = {}
var _completed: Dictionary = {}  # quest_id -> outcome


func _ready() -> void:
	if auto_start_mq01:
		call_deferred("_boot_mq01")


func _boot_mq01() -> void:
	var quest := load(MQ01_PATH) as Quest
	if quest != null:
		start_quest(quest)


func start_quest(quest: Quest) -> bool:
	if quest == null or quest.id == &"":
		return false
	if _active.has(quest.id) or _completed.has(quest.id):
		return false
	if flags != null and not quest.is_available(flags.get_all()):
		return false
	_active[quest.id] = {
		"quest": quest,
		"done": {},
		"outcome": &"",
	}
	quest_started.emit(quest)
	print("[QuestSystem] started '%s'" % quest.id)
	return true


func notify_talked(npc_id: StringName) -> void:
	_match(QuestObjective.Kind.TALK, npc_id)


func notify_reached(trigger_id: StringName) -> void:
	_match(QuestObjective.Kind.REACH, trigger_id)


func notify_flag(flag_id: StringName) -> void:
	_match(QuestObjective.Kind.FLAG, flag_id)


func is_objective_done(quest_id: StringName, objective_id: StringName) -> bool:
	if not _active.has(quest_id):
		return _completed.has(quest_id)
	return bool(_active[quest_id]["done"].get(objective_id, false))


## Which outcome a finished quest ended on, or &"" if it is not finished.
## The world needs this to keep showing the consequence after the fact.
func get_outcome(quest_id: StringName) -> StringName:
	return _completed.get(quest_id, &"")


func is_quest_completed(quest_id: StringName) -> bool:
	return _completed.has(quest_id)


func get_active_quests() -> Array[Quest]:
	var out: Array[Quest] = []
	for entry: Dictionary in _active.values():
		out.append(entry["quest"])
	return out


func get_journal_lines() -> PackedStringArray:
	var lines: PackedStringArray = []
	for entry: Dictionary in _active.values():
		var quest: Quest = entry["quest"]
		var done: Dictionary = entry["done"]
		lines.append(quest.title)
		for objective in quest.objectives:
			if objective.hidden and not done.get(objective.id, false):
				continue
			var mark := "x" if done.get(objective.id, false) else " "
			var optional := " (optional)" if objective.optional else ""
			lines.append("  [%s] %s%s" % [mark, objective.description, optional])
	return lines


func complete_quest(quest_id: StringName, outcome: StringName) -> void:
	if not _active.has(quest_id):
		return
	var entry: Dictionary = _active[quest_id]
	var quest: Quest = entry["quest"]
	_active.erase(quest_id)
	_completed[quest_id] = outcome
	if flags != null:
		for flag in quest.flags_on_complete:
			flags.set_flag(flag, true)
	quest_completed.emit(quest, outcome)
	print("[QuestSystem] completed '%s' via '%s'" % [quest_id, outcome])


func _match(kind: QuestObjective.Kind, target_id: StringName) -> void:
	for quest_id: StringName in _active.keys():
		var entry: Dictionary = _active[quest_id]
		var quest: Quest = entry["quest"]
		var done: Dictionary = entry["done"]
		for objective in quest.objectives:
			if done.get(objective.id, false):
				continue
			if objective.kind != kind:
				continue
			if objective.target_id != target_id:
				continue
			done[objective.id] = true
			objective_completed.emit(quest, objective)
			# Convention: a completed objective id doubles as a world flag, so
			# persona knowledge can gate on story beats without extra wiring.
			if flags != null:
				flags.set_flag(objective.id, true)
			print("[QuestSystem] objective '%s' done on '%s'" % [objective.id, quest.id])
			_try_auto_complete(quest_id)
			return


## When every required objective is done and the quest only has one remaining
## choice path still open, leave it active — outcomes need a player decision.
## Auto-complete is reserved for tests that force an outcome.
func _try_auto_complete(_quest_id: StringName) -> void:
	pass
