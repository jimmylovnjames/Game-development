class_name Biome
extends Resource
## One band of the wasteland, as data.
##
## A biome says how dense a region builds, how tall it gets, how much of it is
## still standing and how much neon is still lit. Like quests, biomes are
## `Resource`s and not code — new regions are a `.tres` in `worlds/biomes/`,
## diffable and hot-reloadable, and the generator is the only thing that has to
## know what the numbers mean.

@export var id: StringName = &""
@export var display_name: String = ""

@export_group("Selection")
## Biomes are chosen by the urbanisation field (see `BiomeMap`): 1.0 is the
## arcology core, 0.0 is open desert. Bands are half-open — [min, max).
@export_range(0.0, 1.0) var min_urbanisation: float = 0.0
@export_range(0.0, 1.0) var max_urbanisation: float = 1.0

@export_group("Lots")
## Chance a lot carries a building at all. The rest are rubble or bare slab.
@export_range(0.0, 1.0) var building_chance: float = 0.72
## Of the lots that get no building, how many are rubble rather than empty.
@export_range(0.0, 1.0) var rubble_chance: float = 0.55

@export_group("Buildings")
@export var min_height: float = 8.0
@export var max_height: float = 46.0
## Exponent on the height roll. Above 1.0 it biases short, so the few tall
## towers actually read as tall instead of vanishing into a wall of equals.
@export_range(0.5, 6.0) var height_bias: float = 2.2
@export var min_footprint: float = 8.0
@export var max_footprint: float = 15.0

@export_group("Signage")
@export_range(0.0, 1.0) var sign_chance: float = 0.55
## Neon tints available to this biome. The style bible allows three families;
## a biome that reaches for a fourth needs a reason.
@export var sign_tints: PackedColorArray = PackedColorArray([
	Color(1.0, 0.176, 0.584),
	Color(0.0, 0.898, 1.0),
])
## Emission energy. Keep it in the 2-3 range — ACES desaturates anything
## higher to a white blob and the glow pass does the blooming anyway.
@export_range(0.0, 8.0) var sign_energy: float = 2.6
@export var sign_light_energy: float = 3.5
@export var sign_light_range: float = 18.0
## Upper bound on the per-sign chance of a dying-ballast dropout.
@export_range(0.0, 1.0) var max_sign_dropout: float = 0.12

@export_group("Street lighting")
## Chance a junction that qualifies for a lamp actually still has a working one.
@export_range(0.0, 1.0) var lamp_chance: float = 1.0
@export var lamp_energy: float = 2.6
@export var lamp_color: Color = Color(1.0, 0.68, 0.36)


func contains_urbanisation(value: float) -> bool:
	return value >= min_urbanisation and value < max_urbanisation


func pick_tint(rng: RandomNumberGenerator) -> Color:
	if sign_tints.is_empty():
		return Color(1.0, 0.176, 0.584)
	return sign_tints[rng.randi() % sign_tints.size()]


## Authoring mistakes that produce a silently broken region rather than an
## error. Mirrors `Quest.design_warnings()` so `tools/verify_setup.gd` can hold
## both to the same standard.
func design_warnings() -> Array[String]:
	var warnings: Array[String] = []
	if String(id).is_empty():
		warnings.append("biome has no id")
	if max_urbanisation <= min_urbanisation:
		warnings.append("urbanisation band is empty (%.2f..%.2f)" % [
			min_urbanisation, max_urbanisation,
		])
	if max_height < min_height:
		warnings.append("max_height is below min_height")
	if max_footprint < min_footprint:
		warnings.append("max_footprint is below min_footprint")
	if sign_chance > 0.0 and sign_tints.is_empty():
		warnings.append("signs are enabled but no sign_tints are defined")
	if sign_energy > 4.0:
		warnings.append(
			"sign_energy %.1f will tonemap to white — keep it near 2-3" % sign_energy
		)
	return warnings
