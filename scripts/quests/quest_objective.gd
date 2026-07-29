class_name QuestObjective
extends Resource
## A single step in a [Quest].
##
## Objectives are pure data. The quest system reads [member kind] and
## [member target_id] and decides how to track progress — an objective never
## contains its own logic. That keeps quests diffable, hot-reloadable, and
## authorable by someone who does not touch engine code.

enum Kind {
	REACH,      ## Enter the trigger volume named target_id.
	ACQUIRE,    ## Hold required_count of item target_id.
	ELIMINATE,  ## Defeat required_count of actor archetype target_id.
	TALK,       ## Complete a dialogue with NPC target_id.
	DELIVER,    ## Give item target_id to NPC named in deliver_to.
	FLAG,       ## Wait for world flag target_id to be set.
	CUSTOM,     ## Handled by a set-piece script; see the quest's notes.
}

## Stable identifier. Referenced by save data — never renamed after shipping.
@export var id: StringName = &""
## Shown in the journal. Written in the player character's voice.
@export_multiline var description: String = ""
@export var kind: Kind = Kind.REACH
## Meaning depends on `kind`: a trigger name, item id, archetype or flag.
@export var target_id: StringName = &""
@export var required_count: int = 1
@export var deliver_to: StringName = &""

@export_group("Presentation")
## Optional objectives are real content, not filler — they should change an
## outcome, not just add loot.
@export var optional: bool = false
## Hidden objectives only appear in the journal once started. Use for reveals.
@export var hidden: bool = false
## Marker shown in the world, if any.
@export var marker_position: Vector3 = Vector3.ZERO
@export var has_marker: bool = false


func is_counted() -> bool:
	return kind in [Kind.ACQUIRE, Kind.ELIMINATE]


func _to_string() -> String:
	return "QuestObjective<%s:%s>" % [id, Kind.keys()[kind]]
