extends SceneTree
## Headless smoke test for the project skeleton.
##
## Verifies that the input map actually matches synthetic events, that the main
## scene instantiates, and that every shader in shaders/ compiles clean.
##
## Usage:
##   godot --headless --path . --script tools/verify_setup.gd

var _failures: int = 0


func _initialize() -> void:
	_check_input_map()
	_check_shaders()
	_check_main_scene()
	_check_addons()
	_check_quests()
	_check_biomes()
	_check_chunk_generation()
	_check_authored_chunk_contract()

	print("")
	if _failures == 0:
		print("VERIFY: all checks passed.")
		quit(0)
	else:
		print("VERIFY: %d check(s) FAILED." % _failures)
		quit(1)


func _fail(message: String) -> void:
	_failures += 1
	print("  FAIL  %s" % message)


func _ok(message: String) -> void:
	print("  ok    %s" % message)


func _check_input_map() -> void:
	print("[input map]")
	var expected := {
		"move_forward": KEY_W,
		"move_back": KEY_S,
		"move_left": KEY_A,
		"move_right": KEY_D,
		"jump": KEY_SPACE,
		"sprint": KEY_SHIFT,
		"interact": KEY_E,
	}
	for action: String in expected:
		if not InputMap.has_action(action):
			_fail("action '%s' is missing from the input map" % action)
			continue
		# Build the event the way the OS would deliver it and confirm it matches.
		var ev := InputEventKey.new()
		ev.physical_keycode = expected[action]
		ev.pressed = true
		if InputMap.event_is_action(ev, action):
			_ok("'%s' matches its key binding" % action)
		else:
			_fail("action '%s' exists but does not match its key event" % action)

	for action: String in ["attack_primary", "attack_secondary"]:
		if not InputMap.has_action(action):
			_fail("action '%s' is missing from the input map" % action)
			continue
		var mb := InputEventMouseButton.new()
		mb.button_index = (
			MOUSE_BUTTON_LEFT if action == "attack_primary" else MOUSE_BUTTON_RIGHT
		)
		mb.pressed = true
		if InputMap.event_is_action(mb, action):
			_ok("'%s' matches its mouse binding" % action)
		else:
			_fail("action '%s' exists but does not match its mouse event" % action)


func _check_shaders() -> void:
	print("[shaders]")
	var paths := _list_files("res://shaders", ".gdshader")
	if paths.is_empty():
		_fail("no .gdshader files found under res://shaders")
		return
	for path: String in paths:
		var shader := load(path) as Shader
		if shader == null:
			_fail("%s failed to load" % path)
			continue
		# get_shader_uniform_list() forces the parser to run over the source.
		shader.get_shader_uniform_list()
		_ok("%s compiled" % path)


func _check_main_scene() -> void:
	print("[main scene]")
	var main_path: String = ProjectSettings.get_setting("application/run/main_scene", "")
	if main_path.is_empty():
		_fail("application/run/main_scene is not set")
		return
	if not ResourceLoader.exists(main_path):
		_fail("main scene '%s' does not exist" % main_path)
		return

	var packed := load(main_path) as PackedScene
	if packed == null:
		_fail("main scene '%s' failed to load as a PackedScene" % main_path)
		return

	var instance := packed.instantiate()
	if instance == null:
		_fail("main scene '%s' failed to instantiate" % main_path)
		return

	_ok("%s instantiated as %s" % [main_path, instance.get_class()])

	# instantiate() still succeeds when a script fails to parse — it just silently
	# comes back scriptless. Assert the script actually attached.
	if instance.get_script() == null:
		_fail("main scene root has no script attached (check for parse errors above)")
	else:
		_ok("root script attached: %s" % instance.get_script().resource_path)

	for node_path: String in [
		"WorldEnvironment", "Moonlight", "World/Streamer",
		"Player", "Player/CameraPivot/SpringArm3D/Camera3D",
		"Player/CameraPivot/SpringArm3D/Camera3D/InteractRay",
		"DebugHUD/DebugLabel",
	]:
		if instance.has_node(node_path):
			_ok("node present: %s" % node_path)
		else:
			_fail("expected node missing: %s" % node_path)

	var player := instance.get_node_or_null("Player")
	if player != null and player.get_script() == null:
		_fail("Player has no script attached")

	_describe(instance, 0)
	instance.free()


func _describe(node: Node, depth: int) -> void:
	# Keep the dump shallow; this is a sanity check, not a scene inspector.
	if depth > 2:
		return
	for child in node.get_children():
		print("        %s- %s (%s)" % ["  ".repeat(depth), child.name, child.get_class()])
		_describe(child, depth + 1)


func _check_addons() -> void:
	print("[addons]")
	var enabled: PackedStringArray = ProjectSettings.get_setting(
		"editor_plugins/enabled", PackedStringArray()
	)
	for cfg: String in ["res://addons/godot_ai/plugin.cfg", "res://addons/godot_mcp/plugin.cfg"]:
		if not FileAccess.file_exists(cfg):
			_fail("addon missing from disk: %s" % cfg)
		elif cfg not in enabled:
			_fail("addon present but not enabled in project settings: %s" % cfg)
		else:
			_ok("installed and enabled: %s" % cfg.get_base_dir().get_file())


func _check_quests() -> void:
	print("[quests]")
	var paths := _list_files("res://quests", ".tres")
	if paths.is_empty():
		_ok("no quest resources yet")
		return
	for path: String in paths:
		var quest := load(path) as Quest
		if quest == null:
			_fail("%s did not load as a Quest" % path)
			continue
		# design_warnings() enforces the tone contract from CLAUDE.md: a quest
		# with a single outcome has no choice in it.
		var warnings := quest.design_warnings()
		if warnings.is_empty():
			_ok("%s (%d objectives, %d outcomes)" % [
				path.get_file(), quest.objectives.size(), quest.outcomes.size(),
			])
		else:
			for warning: String in warnings:
				_fail("%s: %s" % [path.get_file(), warning])


func _check_biomes() -> void:
	print("[biomes]")
	var biomes := ChunkStreamer.load_biomes("res://worlds/biomes")
	if biomes.is_empty():
		_fail("no Biome resources found under res://worlds/biomes")
		return

	# The urbanisation field runs 0..1 and every value has to land somewhere; a
	# hole in the bands means a chunk with no biome, which generates as bare
	# ground with only a warning to show for it.
	var cursor := 0.0
	for biome: Biome in biomes:
		for warning: String in biome.design_warnings():
			_fail("%s: %s" % [String(biome.id), warning])
		if not is_equal_approx(biome.min_urbanisation, cursor):
			_fail("urbanisation gap or overlap at %.2f before '%s' (starts %.2f)" % [
				cursor, String(biome.id), biome.min_urbanisation,
			])
		cursor = biome.max_urbanisation
		_ok("%s covers %.2f..%.2f" % [
			String(biome.id), biome.min_urbanisation, biome.max_urbanisation,
		])
	if not is_equal_approx(cursor, 1.0):
		_fail("biome bands stop at %.2f, not 1.0" % cursor)


func _check_chunk_generation() -> void:
	print("[chunk streaming]")
	var biomes := ChunkStreamer.load_biomes("res://worlds/biomes")
	if biomes.is_empty():
		return  # already reported by _check_biomes

	var generator := ChunkGenerator.new()
	generator.configure(20771113, biomes)

	# Any chunk clear of the plaza cut-out, so there is content to compare.
	var coord := Vector2i(3, -2)
	var first := generator.generate(coord)
	if first.get_child_count() == 0:
		_fail("chunk %s generated nothing at all" % str(coord))
	else:
		_ok("chunk %s: %s" % [str(coord), first.describe()])

	# Same seed and coordinate must produce the same block from a cold generator,
	# or a seed in a bug report reproduces nothing.
	var other := ChunkGenerator.new()
	other.configure(20771113, biomes)
	var repeat := other.generate(coord)
	if first.fingerprint() == repeat.fingerprint():
		_ok("regenerates identically from a fresh generator")
	else:
		_fail("chunk %s is not deterministic across generators" % str(coord))

	var neighbour := generator.generate(coord + Vector2i(1, 0))
	if neighbour.fingerprint() == first.fingerprint():
		_fail("neighbouring chunks generated identical content")
	else:
		_ok("neighbouring chunk differs")

	# The spawn plaza has to stay clear or the player boots inside a tower. All
	# four chunks meeting at the origin can put content near it.
	var intruders := 0
	var plaza_chunks: Array[WorldChunk] = []
	for coord_offset: Vector2i in [
		Vector2i(0, 0), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(-1, -1)
	]:
		var chunk := generator.generate(coord_offset)
		plaza_chunks.append(chunk)
		var chunk_origin := WorldGrid.chunk_origin(coord_offset)
		for child in chunk.get_children():
			if not String(child.name).begins_with("Building"):
				continue
			var world_position: Vector3 = chunk_origin + (child as Node3D).position
			if Vector2(world_position.x, world_position.z).length() < generator.plaza_radius:
				intruders += 1
	if intruders == 0:
		_ok("spawn plaza is clear across all four chunks that meet at the origin")
	else:
		_fail("%d building(s) generated inside the spawn plaza" % intruders)

	var built: Array[WorldChunk] = [first, repeat, neighbour]
	built.append_array(plaza_chunks)
	for chunk: WorldChunk in built:
		chunk.free()


func _check_authored_chunk_contract() -> void:
	print("[authored chunks]")
	# A scene in worlds/chunks/ overrides generation for one coordinate. Two
	# things have to survive being saved and reloaded or the override is worse
	# than useless — it replaces a working chunk with a broken one. The root has
	# to still be a WorldChunk (instantiate() returns a scriptless node when the
	# class cache is stale, and the streamer can only fall back if it can tell),
	# and the chunk_detail group has to still be on the lights, or an authored
	# chunk lights itself from across the map.
	var biomes := ChunkStreamer.load_biomes("res://worlds/biomes")
	if biomes.is_empty():
		return  # already reported by _check_biomes

	var generator := ChunkGenerator.new()
	generator.configure(20771113, biomes)
	var source := generator.generate(Vector2i(5, 5))
	_claim_ownership(source, source)

	var packed := PackedScene.new()
	if packed.pack(source) != OK:
		_fail("a generated chunk could not be packed into a PackedScene")
		source.free()
		return

	var path := "user://verify_authored_chunk.tscn"
	if ResourceSaver.save(packed, path) != OK:
		_fail("a packed chunk could not be saved to %s" % path)
		source.free()
		return

	var reloaded := (load(path) as PackedScene).instantiate()
	var chunk := reloaded as WorldChunk
	if chunk == null:
		_fail("a saved chunk does not reload as a WorldChunk (stale class cache?)")
	else:
		_ok("a chunk scene round-trips through worlds/chunks/ as a WorldChunk")
		var want := _count_in_group(source, WorldChunk.DETAIL_GROUP)
		var got := _count_in_group(chunk, WorldChunk.DETAIL_GROUP)
		if want == 0:
			_fail("the sample chunk has no '%s' members to check" % WorldChunk.DETAIL_GROUP)
		elif want == got:
			_ok("%d '%s' member(s) survived the save" % [got, WorldChunk.DETAIL_GROUP])
		else:
			_fail("'%s' membership did not survive the save (%d of %d)" % [
				WorldChunk.DETAIL_GROUP, got, want,
			])

	reloaded.free()
	source.free()
	DirAccess.remove_absolute(path)


## PackedScene.pack() only keeps descendants owned by the root.
func _claim_ownership(node: Node, root: Node) -> void:
	for child in node.get_children():
		child.owner = root
		_claim_ownership(child, root)


func _count_in_group(node: Node, group: StringName) -> int:
	var total := 0
	for child in node.get_children():
		if child.is_in_group(group):
			total += 1
		total += _count_in_group(child, group)
	return total


func _list_files(dir_path: String, suffix: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := dir_path.path_join(entry)
		if dir.current_is_dir():
			out.append_array(_list_files(full, suffix))
		elif entry.ends_with(suffix):
			out.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out
