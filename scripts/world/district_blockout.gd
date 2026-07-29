class_name DistrictBlockout
extends Node3D
## Seeded placeholder city block: greybox towers, neon signage and street lamps.
##
## This is scaffolding, not the shipping world generator. It exists so the
## lighting, cel shader and camera can be judged against something with real
## silhouettes and real light sources instead of an empty plane. The eventual
## chunk streamer under worlds/ replaces it wholesale — keep gameplay code from
## depending on anything here.

const CONCRETE := preload("res://assets/materials/toon_concrete.tres")
const NEON_MAGENTA := preload("res://assets/materials/neon_magenta.tres")
const NEON_CYAN := preload("res://assets/materials/neon_cyan.tres")

@export_group("Layout")
## Same seed always produces the same block, so bug reports stay reproducible.
@export var world_seed: int = 20771113
## Buildings are placed on a grid_size x grid_size lattice of lots.
@export var grid_size: int = 7
@export var lot_size: float = 22.0
@export var street_width: float = 9.0
## Lots inside this radius of the origin stay empty so the player has a plaza.
@export var plaza_radius: float = 26.0

@export_group("Buildings")
@export var min_height: float = 8.0
@export var max_height: float = 46.0
@export var min_footprint: float = 8.0
@export var max_footprint: float = 15.0
## Chance a lot is a rubble pile / vacant slab instead of a tower.
@export_range(0.0, 1.0) var vacancy_chance: float = 0.18

@export_group("Lighting")
@export var sign_chance: float = 0.55
@export var sign_light_energy: float = 3.5
@export var sign_light_range: float = 18.0
@export var street_lamp_energy: float = 2.6

const LAMP_HEIGHT := 6.0
const LAMP_ARM := 1.3
const LAMP_COLOR := Color(1.0, 0.68, 0.36)

var _rng := RandomNumberGenerator.new()
var _building_count: int = 0
var _sign_count: int = 0


func _ready() -> void:
	generate()


## Rebuilds the block from scratch. Safe to call repeatedly.
func generate() -> void:
	for child in get_children():
		child.queue_free()
	_building_count = 0
	_sign_count = 0

	_rng.seed = world_seed

	var stride := lot_size + street_width
	var half := (grid_size - 1) * 0.5

	for gx in grid_size:
		for gz in grid_size:
			var centre := Vector3((gx - half) * stride, 0.0, (gz - half) * stride)
			if centre.length() < plaza_radius:
				continue
			if _rng.randf() < vacancy_chance:
				_spawn_rubble(centre)
				continue
			_spawn_building(centre)

	_spawn_street_lamps(stride, half)

	print("[DistrictBlockout] seed=%d buildings=%d signs=%d" % [
		world_seed, _building_count, _sign_count,
	])


func _spawn_building(centre: Vector3) -> void:
	var width := _rng.randf_range(min_footprint, max_footprint)
	var depth := _rng.randf_range(min_footprint, max_footprint)
	# Bias toward shorter buildings so the few tall ones actually read as tall.
	var height := lerpf(min_height, max_height, pow(_rng.randf(), 2.2))
	var size := Vector3(width, height, depth)

	var jitter := Vector3(
		_rng.randf_range(-2.0, 2.0), 0.0, _rng.randf_range(-2.0, 2.0)
	)
	var origin := centre + jitter + Vector3(0.0, height * 0.5, 0.0)

	var body := StaticBody3D.new()
	body.name = "Building_%02d" % _building_count
	body.position = origin
	body.rotation.y = _rng.randf_range(-0.06, 0.06)
	body.collision_layer = 1  # world
	body.collision_mask = 0
	add_child(body)

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)

	var mesh_instance := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	mesh_instance.mesh = box_mesh
	mesh_instance.material_override = CONCRETE
	body.add_child(mesh_instance)

	_building_count += 1

	if _rng.randf() < sign_chance:
		_spawn_sign(body, size)


func _spawn_sign(building: StaticBody3D, size: Vector3) -> void:
	# Pick a face and hang the sign a little proud of the wall.
	var faces := [
		{"normal": Vector3.FORWARD, "offset": Vector3(0.0, 0.0, -size.z * 0.5 - 0.25)},
		{"normal": Vector3.BACK, "offset": Vector3(0.0, 0.0, size.z * 0.5 + 0.25)},
		{"normal": Vector3.LEFT, "offset": Vector3(-size.x * 0.5 - 0.25, 0.0, 0.0)},
		{"normal": Vector3.RIGHT, "offset": Vector3(size.x * 0.5 + 0.25, 0.0, 0.0)},
	]
	var face: Dictionary = faces[_rng.randi() % faces.size()]
	var normal: Vector3 = face["normal"]
	var offset: Vector3 = face["offset"]

	# Signs cluster in the lower third — that is where the player will see them.
	var local_y := _rng.randf_range(-size.y * 0.35, size.y * 0.15)

	var sign_size := Vector3(
		_rng.randf_range(1.2, 3.2), _rng.randf_range(2.5, 7.0), 0.3
	)
	var vertical := _rng.randf() < 0.6
	if not vertical:
		var swap := sign_size.x
		sign_size.x = sign_size.y
		sign_size.y = swap

	var holder := Node3D.new()
	holder.name = "Sign_%02d" % _sign_count
	holder.position = offset + Vector3(0.0, local_y, 0.0)
	building.add_child(holder)

	var mesh_instance := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = sign_size
	mesh_instance.mesh = box_mesh
	# Duplicate so per-sign flicker phase does not desync every other sign.
	var material: ShaderMaterial = (
		NEON_MAGENTA if _rng.randf() < 0.55 else NEON_CYAN
	).duplicate()
	material.set_shader_parameter("phase_offset", _rng.randf_range(0.0, 100.0))
	material.set_shader_parameter("dropout_chance", _rng.randf_range(0.0, 0.12))
	mesh_instance.material_override = material
	holder.add_child(mesh_instance)

	var light := OmniLight3D.new()
	light.light_color = material.get_shader_parameter("neon_color")
	light.light_energy = sign_light_energy
	light.omni_range = sign_light_range
	light.shadow_enabled = false  # dozens of these; shadows are not worth the cost
	light.position = normal * -1.5
	holder.add_child(light)

	_sign_count += 1


func _spawn_rubble(centre: Vector3) -> void:
	var chunks := _rng.randi_range(2, 5)
	var holder := Node3D.new()
	holder.name = "Rubble_%02d_%02d" % [int(centre.x), int(centre.z)]
	holder.position = centre
	add_child(holder)

	for i in chunks:
		var size := Vector3(
			_rng.randf_range(2.0, 6.0),
			_rng.randf_range(0.6, 2.4),
			_rng.randf_range(2.0, 6.0),
		)
		var body := StaticBody3D.new()
		body.position = Vector3(
			_rng.randf_range(-6.0, 6.0), size.y * 0.5, _rng.randf_range(-6.0, 6.0)
		)
		body.rotation = Vector3(
			_rng.randf_range(-0.12, 0.12),
			_rng.randf_range(-PI, PI),
			_rng.randf_range(-0.12, 0.12),
		)
		body.collision_layer = 1
		body.collision_mask = 0
		holder.add_child(body)

		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
		body.add_child(shape)

		var mesh_instance := MeshInstance3D.new()
		var box_mesh := BoxMesh.new()
		box_mesh.size = size
		mesh_instance.mesh = box_mesh
		mesh_instance.material_override = CONCRETE
		body.add_child(mesh_instance)


func _spawn_street_lamps(stride: float, half: float) -> void:
	var lamps := Node3D.new()
	lamps.name = "StreetLamps"
	add_child(lamps)

	for gx in grid_size + 1:
		for gz in grid_size + 1:
			if (gx + gz) % 2 == 1:
				continue  # thin them out; a lamp at every junction is too bright
			var pos := Vector3(
				(gx - half - 0.5) * stride, 0.0, (gz - half - 0.5) * stride
			)
			if pos.length() < plaza_radius * 0.5:
				continue

			var post := Node3D.new()
			post.position = pos
			post.rotation.y = _rng.randf_range(-PI, PI)
			lamps.add_child(post)

			var mesh_instance := MeshInstance3D.new()
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = 0.09
			cylinder.bottom_radius = 0.13
			cylinder.height = LAMP_HEIGHT
			mesh_instance.mesh = cylinder
			mesh_instance.position.y = LAMP_HEIGHT * 0.5
			mesh_instance.material_override = CONCRETE
			post.add_child(mesh_instance)

			# Cantilevered arm, so the lamp head hangs over the street rather than
			# sitting inside the post — a light co-located with its own geometry
			# blows that geometry out to a white blob.
			var arm := MeshInstance3D.new()
			var arm_mesh := BoxMesh.new()
			arm_mesh.size = Vector3(LAMP_ARM, 0.12, 0.12)
			arm.mesh = arm_mesh
			arm.position = Vector3(LAMP_ARM * 0.5, LAMP_HEIGHT - 0.1, 0.0)
			arm.material_override = CONCRETE
			post.add_child(arm)

			var head := MeshInstance3D.new()
			var head_mesh := BoxMesh.new()
			head_mesh.size = Vector3(0.5, 0.18, 0.32)
			head.mesh = head_mesh
			head.position = Vector3(LAMP_ARM, LAMP_HEIGHT - 0.22, 0.0)
			# Sodium-vapour amber against the magenta/cyan signage.
			var head_material: ShaderMaterial = NEON_CYAN.duplicate()
			head_material.set_shader_parameter("neon_color", LAMP_COLOR)
			head_material.set_shader_parameter("energy", 2.2)
			head_material.set_shader_parameter("flicker_amount", 0.05)
			head_material.set_shader_parameter("dropout_chance", 0.0)
			head_material.set_shader_parameter("phase_offset", _rng.randf_range(0.0, 100.0))
			head.material_override = head_material
			post.add_child(head)

			# A downward spot rather than an omni: it pools on the street instead
			# of lighting the underside of every balcony and the sky.
			var light := SpotLight3D.new()
			light.position = Vector3(LAMP_ARM, LAMP_HEIGHT - 0.45, 0.0)
			light.rotation.x = -PI * 0.5
			light.light_color = LAMP_COLOR
			light.light_energy = street_lamp_energy
			light.spot_range = 17.0
			light.spot_angle = 62.0
			light.spot_angle_attenuation = 1.4
			light.shadow_enabled = false
			post.add_child(light)


## First safe standing spot for the player, at the centre of the plaza.
func get_spawn_point() -> Vector3:
	return Vector3(0.0, 1.2, 0.0)
