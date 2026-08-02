class_name ComicFX
extends Node3D
## Comic-panel punctuation: hand-lettered sound words in the world and panel
## flashes on the frame. Impacts, hard landings, lightning and quest beats all
## punch through here, so the game reads like a comic even in a still frame.

const WORDS_IMPACT := ["THOK", "KRACK", "KLANK", "THUD"]
const WORDS_HEAVY := ["WHUMP", "KRUNCH", "BAMM"]
const WORDS_STORM := ["KRAKOOM", "BZZZT", "KRAKK"]
const COLOR_IMPACT := Color(0.93, 0.92, 1.0)
const COLOR_HEAVY := Color(0.969, 1.0, 0.235)
const COLOR_STORM := Color(0.969, 1.0, 0.235)
const COLOR_QUEST := Color(1.0, 0.176, 0.584)
const INK := Color(0.03, 0.02, 0.06)

@export var word_lifetime: float = 1.5
@export var word_fade: float = 0.45

var _rng := RandomNumberGenerator.new()
var _flash_layer: CanvasLayer
var _flash_rect: ColorRect


func _ready() -> void:
	add_to_group("comic_fx")
	_rng.seed = 909090

	_flash_layer = CanvasLayer.new()
	_flash_layer.layer = 5
	add_child(_flash_layer)
	_flash_rect = ColorRect.new()
	_flash_rect.anchor_right = 1.0
	_flash_rect.anchor_bottom = 1.0
	_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash_rect.modulate.a = 0.0
	_flash_layer.add_child(_flash_rect)


## Spawn a lettered word at a world position. `style` picks palette and lexicon
## ("impact", "heavy", "storm", "quest"). hold_seconds > 0 keeps the word up
## for staged screenshots instead of the natural lifetime.
func burst(
	word: String,
	world_position: Vector3,
	style: String = "impact",
	hold_seconds: float = -1.0
) -> Label3D:
	var label := Label3D.new()
	label.text = word
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.font_size = 96
	label.pixel_size = 0.011
	label.outline_size = 16
	label.outline_modulate = INK
	label.modulate = _style_color(style)
	label.position = world_position + Vector3(
		_rng.randf_range(-0.25, 0.25), _rng.randf_range(0.0, 0.3), _rng.randf_range(-0.25, 0.25)
	)
	# Words slam in rotated like pasted lettering.
	label.rotation.z = _rng.randf_range(-0.22, 0.22)
	label.scale = Vector3.ONE * _rng.randf_range(0.9, 1.3)
	add_child(label)

	var pop := create_tween()
	var tween := pop.tween_property(label, "scale", label.scale * 1.12, 0.09)
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pop.chain().tween_property(label, "scale", label.scale, 0.12)

	var hold := hold_seconds if hold_seconds > 0.0 else word_lifetime
	_fade_out_after(label, hold)
	return label


func _fade_out_after(label: Label3D, hold: float) -> void:
	await get_tree().create_timer(hold).timeout
	if not is_instance_valid(label):
		return
	var fade := create_tween()
	fade.set_parallel()
	fade.tween_property(label, "modulate:a", 0.0, word_fade)
	fade.tween_property(label, "outline_modulate:a", 0.0, word_fade)
	fade.chain().tween_callback(label.queue_free)


## A beat of white (or magenta, or acid) across the whole panel. Short and
## quiet on purpose — it should read as a page turn, not a flashbang.
func panel_flash(color: Color = Color(1, 1, 1), strength: float = 0.22, seconds: float = 0.16) -> void:
	_flash_rect.color = color
	var flash := create_tween()
	flash.tween_property(_flash_rect, "modulate:a", strength, seconds * 0.3)
	flash.tween_property(_flash_rect, "modulate:a", 0.0, seconds * 0.7)


func _style_color(style: String) -> Color:
	match style:
		"heavy":
			return COLOR_HEAVY
		"storm":
			return COLOR_STORM
		"quest":
			return COLOR_QUEST
		_:
			return COLOR_IMPACT


## Impact lexicon by speed, for anything that hits the street.
func pick_impact(speed: float) -> String:
	if speed > 7.0:
		return WORDS_HEAVY[_rng.randi() % WORDS_HEAVY.size()]
	return WORDS_IMPACT[_rng.randi() % WORDS_IMPACT.size()]


func pick_storm() -> String:
	return WORDS_STORM[_rng.randi() % WORDS_STORM.size()]
