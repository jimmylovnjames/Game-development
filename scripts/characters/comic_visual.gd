class_name ComicVisual
extends Node3D
## Marvel-principle comic humanoid for NeonWastesRPG.
## Applies: 8-head heroic proportions, strong silhouette, clear face,
## layered costume, heavier outer contour, straights-vs-curves.

enum Kit { PLAYER, NPC_CIVILIAN, NPC_TECH, ENEMY_THUG, ENEMY_CORP }

@export var kit: Kit = Kit.PLAYER
@export var face_mask: bool = false
@export var show_visor: bool = true
@export var hair_style: int = 0   # 0 short, 1 volume, 2 spikes/mohawk
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
	var breathe := sin(_time * 1.55) * 0.015 * idle
	if _torso:
		_torso.position.y = _rest["torso"].origin.y + breathe
		_torso.rotation.x = _rest["torso"].basis.get_euler().x + sin(_time * 1.55) * 0.022 * idle
	if _head:
		_head.rotation.x = _rest["head"].basis.get_euler().x + sin(_time * 1.25) * 0.03 * idle
		_head.rotation.y = _rest["head"].basis.get_euler().y + sin(_time * 0.65) * 0.04 * idle
	var phase := _time * (6.2 + _speed_factor * 2.2)
	var swing := sin(phase) * 0.52 * walk
	var swing_opp := sin(phase + PI) * 0.52 * walk
	var bob := absf(sin(phase)) * 0.04 * walk
	if _pelvis:
		_pelvis.position.y = _rest["pelvis"].origin.y + bob
		_pelvis.rotation.z = sin(phase) * 0.04 * walk
	if _arm_l:
		_arm_l.rotation.x = _rest["arm_l"].basis.get_euler().x + swing
	if _arm_r:
		_arm_r.rotation.x = _rest["arm_r"].basis.get_euler().x + swing_opp
	if _thigh_l:
		_thigh_l.rotation.x = _rest["thigh_l"].basis.get_euler().x + swing_opp * 0.88
	if _thigh_r:
		_thigh_r.rotation.x = _rest["thigh_r"].basis.get_euler().x + swing * 0.88


func _cache_limbs() -> void:
	_pelvis = get_node_or_null("Pelvis")
	_torso = get_node_or_null("Torso")
	_head = get_node_or_null("Head")
	_arm_l = get_node_or_null("ArmL")
	_arm_r = get_node_or_null("ArmR")
	_thigh_l = get_node_or_null("ThighL")
	_thigh_r = get_node_or_null("ThighR")


func _store_rest() -> void:
	var map := {"pelvis": _pelvis, "torso": _torso, "head": _head,
		"arm_l": _arm_l, "arm_r": _arm_r, "thigh_l": _thigh_l, "thigh_r": _thigh_r}
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


func _mesh(mesh: Mesh, mat: Material, parent: Node3D, name: String, xform: Transform3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = mesh
	mi.transform = xform
	if mat:
		mi.material_override = mat
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

	# === HEROIC PROPORTIONS (≈8-head system) ===
	# Longer legs, broader shoulders, narrower waist, larger head

	# PELVIS – wider for stable silhouette
	var pelvis_mesh := BoxMesh.new()
	pelvis_mesh.size = Vector3(0.68, 0.26, 0.38)
	var pelvis := _mesh(pelvis_mesh, pants, self, "Pelvis", Transform3D(Basis(), Vector3(0, 0.88, 0)))
	var belt := BoxMesh.new()
	belt.size = Vector3(0.72, 0.07, 0.40)
	_mesh(belt, accent, pelvis, "Belt", Transform3D(Basis(), Vector3(0, 0.11, 0)))

	# TORSO – strong V (broad shoulders → narrow waist)
	var torso := Node3D.new()
	torso.name = "Torso"
	torso.position = Vector3(0, 1.32, 0)
	add_child(torso)

	# Upper chest – very broad (silhouette priority)
	var chest := BoxMesh.new()
	chest.size = Vector3(0.88, 0.46, 0.42)
	_mesh(chest, jacket, torso, "Chest", Transform3D(Basis(), Vector3(0, 0.16, 0)))

	# Abdomen – tapered
	var abdomen := BoxMesh.new()
	abdomen.size = Vector3(0.56, 0.34, 0.34)
	_mesh(abdomen, jacket, torso, "Abdomen", Transform3D(Basis(), Vector3(0, -0.22, 0)))

	# Heavy shoulder pads (comic armor mass)
	var pad := BoxMesh.new()
	pad.size = Vector3(0.30, 0.22, 0.30)
	_mesh(pad, jacket, torso, "PadL", Transform3D(Basis(), Vector3(-0.52, 0.30, 0)))
	_mesh(pad, jacket, torso, "PadR", Transform3D(Basis(), Vector3(0.52, 0.30, 0)))

	# High collar
	var collar := BoxMesh.new()
	collar.size = Vector3(0.52, 0.16, 0.30)
	_mesh(collar, jacket, torso, "Collar", Transform3D(Basis(), Vector3(0, 0.40, -0.05)))

	# Neon chest accent (clear focal point)
	var strip := BoxMesh.new()
	strip.size = Vector3(0.40, 0.07, 0.09)
	_mesh(strip, accent, torso, "ChestStrip", Transform3D(Basis(), Vector3(0, 0.06, 0.22)))

	# Lapels for costume layering
	var lapel := BoxMesh.new()
	lapel.size = Vector3(0.20, 0.40, 0.07)
	_mesh(lapel, jacket, torso, "LapelL", Transform3D(Basis.from_euler(Vector3(0, 0.28, 0)), Vector3(-0.20, 0.02, 0.21)))
	_mesh(lapel, jacket, torso, "LapelR", Transform3D(Basis.from_euler(Vector3(0, -0.28, 0)), Vector3(0.20, 0.02, 0.21)))

	# === HEAD – larger, stronger features ===
	var head := Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, 1.90, 0)
	add_child(head)

	# Skull
	var skull := CapsuleMesh.new()
	skull.radius = 0.215
	skull.height = 0.44
	_mesh(skull, skin, head, "Skull", Transform3D(Basis(), Vector3(0, 0.03, 0)))

	# Strong angular jaw (Marvel face principle)
	var jaw := BoxMesh.new()
	jaw.size = Vector3(0.32, 0.16, 0.24)
	_mesh(jaw, skin, head, "Jaw", Transform3D(Basis(), Vector3(0, -0.16, 0.01)))

	# Face plane for clean feature placement
	var face := BoxMesh.new()
	face.size = Vector3(0.32, 0.28, 0.06)
	_mesh(face, skin, head, "FacePlane", Transform3D(Basis(), Vector3(0, 0.02, -0.17)))

	_build_hair(head, hair)

	# LARGE comic eyes (key readability principle)
	var eye := BoxMesh.new()
	eye.size = Vector3(0.105, 0.065, 0.045)
	_mesh(eye, eyes, head, "EyeL", Transform3D(Basis(), Vector3(-0.08, 0.07, -0.20)))
	_mesh(eye, eyes, head, "EyeR", Transform3D(Basis(), Vector3(0.08, 0.07, -0.20)))

	# Heavy brow
	var brow := BoxMesh.new()
	brow.size = Vector3(0.34, 0.05, 0.06)
	_mesh(brow, hair if hair_style > 0 else skin, head, "Brow", Transform3D(Basis(), Vector3(0, 0.14, -0.19)))

	# Nose
	var nose := BoxMesh.new()
	nose.size = Vector3(0.055, 0.07, 0.08)
	_mesh(nose, skin, head, "Nose", Transform3D(Basis(), Vector3(0, 0.0, -0.22)))

	# Mouth
	var mouth := BoxMesh.new()
	mouth.size = Vector3(0.14, 0.03, 0.035)
	_mesh(mouth, skin, head, "Mouth", Transform3D(Basis(), Vector3(0, -0.09, -0.20)))

	if face_mask:
		var mask_m := BoxMesh.new()
		mask_m.size = Vector3(0.38, 0.20, 0.17)
		_mesh(mask_m, mask_mat, head, "Mask", Transform3D(Basis(), Vector3(0, 0.01, -0.16)))
	elif show_visor:
		var vis := BoxMesh.new()
		vis.size = Vector3(0.38, 0.11, 0.13)
		_mesh(vis, visor, head, "Visor", Transform3D(Basis(), Vector3(0, 0.06, -0.19)))
		var edge := BoxMesh.new()
		edge.size = Vector3(0.40, 0.025, 0.045)
		_mesh(edge, accent, head, "VisorEdge", Transform3D(Basis(), Vector3(0, 0.125, -0.18)))

	# Neck
	var neck := CapsuleMesh.new()
	neck.radius = 0.08
	neck.height = 0.18
	_mesh(neck, skin, self, "Neck", Transform3D(Basis(), Vector3(0, 1.68, 0)))

	# ARMS – stronger upper mass
	_build_arm(self, "ArmL", Vector3(-0.60, 1.34, 0), -0.35, jacket, skin, accent)
	_build_arm(self, "ArmR", Vector3(0.60, 1.34, 0), 0.35, jacket, skin, accent)

	# LEGS – longer for heroic proportion
	_build_leg(self, "ThighL", Vector3(-0.18, 0.55, 0), pants, boots)
	_build_leg(self, "ThighR", Vector3(0.18, 0.55, 0), pants, boots)


func _build_hair(head: Node3D, hair_mat: Material) -> void:
	var base := SphereMesh.new()
	base.radius = 0.23
	base.height = 0.38
	base.radial_segments = 12
	base.rings = 6
	_mesh(base, hair_mat, head, "HairBase",
		Transform3D(Basis.from_scale(Vector3(1.18, 0.88, 1.12)), Vector3(0, 0.13, -0.01)))

	if hair_style >= 1:
		var fringe := SphereMesh.new()
		fringe.radius = 0.17
		fringe.height = 0.24
		_mesh(fringe, hair_mat, head, "HairFront",
			Transform3D(Basis.from_scale(Vector3(1.12, 0.58, 0.72)), Vector3(0, 0.15, -0.15)))

	if hair_style >= 2:
		var spike := BoxMesh.new()
		spike.size = Vector3(0.09, 0.24, 0.13)
		_mesh(spike, hair_mat, head, "Spike1", Transform3D(Basis(), Vector3(0, 0.30, -0.02)))
		_mesh(spike, hair_mat, head, "Spike2", Transform3D(Basis.from_euler(Vector3(0.32, 0, 0)), Vector3(0, 0.26, -0.11)))
		_mesh(spike, hair_mat, head, "Spike3", Transform3D(Basis.from_euler(Vector3(-0.28, 0, 0)), Vector3(0, 0.26, 0.09)))


func _build_arm(parent: Node3D, name: String, pos: Vector3, roll: float,
		sleeve: Material, skin: Material, accent: Material) -> void:
	var upper := CapsuleMesh.new()
	upper.radius = 0.105
	upper.height = 0.54
	var basis := Basis.from_euler(Vector3(0, 0, roll))
	var arm := _mesh(upper, sleeve, parent, name, Transform3D(basis, pos))

	var elbow := SphereMesh.new()
	elbow.radius = 0.09
	_mesh(elbow, sleeve, arm, "Elbow", Transform3D(Basis(), Vector3(0, -0.29, 0)))

	var lower := CapsuleMesh.new()
	lower.radius = 0.08
	lower.height = 0.44
	var forearm := _mesh(lower, skin, arm, "Forearm",
		Transform3D(Basis.from_euler(Vector3(0.20, 0, 0)), Vector3(0, -0.50, 0.02)))

	var hand := BoxMesh.new()
	hand.size = Vector3(0.12, 0.10, 0.17)
	var hand_n := _mesh(hand, skin, forearm, "Hand", Transform3D(Basis(), Vector3(0, -0.29, 0.02)))

	var finger := BoxMesh.new()
	finger.size = Vector3(0.028, 0.045, 0.075)
	_mesh(finger, skin, hand_n, "F1", Transform3D(Basis(), Vector3(-0.032, -0.045, -0.095)))
	_mesh(finger, skin, hand_n, "F2", Transform3D(Basis(), Vector3(0.0, -0.055, -0.105)))
	_mesh(finger, skin, hand_n, "F3", Transform3D(Basis(), Vector3(0.032, -0.045, -0.095)))

	var band := BoxMesh.new()
	band.size = Vector3(0.13, 0.04, 0.13)
	_mesh(band, accent, forearm, "Wrist", Transform3D(Basis(), Vector3(0, -0.19, 0)))


func _build_leg(parent: Node3D, name: String, pos: Vector3, pants: Material, boots: Material) -> void:
	# Longer thigh for heroic leg length
	var thigh_m := CapsuleMesh.new()
	thigh_m.radius = 0.13
	thigh_m.height = 0.52
	var thigh := _mesh(thigh_m, pants, parent, name,
		Transform3D(Basis.from_euler(Vector3(0.10, 0, 0)), pos))

	var knee := SphereMesh.new()
	knee.radius = 0.095
	_mesh(knee, pants, thigh, "Knee", Transform3D(Basis(), Vector3(0, -0.28, 0.01)))

	var shin_m := CapsuleMesh.new()
	shin_m.radius = 0.10
	shin_m.height = 0.48
	var shin := _mesh(shin_m, pants, thigh, "Shin",
		Transform3D(Basis.from_euler(Vector3(-0.16, 0, 0)), Vector3(0, -0.52, 0)))

	# Higher, more structured boot
	var shaft := BoxMesh.new()
	shaft.size = Vector3(0.20, 0.26, 0.24)
	_mesh(shaft, boots, shin, "BootShaft", Transform3D(Basis(), Vector3(0, -0.24, 0.01)))

	var sole := BoxMesh.new()
	sole.size = Vector3(0.22, 0.09, 0.34)
	_mesh(sole, boots, shin, "BootSole", Transform3D(Basis(), Vector3(0, -0.38, -0.05)))
