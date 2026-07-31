class_name PhysicsProp
extends RigidBody3D
## A loose, shoveable piece of street debris: crates, cans, anything the
## player (or an explosion, later) can throw around. Behaviour only — the
## scene file supplies the mesh, shape, mass and physics material.
##
## The player controller pushes these on contact; `kick()` is the explicit
## interface for everything else.

## Fired when the prop hits something faster than the threshold. Audio and
## damage systems subscribe to this later.
signal impacted(impact_speed: float)

## Impact speeds below this are street noise, not events.
@export var impact_speed_threshold: float = 2.5

var _last_speed: float = 0.0


func _ready() -> void:
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	_last_speed = state.linear_velocity.length()


func _on_body_entered(_body: Node) -> void:
	if _last_speed >= impact_speed_threshold:
		impacted.emit(_last_speed)
		var fx := get_tree().get_first_node_in_group("comic_fx") as ComicFX
		if fx != null and _last_speed >= 5.0:
			fx.burst(fx.pick_impact(_last_speed), global_position, "impact")


## Apply an impulse at a world-space point (or through the centre of mass when
## omitted). Named `kick` because that is what the player will do to it.
func kick(impulse: Vector3, at_point := Vector3.INF) -> void:
	if at_point.is_finite():
		apply_impulse(impulse, at_point - global_position)
	else:
		apply_impulse(impulse)
