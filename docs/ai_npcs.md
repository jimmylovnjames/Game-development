# Living NPCs: persona shells and the LLM backend

Every NPC in the district is a **shell**: a blockout body wrapped around a
`PersonaProfile` — a behavioral persona prompt plus the exact boundary of what
that character knows. The world stays alive through them, with or without a
network.

## Two voices, one mouth

| | Offline kernel (default) | LLM backend (optional) |
|---|---|---|
| Needs | nothing | Ollama running locally, or a free OpenAI-compatible API key |
| Latency | instant | ~1–3 s (shows "…" meanwhile) |
| Behaviour | seeded selection over the profile's knowledge, gated by world flags and disposition | the persona prompt + **currently revealed** knowledge becomes a system prompt; the reply is sanitized before display |
| Failure mode | — | silent fallback to the kernel mid-conversation |

The kernel is always the floor. CI and players without a key get the full
scripted life of the district; the LLM only ever *styles* what the character
is already allowed to say.

**Quest-critical dialogue never goes through either.** Vex's MQ01 lines are
authored on `NpcVex` verbatim — noir cost structure is not improvised.

## Limited knowledge is the system

A `PersonaProfile` holds an `Array[KnowledgeItem]`. That list **is** the
character's world — anything absent from it does not exist for them:

- `scopes` — topics the item answers ("scrap", "spine_gate", "syndicate")
- `requires_flag` — hidden until a world flag is set (e.g. Amp's warning only
  surfaces after `talk_to_vex`; completed quest objective ids become flags
  automatically)
- `min_disposition` — kept behind the teeth until the shell warms up
- `grants_flag` — hearing it changes the world
- `once_only` — a good rumor is spent once
- `forbidden_scopes` on the profile — topics the character *refuses*. The
  refusal is authored content; it is how the world says no.

## Turning the LLM on

No key material ever enters the repo — configuration is environment-only.

**Ollama (recommended — free, open source, offline-friendly):**

```bash
ollama pull llama3.2:3b
ollama serve
AI_NPC_PROVIDER=ollama godot --path .
```

**OpenRouter / Groq / llama.cpp server (free tiers work):**

```bash
AI_NPC_PROVIDER=openai \
AI_NPC_API_KEY=sk-... \
AI_NPC_MODEL=meta-llama/llama-3.2-3b-instruct:free \
godot --path .
# optional: AI_NPC_BASE_URL=https://your-endpoint/v1/chat/completions
```

On this VM, set the variables in the Cursor dashboard (Cloud Agents > Secrets)
or export them in your shell before launching the editor.

## Authoring a new persona

1. Create `assets/personas/<name>.tres` as a `PersonaProfile` with
   `KnowledgeItem` sub-resources (copy `marrow_scrap.tres` as a template).
2. Write the `persona_prompt` as temperament + loyalties + speech rhythm +
   what they want — it is fed to the model verbatim.
3. Author `deflect_lines` with the same care as knowledge; refusals carry lore.
4. Instantiate `scenes/characters/persona_shell.tscn`, assign the profile,
   vary the capsule scale for silhouette, place it in
   `DistrictBlockout._spawn_people()`.
5. GameRoot binds dialogue, flags and backend to every shell automatically
   (group `persona_shells`).

Tone guardrails live in CLAUDE.md: knowledge lands through what people refuse
to say, never through codex dumps.

## Testing

`tools/soak_test.gd` stage 9 asserts — without any network — that shells exist,
kernels compose, forbidden scopes deflect, flag-gated knowledge unlocks after
the Vex beat, and the backend is offline when unconfigured.

## The rumor mill

`GossipNetwork` listens for knowledge items shared by any shell and writes
them into circulation. Every `spread_interval` seconds a random item is
repeated by a *different* persona as hearsay ("Word is — …", "Marrow says —
…"), consumed on use so it never repeats. What you hear in the plaza comes
back to you bent — the district talks about what you were told.

## Standing still is a choice, not a default

Shells wander. The style comes from `rig_archetype` — the silhouette a persona
already declares — so a new character gets believable motion without a single
extra field in its `.tres`:

| Archetype | Gait | Reads as |
|---|---|---|
| `vendor`, `fixer`, `courier` | `shift` | Stays on its pitch, shuffles weight, takes the odd half-step |
| `preacher` | `circuit` | Slow closed loop with long pauses, addressing nobody |
| `urchin` | `circle` | Quick orbit that keeps reversing |
| `warden` | `patrol` | Paces a line and turns at each end — habit, not duty |

Tuning lives in `CharacterBuilder.GAITS` (radius, speed, hold range). A shell
never leaves the pitch the designer placed it on: every target is an offset
from its spawn point, so the plaza cannot empty itself overnight.

`CharacterBuilder.apply_gait()` layers the walk on top of `apply_idle()` — it
only writes `rotation.x` on limbs plus a bob on `rig.position.y`, so the breathe
(`rig.scale.y`, `rig.rotation.z`) and the build-time arm splay both survive. The
`amount` parameter eases between 0 and 1 rather than snapping, because a shell
that stops mid-step otherwise freezes with one leg out.

**Facing outranks wandering.** Inside `FACE_RADIUS` (6.5 m) a shell halts and
turns to the courier, then resumes when they leave. That is both the believable
read — people stop and look at you — and the arbitration that stops the gait and
the head-look fighting over `rotation.y`.

## The pass has a witness

Completing `talk_to_vex` sets a world flag (`QuestSystem` does this for every
objective it completes). `PersonaShell` listens on `WorldFlags.flag_changed`,
and the `warden` archetype reacts: Bram abandons his patrol for good, drops his
6.5 m facing radius so he tracks the courier from anywhere in the plaza, and
says one line.

The beat only reads because there was a patrol to break — the consequence is
carried by the wander system rather than bolted on beside it. `soak_test.gd`
stage 14 asserts it from ~35 m away, which is the only distance at which
"ignores the face radius" can actually be proven.
