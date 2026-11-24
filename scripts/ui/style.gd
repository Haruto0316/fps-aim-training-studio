extends RefCounted

const INK := Color("#101b24")
const PANEL := Color("#17252f")
const EDGE := Color("#334754")
const PAPER := Color("#f4f0e6")
const MUTED := Color("#acc0cb")
const ACCENT := Color("#ff936d")


static func flat(color: Color, border := Color.TRANSPARENT, radius := 8) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	return style


static func create_theme() -> Theme:
	var theme := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Yu Gothic UI", "Meiryo", "Segoe UI"])
	theme.default_font = font
	theme.default_font_size = 18
	theme.set_color("font_color", "Label", PAPER)
	theme.set_color("font_color", "Button", PAPER)
	theme.set_color("font_hover_color", "Button", PAPER)
	theme.set_color("font_pressed_color", "Button", PAPER)
	theme.set_stylebox("normal", "Button", _button_box(PANEL, EDGE))
	theme.set_stylebox("hover", "Button", _button_box(Color("#263a46"), ACCENT.darkened(0.4)))
	theme.set_stylebox("pressed", "Button", _button_box(Color("#344957"), ACCENT))
	var focus := flat(Color.TRANSPARENT, ACCENT)
	focus.set_border_width_all(2)
	theme.set_stylebox("focus", "Button", focus)
	return theme


static func _button_box(fill: Color, border: Color) -> StyleBoxFlat:
	var style := flat(fill, border)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 9
	style.content_margin_bottom = 9
	return style


static func label(value: String, font_size := 18, color := PAPER) -> Label:
	var control := Label.new()
	control.text = value
	control.add_theme_font_size_override("font_size", font_size)
	control.add_theme_color_override("font_color", color)
	return control


static func button(value: String, callback: Callable, primary := false) -> Button:
	var control := Button.new()
	control.text = value
	control.custom_minimum_size.y = 46
	control.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	control.pressed.connect(callback)
	if primary:
		control.add_theme_stylebox_override("normal", _button_box(ACCENT, ACCENT))
		control.add_theme_stylebox_override("hover", _button_box(Color("#ffb497"), ACCENT))
		control.add_theme_stylebox_override("pressed", _button_box(Color("#dd7855"), ACCENT))
		for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			control.add_theme_color_override(state, INK)
	return control


static func stack(separation := 12) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", separation)
	return column


static func panel(parent: Control, inset := 20) -> VBoxContainer:
	var frame := PanelContainer.new()
	var surface := flat(PANEL, EDGE, 12)
	surface.content_margin_left = inset
	surface.content_margin_right = inset
	surface.content_margin_top = inset
	surface.content_margin_bottom = inset
	frame.add_theme_stylebox_override("panel", surface)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(frame)
	var contents := stack()
	frame.add_child(contents)
	return contents


static func spin(value: float, low: float, high: float, step: float) -> SpinBox:
	var control := SpinBox.new()
	control.min_value = low
	control.max_value = high
	control.step = step
	control.value = value
	control.select_all_on_focus = true
	control.custom_minimum_size = Vector2(174, 36)
	return control


static func field(parent: Control, caption: String, field: Control) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)
	var caption_label := label(caption, 17, MUTED)
	caption_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(caption_label)
	row.add_child(field)
