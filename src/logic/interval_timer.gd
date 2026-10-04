## 间隔计时器（票 03 第 2 节 / CONTEXT.md「间隔计时器」「计时会话」）。
##
## 阶段机：**准备段 → 游玩段 → 休息段 → … → 最终结算**，无尾休息（最后一次游玩段结束
## 直接结算，休息只夹在游玩段之间）。纯逻辑：不依赖节点树，由 main 每帧喂 dt 并消费事件。
## 语义与参考实现 `src/game/timer.ts` 逐条对齐：
## - `tick` 每次最多返回一个事件，dt 由调用方钳制 ≤0.1s，不会跨多个整秒；
## - 整秒边界用 `ceil(remaining)` 变化判定（浮点累减不会丢秒）；
## - 休息段没有任何跳过入口——`tick` 只有走完，`cancel()` 是唯一的退出方式（退出整个会话）。

class_name IntervalTimer
extends RefCounted

## 阶段：空闲 / 准备 / 游玩 / 休息。
enum Phase { OFF, PREPARE, PLAY, REST }

## 事件类型（`NONE` 表示本帧无事件）。
enum Event { NONE, SECOND, PREPARE_END, PLAY_END, REST_END }

const PREPARE_SECONDS := 5
const PLAY_MIN := 1 ## 每段游玩秒数边界（1–600；出厂默认见 GameSettings，此处为纯逻辑回落值）
const PLAY_MAX := 600
const PLAY_DEFAULT := 60
const REST_MIN := 1 ## 每段休息秒数边界（1–300；同上）
const REST_MAX := 300
const REST_DEFAULT := 20
const REPEAT_MIN := 1 ## 重复次数（游玩段数）边界（1–99；同上）
const REPEAT_MAX := 99
const REPEAT_DEFAULT := 4

## 单段游玩的战绩快照：游玩段结束时由调用方从对局读出并交给 `accumulate`。
class RoundStats:
	var kills := 0
	var shots := 0
	var hits := 0
	var deaths := 0
	var seconds := 0.0

## `tick` 的返回值：`type` 为本帧事件（`NONE` = 无事发生）。
class Tick:
	var type: Event = Event.NONE
	var remaining := 0 ## `SECOND` 事件：整秒值（跨相位的本帧不产生该事件）
	var last := false ## `PLAY_END` 事件：是否最后一轮（直接结算）

	func _init(event_type: Event, remaining_second := 0, is_last := false) -> void:
		type = event_type
		remaining = remaining_second
		last = is_last

var phase: Phase = Phase.OFF
var round := 0 ## 已完成的游玩段数（0..repeat）
var remaining := 0.0 ## 当前环节剩余秒数
var play_seconds := PLAY_DEFAULT
var rest_seconds := REST_DEFAULT
var repeat := REPEAT_DEFAULT

var total_kills := 0
var total_shots := 0
var total_hits := 0
var total_deaths := 0
var total_play_seconds := 0.0

## 上一次整秒边界的 `ceil(remaining)`；−1 表示当前不在计时。
var _last_ceil := -1

## 开始计时会话：先进入准备段（5 秒），结束后自动进入第一游玩段。重置全部累计。
func start(play: float, rest: float, repeat_count: int) -> void:
	play_seconds = maxi(PLAY_MIN, int(play))
	rest_seconds = maxi(REST_MIN, int(rest))
	repeat = maxi(REPEAT_MIN, repeat_count)
	round = 0
	total_kills = 0
	total_shots = 0
	total_hits = 0
	total_deaths = 0
	total_play_seconds = 0.0
	phase = Phase.PREPARE
	remaining = PREPARE_SECONDS
	_last_ceil = PREPARE_SECONDS

## 取消会话（ESC 确认退出整个会话），回到空闲。
func cancel() -> void:
	phase = Phase.OFF
	remaining = 0.0
	_last_ceil = -1

## 累计单段游玩战绩（游玩段结束时调用，最终结算前也要把末段计进来）。
func accumulate(stats: RoundStats) -> void:
	total_kills += stats.kills
	total_shots += stats.shots
	total_hits += stats.hits
	total_deaths += stats.deaths
	total_play_seconds += stats.seconds

## 会话累计准确率（百分比，一位小数）；累计 0 发返回 −1（无数据，与 HUD 同口径）。
func total_accuracy() -> float:
	return DuelMatch.accuracy_percent(total_hits, total_shots)

## 推进 dt 秒，返回本帧事件（最多一个）。
func tick(dt: float) -> Tick:
	if phase == Phase.OFF:
		return Tick.new(Event.NONE)
	remaining -= dt
	if remaining <= 0.0:
		return _switch_phase()
	var c := int(ceil(remaining))
	if c != _last_ceil:
		_last_ceil = c
		return Tick.new(Event.SECOND, c)
	return Tick.new(Event.NONE)

func _switch_phase() -> Tick:
	match phase:
		Phase.PREPARE:
			phase = Phase.PLAY
			remaining = float(play_seconds)
			_last_ceil = int(ceil(remaining))
			return Tick.new(Event.PREPARE_END)
		Phase.PLAY:
			round += 1
			if round >= repeat:
				# 无尾休息：最后一轮直接结算
				phase = Phase.OFF
				remaining = 0.0
				_last_ceil = -1
				return Tick.new(Event.PLAY_END, 0, true)
			phase = Phase.REST
			remaining = float(rest_seconds)
			_last_ceil = int(ceil(remaining))
			return Tick.new(Event.PLAY_END, 0, false)
		_:
			# rest → 下一游玩段
			phase = Phase.PLAY
			remaining = float(play_seconds)
			_last_ceil = int(ceil(remaining))
			return Tick.new(Event.REST_END)