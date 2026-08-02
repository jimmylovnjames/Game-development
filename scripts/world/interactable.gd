class_name Interactable
extends CollisionObject3D
## Anything the courier can press E on.
##
## Contract (CLAUDE.md): sit on physics layer 5 (`interactable`) and expose
## `interact(who)`. The player's InteractRay finds this node (or a parent that
## has the method) and emits `interactable_changed`. Subclasses own the
## behaviour; this base only holds the prompt and the collision layer helper.
##
## Attach to CharacterBody3D, StaticBody3D, RigidBody3D or Area3D — all inherit
## CollisionObject3D.

signal interacted(who: Node3D)

@export var interactable_id: StringName = &""
## Short verb shown in the HUD when the ray is on this object ("Talk", "Take").
@export var prompt: String = "Interact"
@export var can_interact: bool = true


func _ready() -> void:
	_ensure_interactable_layer()


## Layer 5 bit — keep the mask numeric out of gameplay code.
func _ensure_interactable_layer() -> void:
	collision_layer |= 16  # interactable


func interact(who: Node3D) -> void:
	if not can_interact:
		return
	interacted.emit(who)
	_on_interact(who)


## Override in subclasses. Default is a no-op beyond the signal.
func _on_interact(_who: Node3D) -> void:
	pass


func get_prompt() -> String:
	return prompt
