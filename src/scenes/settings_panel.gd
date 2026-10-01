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
var _fire_enabled: CheckButton
var _hit_rate_row: HBoxContainer
var _hit_rate: HSlider
var _movement_mode: OptionButton

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

	# 设置项会随迭代增多，内容超出屏幕时靠滚动兜住（分页见后续切片）。
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(520, 620)
	margin.add_child(scroll)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)

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
	box.add_child(_row("目标距离", _target_range))

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

	box.add_child(_heading("靶子开火"))
	_fire_enabled = _check(GameSettings.bot_fire_enabled)
	_fire_enabled.toggled.connect(_on_fire_enabled)
	box.add_child(_row("开火开关", _fire_enabled))
	_hit_rate = _slider(0.0, 100.0, 1.0, GameSettings.bot_hit_rate)
	_hit_rate.value_changed.connect(_on_hit_rate)
	_hit_rate_row = _row("命中率", _hit_rate)
	_hit_rate_row.visible = GameSettings.bot_fire_enabled # 命中率只在开火时才有意义
	box.add_child(_hit_rate_row)
	box.add_child(_row("bot 常驻开镜", _bound_check(GameSettings.bot_ads_enabled, &"bot_ads_enabled")))

	box.add_child(_heading("躲避与移动"))
	box.add_child(_row("长横移权重", _bound_slider(0.0, 1.0, 0.05, GameSettings.bot_weight_long, &"bot_weight_long")))
	box.add_child(_row("中横移权重", _bound_slider(0.0, 1.0, 0.05, GameSettings.bot_weight_mid, &"bot_weight_mid")))
	box.add_child(_row("快横移权重", _bound_slider(0.0, 1.0, 0.05, GameSettings.bot_weight_fast, &"bot_weight_fast")))
	box.add_child(_row("模式切换下限", _bound_slider(0.2, 10.0, 0.05, GameSettings.bot_switch_min, &"bot_switch_min")))
	box.add_child(_row("模式切换上限", _bound_slider(0.2, 10.0, 0.05, GameSettings.bot_switch_max, &"bot_switch_max")))
	box.add_child(_row("躲避概率(连发)", _bound_slider(0.0, 1.0, 0.05, GameSettings.bot_dodge_auto, &"bot_dodge_auto")))
	box.add_child(_row("躲避概率(单发)", _bound_slider(0.0, 1.0, 0.05, GameSettings.bot_dodge_semi, &"bot_dodge_semi")))
	box.add_child(_row("最短躲避时间", _bound_slider(0.0, 1.0, 0.05, GameSettings.bot_dodge_min_time, &"bot_dodge_min_time")))
	_movement_mode = OptionButton.new()
	_movement_mode.add_item("保持距离", GameSettings.BotMovement.RANGE)
	_movement_mode.add_item("动态游走", GameSettings.BotMovement.WANDER)
	_movement_mode.selected = GameSettings.bot_movement_mode
	_movement_mode.item_selected.connect(_on_movement_mode)
	box.add_child(_row("移动模式", _movement_mode))
	box.add_child(_row("游走倾向", _bound_slider(0.0, 1.0, 0.05, GameSettings.bot_wander, &"bot_wander")))
	box.add_child(_row("进攻倾向", _bound_slider(0.0, 1.0, 0.05, GameSettings.bot_aggression, &"bot_aggression")))
	box.add_child(_row("撤退倾向", _bound_slider(0.0, 1.0, 0.05, GameSettings.bot_retreat, &"bot_retreat")))
	box.add_child(_row("走廊半宽", _bound_slider(0.0, 300.0, 5.0, GameSettings.bot_range_amp, &"bot_range_amp")))

func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 15)
	return label

## 把滑块直接绑到 `GameSettings` 的同名属性上（一列十几个同类控件，逐项写回调只会重复）。
func _bound_slider(min_value: float, max_value: float, step: float, value: float, prop: StringName) -> HSlider:
	var s := _slider(min_value, max_value, step, value)
	s.value_changed.connect(func(v: float) -> void: _write(prop, v))
	return s

func _bound_check(on: bool, prop: StringName) -> CheckButton:
	var c := _check(on)
	c.toggled.connect(func(v: bool) -> void: _write(prop, v))
	return c

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

## `_bound_slider` / `_bound_check` 的落点：写进设置单例 → 落盘 → 通知。
func _write(prop: StringName, value: Variant) -> void:
	GameSettings.set(prop, value)
	_persist()

func _on_fire_enabled(on: bool) -> void:
	GameSettings.bot_fire_enabled = on
	_hit_rate_row.visible = on
	_persist()

func _on_hit_rate(value: float) -> void:
	GameSettings.bot_hit_rate = int(value)
	_persist()

func _on_movement_mode(index: int) -> void:
	GameSettings.bot_movement_mode = _movement_mode.get_item_id(index) as GameSettings.BotMovement
	_persist()

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
