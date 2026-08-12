class_name BiomeMap
extends RefCounted
## Decides which `Biome` a piece of the world belongs to.
##
## The whole map is one scalar field — *urbanisation* — running from 1.0 in the
## arcology core to 0.0 out in the open desert. Ferrum Halo does not end at a
## wall; it thins, so the field is a radial falloff roughened by noise. That
## keeps the city edge ragged the way a place the desert is eating should be,
## and it means a new region is a `.tres` with a different band rather than new
## code.
##
## Sampling is per chunk centre, so a chunk is uniformly one biome. Blending
## across a chunk seam is a later problem; at 64 m the seam sits inside the fog.

## Inside this radius the core stays dense regardless of noise. The opening
## hours of the game happen here and a hollowed-out Ferrum Halo reads as a bug.
const CORE_RADIUS := 240.0
## Metres from the core edge over which urbanisation decays to nothing.
const FALLOFF_RANGE := 900.0

var _noise := FastNoiseLite.new()
var _biomes: Array[Biome] = []


func configure(world_seed: int, biomes: Array[Biome]) -> void:
	_noise.seed = world_seed
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 0.0018
	_noise.fractal_octaves = 3

	_biomes = biomes.duplicate()
	_biomes.sort_custom(func(a: Biome, b: Biome) -> bool:
		return a.min_urbanisation < b.min_urbanisation)


func is_configured() -> bool:
	return not _biomes.is_empty()


func biomes() -> Array[Biome]:
	return _biomes


## 1.0 = arcology core, 0.0 = open waste.
func urbanisation(world_position: Vector3) -> float:
	var flat := Vector2(world_position.x, world_position.z)
	var noise_value := (_noise.get_noise_2d(flat.x, flat.y) + 1.0) * 0.5
	var falloff := 1.0 - clampf((flat.length() - CORE_RADIUS) / FALLOFF_RANGE, 0.0, 1.0)
	# Squared falloff so the core holds its density and then drops off quickly,
	# rather than fading evenly the whole way out.
	return clampf(lerpf(noise_value * 0.55, 1.0, falloff * falloff), 0.0, 1.0)


func biome_at(world_position: Vector3) -> Biome:
	if _biomes.is_empty():
		return null
	var value := urbanisation(world_position)
	for biome in _biomes:
		if biome.contains_urbanisation(value):
			return biome
	# Bands are half-open, so urbanisation exactly 1.0 falls off the end of the
	# last one. Densest biome wins rather than returning nothing.
	return _biomes.back()
