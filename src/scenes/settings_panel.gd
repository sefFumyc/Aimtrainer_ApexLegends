## 设置面板（票 03 第 4 节）：分页面组织（目标与 bot / 躲避与移动 / 画面与输入 / 计时器 / 预设）。
##
## UI 全部程序化拼，不用 `.tscn` 手写控件树。打开时暂停玩家输入。
## 一切改动走 `GameSettings.write_param`：立即生效并持久化；若当前选中预设，改动自动写回该预设。

class_name SettingsPanel
extends Control

signal changed
signal opened
signal closed
## 「全屏宽高比」切档（ADR-0029）：main 据此在独占全屏状态下立即重设分辨率。
signal fullscreen_aspect_changed

const LABEL_WIDTH := 150
const ADS_MULT_MIN := 0.1 ## 「开镜灵敏度倍率」下限（CONTEXT）
const ADS_MULT_MAX := 5.0 ## 「开镜灵敏度倍率」上限（CONTEXT）

## 深色高对比主题（票 05 第 6 项）：半透明深面板 + 纯白文字 + 青绿高亮、禁用变灰。
const PANEL_BG := Color(0.07, 0.08, 0.10, 0.90)
const FIELD_BG := Color(0.13, 0.15, 0.18, 0.95)
const TEXT := Color(1.0, 1.0, 1.0)
const TEXT_DIM := Color(0.45, 0.48, 0.52)
const ACCENT := Color(0.20, 0.85, 0.70) ## 青绿：选中页签 / 聚焦边框 / 滑条已选段

var _layout: OptionButton
var _fire_enabled: CheckButton
var _hit_rate_row: HBoxContainer
var _hit_rate: HSlider
var _movement_mode: OptionButton
var _auto_radius: CheckButton
var _preset_select: OptionButton
var _preset_name: LineEdit
var _slide_attack_check: CheckButton
var _slide_respawn_check: CheckButton
var _slide_jump_check: CheckButton
var _slide_jump_prob_row: HBoxContainer
var _jump_check: CheckButton
var _jump_min_slider: HSlider
var _jump_max_slider: HSlider
var _ras_prob_slider: HSlider
## 「键位」页（ADR-0025）：动作 → 显示按钮；正在采集改键的动作（空 = 非采集态）。
var _bind_buttons := {}
var _capturing_action := StringName("")

## prop → 控件：切预设后按需回灌数值（`set_value_no_signal` 避免反过来再写一遍）。
var _controls := {}

## 「全屏宽高比」（ADR-0029）：档位下拉框 + 只读换算信息行。
var _aspect_select: OptionButton
var _aspect_info: Label

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
	panel.theme = _build_theme()
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
	_build_recoil_page(_page(tabs, "后坐力"))
	_build_bindings_page(_page(tabs, "键位"))
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

	var range_slider := _slider(40.0, GameSettings.TARGET_RANGE_MAX, 10.0, GameSettings.target_range)
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

	# bot 滑铲（票 09）：两个滑铲开关 + 铲跳（受前置条件门控）+ 铲跳概率。
	_slide_attack_check = _bound_check(
		GameSettings.bot_attack_slide_enabled, &"bot_attack_slide_enabled", _sync_slide_interlock
	)
	_slide_respawn_check = _bound_check(
		GameSettings.bot_respawn_slide_enabled, &"bot_respawn_slide_enabled", _sync_slide_interlock
	)
	_slide_jump_check = _bound_check(
		GameSettings.bot_slide_jump_enabled, &"bot_slide_jump_enabled", _sync_slide_interlock
	)
	page.add_child(_row("攻击滑铲", _slide_attack_check))
	page.add_child(_row("重生滑铲", _slide_respawn_check))
	page.add_child(_row("铲跳", _slide_jump_check))
	_slide_jump_prob_row = _row(
		"铲跳概率", _bound_slider(0.0, 1.0, 0.05, GameSettings.bot_slide_jump_prob, &"bot_slide_jump_prob")
	)
	page.add_child(_slide_jump_prob_row)
	_sync_slide_interlock()

	# bot 跳跃（票 11 / ADR-0023）：开关 + 「跳跃间隔」双滑条 + 「RAS 概率」（票 13 / ADR-0028）；
	# 间隔下限 0.5 是故意的——压进滞空（约 0.72s）以下就是落地即跳的连跳 bot。
	# 关闭时两条间隔滑条与 RAS 概率（含数值框）置灰。
	_jump_check = _bound_check(GameSettings.bot_jump_enabled, &"bot_jump_enabled", _sync_jump_grey)
	_jump_min_slider = _bound_slider(
		GameSettings.JUMP_INTERVAL_MIN, GameSettings.JUMP_INTERVAL_MAX, 0.1,
		GameSettings.bot_jump_min, &"bot_jump_min"
	)
	_jump_max_slider = _bound_slider(
		GameSettings.JUMP_INTERVAL_MIN, GameSettings.JUMP_INTERVAL_MAX, 0.1,
		GameSettings.bot_jump_max, &"bot_jump_max"
	)
	_ras_prob_slider = _bound_slider(
		0.0, 1.0, 0.05, GameSettings.bot_jump_ras_prob, &"bot_jump_ras_prob"
	)
	page.add_child(_row("bot 跳跃", _jump_check))
	page.add_child(_row("跳跃间隔下限", _jump_min_slider))
	page.add_child(_row("跳跃间隔上限", _jump_max_slider))
	page.add_child(_row("RAS 概率", _ras_prob_slider))
	_sync_jump_grey()

func _build_video_page(page: VBoxContainer) -> void:
	page.add_child(
		_row(
			"鼠标灵敏度",
			_bound_slider(
				InputSensitivity.MOUSE_SENSITIVITY_MIN,
				InputSensitivity.MOUSE_SENSITIVITY_MAX,
				0.1,
				GameSettings.mouse_sensitivity,
				&"mouse_sensitivity"
			)
		)
	)
	# 手柄灵敏度同样是倍率（0.2–5.0，票 05 起鼠标与它同量纲同区间），步进 0.1。
	page.add_child(
		_row(
			"手柄灵敏度",
			_bound_slider(
				GameSettings.GAMEPAD_SENSITIVITY_MIN,
				GameSettings.GAMEPAD_SENSITIVITY_MAX,
				0.1,
				GameSettings.gamepad_sensitivity,
				&"gamepad_sensitivity"
			)
		)
	)
	page.add_child(_row("开镜灵敏度倍率", _bound_slider(ADS_MULT_MIN, ADS_MULT_MAX, 0.01, GameSettings.ads_sens_mult, &"ads_sens_mult")))
	page.add_child(_row("枪口火光", _bound_check(GameSettings.muzzle_flash_enabled, &"muzzle_flash_enabled")))
	page.add_child(_row("曳光弹", _bound_check(GameSettings.tracer_enabled, &"tracer_enabled")))
	page.add_child(_row("命中提示", _bound_check(GameSettings.hit_marker_enabled, &"hit_marker_enabled")))
	page.add_child(_row("受击红屏", _bound_check(GameSettings.hit_flash_enabled, &"hit_flash_enabled")))

	var quality := OptionButton.new()
	quality.add_item("低", GameSettings.Quality.LOW)
	quality.add_item("中", GameSettings.Quality.MEDIUM)
	quality.selected = GameSettings.graphics_quality
	quality.item_selected.connect(_on_quality)
	page.add_child(_row("画面质量", quality))

	# 「全屏宽高比」（ADR-0029）：只作用于 F11 独占全屏，16:9 恰为桌面原生、
	# 16:10 窄于屏幕由驱动拉伸铺满（CS/Apex stretched 语义）；信息行随档位即时换算。
	_aspect_select = OptionButton.new()
	_aspect_select.add_item("16:9", GameSettings.FULLSCREEN_ASPECT_16_9)
	_aspect_select.add_item("16:10", GameSettings.FULLSCREEN_ASPECT_16_10)
	_aspect_select.selected = _aspect_select.get_item_index(GameSettings.fullscreen_aspect)
	_aspect_select.item_selected.connect(_on_fullscreen_aspect)
	page.add_child(_row("全屏宽高比", _aspect_select))
	_aspect_info = _label(_fullscreen_aspect_text())
	page.add_child(_aspect_info)

## 「后坐力强度」分页（票 08 / ADR-0026）：六通道倍率滑条平铺，倍率量纲 0–2、步进 0.01、
## 两位小数；0 = 关掉该通道抖动。出厂默认全部为玩家实测定稿手感（ADR-0022 第二次烘焙）。
## 个人手感偏好，随 GameSettings 即改即存、不进预设。
func _build_recoil_page(page: VBoxContainer) -> void:
	var lo: float = GameSettings.RECOIL_MULT_MIN
	var hi: float = GameSettings.RECOIL_MULT_MAX
	page.add_child(_row("步枪枪械抖动", _bound_slider(lo, hi, 0.01, GameSettings.recoil_gun_rifle, &"recoil_gun_rifle")))
	page.add_child(_row("手枪枪械抖动", _bound_slider(lo, hi, 0.01, GameSettings.recoil_gun_pistol, &"recoil_gun_pistol")))
	page.add_child(_row("冲锋枪枪械抖动", _bound_slider(lo, hi, 0.01, GameSettings.recoil_gun_burst, &"recoil_gun_burst")))
	page.add_child(_row("步枪相机抖动", _bound_slider(lo, hi, 0.01, GameSettings.recoil_cam_rifle, &"recoil_cam_rifle")))
	page.add_child(_row("手枪相机抖动", _bound_slider(lo, hi, 0.01, GameSettings.recoil_cam_pistol, &"recoil_cam_pistol")))
	page.add_child(_row("冲锋枪相机抖动", _bound_slider(lo, hi, 0.01, GameSettings.recoil_cam_burst, &"recoil_cam_burst")))

	var hint := Label.new()
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.text = "枪械抖动 = 枪模后坐与上抬的幅度倍率；相机抖动 = 视角踢动与水平甩动的幅度倍率。0 为完全关闭，出厂默认即实测定稿手感；对下一发立即生效。"
	page.add_child(hint)

## 「键位」分页（ADR-0025）：六个动作各一行（当前键友好名即按钮），点击进入采集态——
## 按下手柄按键或扳机完成绑定；单一绑定模型，冲突抢占；页级恢复默认。键鼠绑定固定不可改。
func _build_bindings_page(page: VBoxContainer) -> void:
	for action in GamepadBindings.ACTIONS:
		var btn := Button.new()
		btn.pressed.connect(_on_bind_pressed.bind(action))
		_bind_buttons[action] = btn
		page.add_child(_row(GamepadBindings.LABELS[action], btn))

	var reset := Button.new()
	reset.text = "恢复默认手柄键位"
	reset.pressed.connect(_on_bindings_reset)
	page.add_child(_row("", reset))

	var hint := Label.new()
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.text = "点击一项后按下手柄按键或扳机完成绑定；一个键只归一个动作，新绑定会把旧动作上的同键抢占为「未绑定」。Esc 或再点一次取消。键鼠键位固定；移动与视角走摇杆，无键位可言。"
	page.add_child(hint)

	_refresh_bindings()

func _refresh_bindings() -> void:
	for action in _bind_buttons:
		var btn: Button = _bind_buttons[action]
		btn.text = (
			"按手柄任意键…（Esc 取消）"
			if action == _capturing_action
			else GamepadBindings.friendly(GameSettings.gamepad_binding_of(action))
		)

func _on_bind_pressed(action: StringName) -> void:
	_capturing_action = StringName("") if _capturing_action == action else action
	_refresh_bindings()

func _on_bindings_reset() -> void:
	_capturing_action = StringName("")
	GameSettings.reset_gamepad_bindings()
	_refresh_bindings()

## 是否处于改键采集态：采集期间主场景热键全部让位（main._tick_hotkeys 据此短路），
## 否则按 Back/Tab/Esc 改键会同时触发「开关设置 / 结束回合」。
func is_capturing() -> bool:
	return _capturing_action != StringName("")

## 改键采集（ADR-0025）：`_input` 先于 GUI 拿到事件并吞掉，防止手柄键顺手触发聚焦中的
## 控件。手柄按键与过阈值（0.6）的轴算有效绑定；键盘按下事件一律吞掉——Esc 是取消，
## 其余键（含 Space/Enter）不能在采集态重触发聚焦中的改键按钮；键鼠点击不劫持（点别处可换目标）。
func _input(event: InputEvent) -> void:
	if not is_capturing():
		return
	if not visible:
		_capturing_action = StringName("")
		return
	var desc := GamepadBindings.from_event(event)
	var key := event as InputEventKey
	if desc.is_empty() and key == null:
		return
	get_viewport().set_input_as_handled()
	if key != null:
		if key.pressed and key.keycode == KEY_ESCAPE:
			_capturing_action = StringName("")
	elif not desc.is_empty():
		var action := _capturing_action
		_capturing_action = StringName("")
		GameSettings.set_gamepad_binding(action, desc)
	_refresh_bindings()

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
	if control is HSlider:
		# 滑条一律配数值框（票 05 第 2 项）：右侧两位小数常显，也可直接键入。
		var pair := HBoxContainer.new()
		pair.add_theme_constant_override("separation", 8)
		pair.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pair.add_child(control)
		pair.add_child(_value_box(control as HSlider))
		row.add_child(pair)
	else:
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

## 滑条旁的数值框（票 05 第 2 项）：常显两位小数；键入回车或失焦都生效，越界值钳到边界、
## 非法文本回落滑条当前值。通过 `set_meta` 挂回滑条，`_sync_controls` 据此在切预设后一并刷新文本。
func _value_box(s: HSlider) -> LineEdit:
	var edit := LineEdit.new()
	edit.custom_minimum_size.x = 64
	edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	edit.text = "%.2f" % s.value
	var apply := func(text: String) -> void:
		if text.is_valid_float():
			s.value = clampf(text.to_float(), s.min_value, s.max_value) # 走 value_changed → 既有写回链
		edit.text = "%.2f" % s.value
	edit.text_submitted.connect(apply)
	edit.focus_exited.connect(func() -> void: apply.call(edit.text))
	s.value_changed.connect(func(v: float) -> void: edit.text = "%.2f" % v)
	s.set_meta("value_edit", edit)
	return edit

## 深色高对比主题（票 05 第 6 项）：覆盖面板 / 输入框 / 页签 / 下拉列表 / 滑条的底色与文字色。
func _build_theme() -> Theme:
	var t := Theme.new()

	var panel := StyleBoxFlat.new()
	panel.bg_color = PANEL_BG
	panel.set_corner_radius_all(10)
	t.set_stylebox("panel", "PanelContainer", panel)

	# 文字：常规纯白、禁用变灰。
	for type in ["Label", "CheckButton", "LineEdit", "OptionButton", "Button", "PopupMenu"]:
		t.set_color("font_color", type, TEXT)
		t.set_color("font_disabled_color", type, TEXT_DIM)
	t.set_color("font_placeholder_color", "LineEdit", TEXT_DIM)
	t.set_color("font_unselected_color", "TabContainer", TEXT_DIM)
	t.set_color("font_selected_color", "TabContainer", TEXT)

	# 开关激活态（票 05 第 6 项）：选中青绿、未选灰，禁用沿用上面的灰字。
	t.set_color("icon_normal_color", "CheckButton", TEXT_DIM)
	t.set_color("icon_pressed_color", "CheckButton", ACCENT)

	# 输入框 / 按钮：深底，聚焦或悬停时描青绿边。
	var field := StyleBoxFlat.new()
	field.bg_color = FIELD_BG
	field.set_corner_radius_all(6)
	field.set_content_margin_all(6)
	var field_focus := field.duplicate() as StyleBoxFlat
	field_focus.set_border_width_all(2)
	field_focus.border_color = ACCENT
	for type in ["LineEdit", "OptionButton", "Button"]:
		t.set_stylebox("normal", type, field)
		t.set_stylebox("focus", type, field_focus)
	t.set_stylebox("hover", "OptionButton", field_focus)
	t.set_stylebox("hover", "Button", field_focus)
	t.set_stylebox("pressed", "OptionButton", field_focus)
	t.set_stylebox("pressed", "Button", field_focus)

	# 下拉列表：深底白字，悬停项青绿晕染。
	var popup := StyleBoxFlat.new()
	popup.bg_color = Color(0.10, 0.11, 0.14, 0.97)
	popup.set_corner_radius_all(6)
	popup.set_content_margin_all(6)
	t.set_stylebox("panel", "PopupMenu", popup)
	var item_hover := StyleBoxFlat.new()
	item_hover.bg_color = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.18)
	item_hover.set_corner_radius_all(4)
	t.set_stylebox("hover", "PopupMenu", item_hover)

	# 页签：选中页白字 + 青绿顶边，未选中灰字。
	var tab_sel := StyleBoxFlat.new()
	tab_sel.bg_color = FIELD_BG
	tab_sel.set_content_margin_all(8)
	tab_sel.border_width_top = 2
	tab_sel.border_color = ACCENT
	t.set_stylebox("tab_selected", "TabContainer", tab_sel)
	var tab_un := tab_sel.duplicate() as StyleBoxFlat
	tab_un.border_width_top = 0
	tab_un.bg_color = Color(0.10, 0.11, 0.13)
	t.set_stylebox("tab_unselected", "TabContainer", tab_un)
	var tab_panel := StyleBoxFlat.new()
	tab_panel.bg_color = Color(0.10, 0.11, 0.13, 0.92)
	tab_panel.set_content_margin_all(10)
	t.set_stylebox("panel", "TabContainer", tab_panel)

	# 滑条：深灰轨道 + 青绿已选段（抓握钮沿用默认白圈图标，深底上够醒目）。
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.30, 0.32, 0.36)
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	track.set_corner_radius_all(3)
	t.set_stylebox("slider", "HSlider", track)
	var filled := StyleBoxFlat.new()
	filled.bg_color = ACCENT
	filled.set_corner_radius_all(3)
	t.set_stylebox("grabber_area", "HSlider", filled)
	t.set_stylebox("grabber_area_highlight", "HSlider", filled)
	return t

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
			var s := control as HSlider
			s.set_value_no_signal(float(value))
			(s.get_meta("value_edit") as LineEdit).text = "%.2f" % float(value)
		elif control is CheckButton:
			(control as CheckButton).set_value_no_signal(bool(value))
	_layout.selected = GameSettings.arena_layout
	_movement_mode.selected = GameSettings.bot_movement_mode
	_hit_rate_row.visible = GameSettings.bot_fire_enabled
	_auto_radius.disabled = not GameSettings.timer_enabled
	_sync_slide_interlock()
	_sync_jump_grey()

## 滑铲互锁（ADR-0016）：两个滑铲开关都没勾 → 铲跳置灰、概率行隐藏；
## 任一滑铲勾上 → 「bot 常驻开镜」置灰并自动取消（开镜封速 130 < 滑铲门槛 200，
## 两者同时开会把注入滑铲废掉）。感知层另有同一道保险（main._build_perception）。
## `_bound_check` 的开关回调会传「勾选状态 bool」——必须收下（可选），否则参数数量不匹配
## 会抛运行时错误并中断互锁：铲跳勾选框卡死置灰、概率滑条永不显示（票 09 实测 bug，ADR-0017）。
func _sync_slide_interlock(_v: bool = false) -> void:
	var any := GameSettings.bot_slide_any_enabled()
	_slide_jump_check.disabled = not any
	_slide_jump_prob_row.visible = any and GameSettings.bot_slide_jump_enabled
	var ads_check := _controls["bot_ads_enabled"] as CheckButton
	ads_check.disabled = any
	if any and ads_check.button_pressed:
		ads_check.set_pressed_no_signal(false)
		GameSettings.write_param(&"bot_ads_enabled", false)

## 「bot 跳跃」置灰（票 11 / 票 13）：开关关闭时两条间隔滑条与 RAS 概率滑条（含数值框）不可用。
## `_bound_check` 回调同样会传勾选状态 bool——签名收下（票 09 同款教训）。
func _sync_jump_grey(_v: bool = false) -> void:
	var on := GameSettings.bot_jump_enabled
	_jump_min_slider.disabled = not on
	_jump_max_slider.disabled = not on
	_ras_prob_slider.disabled = not on
	(_jump_min_slider.get_meta("value_edit") as LineEdit).editable = on
	(_jump_max_slider.get_meta("value_edit") as LineEdit).editable = on
	(_ras_prob_slider.get_meta("value_edit") as LineEdit).editable = on

func _on_layout(index: int) -> void:
	_write(&"arena_layout", _layout.get_item_id(index))

func _on_movement_mode(index: int) -> void:
	_write(&"bot_movement_mode", _movement_mode.get_item_id(index))

func _on_quality(index: int) -> void:
	_write(&"graphics_quality", GameSettings.Quality.LOW if index == 0 else GameSettings.Quality.MEDIUM)

## 「全屏宽高比」切档（ADR-0029）：写设置（即改即存、不在预设 FIELDS 内故无写回）→
## 刷新信息行 → 通知 main（全屏中立即生效）。
func _on_fullscreen_aspect(index: int) -> void:
	_write(&"fullscreen_aspect", _aspect_select.get_item_id(index))
	_aspect_info.text = _fullscreen_aspect_text()
	fullscreen_aspect_changed.emit()

## 信息行文本：桌面分辨率 → 全屏渲染分辨率（拉伸铺满；与桌面相等即原生直渲）。
func _fullscreen_aspect_text() -> String:
	var screen := DisplayServer.screen_get_size(DisplayServer.window_get_current_screen())
	var full := GameSettings.fullscreen_resolution(screen, GameSettings.fullscreen_aspect)
	if full == screen:
		return "桌面 %d×%d（原生 16:9 直渲）" % [screen.x, screen.y]
	return "桌面 %d×%d → 渲染 %d×%d（横向拉伸铺满）" % [screen.x, screen.y, full.x, full.y]

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