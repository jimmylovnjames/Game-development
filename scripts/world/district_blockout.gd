class_name DistrictBlockout
extends Node3D
## Seeded placeholder city block & wasteland scenery:
## Tiered megastructures, holographic billboards, street barriers, overhead pipes & cables,
## street vendors/kiosks, steam vents, debris/crates, and perimeter wasteland dunes.
##
## Scaffolding with rich silhouette, lighting, comic-shading, and day/night responsiveness.

const CONCRETE := preload("res://assets/materials/toon_concrete.tres")
const NEON_MAGENTA := preload("res://assets/materials/neon_magenta.tres")
const NEON_CYAN := preload("res://assets/materials/neon_cyan.tres")
const METAL_RUST := preload("res://assets/materials/toon_metal_rust.tres")
const SAND := preload("res://assets/materials/toon_sand.tres")

@export_group("Layout")
## Same seed always produces the same block, so bug reports stay reproducible.
@export var world_seed: int = 20771113
## Buildings are placed on a grid_size x grid_size lattice of lots.
@export var grid_size: int = 7
@export var lot_size: float = 22.0
@export var street_width: float = 9.0
## Lots inside this radius of the origin stay empty so the player has an active plaza.
@export var plaza_radius: float = 26.0

@export_group("Buildings")
@export var min_height: float = 12.0
@export var max_height: float = 54.0
@export var min_footprint: float = 9.0
@export var max_footprint: float = 16.0
## Chance a lot is a rubble pile / vacant slab instead of a tower.
@export_range(0.0, 1.0) var vacancy_chance: float = 0.15

@export_group("Lighting")
@export var sign_chance: float = 0.7
@export var sign_light_energy: float = 3.5
@export var sign_light_range: float = 18.0
@export var street_lamp_energy: float = 2.6

const LAMP_HEIGHT := 6.0
const LAMP_ARM := 1.3
const LAMP_COLOR := Color(1.0, 0.68, 0.36)

var _rng := RandomNumberGenerator.new()
var _building_count: int = 0
var _sign_count: int = 0
var _prop_count: int = 0
var _building_positions: Array[Vector3] = []


func _ready() -> void:
	generate()


## Rebuilds the block from scratch. Safe to call repeatedly.
func generate() -> void:
	for child in get_children():
		child.queue_free()
	_building_count = 0
	_sign_count = 0
	_prop_count = 0
	_building_positions.clear()

	_rng.seed = world_seed

	var stride := lot_size + street_width
	var half := (grid_size - 1) * 0.5

	# 1. Spawn Buildings & Vacant Rubble Lots
	for gx in grid_size:
		for gz in grid_size:
			var centre := Vector3((gx - half) * stride, 0.0, (gz - half) * stride)
			if centre.length() < plaza_radius:
				continue
			if _rng.randf() < vacancy_chance:
				_spawn_rubble(centre)
				continue
			_spawn_building(centre)

	# 2. Spawn Street Lamps
	_spawn_street_lamps(stride, half)

	# 3. Spawn Street Props (Barriers, Dumpsters, Crates, Steam vents, Kiosks)
	_spawn_street_furniture(stride, half)

	# 4. Spawn Overhead Power Cables & Pipes
	_spawn_overhead_infrastructure()

	# 5. Spawn Plaza Centrepiece (Hologram Pillar, Benches, Monument)
	_spawn_plaza_centrepiece()

	# 6. Spawn Outer Wasteland Dunes & Ruined Towers
	_spawn_wasteland_perimeter(stride * (half + 1.2))

	print("[DistrictBlockout] seed=%d buildings=%d signs=%d props=%d" % [
		world_seed, _building_count, _sign_count, _prop_count,
	])


func _spawn_building(centre: Vector3) -> void:
	var width := _rng.randf_range(min_footprint, max_footprint)
	var depth := _rng.randf_range(min_footprint, max_footprint)
	# Bias toward varied heights: tiered silhouette
	var height := lerpf(min_height, max_height, pow(_rng.randf(), 1.8))
	var size := Vector3(width, height, depth)

	var jitter := Vector3(
		_rng.randf_range(-1.8, 1.8), 0.0, _rng.randf_range(-1.8, 1.8)
	)
	var base_origin := centre + jitter
	_building_positions.append(base_origin)
	var origin := base_origin + Vector3(0.0, height * 0.5, 0.0)

	var body := StaticBody3D.new()
	body.name = "Building_%02d" % _building_count
	body.position = origin
	body.rotation.y = _rng.randf_range(-0.05, 0.05)
	body.collision_layer = 1  # world
	body.collision_mask = 0
	add_child(body)

	# Main Tower Body
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

	# Tiered setback roof / AC utility deck for richer sci-fi silhouette
	if height > 22.0:
		var tier_h := _rng.randf_range(4.0, 10.0)
		var tier_size := Vector3(width * 0.65, tier_h, depth * 0.65)
		var tier_mesh := MeshInstance3D.new()
		var t_mesh := BoxMesh.new()
		t_mesh.size = tier_size
		tier_mesh.mesh = t_mesh
		tier_mesh.material_override = METAL_RUST
		tier_mesh.position = Vector3(0.0, height * 0.5 + tier_h * 0.5, 0.0)
		body.add_child(tier_mesh)

		# Rooftop antenna/spire with blinking warning beacon
		if _rng.randf() < 0.6:
			var spire_h := _rng.randf_range(5.0, 12.0)
			var spire := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.04
			cyl.bottom_radius = 0.14
			cyl.height = spire_h
			spire.mesh = cyl
			spire.material_override = METAL_RUST
			spire.position = Vector3(0.0, height * 0.5 + tier_h + spire_h * 0.5, 0.0)
			body.add_child(spire)

			var beacon := OmniLight3D.new()
			beacon.light_color = Color(1.0, 0.2, 0.2)
			beacon.light_energy = 2.0
			beacon.omni_range = 10.0
			beacon.position = Vector3(0.0, spire_h * 0.5, 0.0)
			spire.add_child(beacon)

	# Wall piping & conduit details
	if _rng.randf() < 0.75:
		var pipe_mesh := MeshInstance3D.new()
		var cyl_pipe := CylinderMesh.new()
		cyl_pipe.top_radius = 0.18
		cyl_pipe.bottom_radius = 0.18
		cyl_pipe.height = height * 0.85
		pipe_mesh.mesh = cyl_pipe
		pipe_mesh.material_override = METAL_RUST
		var px := (width * 0.5 + 0.1) * (1.0 if _rng.randf() > 0.5 else -1.0)
		var pz := _rng.randf_range(-depth * 0.35, depth * 0.35)
		pipe_mesh.position = Vector3(px, 0.0, pz)
		body.add_child(pipe_mesh)

	_building_count += 1

	if _rng.randf() < sign_chance:
		_spawn_sign(body, size)


func _spawn_sign(building: StaticBody3D, size: Vector3) -> void:
	var faces := [
		{"normal": Vector3.FORWARD, "offset": Vector3(0.0, 0.0, -size.z * 0.5 - 0.25)},
		{"normal": Vector3.BACK, "offset": Vector3(0.0, 0.0, size.z * 0.5 + 0.25)},
		{"normal": Vector3.LEFT, "offset": Vector3(-size.x * 0.5 - 0.25, 0.0, 0.0)},
		{"normal": Vector3.RIGHT, "offset": Vector3(size.x * 0.5 + 0.25, 0.0, 0.0)},
	]
	var face: Dictionary = faces[_rng.randi() % faces.size()]
	var normal: Vector3 = face["normal"]
	var offset: Vector3 = face["offset"]

	# Lower third for street level view or towering upper billboards
	var is_massive_billboard := _rng.randf() < 0.25
	var local_y: float
	var sign_size: Vector3

	if is_massive_billboard:
		local_y = _rng.randf_range(size.y * 0.1, size.y * 0.38)
		sign_size = Vector3(_rng.randf_range(6.0, 11.0), _rng.randf_range(3.5, 6.5), 0.4)
	else:
		local_y = _rng.randf_range(-size.y * 0.35, size.y * 0.05)
		sign_size = Vector3(_rng.randf_range(1.2, 3.2), _rng.randf_range(2.5, 7.0), 0.3)
		if _rng.randf() < 0.4:
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

	var material: ShaderMaterial = (
		NEON_MAGENTA if _rng.randf() < 0.55 else NEON_CYAN
	).duplicate()
	material.set_shader_parameter("phase_offset", _rng.randf_range(0.0, 100.0))
	material.set_shader_parameter("dropout_chance", _rng.randf_range(0.0, 0.12))
	mesh_instance.material_override = material
	holder.add_child(mesh_instance)

	var light := OmniLight3D.new()
	light.light_color = material.get_shader_parameter("neon_color")
	light.light_energy = sign_light_energy * (1.5 if is_massive_billboard else 1.0)
	light.omni_range = sign_light_range * (1.4 if is_massive_billboard else 1.0)
	light.shadow_enabled = false
	light.position = normal * -1.5
	holder.add_child(light)

	_sign_count += 1


func _spawn_rubble(centre: Vector3) -> void:
	var chunks := _rng.randi_range(3, 7)
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
		mesh_instance.material_override = CONCRETE if _rng.randf() > 0.3 else METAL_RUST
		body.add_child(mesh_instance)


func _spawn_street_lamps(stride: float, half: float) -> void:
	var lamps := Node3D.new()
	lamps.name = "StreetLamps"
	add_child(lamps)

	for gx in grid_size + 1:
		for gz in grid_size + 1:
			if (gx + gz) % 2 == 1:
				continue
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

			var head_material: ShaderMaterial = NEON_CYAN.duplicate()
			head_material.set_shader_parameter("neon_color", LAMP_COLOR)
			head_material.set_shader_parameter("energy", 2.2)
			head_material.set_shader_parameter("flicker_amount", 0.05)
			head_material.set_shader_parameter("dropout_chance", 0.0)
			head_material.set_shader_parameter("phase_offset", _rng.randf_range(0.0, 100.0))
			head.material_override = head_material
			post.add_child(head)

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


func _spawn_street_furniture(stride: float, half: float) -> void:
	var furniture := Node3D.new()
	furniture.name = "StreetFurniture"
	add_child(furniture)

	# Barriers, dumpsters, cargo containers along roadsides
	for gx in grid_size:
		for gz in grid_size:
			var cx := (gx - half) * stride
			var cz := (gz - half) * stride
			
			# Spawn security barriers / barricades near intersections
			if _rng.randf() < 0.45:
				var bar_pos := Vector3(cx + lot_size * 0.5 + 1.2, 0.5, cz + _rng.randf_range(-4.0, 4.0))
				_spawn_barrier(furniture, bar_pos, 0.0)
			
			if _rng.randf() < 0.45:
				var bar_pos := Vector3(cx + _rng.randf_range(-4.0, 4.0), 0.5, cz + lot_size * 0.5 + 1.2)
				_spawn_barrier(furniture, bar_pos, PI * 0.5)

			# Spawn shipping cargo containers / dumpsters
			if _rng.randf() < 0.35:
				var cont_pos := Vector3(cx + lot_size * 0.45, 1.3, cz - lot_size * 0.45)
				_spawn_cargo_container(furniture, cont_pos)

			# Steam vent / manhole glow
			if _rng.randf() < 0.3:
				var vent_pos := Vector3(cx + _rng.randf_range(-6.0, 6.0), 0.02, cz + _rng.randf_range(-6.0, 6.0))
				_spawn_steam_vent(furniture, vent_pos)


func _spawn_barrier(parent: Node3D, pos: Vector3, rot_y: float) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	body.rotation.y = rot_y
	body.collision_layer = 1
	body.collision_mask = 0
	parent.add_child(body)

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.4, 0.9, 0.6)
	shape.shape = box
	body.add_child(shape)

	var mesh := MeshInstance3D.new()
	var b_mesh := BoxMesh.new()
	b_mesh.size = Vector3(2.4, 0.9, 0.6)
	mesh.mesh = b_mesh
	mesh.material_override = CONCRETE
	body.add_child(mesh)
	_prop_count += 1


func _spawn_cargo_container(parent: Node3D, pos: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	body.rotation.y = _rng.randf_range(-0.2, 0.2)
	body.collision_layer = 1
	body.collision_mask = 0
	parent.add_child(body)

	var c_size := Vector3(2.8, 2.5, 6.0)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = c_size
	shape.shape = box
	body.add_child(shape)

	var mesh := MeshInstance3D.new()
	var b_mesh := BoxMesh.new()
	b_mesh.size = c_size
	mesh.mesh = b_mesh
	mesh.material_override = METAL_RUST
	body.add_child(mesh)
	_prop_count += 1


func _spawn_steam_vent(parent: Node3D, pos: Vector3) -> void:
	var vent := Node3D.new()
	vent.position = pos
	parent.add_child(vent)

	var grate := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.6
	cyl.bottom_radius = 0.6
	cyl.height = 0.04
	grate.mesh = cyl
	grate.material_override = METAL_RUST
	vent.add_child(grate)

	# Amber/Orange neon under-glow
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.45, 0.15)
	glow.light_energy = 1.6
	glow.omni_range = 4.5
	glow.position.y = 0.3
	glow.shadow_enabled = false
	vent.add_child(glow)
	_prop_count += 1


func _spawn_overhead_infrastructure() -> void:
	if _building_positions.size() < 4:
		return
	
	var infra := Node3D.new()
	infra.name = "OverheadCables"
	add_child(infra)

	# Connect pairs of neighbouring buildings with industrial conduit pipes / wires
	for i in range(0, _building_positions.size() - 1, 2):
		var p1 := _building_positions[i] + Vector3(0.0, _rng.randf_range(8.0, 16.0), 0.0)
		var p2 := _building_positions[i + 1] + Vector3(0.0, _rng.randf_range(8.0, 16.0), 0.0)
		
		var diff := p2 - p1
		var dist := diff.length()
		if dist > 45.0 or dist < 10.0:
			continue
		
		var mid := (p1 + p2) * 0.5 - Vector3(0.0, _rng.randf_range(0.8, 2.2), 0.0) # sag
		
		var cable := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.06
		cyl.bottom_radius = 0.06
		cyl.height = dist
		cable.mesh = cyl
		cable.material_override = METAL_RUST
		
		cable.position = (p1 + p2) * 0.5
		infra.add_child(cable)
		cable.look_at_from_position(cable.position, p2, Vector3.UP)
		cable.rotate_object_local(Vector3.RIGHT, PI * 0.5)
		_prop_count += 1


func _spawn_plaza_centrepiece() -> void:
	var plaza := Node3D.new()
	plaza.name = "PlazaMonument"
	plaza.position = Vector3(0.0, 0.0, 0.0)
	add_child(plaza)

	# Multi-tiered pedestal
	var base_mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 4.5
	cyl.bottom_radius = 5.2
	cyl.height = 0.7
	base_mesh.mesh = cyl
	base_mesh.position.y = 0.35
	base_mesh.material_override = CONCRETE
	plaza.add_child(base_mesh)

	# Holographic core spire
	var core_mesh := MeshInstance3D.new()
	var core_box := BoxMesh.new()
	core_box.size = Vector3(1.2, 7.5, 1.2)
	core_mesh.mesh = core_box
	core_mesh.position.y = 4.4
	core_mesh.material_override = METAL_RUST
	plaza.add_child(core_mesh)

	# Cyan Hologram projector ring
	var holo := MeshInstance3D.new()
	var holo_cyl := CylinderMesh.new()
	holo_cyl.top_radius = 2.4
	holo_cyl.bottom_radius = 2.4
	holo_cyl.height = 0.4
	holo.mesh = holo_cyl
	var holo_mat: ShaderMaterial = NEON_CYAN.duplicate()
	holo_mat.set_shader_parameter("energy", 4.0)
	holo.material_override = holo_mat
	holo.position.y = 5.8
	plaza.add_child(holo)

	var holo_light := OmniLight3D.new()
	holo_light.light_color = Color(0.0, 0.9, 1.0)
	holo_light.light_energy = 3.5
	holo_light.omni_range = 14.0
	holo_light.position.y = 6.0
	holo_light.shadow_enabled = true
	plaza.add_child(holo_light)
	_prop_count += 1


func _spawn_wasteland_perimeter(radius: float) -> void:
	var wasteland := Node3D.new()
	wasteland.name = "WastelandPerimeter"
	add_child(wasteland)

	# Perimeter sand dunes & ruined megaliths circling the city block
	var dune_count := 16
	for i in dune_count:
		var angle := (float(i) / float(dune_count)) * TAU
		var dist := radius + _rng.randf_range(6.0, 28.0)
		var pos := Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)

		var dune_body := StaticBody3D.new()
		dune_body.position = pos + Vector3(0.0, _rng.randf_range(2.0, 5.0), 0.0)
		dune_body.rotation.y = _rng.randf_range(-PI, PI)
		dune_body.collision_layer = 1
		dune_body.collision_mask = 0
		wasteland.add_child(dune_body)

		var dune_size := Vector3(
			_rng.randf_range(24.0, 48.0),
			_rng.randf_range(5.0, 14.0),
			_rng.randf_range(16.0, 32.0)
		)

		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = dune_size
		shape.shape = box
		dune_body.add_child(shape)

		var mesh := MeshInstance3D.new()
		var b_mesh := BoxMesh.new()
		b_mesh.size = dune_size
		mesh.mesh = b_mesh
		mesh.material_override = SAND
		dune_body.add_child(mesh)

		# Distant silhouette spire / ruin in the desert
		if _rng.randf() < 0.4:
			var spire_mesh := MeshInstance3D.new()
			var s_box := BoxMesh.new()
			s_box.size = Vector3(_rng.randf_range(6.0, 14.0), _rng.randf_range(30.0, 75.0), _rng.randf_range(6.0, 14.0))
			spire_mesh.mesh = s_box
			spire_mesh.material_override = CONCRETE
			spire_mesh.position = pos * 1.35 + Vector3(0.0, s_box.size.y * 0.45, 0.0)
			spire_mesh.rotation = Vector3(_rng.randf_range(-0.15, 0.15), _rng.randf_range(-PI, PI), _rng.randf_range(-0.15, 0.15))
			wasteland.add_child(spire_mesh)

		_prop_count += 1


## First safe standing spot for the player, at the centre of the plaza.
func get_spawn_point() -> Vector3:
	return Vector3(0.0, 1.2, 0.0)
