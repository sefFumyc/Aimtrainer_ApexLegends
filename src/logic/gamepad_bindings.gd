## 手柄键位（ADR-0025）：单一绑定模型的纯逻辑缝。
##
## 每个可改键动作**至多一个手柄绑定**（实体按键或扳机/摇杆轴），改键 = 按一个键整体替换，
## 冲突**抢占**（新键自动从旧动作上摘除）。绑定用紧凑字符串描述符承载，便于 settings.cfg
## 持久化与测试比对：`"b10"` = 按钮 10（RB）、`"a5:1"` = 轴 5 正向（RT）、`""` = 未绑定。
## 键鼠事件不在本类管辖内——`apply_all` 回灌 InputMap 时只替换手柄事件、保留键鼠事件。
## 纯逻辑：除 `apply_all` 外不碰任何单例。

class_name GamepadBindings
extends RefCounted

## 轴采集阈值（ADR-0025）：|value| 达标才算有效输入，防轻晃误采。
const AXIS_CAPTURE := 0.6

## 可改键的六个动作（CONTEXT「键位设置」）。
const ACTIONS: Array[StringName] = [
	&"jump", &"crouch", &"fire", &"ads", &"weapon_switch", &"toggle_settings",
]

## 动作 → 设置页显示名。
const LABELS := {
	&"jump": "跳跃",
	&"crouch": "蹲",
	&"fire": "开火",
	&"ads": "开镜",
	&"weapon_switch": "切换武器",
	&"toggle_settings": "开关设置",
}

## 出厂默认（ADR-0025）：砍掉 A/B——跳跃=RT、蹲=LT、开火=RB、开镜=LB、切换武器=Y、开关设置=Back。
## 与 project.godot 手写 InputMap 的手柄事件保持一致（运行时以本表回灌）。
const DEFAULTS := {
	&"jump": "a5:1",
	&"crouch": "a4:1",
	&"fire": "b10",
	&"ads": "b9",
	&"weapon_switch": "b3",
	&"toggle_settings": "b4",
}

## 按钮友好名（Godot JoyButton 枚举；0=A … 14=十字右）。
const BUTTON_NAMES := {
	0: "A", 1: "B", 2: "X", 3: "Y", 4: "Back", 5: "Guide", 6: "Start",
	7: "L3", 8: "R3", 9: "LB", 10: "RB",
	11: "十字上", 12: "十字下", 13: "十字左", 14: "十字右",
}

## 轴友好名：只有扳机有惯用名，摇杆轴无键位惯用名 → 「轴N」。
const AXIS_NAMES := { 4: "LT", 5: "RT" }

## 出厂默认表的一份拷贝（调用方可自由改写，不污染常量）。
static func defaults() -> Dictionary:
	return DEFAULTS.duplicate()

## 把一份「动作 → 描述符」字典就地做抢占清理：`desc` 非空时，摘掉其他动作上的同键绑定。
static func steal(bindings: Dictionary, action: StringName, desc: String) -> void:
	if desc.is_empty():
		return
	for other in ACTIONS:
		if other != action and String(bindings.get(other, "")) == desc:
			bindings[other] = ""

## 采集事件 → 描述符；手柄按键与过阈值的轴有效，其余（键鼠 / 欠阈轴）返回空串。
## 轴事件没有 `pressed` 语义（是连续状态上报），只按阈值判有效；回零（松开）自然落在阈下。
static func from_event(event: InputEvent) -> String:
	if event is InputEventJoypadButton and event.pressed:
		return "b%d" % event.button_index
	if event is InputEventJoypadMotion and absf(event.axis_value) >= AXIS_CAPTURE:
		return "a%d:%d" % [event.axis, 1 if event.axis_value > 0.0 else -1]
	return ""

## 描述符 → 对应的手柄输入事件；未绑定返回 null。
static func event_for(desc: String) -> InputEvent:
	if desc.begins_with("b"):
		var button := InputEventJoypadButton.new()
		button.button_index = int(desc.substr(1))
		return button
	if desc.begins_with("a"):
		var parts := desc.substr(1).split(":")
		if parts.size() != 2:
			return null
		var motion := InputEventJoypadMotion.new()
		motion.axis = int(parts[0])
		motion.axis_value = float(int(parts[1]))
		return motion
	return null

## 描述符 → 玩家可读名（"RB" / "RT" / "轴1−" / "未绑定"）。
static func friendly(desc: String) -> String:
	if desc.is_empty():
		return "未绑定"
	if desc.begins_with("b"):
		return BUTTON_NAMES.get(int(desc.substr(1)), "按钮%s" % desc.substr(1))
	if desc.begins_with("a"):
		var parts := desc.substr(1).split(":")
		if parts.size() != 2:
			return "未绑定"
		var name := String(AXIS_NAMES.get(int(parts[0]), "轴%s" % parts[0]))
		return name + ("−" if parts[1] == "-1" else "")
	return "未绑定"

## 把一份「动作 → 描述符」回灌 InputMap：每个动作只替换**手柄事件**，键鼠事件原样保留——
## 开火/开镜的鼠标键、跳跃的空格等都在 InputMap 里与手柄并存，改手柄键不能动它们。
static func apply_all(bindings: Dictionary) -> void:
	for action in ACTIONS:
		if not InputMap.has_action(action):
			continue
		var keep: Array[InputEvent] = []
		for ev in InputMap.action_get_events(action):
			if not (ev is InputEventJoypadButton or ev is InputEventJoypadMotion):
				keep.append(ev)
		InputMap.action_erase_events(action)
		for ev in keep:
			InputMap.action_add_event(action, ev)
		var ev_pad := event_for(String(bindings.get(action, "")))
		if ev_pad != null:
			InputMap.action_add_event(action, ev_pad)

## 从 settings.cfg 读「动作 → 描述符」：缺项 / 非法描述符一律回落出厂默认。
static func load_bindings(cfg: ConfigFile) -> Dictionary:
	var out := defaults()
	for action in ACTIONS:
		var stored := String(cfg.get_value("input", "bind_" + String(action), out[action]))
		if _valid(stored):
			out[action] = stored
	return out

## 描述符合法性（写入与读回共用同一守卫）。数字部分必须真为整数——`int("x")` 会静默
## 得 0，不设这道闸「bx」就伪装成 b0 混进存档。
static func _valid(desc: String) -> bool:
	if desc.is_empty():
		return true
	if desc.begins_with("b"):
		var n := desc.substr(1)
		return n.is_valid_int() and int(n) >= 0
	if desc.begins_with("a"):
		var parts := desc.substr(1).split(":")
		return (
			parts.size() == 2
			and parts[0].is_valid_int()
			and parts[1].is_valid_int()
			and int(parts[1]) in [-1, 1]
		)
	return false
