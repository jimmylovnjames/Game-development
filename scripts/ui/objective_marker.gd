class_name ObjectiveMarker
extends Control
## On-screen waypoint for the active quest objective.
##
## Drawn rather than built from nodes because it has to do two different things
## — sit on the target when it is visible, and pin to the screen edge pointing
## at it when it is not — and a Control that draws itself handles both without a
## node per state.
##
## Style follows the comic language: ink outline under a neon chevron, no fill,
## nothing that competes with the signage it is pointing at.

const INK := Color(0.031, 0.02, 0.059)
const NEON := Color(0.969, 1.0, 0.235)
## Keep the pinned chevron off the very edge so it is not clipped by the frame.
const EDGE_MARGIN := 56.0
## Below this the marker is redundant — you can see the thing.
const HIDE_WITHIN_METRES := 6.0

var quests: QuestSystem = null
var player: Node3D = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Anchors alone leave the offsets untouched, so the Control keeps whatever
	# zero size it was created with and every inset below goes negative.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if quests == null:
		return
	var marker: Dictionary = quests.get_active_marker()
	if not bool(marker.get("has", false)):
		return

	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return

	var target: Vector3 = marker["position"]
	var from: Vector3 = player.global_position if player != null else camera.global_position
	var distance := from.distance_to(target)
	if distance < HIDE_WITHIN_METRES:
		return

	var rect := get_rect()
	# Nothing sensible to draw in a viewport too small to inset — and building
	# the Rect2 below from a negative size is an engine error, not a no-op.
	if rect.size.x < EDGE_MARGIN * 2.5 or rect.size.y < EDGE_MARGIN * 2.5:
		return
	var centre := rect.size * 0.5
	# Aim at head height rather than the ground, so the chevron sits on the gate
	# rather than on the tarmac in front of it.
	var screen := camera.unproject_position(target + Vector3.UP * 2.0)

	# unproject_position mirrors coordinates for anything behind the camera, so
	# a target at your back would otherwise draw a chevron pointing the wrong
	# way. Reflect it through the centre to recover the true bearing.
	var behind := camera.is_position_behind(target)
	if behind:
		screen = centre - (screen - centre)

	var inner := Rect2(
		Vector2(EDGE_MARGIN, EDGE_MARGIN),
		rect.size - Vector2(EDGE_MARGIN, EDGE_MARGIN) * 2.0
	)
	var on_screen := not behind and inner.has_point(screen)

	if on_screen:
		_draw_diamond(screen, 13.0)
	else:
		screen = _clamp_to_edge(screen, centre, inner)
		_draw_chevron(screen, (screen - centre).angle())

	_draw_caption(screen, "%d m" % int(round(distance)), on_screen)


## Push the point out along its bearing from the centre until it lands on the
## edge of `inner`, so an off-screen target reads as a compass heading.
func _clamp_to_edge(point: Vector2, centre: Vector2, inner: Rect2) -> Vector2:
	var direction := point - centre
	if direction.length_squared() < 0.001:
		direction = Vector2.RIGHT
	direction = direction.normalized()

	var half := inner.size * 0.5
	# Scale the ray so whichever axis hits its bound first defines the contact.
	var scale_x := half.x / maxf(absf(direction.x), 0.0001)
	var scale_y := half.y / maxf(absf(direction.y), 0.0001)
	return centre + direction * minf(scale_x, scale_y)


func _draw_diamond(at: Vector2, size: float) -> void:
	var points := PackedVector2Array([
		at + Vector2(0.0, -size),
		at + Vector2(size, 0.0),
		at + Vector2(0.0, size),
		at + Vector2(-size, 0.0),
		at + Vector2(0.0, -size),
	])
	draw_polyline(points, INK, 6.0, true)
	draw_polyline(points, NEON, 2.5, true)


func _draw_chevron(at: Vector2, angle: float) -> void:
	var forward := Vector2.RIGHT.rotated(angle)
	var side := forward.orthogonal()
	var points := PackedVector2Array([
		at + forward * 16.0,
		at - forward * 8.0 + side * 12.0,
		at - forward * 8.0 - side * 12.0,
		at + forward * 16.0,
	])
	draw_polyline(points, INK, 7.0, true)
	draw_polyline(points, NEON, 2.5, true)


func _draw_caption(at: Vector2, text: String, on_screen: bool) -> void:
	var font := get_theme_default_font()
	if font == null:
		return
	var size := 15
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x
	var origin := at + Vector2(-width * 0.5, 30.0 if on_screen else 34.0)
	# Ink first, then the type over it — the same read as every other panel.
	for offset: Vector2 in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		draw_string(font, origin + offset * 2.0, text,
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, size, INK)
	draw_string(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size, NEON)
