## 命名预设表（票 03 第 4 节 / CONTEXT.md「预设」「默认预设」「活文档」）。
##
## 19 项训练参数的命名快照，**独立**于全局设置持久化，另存选中项。
## - 「不选预设」= 全局设置本身，没有独立存档——行为与预设机制不存在时完全一致；
## - 选中期间的一切改动自动写回该预设（活文档语义，不设显式保存按钮）；
## - 老预设缺项时按出厂默认补齐，不丢预设；核心六项缺失则视为损坏，整条跳过。
##
## 纯逻辑：只吃 / 吐 Dictionary（String 键），不认识 `GameSettings` 与节点树。

class_name PresetStore
extends RefCounted

## 23 项训练参数（票 09 起）：「目标与 bot」6 项 + 「躲避与移动」13 项 + 「bot 滑铲」4 项。
## 不含「武器」、灵敏度 / 画面质量 / 计时器 / 场地布局——这些全局共享。
const FIELDS: Array[String] = [
	"target_range",
	"body_radius",
	"bot_hit_rate",
	"bot_fire_enabled",
	"bot_ads_enabled",
	"lifesteal_enabled",
	"bot_movement_mode",
	"bot_wander",
	"bot_aggression",
	"bot_retreat",
	"bot_range_amp",
	"bot_dodge_auto",
	"bot_dodge_semi",
	"bot_dodge_min_time",
	"bot_switch_min",
	"bot_switch_max",
	"bot_weight_long",
	"bot_weight_mid",
	"bot_weight_fast",
	"bot_attack_slide_enabled",
	"bot_respawn_slide_enabled",
	"bot_slide_jump_enabled",
	"bot_slide_jump_prob",
]

## 核心六项：任一缺失即视为损坏预设。
const CORE_FIELDS: Array[String] = [
	"target_range",
	"body_radius",
	"bot_hit_rate",
	"bot_fire_enabled",
	"bot_ads_enabled",
	"lifesteal_enabled",
]

## 出厂默认（缺字段时补齐；与 `GameSettings` 的初值一致——玩家实测定稿手感，2026-10 烘焙）。
const DEFAULTS := {
	"target_range": 400.0,
	"body_radius": 12.0,
	"bot_hit_rate": 50,
	"bot_fire_enabled": true,
	"bot_ads_enabled": false,
	"lifesteal_enabled": false,
	"bot_movement_mode": 1,
	"bot_wander": 0.45,
	"bot_aggression": 0.5,
	"bot_retreat": 0.3,
	"bot_range_amp": 100.0,
	"bot_dodge_auto": 0.15,
	"bot_dodge_semi": 0.3,
	"bot_dodge_min_time": 0.1,
	"bot_switch_min": 1.0,
	"bot_switch_max": 1.5,
	"bot_weight_long": 0.5,
	"bot_weight_mid": 0.3,
	"bot_weight_fast": 0.3,
	"bot_attack_slide_enabled": true,
	"bot_respawn_slide_enabled": true,
	"bot_slide_jump_enabled": true,
	"bot_slide_jump_prob": 0.5,
}

## 预设名 → 23 项快照（String 键）。
var _presets := {}
## 当前选中的预设名；空串 = 默认预设（全局设置本身）。
var _active := ""

## 全部预设名（插入顺序）。
func names() -> PackedStringArray:
	return PackedStringArray(_presets.keys())

func has(name: String) -> bool:
	return _presets.has(name)

## 当前选中的预设名；空串表示「不选预设」。
func active() -> String:
	return _active

## 存为新预设并自动选中；空名或重名返回 false（不覆盖已有预设）。
func store(name: String, values: Dictionary) -> bool:
	var trimmed := name.strip_edges()
	if trimmed.is_empty() or has(trimmed):
		return false
	var normalized := _normalize(values)
	if normalized.is_empty():
		return false
	_presets[trimmed] = normalized
	_active = trimmed
	return true

## 删除预设；删的是当前选中则回落「不选预设」。
func erase(name: String) -> void:
	_presets.erase(name)
	if _active == name:
		_active = ""

## 选中预设；空名或不存在则回落「不选预设」（不触碰全局数值）。
func select(name: String) -> void:
	_active = name if has(name) else ""

## 取某个预设的 23 项快照**副本**（不存在时返回空字典）。
func capture(name: String) -> Dictionary:
	var preset: Dictionary = _presets.get(name, {})
	return preset.duplicate()

## 活文档写回：把 `values` 覆盖进当前选中的预设；未选中时为空操作。
func write_back(values: Dictionary) -> void:
	if _active.is_empty() or not has(_active):
		return
	var normalized := _normalize(values)
	if not normalized.is_empty():
		_presets[_active] = normalized

## 序列化（交给 `ConfigFile` 落盘）。
func to_dict() -> Dictionary:
	return {"presets": _presets.duplicate(true), "active": _active}

## 反序列化：损坏预设（核心六项缺失）跳过；选中项不存在时回落「不选预设」。
func from_dict(data: Dictionary) -> void:
	_presets.clear()
	var raw: Variant = data.get("presets", {})
	if raw is Dictionary:
		for name in (raw as Dictionary).keys():
			var normalized := _normalize((raw as Dictionary)[name])
			if not normalized.is_empty():
				_presets[str(name)] = normalized
	select(str(data.get("active", "")))

## 整理成完整 23 项快照：核心六项缺失返回空字典（损坏），其余缺字段按出厂默认补齐。
func _normalize(raw: Variant) -> Dictionary:
	if not (raw is Dictionary):
		return {}
	var src := raw as Dictionary
	for core in CORE_FIELDS:
		if not src.has(core):
			return {}
	var out := {}
	for field in FIELDS:
		out[field] = src.get(field, DEFAULTS[field])
	return out