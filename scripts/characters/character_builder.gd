class_name CharacterBuilder
extends RefCounted
## Procedural comic characters. No model files, no textures: every figure is
## assembled from primitives with exaggerated comic proportions (oversized
## head, blocked coat silhouette, glowing eye-slits) and finished with the
## shared toon shader plus an ink outline pass.
##
## Archetypes change geometry, not just palette — a preacher reads as a
## preacher from across the plaza in silhouette, which is the whole job at
## blockout fidelity. Detail lives in silhouette breaks (joints, cuffs,
## face planes, coat flaps) and soft skin/cloth tonal flecks — not in
## photographic albedo.

const TOON := preload("res://shaders/toon_cel.gdshader")
const NEON := preload("res://shaders/neon_sign.gdshader")
const INK := preload("res://assets/materials/outline_ink.tres")
## Authored 3-band light ramp. Characters get the ramp rather than the numeric
## banding so the shadow end can drift cold violet and the lit end warm — a hue
## shift across the terminator that a band count cannot express.
const LIGHT_RAMP := preload("res://assets/materials/ramps/ramp_character.tres")
const SKIN_RAMP := preload("res://assets/materials/ramps/ramp_skin.tres")

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
## Coat albedos stay desaturated but not crushed — too-dark coats erase
## silhouette breaks (pockets, flaps, cuffs) under neon bloom.
const PALETTES := {
	&"fixer": [Color(0.16, 0.17, 0.22), Color(1.0, 0.176, 0.584), Color(0.82, 0.66, 0.74), Color(1.0, 0.176, 0.584)],
	&"vendor": [Color(0.28, 0.18, 0.12), Color(1.0, 0.68, 0.36), Color(0.88, 0.72, 0.58), Color(1.0, 0.68, 0.36)],
	&"preacher": [Color(0.12, 0.12, 0.16), Color(0.969, 1.0, 0.235), Color(0.72, 0.62, 0.74), Color(0.969, 1.0, 0.235)],
	&"urchin": [Color(0.16, 0.18, 0.24), Color(0.0, 0.898, 1.0), Color(0.8, 0.62, 0.52), Color(0.0, 0.898, 1.0)],
	&"warden": [Color(0.2, 0.19, 0.15), Color(0.56, 0.66, 0.78), Color(0.74, 0.62, 0.56), Color(0.56, 0.66, 0.78)],
	&"courier": [Color(0.14, 0.18, 0.24), Color(0.0, 0.898, 1.0), Color(0.8, 0.66, 0.76), Color(0.0, 0.898, 1.0)],
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
	var is_player := archetype == &"courier"

	var coat_mat := _cloth(palette[0], palette[1], 0.86, is_player, 0.06)
	var trim_mat := _cloth(palette[0].darkened(0.25), palette[1], 0.8, is_player, 0.04)
	var skin_mat := _skin(palette[2], palette[1], is_player)
	var hat_mat := _cloth(palette[0].darkened(0.35), palette[1], 0.88, is_player, 0.03)
	var leather_mat := _cloth(palette[0].darkened(0.15).lerp(Color(0.22, 0.12, 0.09), 0.4), palette[1], 0.72, is_player, 0.04)
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
	var head_r := height * 0.085

	_build_legs(rig, coat_mat, leather_mat, hip_y, half_w, bulk)
	_build_torso(rig, coat_mat, trim_mat, glow_mat, hip_y, shoulder_y, bulk, features, is_player)
	_build_arms(rig, coat_mat, trim_mat, skin_mat, hip_y, shoulder_y, bulk)
	_build_coat(rig, coat_mat, trim_mat, hip_y, bulk, features)
	_build_head(rig, skin_mat, hat_mat, coat_mat, trim_mat, eye_mat, glow_mat,
		height, head_y, shoulder_y, head_r, features, is_player)
	_build_extras(rig, trim_mat, glow_mat, leather_mat, hip_y, shoulder_y, bulk, features, is_player)

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


## Walk cycle layered on top of apply_idle: limbs contra-swing from hip and
## shoulder pivots, and the whole rig bobs on the step.
##
## `amount` is 0 standing and 1 at full stride. Callers ease it rather than
## snapping, otherwise a shell that stops mid-step freezes with one leg out.
## Only rotation.x is written, so the build-time arm splay on rotation.z and the
## breathe on rig.scale.y / rig.rotation.z both survive untouched.
static func apply_gait(rig: Node3D, phase: float, amount: float) -> void:
	if rig == null:
		return
	var swing := sin(phase) * 0.40 * amount
	for part_name: String in ["LegL", "ArmR"]:
		var node := rig.get_node_or_null(part_name) as Node3D
		if node != null:
			node.rotation.x = swing
	for part_name: String in ["LegR", "ArmL"]:
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


static func _build_legs(
	rig: Node3D, coat_mat: Material, leather_mat: Material,
	hip_y: float, half_w: float, bulk: float
) -> void:
	var thigh_h := hip_y * 0.48
	var shin_h := hip_y * 0.38
	for side in [-1.0, 1.0]:
		var leg := Node3D.new()
		leg.name = "Leg" + _s(side)
		leg.position = Vector3(side * half_w, hip_y, 0.0)
		rig.add_child(leg)

		_part(leg, _cyl(0.082 * bulk, 0.068 * bulk, thigh_h), coat_mat,
			Vector3(0.0, -thigh_h * 0.5, 0.0), "Thigh")
		_part(leg, _sphere(0.055 * bulk), coat_mat,
			Vector3(0.0, -thigh_h, 0.0), "Knee")
		_part(leg, _cyl(0.062 * bulk, 0.052 * bulk, shin_h), coat_mat,
			Vector3(0.0, -thigh_h - shin_h * 0.5, 0.0), "Shin")
		# Boot shaft + toe — silhouette break at the ankle.
		_part(leg, _cyl(0.068 * bulk, 0.078 * bulk, 0.16), leather_mat,
			Vector3(0.0, -hip_y + 0.16, 0.01), "BootShaft")
		_part(leg, _box(Vector3(0.15 * bulk, 0.075, 0.27)), leather_mat,
			Vector3(0.0, -hip_y + 0.038, -0.035), "Boot")
		_part(leg, _box(Vector3(0.12 * bulk, 0.04, 0.08)), leather_mat,
			Vector3(0.0, -hip_y + 0.055, -0.14), "BootToe")


static func _build_torso(
	rig: Node3D, coat_mat: Material, trim_mat: Material, glow_mat: Material,
	hip_y: float, shoulder_y: float, bulk: float, features: Dictionary, is_player: bool
) -> void:
	_part(rig, _box(Vector3(0.32 * bulk, 0.16, 0.22 * bulk)), coat_mat,
		Vector3(0.0, hip_y + 0.06, 0.0), "Hips")
	_part(rig, _box(Vector3(0.4 * bulk, shoulder_y - hip_y - 0.06, 0.24 * bulk)), coat_mat,
		Vector3(0.0, (hip_y + shoulder_y) * 0.5 + 0.02, 0.0), "Torso")
	# Chest panel / zipper channel — a hard vertical break the cel shader loves.
	_part(rig, _box(Vector3(0.06 * bulk, shoulder_y - hip_y - 0.14, 0.02)), trim_mat,
		Vector3(0.0, (hip_y + shoulder_y) * 0.5 + 0.04, -0.125 * bulk), "Zipper")
	if is_player:
		_part(rig, _box(Vector3(0.02, shoulder_y - hip_y - 0.22, 0.015)), glow_mat,
			Vector3(0.0, (hip_y + shoulder_y) * 0.5 + 0.06, -0.135 * bulk), "ZipGlow")

	_part(rig, _box(Vector3(0.42 * bulk, 0.05, 0.26 * bulk)), trim_mat,
		Vector3(0.0, hip_y + 0.16, 0.0), "Belt")
	_part(rig, _box(Vector3(0.08, 0.07, 0.04)), glow_mat if is_player else trim_mat,
		Vector3(0.0, hip_y + 0.16, -0.14 * bulk), "BeltBuckle")

	_part(rig, _box(Vector3(0.52 * bulk, 0.11, 0.28 * bulk)), coat_mat,
		Vector3(0.0, shoulder_y, 0.0), "Shoulders")
	if bulk > 1.05:
		for side in [-1.0, 1.0]:
			_part(rig, _sphere(0.09 * bulk), coat_mat,
				Vector3(side * 0.26 * bulk, shoulder_y + 0.05, 0.0), "Pad" + _s(side))

	# Pockets — small silhouette nubs on the coat front.
	for side in [-1.0, 1.0]:
		_part(rig, _box(Vector3(0.1 * bulk, 0.09, 0.03)), trim_mat,
			Vector3(side * 0.14 * bulk, hip_y + 0.28, -0.13 * bulk), "Pocket" + _s(side))

	if features["collar"]:
		# Split collar flaps read better than a single brick.
		for side in [-1.0, 1.0]:
			var flap := _part(rig, _box(Vector3(0.14 * bulk, 0.17, 0.06)), coat_mat,
				Vector3(side * 0.1 * bulk, shoulder_y + 0.13, 0.1 * bulk), "Collar" + _s(side))
			flap.rotation.y = side * -0.35
			flap.rotation.x = -0.2


static func _build_arms(
	rig: Node3D, coat_mat: Material, trim_mat: Material, skin_mat: Material,
	hip_y: float, shoulder_y: float, bulk: float
) -> void:
	var arm_len := shoulder_y - hip_y
	var upper_h := arm_len * 0.48
	var lower_h := arm_len * 0.42
	for side in [-1.0, 1.0]:
		var arm := Node3D.new()
		arm.name = "Arm" + _s(side)
		arm.position = Vector3(side * 0.28 * bulk, shoulder_y - 0.02, 0.0)
		arm.rotation.z = side * 0.12
		rig.add_child(arm)

		_part(arm, _sphere(0.06 * bulk), coat_mat, Vector3.ZERO, "ShoulderJoint")
		_part(arm, _cyl(0.058 * bulk, 0.05 * bulk, upper_h), coat_mat,
			Vector3(0.0, -upper_h * 0.5, 0.0), "Upper")
		_part(arm, _sphere(0.045 * bulk), coat_mat,
			Vector3(0.0, -upper_h, 0.0), "Elbow")
		_part(arm, _cyl(0.048 * bulk, 0.042 * bulk, lower_h), coat_mat,
			Vector3(0.0, -upper_h - lower_h * 0.5, 0.0), "Forearm")
		_part(arm, _cyl(0.05 * bulk, 0.048 * bulk, 0.06), trim_mat,
			Vector3(0.0, -upper_h - lower_h + 0.01, 0.0), "Cuff")

		var hand := _part(arm, _box(Vector3(0.085, 0.1, 0.075)), skin_mat,
			Vector3(0.0, -upper_h - lower_h - 0.065, 0.0), "Hand")
		# Three finger stubs — enough to stop the mitt reading as a brick.
		for f in range(3):
			_part(hand, _box(Vector3(0.02, 0.045, 0.02)), skin_mat,
				Vector3((float(f) - 1.0) * 0.026, -0.068, -0.01), "Finger%d" % f)
		_part(hand, _box(Vector3(0.022, 0.04, 0.022)), skin_mat,
			Vector3(side * -0.04, -0.02, 0.01), "Thumb")


static func _build_coat(
	rig: Node3D, coat_mat: Material, trim_mat: Material,
	hip_y: float, bulk: float, features: Dictionary
) -> void:
	match String(features["coat"]):
		"long":
			var skirt := _cyl_open(0.24 * bulk, 0.36 * bulk, hip_y * 0.9)
			_part(rig, skirt, coat_mat, Vector3(0.0, hip_y * 0.52, 0.0), "CoatSkirt")
			# Open flaps so the long coat breaks silhouette when the figure turns.
			for side in [-1.0, 1.0]:
				var flap := _part(rig, _box(Vector3(0.14 * bulk, hip_y * 0.72, 0.04)), coat_mat,
					Vector3(side * 0.16 * bulk, hip_y * 0.45, -0.12 * bulk), "CoatFlap" + _s(side))
				flap.rotation.y = side * 0.25
		"robe":
			var robe := _cyl_open(0.26 * bulk, 0.4 * bulk, hip_y * 1.15)
			_part(rig, robe, coat_mat, Vector3(0.0, hip_y * 0.5, 0.0), "Robe")
			_part(rig, _box(Vector3(0.44 * bulk, 0.06, 0.28 * bulk)), trim_mat,
				Vector3(0.0, hip_y * 0.98, 0.0), "RobeTrim")
			_part(rig, _box(Vector3(0.08 * bulk, hip_y * 0.9, 0.03)), trim_mat,
				Vector3(0.0, hip_y * 0.5, -0.18 * bulk), "RobeSash")
		"apron":
			_part(rig, _box(Vector3(0.34 * bulk, hip_y * 0.72, 0.04)), trim_mat,
				Vector3(0.0, hip_y * 0.62, -0.14 * bulk), "Apron")
			_part(rig, _box(Vector3(0.36 * bulk, 0.05, 0.05)), trim_mat,
				Vector3(0.0, hip_y * 0.95, -0.12 * bulk), "ApronBib")
		"short":
			_part(rig, _box(Vector3(0.44 * bulk, 0.14, 0.28 * bulk)), coat_mat,
				Vector3(0.0, hip_y - 0.02, 0.0), "JacketHem")
			for side in [-1.0, 1.0]:
				_part(rig, _box(Vector3(0.12 * bulk, 0.16, 0.05)), coat_mat,
					Vector3(side * 0.14 * bulk, hip_y + 0.02, -0.12 * bulk), "HemFlap" + _s(side))


static func _build_head(
	rig: Node3D, skin_mat: Material, hat_mat: Material, coat_mat: Material,
	trim_mat: Material, eye_mat: Material, glow_mat: Material,
	height: float, head_y: float, shoulder_y: float, head_r: float,
	features: Dictionary, is_player: bool
) -> void:
	_part(rig, _cyl(0.05, 0.055, 0.11), skin_mat, Vector3(0.0, shoulder_y + 0.1, 0.0), "Neck")
	var head := _part(rig, _sphere(head_r), skin_mat, Vector3(0.0, head_y, 0.0), "Head")

	# Face planes — jaw / nose / brows / ears so a head is not just a ball.
	_part(head, _sphere(head_r * 0.42), skin_mat,
		Vector3(0.0, -head_r * 0.42, -head_r * 0.15), "Jaw")
	_part(head, _box(Vector3(head_r * 0.22, head_r * 0.28, head_r * 0.22)), skin_mat,
		Vector3(0.0, -head_r * 0.05, -head_r * 0.92), "Nose")
	_part(head, _box(Vector3(head_r * 1.05, head_r * 0.1, head_r * 0.12)), hat_mat,
		Vector3(0.0, head_r * 0.28, -head_r * 0.7), "Brow")
	# Mouth slit — a hard comic cut, not lips.
	_part(head, _box(Vector3(head_r * 0.35, head_r * 0.06, head_r * 0.08)), hat_mat,
		Vector3(0.0, -head_r * 0.35, -head_r * 0.78), "Mouth")
	for side in [-1.0, 1.0]:
		_part(head, _sphere(head_r * 0.28), skin_mat,
			Vector3(side * head_r * 0.55, -head_r * 0.05, -head_r * 0.25), "Cheek" + _s(side))
		var ear := _part(head, _box(Vector3(head_r * 0.18, head_r * 0.35, head_r * 0.2)), skin_mat,
			Vector3(side * head_r * 0.95, 0.0, 0.0), "Ear" + _s(side))
		ear.rotation.z = side * 0.15
		# Hair / sideburn wedges so the skull isn't a bare ball under the hat.
		_part(head, _box(Vector3(head_r * 0.22, head_r * 0.4, head_r * 0.35)), hat_mat,
			Vector3(side * head_r * 0.7, head_r * 0.15, head_r * 0.15), "Sideburn" + _s(side))

	if features["eyes"] == "visor":
		_part(head, _box(Vector3(height * 0.14, 0.04, 0.025)), eye_mat,
			Vector3(0.0, 0.015, -height * 0.078), "Visor")
		_part(head, _box(Vector3(height * 0.15, 0.012, 0.018)), trim_mat,
			Vector3(0.0, 0.04, -height * 0.072), "VisorFrame")
	else:
		for side in [-1.0, 1.0]:
			_part(head, _box(Vector3(0.055, 0.032, 0.022)), eye_mat,
				Vector3(side * height * 0.038, 0.02, -height * 0.075), "Eye" + _s(side))
			_part(head, _box(Vector3(0.06, 0.012, 0.015)), hat_mat,
				Vector3(side * height * 0.038, 0.042, -height * 0.07), "Lid" + _s(side))

	if is_player:
		# Comms bud — player silhouette cue from behind.
		_part(head, _box(Vector3(0.035, 0.045, 0.03)), trim_mat,
			Vector3(head_r * 0.95, -head_r * 0.1, head_r * 0.15), "Earpiece")
		_part(head, _sphere(0.018), glow_mat,
			Vector3(head_r * 0.95, -head_r * 0.1, head_r * 0.18), "EarpieceGlow")

	match String(features["hat"]):
		"brim":
			_part(head, _cyl(height * 0.17, height * 0.17, 0.025), hat_mat,
				Vector3(0.0, height * 0.06, 0.0), "HatBrim")
			_part(head, _cyl(height * 0.09, height * 0.11, 0.12), hat_mat,
				Vector3(0.0, height * 0.12, 0.0), "HatTop")
			_part(head, _box(Vector3(height * 0.04, 0.03, height * 0.08)), trim_mat,
				Vector3(0.0, height * 0.055, -height * 0.12), "HatBand")
		"cap":
			_part(head, _cyl(height * 0.1, height * 0.12, 0.07), hat_mat,
				Vector3(0.0, height * 0.075, 0.0), "Cap")
			_part(head, _box(Vector3(height * 0.12, 0.02, 0.09)), hat_mat,
				Vector3(0.0, height * 0.05, -height * 0.1), "CapBrim")
			if is_player:
				_part(head, _box(Vector3(height * 0.05, 0.015, 0.04)), glow_mat,
					Vector3(0.0, height * 0.09, -height * 0.02), "CapBadge")
		"peaked":
			_part(head, _cyl(height * 0.11, height * 0.13, 0.08), hat_mat,
				Vector3(0.0, height * 0.075, 0.0), "Cap")
			_part(head, _box(Vector3(height * 0.14, 0.02, 0.1)), trim_mat,
				Vector3(0.0, height * 0.045, -height * 0.1), "CapBrim")
			_part(head, _box(Vector3(height * 0.05, 0.025, 0.03)), trim_mat,
				Vector3(0.0, height * 0.1, -height * 0.05), "CapBadge")
		"hood":
			_part(head, _cyl(0.02, height * 0.13, height * 0.14), hat_mat,
				Vector3(0.0, height * 0.05, height * 0.02), "Hood")
			_part(head, _box(Vector3(height * 0.18, height * 0.08, height * 0.06)), hat_mat,
				Vector3(0.0, height * 0.02, -height * 0.08), "HoodCowl")
		"hoodie":
			_part(head, _cyl(height * 0.12, height * 0.13, 0.09), coat_mat,
				Vector3(0.0, height * 0.06, height * 0.03), "Hood")
			_part(head, _box(Vector3(height * 0.16, height * 0.06, height * 0.05)), coat_mat,
				Vector3(0.0, height * 0.01, -height * 0.07), "HoodCowl")


static func _build_extras(
	rig: Node3D, trim_mat: Material, glow_mat: Material, leather_mat: Material,
	hip_y: float, shoulder_y: float, bulk: float, features: Dictionary, is_player: bool
) -> void:
	if features["bag"]:
		_part(rig, _box(Vector3(0.3 * bulk, 0.24, 0.12)), leather_mat,
			Vector3(0.0, hip_y + 0.3, 0.19 * bulk), "Bag")
		_part(rig, _box(Vector3(0.08, 0.32, 0.03)), trim_mat,
			Vector3(0.12 * bulk, hip_y + 0.42, 0.12 * bulk), "BagStrap")
		if is_player:
			# Transit-pass pouch — the courier's one job, worn on the hip.
			_part(rig, _box(Vector3(0.12, 0.1, 0.05)), trim_mat,
				Vector3(0.2 * bulk, hip_y + 0.18, -0.05), "PassPouch")
			_part(rig, _box(Vector3(0.08, 0.04, 0.02)), glow_mat,
				Vector3(0.2 * bulk, hip_y + 0.2, -0.08), "PassGlow")
	if features["pendant"]:
		_part(rig, _box(Vector3(0.09, 0.12, 0.03)), glow_mat,
			Vector3(0.0, shoulder_y - 0.14, -0.14 * bulk), "Pendant")
		_part(rig, _cyl(0.008, 0.008, 0.16), trim_mat,
			Vector3(0.0, shoulder_y - 0.02, -0.08 * bulk), "PendantChain")


static func _skin(color: Color, rim: Color, is_player: bool) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = TOON
	mat.next_pass = INK
	mat.set_shader_parameter("albedo_color", color)
	mat.set_shader_parameter("roughness", 0.82)
	mat.set_shader_parameter("rim_color", rim)
	# Flesh wraps light further around the terminator than cloth — keeps cheeks
	# readable in alleys instead of going black at the jaw.
	mat.set_shader_parameter("shadow_wrap", 0.58)
	mat.set_shader_parameter("shadow_tint_strength", 0.42)
	mat.set_shader_parameter("spec_strength", 0.22)
	mat.set_shader_parameter("spec_threshold", 0.74)
	mat.set_shader_parameter("spec_softness", 0.04)
	mat.set_shader_parameter("rim_strength", 1.35 if is_player else 0.7)
	mat.set_shader_parameter("rim_power", 2.6)
	mat.set_shader_parameter("rim_light_bias", 0.08 if is_player else 0.4)
	mat.set_shader_parameter("light_ramp", SKIN_RAMP)
	mat.set_shader_parameter("use_light_ramp", true)
	mat.set_shader_parameter("detail_strength", 0.28 if is_player else 0.22)
	mat.set_shader_parameter("detail_scale", 16.0)
	mat.set_shader_parameter("detail_contrast", 0.65)
	return mat


static func _cloth(
	color: Color, rim: Color, roughness: float, is_player: bool, grime: float
) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = TOON
	mat.next_pass = INK
	mat.set_shader_parameter("albedo_color", color)
	mat.set_shader_parameter("roughness", roughness)
	mat.set_shader_parameter("rim_color", rim)
	mat.set_shader_parameter("rim_strength", 1.55 if is_player else 0.95)
	mat.set_shader_parameter("rim_light_bias", 0.1 if is_player else 0.45)
	mat.set_shader_parameter("shadow_tint_strength", 0.55)
	mat.set_shader_parameter("shadow_wrap", 0.34)
	mat.set_shader_parameter("spec_strength", 0.45)
	mat.set_shader_parameter("light_ramp", LIGHT_RAMP)
	mat.set_shader_parameter("use_light_ramp", true)
	mat.set_shader_parameter("detail_strength", 0.16)
	mat.set_shader_parameter("detail_scale", 7.0)
	mat.set_shader_parameter("detail_contrast", 0.55)
	# Flat white default sampler would otherwise dirt-wash the whole coat.
	mat.set_shader_parameter("grime_strength", minf(grime, 0.08))
	mat.set_shader_parameter("grime_up_bias", 0.55)
	return mat


static func _toon(color: Color, rim: Color, roughness: float) -> ShaderMaterial:
	# Kept for any external callers that still expect the generic helper.
	return _cloth(color, rim, roughness, false, 0.0)


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
	mesh.radial_segments = 16
	return mesh


static func _cyl_open(top_r: float, bottom_r: float, height: float) -> CylinderMesh:
	var mesh := _cyl(top_r, bottom_r, height)
	mesh.cap_top = false
	mesh.cap_bottom = false
	return mesh


static func _box(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	# Soft bevel via subdivision keeps inverted-hull ink from tearing at edges.
	mesh.subdivide_width = 1
	mesh.subdivide_height = 1
	mesh.subdivide_depth = 1
	return mesh


static func _sphere(radius: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 18
	mesh.rings = 12
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
