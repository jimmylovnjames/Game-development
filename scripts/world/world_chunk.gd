class_name WorldChunk
extends Node3D
## One streamed cell of the world.
##
## Content is authored in chunk-local space with the chunk node sitting at
## `WorldGrid.chunk_origin()`, so a chunk can be built before it is parented and
## can be freed without anything else noticing. Procedurally generated chunks
## and hand-authored ones under `worlds/chunks/` are the same type — the
## streamer does not care which it got.
##
## Lights and other per-frame-expensive detail go in the `chunk_detail` group.
## The streamer hides that group on chunks outside the detail ring: with a
## couple of lights per chunk and a 7x7 load ring, lighting every loaded chunk
## puts well over a hundred lights in frame and washes the cel bands flat.

const DETAIL_GROUP := &"chunk_detail"

var coord := Vector2i.ZERO
var chunk_seed: int = 0
var biome_id: StringName = &""
var building_count: int = 0
var sign_count: int = 0

var _detail_nodes: Array[Node3D] = []
var _detail_enabled: bool = true


func _ready() -> void:
	_collect_detail_nodes()
	_apply_detail()


func set_detail_enabled(enabled: bool) -> void:
	if _detail_enabled == enabled:
		return
	_detail_enabled = enabled
	# Called before the chunk is parented on the frame it is built; `_ready()`
	# applies the pending state once the subtree exists.
	if is_node_ready():
		_apply_detail()


func is_detail_enabled() -> bool:
	return _detail_enabled


func detail_node_count() -> int:
	return _detail_nodes.size()


## Stable digest of the chunk's contents, for asserting that the same seed and
## coordinate really do produce the same block.
func fingerprint() -> String:
	var parts := PackedStringArray()
	_fingerprint_into(self, parts)
	return "%x" % hash("|".join(parts))


func describe() -> String:
	return "%s biome=%s seed=%d buildings=%d signs=%d" % [
		str(coord), String(biome_id), chunk_seed, building_count, sign_count,
	]


func _apply_detail() -> void:
	for node in _detail_nodes:
		node.visible = _detail_enabled


func _collect_detail_nodes() -> void:
	_detail_nodes.clear()
	_scan_for_detail(self)


func _scan_for_detail(node: Node) -> void:
	for child in node.get_children():
		if child is Node3D and child.is_in_group(DETAIL_GROUP):
			_detail_nodes.append(child)
		_scan_for_detail(child)


func _fingerprint_into(node: Node, parts: PackedStringArray) -> void:
	for child in node.get_children():
		# Class and transform, never `name`. Godot names unnamed nodes from a
		# process-global serial counter, so names differ between two otherwise
		# identical chunks and would make this digest useless.
		if child is Node3D:
			var spatial := child as Node3D
			parts.append("%s@%s,%s,%s/%s,%s,%s" % [
				child.get_class(),
				String.num(spatial.position.x, 3),
				String.num(spatial.position.y, 3),
				String.num(spatial.position.z, 3),
				String.num(spatial.rotation.x, 4),
				String.num(spatial.rotation.y, 4),
				String.num(spatial.rotation.z, 4),
			])
		else:
			parts.append(child.get_class())
		_fingerprint_into(child, parts)
