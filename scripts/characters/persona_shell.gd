class_name PersonaShell
extends Interactable
## An NPC shell: a body, a PersonaProfile, and a voice.
##
## Two ways to speak, picked per conversation:
##   1. Offline kernel (always available): deterministic seeded selection over
##      the profile's knowledge, gated by world flags and disposition. This is
##      the guarantee that the world talks even with no network and no key.
##   2. LLM backend (optional, see NpcLlmBackend): the persona prompt plus the
##      *currently revealed* knowledge items become a system prompt; the reply
##      is sanitized before it ever reaches the UI. Any failure falls back to
##      the kernel mid-conversation.
##
## Quest-critical dialogue (Vex in MQ01) stays fully scripted on NpcVex — the
## noir cost structure is not something to improvise.

signal spoke(line: String)

@export var profile: PersonaProfile
## How warm the shell is to the courier right now. Quests and gifts move this.
@export_range(0.0, 1.0) var disposition: float = 0.5

var _rng := RandomNumberGenerator.new()
var _dialogue: DialogueUI = null
var _flags: WorldFlags = null
var _backend: NpcLlmBackend = null
var _talk_count: int = 0
var _consumed: Dictionary = {}  # KnowledgeItem.id -> true
var _bark_label: Label3D = null
var _bark_timer: float = 0.0
var _bark_show_left: float = 0.0
var _llm_pending: bool = false


func _ready() -> void:
	super._ready()
	add_to_group("persona_shells")
	if profile == null:
		push_warning("[PersonaShell] %s has no profile" % name)
		return
	interactable_id = profile.persona_id
	prompt = "Talk to %s" % profile.display_name
	collision_layer = 8 | 16  # npc | interactable
	collision_mask = 1  # world
	# Deterministic voice per persona per world seed.
	_rng.seed = hash(String(profile.persona_id)) + 20771113
	_bark_timer = _rng.randf_range(2.0, profile.bark_interval)
	_bark_label = get_node_or_null("BarkLabel") as Label3D
	if _bark_label != null:
		_bark_label.visible = false
		_bark_label.modulate = profile.name_color
	_apply_tint()


func _apply_tint() -> void:
	var mesh := get_node_or_null("Mesh") as MeshInstance3D
	if mesh == null or profile == null:
		return
	var material := mesh.get_surface_override_material(0) as ShaderMaterial
	if material == null:
		material = mesh.get_active_material(0) as ShaderMaterial
	if material == null:
		return
	material = material.duplicate() as ShaderMaterial
	material.set_shader_parameter("albedo_color", profile.body_tint)
	material.set_shader_parameter("rim_color", profile.name_color)
	mesh.set_surface_override_material(0, material)


func bind(dialogue: DialogueUI, flags: WorldFlags, backend: NpcLlmBackend) -> void:
	_dialogue = dialogue
	_flags = flags
	_backend = backend


func _process(delta: float) -> void:
	if profile == null:
		return
	_update_barks(delta)


func _on_interact(who: Node3D) -> void:
	if _dialogue == null or profile == null:
		return
	if _dialogue.is_active() or _llm_pending:
		return
	_hide_bark()

	if _backend != null and _backend.is_active():
		_talk_via_llm(who)
		return

	var lines := compose_lines()
	if lines.is_empty():
		return
	_talk_count += 1
	_dialogue.open(profile.persona_id, profile.display_name, lines)
	_dialogue.set_speaker_color(profile.name_color)
	for line in lines:
		spoke.emit(line)


## Kernel path: greetings on first contact, then knowledge within scope, then
## deflections. Deterministic given the persona seed + talk count.
func compose_lines() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	if _talk_count == 0 and not profile.greeting_lines.is_empty():
		out.append_array(profile.greeting_lines)
		return out

	var revealed := revealed_knowledge()
	if not revealed.is_empty():
		var item: KnowledgeItem = revealed[_rng.randi() % revealed.size()]
		out.append(item.text)
		if item.once_only:
			_consumed[item.id] = true
		if item.grants_flag != &"" and _flags != null:
			_flags.set_flag(item.grants_flag, true)
		return out

	out.append(_deflect_line())
	return out


## Knowledge the shell is willing to surface right now.
func revealed_knowledge() -> Array[KnowledgeItem]:
	var out: Array[KnowledgeItem] = []
	for item in profile.knowledge:
		if _is_revealed(item):
			out.append(item)
	return out


func _is_revealed(item: KnowledgeItem) -> bool:
	if _consumed.get(item.id, false):
		return false
	if disposition < item.min_disposition:
		return false
	if item.requires_flag != &"":
		if _flags == null or not _flags.has_flag(item.requires_flag):
			return false
	return true


## Direct topic probe — the dialogue system's "ask about X" hook and the soak
## test's way to assert knowledge boundaries without driving the UI.
func answer_about(topic: StringName) -> Dictionary:
	if topic in profile.forbidden_scopes:
		return {"text": _deflect_line(), "deflected": true}
	for item in profile.knowledge:
		if not (topic in item.scopes):
			continue
		if not _is_revealed(item):
			continue
		if item.once_only:
			_consumed[item.id] = true
		if item.grants_flag != &"" and _flags != null:
			_flags.set_flag(item.grants_flag, true)
		return {"text": item.text, "deflected": false}
	return {"text": _deflect_line(), "deflected": true}


func _deflect_line() -> String:
	if profile.deflect_lines.is_empty():
		return "..."
	return profile.deflect_lines[_rng.randi() % profile.deflect_lines.size()]


## --- LLM path -------------------------------------------------------------

func _talk_via_llm(_who: Node3D) -> void:
	_llm_pending = true
	_dialogue.open(profile.persona_id, profile.display_name, PackedStringArray(["…"]))
	_dialogue.set_speaker_color(profile.name_color)
	_talk_count += 1

	var system := build_llm_system_prompt()
	var user := "The courier stops and waits for you to speak first."
	_backend.request_completion(system, user, _on_llm_response)


func build_llm_system_prompt() -> String:
	var facts: PackedStringArray = PackedStringArray()
	for item in revealed_knowledge():
		facts.append("- %s" % item.text)
	if facts.is_empty():
		facts.append("- Nothing you are willing to share today.")

	var refusals := ""
	if not profile.forbidden_scopes.is_empty():
		refusals = "\nYou refuse to discuss: %s. Refuse in character." % ", ".join(
			profile.forbidden_scopes
		)

	return "%s\n\nYou know ONLY these facts:\n%s%s\n\nRules: answer as %s in at most two short sentences. Never mention being an AI or a game. Never invent facts outside the list. If asked about anything beyond your knowledge, deflect in character." % [
		profile.persona_prompt,
		"\n".join(facts),
		refusals,
		profile.display_name,
	]


func _on_llm_response(raw: String) -> void:
	_llm_pending = false
	if _dialogue == null:
		return
	var cleaned := sanitize_llm_response(raw)
	if cleaned.is_empty():
		# Backend failed or refused: the kernel takes over mid-conversation.
		var fallback := compose_lines()
		if fallback.is_empty():
			fallback = PackedStringArray([_deflect_line()])
		_dialogue.replace_lines(fallback)
		for line in fallback:
			spoke.emit(line)
		return
	_dialogue.replace_lines(PackedStringArray([cleaned]))
	spoke.emit(cleaned)


## Strip the failure modes out of a free model: stage directions, quotes,
## markdown, run-ons. Anything left is capped at two sentences.
func sanitize_llm_response(raw: String) -> String:
	var text := raw.strip_edges()
	if text.is_empty():
		return ""
	# No roleplay asterisks, no markdown headers, no leading name tags.
	var banned := ["*", "#", "```", profile.display_name + ":"]
	for token in banned:
		text = text.replace(token, "")
	text = text.strip_edges().trim_prefix("\"").trim_suffix("\"")
	# Two sentences max, 280 chars max.
	var sentence_end := 0
	var count := 0
	for i in text.length():
		if text[i] in [".", "!", "?", "…"]:
			count += 1
			sentence_end = i + 1
			if count >= 2:
				break
	if count >= 2:
		text = text.substr(0, sentence_end)
	if text.length() > 280:
		text = text.substr(0, 280)
	return text.strip_edges()


## --- Ambient barks ---------------------------------------------------------

func _update_barks(delta: float) -> void:
	if _bark_show_left > 0.0:
		_bark_show_left -= delta
		if _bark_show_left <= 0.0:
			_hide_bark()
		return
	if _dialogue != null and _dialogue.is_active():
		return
	if profile.chattiness <= 0.0 or _bark_label == null:
		return

	_bark_timer -= delta
	if _bark_timer > 0.0:
		return
	_bark_timer = profile.bark_interval * _rng.randf_range(0.7, 1.4)
	if _rng.randf() > profile.chattiness:
		return

	var player := get_tree().get_first_node_in_group("player")
	if player != null and global_position.distance_to(player.global_position) > 14.0:
		return

	var line := _bark_line()
	if line.is_empty():
		return
	_bark_label.text = line
	_bark_label.visible = true
	_bark_show_left = 3.5
	spoke.emit(line)


func _bark_line() -> String:
	# Idle chatter leans on cheap knowledge (no flag gates), then greetings the
	# courier never heard, then deflections as grumbles.
	var cheap: Array[KnowledgeItem] = []
	for item in profile.knowledge:
		if item.requires_flag == &"" and item.min_disposition <= 0.3 and not item.once_only:
			cheap.append(item)
	if not cheap.is_empty() and _rng.randf() < 0.6:
		return cheap[_rng.randi() % cheap.size()].text
	if _talk_count == 0 and not profile.greeting_lines.is_empty() and _rng.randf() < 0.4:
		return profile.greeting_lines[_rng.randi() % profile.greeting_lines.size()]
	return _deflect_line()


func _hide_bark() -> void:
	_bark_show_left = 0.0
	if _bark_label != null:
		_bark_label.visible = false
