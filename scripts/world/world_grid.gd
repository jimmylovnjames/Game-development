class_name WorldGrid
extends RefCounted
## The fixed lattice every streamed thing agrees on.
##
## Chunks, building lots and street-lamp posts all derive their positions from
## the constants here rather than from wherever the streamer happens to be
## standing. That is what makes seams invisible: a lot belongs to exactly one
## chunk by arithmetic, and roads line up across chunk borders because the lot
## lattice is global, not per-chunk.
##
## Static only — never instantiated.

## Metres per chunk edge. Fixed, per CLAUDE.md: nothing may assume the whole
## world is resident, so this is the unit everything streams in.
const CHUNK_SIZE := 64.0
const LOTS_PER_CHUNK := 2
const LOT_STRIDE := CHUNK_SIZE / LOTS_PER_CHUNK


static func world_to_chunk(world_position: Vector3) -> Vector2i:
	return Vector2i(
		floori(world_position.x / CHUNK_SIZE),
		floori(world_position.z / CHUNK_SIZE),
	)


## Corner of the chunk, and the transform its content is authored relative to.
static func chunk_origin(coord: Vector2i) -> Vector3:
	return Vector3(coord.x * CHUNK_SIZE, 0.0, coord.y * CHUNK_SIZE)


static func chunk_centre(coord: Vector2i) -> Vector3:
	return chunk_origin(coord) + Vector3(CHUNK_SIZE * 0.5, 0.0, CHUNK_SIZE * 0.5)


## Lowest-indexed lot owned by a chunk. Ownership is exclusive, so no lot is
## ever built twice at a seam.
static func first_lot_in_chunk(coord: Vector2i) -> Vector2i:
	return coord * LOTS_PER_CHUNK


static func lot_centre(lot: Vector2i) -> Vector3:
	return Vector3((lot.x + 0.5) * LOT_STRIDE, 0.0, (lot.y + 0.5) * LOT_STRIDE)


## Corner shared by four lots — where street furniture goes.
static func lot_corner(lot: Vector2i) -> Vector3:
	return Vector3(lot.x * LOT_STRIDE, 0.0, lot.y * LOT_STRIDE)


static func chebyshev(delta: Vector2i) -> int:
	return maxi(absi(delta.x), absi(delta.y))


## Deterministic per-chunk seed.
##
## Written as an explicit integer mix rather than `hash()` so the value does not
## move between engine builds: a seed quoted in a bug report has to reproduce
## the same block a year from now. Chunks must also generate identically no
## matter what order the player wanders into them, which rules out a single
## shared RNG stream.
static func chunk_seed(world_seed: int, coord: Vector2i) -> int:
	var h: int = world_seed
	h = (h ^ (coord.x * 0x1F1F1F1F)) * 0x27220A95
	h = (h ^ (coord.y * 0x2545F491)) * 0x165667B1
	h = h ^ (h >> 29)
	h = h * 0x27D4EB2F
	h = h ^ (h >> 32)
	return h & 0x7FFFFFFFFFFFFFFF
