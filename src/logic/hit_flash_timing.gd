## 受击红屏时序：事件触发的线性渐隐计时（ADR-0019，CONTEXT「受击红屏」）。
##
## - 命中事件把剩余时长重置回满额——重复命中刷新，从峰值重新渐隐。
## - alpha 比例 = 剩余时长 / 满额，HUD 乘峰值不透明度落屏。
## 纯逻辑：不依赖节点树，与 `HitMarkerTiming` 同构（计时进纯逻辑层，ADR-0009）。

class_name HitFlashTiming
extends RefCounted

const FADE_TIME_S := 0.4 ## 从峰值到完全消隐的时长（秒）

var _left := 0.0 ## 剩余存活时长；0 = 不可见

## 受击事件（重复受击刷新计时）。
func flash() -> void:
	_left = FADE_TIME_S

## 时间推进；返回当前 alpha 比例（0–1，0 = 不可见）。
func tick(delta: float) -> float:
	if _left > 0.0:
		_left = maxf(0.0, _left - delta)
	return _left / FADE_TIME_S

func is_idle() -> bool:
	return _left <= 0.0
