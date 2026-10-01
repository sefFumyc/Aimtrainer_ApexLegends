## 计时覆盖层（CONTEXT.md「准备段」「休息段」）。
##
## 准备段：屏幕中央大字倒计时；休息段：全屏覆盖层显示剩余秒数 + 当前轮次 + 本轮战绩
## （以及自动调径的「半径 旧→新」）。休息段**没有任何跳过入口**——只有 ESC 能退出整个会话。

class_name TimerOverlay
extends Control

var _big: Label
var _info: Label

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	_build()

func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.04, 0.06, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	center.add_child(box)

	_big = Label.new()
	_big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_big.add_theme_font_size_override("font_size", 84)
	box.add_child(_big)

	_info = Label.new()
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.custom_minimum_size.x = 420
	box.add_child(_info)

## 准备段：5 秒大字倒计时。
func show_prepare(seconds: int) -> void:
	_big.text = str(seconds)
	_info.text = "准备"
	visible = true

## 休息段：剩余秒数 + 轮次 + 本轮战绩 + 自动调径记录。
func show_rest(seconds: int, round_index: int, repeat: int, stats_text: String, radius_lines: Array) -> void:
	_big.text = str(seconds)
	var text := "休息　第 %d / %d 轮" % [round_index, repeat]
	if not stats_text.is_empty():
		text += "\n" + stats_text
	for line in radius_lines:
		text += "\n" + str(line)
	text += "\n（休息不可跳过，ESC 退出整个会话）"
	_info.text = text
	visible = true

## 整秒边界刷新剩余秒数（准备段与休息段共用）。
func set_seconds(seconds: int) -> void:
	if visible:
		_big.text = str(seconds)

func hide_overlay() -> void:
	visible = false