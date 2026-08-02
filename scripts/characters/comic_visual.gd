class_name ComicVisual
extends Node3D
## Procedural Marvel-style comic humanoid for NeonWastesRPG.
## Angular proportions, clear face plates, strong silhouette, kit variants.
## Designed to read as cartoon/comic rather than abstract capsules.

enum Kit { PLAYER, NPC_CIVILIAN, NPC_TECH, ENEMY_THUG, ENEMY_CORP }

@export var kit: Kit = Kit.PLAYER
@export var face_mask: bool = false
@export var show_visor: bool = true
@export var hair_style: int = 0          # 0=short, 1=volume, 2=mohawk/spikes
@export var idle_bob: float = 1.0
@export var walk_swing: float = 1.0

var _time: float = 0.0
var _speed_factor: float = 0.0
var _body: CharacterBody3D = null
var _arm_l: Node3D; var _arm_r: Node3D
var _thigh_l: Node3D; var _thigh_r: Node3D
var _torso: Node3D; var _head: Node3D; var _pelvis: Node3D
var _rest: Dictionary = {}


func _ready() -> void:
	_body = get_parent() as CharacterBody3D
	_build()
	_cache_limbs()
	_store_rest()


func _process(delta: float) -> void:
	_time += delta
	_update_speed_factor()
	_apply_pose(delta)


func set_locomotion_speed(horizontal_speed: float, walk_ref: float = 4.0) -> void:
	_speed_factor = clampf(horizontal_speed / maxf(walk_ref, 0.01), 0.0, 1.5)


func _update_speed_factor() -> void:
	if _body == null:
		return
	var h := Vector2(_body.velocity.x, _body.velocity.z).length()
	_speed_factor = clampf(h / 4.0, 0.0, 1.5)


func _apply_pose(_delta: float) -> void:
	var idle := (1.0 - clampf(_speed_factor, 0.0, 1.0)) * idle_bob
	var walk := clampf(_speed_factor, 0.0, 1.0) * walk_swing
	var breathe := sin(_time * 1.6) * 0.014 * idle
	if _torso:
		_torso.position.y = _rest["torso"].origin.y + breathe
		_torso.rotation.x = _rest["torso"].basis.get_euler().x + sin(_time * 1.6) * 0.025 * idle
	if _head:
		_head.rotation.x = _rest["head"].basis.get_euler().x + sin(_time * 1.3) * 0.035 * idle
		_head.rotation.y = _rest["head"].basis.get_euler().y + sin(_time * 0.7) * 0.045 * idle
	var phase := _time * (6.5 + _speed_factor * 2.0)
	var swing := sin(phase) * 0.58 * walk
	var swing_opp := sin(phase + PI) * 0.58 * walk
	var bob := absf(sin(phase)) * 0.038 * walk
	if _pelvis:
		_pelvis.position.y = _rest["pelvis"].origin.y + bob
		_pelvis.rotation.z = sin(phase) * 0.045 * walk
	if _arm_l:
		_arm_l.rotation.x = _rest["arm_l"].basis.get_euler().x + swing
	if _arm_r:
		_arm_r.rotation.x = _rest["arm_r"].basis.get_euler().x + swing_opp
	if _thigh_l:
		_thigh_l.rotation.x = _rest["thigh_l"].basis.get_euler().x + swing_opp * 0.9
	if _thigh_r:
		_thigh_r.rotation.x = _rest["thigh_r"].basis.get_euler().x + swing * 0.9


func _cache_limbs() -> void:
	_pelvis = get_node_or_null("Pelvis")
	_torso = get_node_or_null("Torso")
	_head = get_node_or_null("Head")
	_arm_l = get_node_or_null("ArmL")
	_arm_r = get_node_or_null("ArmR")
	_thigh_l = get_node_or_null("ThighL")
	_thigh_r = get_node_or_null("ThighR")


func _store_rest() -> void:
	var map := {
		"pelvis": _pelvis, "torso": _torso, "head": _head,
		"arm_l": _arm_l, "arm_r": _arm_r, "thigh_l": _thigh_l, "thigh_r": _thigh_r
	}
	for n in map:
		var node: Node3D = map[n]
		if node:
			_rest[n] = node.transform


func _mat(path: String) -> Material:
	return load(path) as Material


func _kit_mats() -> Dictionary:
	var base := {
		"skin": "res://assets/materials/toon_skin.tres",
		"hair": "res://assets/materials/toon_hair.tres",
		"jacket": "res://assets/materials/toon_jacket.tres",
		"pants": "res://assets/materials/toon_pants.tres",
		"boots": "res://assets/materials/toon_boots.tres",
		"visor": "res://assets/materials/toon_visor.tres",
		"accent": "res://assets/materials/toon_accent.tres",
		"eyes": "res://assets/materials/toon_eyes.tres",
		"mask": "res://assets/materials/toon_mask.tres",
	}
	match kit:
		Kit.NPC_CIVILIAN:
			base["jacket"] = "res://assets/materials/toon_concrete.tres"
			base["accent"] = "res://assets/materials/toon_pants.tres"
		Kit.NPC_TECH:
			base["accent"] = "res://assets/materials/toon_visor.tres"
		Kit.ENEMY_THUG:
			base["jacket"] = "res://assets/materials/toon_boots.tres"
			base["visor"] = "res://assets/materials/toon_mask.tres"
		Kit.ENEMY_CORP:
			base["accent"] = "res://assets/materials/toon_accent.tres"
	return base


func _mesh_instance(mesh: Mesh, material: Material, parent: Node3D, name: String, xform: Transform3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = mesh
	mi.transform = xform
	if material:
		mi.material_override = material
	parent.add_child(mi)
	return mi


func _build() -> void:
	for c in get_children():
		remove_child(c)
		c.free()

	var m := _kit_mats()
	var skin := _mat(m["skin"])
	var hair := _mat(m["hair"])
	var jacket := _mat(m["jacket"])
	var pants := _mat(m["pants"])
	var boots := _mat(m["boots"])
	var visor := _mat(m["visor"])
	var accent := _mat(m["accent"])
	var eyes := _mat(m["eyes"])
	var mask_mat := _mat(m["mask"])

	# === PELVIS / HIPS (wider for comic proportions) ===
	var pelvis_mesh := BoxMesh.new()
	pelvis_mesh.size = Vector3(0.62, 0.28, 0.36)
	var pelvis := _mesh_instance(pelvis_mesh, pants, self, "Pelvis", Transform3D(Basis(), Vector3(0, 0.90, 0)))

	# Belt / hip accent
	var belt := BoxMesh.new()
	belt.size = Vector3(0.66, 0.08, 0.38)
	_mesh_instance(belt, accent, pelvis, "Belt", Transform3D(Basis(), Vector3(0, 0.12, 0)))

	# === TORSO (heroic V-shape: broad shoulders, tapered waist) ===
	var torso := Node3D.new()
	torso.name = "Torso"
	torso.position = Vector3(0, 1.28, 0)
	add_child(torso)

	# Upper chest (broader)
	var chest := BoxMesh.new()
	chest.size = Vector3(0.78, 0.42, 0.40)
	_mesh_instance(chest, jacket, torso, "Chest", Transform3D(Basis(), Vector3(0, 0.18, 0)))

	# Lower torso / abdomen (narrower)
	var abs_mesh := BoxMesh.new()
	abs_mesh.size = Vector3(0.58, 0.32, 0.34)
	_mesh_instance(abs_mesh, jacket, torso, "Abdomen", Transform3D(Basis(), Vector3(0, -0.18, 0)))

	# Shoulder pads (comic armor feel)
	var shoulder := BoxMesh.new()
	shoulder.size = Vector3(0.26, 0.18, 0.26)
	_mesh_instance(shoulder, jacket, torso, "ShoulderL", Transform3D(Basis(), Vector3(-0.48, 0.28, 0)))
	_mesh_instance(shoulder, jacket, torso, "ShoulderR", Transform3D(Basis(), Vector3(0.48, 0.28, 0)))

	# Collar / high neck of jacket
	var collar := BoxMesh.new()
	collar.size = Vector3(0.48, 0.14, 0.28)
	_mesh_instance(collar, jacket, torso, "Collar", Transform3D(Basis(), Vector3(0, 0.38, -0.04)))

	# Neon accent strip across chest
	var strip := BoxMesh.new()
	strip.size = Vector3(0.36, 0.06, 0.08)
	_mesh_instance(strip, accent, torso, "ChestStrip", Transform3D(Basis(), Vector3(0, 0.08, 0.21)))

	# Jacket front panels (lapels)
	var lapel := BoxMesh.new()
	lapel.size = Vector3(0.18, 0.36, 0.06)
	_mesh_instance(lapel, jacket, torso, "LapelL", Transform3D(Basis.from_euler(Vector3(0, 0.25, 0)), Vector3(-0.18, 0.05, 0.20)))
	_mesh_instance(lapel, jacket, torso, "LapelR", Transform3D(Basis.from_euler(Vector3(0, -0.25, 0)), Vector3(0.18, 0.05, 0.20)))

	# === HEAD (larger, more cartoonish) ===
	var head := Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, 1.82, 0)
	add_child(head)

	# Main cranium
	var skull := CapsuleMesh.new()
	skull.radius = 0.20
	skull.height = 0.42
	_mesh_instance(skull, skin, head, "Skull", Transform3D(Basis(), Vector3(0, 0.02, 0)))

	# Jaw / chin (angular)
	var jaw := BoxMesh.new()
	jaw.size = Vector3(0.28, 0.14, 0.22)
	_mesh_instance(jaw, skin, head, "Jaw", Transform3D(Basis(), Vector3(0, -0.14, 0.02)))

	# Face plane
	var face_plane := BoxMesh.new()
	face_plane.size = Vector3(0.30, 0.26, 0.06)
	_mesh_instance(face_plane, skin, head, "FacePlane", Transform3D(Basis(), Vector3(0, 0.02, -0.16)))

	# === HAIR ===
	_build_hair(head, hair)

	# === FACE DETAILS ===
	# Large comic eyes
	var eye := BoxMesh.new()
	eye.size = Vector3(0.09, 0.055, 0.04)
	_mesh_instance(eye, eyes, head, "EyeL", Transform3D(Basis(), Vector3(-0.075, 0.06, -0.19)))
	_mesh_instance(eye, eyes, head, "EyeR", Transform3D(Basis(), Vector3(0.075, 0.06, -0.19)))

	# Thick comic brows
	var brow := BoxMesh.new()
	brow.size = Vector3(0.30, 0.04, 0.05)
	_mesh_instance(brow, hair if hair_style > 0 else skin, head, "Brow", Transform3D(Basis(), Vector3(0, 0.12, -0.18)))

	# Nose
	var nose := BoxMesh.new()
	nose.size = Vector3(0.05, 0.06, 0.07)
	_mesh_instance(nose, skin, head, "Nose", Transform3D(Basis(), Vector3(0, 0.0, -0.21)))

	# Mouth suggestion
	var mouth := BoxMesh.new()
	mouth.size = Vector3(0.12, 0.025, 0.03)
	_mesh_instance(mouth, skin, head, "Mouth", Transform3D(Basis(), Vector3(0, -0.08, -0.19)))

	# Visor or mask
	if face_mask:
		var mask_mesh := BoxMesh.new()
		mask_mesh.size = Vector3(0.36, 0.18, 0.16)
		_mesh_instance(mask_mesh, mask_mat, head, "Mask", Transform3D(Basis(), Vector3(0, 0.01, -0.15)))
	elif show_visor:
		var visor_mesh := BoxMesh.new()
		visor_mesh.size = Vector3(0.36, 0.10, 0.12)
		_mesh_instance(visor_mesh, visor, head, "Visor", Transform3D(Basis(), Vector3(0, 0.05, -0.18)))
		# Visor glow edge
		var visor_edge := BoxMesh.new()
		visor_edge.size = Vector3(0.38, 0.02, 0.04)
		_mesh_instance(visor_edge, accent, head, "VisorEdge", Transform3D(Basis(), Vector3(0, 0.11, -0.17)))

	# === NECK ===
	var neck := CapsuleMesh.new()
	neck.radius = 0.075
	neck.height = 0.18
	_mesh_instance(neck, skin, self, "Neck", Transform3D(Basis(), Vector3(0, 1.64, 0)))

	# === ARMS ===
	_build_arm(self, "ArmL", Vector3(-0.55, 1.30, 0), -0.32, jacket, skin, accent)
	_build_arm(self, "ArmR", Vector3(0.55, 1.30, 0), 0.32, jacket, skin, accent)

	# === LEGS ===
	_build_leg(self, "ThighL", Vector3(-0.17, 0.58, 0), pants, boots)
	_build_leg(self, "ThighR", Vector3(0.17, 0.58, 0), pants, boots)


func _build_hair(head: Node3D, hair_mat: Material) -> void:
	# Base hair volume
	var base := SphereMesh.new()
	base.radius = 0.22
	base.height = 0.36
	base.radial_segments = 12
	base.rings = 6
	_mesh_instance(base, hair_mat, head, "HairBase",
		Transform3D(Basis.from_scale(Vector3(1.15, 0.85, 1.1)), Vector3(0, 0.12, -0.01)))

	if hair_style >= 1:
		# Front fringe / volume
		var fringe := SphereMesh.new()
		fringe.radius = 0.16
		fringe.height = 0.22
		_mesh_instance(fringe, hair_mat, head, "HairFront",
			Transform3D(Basis.from_scale(Vector3(1.1, 0.55, 0.7)), Vector3(0, 0.14, -0.14)))

	if hair_style >= 2:
		# Mohawk / cyber spikes
		var spike := BoxMesh.new()
		spike.size = Vector3(0.08, 0.22, 0.12)
		_mesh_instance(spike, hair_mat, head, "Spike1", Transform3D(Basis(), Vector3(0, 0.28, -0.02)))
		_mesh_instance(spike, hair_mat, head, "Spike2", Transform3D(Basis.from_euler(Vector3(0.3, 0, 0)), Vector3(0, 0.24, -0.10)))
		_mesh_instance(spike, hair_mat, head, "Spike3", Transform3D(Basis.from_euler(Vector3(-0.25, 0, 0)), Vector3(0, 0.24, 0.08)))


func _build_arm(parent: Node3D, name: String, pos: Vector3, shoulder_roll: float,
		sleeve: Material, skin: Material, accent: Material) -> void:
	# Upper arm
	var upper := CapsuleMesh.new()
	upper.radius = 0.095
	upper.height = 0.52
	var basis := Basis.from_euler(Vector3(0, 0, shoulder_roll))
	var arm := _mesh_instance(upper, sleeve, parent, name, Transform3D(basis, pos))

	# Elbow joint
	var elbow := SphereMesh.new()
	elbow.radius = 0.08
	_mesh_instance(elbow, sleeve, arm, "Elbow", Transform3D(Basis(), Vector3(0, -0.28, 0)))

	# Forearm
	var lower := CapsuleMesh.new()
	lower.radius = 0.075
	lower.height = 0.42
	var forearm := _mesh_instance(lower, skin, arm, "Forearm",
		Transform3D(Basis.from_euler(Vector3(0.22, 0, 0)), Vector3(0, -0.48, 0.02)))

	# Glove / hand base
	var hand := BoxMesh.new()
	hand.size = Vector3(0.11, 0.09, 0.16)
	var hand_n := _mesh_instance(hand, skin, forearm, "Hand",
		Transform3D(Basis(), Vector3(0, -0.28, 0.02)))

	# Simple finger suggestions
	var finger := BoxMesh.new()
	finger.size = Vector3(0.025, 0.04, 0.07)
	_mesh_instance(finger, skin, hand_n, "F1", Transform3D(Basis(), Vector3(-0.03, -0.04, -0.09)))
	_mesh_instance(finger, skin, hand_n, "F2", Transform3D(Basis(), Vector3(0.0, -0.05, -0.10)))
	_mesh_instance(finger, skin, hand_n, "F3", Transform3D(Basis(), Vector3(0.03, -0.04, -0.09)))

	# Wrist accent band
	var band := BoxMesh.new()
	band.size = Vector3(0.12, 0.04, 0.12)
	_mesh_instance(band, accent, forearm, "WristBand", Transform3D(Basis(), Vector3(0, -0.18, 0)))


func _build_leg(parent: Node3D, name: String, pos: Vector3, pants: Material, boots: Material) -> void:
	# Thigh
	var thigh_mesh := CapsuleMesh.new()
	thigh_mesh.radius = 0.125
	thigh_mesh.height = 0.48
	var thigh := _mesh_instance(thigh_mesh, pants, parent, name,
		Transform3D(Basis.from_euler(Vector3(0.12, 0, 0)), pos))

	# Knee
	var knee := SphereMesh.new()
	knee.radius = 0.09
	_mesh_instance(knee, pants, thigh, "Knee", Transform3D(Basis(), Vector3(0, -0.26, 0.01)))

	# Shin
	var shin_mesh := CapsuleMesh.new()
	shin_mesh.radius = 0.095
	shin_mesh.height = 0.44
	var shin := _mesh_instance(shin_mesh, pants, thigh, "Shin",
		Transform3D(Basis.from_euler(Vector3(-0.18, 0, 0)), Vector3(0, -0.48, 0)))

	# Boot shaft (higher)
	var boot_shaft := BoxMesh.new()
	boot_shaft.size = Vector3(0.18, 0.22, 0.22)
	_mesh_instance(boot_shaft, boots, shin, "BootShaft",
		Transform3D(Basis(), Vector3(0, -0.22, 0.01)))

	# Boot sole / toe
	var sole := BoxMesh.new()
	sole.size = Vector3(0.20, 0.08, 0.32)
	_mesh_instance(sole, boots, shin, "BootSole",
		Transform3D(Basis(), Vector3(0, -0.34, -0.04)))
