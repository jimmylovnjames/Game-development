class_name KnowledgeItem
extends Resource
## One thing an NPC knows — a fact, a rumor, a price, a refusal.
##
## Knowledge is the unit of "limited knowledge": an NPC's world is exactly the
## items listed in their PersonaProfile, gated further by world flags and
## disposition. What a character does not have here, they cannot say — which is
## how the world explains itself through refusals instead of codex dumps.

@export var id: StringName = &""
## The fact in the character's voice. One or two sentences, spoken register.
@export_multiline var text: String = ""
## Topic tags this item answers to ("scrap", "spine_gate", "syndicate", …).
@export var scopes: PackedStringArray = PackedStringArray()
## Only surfaced once this world flag is set. Empty means always available.
@export var requires_flag: StringName = &""
## World flag set on the player hearing this — knowledge has consequences.
@export var grants_flag: StringName = &""
## Below this disposition the item stays behind the character's teeth.
@export_range(0.0, 1.0) var min_disposition: float = 0.0
## Once-only items are consumed after being told, like a good rumor.
@export var once_only: bool = false


func _to_string() -> String:
	return "KnowledgeItem<%s>" % id
