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
##
## Limb pivots are Node3D parents (LegL/ArmL/…) so gait rotates a whole limb;
## boots and hands ride as children. Skin uses a softer wrap + world-space
## mottling so faces and hands read as flesh rather than plastic spheres.

const TOON := preload("res://shaders/toon_cel.gdshader")
const NEON := preload("res://shaders/neon_sign.gdshader")
const INK := preload("res://assets/materials/outline_ink.tres")
## Authored 3-band light ramp. Characters get the ramp rather than the numeric
## banding so the shadow end can drift cold violet and the lit end warm — a hue
## shift across the terminator that a band count cannot express.
const LIGHT_RAMP := preload("res://assets/materials/ramps/ramp_character.tres")

## archetype -> feature flags the assembler reads
const FEATURES := {
	&"fixer": {"hat": "brim", "coat": "long", "collar": true, "eyes": "visor", "bag": false, "pendant": false, "cyber": true, "hair": "slick"},
	&"vendor": {"hat": "cap", "coat": "apron", "collar": false, "eyes": "pair", "bag": false, "pendant": false, "cyber": false, "hair": "tuft"},
	&"preacher": {"hat": "hood", "coat": "robe", "collar": false, "eyes": "pair", "bag": false, "pendant": true, "cyber": false, "hair": "none"},
	&"urchin": {"hat": "hoodie", "coat": "short", "collar": false, "eyes": "pair", "bag": true, "pendant": false, "cyber": false, "hair": "messy"},
	&"warden": {"hat": "peaked", "coat": "long", "collar": true, "eyes": "pair", "bag": false, "pendant": false, "cyber": true, "hair": "crop"},
	&"courier": {"hat": "cap", "coat": "short", "collar": true, "eyes": "visor", "bag": true, "pendant": false, "cyber": true, "hair": "bangs"},
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

	var coat_mat := _cloth(palette[0], palette[1], 0.88)
	var trim_mat := _cloth(palette[0].darkened(0.35), palette[1], 0.82)
	var leather_mat := _cloth(palette[0].darkened(0.55), palette[1], 0.7)
	var skin_mat := _skin(palette[2], palette[1])
	var jaw_mat := _skin(palette[2].darkened(0.08), palette[1])
	var hair_mat := _cloth(palette[0].darkened(0.65), palette[1], 0.9)
	var hat_mat := _cloth(palette[0].darkened(0.5), palette[1], 0.85)
	var eye_mat := _neon(palette[3], 1.9)
	var glow_mat := _neon(palette[1], 2.2)
	var mouth_mat := _cloth(Color(0.18, 0.08, 0.1), palette[1], 0.95)

	var rig := Node3D.new()
	rig.name = "Rig"
	rig.set_meta("height", height)
	rig.set_meta("archetype", archetype)

	# Comic proportions: legs ~42%, torso ~34%, head oversized.
	var hip_y := height * 0.46
	var shoulder_y := height * 0.76
	var head_y := height * 0.87
	var head_r := height * 0.085
	var half_w := 0.105 * bulk
	var thigh_len := hip_y * 0.48
	var shin_len := hip_y * 0.42
	var arm_len := shoulder_y - hip_y

	# Legs: articulated thigh / knee / shin / boot under a hip pivot.
	for side in [-1.0, 1.0]:
		var leg := Node3D.new()
		leg.name = "Leg" + _s(side)
		leg.position = Vector3(side * half_w, hip_y, 0.0)
		rig.add_child(leg)

		_part(leg, _cyl(0.078 * bulk, 0.068 * bulk, thigh_len), coat_mat,
			Vector3(0.0, -thigh_len * 0.5, 0.0), "Thigh")
		_part(leg, _sphere(0.055 * bulk), coat_mat,
			Vector3(0.0, -thigh_len, 0.0), "Knee")
		_part(leg, _cyl(0.062 * bulk, 0.05 * bulk, shin_len), coat_mat,
			Vector3(0.0, -(thigh_len + shin_len * 0.5), 0.0), "Shin")

		var boot := Node3D.new()
		boot.name = "Boot"
		boot.position = Vector3(0.0, -hip_y + 0.045, -0.02)
		leg.add_child(boot)
		_part(boot, _box(Vector3(0.15 * bulk, 0.08, 0.24)), leather_mat,
			Vector3(0.0, 0.0, 0.0), "BootBody")
		_part(boot, _box(Vector3(0.16 * bulk, 0.035, 0.27)), hat_mat,
			Vector3(0.0, -0.04, -0.02), "BootSole")
		_part(boot, _cyl(0.07 * bulk, 0.065 * bulk, 0.1), leather_mat,
			Vector3(0.0, 0.07, 0.02), "BootCuff")

	# Hips and layered torso: chest plate + underlayer for silhouette depth.
	_part(rig, _box(Vector3(0.32 * bulk, 0.16, 0.22 * bulk)), coat_mat,
		Vector3(0.0, hip_y + 0.06, 0.0), "Hips")
	_part(rig, _box(Vector3(0.38 * bulk, shoulder_y - hip_y - 0.1, 0.22 * bulk)), coat_mat,
		Vector3(0.0, (hip_y + shoulder_y) * 0.5 + 0.02, 0.0), "Torso")
	_part(rig, _box(Vector3(0.42 * bulk, (shoulder_y - hip_y) * 0.42, 0.26 * bulk)), coat_mat,
		Vector3(0.0, shoulder_y - (shoulder_y - hip_y) * 0.22, 0.01), "Chest")
	_part(rig, _box(Vector3(0.44 * bulk, 0.05, 0.27 * bulk)), trim_mat,
		Vector3(0.0, hip_y + 0.16, 0.0), "Belt")
	_part(rig, _box(Vector3(0.07, 0.08, 0.04)), glow_mat,
		Vector3(0.0, hip_y + 0.16, -0.14 * bulk), "BeltBuckle")
	# Side pockets and a centre seam — small silhouette marks that read at mid distance.
	for side in [-1.0, 1.0]:
		_part(rig, _box(Vector3(0.1 * bulk, 0.12, 0.04)), trim_mat,
			Vector3(side * 0.14 * bulk, hip_y + 0.28, -0.12 * bulk), "Pocket" + _s(side))
	_part(rig, _box(Vector3(0.03, shoulder_y - hip_y - 0.12, 0.02)), trim_mat,
		Vector3(0.0, (hip_y + shoulder_y) * 0.5 + 0.04, -0.125 * bulk), "Zipper")

	# Shoulders: the comic block that carries the silhouette.
	_part(rig, _box(Vector3(0.52 * bulk, 0.11, 0.28 * bulk)), coat_mat,
		Vector3(0.0, shoulder_y, 0.0), "Shoulders")
	for side in [-1.0, 1.0]:
		_part(rig, _sphere(0.08 * bulk), coat_mat,
			Vector3(side * 0.24 * bulk, shoulder_y + 0.02, 0.0), "Deltoid" + _s(side))
	if bulk > 1.1:
		for side in [-1.0, 1.0]:
			_part(rig, _sphere(0.1 * bulk), coat_mat,
				Vector3(side * 0.28 * bulk, shoulder_y + 0.05, 0.0), "Pad" + _s(side))

	# Arms: upper / elbow / forearm / cuff / mitt under a shoulder pivot.
	for side in [-1.0, 1.0]:
		var arm := Node3D.new()
		arm.name = "Arm" + _s(side)
		arm.position = Vector3(side * 0.28 * bulk, shoulder_y - 0.02, 0.0)
		arm.rotation.z = side * 0.12
		rig.add_child(arm)

		var upper_len := arm_len * 0.48
		var lower_len := arm_len * 0.42
		_part(arm, _cyl(0.058 * bulk, 0.05 * bulk, upper_len), coat_mat,
			Vector3(0.0, -upper_len * 0.5, 0.0), "UpperArm")
		_part(arm, _sphere(0.048 * bulk), coat_mat,
			Vector3(0.0, -upper_len, 0.0), "Elbow")
		_part(arm, _cyl(0.048 * bulk, 0.042 * bulk, lower_len), coat_mat,
			Vector3(0.0, -(upper_len + lower_len * 0.5), 0.0), "Forearm")
		_part(arm, _cyl(0.05 * bulk, 0.048 * bulk, 0.06), trim_mat,
			Vector3(0.0, -(upper_len + lower_len) + 0.02, 0.0), "Cuff")

		var hand := Node3D.new()
		hand.name = "Hand"
		hand.position = Vector3(0.0, -(upper_len + lower_len) - 0.04, 0.0)
		arm.add_child(hand)
		_part(hand, _box(Vector3(0.08, 0.09, 0.055)), skin_mat,
			Vector3(0.0, 0.0, 0.0), "Palm")
		for fi in range(3):
			var fx := (float(fi) - 1.0) * 0.028
			_part(hand, _box(Vector3(0.022, 0.055, 0.022)), skin_mat,
				Vector3(fx, -0.065, -0.01), "Finger%d" % fi)
		_part(hand, _box(Vector3(0.022, 0.04, 0.022)), skin_mat,
			Vector3(side * -0.04, -0.02, 0.01), "Thumb")

		if features["cyber"]:
			_part(arm, _box(Vector3(0.035, 0.08, 0.02)), glow_mat,
				Vector3(side * 0.04, -upper_len * 0.55, -0.04), "ForearmPort")

	# Coat geometry per archetype — this is most of the read.
	match String(features["coat"]):
		"long":
			var skirt := _cyl_open(0.24 * bulk, 0.38 * bulk, hip_y * 0.92)
			_part(rig, skirt, coat_mat, Vector3(0.0, hip_y * 0.52, 0.0), "CoatSkirt")
			for side in [-1.0, 1.0]:
				_part(rig, _box(Vector3(0.1 * bulk, hip_y * 0.55, 0.06)), coat_mat,
					Vector3(side * 0.16 * bulk, hip_y * 0.45, -0.08), "CoatFlap" + _s(side))
			_part(rig, _box(Vector3(0.18 * bulk, 0.22, 0.05)), trim_mat,
				Vector3(0.0, shoulder_y - 0.12, -0.13 * bulk), "Lapels")
		"robe":
			var robe := _cyl_open(0.26 * bulk, 0.42 * bulk, hip_y * 1.15)
			_part(rig, robe, coat_mat, Vector3(0.0, hip_y * 0.5, 0.0), "Robe")
			_part(rig, _box(Vector3(0.46 * bulk, 0.06, 0.3 * bulk)), trim_mat,
				Vector3(0.0, hip_y * 0.98, 0.0), "RobeTrim")
			_part(rig, _box(Vector3(0.08, hip_y * 0.7, 0.04)), trim_mat,
				Vector3(0.0, hip_y * 0.55, -0.16 * bulk), "RobeSash")
		"apron":
			_part(rig, _box(Vector3(0.36 * bulk, hip_y * 0.72, 0.04)), trim_mat,
				Vector3(0.0, hip_y * 0.62, -0.14 * bulk), "Apron")
			_part(rig, _box(Vector3(0.04, hip_y * 0.35, 0.03)), leather_mat,
				Vector3(-0.1 * bulk, shoulder_y - 0.1, -0.08), "ApronStrap")
			_part(rig, _box(Vector3(0.12 * bulk, 0.1, 0.05)), leather_mat,
				Vector3(0.12 * bulk, hip_y * 0.55, -0.16 * bulk), "ApronPocket")
		"short":
			_part(rig, _box(Vector3(0.46 * bulk, 0.16, 0.3 * bulk)), coat_mat,
				Vector3(0.0, hip_y - 0.02, 0.0), "JacketHem")
			for side in [-1.0, 1.0]:
				_part(rig, _box(Vector3(0.08 * bulk, 0.2, 0.05)), coat_mat,
					Vector3(side * 0.18 * bulk, hip_y + 0.05, -0.12 * bulk), "HemFlap" + _s(side))
			_part(rig, _box(Vector3(0.16 * bulk, 0.18, 0.045)), trim_mat,
				Vector3(0.0, shoulder_y - 0.1, -0.13 * bulk), "JacketLapels")

	# High collar for the noir silhouettes.
	if features["collar"]:
		_part(rig, _box(Vector3(0.36 * bulk, 0.18, 0.09)), coat_mat,
			Vector3(0.0, shoulder_y + 0.12, 0.12 * bulk), "Collar")
		for side in [-1.0, 1.0]:
			_part(rig, _box(Vector3(0.08, 0.14, 0.06)), coat_mat,
				Vector3(side * 0.14 * bulk, shoulder_y + 0.1, 0.08 * bulk), "CollarWing" + _s(side))

	# Neck and head: jaw plate, nose, brow, ears, mouth — silhouette, not anatomy.
	_part(rig, _cyl(0.055, 0.065, 0.11), skin_mat, Vector3(0.0, shoulder_y + 0.1, 0.0), "Neck")
	var head := _part(rig, _sphere(head_r), skin_mat, Vector3(0.0, head_y, 0.0), "Head")
	_part(head, _sphere(head_r * 0.92), jaw_mat,
		Vector3(0.0, -head_r * 0.28, -head_r * 0.05), "Jaw")
	_part(head, _box(Vector3(head_r * 1.35, head_r * 0.95, head_r * 0.35)), skin_mat,
		Vector3(0.0, -head_r * 0.05, -head_r * 0.72), "FacePlate")
	_part(head, _box(Vector3(head_r * 1.1, head_r * 0.18, head_r * 0.28)), jaw_mat,
		Vector3(0.0, head_r * 0.28, -head_r * 0.7), "Brow")
	_part(head, _box(Vector3(head_r * 0.22, head_r * 0.28, head_r * 0.35)), skin_mat,
		Vector3(0.0, -head_r * 0.02, -head_r * 0.95), "Nose")
	_part(head, _box(Vector3(head_r * 0.45, head_r * 0.08, head_r * 0.12)), mouth_mat,
		Vector3(0.0, -head_r * 0.38, -head_r * 0.82), "Mouth")
	for side in [-1.0, 1.0]:
		_part(head, _sphere(head_r * 0.28), skin_mat,
			Vector3(side * head_r * 0.55, -head_r * 0.08, -head_r * 0.35), "Cheek" + _s(side))
		var ear := _part(head, _cyl(head_r * 0.12, head_r * 0.16, head_r * 0.22), skin_mat,
			Vector3(side * head_r * 0.95, 0.0, 0.0), "Ear" + _s(side))
		ear.rotation.z = side * 0.35

	# Eye-slits: the noir face. A visor band or a pair of glow slots.
	if features["eyes"] == "visor":
		_part(head, _box(Vector3(head_r * 1.55, head_r * 0.32, 0.03)), eye_mat,
			Vector3(0.0, head_r * 0.08, -head_r * 0.88), "Visor")
		_part(head, _box(Vector3(head_r * 1.65, head_r * 0.08, 0.025)), trim_mat,
			Vector3(0.0, head_r * 0.28, -head_r * 0.86), "VisorRim")
	else:
		for side in [-1.0, 1.0]:
			_part(head, _box(Vector3(head_r * 0.42, head_r * 0.28, 0.03)), eye_mat,
				Vector3(side * head_r * 0.38, head_r * 0.1, -head_r * 0.86), "Eye" + _s(side))
			_part(head, _box(Vector3(head_r * 0.48, head_r * 0.08, 0.02)), jaw_mat,
				Vector3(side * head_r * 0.38, head_r * 0.28, -head_r * 0.84), "Lid" + _s(side))

	if features["cyber"]:
		_part(head, _box(Vector3(head_r * 0.35, head_r * 0.12, head_r * 0.08)), glow_mat,
			Vector3(head_r * 0.7, head_r * 0.15, -head_r * 0.2), "TempleImplant")

	# Hair — silhouette marks above the skull, skipped under full hoods.
	match String(features["hair"]):
		"slick":
			_part(head, _box(Vector3(head_r * 1.5, head_r * 0.35, head_r * 1.4)), hair_mat,
				Vector3(0.0, head_r * 0.55, head_r * 0.05), "Hair")
		"tuft":
			_part(head, _sphere(head_r * 0.45), hair_mat,
				Vector3(0.0, head_r * 0.75, head_r * 0.1), "Hair")
		"messy":
			for i in range(3):
				var ox := (float(i) - 1.0) * head_r * 0.35
				_part(head, _box(Vector3(head_r * 0.35, head_r * 0.4, head_r * 0.3)), hair_mat,
					Vector3(ox, head_r * 0.7, head_r * 0.15 - absf(ox) * 0.2), "Hair%d" % i)
		"crop":
			_part(head, _cyl(head_r * 0.95, head_r * 0.85, head_r * 0.35), hair_mat,
				Vector3(0.0, head_r * 0.55, 0.0), "Hair")
		"bangs":
			_part(head, _box(Vector3(head_r * 1.4, head_r * 0.28, head_r * 0.35)), hair_mat,
				Vector3(0.0, head_r * 0.45, -head_r * 0.55), "Bangs")
			_part(head, _box(Vector3(head_r * 1.5, head_r * 0.3, head_r * 1.2)), hair_mat,
				Vector3(0.0, head_r * 0.6, head_r * 0.15), "Hair")
		_:
			pass

	# Headwear.
	match String(features["hat"]):
		"brim":
			_part(head, _cyl(head_r * 1.95, head_r * 1.95, 0.03), hat_mat,
				Vector3(0.0, head_r * 0.55, 0.0), "HatBrim")
			_part(head, _cyl(head_r * 1.05, head_r * 1.2, head_r * 1.1), hat_mat,
				Vector3(0.0, head_r * 1.15, 0.0), "HatTop")
			_part(head, _box(Vector3(head_r * 0.5, head_r * 0.12, head_r * 0.08)), trim_mat,
				Vector3(0.0, head_r * 0.7, -head_r * 1.0), "HatBand")
		"cap":
			_part(head, _cyl(head_r * 1.15, head_r * 1.35, head_r * 0.7), hat_mat,
				Vector3(0.0, head_r * 0.75, 0.05), "Cap")
			_part(head, _box(Vector3(head_r * 1.3, 0.025, head_r * 0.9)), hat_mat,
				Vector3(0.0, head_r * 0.45, -head_r * 1.05), "CapBrim")
		"peaked":
			_part(head, _cyl(head_r * 1.2, head_r * 1.4, head_r * 0.75), hat_mat,
				Vector3(0.0, head_r * 0.75, 0.0), "Cap")
			_part(head, _box(Vector3(head_r * 1.5, 0.025, head_r * 1.0)), trim_mat,
				Vector3(0.0, head_r * 0.42, -head_r * 1.05), "CapBrim")
			_part(head, _box(Vector3(head_r * 0.35, head_r * 0.2, head_r * 0.08)), glow_mat,
				Vector3(0.0, head_r * 0.85, -head_r * 1.15), "CapBadge")
		"hood":
			_part(head, _cyl(0.02, head_r * 1.45, head_r * 1.5), hat_mat,
				Vector3(0.0, head_r * 0.45, head_r * 0.2), "Hood")
			_part(head, _box(Vector3(head_r * 1.6, head_r * 0.2, head_r * 0.9)), hat_mat,
				Vector3(0.0, head_r * 0.15, -head_r * 0.4), "HoodCowl")
		"hoodie":
			_part(head, _cyl(head_r * 1.3, head_r * 1.4, head_r * 0.95), coat_mat,
				Vector3(0.0, head_r * 0.55, head_r * 0.25), "Hood")
			for side in [-1.0, 1.0]:
				_part(head, _box(Vector3(head_r * 0.35, head_r * 0.7, head_r * 0.15)), coat_mat,
					Vector3(side * head_r * 0.7, head_r * 0.1, -head_r * 0.2), "HoodSide" + _s(side))

	# Extras.
	if features["bag"]:
		_part(rig, _box(Vector3(0.32 * bulk, 0.26, 0.14)), trim_mat,
			Vector3(0.0, hip_y + 0.32, 0.2 * bulk), "Bag")
		_part(rig, _box(Vector3(0.04, 0.35, 0.03)), leather_mat,
			Vector3(0.14 * bulk, shoulder_y - 0.05, 0.08), "BagStrap")
		_part(rig, _box(Vector3(0.1, 0.08, 0.04)), glow_mat,
			Vector3(0.0, hip_y + 0.38, 0.28 * bulk), "BagBuckle")
	if features["pendant"]:
		_part(rig, _box(Vector3(0.1, 0.14, 0.035)), glow_mat,
			Vector3(0.0, shoulder_y - 0.14, -0.15 * bulk), "Pendant")
		_part(rig, _cyl(0.01, 0.01, 0.12), trim_mat,
			Vector3(0.0, shoulder_y - 0.02, -0.12 * bulk), "PendantChain")

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


## Walk cycle layered on top of apply_idle: limbs contra-swing, and the whole
## rig bobs on the step. Boots and hands are children of Leg/Arm pivots, so only
## the pivot nodes need rotation.
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


static func _cloth(color: Color, rim: Color, roughness: float) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = TOON
	mat.next_pass = INK
	mat.set_shader_parameter("albedo_color", color)
	mat.set_shader_parameter("roughness", roughness)
	mat.set_shader_parameter("rim_color", rim)
	mat.set_shader_parameter("rim_strength", 0.78)
	mat.set_shader_parameter("rim_light_bias", 0.55)
	mat.set_shader_parameter("shadow_tint_strength", 0.6)
	mat.set_shader_parameter("spec_strength", 0.55)
	mat.set_shader_parameter("light_ramp", LIGHT_RAMP)
	mat.set_shader_parameter("use_light_ramp", true)
	return mat


static func _skin(color: Color, rim: Color) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = TOON
	mat.next_pass = INK
	mat.set_shader_parameter("albedo_color", color)
	mat.set_shader_parameter("roughness", 0.72)
	mat.set_shader_parameter("rim_color", rim)
	mat.set_shader_parameter("rim_strength", 0.95)
	mat.set_shader_parameter("rim_power", 2.8)
	mat.set_shader_parameter("rim_light_bias", 0.4)
	mat.set_shader_parameter("shadow_wrap", 0.55)
	mat.set_shader_parameter("shadow_tint_strength", 0.45)
	mat.set_shader_parameter("spec_strength", 0.28)
	mat.set_shader_parameter("spec_threshold", 0.72)
	mat.set_shader_parameter("spec_softness", 0.08)
	mat.set_shader_parameter("skin_mottle", 0.22)
	mat.set_shader_parameter("skin_mottle_scale", 9.0)
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
	return mesh


static func _sphere(radius: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 16
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
