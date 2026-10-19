## 演示模式的追踪数学（ADR-0033 / ADR-0034）——纯逻辑缝。
##
## 「完美的瞄准动作」= **限速 + 指数缓动**的平滑跟枪：单帧转角不超过「最大转向角速度」，
## 剩余误差按指数衰减，收进死区后一次贴齐（误差归零、不抖、不过冲）。到位判定
## （视线夹角阈值）供场景侧决定何时自动开火。
##
## 按「可见性」（ADR-0034）分**三态**：
## - `TRACK`：看得见（或仍在「失去可见」的宽限期内）→ 拉枪追踪；
## - `COAST`：看不见 → 继承上一帧的角速度、按指数速率滑行收住（不是一帧急停，像自瞄）；
## - `HOLD`：bot 死亡空窗 → 原样返回，相机冻结保持（ADR-0033 原样，**不滑行**）。
##
## 纯逻辑：不依赖节点树；`Player` 只负责喂「眼位 / 锁定点 / 当前朝向 / dt」，
## `main` 负责喂锁定点、「有没有目标」与「看不看得见」。参数硬编码（ADR-0034：不进设置面板）。

class_name DemoAim
extends RefCounted

## 演示模式相机的三态（ADR-0034）。
enum Mode {
	TRACK, ## 看得见：拉枪追踪
	COAST, ## 看不见：带惯性滑行收住
	HOLD, ## bot 死亡空窗：冻结保持
}

## 最大转向角速度（rad/s，约 688°/s）：跟枪的「手速」上限——观感是一次可见的快速甩枪，
## 不是瞬移贴脸，也不是肉眼可辨的迟缓。
const MAX_TURN_RATE := 12.0
## 指数缓动速率（1/s）：一阶滞后的稳态残差 = 目标角速度 / 本值，所以它直接决定「跟枪跟得多紧」。
## 实测（探针，range 400 / bot 满速横移 ≈1.0 rad/s）：10 → 残差 5.6°（只有 74% 的帧算「到位」，
## 开火被反复中断）；40 → 残差 ≈1.4°，横移中准星基本粘在身体上，观感才是「完美的跟枪」。
## 注意它**不影响**大角度甩枪的观感——那种误差远超单帧限速，由 `MAX_TURN_RATE` 主导。
const EASE_RATE := 40.0
## 滑行的指数衰减速率（1/s，ADR-0034）：时间常数 0.1s，可见的滑行约 0.2–0.3s；滑出角度 =
## 失去可见时的角速度 ÷ 本值（典型 4°–15°）。刻意不复用 `EASE_RATE`——那个衰减太快（约 25ms），
## 看不出「余势」，就与「像自瞄一样一帧静止」无异。
const COAST_DECAY := 10.0
## 「失去可见」的宽限（s，ADR-0034）：必须连续看不见满这么久才真的进入滑行；期间重新出现
## 则继续跟枪。挡住贴「遮挡物」边缘时可见性逐帧翻转造成的抖动；恢复可见则即时、无宽限。
const LOST_GRACE := 0.1
## 到位判定阈值（rad，约 2°）：瞄得这么准才开火。
const ON_TARGET_ANGLE := deg_to_rad(2.0)
## 收敛死区（rad，约 0.05°）：剩余误差收进这里就一次贴齐，消掉指数尾巴上的亚像素抖动。
const SNAP_ANGLE := deg_to_rad(0.05)

var _mode: Mode = Mode.HOLD
## 已连续「看不见」的时长（s）：喂给宽限判定，看得见的帧清零。
var _invisible_time := 0.0
## 上一帧的角速度（rad/s）：滑行的初速，由追踪帧逐帧刷新。
var _vel := Vector2.ZERO

## 当前状态（`Mode`）——供场景侧/探针读取。
func mode() -> Mode:
	return _mode

## 当前朝向的前向单位向量：与 `Player.aim_direction` 同一表达式（只取逻辑朝向，
## 不含视觉后坐力），保证「演示判定」与「实际弹道」用的是同一套约定。
static func forward(yaw: float, pitch: float) -> Vector3:
	return -Basis.from_euler(Vector3(pitch, yaw, 0.0)).z

## 推进一帧，返回新的 `(yaw, pitch)`。
## `has_target` = bot 活着（假 → 死亡空窗，冻结保持）；`visible` = 「可见性」通畅（假 → 不锁定）。
func update(
	eye: Vector3,
	target: Vector3,
	yaw: float,
	pitch: float,
	delta: float,
	has_target: bool = true,
	visible: bool = true,
) -> Vector2:
	var cur := Vector2(yaw, pitch)
	if delta <= 0.0:
		return cur
	if not has_target:
		# bot 死亡空窗：冻结保持，与「看不见」不同——不滑行（ADR-0034 用户裁定）。
		_mode = Mode.HOLD
		_invisible_time = 0.0
		_vel = Vector2.ZERO
		return cur
	if visible:
		_invisible_time = 0.0
	else:
		_invisible_time += delta
	# 看得见，或仍在「失去可见」的宽限期内：继续拉枪（开火由 `on_target` 的「可见」闸单独把关）。
	if visible or _invisible_time < LOST_GRACE:
		_mode = Mode.TRACK
		var aim := _track(eye, target, cur, delta)
		_vel = (aim - cur) / delta
		return aim
	# 看不见：带着上一帧的角速度滑行收住（指数衰减，「余势」肉眼可见）。
	_mode = Mode.COAST
	var decay := exp(-COAST_DECAY * delta)
	var slid := cur + _vel * (1.0 - decay) / COAST_DECAY
	_vel *= decay
	return slid

## 限速 + 指数缓动的一帧追踪（ADR-0033 的跟枪数学）。
func _track(eye: Vector3, target: Vector3, cur: Vector2, delta: float) -> Vector2:
	var to_target := target - eye
	if to_target.length_squared() < 1e-12:
		return cur
	# 目标方向换算成 (yaw, pitch)：与 `forward` 同一约定（yaw = 0 朝 −Z，俯仰为正朝上）。
	var desired := Vector2(
		atan2(-to_target.x, -to_target.z),
		atan2(to_target.y, sqrt(to_target.x * to_target.x + to_target.z * to_target.z)),
	)
	# 角差取最短弧（yaw 可能已漂出 ±π，wrap 后仍在自己那一支上收敛）。
	var err := Vector2(wrapf(desired.x - cur.x, -PI, PI), desired.y - cur.y)
	# 先算「指数缓动想走多远」，再按单帧角速度上限整体钳制（水平与俯仰合成为一次转向）。
	var move := err * (1.0 - exp(-EASE_RATE * delta))
	var max_step := MAX_TURN_RATE * delta
	var span := move.length()
	if span > max_step:
		move *= max_step / span
	var remaining := err - move
	if absf(remaining.x) <= SNAP_ANGLE and absf(remaining.y) <= SNAP_ANGLE:
		return cur + err # 死区内一次走完：误差精确归零
	return cur + move

## 「可以开火」：既要瞄到位（夹角 ≤ `ON_TARGET_ANGLE`），又要**看得见**且目标还在——
## 看不见就一颗子弹都不出膛（否则隔墙开火必打在掩体上）。ADR-0034。
static func on_target(
	eye: Vector3,
	target: Vector3,
	yaw: float,
	pitch: float,
	has_target: bool = true,
	visible: bool = true,
) -> bool:
	if not has_target or not visible:
		return false
	var to_target := target - eye
	if to_target.length_squared() < 1e-12:
		return false
	var dot := forward(yaw, pitch).normalized().dot(to_target.normalized())
	return acos(clampf(dot, -1.0, 1.0)) <= ON_TARGET_ANGLE
