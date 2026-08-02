class_name PersonaProfile
extends Resource
## A behavioral persona: who this shell thinks it is, how it talks, and the
## exact boundary of what it knows.
##
## The offline kernel reads this directly. The optional LLM backend receives
## `persona_prompt` plus the *revealed* knowledge items as its system prompt —
## never the full item list, so the model cannot leak what the character
## would not say.

@export_group("Identity")
@export var persona_id: StringName = &""
@export var display_name: String = ""
## One-word archetype for authoring and debugging ("fixer", "preacher").
@export var archetype: String = ""
## Character rig archetype: fixer / vendor / preacher / urchin / warden.
@export var rig_archetype: StringName = &"fixer"
@export var rig_height: float = 1.8
@export var rig_bulk: float = 1.0
## Name colour in dialogue and on the bark label.
@export var name_color: Color = Color(0.0, 0.898, 1.0)
## Body tint so silhouettes stay distinct at blockout fidelity.
@export var body_tint: Color = Color(0.16, 0.18, 0.26)

@export_group("Behavior")
## The behavioral persona prompt: temperament, loyalties, speech rhythm, and
## what the character wants. Fed verbatim to the LLM backend; the offline
## kernel uses it only for tone documentation.
@export_multiline var persona_prompt: String = ""
## First-meeting lines, in order. The kernel plays these before knowledge.
@export var greeting_lines: PackedStringArray = PackedStringArray()
## Said when asked about something outside this shell's knowledge. Deflections
## are content — they are how the world says no.
@export var deflect_lines: PackedStringArray = PackedStringArray()

@export_group("Knowledge")
## The complete boundary of what this character knows. Nothing outside this
## list exists for them.
@export var knowledge: Array[KnowledgeItem] = []
## Scopes this character actively refuses — they know OF the topic, and their
## refusal is itself information.
@export var forbidden_scopes: PackedStringArray = PackedStringArray()

@export_group("Pacing")
@export var bark_interval: float = 10.0
## How talkative the shell is when idle (0 = silent unless addressed).
@export_range(0.0, 1.0) var chattiness: float = 0.6


func _to_string() -> String:
	return "PersonaProfile<%s>" % persona_id
