extends RefCounted
## The game's look for menus and the HUD: dark glassy panels with thin neon edges, chrome text
## with a hot pink glow, buttons that light up when pressed or focused.

const CHROME := Color(0.88, 0.92, 1.0)
const PINK := Color(1.0, 0.35, 0.72)
const CYAN := Color(0.35, 0.9, 1.0)
const GLASS := Color(0.04, 0.03, 0.09, 0.72)


static func panel(edge := CYAN, radius := 14, fill := GLASS) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = edge
	box.set_border_width_all(2)
	box.set_corner_radius_all(radius)
	box.content_margin_left = 18
	box.content_margin_right = 18
	box.content_margin_top = 10
	box.content_margin_bottom = 10
	box.shadow_color = Color(edge.r, edge.g, edge.b, 0.35)
	box.shadow_size = 8
	return box


static func make() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 24
	theme.set_color("font_color", "Label", CHROME)
	theme.set_color("font_outline_color", "Label", Color(0.0, 0.0, 0.0, 0.85))
	theme.set_constant("outline_size", "Label", 6)

	var normal := panel(Color(CYAN.r, CYAN.g, CYAN.b, 0.7))
	var hover := panel(PINK, 14, Color(0.12, 0.04, 0.14, 0.82))
	var pressed := panel(PINK, 14, Color(0.4, 0.08, 0.3, 0.9))
	var focus := panel(PINK, 14, Color(0, 0, 0, 0))
	focus.set_border_width_all(3)
	theme.set_stylebox("normal", "Button", normal)
	theme.set_stylebox("hover", "Button", hover)
	theme.set_stylebox("pressed", "Button", pressed)
	theme.set_stylebox("focus", "Button", focus)
	theme.set_stylebox("disabled", "Button", normal)
	theme.set_color("font_color", "Button", CHROME)
	theme.set_color("font_hover_color", "Button", Color.WHITE)
	theme.set_color("font_pressed_color", "Button", Color.WHITE)
	theme.set_color("font_focus_color", "Button", Color.WHITE)
	theme.set_color("font_outline_color", "Button", Color(0, 0, 0, 0.8))
	theme.set_constant("outline_size", "Button", 4)
	theme.set_stylebox("panel", "PanelContainer", panel())
	theme.set_color("font_color", "CheckButton", CHROME)
	return theme


## A big chrome heading with a glow round it
static func heading(text: String, size: int, glow := PINK) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", CHROME)
	label.add_theme_color_override("font_outline_color", glow)
	label.add_theme_constant_override("outline_size", maxi(size / 8, 6))
	label.add_theme_color_override("font_shadow_color", Color(glow.r, glow.g, glow.b, 0.45))
	label.add_theme_constant_override("shadow_offset_x", 0)
	label.add_theme_constant_override("shadow_offset_y", 4)
	label.add_theme_constant_override("shadow_outline_size", maxi(size / 4, 10))
	return label


## Small text, like a caption
static func caption(text: String, size := 20, color := CHROME) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label
