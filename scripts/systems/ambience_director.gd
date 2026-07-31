class_name AmbienceDirector
extends Node
## The district's sound floor, synthesized at boot: rain hiss that tracks the
## rain system's intensity, a two-note transformer drone under everything, and
## thunder that chases StormDirector strikes. No audio assets — every loop is
## generated PCM, seeded and deterministic, so the mix is identical on every
## machine and CI never needs files.

const MIX_RATE := 22050
const RAIN_SECONDS := 4.0
const DRONE_SECONDS := 6.0
const THUNDER_SECONDS := 2.8

var _rng := RandomNumberGenerator.new()
var _rain_player: AudioStreamPlayer
var _drone_player: AudioStreamPlayer
var _thunder_player: AudioStreamPlayer
var _rain: RainSystem
var _storm: StormDirector

## Test-visible counters (headless audio drivers are dummies).
var thunder_plays: int = 0


func _ready() -> void:
	_rng.seed = 777001

	_rain_player = _make_player("Rain", _make_rain_stream(), -14.0)
	_drone_player = _make_player("Drone", _make_drone_stream(), -24.0)
	_thunder_player = _make_player("Thunder", _make_thunder_stream(), -8.0)

	_rain = get_tree().get_first_node_in_group("rain_volume") as RainSystem
	_storm = get_node_or_null("../StormDirector") as StormDirector
	if _storm != null:
		_storm.struck.connect(_on_storm_struck)

	_rain_player.play()
	_drone_player.play()


func _process(_delta: float) -> void:
	if _rain == null:
		return
	# Rain loudness tracks the visual intensity, so a storm passing is audible.
	var target := -30.0 + _rain.intensity * 18.0
	_rain_player.volume_db = lerpf(_rain_player.volume_db, target, 0.05)


func _on_storm_struck(strength: float) -> void:
	# Thunder arrives late like it has distance to cross.
	var delay := _rng.randf_range(0.2, 0.9) * (2.0 - clampf(strength, 0.5, 1.5))
	await get_tree().create_timer(delay).timeout
	_thunder_player.volume_db = -9.0 + strength * 4.0
	_thunder_player.play()
	thunder_plays += 1


func _make_player(node_name: String, stream: AudioStreamWAV, volume_db: float) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = node_name
	player.stream = stream
	player.volume_db = volume_db
	add_child(player)
	return player


## Broadband hiss through a slow swell — reads as rain on tar and neon alike.
func _make_rain_stream() -> AudioStreamWAV:
	var count := int(MIX_RATE * RAIN_SECONDS)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = _render_samples(count, func(i: int) -> float:
		var x := _rng.randf_range(-1.0, 1.0)
		var swell := 0.75 + 0.25 * sin(float(i) / count * TAU * 2.0)
		return x * 0.32 * swell
	)
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = count
	return stream


## Mains hum with a minor second beating against it — the sound of a city that
## never powers down.
func _make_drone_stream() -> AudioStreamWAV:
	var count := int(MIX_RATE * DRONE_SECONDS)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = _render_samples(count, func(i: int) -> float:
		var t := float(i) / MIX_RATE
		var fundamental := sin(TAU * 55.0 * t) * 0.30
		var beat := sin(TAU * 55.9 * t) * 0.22
		var overtone := sin(TAU * 110.6 * t) * 0.10
		var tremolo := 0.8 + 0.2 * sin(TAU * 0.13 * t)
		return (fundamental + beat + overtone) * tremolo
	)
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = count
	return stream


## Brown-noise rumble with a fast attack and a long low tail.
func _make_thunder_stream() -> AudioStreamWAV:
	var count := int(MIX_RATE * THUNDER_SECONDS)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	var brown := 0.0
	stream.data = _render_samples(count, func(i: int) -> float:
		var t := float(i) / MIX_RATE
		brown = clampf(brown + _rng.randf_range(-0.055, 0.055), -1.0, 1.0)
		var envelope := t / 0.05 if t < 0.05 else exp(-(t - 0.05) * 1.9)
		var crack := 0.0
		if t < 0.02:
			crack = _rng.randf_range(-0.5, 0.5) * (1.0 - t / 0.02)
		return brown * 0.85 * envelope + crack
	)
	return stream


func _render_samples(count: int, generator: Callable) -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(count * 2)
	var lp := 0.0
	for i in count:
		var sample: float = generator.call(i)
		# One-pole lowpass to sand the digital edges off whatever we generated.
		lp += 0.18 * (sample - lp)
		data.encode_s16(i * 2, int(clampf(lp, -1.0, 1.0) * 32760.0))
	return data
