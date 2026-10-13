extends RefCounted
## The game's look for menus and the HUD: the turn of the millennium. Everything is a gel pill or
## a pane of smoked glass in a chrome rim: buttons of see-through aqua with a wet highlight
## across the top and light pooling in the bottom, going lime under the pointer and orange when
## pressed; panels of dark blue glass with the same rim; text in slanted, wide-set capitals, white
## with a hard drop shadow; headings in chrome. All of it is drawn here, into little images made
## once and stretched by their middles (no art files).

const CHROME := Color(0.93, 0.95, 1.0)
const AQUA := Color(0.25, 0.72, 1.0)
const LIME := Color(0.72, 1.0, 0.22)
const ORANGE := Color(1.0, 0.6, 0.12)
const NAVY := Color(0.03, 0.06, 0.16)
const GLASS := Color(0.04, 0.08, 0.2, 0.78)

static var _font: FontVariation
static var _made := {} # the images drawn so far, by what they are


## The lettering: slanted, wide-set, a little heavier
static func font() -> Font:
	if _font == null:
		_font = FontVariation.new()
		_font.base_font = ThemeDB.fallback_font
		_font.variation_transform = Transform2D(Vector2(1.0, 0.0), Vector2(0.17, 1.0), Vector2.ZERO)
		_font.variation_embolden = 0.25
		_font.spacing_glyph = 3
	return _font


## A gel pill (or a pane, with less `gloss`): `fill` behind a chrome rim, a highlight across its
## top and light gathered at its foot. `radius`: its corners, in a 64-pixel square (32: a circle).
static func gel(fill: Color, radius := 22, gloss := 0.5, rim := 3.0, size := 64) -> StyleBoxTexture:
	var key := "%s %d %.2f %.1f %d" % [fill.to_html(), radius, gloss, rim, size]
	if not _made.has(key):
		var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
		for y in size:
			for x in size:
				# How far inside the rounded square this pixel is
				var q := Vector2(absf(x + 0.5 - size * 0.5), absf(y + 0.5 - size * 0.5)) - Vector2(size * 0.5 - radius, size * 0.5 - radius)
				var inside := -(Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - radius)
				var down := float(y) / (size - 1)
				var color: Color
				if inside < rim:
					# The rim: chrome, bright along the top, a dark band, a glint, dark at the foot
					var metal := 0.95 - down * 0.6 + 0.25 * exp(-pow((down - 0.62) * 9.0, 2.0))
					color = Color(metal * 0.95, metal * 0.98, metal * 1.05, 1.0)
				else:
					color = Color(fill.r * lerpf(1.1, 0.6, down), fill.g * lerpf(1.1, 0.6, down), fill.b * lerpf(1.1, 0.65, down), fill.a)
					# The highlight: a soft white band across the upper part, rounded with the pill
					var lit := (1.0 - smoothstep(0.08, 0.5, down)) * smoothstep(rim + 1.0, rim + 5.0, inside)
					color = color.lerp(Color(1.0, 1.0, 1.0, minf(fill.a + 0.25, 1.0)), lit * gloss)
					# ...and the light that gathers in the bottom of it
					var pooled := smoothstep(0.62, 1.0, down) * smoothstep(rim, rim + 4.0, inside)
					color = color.lerp(Color(minf(fill.r * 1.9 + 0.1, 1.0), minf(fill.g * 1.9 + 0.1, 1.0), minf(fill.b * 1.9 + 0.1, 1.0), color.a), pooled * gloss * 0.9)
				color.a *= smoothstep(-0.6, 0.6, inside)
				image.set_pixel(x, y, color)
		_made[key] = ImageTexture.create_from_image(image)
	var box := StyleBoxTexture.new()
	box.texture = _made[key]
	var edge := minf(radius + 2.0, 31.0)
	box.texture_margin_left = edge
	box.texture_margin_right = edge
	box.texture_margin_top = edge
	box.texture_margin_bottom = edge
	box.content_margin_left = 22
	box.content_margin_right = 22
	box.content_margin_top = 7
	box.content_margin_bottom = 7
	return box


## A pane of smoked glass in a chrome rim (panels: the stats, the standings, the TUNE panel)
static func panel(fill := GLASS, radius := 16) -> StyleBoxTexture:
	return gel(fill, radius, 0.16, 2.5)


## A round gel button (the DASH button), in a colour
static func orb(fill: Color) -> StyleBoxTexture:
	# (drawn big and stretched whole, so it stays a circle at any size)
	var box := gel(Color(fill.r, fill.g, fill.b, 0.82), 80, 0.6, 9.0, 160)
	box.texture_margin_left = 0
	box.texture_margin_right = 0
	box.texture_margin_top = 0
	box.texture_margin_bottom = 0
	box.content_margin_left = 6
	box.content_margin_right = 6
	return box


static func make() -> Theme:
	var theme := Theme.new()
	theme.default_font = font()
	theme.default_font_size = 22
	theme.set_color("font_color", "Label", CHROME)
	theme.set_color("font_shadow_color", "Label", Color(0.0, 0.03, 0.12, 0.9))
	theme.set_constant("shadow_offset_x", "Label", 2)
	theme.set_constant("shadow_offset_y", "Label", 2)
	theme.set_color("font_outline_color", "Label", Color(0.0, 0.02, 0.08, 0.7))
	theme.set_constant("outline_size", "Label", 4)

	theme.set_stylebox("normal", "Button", gel(Color(AQUA.r * 0.55, AQUA.g * 0.6, AQUA.b * 0.8, 0.8)))
	theme.set_stylebox("hover", "Button", gel(Color(LIME.r * 0.6, LIME.g * 0.7, LIME.b * 0.5, 0.88)))
	theme.set_stylebox("pressed", "Button", gel(Color(ORANGE.r * 0.9, ORANGE.g * 0.8, ORANGE.b * 0.6, 0.95), 22, 0.3))
	theme.set_stylebox("focus", "Button", gel(Color(LIME.r, LIME.g, LIME.b, 0.22), 22, 0.0, 4.0))
	theme.set_stylebox("disabled", "Button", gel(Color(0.2, 0.25, 0.35, 0.6), 22, 0.2))
	theme.set_color("font_color", "Button", Color.WHITE)
	theme.set_color("font_hover_color", "Button", Color.WHITE)
	theme.set_color("font_pressed_color", "Button", Color.WHITE)
	theme.set_color("font_focus_color", "Button", Color.WHITE)
	theme.set_color("font_outline_color", "Button", Color(0.0, 0.05, 0.2, 0.75))
	theme.set_constant("outline_size", "Button", 5)
	theme.set_stylebox("panel", "PanelContainer", panel())
	theme.set_color("font_color", "CheckButton", CHROME)
	return theme


## A big chrome heading: white, a dark rim, and a hard shadow in a colour set down and to the right
static func heading(text: String, size: int, glow := AQUA) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", CHROME)
	label.add_theme_color_override("font_outline_color", NAVY)
	label.add_theme_constant_override("outline_size", maxi(size / 7, 6))
	label.add_theme_color_override("font_shadow_color", glow)
	label.add_theme_constant_override("shadow_offset_x", maxi(size / 16, 3))
	label.add_theme_constant_override("shadow_offset_y", maxi(size / 16, 3))
	label.add_theme_constant_override("shadow_outline_size", maxi(size / 7, 6))
	return label


## Small text, like a caption
static func caption(text: String, size := 20, color := CHROME) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label
