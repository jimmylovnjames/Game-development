class_name RainSystem
extends Node3D
## Camera-following rain volume: streak particles above, splash rings on the
## ground. Particles simulate in world space (local_coords = false) so the
## volume can chase the camera without dragging already-fallen drops with it.
##
## The node positions itself on the ground under the active camera every frame;
## gameplay code only touches `intensity`.

const STREAK_MATERIAL := preload("res://assets/materials/rain_streak.tres")
const SPLASH_MATERIAL := preload("res://assets/materials/rain_splash.tres")

@export_group("Coverage")
## Half-extent of the emission box around the camera.
@export var radius: float = 22.0
## Height above the emitter where drops spawn.
@export var fall_height: float = 20.0
@export var wind := Vector2(1.4, 0.5)

@export_group("Density")
## 0.0 stops emission, 1.0 is a downpour.
@export_range(0.0, 1.0) var intensity: float = 0.85:
	set(value):
		intensity = clampf(value, 0.0, 1.0)
		_apply_intensity()
@export var max_streaks: int = 850
@export var max_splashes: int = 240

var _streaks: GPUParticles3D
var _splashes: GPUParticles3D


func _ready() -> void:
	_streaks = _make_streaks()
	_splashes = _make_splashes()
	add_child(_streaks)
	add_child(_splashes)
	add_to_group("rain_volume")
	_apply_intensity()


func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var target := camera.global_position
	target.y = 0.0
	global_position = target


func _apply_intensity() -> void:
	if _streaks == null or _splashes == null:
		return
	var on := intensity > 0.01
	_streaks.emitting = on
	_splashes.emitting = on
	_streaks.amount_ratio = intensity
	_splashes.amount_ratio = intensity


func _make_streaks() -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = "Streaks"
	particles.amount = max_streaks
	# Lifetime x velocity must exceed fall_height or drops die mid-air.
	particles.lifetime = fall_height / 19.0
	particles.preprocess = particles.lifetime
	particles.local_coords = false
	particles.visibility_aabb = AABB(
		Vector3(-radius - 10.0, -4.0, -radius - 10.0),
		Vector3((radius + 10.0) * 2.0, fall_height + 8.0, (radius + 10.0) * 2.0)
	)

	var material := ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	material.emission_box_extents = Vector3(radius, 0.5, radius)
	material.direction = Vector3(wind.x, -1.0, wind.y).normalized()
	material.spread = 1.5
	material.initial_velocity_min = 21.0
	material.initial_velocity_max = 26.0
	material.gravity = Vector3(0.0, -2.0, 0.0)
	# Stretch the drop's Y axis along its motion so wind slants the streaks.
	material.particle_flag_align_y = true
	material.color_ramp = _make_fade_ramp(0.08, 0.85)
	particles.process_material = material

	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.02, 0.6, 0.02)
	mesh.material = STREAK_MATERIAL
	particles.draw_pass_1 = mesh

	particles.position = Vector3(0.0, fall_height, 0.0)
	return particles


func _make_splashes() -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = "Splashes"
	particles.amount = max_splashes
	particles.lifetime = 0.38
	particles.preprocess = 0.38
	particles.local_coords = false
	particles.visibility_aabb = AABB(
		Vector3(-radius - 4.0, -1.0, -radius - 4.0),
		Vector3((radius + 4.0) * 2.0, 4.0, (radius + 4.0) * 2.0)
	)

	var material := ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	material.emission_box_extents = Vector3(radius, 0.05, radius)
	material.direction = Vector3.UP
	material.spread = 0.0
	material.initial_velocity_min = 0.0
	material.initial_velocity_max = 0.0
	material.gravity = Vector3.ZERO
	material.scale_min = 0.7
	material.scale_max = 1.3
	material.scale_curve = _make_growth_curve()
	material.color_ramp = _make_fade_ramp(0.0, 1.0)
	particles.process_material = material

	# A flat quad lying on the street; the shader draws the ring shape and the
	# process material grows it over the particle's short life.
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(0.55, 0.55)
	mesh.orientation = PlaneMesh.FACE_Y
	mesh.material = SPLASH_MATERIAL
	particles.draw_pass_1 = mesh

	particles.position = Vector3(0.0, 0.04, 0.0)
	return particles


func _make_fade_ramp(fade_in: float, fade_out_start: float) -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 1.0, 1.0, 0.0 if fade_in > 0.0 else 1.0))
	gradient.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	gradient.add_point(fade_in, Color(1.0, 1.0, 1.0, 1.0))
	gradient.add_point(fade_out_start, Color(1.0, 1.0, 1.0, 1.0))
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	return texture


func _make_growth_curve() -> CurveTexture:
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.2))
	curve.add_point(Vector2(1.0, 1.0))
	var texture := CurveTexture.new()
	texture.curve = curve
	return texture
