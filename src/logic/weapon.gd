## 武器数据表与开火节奏（ADR-0010 起步两枪；ADR-0026 扩到三枪：步枪/手枪/冲锋枪）。
##
## - 步枪：按住连射 10 发/秒，身体 25 / 爆头 35。
## - 手枪：单发最快 3 发/秒，身体 70 / 爆头 110；冷却期内的点击**缓冲一发**（多余的被吸收），
##   冷却结束时补发；切换武器丢弃缓冲并清零冷却余量。
## - 冲锋枪：整组连发（ADR-0026）——点一次打一组 5 发（组内 50ms/发），组间最快 430ms
##   且**从组首发起算**；冷却期内的点击**缓冲一整组**、窗口打开即补发；按住开火键 =
##   窗口一开就连下一组；组一旦开始就打完（松键不打断）；切换武器丢弃组剩余与缓冲。
## 纯逻辑：不依赖节点树。

class_name Weapon
extends RefCounted

const RIFLE := &"rifle"
const PISTOL := &"pistol"
const BURST := &"burst"

const RIFLE_INTERVAL := 0.1 ## 射速间隔 = 10 发/秒
const RIFLE_BODY_DAMAGE := 25
const RIFLE_HEADSHOT_DAMAGE := 35
const PISTOL_INTERVAL := 1.0 / 3.0 ## 最快 3 发/秒
const PISTOL_BODY_DAMAGE := 70
const PISTOL_HEADSHOT_DAMAGE := 110
const BURST_SIZE := 5 ## 每组发数（首发在触发帧当场响，余 4 发按组内间隔跟进）
const BURST_SHOT_INTERVAL := 0.05 ## 组内弹间隔（50ms/发）
const BURST_INTERVAL := 0.43 ## 组间节奏 = 组首到组首（ADR-0026；组末发到下窗 230ms）
const BURST_BODY_DAMAGE := 20
const BURST_HEADSHOT_DAMAGE := 30

## 是否「按住连射」语义（无点击边沿）：只有步枪。手枪点一发、冲锋枪点一组——
## 二者的 press() 点击边沿都有意义（缓冲语义挂在这条路径上）。
static func automatic(id: StringName) -> bool:
	return id == RIFLE

## 「连发压迫感」档：步枪与冲锋枪（按死输出节奏接近，躲避概率/开镜枪体收敛归同档，ADR-0026）。
static func is_auto_tier(id: StringName) -> bool:
	return id != PISTOL

## 三枪循环切换（Q / 手柄「切换武器」共用动作）：步枪→手枪→冲锋枪→步枪（与数字键 1/2/3 对齐）。
static func next(id: StringName) -> StringName:
	match id:
		RIFLE:
			return PISTOL
		PISTOL:
			return BURST
		_:
			return RIFLE

## 组内射速间隔（秒）；冲锋枪即 50ms 弹间隔。
static func interval(id: StringName) -> float:
	match id:
		PISTOL:
			return PISTOL_INTERVAL
		BURST:
			return BURST_SHOT_INTERVAL
		_:
			return RIFLE_INTERVAL

static func body_damage(id: StringName) -> int:
	match id:
		PISTOL:
			return PISTOL_BODY_DAMAGE
		BURST:
			return BURST_BODY_DAMAGE
		_:
			return RIFLE_BODY_DAMAGE

static func headshot_damage(id: StringName) -> int:
	match id:
		PISTOL:
			return PISTOL_HEADSHOT_DAMAGE
		BURST:
			return BURST_HEADSHOT_DAMAGE
		_:
			return RIFLE_HEADSHOT_DAMAGE

## 枪声基准音高（ADR-0026）：冲锋枪整体 ×1.15（音调偏高，凭耳朵可分辨武器），其余 1.0。
static func sound_pitch(id: StringName) -> float:
	return 1.15 if id == BURST else 1.0

var _automatic := false
var _burst := false
var _interval := 0.0
var _cool := 0.0
var _pending := false
## 冲锋枪整组状态：组内剩余发数（0 = 无组进行中）与下一发的组内到点计时。
var _group_left := 0
var _shot_cool := 0.0

func _init(id: StringName) -> void:
	_automatic = automatic(id)
	_burst = id == BURST
	_interval = interval(id)

## 开火边沿（点击 / 手柄开火上升沿）。返回本帧是否开火。
## 步枪：立即开火并重置射速计时；手枪：冷却就绪立即开火，冷却中缓冲一发；
## 冲锋枪：就绪立即开组（首发当场响），组中/冷却中缓冲一整组（同一窗口多次点击只缓冲一组）。
func press() -> bool:
	if _automatic:
		_cool = _interval
		return true
	if _burst:
		if _group_left == 0 and _cool <= 0.0:
			_start_group()
			return true
		_pending = true
		return false
	if _cool <= 0.0:
		_cool = _interval
		return true
	_pending = true
	return false

## 开一组：首发由调用方当场记账，余 4 发按组内间隔跟进；窗口时钟从组首起算（ADR-0026）。
func _start_group() -> void:
	_group_left = BURST_SIZE - 1
	_shot_cool = BURST_SHOT_INTERVAL
	_cool = BURST_INTERVAL

## 推进 dt，返回本帧开火次数。
## 步枪：仅在按住时推进（累加器不丢时间，可能一帧多发）；手枪：无条件推进冷却并补发缓冲；
## 冲锋枪：组内按弹间隔逐发推进（松键不打断整组），窗口开后按住即连下一组、有缓冲则补组。
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
	var count := 0
	if _burst and _group_left > 0:
		_shot_cool -= dt
		while _shot_cool <= 0.0 and _group_left > 0:
			count += 1
			_group_left -= 1
			_shot_cool += BURST_SHOT_INTERVAL
	_cool -= dt
	if _cool > 0.0:
		return count
	if _burst:
		if held or _pending:
			_pending = false
			_start_group()
			count += 1
		return count
	if _pending:
		_pending = false
		_cool = _interval
		count += 1
	return count

## 切换武器：丢弃缓冲与组剩余并清零冷却余量（下一发/下一组立即就绪）。
func reset() -> void:
	_pending = false
	_cool = 0.0
	_group_left = 0
	_shot_cool = 0.0
