# worlds/chunks

Fixed-size world chunks. Nothing in the codebase may assume the whole world is
resident — see CLAUDE.md, "Architecture".

Chunks are `WorldGrid.CHUNK_SIZE` metres square and are generated on demand by
`ChunkStreamer` (`scripts/world/chunk_streamer.gd`). This directory is for the
exceptions: **authored chunk overrides**.

## Authored overrides

A scene named `chunk_<x>_<z>.tscn` here replaces procedural generation for that
coordinate — negative coordinates included, e.g. `chunk_-3_12.tscn`. This is how
a hand-built story district drops into a procedural world.

Rules for an authored chunk:

- The scene root must have `scripts/world/world_chunk.gd` attached. A root
  without the script is rejected with a warning and the coordinate falls back to
  generation, because `instantiate()` silently returns a scriptless node when
  the class cache is stale (CLAUDE.md §6).
- Content is authored in **chunk-local space**: local `(0, 0, 0)` is the chunk's
  low corner, and the chunk spans `0 .. CHUNK_SIZE` on X and Z. The streamer
  positions the root.
- The chunk owns its own ground and collision. There is no world floor outside
  the load ring.
- Put every `Light3D` in the `chunk_detail` group. The streamer hides that group
  outside `detail_radius`; a chunk that lights itself unconditionally puts its
  lights in frame from across the map.
