class_name TextureFactory
extends RefCounted
## Runtime texture synthesis for effects that need a soft alpha shape but no
## authored art. Everything here is deterministic and tiny — generated once at
## boot, shared by every emitter that asks for it.

static var _soft_blob_cache: ImageTexture = null


## Radial-gradient blob: opaque centre fading to transparent at the rim.
## Used for steam/smoke particle billboards.
static func soft_blob(size: int = 64) -> ImageTexture:
	if _soft_blob_cache != null:
		return _soft_blob_cache

	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var centre := Vector2(size, size) * 0.5
	var radius := size * 0.5
	for y in size:
		for x in size:
			var d := Vector2(x, y).distance_to(centre) / radius
			# Smooth hermite falloff; squared once for a fatter, softer core.
			var a := smoothstep(1.0, 0.15, d)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a * a))
	_soft_blob_cache = ImageTexture.create_from_image(img)
	return _soft_blob_cache
