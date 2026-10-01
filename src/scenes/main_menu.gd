## 主菜单（CONTEXT.md「主菜单」）：游戏入口屏幕——「开始对局」/「进入设置」。
##
## 「开始」在「间隔计时器」开启时进入计时会话（准备 → 游玩 → 休息），否则直接开始普通对局。
## UI 全程序化拼装，与 settings_panel 同一写法。

class_name MainMenu
extends Control

signal start_pressed
signal settings_pressed

var _hint: Label

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()
	open()

func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.05, 0.07, 0.94)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	center.add_child(box)

	var title := Label.new()
	title.text = "瞄准训练器"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	box.add_child(title)

	var start_button := _button("开始对局")
	start_button.pressed.connect(func() -> void: start_pressed.emit())
	box.add_child(start_button)

	var settings_button := _button("进入设置")
	settings_button.pressed.connect(func() -> void: settings_pressed.emit())
	box.add_child(settings_button)

	_hint = Label.new()
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size.x = 300
	box.add_child(_hint)

func _button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(260, 44)
	return button

## 显示主菜单；「开始」的提示随「间隔计时器」开关变化。
func open() -> void:
	visible = true
	_hint.text = (
		"开始将进入计时会话（准备 → 游玩 → 休息）"
		if GameSettings.timer_enabled
		else "开始将进入普通对局（无尽练习）"
	)