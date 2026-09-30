## 击中提示时序状态机：生命周期 = 保持(hold) → 消失(fade)。
##
## - 命中：白 X 完整显示保持 hitHoldMs，保持期或消失期再来命中都重置回完整保持。
## - 击杀：红 X 完整显示保持 killHoldMs（击杀事件重复重置），保持到期播 killFadeMs 消失动画。
## - 击杀优先：红 X 展示期（保持或消失）内到来的白命中不打断、被忽略；
##   任意时刻到来的击杀直接切 kill-hold 从头保持。
## 纯逻辑：不依赖节点树，HUD 只负责把状态落到节点。

class_name HitMarkerTiming
extends RefCounted

const HIT_HOLD_MS := 250.0 ## 命中保持时长
const HIT_FADE_MS := 60.0 ## 命中消失动画时长
const KILL_HOLD_MS := 480.0 ## 击杀保持时长
const KILL_FADE_MS := 80.0 ## 击杀消失动画时长

const KIND_NONE := &"none"
const KIND_HIT := &"hit"
const KIND_KILL := &"kill"
const PHASE_NONE := &"none"
const PHASE_HOLD := &"hold"
const PHASE_FADE := &"fade"

var kind := KIND_NONE
var phase := PHASE_NONE
var remaining_ms := 0.0

## 命中 / 击杀事件 → 新状态（一律回到完整保持；仅「红展示期白命中」被忽略）。
func event(new_kind: StringName) -> void:
	if new_kind == KIND_HIT and kind == KIND_KILL:
		return # 击杀优先：红 X 保持 / 消失期白命中忽略
	kind = new_kind
	phase = PHASE_HOLD
	remaining_ms = HIT_HOLD_MS if new_kind == KIND_HIT else KILL_HOLD_MS

## 时间推进：保持到期转消失动画，消失动画播完归 idle；idle 静止不动。
func tick(dt_ms: float) -> void:
	if phase == PHASE_NONE:
		return
	remaining_ms -= dt_ms
	if remaining_ms > 0.0:
		return
	if phase == PHASE_HOLD:
		phase = PHASE_FADE
		remaining_ms = HIT_FADE_MS if kind == KIND_HIT else KILL_FADE_MS
		return
	kind = KIND_NONE
	phase = PHASE_NONE
	remaining_ms = 0.0

func is_idle() -> bool:
	return phase == PHASE_NONE