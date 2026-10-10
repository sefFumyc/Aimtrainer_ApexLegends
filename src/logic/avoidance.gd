## bot 躲避控制（CONTEXT.md「躲避控制」「变向」「模式切换」「模式权重」「最短躲避时间」「前后分量」）。
##
## 移植自参考实现 `src/game/avoidance.ts` 的**语义与数值**：
## - 三档横移只在变向间隔上分档（长 0.6–1.0 / 中 0.4–0.7 / 快 0.2–0.5s），速度与其它行为不变；
## - 每次自然变向从**当前模式区间重抽**下一次间隔（不是固定频率）；
## - 模式切换在 [switchMin, switchMax] 内随机触发，触发时按模式权重抽新模式并重置变向计时；
## - 「最短躲避时间」只约束躲避（门槛内掷中的躲避被直接丢弃、且不消耗随机数）。
##
## 「撞墙反向」只翻方向：不重掷前后分量、不重置变向/切换计时，但重置「最短躲避时间」时钟。
##
## 本类是**纯逻辑**：不依赖节点树（ADR-0009 / ADR-0013），随机源由外部注入
## （`RandomNumberGenerator`，测试可固定种子得到可复现序列）。

class_name AvoidanceController
extends RefCounted

enum Mode { LONG, MID, FAST }

const MODE_ORDER := [Mode.LONG, Mode.MID, Mode.FAST]

## 三档横移的变向间隔区间（秒），下标即 `Mode` 的值。
const STRAFE_MIN := [0.6, 0.4, 0.2]
const STRAFE_MAX := [1.0, 0.7, 0.5]

## 方向：-1 左 / +1 右 / 0 未确定。
const DIR_NONE := 0
const DIR_LEFT := -1
const DIR_RIGHT := 1

## 前后分量：0 无 / +1 前压(W) / -1 退开(S)。
const FORE_NONE := 0
const FORE_FORWARD := 1
const FORE_BACK := -1

## 可调配置（由场景每帧从 `GameSettings` 刷新，控制器只读）。
class Config:
	var switch_min := 1.0 ## 模式切换间隔下限（秒）
	var switch_max := 1.5 ## 模式切换间隔上限（秒）
	var weights := [0.3, 0.4, 0.3] ## 三档权重（长/中/快，相对比例，内部按总和的归一化）
	var wander := 0.5 ## 游走倾向：变向时混入前后分量的概率
	var aggression := 0.5 ## 进攻倾向：混入的那一份选 W 的权重
	var retreat := 0.5 ## 撤退倾向：混入的那一份选 S 的权重
	var dodge_min := 0.15 ## 最短躲避时间（秒，0 = 关闭）

var dir := DIR_NONE
var mode: Mode = Mode.MID
var fore_mix := FORE_NONE
var flip_timer := 0.0 ## 距下一次自然变向的剩余秒数
var switch_timer := 0.0 ## 距下一次模式切换的剩余秒数
var since_flip := 0.0 ## 距上一次方向确定事件的秒数（躲避/自然变向/撞墙反向/刷新都归零）

var _rng: RandomNumberGenerator
var _config: Config
var _strafe_min: Array
var _strafe_max: Array

## `strafe_min` / `strafe_max` 仅供测试注入自定义变向区间（默认三档固定定义）。
func _init(rng: RandomNumberGenerator, config: Config, strafe_min := [], strafe_max := []) -> void:
	_rng = rng
	_config = config
	_strafe_min = strafe_min if strafe_min.size() == 3 else STRAFE_MIN
	_strafe_max = strafe_max if strafe_max.size() == 3 else STRAFE_MAX

## bot 出现（开局 / 死亡刷新）：按权重抽初始模式、随机初始方向、掷前后分量、两个计时落入各自区间。
func spawn() -> void:
	mode = _weighted_pick()
	dir = DIR_LEFT if _rng.randf() < 0.5 else DIR_RIGHT
	fore_mix = _roll_fore_mix()
	flip_timer = _random_seconds(_mode_range())
	switch_timer = _random_seconds(Vector2(_config.switch_min, _config.switch_max))
	since_flip = 0.0

## 推进计时：变向计时归零 → 翻向并重抽（含前后分量）；切换计时归零 → 按权重抽新模式并重置变向计时。
## `allow_flip = false` 时到点**作废**：不翻向、不掷前后分量、`since_flip` 不清，但间隔照常重抽
## （bot 空中到点一律走这条通道——预约的空中变向由钉点执行、不经计时器到点，ADR-0027）。
## 返回本帧是否真的自然变向。
func update(dt: float, allow_flip := true) -> bool:
	since_flip += dt
	var flipped := false
	flip_timer -= dt
	if flip_timer <= 0.0:
		if allow_flip:
			dir = -dir
			fore_mix = _roll_fore_mix() # 自然变向 = 除刷新外唯一的前后分量重掷点（先掷，保持旧 RNG 序）
			since_flip = 0.0
			flipped = true
		flip_timer = _random_seconds(_mode_range()) # 跳了或作废都照常重抽
	switch_timer -= dt
	if switch_timer <= 0.0:
		mode = _weighted_pick()
		flip_timer = _random_seconds(_mode_range())
		switch_timer = _random_seconds(Vector2(_config.switch_min, _config.switch_max))
	return flipped

## 空中变向钉点执行（ADR-0027）：翻向 + 重掷前后分量 + 重置「最短躲避时间」时钟。
## **不动变向计时器**——原定到点照旧走到、在空中经「作废重抽」通道重抽（节奏零偏移）。
## 与 `update` 的自然变向内容一致，只是执行时机由 bot 侧的升程一半钉点决定、不经计时器到点。
func pinned_flip() -> void:
	dir = -dir
	fore_mix = _roll_fore_mix()
	since_flip = 0.0

## 撞墙 / 前向探测被迫反向：只翻方向，不动任何计时、不重掷前后分量。
## 它是安全纠正、永不被「最短躲避时间」拦，但仍算方向确定事件 → 重置时钟。
func wall_flip() -> void:
	if dir == DIR_NONE:
		return
	dir = -dir
	since_flip = 0.0

## 躲避：被命中时按概率立刻翻向。算一次真变向（重抽变向间隔），但**不**重掷前后分量。
## 「最短躲避时间」内掷中的躲避直接丢弃：不翻向、不重抽间隔、**不消耗随机数**
## （门槛检查排在概率掷骰之前）。返回是否真的翻了。
func dodge(chance: float) -> bool:
	if dir == DIR_NONE:
		return false
	if _config.dodge_min > 0.0 and since_flip < _config.dodge_min:
		return false
	if chance <= 0.0:
		return false
	if not (_rng.randf() < chance):
		return false
	dir = -dir
	flip_timer = _random_seconds(_mode_range())
	since_flip = 0.0
	return true

## 掷前后分量：游走倾向决定「是否混入」，进攻:撤退加权决定 W 还是 S（两者都为 0 则不混入）。
func _roll_fore_mix() -> int:
	if not (_rng.randf() < _config.wander):
		return FORE_NONE
	var total: float = float(_config.aggression) + float(_config.retreat)
	if total <= 0.0:
		return FORE_NONE
	return FORE_FORWARD if _rng.randf() * total < float(_config.aggression) else FORE_BACK

## 按权重抽模式（可抽中当前模式）；三档权重全 0 时回落等权。
func _weighted_pick() -> Mode:
	var weights: Array = _config.weights
	var total := 0.0
	for w in weights:
		total += float(w)
	if total <= 0.0:
		return MODE_ORDER[_rng.randi_range(0, MODE_ORDER.size() - 1)]
	var roll := _rng.randf() * total
	for m in MODE_ORDER:
		roll -= float(weights[m])
		if roll < 0.0:
			return m
	return MODE_ORDER[MODE_ORDER.size() - 1]

func _mode_range() -> Vector2:
	return Vector2(float(_strafe_min[mode]), float(_strafe_max[mode]))

func _random_seconds(range: Vector2) -> float:
	return range.x + _rng.randf() * (range.y - range.x)