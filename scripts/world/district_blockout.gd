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
const SIDEWALK := preload("res://assets/materials/toon_sidewalk.tres")
const NEON_MAGENTA := preload("res://assets/materials/neon_magenta.tres")
const NEON_CYAN := preload("res://assets/materials/neon_cyan.tres")
const METAL_DARK := preload("res://assets/materials/toon_metal_dark.tres")
const RUST := preload("res://assets/materials/toon_rust.tres")
const PUDDLE := preload("res://assets/materials/puddle.tres")
const HOLO_MAGENTA := preload("res://assets/materials/hologram_magenta.tres")
const HOLO_CYAN := preload("res://assets/materials/hologram_cyan.tres")
const POSTER := preload("res://assets/materials/toon_poster.tres")
const COLOSSUS := preload("res://assets/materials/holo_colossus.tres")
const SHELL_SCENE := preload("res://scenes/characters/persona_shell.tscn")
const PERSONA_MARROW := preload("res://assets/personas/marrow_scrap.tres")
const PERSONA_AMP := preload("res://assets/personas/sister_amp.tres")
const PERSONA_KIP := preload("res://assets/personas/kip_dockrat.tres")
const PERSONA_BRAM := preload("res://assets/personas/warden_bram.tres")
const CRATE_SCENE := preload("res://scenes/props/physics_crate.tscn")
const CAN_SCENE := preload("res://scenes/props/physics_can.tscn")
const DUMPSTER_SCENE := preload("res://scenes/props/dumpster.tscn")
const BARRIER_SCENE := preload("res://scenes/props/jersey_barrier.tscn")
const BOLLARD_SCENE := preload("res://scenes/props/bollard.tscn")
const CONE_SCENE := preload("res://scenes/props/traffic_cone.tscn")
const MANHOLE_SCENE := preload("res://scenes/props/manhole.tscn")
const SCAFFOLD_SCENE := preload("res://scenes/props/scaffold_frame.tscn")

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

@export_group("Atmosphere")
## Fraction of tall towers that carry a holographic ad board.
@export_range(0.0, 1.0) var holo_board_chance: float = 0.24
@export var max_holo_boards: int = 6
@export var holo_light_energy: float = 1.1
@export var puddle_count: int = 16
@export var steam_vent_count: int = 6
## Chance a cable runs between two neighbouring rooftops.
@export_range(0.0, 1.0) var cable_chance: float = 0.55

@export_group("Props")
@export var crate_count: int = 8
@export var can_count: int = 14
@export var dumpster_count: int = 7
@export var barrier_count: int = 10
@export var bollard_group_count: int = 8
@export var cone_count: int = 12
@export var manhole_count: int = 9
@export var scaffold_count: int = 5
@export var poster_chance: float = 0.45
@export var window_light_chance: float = 0.7

const LAMP_HEIGHT := 6.0
const LAMP_ARM := 1.3
const LAMP_COLOR := Color(1.0, 0.68, 0.36)
const CABLE_SEGMENTS := 9
const SIDEWALK_WIDTH := 2.2
const KERB_HEIGHT := 0.14
const ACID_YELLOW := Color(0.969, 1.0, 0.235)

var _rng := RandomNumberGenerator.new()
var _building_count: int = 0
var _sign_count: int = 0
## Grid cell -> {"pos", "size"} for every standing tower; cables and holo
## boards need to know where the rooftops ended up.
var _buildings: Dictionary = {}
var _steam_material: StandardMaterial3D = null
var _steam_process_material: ParticleProcessMaterial = null
var _steam_quad: QuadMesh = null


func _ready() -> void:
	generate()


## Rebuilds the block from scratch. Safe to call repeatedly.
func generate() -> void:
	for child in get_children():
		child.queue_free()
	_building_count = 0
	_sign_count = 0
	_buildings.clear()

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
			_spawn_building(centre, Vector2i(gx, gz))

	_spawn_street_lamps(stride, half)
	_spawn_sidewalks(stride, half)
	_spawn_cables()
	_spawn_puddles(stride, half)
	_spawn_holo_boards()
	_spawn_colossus()
	_spawn_steam_vents(stride, half)
	_spawn_street_dressing(stride, half)
	_spawn_physics_props(stride, half)
	_spawn_people()

	print("[DistrictBlockout] seed=%d buildings=%d signs=%d street_props=%d" % [
		world_seed, _building_count, _sign_count,
		crate_count + can_count + dumpster_count + barrier_count + cone_count,
	])


func _spawn_building(centre: Vector3, cell: Vector2i) -> void:
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

	_buildings[cell] = {"pos": origin, "size": size, "body": body}
	_building_count += 1

	_spawn_rooftop_clutter(body, size)
	_spawn_window_lights(body, size)
	_spawn_wall_posters(body, size)

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
	# Duplicate so per-sign flicker phase does not desync every other sign, and
	# so each city block leans on its own neon family instead of one palette.
	var cell := _cell_of(building)
	var family := _cell_family(cell)
	var material: ShaderMaterial = (
		NEON_MAGENTA if family < 6 else NEON_CYAN
	).duplicate()
	if family >= 9:
		material.set_shader_parameter("neon_color", ACID_YELLOW)
	elif family == 8:
		material.set_shader_parameter("neon_color", LAMP_COLOR)
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


## Which lattice cell a building body lives in; recorded at spawn so signage
## and window lights can share one neon family per block.
func _cell_of(building: StaticBody3D) -> Vector2i:
	for cell: Vector2i in _buildings:
		if _buildings[cell]["body"] == building:
			return cell
	return Vector2i.ZERO


## Deterministic block flavour: 0-5 magenta-led, 6-7 cyan-led, 8 amber, 9 acid.
func _cell_family(cell: Vector2i) -> int:
	var h := int(cell.x * 73856093) ^ int(cell.y * 19349663)
	return abs(h) % 10


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


## Water tanks, AC units, antennas and pipe runs — the roofline is where the
## silhouette reads, and a bare box roofline reads as unfinished.
func _spawn_rooftop_clutter(body: StaticBody3D, size: Vector3) -> void:
	var roof_y := size.y * 0.5
	for i in _rng.randi_range(1, 3):
		var spot := Vector3(
			_rng.randf_range(-size.x * 0.28, size.x * 0.28),
			roof_y,
			_rng.randf_range(-size.z * 0.28, size.z * 0.28),
		)
		match _rng.randi() % 4:
			0:
				_make_water_tank(body, spot)
			1:
				_make_ac_unit(body, spot)
			2:
				_make_antenna(body, spot)
			_:
				_make_roof_pipe(body, spot, size)


func _make_water_tank(parent: Node3D, spot: Vector3) -> void:
	var radius := _rng.randf_range(0.9, 1.5)
	var height := _rng.randf_range(1.6, 2.4)

	var tank := MeshInstance3D.new()
	var drum := CylinderMesh.new()
	drum.top_radius = radius
	drum.bottom_radius = radius * 1.04
	drum.height = height
	drum.radial_segments = 12
	tank.mesh = drum
	tank.position = spot + Vector3(0.0, height * 0.5 + 0.5, 0.0)
	tank.material_override = RUST
	parent.add_child(tank)

	var lid := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.06
	cone.bottom_radius = radius * 1.12
	cone.height = 0.55
	cone.radial_segments = 12
	lid.mesh = cone
	lid.position = spot + Vector3(0.0, height + 0.78, 0.0)
	lid.material_override = RUST
	parent.add_child(lid)

	# Stub legs, so the tank is not floating on the membrane.
	var legs := MeshInstance3D.new()
	var frame := BoxMesh.new()
	frame.size = Vector3(radius * 1.5, 0.55, radius * 1.5)
	legs.mesh = frame
	legs.position = spot + Vector3(0.0, 0.28, 0.0)
	legs.material_override = METAL_DARK
	parent.add_child(legs)


func _make_ac_unit(parent: Node3D, spot: Vector3) -> void:
	var size := Vector3(
		_rng.randf_range(0.9, 1.7), _rng.randf_range(0.5, 0.9), _rng.randf_range(0.7, 1.2)
	)
	var unit := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	unit.mesh = box
	unit.position = spot + Vector3(0.0, size.y * 0.5, 0.0)
	unit.rotation.y = _rng.randf_range(-PI, PI)
	unit.material_override = METAL_DARK
	parent.add_child(unit)

	# The fan disc on top is what makes it read as HVAC from across the street.
	var fan := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = size.x * 0.3
	disc.bottom_radius = size.x * 0.3
	disc.height = 0.06
	disc.radial_segments = 12
	fan.mesh = disc
	fan.position = spot + Vector3(0.0, size.y + 0.03, 0.0)
	fan.rotation.y = unit.rotation.y
	fan.material_override = RUST
	parent.add_child(fan)


func _make_antenna(parent: Node3D, spot: Vector3) -> void:
	var height := _rng.randf_range(2.5, 6.5)

	var mast := MeshInstance3D.new()
	var pole := CylinderMesh.new()
	pole.top_radius = 0.03
	pole.bottom_radius = 0.05
	pole.height = height
	pole.radial_segments = 6
	mast.mesh = pole
	mast.position = spot + Vector3(0.0, height * 0.5, 0.0)
	mast.material_override = METAL_DARK
	parent.add_child(mast)

	for bar in _rng.randi_range(1, 2):
		var cross := MeshInstance3D.new()
		var arm := BoxMesh.new()
		var arm_len := _rng.randf_range(0.5, 1.1)
		arm.size = Vector3(arm_len, 0.04, 0.04)
		cross.mesh = arm
		cross.position = spot + Vector3(0.0, height * _rng.randf_range(0.6, 0.92), 0.0)
		cross.rotation.y = _rng.randf_range(-PI, PI)
		cross.material_override = METAL_DARK
		parent.add_child(cross)

	# Aircraft-warning bead: a pinprick of neon on the tallest masts.
	if height > 4.0 and _rng.randf() < 0.7:
		var bead := MeshInstance3D.new()
		var cube := BoxMesh.new()
		cube.size = Vector3(0.1, 0.1, 0.1)
		bead.mesh = cube
		bead.position = spot + Vector3(0.0, height + 0.05, 0.0)
		var material: ShaderMaterial = (
			NEON_MAGENTA if _rng.randf() < 0.5 else NEON_CYAN
		).duplicate()
		material.set_shader_parameter("energy", 1.6)
		material.set_shader_parameter("flicker_amount", 0.3)
		material.set_shader_parameter("phase_offset", _rng.randf_range(0.0, 100.0))
		bead.material_override = material
		parent.add_child(bead)


func _make_roof_pipe(parent: Node3D, spot: Vector3, size: Vector3) -> void:
	var pipe := MeshInstance3D.new()
	var run := BoxMesh.new()
	var length := size.x * _rng.randf_range(0.5, 0.85)
	run.size = Vector3(length, 0.12, 0.12)
	pipe.mesh = run
	pipe.position = Vector3(spot.x, size.y * 0.5 + 0.1, size.z * 0.42)
	pipe.rotation.y = _rng.randf_range(-0.1, 0.1)
	pipe.material_override = RUST
	parent.add_child(pipe)


## Lit windows: a few emissive boxes on each face so towers read as inhabited
## rather than solid concrete. Kept dim so the glow pass blooms them without
## tonemapping to white.
func _spawn_window_lights(body: StaticBody3D, size: Vector3) -> void:
	if _rng.randf() > window_light_chance:
		return
	var faces := [
		{"normal": Vector3.FORWARD, "offset": Vector3(0.0, 0.0, -size.z * 0.5 - 0.04)},
		{"normal": Vector3.BACK, "offset": Vector3(0.0, 0.0, size.z * 0.5 + 0.04)},
		{"normal": Vector3.LEFT, "offset": Vector3(-size.x * 0.5 - 0.04, 0.0, 0.0)},
		{"normal": Vector3.RIGHT, "offset": Vector3(size.x * 0.5 + 0.04, 0.0, 0.0)},
	]
	var count := _rng.randi_range(2, 5)
	for i in count:
		var face: Dictionary = faces[_rng.randi() % faces.size()]
		var offset: Vector3 = face["offset"]
		var local_y := _rng.randf_range(-size.y * 0.35, size.y * 0.4)
		var lateral := _rng.randf_range(-0.35, 0.35)
		var along := Vector3.ZERO
		if absf(offset.x) > absf(offset.z):
			along = Vector3(0.0, 0.0, lateral * size.z)
		else:
			along = Vector3(lateral * size.x, 0.0, 0.0)

		var pane := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(
			_rng.randf_range(0.6, 1.4) if absf(offset.z) > absf(offset.x) else 0.08,
			_rng.randf_range(0.7, 1.5),
			_rng.randf_range(0.6, 1.4) if absf(offset.x) > absf(offset.z) else 0.08,
		)
		pane.mesh = box
		pane.position = offset + along + Vector3(0.0, local_y, 0.0)
		# Window light hue follows the block's neon family so a street corner
		# reads as one neighbourhood, not a bag of random colours.
		var family := _cell_family(_cell_of(body))
		var cyan_chance := 0.85 if family >= 6 and family < 9 else 0.45
		var material: ShaderMaterial = (
			NEON_CYAN if _rng.randf() < cyan_chance else NEON_MAGENTA
		).duplicate()
		if family == 9 and _rng.randf() < 0.3:
			material.set_shader_parameter("neon_color", ACID_YELLOW)
		material.set_shader_parameter("energy", _rng.randf_range(0.9, 1.6))
		material.set_shader_parameter("flicker_amount", _rng.randf_range(0.0, 0.08))
		material.set_shader_parameter("dropout_chance", 0.0)
		material.set_shader_parameter("phase_offset", _rng.randf_range(0.0, 100.0))
		pane.material_override = material
		pane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		body.add_child(pane)


## Weathered posters stuck low on the walls — colour without claiming neon.
func _spawn_wall_posters(body: StaticBody3D, size: Vector3) -> void:
	if _rng.randf() > poster_chance:
		return
	var faces := [
		{"yaw": PI, "offset": Vector3(0.0, 0.0, -size.z * 0.5 - 0.05)},
		{"yaw": 0.0, "offset": Vector3(0.0, 0.0, size.z * 0.5 + 0.05)},
		{"yaw": -PI * 0.5, "offset": Vector3(-size.x * 0.5 - 0.05, 0.0, 0.0)},
		{"yaw": PI * 0.5, "offset": Vector3(size.x * 0.5 + 0.05, 0.0, 0.0)},
	]
	for i in _rng.randi_range(1, 2):
		var face: Dictionary = faces[_rng.randi() % faces.size()]
		var poster := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(_rng.randf_range(0.9, 1.8), _rng.randf_range(1.2, 2.4))
		poster.mesh = quad
		poster.position = face["offset"] + Vector3(
			0.0, -size.y * _rng.randf_range(0.15, 0.35), 0.0
		)
		poster.rotation.y = face["yaw"]
		var material: ShaderMaterial = POSTER.duplicate()
		if _rng.randf() < 0.5:
			material.set_shader_parameter("emission_color", Color(0.0, 0.898, 1.0))
			material.set_shader_parameter("rim_color", Color(0.0, 0.898, 1.0))
		material.set_shader_parameter(
			"emission_energy", _rng.randf_range(0.2, 0.55)
		)
		poster.material_override = material
		poster.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		body.add_child(poster)


## Raised sidewalk ribbons along both street axes, with a thin kerb lip so the
## street edge reads as a street edge instead of a painted line on a flat plane.
func _spawn_sidewalks(stride: float, half: float) -> void:
	var holder := Node3D.new()
	holder.name = "Sidewalks"
	add_child(holder)

	# One segment per street cell, cut short of the junction so corners do not
	# stack four overlapping slabs on top of each other.
	var segment := stride - street_width * 0.85
	for axis in 2:
		for line in grid_size + 1:
			for along_i in grid_size:
				var centre_coord := (line - half - 0.5) * stride
				var along_coord := (along_i - half) * stride
				for side_i in 2:
					var side := -1.0 if side_i == 0 else 1.0
					var offset: float = side * (street_width * 0.5 - SIDEWALK_WIDTH * 0.5)
					var pos := Vector3.ZERO
					var slab_size := Vector3.ZERO
					if axis == 0:
						pos = Vector3(centre_coord + offset, KERB_HEIGHT * 0.5, along_coord)
						slab_size = Vector3(SIDEWALK_WIDTH, KERB_HEIGHT, segment)
					else:
						pos = Vector3(along_coord, KERB_HEIGHT * 0.5, centre_coord + offset)
						slab_size = Vector3(segment, KERB_HEIGHT, SIDEWALK_WIDTH)
					if Vector2(pos.x, pos.z).length() < plaza_radius * 0.7:
						continue

					var body := StaticBody3D.new()
					body.collision_layer = 1
					body.collision_mask = 0
					body.position = pos
					holder.add_child(body)

					var shape := CollisionShape3D.new()
					var box := BoxShape3D.new()
					box.size = slab_size
					shape.shape = box
					body.add_child(shape)

					var mesh_instance := MeshInstance3D.new()
					var box_mesh := BoxMesh.new()
					box_mesh.size = slab_size
					mesh_instance.mesh = box_mesh
					mesh_instance.material_override = SIDEWALK
					body.add_child(mesh_instance)

					var kerb := MeshInstance3D.new()
					var kerb_mesh := BoxMesh.new()
					if axis == 0:
						kerb_mesh.size = Vector3(0.16, KERB_HEIGHT * 1.2, segment)
						kerb.position = Vector3(
							-side * (SIDEWALK_WIDTH * 0.5 - 0.04), 0.015, 0.0
						)
					else:
						kerb_mesh.size = Vector3(segment, KERB_HEIGHT * 1.2, 0.16)
						kerb.position = Vector3(
							0.0, 0.015, -side * (SIDEWALK_WIDTH * 0.5 - 0.04)
						)
					kerb.mesh = kerb_mesh
					kerb.material_override = CONCRETE
					body.add_child(kerb)


## Dumpsters, barriers, bollards, cones, manholes and scaffold — the street
## furniture that makes a greybox feel walked-in.
func _spawn_street_dressing(stride: float, half: float) -> void:
	var holder := Node3D.new()
	holder.name = "StreetDressing"
	add_child(holder)

	for i in dumpster_count:
		var dumpster := DUMPSTER_SCENE.instantiate()
		dumpster.name = "Dumpster_%02d" % i
		dumpster.position = _random_kerbside(stride, half) + Vector3(0.0, 0.0, 0.0)
		dumpster.rotation.y = _rng.randf_range(-0.2, 0.2) + (
			PI * 0.5 if _rng.randf() < 0.5 else 0.0
		)
		holder.add_child(dumpster)

	for i in barrier_count:
		var barrier := BARRIER_SCENE.instantiate()
		barrier.name = "Barrier_%02d" % i
		barrier.position = _random_street_point(stride, half)
		barrier.rotation.y = _rng.randf_range(-PI, PI)
		holder.add_child(barrier)

	for i in bollard_group_count:
		var origin := _random_kerbside(stride, half)
		var count := _rng.randi_range(2, 4)
		for j in count:
			var bollard := BOLLARD_SCENE.instantiate()
			bollard.name = "Bollard_%02d_%02d" % [i, j]
			bollard.position = origin + Vector3(j * 0.7, 0.0, 0.0).rotated(
				Vector3.UP, _rng.randf_range(0.0, TAU)
			)
			holder.add_child(bollard)

	for i in cone_count:
		var cone := CONE_SCENE.instantiate()
		cone.name = "Cone_%02d" % i
		cone.position = _random_street_point(stride, half) + Vector3(
			_rng.randf_range(-1.5, 1.5), 0.0, _rng.randf_range(-1.5, 1.5)
		)
		cone.rotation.y = _rng.randf_range(-PI, PI)
		holder.add_child(cone)

	for i in manhole_count:
		var manhole := MANHOLE_SCENE.instantiate()
		manhole.name = "Manhole_%02d" % i
		manhole.position = _random_street_point(stride, half)
		manhole.rotation.y = _rng.randf_range(-PI, PI)
		holder.add_child(manhole)

	for i in scaffold_count:
		var scaffold := SCAFFOLD_SCENE.instantiate()
		scaffold.name = "Scaffold_%02d" % i
		# Prefer the face of a building when one is nearby; otherwise kerbside.
		var placed := false
		if not _buildings.is_empty() and _rng.randf() < 0.7:
			var keys: Array = _buildings.keys()
			var record: Dictionary = _buildings[keys[_rng.randi() % keys.size()]]
			var size: Vector3 = record["size"]
			var body: StaticBody3D = record["body"]
			scaffold.position = body.global_position + Vector3(
				0.0, -size.y * 0.5, size.z * 0.5 + 0.7
			)
			scaffold.position.y = 0.0
			scaffold.rotation.y = body.rotation.y
			placed = true
		if not placed:
			scaffold.position = _random_kerbside(stride, half)
			scaffold.rotation.y = _rng.randf_range(-PI, PI)
		holder.add_child(scaffold)


## AD-7: a building-scale watching face on the tallest tower, angled back at
## the plaza. One per district; it is the skyline's signature.
func _spawn_colossus() -> void:
	var tallest: Dictionary = {}
	var best := 0.0
	for record: Dictionary in _buildings.values():
		if record["size"].y > best:
			best = record["size"].y
			tallest = record
	if tallest.is_empty():
		return

	var body: StaticBody3D = tallest["body"]
	var size: Vector3 = tallest["size"]

	var holder := Node3D.new()
	holder.name = "Colossus"
	body.add_child(holder)
	holder.position = Vector3(0.0, size.y * 0.28, size.z * 0.5 + 0.7)

	var panel := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(11.0, 14.0)
	panel.mesh = quad
	var material: ShaderMaterial = COLOSSUS.duplicate()
	material.set_shader_parameter("phase_offset", _rng.randf_range(0.0, 100.0))
	panel.material_override = material
	panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(panel)

	# The face must light its own tower or it reads as a sticker.
	var light := OmniLight3D.new()
	light.light_color = Color(0.0, 0.898, 1.0)
	light.light_energy = 2.4
	light.omni_range = 38.0
	light.shadow_enabled = false
	light.position = Vector3(0.0, 0.0, 3.0)
	holder.add_child(light)


## Kerbside point: on the sidewalk strip rather than mid-carriageway.
func _random_kerbside(stride: float, half: float) -> Vector3:
	var line := _rng.randi_range(0, grid_size)
	var along := _rng.randf_range(-half - 0.3, half + 0.3) * stride
	var side: float = -1.0 if _rng.randf() < 0.5 else 1.0
	var offset: float = side * (street_width * 0.5 - SIDEWALK_WIDTH * 0.55)
	if _rng.randf() < 0.5:
		return Vector3((line - half - 0.5) * stride + offset, 0.0, along)
	return Vector3(along, 0.0, (line - half - 0.5) * stride + offset)


## Catenary cables strung between neighbouring rooftops, baked into a single
## MultiMesh so a whole district of wires costs one draw call.
func _spawn_cables() -> void:
	var transforms: Array[Transform3D] = []
	for cell: Vector2i in _buildings:
		for step: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
			var neighbour := cell + step
			if not _buildings.has(neighbour):
				continue
			if _rng.randf() > cable_chance:
				continue
			var a: Dictionary = _buildings[cell]
			var b: Dictionary = _buildings[neighbour]
			var pa: Vector3 = a["pos"] + Vector3(
				0.0, a["size"].y * _rng.randf_range(0.28, 0.44), 0.0
			)
			var pb: Vector3 = b["pos"] + Vector3(
				0.0, b["size"].y * _rng.randf_range(0.28, 0.44), 0.0
			)
			_append_catenary(transforms, pa, pb, pa.distance_to(pb) * 0.05)

	if transforms.is_empty():
		return

	var unit := CylinderMesh.new()
	unit.top_radius = 1.0
	unit.bottom_radius = 1.0
	unit.height = 2.0
	unit.radial_segments = 5

	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = unit
	multimesh.instance_count = transforms.size()
	for i in transforms.size():
		multimesh.set_instance_transform(i, transforms[i])

	var holder := MultiMeshInstance3D.new()
	holder.name = "Cables"
	holder.multimesh = multimesh
	holder.material_override = METAL_DARK
	holder.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(holder)


func _append_catenary(out: Array[Transform3D], a: Vector3, b: Vector3, sag: float) -> void:
	var prev := a
	for i in range(1, CABLE_SEGMENTS + 1):
		var t := float(i) / CABLE_SEGMENTS
		var p := a.lerp(b, t)
		# Parabola: cheap stand-in for a true catenary at these spans.
		p.y -= sag * 4.0 * t * (1.0 - t)
		_append_cable_segment(out, prev, p, 0.03)
		prev = p


func _append_cable_segment(out: Array[Transform3D], a: Vector3, b: Vector3, radius: float) -> void:
	var delta := b - a
	var length := delta.length()
	if length < 0.01:
		return
	var y := delta / length
	var x := y.cross(Vector3.UP)
	if x.length_squared() < 0.001:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y).normalized()
	# Unit cylinder is 2 m tall centred on its origin; scale Y to half-length.
	out.append(Transform3D(Basis(x * radius, y * (length * 0.5), z * radius), (a + b) * 0.5))


func _spawn_puddles(stride: float, half: float) -> void:
	var holder := Node3D.new()
	holder.name = "Puddles"
	add_child(holder)

	for i in puddle_count:
		# Puddles live on the street lattice: junctions plus random kerbside
		# offsets, never inside a lot.
		var pos := _random_street_point(stride, half)
		pos += Vector3(_rng.randf_range(-2.5, 2.5), 0.0, _rng.randf_range(-2.5, 2.5))
		pos.y = 0.02

		var mesh_instance := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		var width := _rng.randf_range(1.6, 5.5)
		plane.size = Vector2(width, width * _rng.randf_range(0.5, 1.0))
		mesh_instance.mesh = plane
		# One shared material: the shoreline noise is world-space, so every
		# puddle gets a different silhouette from the same shader state.
		mesh_instance.material_override = PUDDLE
		mesh_instance.position = pos
		mesh_instance.rotation.y = _rng.randf_range(-PI, PI)
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(mesh_instance)


func _spawn_holo_boards() -> void:
	var spawned := 0
	for cell: Vector2i in _buildings:
		if spawned >= max_holo_boards:
			break
		var record: Dictionary = _buildings[cell]
		var size: Vector3 = record["size"]
		if size.y < 16.0:
			continue  # short blocks keep their walls for signage
		if _rng.randf() > holo_board_chance:
			continue

		var body: StaticBody3D = record["body"]
		var faces := [
			{"yaw": PI, "offset": Vector3(0.0, 0.0, -size.z * 0.5 - 0.45)},
			{"yaw": 0.0, "offset": Vector3(0.0, 0.0, size.z * 0.5 + 0.45)},
			{"yaw": -PI * 0.5, "offset": Vector3(-size.x * 0.5 - 0.45, 0.0, 0.0)},
			{"yaw": PI * 0.5, "offset": Vector3(size.x * 0.5 + 0.45, 0.0, 0.0)},
		]
		var face: Dictionary = faces[_rng.randi() % faces.size()]

		var holder := Node3D.new()
		holder.name = "HoloBoard_%02d" % spawned
		holder.position = face["offset"] + Vector3(
			0.0, size.y * _rng.randf_range(0.1, 0.3), 0.0
		)
		holder.rotation.y = face["yaw"]
		body.add_child(holder)

		var panel := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(_rng.randf_range(3.5, 6.5), _rng.randf_range(2.5, 4.5))
		panel.mesh = quad
		var material: ShaderMaterial = (
			HOLO_MAGENTA if spawned % 2 == 0 else HOLO_CYAN
		).duplicate()
		material.set_shader_parameter("phase_offset", _rng.randf_range(0.0, 100.0))
		panel.material_override = material
		panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(panel)

		# The board has to throw its colour onto the wall behind it or it reads
		# as a sticker rather than a light source.
		var light := OmniLight3D.new()
		light.light_color = material.get_shader_parameter("holo_color")
		light.light_energy = holo_light_energy
		light.omni_range = 10.0
		light.shadow_enabled = false
		light.position = Vector3(0.0, 0.0, 1.2)
		holder.add_child(light)

		spawned += 1


func _spawn_steam_vents(stride: float, half: float) -> void:
	_make_steam_resources()
	var holder := Node3D.new()
	holder.name = "SteamVents"
	add_child(holder)

	for i in steam_vent_count:
		var pos := _random_street_point(stride, half)
		var particles := GPUParticles3D.new()
		particles.name = "Vent_%02d" % i
		particles.amount = 20
		particles.lifetime = _rng.randf_range(2.4, 3.6)
		particles.preprocess = particles.lifetime
		particles.local_coords = false
		particles.visibility_aabb = AABB(Vector3(-5.0, -1.0, -5.0), Vector3(10.0, 12.0, 10.0))
		particles.process_material = _steam_process_material
		particles.draw_pass_1 = _steam_quad
		particles.position = pos + Vector3(0.0, 0.15, 0.0)
		holder.add_child(particles)


func _make_steam_resources() -> void:
	if _steam_material != null:
		return

	_steam_material = StandardMaterial3D.new()
	_steam_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_steam_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_steam_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_steam_material.albedo_texture = TextureFactory.soft_blob(64)
	# Cold violet smoke: steam lit by the district, not a whiteout.
	_steam_material.albedo_color = Color(0.5, 0.42, 0.62, 0.16)

	var fade := Gradient.new()
	fade.set_color(0, Color(1.0, 1.0, 1.0, 0.0))
	fade.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	fade.add_point(0.2, Color(1.0, 1.0, 1.0, 1.0))
	fade.add_point(0.65, Color(1.0, 1.0, 1.0, 0.6))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade

	var growth := Curve.new()
	growth.add_point(Vector2(0.0, 0.35))
	growth.add_point(Vector2(1.0, 1.0))
	var scale_curve := CurveTexture.new()
	scale_curve.curve = growth

	_steam_process_material = ParticleProcessMaterial.new()
	_steam_process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	_steam_process_material.emission_sphere_radius = 0.3
	_steam_process_material.direction = Vector3(0.25, 1.0, 0.1)
	_steam_process_material.spread = 16.0
	_steam_process_material.initial_velocity_min = 1.2
	_steam_process_material.initial_velocity_max = 2.2
	# Steam is buoyant: gravity points up, damping bleeds the rise off.
	_steam_process_material.gravity = Vector3(0.0, 0.4, 0.0)
	_steam_process_material.damping_min = 0.25
	_steam_process_material.damping_max = 0.5
	_steam_process_material.scale_min = 0.8
	_steam_process_material.scale_max = 1.5
	_steam_process_material.scale_curve = scale_curve
	_steam_process_material.color_ramp = ramp

	_steam_quad = QuadMesh.new()
	_steam_quad.size = Vector2(1.7, 1.7)
	_steam_quad.material = _steam_material


func _spawn_physics_props(stride: float, half: float) -> void:
	var holder := Node3D.new()
	holder.name = "PhysicsProps"
	add_child(holder)

	for i in crate_count:
		var crate := CRATE_SCENE.instantiate()
		crate.name = "Crate_%02d" % i
		crate.position = _random_street_point(stride, half) + Vector3(
			_rng.randf_range(-2.2, 2.2), 0.42, _rng.randf_range(-2.2, 2.2)
		)
		crate.rotation.y = _rng.randf_range(-PI, PI)
		holder.add_child(crate)

	for i in can_count:
		var can := CAN_SCENE.instantiate()
		can.name = "Can_%02d" % i
		# Some cans lie tipped on their side; the resting height changes with it.
		var tipped := _rng.randf() < 0.45
		can.position = _random_street_point(stride, half) + Vector3(
			_rng.randf_range(-2.6, 2.6), 0.16 if tipped else 0.21, _rng.randf_range(-2.6, 2.6)
		)
		if tipped:
			can.rotation = Vector3(PI * 0.5, _rng.randf_range(-PI, PI), 0.0)
		holder.add_child(can)


## The plaza's regulars. Positions are fixed (not seeded) so designers and
## tests always know where a given persona stands. Silhouettes vary so each
## reads at distance even before the bark label says who it is.
func _spawn_people() -> void:
	var holder := Node3D.new()
	holder.name = "People"
	add_child(holder)

	# persona, position, yaw, body scale
	var placements := [
		{"profile": PERSONA_MARROW, "pos": Vector3(7.5, 0.0, 3.0), "yaw": -2.2, "scale": Vector3(1.25, 0.92, 1.25)},
		{"profile": PERSONA_AMP, "pos": Vector3(-4.5, 0.0, 5.5), "yaw": 0.6, "scale": Vector3(0.9, 1.08, 0.9)},
		{"profile": PERSONA_KIP, "pos": Vector3(10.0, 0.0, -8.0), "yaw": 2.8, "scale": Vector3(0.75, 0.82, 0.75)},
		{"profile": PERSONA_BRAM, "pos": Vector3(-9.0, 0.0, -7.0), "yaw": -0.4, "scale": Vector3(1.18, 1.0, 1.18)},
	]
	for entry: Dictionary in placements:
		var shell := SHELL_SCENE.instantiate() as PersonaShell
		shell.name = "Shell_%s" % entry["profile"].persona_id
		shell.profile = entry["profile"]
		shell.position = entry["pos"]
		shell.rotation.y = entry["yaw"]
		var mesh := shell.get_node_or_null("Mesh") as MeshInstance3D
		if mesh != null:
			mesh.scale = entry["scale"]
		holder.add_child(shell)


## A point on the street network (the gaps between lot rows), never on a lot.
func _random_street_point(stride: float, half: float) -> Vector3:
	var line := _rng.randi_range(0, grid_size)
	var along := _rng.randf_range(-half - 0.4, half + 0.4) * stride
	if _rng.randf() < 0.5:
		return Vector3((line - half - 0.5) * stride, 0.0, along)
	return Vector3(along, 0.0, (line - half - 0.5) * stride)


## First safe standing spot for the player, at the centre of the plaza.
func get_spawn_point() -> Vector3:
	return Vector3(0.0, 1.2, 0.0)
