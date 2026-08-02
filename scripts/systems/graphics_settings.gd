class_name GraphicsSettings
extends Node
## Runtime quality tiers, so the district that was authored on a workstation
## also runs on a fanless laptop.
##
## The blockout puts ~135 realtime lights and ~1500 mesh instances in front of
## the camera, with volumetric fog, SSIL, SSAO and glow on top. That is a
## discrete-GPU load. On integrated graphics — a MacBook Air especially, where
## a Retina backbuffer is ~2560x1664 and there is no fan to fall back on — the
## expensive passes have to come off and the lights have to cull by distance.
##
## Nothing here changes how the game looks *in kind*: the cel shading, ink
## outlines and neon are untouched at every tier. What changes is how much
## atmosphere sits on top and how far away things keep being lit.

enum Tier {
	POTATO,   ## Intel integrated / very old hardware. Everything optional is off.
	LAPTOP,   ## Apple Silicon Air, thin-and-light integrated GPUs.
	DESKTOP,  ## Discrete GPU. The look as authored.
}

## Per-tier settings. `light_fade_begin` is where positional lights start
## fading; beyond begin+length they cost nothing at all, which is the single
## biggest win available given how many the district spawns.
const TIERS := {
	Tier.POTATO: {
		"name": "potato",
		"render_scale": 0.62,
		"scaling_mode": Viewport.SCALING_3D_MODE_BILINEAR,
		"msaa": Viewport.MSAA_DISABLED,
		"fxaa": true,
		"volumetric_fog": false,
		"ssil": false,
		"ssao": false,
		"glow": true,
		"shadow_atlas": 1024,
		"directional_shadows": true,
		"shadow_distance": 55.0,
		"light_fade_begin": 20.0,
		"light_fade_length": 9.0,
		"rain_intensity": 0.45,
	},
	Tier.LAPTOP: {
		"name": "laptop",
		"render_scale": 0.8,
		"scaling_mode": Viewport.SCALING_3D_MODE_BILINEAR,
		"msaa": Viewport.MSAA_DISABLED,
		"fxaa": true,
		"volumetric_fog": false,
		"ssil": false,
		"ssao": true,
		"glow": true,
		"shadow_atlas": 2048,
		"directional_shadows": true,
		"shadow_distance": 90.0,
		"light_fade_begin": 34.0,
		"light_fade_length": 14.0,
		"rain_intensity": 0.75,
	},
	Tier.DESKTOP: {
		"name": "desktop",
		"render_scale": 1.0,
		"scaling_mode": Viewport.SCALING_3D_MODE_BILINEAR,
		"msaa": Viewport.MSAA_4X,
		"fxaa": false,
		"volumetric_fog": true,
		"ssil": true,
		"ssao": true,
		"glow": true,
		"shadow_atlas": 4096,
		"directional_shadows": true,
		"shadow_distance": 140.0,
		"light_fade_begin": 70.0,
		"light_fade_length": 30.0,
		"rain_intensity": 1.0,
	},
}

signal tier_applied(tier: int)

var _tier: int = Tier.DESKTOP
var _lights_faded: int = 0


## Command line wins, then an explicit project setting, then hardware sniffing.
##
##   godot --path . -- --quality=laptop
static func resolve_tier() -> int:
	for arg in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if arg.begins_with("--quality="):
			var wanted := arg.split("=", true, 1)[1].to_lower()
			for tier: int in TIERS:
				if TIERS[tier]["name"] == wanted:
					return tier
			push_warning("[GraphicsSettings] unknown --quality='%s'" % wanted)

	var configured: String = str(
		ProjectSettings.get_setting("neonwastes/graphics/tier", "auto")
	).to_lower()
	if configured != "auto" and not configured.is_empty():
		for tier: int in TIERS:
			if TIERS[tier]["name"] == configured:
				return tier
		push_warning("[GraphicsSettings] unknown tier setting '%s'" % configured)

	return detect_tier()


## Integrated GPUs get the laptop tier; the very weakest get potato. This is a
## starting point the player can override, not a verdict.
static func detect_tier() -> int:
	var adapter_type := RenderingServer.get_video_adapter_type()
	var adapter := RenderingServer.get_video_adapter_name().to_lower()

	if adapter_type == RenderingDevice.DEVICE_TYPE_CPU:
		return Tier.POTATO
	if adapter_type == RenderingDevice.DEVICE_TYPE_DISCRETE_GPU:
		return Tier.DESKTOP

	# Software rasterisers report themselves as ordinary adapters on some
	# drivers, so match the names too rather than trusting the device type.
	for software: String in ["llvmpipe", "softpipe", "swiftshader", "lavapipe"]:
		if adapter.contains(software):
			return Tier.POTATO

	# Intel integrated parts predate the budget this scene assumes by a wide
	# margin; Apple Silicon and recent AMD APUs hold the middle tier fine.
	if adapter.contains("intel") or adapter.contains("uhd") or adapter.contains("iris"):
		return Tier.POTATO
	return Tier.LAPTOP


func apply(tier: int = -1, scene_root: Node = null) -> void:
	_tier = tier if TIERS.has(tier) else resolve_tier()
	var config: Dictionary = TIERS[_tier]

	_apply_viewport(config)
	_apply_environment(config, scene_root)
	_apply_lights(config, scene_root)
	_apply_rain(config, scene_root)

	tier_applied.emit(_tier)
	print("[GraphicsSettings] tier=%s adapter='%s' render_scale=%.2f lights_faded=%d" % [
		config["name"],
		RenderingServer.get_video_adapter_name(),
		float(config["render_scale"]),
		_lights_faded,
	])


func _apply_viewport(config: Dictionary) -> void:
	var viewport := get_viewport()
	if viewport == null:
		return
	# Retina backbuffers are the quiet killer on a Mac laptop: the window is
	# 1440 wide and the framebuffer is 2880. Rendering 3D below native and
	# letting the UI stay crisp is far cheaper than dropping effects.
	viewport.scaling_3d_mode = config["scaling_mode"]
	viewport.scaling_3d_scale = config["render_scale"]
	viewport.msaa_3d = config["msaa"]
	viewport.screen_space_aa = (
		Viewport.SCREEN_SPACE_AA_FXAA if config["fxaa"] else Viewport.SCREEN_SPACE_AA_DISABLED
	)
	# TAA smears the hard cel terminator into mush. Never on, at any tier.
	viewport.use_taa = false
	viewport.positional_shadow_atlas_size = config["shadow_atlas"]


func _apply_environment(config: Dictionary, scene_root: Node) -> void:
	var world_env := _find_world_environment(scene_root)
	if world_env == null or world_env.environment == null:
		return
	var env := world_env.environment
	env.volumetric_fog_enabled = config["volumetric_fog"]
	env.ssil_enabled = config["ssil"]
	env.ssao_enabled = config["ssao"]
	env.glow_enabled = config["glow"]
	# Depth fog is cheap and carries the distance read once the volumetric pass
	# is gone, so it stays on at every tier — but it has to work harder.
	if not bool(config["volumetric_fog"]):
		env.fog_density = maxf(env.fog_density, 0.0045)


## Distance fade on every positional light. Without it the renderer considers
## all ~135 of them every frame no matter where the courier is standing.
func _apply_lights(config: Dictionary, scene_root: Node) -> void:
	_lights_faded = 0
	var root_node: Node = scene_root if scene_root != null else get_tree().current_scene
	if root_node == null:
		root_node = get_tree().root
	var begin := float(config["light_fade_begin"])
	var length := float(config["light_fade_length"])

	var stack: Array[Node] = [root_node]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.append(child)

		if node is DirectionalLight3D:
			var sun := node as DirectionalLight3D
			sun.shadow_enabled = config["directional_shadows"]
			sun.directional_shadow_max_distance = config["shadow_distance"]
			continue

		var light := node as Light3D
		if light == null:
			continue
		light.distance_fade_enabled = true
		light.distance_fade_begin = begin
		light.distance_fade_length = length
		light.distance_fade_shadow = begin
		_lights_faded += 1


func _apply_rain(config: Dictionary, scene_root: Node) -> void:
	var root_node: Node = scene_root if scene_root != null else get_tree().current_scene
	if root_node == null:
		return
	var rain := root_node.get_node_or_null("World/Rain")
	if rain != null and "intensity" in rain:
		rain.intensity = float(config["rain_intensity"])


func _find_world_environment(scene_root: Node) -> WorldEnvironment:
	var root_node: Node = scene_root if scene_root != null else get_tree().current_scene
	if root_node == null:
		return null
	var direct := root_node.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if direct != null:
		return direct
	var stack: Array[Node] = [root_node]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is WorldEnvironment:
			return node as WorldEnvironment
		for child in node.get_children():
			stack.append(child)
	return null


func get_tier() -> int:
	return _tier


func get_tier_name() -> String:
	return str(TIERS[_tier]["name"])
