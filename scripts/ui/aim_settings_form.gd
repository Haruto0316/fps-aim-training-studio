extends RefCounted

const Aim = preload("res://scripts/input/aim_settings.gd")
const Style = preload("res://scripts/ui/style.gd")
const CAPTIONS := {
	"sensitivity": "マウス感度", "horizontal": "水平倍率", "vertical": "垂直倍率",
	"vertical_fov": "垂直 FOV（°）"
}

var settings: Aim
var draft: Dictionary
var inputs: Array[SpinBox] = []


func _init(profile: Aim, form: VBoxContainer, reading: Label) -> void:
	settings = profile
	draft = settings.values.duplicate(true)
	var presets := OptionButton.new()
	presets.name = "SensitivityPreset"
	presets.custom_minimum_size = Vector2(228, 36)
	var preset_ids := settings.presets.keys()
	for key: String in preset_ids:
		presets.add_item(settings.presets[key].label)
	presets.select(preset_ids.find(draft.preset))
	Style.field(form, "感度プリセット", presets)
	var values := draft
	var update_distance := func() -> void:
		reading.text = "%.2f cm / 360°" % profile.cm_per_turn(values)
	var fields := {}
	for key: String in CAPTIONS:
		var limits: Array = Aim.FIELDS[key]
		var field := Style.spin(draft[key], limits[0], limits[1], limits[2])
		if key in ["sensitivity", "horizontal", "vertical"]:
			field.custom_arrow_step = 0.1
		inputs.append(field)
		fields[key] = field
		Style.field(form, CAPTIONS[key], field)
		field.value_changed.connect(func(value: float) -> void:
			values[key] = value
			update_distance.call()
		)
	var update_axes := func() -> void:
		fields.horizontal.get_parent().visible = values.preset == "generic"
		fields.vertical.get_parent().visible = values.preset == "generic"
	var dpi := OptionButton.new()
	dpi.name = "MouseDpi"
	dpi.custom_minimum_size = Vector2(174, 36)
	for option: int in Aim.DPI_OPTIONS:
		dpi.add_item(str(option), option)
	dpi.select(dpi.get_item_index(int(values.dpi)))
	Style.field(form, "マウス DPI", dpi)
	dpi.item_selected.connect(func(index: int) -> void:
		values.dpi = dpi.get_item_id(index)
		update_distance.call()
	)
	presets.item_selected.connect(func(index: int) -> void:
		var sensitivity: SpinBox = fields.sensitivity
		sensitivity.apply()
		values.sensitivity_by_preset[values.preset] = values.sensitivity
		values.preset = preset_ids[index]
		values.sensitivity = values.sensitivity_by_preset[values.preset]
		sensitivity.value = values.sensitivity
		# SpinBox refreshes its text on draw. Commit the new preset to the field immediately.
		sensitivity.get_line_edit().text = String.num(sensitivity.value, 4)
		update_axes.call()
		update_distance.call()
	)
	update_axes.call()
	update_distance.call()


func save() -> Error:
	for field in inputs:
		field.apply()
	return settings.save(draft)
