class_name CharacterBuilder
extends RefCounted
## Procedural comic characters. No model files, no textures: every figure is
## assembled from primitives with exaggerated comic proportions (oversized
## head, blocked coat silhouette, glowing eye-slits) and finished with the
## shared toon shader plus an ink outline pass.
##
## Archetypes change geometry, not just palette — a preacher reads as a
## preacher from across the plaza in silhouette, which is the whole job at
## blockout fidelity.

const TOON := preload("res://shaders/toon_cel.gdshader")
const NEON := preload("res://shaders/neon_sign.gdshader")
const INK := preload("res://assets/materials/outline_ink.tres")
## Authored 3-band light ramp. Characters get the ramp rather than the numeric
## banding so the shadow end can drift cold violet and the lit end warm — a hue
## shift across the terminator that a band count cannot express.
const LIGHT_RAMP := preload("res://assets/materials/ramps/ramp_character.tres")

## archetype -> feature flags the assembler reads
const FEATURES := {
	&"fixer": {"hat": "brim", "coat": "long", "collar": true, "eyes": "visor", "bag": false, "pendant": false},
	&"vendor": {"hat": "cap", "coat": "apron", "collar": false, "eyes": "pair", "bag": false, "pendant": false},
	&"preacher": {"hat": "hood", "coat": "robe", "collar": false, "eyes": "pair", "bag": false, "pendant": true},
	&"urchin": {"hat": "hoodie", "coat": "short", "collar": false, "eyes": "pair", "bag": true, "pendant": false},
	&"warden": {"hat": "peaked", "coat": "long", "collar": true, "eyes": "pair", "bag": false, "pendant": false},
	&"courier": {"hat": "cap", "coat": "short", "collar": true, "eyes": "visor", "bag": true, "pendant": false},
}

## Default palettes per archetype: coat / trim (accent + rim) / skin / eyes.
## Saturated colour lives in trim and eyes only — the style bible's rule.
const PALETTES := {
	&"fixer": [Color(0.1, 0.11, 0.15), Color(1.0, 0.176, 0.584), Color(0.72, 0.66, 0.79), Color(1.0, 0.176, 0.584)],
	&"vendor": [Color(0.23, 0.14, 0.09), Color(1.0, 0.68, 0.36), Color(0.79, 0.66, 0.55), Color(1.0, 0.68, 0.36)],
	&"preacher": [Color(0.07, 0.07, 0.1), Color(0.969, 1.0, 0.235), Color(0.61, 0.56, 0.72), Color(0.969, 1.0, 0.235)],
	&"urchin": [Color(0.11, 0.13, 0.19), Color(0.0, 0.898, 1.0), Color(0.72, 0.6, 0.52), Color(0.0, 0.898, 1.0)],
	&"warden": [Color(0.14, 0.13, 0.1), Color(0.56, 0.66, 0.78), Color(0.66, 0.6, 0.56), Color(0.56, 0.66, 0.78)],
	&"courier": [Color(0.09, 0.13, 0.17), Color(0.0, 0.898, 1.0), Color(0.72, 0.66, 0.79), Color(0.0, 0.898, 1.0)],
}


## Build a rig. Returns a Node3D named "Rig" whose origin sits at the feet,
## with meta "height" so callers can place bark labels and cameras.
static func build(
	archetype: StringName,
	height: float = 1.8,
	bulk: float = 1.0,
	palette_override := PackedColorArray()
) -> Node3D:
	var palette: PackedColorArray = PALETTES.get(archetype, PALETTES[&"fixer"])
	if palette_override.size() == 4:
		palette = palette_override
	var features: Dictionary = FEATURES.get(archetype, FEATURES[&"fixer"])

	var coat_mat := _toon(palette[0], palette[1], 0.85)
	var trim_mat := _toon(palette[0].darkened(0.35), palette[1], 0.8)
	var skin_mat := _toon(palette[2], palette[1], 0.65)
	var hat_mat := _toon(palette[0].darkened(0.5), palette[1], 0.85)
	var eye_mat := _neon(palette[3], 1.9)
	var glow_mat := _neon(palette[1], 2.2)

	var rig := Node3D.new()
	rig.name = "Rig"
	rig.set_meta("height", height)
	rig.set_meta("archetype", archetype)

	# Comic proportions: legs ~42%, torso ~34%, head oversized.
	var hip_y := height * 0.46
	var shoulder_y := height * 0.76
	var head_y := height * 0.87
	var half_w := 0.105 * bulk

	# Legs: tapered, slightly apart, dark boots.
	for side in [-1.0, 1.0]:
		var leg := _cyl(0.075 * bulk, 0.055 * bulk, hip_y * 0.92)
		_part(rig, leg, coat_mat, Vector3(side * half_w, hip_y * 0.48, 0.0), "Leg" + _s(side))
		var boot := _box(Vector3(0.16 * bulk, 0.09, 0.26))
		_part(rig, boot, hat_mat, Vector3(side * half_w, 0.045, -0.03), "Boot" + _s(side))

	# Hips and torso: a hard-edged block, belted at the waist.
	_part(rig, _box(Vector3(0.3 * bulk, 0.16, 0.2 * bulk)), coat_mat,
		Vector3(0.0, hip_y + 0.06, 0.0), "Hips")
	_part(rig, _box(Vector3(0.4 * bulk, shoulder_y - hip_y - 0.06, 0.24 * bulk)), coat_mat,
		Vector3(0.0, (hip_y + shoulder_y) * 0.5 + 0.02, 0.0), "Torso")
	_part(rig, _box(Vector3(0.42 * bulk, 0.05, 0.26 * bulk)), trim_mat,
		Vector3(0.0, hip_y + 0.16, 0.0), "Belt")

	# Shoulders: the comic block that carries the silhouette.
	_part(rig, _box(Vector3(0.5 * bulk, 0.1, 0.26 * bulk)), coat_mat,
		Vector3(0.0, shoulder_y, 0.0), "Shoulders")
	if bulk > 1.1:
		for side in [-1.0, 1.0]:
			_part(rig, _sphere(0.09 * bulk), coat_mat,
				Vector3(side * 0.26 * bulk, shoulder_y + 0.05, 0.0), "Pad" + _s(side))

	# Arms: sleeves angled a few degrees out, hands as mitts.
	for side in [-1.0, 1.0]:
		var arm := _cyl(0.055 * bulk, 0.045 * bulk, shoulder_y - hip_y)
		var part := _part(rig, arm, coat_mat,
			Vector3(side * 0.27 * bulk, (shoulder_y + hip_y) * 0.5 + 0.04, 0.0), "Arm" + _s(side))
		part.rotation.z = side * 0.1
		_part(rig, _box(Vector3(0.09, 0.11, 0.09)), skin_mat,
			Vector3(side * 0.31 * bulk, hip_y + 0.02, 0.0), "Hand" + _s(side))

	# Coat geometry per archetype — this is most of the read.
	match String(features["coat"]):
		"long":
			var skirt := _cyl_open(0.24 * bulk, 0.36 * bulk, hip_y * 0.9)
			_part(rig, skirt, coat_mat, Vector3(0.0, hip_y * 0.52, 0.0), "CoatSkirt")
		"robe":
			var robe := _cyl_open(0.26 * bulk, 0.4 * bulk, hip_y * 1.15)
			_part(rig, robe, coat_mat, Vector3(0.0, hip_y * 0.5, 0.0), "Robe")
			_part(rig, _box(Vector3(0.44 * bulk, 0.06, 0.28 * bulk)), trim_mat,
				Vector3(0.0, hip_y * 0.98, 0.0), "RobeTrim")
		"apron":
			_part(rig, _box(Vector3(0.34 * bulk, hip_y * 0.72, 0.04)), trim_mat,
				Vector3(0.0, hip_y * 0.62, -0.14 * bulk), "Apron")
		"short":
			_part(rig, _box(Vector3(0.44 * bulk, 0.14, 0.28 * bulk)), coat_mat,
				Vector3(0.0, hip_y - 0.02, 0.0), "JacketHem")

	# High collar for the noir silhouettes.
	if features["collar"]:
		_part(rig, _box(Vector3(0.34 * bulk, 0.16, 0.08)), coat_mat,
			Vector3(0.0, shoulder_y + 0.12, 0.12 * bulk), "Collar")

	# Head: oversized sphere on a short neck.
	_part(rig, _cyl(0.05, 0.06, 0.1), skin_mat, Vector3(0.0, shoulder_y + 0.1, 0.0), "Neck")
	var head := _part(rig, _sphere(height * 0.085), skin_mat, Vector3(0.0, head_y, 0.0), "Head")

	# Eye-slits: the noir face. A visor band or a pair of glow slots.
	if features["eyes"] == "visor":
		_part(head, _box(Vector3(height * 0.13, 0.035, 0.02)), eye_mat,
			Vector3(0.0, 0.02, -height * 0.078), "Visor")
	else:
		for side in [-1.0, 1.0]:
			_part(head, _box(Vector3(0.055, 0.03, 0.02)), eye_mat,
				Vector3(side * height * 0.038, 0.02, -height * 0.075), "Eye" + _s(side))

	# Headwear.
	match String(features["hat"]):
		"brim":
			_part(head, _cyl(height * 0.17, height * 0.17, 0.025), hat_mat,
				Vector3(0.0, height * 0.06, 0.0), "HatBrim")
			_part(head, _cyl(height * 0.09, height * 0.11, 0.12), hat_mat,
				Vector3(0.0, height * 0.12, 0.0), "HatTop")
		"cap":
			_part(head, _cyl(height * 0.1, height * 0.12, 0.07), hat_mat,
				Vector3(0.0, height * 0.075, 0.0), "Cap")
			_part(head, _box(Vector3(height * 0.12, 0.02, 0.09)), hat_mat,
				Vector3(0.0, height * 0.05, -height * 0.1), "CapBrim")
		"peaked":
			_part(head, _cyl(height * 0.11, height * 0.13, 0.08), hat_mat,
				Vector3(0.0, height * 0.075, 0.0), "Cap")
			_part(head, _box(Vector3(height * 0.14, 0.02, 0.1)), trim_mat,
				Vector3(0.0, height * 0.045, -height * 0.1), "CapBrim")
		"hood":
			_part(head, _cyl(0.02, height * 0.13, height * 0.14), hat_mat,
				Vector3(0.0, height * 0.05, height * 0.02), "Hood")
		"hoodie":
			_part(head, _cyl(height * 0.12, height * 0.13, 0.09), coat_mat,
				Vector3(0.0, height * 0.06, height * 0.03), "Hood")

	# Extras.
	if features["bag"]:
		_part(rig, _box(Vector3(0.3 * bulk, 0.24, 0.12)), trim_mat,
			Vector3(0.0, hip_y + 0.3, 0.19 * bulk), "Bag")
	if features["pendant"]:
		_part(rig, _box(Vector3(0.09, 0.12, 0.03)), glow_mat,
			Vector3(0.0, shoulder_y - 0.14, -0.14 * bulk), "Pendant")

	return rig


## Breathing and idle sway. Cheap: two sine terms on the rig root, applied by
## shells and Vex so figures never statue.
static func apply_idle(rig: Node3D, time: float, intensity: float = 1.0) -> void:
	if rig == null:
		return
	rig.scale.y = 1.0 + sin(time * 1.35) * 0.012 * intensity
	rig.rotation.z = sin(time * 0.6) * 0.008 * intensity


## How each archetype occupies its patch of street. Keyed by rig archetype so a
## persona gets believable motion from the silhouette it already declares — no
## per-character authoring, no new fields on PersonaProfile.
##
##   shift   — stays put, shuffles weight, takes the odd half-step (stallholders)
##   circuit — slow closed loop, long pauses to address nobody in particular
##   circle  — quick orbit with frequent reversals (kids, restlessness)
##   patrol  — paces a line and turns at each end (habit, not duty)
const GAITS := {
	&"fixer": {"kind": &"shift", "radius": 0.35, "speed": 0.40, "hold": Vector2(4.0, 8.0)},
	&"vendor": {"kind": &"shift", "radius": 0.55, "speed": 0.45, "hold": Vector2(3.0, 6.5)},
	&"preacher": {"kind": &"circuit", "radius": 1.5, "speed": 0.55, "hold": Vector2(2.5, 5.0)},
	&"urchin": {"kind": &"circle", "radius": 2.1, "speed": 1.30, "hold": Vector2(0.4, 1.4)},
	&"warden": {"kind": &"patrol", "radius": 3.2, "speed": 0.80, "hold": Vector2(2.0, 4.0)},
	&"courier": {"kind": &"shift", "radius": 0.6, "speed": 0.60, "hold": Vector2(2.0, 5.0)},
}


static func gait_for(archetype: StringName) -> Dictionary:
	return GAITS.get(archetype, GAITS[&"fixer"])


## Walk cycle layered on top of apply_idle: limbs contra-swing, boots roll with
## the leg they belong to, and the whole rig bobs on the step.
##
## `amount` is 0 standing and 1 at full stride. Callers ease it rather than
## snapping, otherwise a shell that stops mid-step freezes with one leg out.
## Only rotation.x is written, so the build-time arm splay on rotation.z and the
## breathe on rig.scale.y / rig.rotation.z both survive untouched.
static func apply_gait(rig: Node3D, phase: float, amount: float) -> void:
	if rig == null:
		return
	var swing := sin(phase) * 0.40 * amount
	for part_name: String in ["LegL", "BootL", "ArmR"]:
		var node := rig.get_node_or_null(part_name) as Node3D
		if node != null:
			node.rotation.x = swing
	for part_name: String in ["LegR", "BootR", "ArmL"]:
		var node := rig.get_node_or_null(part_name) as Node3D
		if node != null:
			node.rotation.x = -swing
	# Twice the stride frequency: the body rises on each footfall, not each cycle.
	rig.position.y = absf(sin(phase)) * 0.035 * amount


## Yaw that faces `target` from `from`, for turn-to-face behaviour.
static func yaw_toward(from: Vector3, target: Vector3) -> float:
	var d := target - from
	d.y = 0.0
	if d.length_squared() < 0.001:
		return 0.0
	return atan2(d.x, d.z)


static func _toon(color: Color, rim: Color, roughness: float) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = TOON
	mat.next_pass = INK
	mat.set_shader_parameter("albedo_color", color)
	mat.set_shader_parameter("roughness", roughness)
	mat.set_shader_parameter("rim_color", rim)
	mat.set_shader_parameter("rim_strength", 0.75)
	mat.set_shader_parameter("rim_light_bias", 0.55)
	mat.set_shader_parameter("shadow_tint_strength", 0.6)
	mat.set_shader_parameter("light_ramp", LIGHT_RAMP)
	mat.set_shader_parameter("use_light_ramp", true)
	return mat


static func _neon(color: Color, energy: float) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = NEON
	mat.set_shader_parameter("neon_color", color)
	mat.set_shader_parameter("energy", energy)
	mat.set_shader_parameter("flicker_amount", 0.04)
	mat.set_shader_parameter("dropout_chance", 0.0)
	return mat


static func _cyl(top_r: float, bottom_r: float, height: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top_r
	mesh.bottom_radius = bottom_r
	mesh.height = height
	mesh.radial_segments = 10
	return mesh


static func _cyl_open(top_r: float, bottom_r: float, height: float) -> CylinderMesh:
	var mesh := _cyl(top_r, bottom_r, height)
	mesh.cap_top = false
	mesh.cap_bottom = false
	return mesh


static func _box(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh


static func _sphere(radius: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 12
	mesh.rings = 8
	return mesh


static func _part(
	parent: Node, mesh: Mesh, mat: Material, pos: Vector3, part_name: String
) -> MeshInstance3D:
	var inst := MeshInstance3D.new()
	inst.name = part_name
	inst.mesh = mesh
	inst.material_override = mat
	inst.position = pos
	parent.add_child(inst)
	return inst


static func _s(side: float) -> String:
	return "L" if side < 0.0 else "R"
