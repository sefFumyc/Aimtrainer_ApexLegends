## 结算屏（CONTEXT.md「结算快照」）：结束对局后定格显示准确率 / 击杀 / 死亡 / 用时。
##
## 「新开一局」永远是普通对局——「间隔计时器」只从主菜单「开始」触发。

class_name SettlementScreen
extends Control

signal new_round_pressed
signal menu_pressed

var _body: VBoxContainer

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	_build()

func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.04, 0.06, 0.9)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	center.add_child(box)

	var title := Label.new()
	title.text = "本局结算"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	box.add_child(title)

	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 6)
	box.add_child(_body)

	var again := Button.new()
	again.text = "新开一局"
	again.custom_minimum_size = Vector2(260, 42)
	again.pressed.connect(func() -> void: new_round_pressed.emit())
	box.add_child(again)

	var to_menu := Button.new()
	to_menu.text = "返回主菜单"
	to_menu.custom_minimum_size = Vector2(260, 42)
	to_menu.pressed.connect(func() -> void: menu_pressed.emit())
	box.add_child(to_menu)

## 显示结算内容（一行一条）。
func show_result(lines: Array) -> void:
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	for line in lines:
		var label := Label.new()
		label.text = str(line)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_body.add_child(label)
	visible = true