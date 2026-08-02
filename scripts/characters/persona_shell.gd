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
## Fired when this shell passes a knowledge item to anyone — the gossip
## network writes it into circulation.
signal knowledge_shared(item: KnowledgeItem, source: PersonaShell)

## Once the courier takes Vex's pass, the warden stops pacing and starts
## watching. One scripted beat, hung off the flag QuestSystem already sets for
## every completed objective — no new system, no new wiring.
const WATCH_FLAG := &"talk_to_vex"
const WATCH_ARCHETYPE := &"warden"
const WATCH_LINE := "Off duty. Not off watch. Not since you took that."
const WATCH_BARK_SECONDS := 7.0

## Inside this radius a shell stops wandering and turns to the courier. Also the
## arbiter between gait and facing: only one of them steers rotation.y at a time.
const FACE_RADIUS := 6.5

@export var profile: PersonaProfile
## How warm the shell is to the courier right now. Quests and gifts move this.
@export_range(0.0, 1.0) var disposition: float = 0.5

var _rng := RandomNumberGenerator.new()
var _dialogue: DialogueUI = null
var _flags: WorldFlags = null
var _backend: NpcLlmBackend = null
var _talk_count: int = 0
var _consumed: Dictionary = {}  # KnowledgeItem.id -> true
var _hearsay: Array[String] = []
var _bark_label: Label3D = null
var _bark_timer: float = 0.0
var _bark_show_left: float = 0.0
var _llm_pending: bool = false
var _rig: Node3D = null
var _idle_time: float = 0.0
var _look_target: Node3D = null

var _gait: Dictionary = {}
var _home := Vector3.ZERO
var _patrol_axis := Vector3.FORWARD
var _wander_target := Vector3.ZERO
var _hold_left: float = 0.0
var _moving: bool = false
var _stride_phase: float = 0.0
var _stride_amount: float = 0.0
var _orbit_angle: float = 0.0
var _orbit_dir: float = 1.0
var _watching: bool = false
## Interactable's base is CollisionObject3D, so the body API is not statically
## visible even though persona_shell.tscn roots at CharacterBody3D. A shell
## attached to something else simply does not wander.
var _body: CharacterBody3D = null


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
	_idle_time = _rng.randf_range(0.0, 10.0)
	_init_wander()
	_build_rig()
	_bark_label = get_node_or_null("BarkLabel") as Label3D
	if _bark_label != null:
		_bark_label.visible = false
		_bark_label.modulate = profile.name_color
		_bark_label.position.y = profile.rig_height + 0.45


func _build_rig() -> void:
	# Palette comes from the archetype defaults unless the profile overrides it.
	var palette := PackedColorArray()
	if profile.body_tint != Color(0.16, 0.18, 0.26):
		palette = CharacterBuilder.PALETTES.get(
			profile.rig_archetype, CharacterBuilder.PALETTES[&"fixer"]
		).duplicate()
		palette[0] = profile.body_tint
		palette[1] = profile.name_color
		palette[3] = profile.name_color
	_rig = CharacterBuilder.build(
		profile.rig_archetype, profile.rig_height, profile.rig_bulk, palette
	)
	add_child(_rig)


func bind(dialogue: DialogueUI, flags: WorldFlags, backend: NpcLlmBackend) -> void:
	_dialogue = dialogue
	_flags = flags
	_backend = backend
	if _flags == null:
		return
	if not _flags.flag_changed.is_connected(_on_flag_changed):
		_flags.flag_changed.connect(_on_flag_changed)
	# Shells are bound after the blockout spawns them, so the beat may already
	# have fired by the time we get here (a reload, or a late-registered shell).
	if _flags.has_flag(WATCH_FLAG):
		_begin_watch()


func _on_flag_changed(flag: StringName, value: bool) -> void:
	if flag == WATCH_FLAG and value:
		_begin_watch()


## The visible consequence of MQ01's first beat: the warden abandons his patrol
## and does not look away again. It reads *because* there was a patrol to break.
func _begin_watch() -> void:
	if _watching or profile == null:
		return
	if profile.rig_archetype != WATCH_ARCHETYPE:
		return
	_watching = true
	_moving = false
	_hold_left = 0.0
	if _body != null:
		_body.velocity = Vector3.ZERO
	if _bark_label != null:
		_bark_label.text = WATCH_LINE
		_bark_label.visible = true
		_bark_show_left = WATCH_BARK_SECONDS
	spoke.emit(WATCH_LINE)
	print("[PersonaShell] %s breaks patrol and watches the courier." % profile.display_name)


## True once this shell has reacted to the pass. Exposed for the soak test.
func is_watching() -> bool:
	return _watching


func _process(delta: float) -> void:
	if profile == null:
		return
	_idle_time += delta
	# Breathe always runs; the gait layers on top of it and eases to nothing
	# when the shell is standing still.
	CharacterBuilder.apply_idle(_rig, _idle_time, 0.8)
	CharacterBuilder.apply_gait(_rig, _stride_phase, _stride_amount)
	_update_facing(delta)
	_update_barks(delta)


## Turn to face the courier when they are close and nobody is mid-sentence.
## A watching shell has no radius — that is the whole point of it.
func _update_facing(delta: float) -> void:
	if _look_target == null or not is_instance_valid(_look_target):
		_look_target = get_tree().get_first_node_in_group("player") as Node3D
		return
	if _dialogue != null and _dialogue.is_active():
		return
	var dist := global_position.distance_to(_look_target.global_position)
	if dist > FACE_RADIUS and not _watching:
		return
	var want := CharacterBuilder.yaw_toward(global_position, _look_target.global_position)
	rotation.y = lerp_angle(rotation.y, want, minf(3.2 * delta, 1.0))


## --- Wander ---------------------------------------------------------------

func _init_wander() -> void:
	# `self as CharacterBody3D` is a parse error — CharacterBody3D does not
	# inherit PersonaShell, so the compiler sees an impossible sibling cast.
	# Widening to Node first makes it an ordinary downcast, which succeeds
	# whenever the scene root really is a body.
	var as_node: Node = self
	_body = as_node as CharacterBody3D
	_gait = CharacterBuilder.gait_for(profile.rig_archetype)
	_home = position
	# Pace along the direction the designer pointed this shell, so a patrol runs
	# down the kerb it was placed on rather than across it.
	_patrol_axis = Vector3(sin(rotation.y), 0.0, cos(rotation.y))
	_hold_left = _rng.randf_range(0.0, float(_gait["hold"].y))
	_orbit_dir = 1.0 if _rng.randf() < 0.5 else -1.0
	_orbit_angle = _rng.randf_range(0.0, TAU)


func _physics_process(delta: float) -> void:
	if profile == null or _body == null:
		return

	# Face-player and dialogue both outrank wandering: people stop and look at
	# you rather than pacing through a conversation.
	if _watching or _is_busy() or _player_is_near():
		_halt(delta)
	else:
		_step_wander(delta)

	if _body.is_on_floor():
		_body.velocity.y = 0.0
	else:
		_body.velocity.y -= 9.8 * delta
	_body.move_and_slide()


func _is_busy() -> bool:
	return _dialogue != null and _dialogue.is_active()


func _player_is_near() -> bool:
	if _look_target == null or not is_instance_valid(_look_target):
		return false
	return global_position.distance_to(_look_target.global_position) <= FACE_RADIUS


func _halt(delta: float) -> void:
	_moving = false
	_body.velocity.x = move_toward(_body.velocity.x, 0.0, 6.0 * delta)
	_body.velocity.z = move_toward(_body.velocity.z, 0.0, 6.0 * delta)
	_stride_amount = move_toward(_stride_amount, 0.0, 3.5 * delta)
	# Keep advancing the phase while blending out so the legs settle closed
	# instead of stopping wherever the sine happened to be.
	_stride_phase += delta * 4.0 * _stride_amount


func _step_wander(delta: float) -> void:
	if _hold_left > 0.0:
		_hold_left -= delta
		_halt(delta)
		return

	if not _moving:
		_pick_target()
		_moving = true

	var to_target := _wander_target - position
	to_target.y = 0.0
	if to_target.length() < 0.2:
		_moving = false
		_hold_left = _rng.randf_range(float(_gait["hold"].x), float(_gait["hold"].y))
		return

	var speed := float(_gait["speed"])
	var dir := to_target.normalized()
	_body.velocity.x = dir.x * speed
	_body.velocity.z = dir.z * speed

	var want := CharacterBuilder.yaw_toward(position, _wander_target)
	rotation.y = lerp_angle(rotation.y, want, minf(4.0 * delta, 1.0))

	_stride_amount = move_toward(_stride_amount, 1.0, 3.0 * delta)
	# Stride frequency tracks speed, so the urchin scurries and the preacher
	# processes without either looking like it is skating.
	_stride_phase += delta * (3.0 + speed * 4.0)


func _pick_target() -> void:
	var radius := float(_gait["radius"])
	match StringName(_gait["kind"]):
		&"patrol":
			# Flip to whichever end we are further from.
			var ahead := _home + _patrol_axis * radius
			var behind := _home - _patrol_axis * radius
			_wander_target = behind if position.distance_to(ahead) < position.distance_to(behind) else ahead
		&"circuit":
			_orbit_angle += _orbit_dir * TAU / 6.0
			_wander_target = _home + Vector3(cos(_orbit_angle), 0.0, sin(_orbit_angle)) * radius
		&"circle":
			# Kids do not commit to a direction for long.
			if _rng.randf() < 0.3:
				_orbit_dir = -_orbit_dir
			_orbit_angle += _orbit_dir * _rng.randf_range(TAU / 6.0, TAU / 3.0)
			_wander_target = _home + Vector3(cos(_orbit_angle), 0.0, sin(_orbit_angle)) * radius
		_:
			# "shift": a half-step around the pitch, never really leaving it.
			var angle := _rng.randf_range(0.0, TAU)
			var reach := _rng.randf_range(0.4, 1.0) * radius
			_wander_target = _home + Vector3(cos(angle), 0.0, sin(angle)) * reach


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
		knowledge_shared.emit(item, self)
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
		knowledge_shared.emit(item, self)
		return {"text": item.text, "deflected": false}
	return {"text": _deflect_line(), "deflected": true}


## The gossip network's door in: a second-hand line enters the bark pool.
func inject_hearsay(text: String) -> void:
	_hearsay.append(text)


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
	# Fresh hearsay beats stale small talk; it is consumed so it never repeats.
	if not _hearsay.is_empty() and _rng.randf() < 0.65:
		return _hearsay.pop_front()
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


## Exposed for soak tests: the built rig root.
func get_rig() -> Node3D:
	return _rig
