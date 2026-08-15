class_name ChunkGenerator
extends RefCounted
## Builds the contents of one chunk from its coordinate and the world seed.
##
## Pure in the way that matters: `generate()` reads nothing but its arguments
## and the biome data, so a chunk is identical whichever direction the player
## walked in from. The RNG is seeded per chunk rather than shared, because a
## single stream would make every block depend on the order it was visited.
##
## Content is a direct descendant of the old `DistrictBlockout` — greybox
## towers, hung signage, cantilevered street lamps — with the shape of it moved
## into `Biome` data. The lighting choices in here were expensive to learn;
## the comments say why before changing them looks tempting.

const CONCRETE := preload("res://assets/materials/toon_concrete.tres")
const ASPHALT := preload("res://assets/materials/toon_asphalt.tres")
const NEON := preload("res://assets/materials/neon_cyan.tres")

const LAMP_HEIGHT := 6.0
const LAMP_ARM := 1.3
## Ground slabs overlap their neighbours by this much. Butt-jointed static
## boxes leave float-width cracks at the seam that a capsule can catch on.
const GROUND_OVERLAP := 0.2

## Lots whose centre falls inside this radius of the world origin stay empty, so
## the player always spawns into a plaza rather than inside a tower.
var plaza_radius: float = 26.0

var _world_seed: int = 0
var _biome_map := BiomeMap.new()


func configure(world_seed: int, biomes: Array[Biome]) -> void:
	_world_seed = world_seed
	_biome_map.configure(world_seed, biomes)


func world_seed() -> int:
	return _world_seed


func biome_at(world_position: Vector3) -> Biome:
	return _biome_map.biome_at(world_position)


func urbanisation(world_position: Vector3) -> float:
	return _biome_map.urbanisation(world_position)


func has_biomes() -> bool:
	return _biome_map.is_configured()


## Builds a detached chunk. The caller parents it and sets its transform.
func generate(coord: Vector2i) -> WorldChunk:
	var chunk := WorldChunk.new()
	chunk.name = "Chunk_%d_%d" % [coord.x, coord.y]
	chunk.coord = coord
	chunk.chunk_seed = WorldGrid.chunk_seed(_world_seed, coord)

	_spawn_ground(chunk)

	var biome := _biome_map.biome_at(WorldGrid.chunk_centre(coord))
	if biome == null:
		# Bare ground beats an exception: an unconfigured streamer should still
		# give the player something to stand on while the error is on screen.
		push_warning("ChunkGenerator has no biome for chunk %s" % str(coord))
		return chunk
	chunk.biome_id = biome.id

	var rng := RandomNumberGenerator.new()
	rng.seed = chunk.chunk_seed

	var first_lot := WorldGrid.first_lot_in_chunk(coord)
	for ix in WorldGrid.LOTS_PER_CHUNK:
		for iz in WorldGrid.LOTS_PER_CHUNK:
			_spawn_lot(chunk, biome, rng, Vector2i(first_lot.x + ix, first_lot.y + iz))

	_spawn_street_lamps(chunk, biome, rng, first_lot)
	return chunk


func _local(chunk: WorldChunk, world_position: Vector3) -> Vector3:
	return world_position - WorldGrid.chunk_origin(chunk.coord)


func _spawn_ground(chunk: WorldChunk) -> void:
	var centre := Vector3(WorldGrid.CHUNK_SIZE * 0.5, 0.0, WorldGrid.CHUNK_SIZE * 0.5)

	var body := StaticBody3D.new()
	body.name = "Ground"
	body.position = centre
	body.collision_layer = 1  # world
	body.collision_mask = 0
	chunk.add_child(body)

	var shape := CollisionShape3D.new()
	shape.name = "Collision"
	var box := BoxShape3D.new()
	box.size = Vector3(
		WorldGrid.CHUNK_SIZE + GROUND_OVERLAP, 1.0, WorldGrid.CHUNK_SIZE + GROUND_OVERLAP
	)
	shape.shape = box
	shape.position.y = -0.5  # top face flush with y = 0
	body.add_child(shape)

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	var plane := PlaneMesh.new()
	plane.size = Vector2(WorldGrid.CHUNK_SIZE, WorldGrid.CHUNK_SIZE)
	plane.subdivide_width = 2
	plane.subdivide_depth = 2
	mesh_instance.mesh = plane
	mesh_instance.material_override = ASPHALT
	body.add_child(mesh_instance)


func _spawn_lot(
	chunk: WorldChunk, biome: Biome, rng: RandomNumberGenerator, lot: Vector2i
) -> void:
	var world_centre := WorldGrid.lot_centre(lot)
	if Vector2(world_centre.x, world_centre.z).length() < plaza_radius:
		return

	# Every branch below consumes the stream in a fixed order, so the chunk is
	# reproducible even though the lots take different paths through it.
	if rng.randf() > biome.building_chance:
		if rng.randf() < biome.rubble_chance:
			_spawn_rubble(chunk, rng, _local(chunk, world_centre), lot)
		return

	_spawn_building(chunk, biome, rng, _local(chunk, world_centre))


func _spawn_building(
	chunk: WorldChunk, biome: Biome, rng: RandomNumberGenerator, centre: Vector3
) -> void:
	var width := rng.randf_range(biome.min_footprint, biome.max_footprint)
	var depth := rng.randf_range(biome.min_footprint, biome.max_footprint)
	var height := lerpf(
		biome.min_height, biome.max_height, pow(rng.randf(), biome.height_bias)
	)
	var size := Vector3(width, height, depth)

	var jitter := Vector3(rng.randf_range(-2.0, 2.0), 0.0, rng.randf_range(-2.0, 2.0))

	var body := StaticBody3D.new()
	body.name = "Building_%02d" % chunk.building_count
	body.position = centre + jitter + Vector3(0.0, height * 0.5, 0.0)
	body.rotation.y = rng.randf_range(-0.06, 0.06)
	body.collision_layer = 1  # world
	body.collision_mask = 0
	chunk.add_child(body)

	var shape := CollisionShape3D.new()
	shape.name = "Collision"
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	mesh_instance.mesh = box_mesh
	mesh_instance.material_override = CONCRETE
	body.add_child(mesh_instance)

	chunk.building_count += 1

	if rng.randf() < biome.sign_chance:
		_spawn_sign(chunk, biome, rng, body, size)


func _spawn_sign(
	chunk: WorldChunk,
	biome: Biome,
	rng: RandomNumberGenerator,
	building: StaticBody3D,
	size: Vector3
) -> void:
	# Pick a face and hang the sign a little proud of the wall.
	var faces := [
		{"normal": Vector3.FORWARD, "offset": Vector3(0.0, 0.0, -size.z * 0.5 - 0.25)},
		{"normal": Vector3.BACK, "offset": Vector3(0.0, 0.0, size.z * 0.5 + 0.25)},
		{"normal": Vector3.LEFT, "offset": Vector3(-size.x * 0.5 - 0.25, 0.0, 0.0)},
		{"normal": Vector3.RIGHT, "offset": Vector3(size.x * 0.5 + 0.25, 0.0, 0.0)},
	]
	var face: Dictionary = faces[rng.randi() % faces.size()]
	var normal: Vector3 = face["normal"]
	var offset: Vector3 = face["offset"]

	# Signs cluster in the lower third — that is where the player will see them.
	var local_y := rng.randf_range(-size.y * 0.35, size.y * 0.15)

	var sign_size := Vector3(rng.randf_range(1.2, 3.2), rng.randf_range(2.5, 7.0), 0.3)
	if rng.randf() >= 0.6:
		var swap := sign_size.x
		sign_size.x = sign_size.y
		sign_size.y = swap

	var holder := Node3D.new()
	holder.name = "Sign_%02d" % chunk.sign_count
	holder.position = offset + Vector3(0.0, local_y, 0.0)
	building.add_child(holder)

	var tint := biome.pick_tint(rng)

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	var box_mesh := BoxMesh.new()
	box_mesh.size = sign_size
	mesh_instance.mesh = box_mesh
	# Duplicated per sign so the flicker phase does not desync every other sign
	# on the street when one of them is set.
	var material: ShaderMaterial = NEON.duplicate()
	material.set_shader_parameter("neon_color", tint)
	material.set_shader_parameter("energy", biome.sign_energy)
	material.set_shader_parameter("phase_offset", rng.randf_range(0.0, 100.0))
	material.set_shader_parameter(
		"dropout_chance", rng.randf_range(0.0, biome.max_sign_dropout)
	)
	mesh_instance.material_override = material
	holder.add_child(mesh_instance)

	var light := OmniLight3D.new()
	light.name = "SignLight"
	light.light_color = tint
	light.light_energy = biome.sign_light_energy
	light.omni_range = biome.sign_light_range
	light.shadow_enabled = false  # dozens of these; shadows are not worth the cost
	light.position = normal * -1.5
	light.add_to_group(WorldChunk.DETAIL_GROUP)
	holder.add_child(light)

	chunk.sign_count += 1


func _spawn_rubble(
	chunk: WorldChunk, rng: RandomNumberGenerator, centre: Vector3, lot: Vector2i
) -> void:
	var holder := Node3D.new()
	holder.name = "Rubble_%d_%d" % [lot.x, lot.y]
	holder.position = centre
	chunk.add_child(holder)

	var pieces := rng.randi_range(2, 5)
	for i in pieces:
		var size := Vector3(
			rng.randf_range(2.0, 6.0),
			rng.randf_range(0.6, 2.4),
			rng.randf_range(2.0, 6.0),
		)
		var body := StaticBody3D.new()
		body.name = "Piece_%d" % i
		body.position = Vector3(
			rng.randf_range(-6.0, 6.0), size.y * 0.5, rng.randf_range(-6.0, 6.0)
		)
		body.rotation = Vector3(
			rng.randf_range(-0.12, 0.12),
			rng.randf_range(-PI, PI),
			rng.randf_range(-0.12, 0.12),
		)
		body.collision_layer = 1  # world
		body.collision_mask = 0
		holder.add_child(body)

		var shape := CollisionShape3D.new()
		shape.name = "Collision"
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
		body.add_child(shape)

		var mesh_instance := MeshInstance3D.new()
		mesh_instance.name = "Mesh"
		var box_mesh := BoxMesh.new()
		box_mesh.size = size
		mesh_instance.mesh = box_mesh
		mesh_instance.material_override = CONCRETE
		body.add_child(mesh_instance)


func _spawn_street_lamps(
	chunk: WorldChunk, biome: Biome, rng: RandomNumberGenerator, first_lot: Vector2i
) -> void:
	var lamps := Node3D.new()
	lamps.name = "StreetLamps"
	chunk.add_child(lamps)

	# A chunk owns the corners at its low edges only, so the shared corner
	# between two chunks gets exactly one lamp.
	for ix in WorldGrid.LOTS_PER_CHUNK:
		for iz in WorldGrid.LOTS_PER_CHUNK:
			var lot := Vector2i(first_lot.x + ix, first_lot.y + iz)
			# Thin them out — a lamp at every junction is too bright — but keep
			# the *odd* diagonal, not the even one. The even diagonal puts a lamp
			# site on the world origin, which the plaza rule below then deletes,
			# leaving the spawn unlit for 45 m in every direction. Odd parity
			# rings the plaza at 32 m instead, at identical lamp density.
			#
			# posmod, not %: GDScript's modulo keeps the sign of the dividend,
			# which would flip this parity across the west and north half-planes.
			if posmod(lot.x + lot.y, 2) != 1:
				continue
			if rng.randf() > biome.lamp_chance:
				continue

			var world_position := WorldGrid.lot_corner(lot)
			if Vector2(world_position.x, world_position.z).length() < plaza_radius * 0.5:
				continue

			_spawn_lamp(lamps, biome, rng, _local(chunk, world_position))


func _spawn_lamp(
	parent: Node3D, biome: Biome, rng: RandomNumberGenerator, position_local: Vector3
) -> void:
	var post := Node3D.new()
	post.name = "Lamp"
	post.position = position_local
	post.rotation.y = rng.randf_range(-PI, PI)
	parent.add_child(post)

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Post"
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.09
	cylinder.bottom_radius = 0.13
	cylinder.height = LAMP_HEIGHT
	mesh_instance.mesh = cylinder
	mesh_instance.position.y = LAMP_HEIGHT * 0.5
	mesh_instance.material_override = CONCRETE
	post.add_child(mesh_instance)

	# Cantilevered arm, so the lamp head hangs over the street rather than
	# sitting inside the post — a light co-located with its own geometry blows
	# that geometry out to a white blob.
	var arm := MeshInstance3D.new()
	arm.name = "Arm"
	var arm_mesh := BoxMesh.new()
	arm_mesh.size = Vector3(LAMP_ARM, 0.12, 0.12)
	arm.mesh = arm_mesh
	arm.position = Vector3(LAMP_ARM * 0.5, LAMP_HEIGHT - 0.1, 0.0)
	arm.material_override = CONCRETE
	post.add_child(arm)

	var head := MeshInstance3D.new()
	head.name = "Head"
	var head_mesh := BoxMesh.new()
	head_mesh.size = Vector3(0.5, 0.18, 0.32)
	head.mesh = head_mesh
	head.position = Vector3(LAMP_ARM, LAMP_HEIGHT - 0.22, 0.0)
	# Sodium-vapour amber against the magenta/cyan signage.
	var head_material: ShaderMaterial = NEON.duplicate()
	head_material.set_shader_parameter("neon_color", biome.lamp_color)
	head_material.set_shader_parameter("energy", 2.2)
	head_material.set_shader_parameter("flicker_amount", 0.05)
	head_material.set_shader_parameter("dropout_chance", 0.0)
	head_material.set_shader_parameter("phase_offset", rng.randf_range(0.0, 100.0))
	head.material_override = head_material
	post.add_child(head)

	# A downward spot rather than an omni: it pools on the street instead of
	# lighting the underside of every balcony and the sky.
	var light := SpotLight3D.new()
	light.name = "LampLight"
	light.position = Vector3(LAMP_ARM, LAMP_HEIGHT - 0.45, 0.0)
	light.rotation.x = -PI * 0.5
	light.light_color = biome.lamp_color
	light.light_energy = biome.lamp_energy
	light.spot_range = 17.0
	light.spot_angle = 62.0
	light.spot_angle_attenuation = 1.4
	light.shadow_enabled = false
	light.add_to_group(WorldChunk.DETAIL_GROUP)
	post.add_child(light)
