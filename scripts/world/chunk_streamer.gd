class_name ChunkStreamer
extends Node3D
## Keeps the chunks around a follow target resident, and nothing else.
##
## This is the shipping replacement for `DistrictBlockout`: the world is no
## longer a scene, it is a lattice of cells built on demand. Gameplay code must
## not hold references to chunk contents across frames — anything outside the
## ring is gone.
##
## Three radii, in increasing size:
##   `detail_radius`  chunks whose lights are on. Everything past it keeps its
##                    emissive signage but drops its `Light3D`s, because a full
##                    7x7 ring of lit chunks puts >100 lights in frame and the
##                    cel bands go flat.
##   `load_radius`    chunks that are built and collidable.
##   `+unload_padding` hysteresis before a chunk is freed, so walking back and
##                    forth across a seam does not rebuild it every step.
##
## Chunks under `worlds/chunks/` named `chunk_<x>_<z>.tscn` override generation
## for that coordinate, which is how a hand-authored story district drops into
## a procedural world.

signal chunk_loaded(coord: Vector2i)
signal chunk_unloaded(coord: Vector2i)
## Emitted when the build queue drains. Useful for fades and for tests that need
## to know the world under the player is actually there.
signal streaming_settled(loaded_count: int)

const AUTHORED_DIR := "res://worlds/chunks"
const UNLIMITED := -1

@export_group("World")
## Stored, not derived: a seed in a bug report has to reproduce the same city.
@export var world_seed: int = 20771113
@export_node_path("Node3D") var target_path: NodePath
## Biomes are loaded from here when `biomes` is left empty, so adding a region
## is a `.tres` and nothing else.
@export_dir var biome_directory: String = "res://worlds/biomes"
@export var biomes: Array[Biome] = []

@export_group("Radii")
@export_range(1, 8) var load_radius: int = 3
@export_range(0, 4) var unload_padding: int = 1
@export_range(0, 8) var detail_radius: int = 1

@export_group("Budget")
## Chunks built per frame once streaming is running. Warm-up ignores this.
@export_range(1, 32) var builds_per_frame: int = 2
@export var warm_up_on_ready: bool = true

var _generator := ChunkGenerator.new()
var _chunks := {}  # Vector2i -> WorldChunk
var _pending: Array[Vector2i] = []
var _target: Node3D = null
var _centre := Vector2i.ZERO
var _has_centre: bool = false
var _settled: bool = false
var _authored_count: int = 0


func _ready() -> void:
	if biomes.is_empty():
		biomes = load_biomes(biome_directory)
	if biomes.is_empty():
		push_warning(
			"ChunkStreamer found no biomes in '%s' — chunks will be bare ground"
			% biome_directory
		)
	_generator.configure(world_seed, biomes)

	_resolve_target()
	if warm_up_on_ready:
		var start := Vector3.ZERO
		if _target != null:
			start = _target.global_position
		warm_up_at(start)


func _process(_delta: float) -> void:
	_resolve_target()
	if _target != null:
		var coord := WorldGrid.world_to_chunk(_target.global_position)
		if not _has_centre or coord != _centre:
			_recentre(coord)
	_drain_queue(builds_per_frame)


# -- public API ---------------------------------------------------------------


## Builds everything in the load ring immediately. Call it before teleporting
## the player, not after — a frame-budgeted stream leaves them standing on
## nothing.
func warm_up(centre: Vector2i) -> void:
	_recentre(centre)
	_drain_queue(UNLIMITED)


func warm_up_at(world_position: Vector3) -> void:
	warm_up(WorldGrid.world_to_chunk(world_position))


func loaded_count() -> int:
	return _chunks.size()


func pending_count() -> int:
	return _pending.size()


## Chunks in the load ring. Only equal to `loaded_count()` straight after a
## `warm_up()` — in motion the resident set runs ahead of it, because the
## hysteresis margin keeps chunks the player just left.
func load_ring_count() -> int:
	var side := load_radius * 2 + 1
	return side * side


## Ceiling on the resident set: the load ring plus everything the hysteresis
## margin is still holding on to.
func max_resident_count() -> int:
	var side := (load_radius + unload_padding) * 2 + 1
	return side * side


func is_loaded(coord: Vector2i) -> bool:
	return _chunks.has(coord)


func get_chunk(coord: Vector2i) -> WorldChunk:
	return _chunks.get(coord, null) as WorldChunk


func loaded_coords() -> Array:
	return _chunks.keys()


func current_centre() -> Vector2i:
	return _centre


func authored_chunk_count() -> int:
	return _authored_count


func biome_at(world_position: Vector3) -> Biome:
	return _generator.biome_at(world_position)


func urbanisation(world_position: Vector3) -> float:
	return _generator.urbanisation(world_position)


## Centre of the plaza the generator keeps clear, one step above the road.
func get_spawn_point() -> Vector3:
	return Vector3(0.0, 1.2, 0.0)


## Rebuilds every resident chunk. For seed changes and live authoring — not
## something gameplay should call.
func rebuild() -> void:
	for coord: Vector2i in _chunks.keys():
		_unload(coord)
	_pending.clear()
	_generator.configure(world_seed, biomes)
	_settled = false
	if _has_centre:
		warm_up(_centre)


static func load_biomes(directory: String) -> Array[Biome]:
	var out: Array[Biome] = []
	var dir := DirAccess.open(directory)
	if dir == null:
		return out
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not dir.current_is_dir() and entry.ends_with(".tres"):
			var path := directory.path_join(entry)
			var biome := load(path) as Biome
			if biome == null:
				push_warning("'%s' is not a Biome resource" % path)
			else:
				out.append(biome)
		entry = dir.get_next()
	dir.list_dir_end()
	out.sort_custom(func(a: Biome, b: Biome) -> bool:
		return a.min_urbanisation < b.min_urbanisation)
	return out


# -- streaming ----------------------------------------------------------------


func _resolve_target() -> void:
	if _target != null and not is_instance_valid(_target):
		_target = null  # the target was freed out from under us
	if _target != null or target_path.is_empty():
		return
	_target = get_node_or_null(target_path) as Node3D


func _recentre(centre: Vector2i) -> void:
	_centre = centre
	_has_centre = true

	var drop_limit := load_radius + unload_padding

	for coord: Vector2i in _chunks.keys():
		if WorldGrid.chebyshev(coord - centre) > drop_limit:
			_unload(coord)

	# Queued builds the player walked away from before we got to them.
	var still_wanted: Array[Vector2i] = []
	for coord: Vector2i in _pending:
		if WorldGrid.chebyshev(coord - centre) <= drop_limit:
			still_wanted.append(coord)
	_pending = still_wanted

	for dx in range(-load_radius, load_radius + 1):
		for dz in range(-load_radius, load_radius + 1):
			var coord := centre + Vector2i(dx, dz)
			# Linear scans over a queue bounded by the load ring — a couple of
			# thousand comparisons on the frame the player crosses a seam.
			if not _chunks.has(coord) and not _pending.has(coord):
				_pending.append(coord)

	# Nearest first, so the ground under the player exists before the skyline.
	_pending.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return (a - centre).length_squared() < (b - centre).length_squared())

	_apply_detail_ring(centre)

	if not _pending.is_empty():
		_settled = false


func _drain_queue(budget: int) -> void:
	var built := 0
	while (budget == UNLIMITED or built < budget) and not _pending.is_empty():
		var coord: Vector2i = _pending.pop_front()
		if _chunks.has(coord):
			continue
		_load(coord)
		built += 1

	if _pending.is_empty() and not _settled:
		_settled = true
		streaming_settled.emit(_chunks.size())


func _load(coord: Vector2i) -> void:
	var chunk := _instantiate_authored(coord)
	if chunk == null:
		chunk = _generator.generate(coord)
	else:
		_authored_count += 1

	chunk.coord = coord
	chunk.position = WorldGrid.chunk_origin(coord)
	chunk.set_detail_enabled(WorldGrid.chebyshev(coord - _centre) <= detail_radius)

	_chunks[coord] = chunk
	add_child(chunk)
	chunk_loaded.emit(coord)


func _unload(coord: Vector2i) -> void:
	var chunk: WorldChunk = _chunks.get(coord, null)
	if chunk == null:
		return
	_chunks.erase(coord)
	chunk.queue_free()
	chunk_unloaded.emit(coord)


func _apply_detail_ring(centre: Vector2i) -> void:
	for coord: Vector2i in _chunks.keys():
		var chunk: WorldChunk = _chunks[coord]
		chunk.set_detail_enabled(WorldGrid.chebyshev(coord - centre) <= detail_radius)


func _instantiate_authored(coord: Vector2i) -> WorldChunk:
	var path := "%s/chunk_%d_%d.tscn" % [AUTHORED_DIR, coord.x, coord.y]
	if not ResourceLoader.exists(path):
		return null

	var packed := load(path) as PackedScene
	if packed == null:
		push_warning("authored chunk '%s' did not load as a PackedScene" % path)
		return null

	var node := packed.instantiate()
	var chunk := node as WorldChunk
	if chunk == null:
		# instantiate() happily returns a scriptless node when the class cache is
		# stale (CLAUDE.md §6). Fall back to generation rather than parenting a
		# dud that silently has no ground.
		push_warning(
			"authored chunk '%s' has no WorldChunk script — generating instead" % path
		)
		node.free()
		return null
	return chunk
