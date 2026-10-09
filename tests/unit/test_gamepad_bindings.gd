## GamepadBindings（ADR-0025）行为测试：描述符编码 / 友好名 / 抢占 / InputMap 回灌 / 配置读写。

extends GutTest

func test_defaults_cover_all_actions() -> void:
	var d := GamepadBindings.defaults()
	for action in GamepadBindings.ACTIONS:
		assert_true(d.has(action), "默认表必须覆盖动作 " + String(action))
		assert_false(String(d[action]).is_empty(), "出厂默认不允许未绑定：" + String(action))
	assert_eq(d[&"jump"], "a5:1")
	assert_eq(d[&"crouch"], "a4:1")
	assert_eq(d[&"fire"], "b10")
	assert_eq(d[&"ads"], "b9")
	assert_eq(d[&"weapon_switch"], "b3")
	assert_eq(d[&"toggle_settings"], "b4")

func test_from_event_button() -> void:
	var press := InputEventJoypadButton.new()
	press.button_index = 0
	press.pressed = true
	assert_eq(GamepadBindings.from_event(press), "b0")
	press.pressed = false
	assert_eq(GamepadBindings.from_event(press), "") # 松开事件不算绑定

func test_from_event_axis_threshold_and_sign() -> void:
	var motion := InputEventJoypadMotion.new() # 轴事件没有 pressed 属性，只按阈值判有效
	motion.axis = 5
	motion.axis_value = 0.9
	assert_eq(GamepadBindings.from_event(motion), "a5:1")
	motion.axis = 1
	motion.axis_value = -0.9
	assert_eq(GamepadBindings.from_event(motion), "a1:-1")
	motion.axis_value = 0.3 # 低于采集阈值：轻晃不误采
	assert_eq(GamepadBindings.from_event(motion), "")

func test_from_event_ignores_non_joypad() -> void:
	var key := InputEventKey.new()
	key.keycode = KEY_ESCAPE
	key.pressed = true
	assert_eq(GamepadBindings.from_event(key), "")
	assert_eq(GamepadBindings.from_event(InputEventMouseButton.new()), "")

func test_friendly_names() -> void:
	assert_eq(GamepadBindings.friendly("b0"), "A")
	assert_eq(GamepadBindings.friendly("b10"), "RB")
	assert_eq(GamepadBindings.friendly("a5:1"), "RT")
	assert_eq(GamepadBindings.friendly("a4:1"), "LT")
	assert_eq(GamepadBindings.friendly("a1:-1"), "轴1−")
	assert_eq(GamepadBindings.friendly(""), "未绑定")
	assert_eq(GamepadBindings.friendly("b99"), "按钮99")

func test_event_for_roundtrip() -> void:
	var btn := GamepadBindings.event_for("b3") as InputEventJoypadButton
	assert_not_null(btn)
	assert_eq(btn.button_index, 3)
	var axis := GamepadBindings.event_for("a4:1") as InputEventJoypadMotion
	assert_not_null(axis)
	assert_eq(axis.axis, 4)
	assert_eq(axis.axis_value, 1.0)
	var neg := GamepadBindings.event_for("a1:-1") as InputEventJoypadMotion
	assert_eq(neg.axis_value, -1.0)
	assert_null(GamepadBindings.event_for(""))
	assert_null(GamepadBindings.event_for("garbage"))

func test_steal_clears_conflict_only() -> void:
	var b := GamepadBindings.defaults()
	GamepadBindings.steal(b, &"jump", "b10")
	assert_eq(String(b[&"fire"]), "") # RB 被跳跃抢占 → 开火未绑定
	assert_eq(String(b[&"ads"]), "b9") # 其他动作不受牵连
	GamepadBindings.steal(b, &"crouch", "") # 未绑定不抢占
	assert_eq(String(b[&"fire"]), "")

func test_apply_all_preserves_keyboard_and_replaces_pad() -> void:
	if not InputMap.has_action("jump"):
		return # 无 InputMap 的极端环境跳过
	GamepadBindings.apply_all({&"jump": "b2"})
	var has_key := false
	var has_new_pad := false
	var has_old_pad := false
	for ev in InputMap.action_get_events("jump"):
		if ev is InputEventKey:
			has_key = true # 键鼠事件（空格）必须原样保留
		elif ev is InputEventJoypadButton and ev.button_index == 2:
			has_new_pad = true
		elif ev is InputEventJoypadMotion:
			has_old_pad = true # 旧扳机轴应被整体替换掉
	assert_true(has_key)
	assert_true(has_new_pad)
	assert_false(has_old_pad)
	GamepadBindings.apply_all(GamepadBindings.defaults()) # 还原，不污染其他测试

func test_load_bindings_valid_invalid_missing() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("input", "bind_fire", "b2")
	cfg.set_value("input", "bind_jump", "xx") # 非法描述符 → 回落默认
	var b := GamepadBindings.load_bindings(cfg)
	assert_eq(String(b[&"fire"]), "b2")
	assert_eq(String(b[&"jump"]), "a5:1")
	assert_eq(String(b[&"toggle_settings"]), "b4") # 缺项回落默认

func test_load_bindings_accepts_unbound() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("input", "bind_ads", "")
	var b := GamepadBindings.load_bindings(cfg)
	assert_eq(String(b[&"ads"]), "") # 空串是合法状态（未绑定）
