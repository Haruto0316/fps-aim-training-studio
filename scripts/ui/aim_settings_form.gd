extends RefCounted

const Aim = preload("res://scripts/input/aim_settings.gd")
const Style = preload("res://scripts/ui/style.gd")
const CAPTIONS := {
	"sensitivity": "基本感度", "horizontal": "水平倍率", "vertical": "垂直倍率",
	"vertical_fov": "垂直 FOV（°）", "dpi": "マウス DPI"
}

var settings: Aim
var draft: Dictionary
var inputs: Array[SpinBox] = []


func _init(profile: Aim, form: VBoxContainer, reading: Label) -> void:
	settings = profile
	draft = settings.values.duplicate()
	var presets := OptionButton.new()
	presets.custom_minimum_size = Vector2(228, 36)
	var preset_ids := settings.presets.keys()
	for key: String in preset_ids:
		presets.add_item(settings.presets[key].label)
	presets.select(preset_ids.find(draft.preset))
	Style.field(form, "感度プリセット", presets)
	var values := draft
	var update_distance := func() -> void:
		reading.text = "%.2f cm / 360°" % profile.cm_per_turn(values)
	for key: String in CAPTIONS:
		var limits: Array = Aim.FIELDS[key]
		var field := Style.spin(draft[key], limits[0], limits[1], limits[2])
		if key in ["sensitivity", "horizontal", "vertical"]:
			field.custom_arrow_step = 0.1
		inputs.append(field)
		Style.field(form, CAPTIONS[key], field)
		field.value_changed.connect(func(value: float) -> void:
			values[key] = value
			update_distance.call()
		)
	presets.item_selected.connect(func(index: int) -> void:
		values.preset = preset_ids[index]
		update_distance.call()
	)
	update_distance.call()


func save() -> Error:
	for field in inputs:
		field.apply()
	return settings.save(draft)
