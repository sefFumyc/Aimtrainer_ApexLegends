## 武器数据表与开火节奏（ADR-0010：只有步枪与手枪，无空手）。
##
## - 步枪：按住连射 10 发/秒，身体 25 / 爆头 35。
## - 手枪：单发最快 3 发/秒，身体 70 / 爆头 110；冷却期内的点击**缓冲一发**（多余的被吸收），
##   冷却结束时补发；切枪丢弃缓冲并清零冷却余量。
## 纯逻辑：不依赖节点树。

class_name Weapon
extends RefCounted

const RIFLE := &"rifle"
const PISTOL := &"pistol"

const RIFLE_INTERVAL := 0.1 ## 射速间隔 = 10 发/秒
const RIFLE_BODY_DAMAGE := 25
const RIFLE_HEADSHOT_DAMAGE := 35
const PISTOL_INTERVAL := 1.0 / 3.0 ## 最快 3 发/秒
const PISTOL_BODY_DAMAGE := 70
const PISTOL_HEADSHOT_DAMAGE := 110

static func is_rifle(id: StringName) -> bool:
	return id != PISTOL

## 射速间隔（秒）。
static func interval(id: StringName) -> float:
	return RIFLE_INTERVAL if is_rifle(id) else PISTOL_INTERVAL

## 是否按住连射。
static func automatic(id: StringName) -> bool:
	return is_rifle(id)

static func body_damage(id: StringName) -> int:
	return RIFLE_BODY_DAMAGE if is_rifle(id) else PISTOL_BODY_DAMAGE

static func headshot_damage(id: StringName) -> int:
	return RIFLE_HEADSHOT_DAMAGE if is_rifle(id) else PISTOL_HEADSHOT_DAMAGE

## 「就近切枪」（Q）：切到另一把。
static func other(id: StringName) -> StringName:
	return PISTOL if is_rifle(id) else RIFLE

var _interval := 0.0
var _automatic := false
var _cool := 0.0
var _pending := false

func _init(id: StringName) -> void:
	_interval = interval(id)
	_automatic = automatic(id)

## 开火边沿（点击 / 手柄开火上升沿）。返回本帧是否开火。
## 步枪：立即开火并重置射速计时；手枪：冷却就绪立即开火，冷却中缓冲一发。
func press() -> bool:
	if _automatic:
		_cool = _interval
		return true
	if _cool <= 0.0:
		_cool = _interval
		return true
	_pending = true
	return false

## 推进 dt，返回本帧开火次数。
## 步枪：仅在按住时推进（累加器不丢时间，可能一帧多发）；手枪：无条件推进冷却并补发缓冲。
func advance(dt: float, held: bool) -> int:
	if _automatic:
		if not held:
			return 0
		var count := 0
		_cool -= dt
		while _cool <= 0.0:
			count += 1
			_cool += _interval
		return count
	_cool -= dt
	if _cool > 0.0 or not _pending:
		return 0
	_pending = false
	_cool = _interval
	return 1

## 切枪：丢弃缓冲并清零冷却余量（下一发立即就绪）。
func reset() -> void:
	_pending = false
	_cool = 0.0