## 角色姿势混合（纯逻辑，票 04）：把靶子的**实际水平速度**翻译成三个表现层读数——
## 「该用哪个基准姿势」「躯干朝移动方向侧偏多少」「步频该多快」。
##
## 语义移植自参考实现 `src/render/poseBlend.ts`（PoseBlendController）：
## 三个基准姿势 静止(idle) / 向左走(left) / 向右走(right)，前/后走复用「直立」基准；
## 姿势之间按关键帧混合过渡（直立→侧向 250ms、侧向→直立 200ms、左↔右 250ms），
## 过渡可随时**打断**——新目标从当前侧偏起步、接全新时长，不排队。
##
## 参考实现把权重摊成 idle/left/right 三分量，但引擎侧只消费 `left − right` 这一个标量（侧偏）；
## 而「混合后的三分量之差」恒等于「三分量之差再混合」（线性），所以本类直接混合这一个标量，
## 对外行为与参考实现完全等价。
##
## 本类是**纯逻辑**：不依赖节点树（ADR-0009），由 `target.gd` 消费（选动作 / 调播放速率 / 写骨）。
## 它**只读**速度、不产生任何位移，也不认识任何开关——所以票 04 的特效开关不可能挪动靶子（验收 7）。

class_name PoseBlend
extends RefCounted

## 基准姿势。前/后走归入 STRAIGHT（与「直立」共用同一基准）。
enum Motion { IDLE, LEFT, RIGHT, STRAIGHT }

## 满速基准 = 持枪行走速度（`BASE_SPEED × SPEED_MULT_GUN`，也是靶的速度上限）。步频按它归一化。
const TARGET_SPEED := MovementSimulator.BASE_SPEED * MovementSimulator.SPEED_MULT_GUN

## 混合时长与判静阈值（参考实现 DEFAULT_POSE_BLEND_CONFIG，单位由 ms 换算为 s）。
class Config:
	var idle_walk := 0.25 ## 直立 → 侧向
	var walk_idle := 0.20 ## 侧向 → 直立
	var switch_lr := 0.25 ## 左走 ↔ 右走
	var speed_eps := 0.5 ## 速率判静阈值（u/s，低于此视为静止）
	var strafe_dominance := 0.5 ## |lat| > 本值 × |fwd| 时按侧走判向

## 一帧的表现层读数。
class Frame:
	var motion := Motion.IDLE
	## 侧偏权重：+1 全左、−1 全右、0 直立（左走为正，与参考实现 `weights.left − weights.right` 同号）。
	var lean := 0.0
	## 归一化步频系数：当前速率 ÷ 满速，钳在 0–1。速度 0 → 0，满速 → 1。
	var gait := 0.0
	## 本帧发生姿势切换时的过渡时长（秒）；没有切换则为 0。
	## 表现层拿它做动作交叉淡入，用的就是上面这套 250/200/250ms。
	var blend := 0.0

var _config: Config
var _motion := Motion.IDLE
var _lean := 0.0
var _blending := false
var _from := 0.0
var _elapsed := 0.0
var _duration := 0.0
var _started := 0.0 ## 本帧新起的那一段过渡时长（供 Frame.blend）

func _init(config: Config = null) -> void:
	_config = config if config != null else Config.new()

## 回到静止直立（换靶 / 重新刷新时用）。
func reset() -> void:
	_motion = Motion.IDLE
	_lean = 0.0
	_blending = false
	_from = 0.0
	_elapsed = 0.0
	_duration = 0.0
	_started = 0.0

## 推进一帧。
## `speed` 当前水平速率（u/s）；`lat` / `fwd` 是速度在**自身朝向系**里的分量（正 = 右 / 正 = 前）。
func update(dt: float, speed: float, lat: float, fwd: float) -> Frame:
	_retarget(_classify(speed, lat, fwd))
	if _blending:
		_elapsed += dt
		var t := minf(1.0, _elapsed / _duration)
		_lean = lerpf(_from, lean_of(_motion), t)
		if t >= 1.0:
			_blending = false

	var frame := Frame.new()
	frame.motion = _motion
	frame.lean = _lean
	frame.gait = clampf(speed / TARGET_SPEED, 0.0, 1.0)
	frame.blend = _started
	_started = 0.0
	return frame

## 姿判：静止 / 侧走（侧向优势）/ 直走。
func _classify(speed: float, lat: float, fwd: float) -> Motion:
	if speed <= _config.speed_eps:
		return Motion.IDLE
	if absf(lat) > _config.strafe_dominance * absf(fwd):
		return Motion.RIGHT if lat > 0.0 else Motion.LEFT
	return Motion.STRAIGHT

## 基准姿势的侧偏目标值。
static func lean_of(motion: Motion) -> float:
	if motion == Motion.LEFT:
		return 1.0
	if motion == Motion.RIGHT:
		return -1.0
	return 0.0

static func _upright(motion: Motion) -> bool:
	return motion == Motion.IDLE or motion == Motion.STRAIGHT

## 换目标：目标没变就继续走进行中的过渡；直立↔直立只换语义（侧偏都是 0，没有可过渡的量）；
## 其余一律打断重开——从**当前侧偏**起步、接全新时长。
func _retarget(target: Motion) -> void:
	if target == _motion:
		return
	var prev := _motion
	_motion = target
	_started = _duration_of(prev, target)
	if _upright(prev) and _upright(target):
		_blending = false
		return
	_blending = true
	_from = _lean
	_elapsed = 0.0
	_duration = _started

func _duration_of(from: Motion, to: Motion) -> float:
	var lr := (from == Motion.LEFT and to == Motion.RIGHT) or (from == Motion.RIGHT and to == Motion.LEFT)
	if lr:
		return _config.switch_lr
	return _config.walk_idle if _upright(to) else _config.idle_walk