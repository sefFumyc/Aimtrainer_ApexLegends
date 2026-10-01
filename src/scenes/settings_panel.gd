## 设置面板（票 03 第 4 节）：分页面组织（目标与 bot / 躲避与移动 / 画面与输入 / 计时器 / 预设）。
##
## UI 全部程序化拼，不用 `.tscn` 手写控件树。打开时暂停玩家输入。
## 一切改动走 `GameSettings.write_param`：立即生效并持久化；若当前选中预设，改动自动写回该预设。

class_name SettingsPanel
extends Control

signal changed
signal opened
signal closed

const LABEL_WIDTH := 150
const ADS_MULT_MIN := 0.1 ## 「开镜灵敏度倍率」下限（CONTEXT）
const ADS_MULT_MAX := 5.0 ## 「开镜灵敏度倍率」上限（CONTEXT）

var _layout: OptionButton
var _fire_enabled: CheckButton
var _hit_rate_row: HBoxContainer
var _hit_rate: HSlider
var _movement_mode: OptionButton
var _auto_radius: CheckButton
var _preset_select: OptionButton
var _preset_name: LineEdit

## prop → 控件：切预设后按需回灌数值（`set_value_no_signal` 避免反过来再写一遍）。
var _controls := {}

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

	var tabs := TabContainer.new()
	tabs.custom_minimum_size = Vector2(620, 560)
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(tabs)

	_build_target_page(_page(tabs, "目标与 bot"))
	_build_avoidance_page(_page(tabs, "躲避与移动"))
	_build_video_page(_page(tabs, "画面与输入"))
	_build_timer_page(_page(tabs, "计时器"))
	_build_preset_page(_page(tabs, "预设"))

# ---- 各分页 ----

func _build_target_page(page: VBoxContainer) -> void:
	_layout = OptionButton.new()
	_layout.add_item("空旷", CoverLayout.Layout.OPEN)
	_layout.add_item("少量遮挡", CoverLayout.Layout.SPARSE)
	_layout.add_item("多遮挡", CoverLayout.Layout.DENSE)
	_layout.selected = GameSettings.arena_layout
	_layout.item_selected.connect(_on_layout)
	page.add_child(_row("场地布局", _layout))

	var radius := _slider(Physique.BODY_RADIUS_MIN, Physique.BODY_RADIUS_MAX, 1.0, GameSettings.body_radius)
	radius.value_changed.connect(func(v: float) -> void: _write(&"body_radius", v))
	_controls["body_radius"] = radius
	page.add_child(_row("靶体型半径", radius))

	var range_slider := _slider(40.0, 800.0, 10.0, GameSettings.target_range)
	range_slider.value_changed.connect(func(v: float) -> void: _write(&"target_range", v))
	_controls["target_range"] = range_slider
	page.add_child(_row("目标距离", range_slider))

	_fire_enabled = _bound_check(GameSettings.bot_fire_enabled, &"bot_fire_enabled", _on_fire_enabled)
	page.add_child(_row("开火开关", _fire_enabled))

	_hit_rate = _slider(0.0, 100.0, 1.0, GameSettings.bot_hit_rate)
	_hit_rate.value_changed.connect(func(v: float) -> void: _write(&"bot_hit_rate", int(v)))
	_controls["bot_hit_rate"] = _hit_rate
	_hit_rate_row = _row("命中率", _hit_rate)
	_hit_rate_row.visible = GameSettings.bot_fire_enabled # 命中率只在开火时才有意义
	page.add_child(_hit_rate_row)

	page.add_child(_row("bot 常驻开镜", _bound_check(GameSettings.bot_ads_enabled, &"bot_ads_enabled")))
	page.add_child(_row("吸血", _bound_check(GameSettings.lifesteal_enabled, &"lifesteal_enabled")))

func _build_avoidance_page(page: VBoxContainer) -> void:
	page.add_child(_row("长横移权重", _bound_slider(0.0, 1.0, 0.05, GameSettings.bot_weight_long, &"bot_weight_long")))
	page.add_child(_row("中横移权重", _bound_slider(0.0, 1.0, 0.05, GameSettings.bot_weight_mid, &"bot_weight_mid")))
	page.add_child(_row("快横移权重", _bound_slider(0.0, 1.0, 0.05, GameSettings.bot_weight_fast, &"bot_weight_fast")))
	page.add_child(_row("模式切换下限", _bound_slider(0.2, 10.0, 0.05, GameSettings.bot_switch_min, &"bot_switch_min")))
	page.add_child(_row("模式切换上限", _bound_slider(0.2, 10.0, 0.05, GameSettings.bot_switch_max, &"bot_switch_max")))
	page.add_child(_row("躲避概率(连发)", _bound_slider(0.0, 1.0, 0.05, GameSettings.bot_dodge_auto, &"bot_dodge_auto")))
	page.add_child(_row("躲避概率(单发)", _bound_slider(0.0, 1.0, 0.05, GameSettings.bot_dodge_semi, &"bot_dodge_semi")))
	page.add_child(_row("最短躲避时间", _bound_slider(0.0, 1.0, 0.05, GameSettings.bot_dodge_min_time, &"bot_dodge_min_time")))

	_movement_mode = OptionButton.new()
	_movement_mode.add_item("保持距离", GameSettings.BotMovement.RANGE)
	_movement_mode.add_item("动态游走", GameSettings.BotMovement.WANDER)
	_movement_mode.selected = GameSettings.bot_movement_mode
	_movement_mode.item_selected.connect(_on_movement_mode)
	page.add_child(_row("移动模式", _movement_mode))

	page.add_child(_row("游走倾向", _bound_slider(0.0, 1.0, 0.05, GameSettings.bot_wander, &"bot_wander")))
	page.add_child(_row("进攻倾向", _bound_slider(0.0, 1.0, 0.05, GameSettings.bot_aggression, &"bot_aggression")))
	page.add_child(_row("撤退倾向", _bound_slider(0.0, 1.0, 0.05, GameSettings.bot_retreat, &"bot_retreat")))
	page.add_child(_row("走廊半宽", _bound_slider(0.0, 300.0, 5.0, GameSettings.bot_range_amp, &"bot_range_amp")))

func _build_video_page(page: VBoxContainer) -> void:
	page.add_child(
		_row(
			"鼠标灵敏度",
			_bound_slider(
				GameSettings.SENSITIVITY_MIN,
				GameSettings.SENSITIVITY_MAX,
				0.0001,
				GameSettings.mouse_sensitivity,
				&"mouse_sensitivity"
			)
		)
	)
	page.add_child(
		_row(
			"手柄灵敏度",
			_bound_slider(
				GameSettings.SENSITIVITY_MIN,
				GameSettings.SENSITIVITY_MAX,
				0.0001,
				GameSettings.gamepad_sensitivity,
				&"gamepad_sensitivity"
			)
		)
	)
	page.add_child(_row("开镜灵敏度倍率", _bound_slider(ADS_MULT_MIN, ADS_MULT_MAX, 0.01, GameSettings.ads_sens_mult, &"ads_sens_mult")))
	page.add_child(_row("枪口火光", _bound_check(GameSettings.muzzle_flash_enabled, &"muzzle_flash_enabled")))
	page.add_child(_row("曳光弹", _bound_check(GameSettings.tracer_enabled, &"tracer_enabled")))
	page.add_child(_row("命中提示", _bound_check(GameSettings.hit_marker_enabled, &"hit_marker_enabled")))

	var quality := OptionButton.new()
	quality.add_item("低", GameSettings.Quality.LOW)
	quality.add_item("中", GameSettings.Quality.MEDIUM)
	quality.selected = GameSettings.graphics_quality
	quality.item_selected.connect(_on_quality)
	page.add_child(_row("画面质量", quality))

func _build_timer_page(page: VBoxContainer) -> void:
	page.add_child(_row("间隔计时器", _bound_check(GameSettings.timer_enabled, &"timer_enabled", _on_timer_toggle)))
	_auto_radius = _check(GameSettings.auto_adjust_radius)
	_auto_radius.toggled.connect(func(v: bool) -> void: _write(&"auto_adjust_radius", v))
	_auto_radius.disabled = not GameSettings.timer_enabled # 前置条件 = 计时器勾选
	_controls["auto_adjust_radius"] = _auto_radius
	page.add_child(_row("自动调径", _auto_radius))
	page.add_child(_row("每段游玩秒数", _bound_int_slider(1.0, 600.0, 1.0, GameSettings.timer_play_seconds, &"timer_play_seconds")))
	page.add_child(_row("每段休息秒数", _bound_int_slider(1.0, 300.0, 1.0, GameSettings.timer_rest_seconds, &"timer_rest_seconds")))
	page.add_child(_row("重复次数", _bound_int_slider(1.0, 99.0, 1.0, GameSettings.timer_repeat, &"timer_repeat")))

func _build_preset_page(page: VBoxContainer) -> void:
	_preset_select = OptionButton.new()
	_preset_select.item_selected.connect(_on_preset_selected)
	page.add_child(_row("当前预设", _preset_select))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.add_child(_label("新建预设"))
	_preset_name = LineEdit.new()
	_preset_name.placeholder_text = "预设名字"
	_preset_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_preset_name)
	var save_button := Button.new()
	save_button.text = "存为新预设"
	save_button.pressed.connect(_on_preset_save)
	row.add_child(save_button)
	page.add_child(row)

	var erase_button := Button.new()
	erase_button.text = "删除当前预设"
	erase_button.pressed.connect(_on_preset_erase)
	page.add_child(_row("", erase_button))

	var hint := Label.new()
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.text = "选中预设后一切改动自动写回该预设（含自动调径改半径）；「不选预设」就是全局设置本身。"
	page.add_child(hint)

	_refresh_presets()

# ---- 控件工厂 ----

## 新建一个分页（`TabContainer` 的子节点名即标签名），返回其内容列。
func _page(tabs: TabContainer, title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	return box

func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size.x = LABEL_WIDTH
	return label

## 把滑块直接绑到 `GameSettings` 的同名属性上（一列十几个同类控件，逐项写回调只会重复）。
func _bound_slider(min_value: float, max_value: float, step: float, value: float, prop: StringName) -> HSlider:
	var s := _slider(min_value, max_value, step, value)
	s.value_changed.connect(func(v: float) -> void: _write(prop, v))
	_controls[String(prop)] = s
	return s

## 整型设置项的滑块（写回时取整，避免 float 写进 int 属性）。
func _bound_int_slider(min_value: float, max_value: float, step: float, value: float, prop: StringName) -> HSlider:
	var s := _slider(min_value, max_value, step, value)
	s.value_changed.connect(func(v: float) -> void: _write(prop, int(v)))
	_controls[String(prop)] = s
	return s

func _bound_check(on: bool, prop: StringName, extra: Callable = Callable()) -> CheckButton:
	var c := _check(on)
	c.toggled.connect(func(v: bool) -> void:
		_write(prop, v)
		if extra.is_valid():
			extra.call(v)
	)
	_controls[String(prop)] = c
	return c

func _row(label_text: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	if not label_text.is_empty():
		row.add_child(_label(label_text))
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return row

func _slider(min_value: float, max_value: float, step: float, value: float) -> HSlider:
	var s := HSlider.new()
	s.min_value = min_value
	s.max_value = max_value
	s.step = step
	s.value = value
	s.custom_minimum_size.x = 240
	return s

func _check(on: bool) -> CheckButton:
	var c := CheckButton.new()
	c.button_pressed = on
	return c

# ---- 写回与刷新 ----

## 一切改动的落点：写进设置单例（自动落盘 + 写回选中预设）→ 通知场景。
func _write(prop: StringName, value: Variant) -> void:
	GameSettings.write_param(prop, value)
	changed.emit()

## 切预设后把各控件回灌成全局设置的当前值（不触发写回）。
func _sync_controls() -> void:
	for prop in _controls.keys():
		var control: Control = _controls[prop]
		var value: Variant = GameSettings.get(prop)
		if control is HSlider:
			(control as HSlider).set_value_no_signal(float(value))
		elif control is CheckButton:
			(control as CheckButton).set_value_no_signal(bool(value))
	_layout.selected = GameSettings.arena_layout
	_movement_mode.selected = GameSettings.bot_movement_mode
	_hit_rate_row.visible = GameSettings.bot_fire_enabled
	_auto_radius.disabled = not GameSettings.timer_enabled

func _on_layout(index: int) -> void:
	_write(&"arena_layout", _layout.get_item_id(index))

func _on_movement_mode(index: int) -> void:
	_write(&"bot_movement_mode", _movement_mode.get_item_id(index))

func _on_quality(index: int) -> void:
	_write(&"graphics_quality", GameSettings.Quality.LOW if index == 0 else GameSettings.Quality.MEDIUM)

func _on_fire_enabled(on: bool) -> void:
	_hit_rate_row.visible = on

func _on_timer_toggle(on: bool) -> void:
	_auto_radius.disabled = not on

# ---- 预设页 ----

func _refresh_presets() -> void:
	_preset_select.clear()
	_preset_select.add_item("不选预设（全局设置）", 0)
	var names := GameSettings.preset_names()
	for i in names.size():
		_preset_select.add_item(names[i], i + 1)
	var active := GameSettings.active_preset()
	_preset_select.selected = 0
	for i in names.size():
		if names[i] == active:
			_preset_select.selected = i + 1
			break

func _on_preset_selected(index: int) -> void:
	var id := _preset_select.get_item_id(index)
	var names := GameSettings.preset_names()
	GameSettings.select_preset("" if id <= 0 else names[id - 1])
	_sync_controls()
	_refresh_presets()
	changed.emit()

func _on_preset_save() -> void:
	if GameSettings.save_preset(_preset_name.text):
		_preset_name.text = ""
	_refresh_presets()
	changed.emit()

func _on_preset_erase() -> void:
	var active := GameSettings.active_preset()
	if active.is_empty():
		return
	GameSettings.erase_preset(active)
	_refresh_presets()
	changed.emit()