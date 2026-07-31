class_name StormDirector
extends Node
## Heat lightning over the district: every ~7.7 s slot rolls for a strike and
## spikes the key light in a stuttered burst. The sky shader flashes the cloud
## deck on its own schedule; the two do not need to agree — storms feel wrong
## when light and sky are frame-locked.

@export var light_path: NodePath = "../Moonlight"
## Slot probability of a strike.
@export_range(0.0, 1.0) var strike_chance: float = 0.14
@export var slot_seconds: float = 7.7
@export var base_energy: float = 0.5
@export var strike_energy: float = 3.2

## Running total, asserted by soak tests when a storm needs forcing.
var strike_count: int = 0

var _light: DirectionalLight3D
var _last_slot: int = -1
var _burst: float = 0.0
var _burst_time: float = 0.0


func _ready() -> void:
	_light = get_node_or_null(light_path) as DirectionalLight3D
	if _light != null:
		base_energy = _light.light_energy


func _process(delta: float) -> void:
	if _light == null:
		return

	var slot := int(Time.get_ticks_msec() / 1000.0 / slot_seconds)
	if slot != _last_slot:
		_last_slot = slot
		if _roll(slot) < strike_chance:
			_burst = 0.5 + 0.5 * _roll(slot * 7.31)
			_burst_time = 0.0
			strike_count += 1

	if _burst > 0.0:
		_burst_time += delta
		# Stuttered envelope: three quick flashes decaying over ~0.6 s.
		var t := _burst_time
		var envelope := 0.0
		if t < 0.08:
			envelope = 1.0
		elif t < 0.16:
			envelope = 0.25
		elif t < 0.28:
			envelope = 0.85
		elif t < 0.36:
			envelope = 0.2
		elif t < 0.55:
			envelope = 0.55 * (1.0 - (t - 0.36) / 0.19)
		else:
			envelope = 0.0
			_burst = 0.0
		_light.light_energy = base_energy + strike_energy * envelope * _burst


func _roll(seed: float) -> float:
	var p := seed * 0.1031
	p -= floorf(p)
	p *= p + 33.33
	p -= floorf(p)
	p *= p + p
	return p - floorf(p)
