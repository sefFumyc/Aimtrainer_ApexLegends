## 演示模式的追踪数学（ADR-0033）——纯逻辑缝。
##
## 「完美的瞄准动作」= **限速 + 指数缓动**的平滑跟枪：单帧转角不超过「最大转向角速度」，
## 剩余误差按指数衰减，收进死区后一次贴齐（误差归零、不抖、不过冲）。到位判定
## （视线夹角阈值）供场景侧决定何时自动开火。无目标（bot 死亡空窗期）时原样返回，
## 即相机冻结保持。
##
## 纯逻辑：不依赖节点树；`Player` 只负责喂「眼位 / 锁定点 / 当前朝向 / dt」，
## `main` 负责喂锁定点与「有没有目标」。参数硬编码（ADR-0033：不进设置面板）。

class_name DemoAim
extends RefCounted

## 最大转向角速度（rad/s，约 688°/s）：跟枪的「手速」上限——观感是一次可见的快速甩枪，
## 不是瞬移贴脸，也不是肉眼可辨的迟缓。
const MAX_TURN_RATE := 12.0
## 指数缓动速率（1/s）：一阶滞后的稳态残差 = 目标角速度 / 本值，所以它直接决定「跟枪跟得多紧」。
## 实测（探针，range 400 / bot 满速横移 ≈1.0 rad/s）：10 → 残差 5.6°（只有 74% 的帧算「到位」，
## 开火被反复中断）；40 → 残差 ≈1.4°，横移中准星基本粘在身体上，观感才是「完美的跟枪」。
## 注意它**不影响**大角度甩枪的观感——那种误差远超单帧限速，由 `MAX_TURN_RATE` 主导。
const EASE_RATE := 40.0
## 到位判定阈值（rad，约 2°）：瞄得这么准才开火。
const ON_TARGET_ANGLE := deg_to_rad(2.0)
## 收敛死区（rad，约 0.05°）：剩余误差收进这里就一次贴齐，消掉指数尾巴上的亚像素抖动。
const SNAP_ANGLE := deg_to_rad(0.05)

## 当前朝向的前向单位向量：与 `Player.aim_direction` 同一表达式（只取逻辑朝向，
## 不含视觉后坐力），保证「演示判定」与「实际弹道」用的是同一套约定。
static func forward(yaw: float, pitch: float) -> Vector3:
	return -Basis.from_euler(Vector3(pitch, yaw, 0.0)).z

## 推进一帧，返回新的 `(yaw, pitch)`。`has_target` 为假时原样返回（冻结保持）。
static func step(
	eye: Vector3, target: Vector3, yaw: float, pitch: float, dt: float, has_target: bool = true
) -> Vector2:
	var cur := Vector2(yaw, pitch)
	if not has_target or dt <= 0.0:
		return cur
	var to_target := target - eye
	if to_target.length_squared() < 1e-12:
		return cur
	# 目标方向换算成 (yaw, pitch)：与 `forward` 同一约定（yaw = 0 朝 −Z，俯仰为正朝上）。
	var desired := Vector2(
		atan2(-to_target.x, -to_target.z),
		atan2(to_target.y, sqrt(to_target.x * to_target.x + to_target.z * to_target.z)),
	)
	# 角差取最短弧（yaw 可能已漂出 ±π，wrap 后仍在自己那一支上收敛）。
	var err := Vector2(wrapf(desired.x - yaw, -PI, PI), desired.y - pitch)
	# 先算「指数缓动想走多远」，再按单帧角速度上限整体钳制（水平与俯仰合成为一次转向）。
	var move := err * (1.0 - exp(-EASE_RATE * dt))
	var max_step := MAX_TURN_RATE * dt
	var span := move.length()
	if span > max_step:
		move *= max_step / span
	var remaining := err - move
	if absf(remaining.x) <= SNAP_ANGLE and absf(remaining.y) <= SNAP_ANGLE:
		return cur + err # 死区内一次走完：误差精确归零
	return cur + move

## 视线是否已瞄到位（夹角 ≤ `ON_TARGET_ANGLE`）；无目标恒为假。
static func on_target(
	eye: Vector3, target: Vector3, yaw: float, pitch: float, has_target: bool = true
) -> bool:
	if not has_target:
		return false
	var to_target := target - eye
	if to_target.length_squared() < 1e-12:
		return false
	var dot := forward(yaw, pitch).normalized().dot(to_target.normalized())
	return acos(clampf(dot, -1.0, 1.0)) <= ON_TARGET_ANGLE
