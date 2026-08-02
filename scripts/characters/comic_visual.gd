class_name ComicVisual
extends Node3D
## Procedural comic-book humanoid for NeonWastesRPG.
## Builds body, applies material kits, drives idle/walk poses, face slots.

enum Kit { PLAYER, NPC_CIVILIAN, NPC_TECH, ENEMY_THUG, ENEMY_CORP }

@export var kit: Kit = Kit.PLAYER
@export var face_mask: bool = false
@export var show_visor: bool = true
@export var hair_style: int = 0
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
	var breathe := sin(_time * 1.6) * 0.012 * idle
	if _torso:
		_torso.position.y = _rest["torso"].origin.y + breathe
		_torso.rotation.x = _rest["torso"].basis.get_euler().x + sin(_time * 1.6) * 0.02 * idle
	if _head:
		_head.rotation.x = _rest["head"].basis.get_euler().x + sin(_time * 1.3) * 0.03 * idle
		_head.rotation.y = _rest["head"].basis.get_euler().y + sin(_time * 0.7) * 0.04 * idle
	var phase := _time * (6.5 + _speed_factor * 2.0)
	var swing := sin(phase) * 0.55 * walk
	var swing_opp := sin(phase + PI) * 0.55 * walk
	var bob := absf(sin(phase)) * 0.035 * walk
	if _pelvis:
		_pelvis.position.y = _rest["pelvis"].origin.y + bob
		_pelvis.rotation.z = sin(phase) * 0.04 * walk
	if _arm_l:
		_arm_l.rotation.x = _rest["arm_l"].basis.get_euler().x + swing
	if _arm_r:
		_arm_r.rotation.x = _rest["arm_r"].basis.get_euler().x + swing_opp
	if _thigh_l:
		_thigh_l.rotation.x = _rest["thigh_l"].basis.get_euler().x + swing_opp * 0.85
	if _thigh_r:
		_thigh_r.rotation.x = _rest["thigh_r"].basis.get_euler().x + swing * 0.85

func _cache_limbs() -> void:
	_pelvis = get_node_or_null("Pelvis")
	_torso = get_node_or_null("Torso")
	_head = get_node_or_null("Head")
	_arm_l = get_node_or_null("ArmL")
	_arm_r = get_node_or_null("ArmR")
	_thigh_l = get_node_or_null("ThighL")
	_thigh_r = get_node_or_null("ThighR")

func _store_rest() -> void:
	var map := {"pelvis": _pelvis, "torso": _torso, "head": _head, "arm_l": _arm_l, "arm_r": _arm_r, "thigh_l": _thigh_l, "thigh_r": _thigh_r}
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
	var skin := _mat(m["skin"]); var hair := _mat(m["hair"]); var jacket := _mat(m["jacket"])
	var pants := _mat(m["pants"]); var boots := _mat(m["boots"]); var visor := _mat(m["visor"])
	var accent := _mat(m["accent"]); var eyes := _mat(m["eyes"]); var mask_mat := _mat(m["mask"])

	var pelvis_mesh := BoxMesh.new(); pelvis_mesh.size = Vector3(0.56, 0.26, 0.32)
	var pelvis := _mesh_instance(pelvis_mesh, pants, self, "Pelvis", Transform3D(Basis(), Vector3(0, 0.92, 0)))
	var belt_mesh := BoxMesh.new(); belt_mesh.size = Vector3(0.6, 0.07, 0.34)
	_mesh_instance(belt_mesh, accent, pelvis, "Belt", Transform3D(Basis(), Vector3(0, 0.14, 0)))

	var torso_mesh := BoxMesh.new(); torso_mesh.size = Vector3(0.7, 0.6, 0.36)
	var torso := _mesh_instance(torso_mesh, jacket, self, "Torso", Transform3D(Basis(), Vector3(0, 1.34, 0)))
	var collar_mesh := BoxMesh.new(); collar_mesh.size = Vector3(0.52, 0.1, 0.26)
	_mesh_instance(collar_mesh, jacket, torso, "Collar", Transform3D(Basis(), Vector3(0, 0.32, -0.02)))
	var shoulder_mesh := BoxMesh.new(); shoulder_mesh.size = Vector3(0.2, 0.14, 0.2)
	_mesh_instance(shoulder_mesh, jacket, torso, "ShoulderL", Transform3D(Basis(), Vector3(-0.4, 0.2, 0)))
	_mesh_instance(shoulder_mesh, jacket, torso, "ShoulderR", Transform3D(Basis(), Vector3(0.4, 0.2, 0)))
	var strip := BoxMesh.new(); strip.size = Vector3(0.28, 0.05, 0.06)
	_mesh_instance(strip, accent, torso, "AccentStrip", Transform3D(Basis(), Vector3(0, 0.05, 0.19)))

	var head_mesh := CapsuleMesh.new(); head_mesh.radius = 0.19; head_mesh.height = 0.4
	var head := _mesh_instance(head_mesh, skin, self, "Head", Transform3D(Basis(), Vector3(0, 1.86, 0)))
	var hair_mesh := SphereMesh.new(); hair_mesh.radius = 0.21; hair_mesh.height = 0.34; hair_mesh.radial_segments = 12; hair_mesh.rings = 6
	_mesh_instance(hair_mesh, hair, head, "Hair", Transform3D(Basis.from_scale(Vector3(1.12, 0.82, 1.08)), Vector3(0, 0.1, -0.02)))
	if hair_style >= 1:
		_mesh_instance(hair_mesh, hair, head, "HairFront", Transform3D(Basis.from_scale(Vector3(1.0, 0.5, 0.65)), Vector3(0, 0.12, -0.12)))

	var eye_mesh := BoxMesh.new(); eye_mesh.size = Vector3(0.07, 0.035, 0.03)
	_mesh_instance(eye_mesh, eyes, head, "EyeL", Transform3D(Basis(), Vector3(-0.07, 0.04, -0.17)))
	_mesh_instance(eye_mesh, eyes, head, "EyeR", Transform3D(Basis(), Vector3(0.07, 0.04, -0.17)))
	var brow := BoxMesh.new(); brow.size = Vector3(0.28, 0.03, 0.06)
	_mesh_instance(brow, hair if hair_style > 0 else skin, head, "Brow", Transform3D(Basis(), Vector3(0, 0.09, -0.16)))
	if face_mask:
		var mask_mesh := BoxMesh.new(); mask_mesh.size = Vector3(0.34, 0.16, 0.14)
		_mesh_instance(mask_mesh, mask_mat, head, "Mask", Transform3D(Basis(), Vector3(0, -0.02, -0.14)))
	elif show_visor:
		var visor_mesh := BoxMesh.new(); visor_mesh.size = Vector3(0.34, 0.08, 0.11)
		_mesh_instance(visor_mesh, visor, head, "Visor", Transform3D(Basis(), Vector3(0, 0.03, -0.16)))
	var nose := BoxMesh.new(); nose.size = Vector3(0.04, 0.05, 0.06)
	_mesh_instance(nose, skin, head, "Nose", Transform3D(Basis(), Vector3(0, -0.01, -0.19)))

	var neck_mesh := CapsuleMesh.new(); neck_mesh.radius = 0.07; neck_mesh.height = 0.2
	_mesh_instance(neck_mesh, skin, self, "Neck", Transform3D(Basis(), Vector3(0, 1.66, 0)))
	_build_arm(self, "ArmL", Vector3(-0.5, 1.26, 0), -0.28, jacket, skin)
	_build_arm(self, "ArmR", Vector3(0.5, 1.26, 0), 0.28, jacket, skin)
	_build_leg(self, "ThighL", Vector3(-0.15, 0.62, 0), pants, boots)
	_build_leg(self, "ThighR", Vector3(0.15, 0.62, 0), pants, boots)

func _build_arm(parent: Node3D, name: String, pos: Vector3, shoulder_roll: float, sleeve: Material, skin: Material) -> void:
	var upper := CapsuleMesh.new(); upper.radius = 0.085; upper.height = 0.55
	var basis := Basis.from_euler(Vector3(0, 0, shoulder_roll))
	var arm := _mesh_instance(upper, sleeve, parent, name, Transform3D(basis, pos))
	var lower := CapsuleMesh.new(); lower.radius = 0.07; lower.height = 0.45
	var forearm := _mesh_instance(lower, skin, arm, "Forearm", Transform3D(Basis.from_euler(Vector3(0.25, 0, 0)), Vector3(0, -0.46, 0.03)))
	var hand := BoxMesh.new(); hand.size = Vector3(0.1, 0.07, 0.14)
	_mesh_instance(hand, skin, forearm, "Hand", Transform3D(Basis(), Vector3(0, -0.26, 0.02)))

func _build_leg(parent: Node3D, name: String, pos: Vector3, pants: Material, boots: Material) -> void:
	var thigh_mesh := CapsuleMesh.new(); thigh_mesh.radius = 0.12; thigh_mesh.height = 0.5
	var thigh := _mesh_instance(thigh_mesh, pants, parent, name, Transform3D(Basis.from_euler(Vector3(0.15, 0, 0)), pos))
	var shin_mesh := CapsuleMesh.new(); shin_mesh.radius = 0.09; shin_mesh.height = 0.46
	var shin := _mesh_instance(shin_mesh, pants, thigh, "Shin", Transform3D(Basis.from_euler(Vector3(-0.2, 0, 0)), Vector3(0, -0.46, 0)))
	var boot := BoxMesh.new(); boot.size = Vector3(0.18, 0.12, 0.3)
	_mesh_instance(boot, boots, shin, "Boot", Transform3D(Basis(), Vector3(0, -0.28, -0.04)))
