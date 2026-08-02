# scenes/characters

NPCs and enemies — all `CharacterBody3D` with a shared `ComicVisual` body.

| Scene | Kit | Face | Notes |
|---|---|---|---|
| `npc_civilian.tscn` | civilian | eyes, no visor | Idle wander optional |
| `npc_tech.tscn` | tech | cyan visor | Street tech |
| `enemy_thug.tscn` | thug | full mask | Wander on |
| `enemy_corp.tscn` | corp | magenta-rim visor | Wander on |

Body construction + idle/walk pose live in `scripts/characters/comic_visual.gd`.
Locomotion for non-player bodies: `scripts/characters/npc_body.gd`.
