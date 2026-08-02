class_name GossipNetwork
extends Node
## The rumor mill. When a persona shares a knowledge item with the courier,
## the network writes it into circulation; a while later a *different* persona
## may repeat it as hearsay — prefixed, second-hand, and slightly cheaper than
## the original. What you hear in the plaza comes back to you bent.
##
## This is what makes the shell system feel alive rather than scripted: the
## knowledge graph moves on its own, and the same fact never arrives twice
## wearing the same coat.

signal hearsay_added(shell_id: StringName, text: String)

## Seconds between spread attempts. Short enough for the demo block to feel
## busy; the chunk streamer can retune per district later.
@export var spread_interval: float = 14.0

const HEARSAY_PREFIXES := ["Word is — ", "They say ", "Heard in the stalls: "]

var _entries: Array = []  # {"item": KnowledgeItem, "source": PersonaShell}
var _shells: Array[PersonaShell] = []
var _rng := RandomNumberGenerator.new()
var _spread_timer: float = 0.0
## Total hearsay lines injected; asserted by soak tests.
var hearsay_total: int = 0


func _ready() -> void:
	_rng.seed = 414141
	_spread_timer = spread_interval * 0.5


func register_shell(shell: PersonaShell) -> void:
	if shell in _shells:
		return
	_shells.append(shell)
	if not shell.knowledge_shared.is_connected(_on_knowledge_shared):
		shell.knowledge_shared.connect(_on_knowledge_shared)


func _on_knowledge_shared(item: KnowledgeItem, source: PersonaShell) -> void:
	if item.scopes.is_empty():
		return  # flavor talk does not travel; facts and rumors do
	for entry: Dictionary in _entries:
		if entry["item"].id == item.id:
			return
	_entries.append({"item": item, "source": source})


func _process(delta: float) -> void:
	if _entries.is_empty() or _shells.size() < 2:
		return
	_spread_timer -= delta
	if _spread_timer > 0.0:
		return
	_spread_timer = spread_interval * _rng.randf_range(0.75, 1.3)
	_spread_one()


func _spread_one() -> void:
	var entry: Dictionary = _entries[_rng.randi() % _entries.size()]
	var source: PersonaShell = entry["source"]
	var candidates: Array[PersonaShell] = []
	for shell in _shells:
		if shell != source:
			candidates.append(shell)
	if candidates.is_empty():
		return
	var target: PersonaShell = candidates[_rng.randi() % candidates.size()]
	target.inject_hearsay(_mutate(entry))
	hearsay_total += 1


## Second-hand phrasing: attribution optional, confidence degraded.
func _mutate(entry: Dictionary) -> String:
	var item: KnowledgeItem = entry["item"]
	var source: PersonaShell = entry["source"]
	if _rng.randf() < 0.45 and source.profile != null:
		return "%s says — %s" % [source.profile.display_name, item.text]
	return HEARSAY_PREFIXES[_rng.randi() % HEARSAY_PREFIXES.size()] + item.text


## Tests and scripted beats: circulate everything immediately.
func force_spread_all() -> int:
	var count := _entries.size()
	for entry: Dictionary in _entries:
		var source: PersonaShell = entry["source"]
		for shell in _shells:
			if shell == source:
				continue
			shell.inject_hearsay(_mutate(entry))
			hearsay_total += 1
			break
	return count
