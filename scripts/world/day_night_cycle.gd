class_name DayNightCycle
extends Node3D
## Day-Night cycle and atmospheric lighting controller for NeonWastesRPG.
##
## Manages Sun and Moon celestial paths, sky color gradients, ambient lighting,
## volumetric fog moods, and day/night toggles.
##
## Supports real-time time progression, manual time scrubbing, and time presets:
## 0: Night (Noir Neon), 1: Dawn (Amber/Violet), 2: Noon (Dusty Harsh Sunlight), 3: Dusk (Blood Orange/Cyan).

signal time_of_day_changed(time_normalized: float, is_day: bool)

enum TimePreset {
	NOIR_NIGHT,
	DESERT_DAWN,
	HARSH_NOON,
	CASCADE_DUSK,
}

@export_group("Cycle")
## Progress 0.0 to 1.0 (0.0 = midnight, 0.25 = sunrise 6am, 0.5 = noon 12pm, 0.75 = sunset 6pm, 1.0 = midnight).
@export_range(0.0, 1.0) var time_of_day: float = 0.0:
	set(val):
		time_of_day = fposmod(val, 1.0)
		_apply_cycle()
## Cycle length in real-world seconds (0 = cycle paused).
@export var day_length_seconds: float = 180.0
@export var auto_advance: bool = true

@export_group("References")
@export var world_environment: WorldEnvironment
@export var sun_light: DirectionalLight3D
@export var moon_light: DirectionalLight3D

var _env: Environment
var _sky_mat: ProceduralSkyMaterial
var _is_day: bool = false


func _ready() -> void:
	if world_environment and world_environment.environment:
		_env = world_environment.environment
		if _env.sky and _env.sky.sky_material is ProceduralSkyMaterial:
			_sky_mat = _env.sky.sky_material as ProceduralSkyMaterial
	
	_apply_cycle()


func _process(delta: float) -> void:
	if auto_advance and day_length_seconds > 0.0:
		time_of_day = fposmod(time_of_day + (delta / day_length_seconds), 1.0)


## Quick toggle for testing/keybind
func toggle_day_night() -> void:
	if is_daytime():
		time_of_day = 0.0  # Noir Night
	else:
		time_of_day = 0.5  # Harsh Noon


func set_preset(preset: TimePreset) -> void:
	match preset:
		TimePreset.NOIR_NIGHT:
			time_of_day = 0.0
		TimePreset.DESERT_DAWN:
			time_of_day = 0.25
		TimePreset.HARSH_NOON:
			time_of_day = 0.5
		TimePreset.CASCADE_DUSK:
			time_of_day = 0.75


func is_daytime() -> bool:
	return time_of_day >= 0.22 and time_of_day <= 0.78


func get_time_string() -> String:
	var total_minutes := int(time_of_day * 24.0 * 60.0)
	var hours := (total_minutes / 60) % 24
	var minutes := total_minutes % 60
	var period := "AM" if hours < 12 else "PM"
	var display_hour := hours % 12
	if display_hour == 0:
		display_hour = 12
	return "%02d:%02d %s (%s)" % [
		display_hour, minutes, period,
		"Day" if is_daytime() else "Night"
	]


func _apply_cycle() -> void:
	var angle := time_of_day * TAU - PI * 0.5  # 0.5 (noon) = top (PI/2), 0.0 (midnight) = bottom (-PI/2)
	var sun_dir := Vector3(cos(angle), sin(angle), -0.45).normalized()
	var moon_dir := -sun_dir
	
	# Sun lighting
	if sun_light:
		if sun_dir.y > -0.15:
			sun_light.visible = true
			sun_light.look_at_from_position(Vector3.ZERO, -sun_dir, Vector3.UP)
			var sun_intensity := clampf((sun_dir.y + 0.15) / 0.5, 0.0, 1.0)
			# Noon is warm dusty amber-white; sunset/sunrise is blood-orange
			var sun_color := Color(1.0, 0.92, 0.78).lerp(Color(1.0, 0.42, 0.18), 1.0 - clampf(sun_dir.y, 0.0, 1.0))
			sun_light.light_color = sun_color
			sun_light.light_energy = lerpf(0.0, 1.4, sun_intensity)
		else:
			sun_light.visible = false
			sun_light.light_energy = 0.0
	
	# Moon lighting (cold cyan-violet noir key)
	if moon_light:
		if moon_dir.y > -0.15:
			moon_light.visible = true
			moon_light.look_at_from_position(Vector3.ZERO, -moon_dir, Vector3.UP)
			var moon_intensity := clampf((moon_dir.y + 0.15) / 0.5, 0.0, 1.0)
			moon_light.light_color = Color(0.54, 0.61, 1.0)
			moon_light.light_energy = lerpf(0.0, 0.55, moon_intensity)
		else:
			moon_light.visible = false
			moon_light.light_energy = 0.0

	# Atmosphere & Sky colors
	var day_factor := clampf((sun_dir.y + 0.1) / 0.6, 0.0, 1.0)
	var twilight_factor := clampf(1.0 - absf(sun_dir.y) / 0.35, 0.0, 1.0)
	
	if _sky_mat:
		# Sky zenith
		var night_top := Color(0.043, 0.031, 0.094)
		var day_top := Color(0.18, 0.38, 0.68)
		var dusk_top := Color(0.12, 0.08, 0.28)
		var top_col := night_top.lerp(day_top, day_factor).lerp(dusk_top, twilight_factor * 0.5)
		_sky_mat.sky_top_color = top_col

		# Sky horizon
		var night_horizon := Color(0.31, 0.067, 0.235)  # Neon glow
		var day_horizon := Color(0.85, 0.72, 0.55)    # Desert haze
		var dusk_horizon := Color(0.95, 0.32, 0.22)   # Blood orange
		var horiz_col := night_horizon.lerp(day_horizon, day_factor).lerp(dusk_horizon, twilight_factor * 0.7)
		_sky_mat.sky_horizon_color = horiz_col
		
		# Ground horizon
		var night_g_horizon := Color(0.18, 0.055, 0.14)
		var day_g_horizon := Color(0.52, 0.42, 0.32)
		_sky_mat.ground_horizon_color = night_g_horizon.lerp(day_g_horizon, day_factor)

	if _env:
		# Ambient lighting
		var night_amb := Color(0.192, 0.153, 0.337)
		var day_amb := Color(0.48, 0.44, 0.52)
		_env.ambient_light_color = night_amb.lerp(day_amb, day_factor)
		_env.ambient_light_energy = lerpf(1.1, 1.35, day_factor)
		
		# Volumetric Fog
		var night_fog_emit := Color(0.075, 0.02, 0.11)
		var day_fog_emit := Color(0.0, 0.0, 0.0)
		_env.volumetric_fog_emission = night_fog_emit.lerp(day_fog_emit, day_factor)
		
		var night_fog_albedo := Color(0.5, 0.42, 0.62)
		var day_fog_albedo := Color(0.82, 0.75, 0.68)
		_env.volumetric_fog_albedo = night_fog_albedo.lerp(day_fog_albedo, day_factor)
		
		# Exposure / Tonemap
		_env.tonemap_exposure = lerpf(1.0, 1.08, day_factor)
	
	var new_is_day := is_daytime()
	if new_is_day != _is_day:
		_is_day = new_is_day
		time_of_day_changed.emit(time_of_day, _is_day)
