## 极简设置面板（票 01 验收条件 7 / 10）：改完立刻生效并写回 `user://settings.cfg`。
##
## UI 全部程序化拼，不用 `.tscn` 手写控件树。打开时暂停玩家输入。

class_name SettingsPanel
extends Control

signal changed
signal opened
signal closed

const LABEL_WIDTH := 150
const ADS_MULT_MIN := 0.1 ## 「开镜灵敏度倍率」下限（CONTEXT）
const ADS_MULT_MAX := 5.0 ## 「开镜灵敏度倍率」上限（CONTEXT）

var _layout: OptionButton
var _body_radius: HSlider
var _target_range: HSlider
var _sensitivity: HSlider
var _ads_mult: HSlider
var _muzzle: CheckButton
var _tracer: CheckButton
var _marker_enabled: CheckButton

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	_build()

## 打开 / 关闭；返回打开后的状态。
func toggle() -> bool:
	visible = not visible
	if visible:
		opened.emit()
	else:
		closed.emit()
	return visible

func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(panel)

	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 18)
	panel.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)

	var title := Label.new()
	title.text = "设置（Tab 开关，改动即时生效并保存）"
	box.add_child(title)

	_layout = OptionButton.new()
	_layout.add_item("空旷", CoverLayout.Layout.OPEN)
	_layout.add_item("少量遮挡", CoverLayout.Layout.SPARSE)
	_layout.add_item("多遮挡", CoverLayout.Layout.DENSE)
	_layout.selected = GameSettings.arena_layout
	_layout.item_selected.connect(_on_layout)
	box.add_child(_row("场地布局", _layout))

	_body_radius = _slider(Physique.BODY_RADIUS_MIN, Physique.BODY_RADIUS_MAX, 1.0, GameSettings.body_radius)
	_body_radius.value_changed.connect(_on_body_radius)
	box.add_child(_row("靶体型半径", _body_radius))

	_target_range = _slider(40.0, 800.0, 10.0, GameSettings.target_range)
	_target_range.value_changed.connect(_on_target_range)
	box.add_child(_row("靶刷新距离", _target_range))

	_sensitivity = _slider(0.0005, 0.006, 0.0001, GameSettings.mouse_sensitivity)
	_sensitivity.value_changed.connect(_on_sensitivity)
	box.add_child(_row("鼠标灵敏度", _sensitivity))

	_ads_mult = _slider(ADS_MULT_MIN, ADS_MULT_MAX, 0.01, GameSettings.ads_sens_mult)
	_ads_mult.value_changed.connect(_on_ads_mult)
	box.add_child(_row("开镜灵敏度倍率", _ads_mult))

	_muzzle = _check(GameSettings.muzzle_flash_enabled)
	_muzzle.toggled.connect(_on_muzzle)
	box.add_child(_row("枪口火光", _muzzle))

	_tracer = _check(GameSettings.tracer_enabled)
	_tracer.toggled.connect(_on_tracer)
	box.add_child(_row("曳光弹", _tracer))

	_marker_enabled = _check(GameSettings.hit_marker_enabled)
	_marker_enabled.toggled.connect(_on_marker)
	box.add_child(_row("命中提示", _marker_enabled))

func _row(label_text: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = LABEL_WIDTH
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return row

func _slider(min_value: float, max_value: float, step: float, value: float) -> HSlider:
	var s := HSlider.new()
	s.min_value = min_value
	s.max_value = max_value
	s.step = step
	s.value = value
	s.custom_minimum_size.x = 220
	return s

func _check(on: bool) -> CheckButton:
	var c := CheckButton.new()
	c.button_pressed = on
	return c

# ---- 回调：先写进设置单例、再落盘、再通知 ----

func _persist() -> void:
	GameSettings.save_settings()
	changed.emit()

func _on_layout(index: int) -> void:
	GameSettings.arena_layout = _layout.get_item_id(index) as GameSettings.Layout
	_persist()

func _on_body_radius(value: float) -> void:
	GameSettings.body_radius = value
	_persist()

func _on_target_range(value: float) -> void:
	GameSettings.target_range = value
	_persist()

func _on_sensitivity(value: float) -> void:
	GameSettings.mouse_sensitivity = value
	_persist()

func _on_ads_mult(value: float) -> void:
	GameSettings.ads_sens_mult = value
	_persist()

func _on_muzzle(on: bool) -> void:
	GameSettings.muzzle_flash_enabled = on
	_persist()

func _on_tracer(on: bool) -> void:
	GameSettings.tracer_enabled = on
	_persist()

func _on_marker(on: bool) -> void:
	GameSettings.hit_marker_enabled = on
	_persist()
