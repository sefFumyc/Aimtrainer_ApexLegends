## 骨级「朝向侧偏」（票 04）：把躯干朝移动方向偏一点，叠在靶子**正在播的动作之上**。
##
## 侧偏量取自参考实现 `src/render/character.ts` 的 `CharacterRig.apply`（角度按 ADR-0015 收敛）：
## 骨盆朝移动方向偏 30°、肩偏 10°——
## 于是下半身朝移动方向、上半身基本仍朝瞄准方向，这才是「侧偏」而不是「整体瞬转」。
## 颈以上再把世界偏角拉回 0，使**头的世界朝向与瞄准方向一致**（CONTEXT「头不动（≈0°）」：
## 肩偏是「肩在动、头没动」，不是「整个上半身一起歪」）。
##
## ❗ 三段都要按**世界目标角**强制，不能只在动画上「加拧」：
## 探针实测 KayKit 横移动画自己就让躯干随步态大幅摆动（hips 在 −32°~+53° 间摆、chest ≈ +55°、
## head ≈ +40°）。「加拧」写法（骨盆 +25 叠在动画上、胸腔/头静态反旋）有两重失败：
## 1) 静态反旋抵不掉动画自带的拧转 → 三段全拧向同一边（78/38/32），「整个身子一起歪」；
## 2) 骨盆叠加值随步态相位摆动 → 有相位骨盆反而比胸腔拧得少（−7 vs 16），梯子倒挂。
## 所以逐帧按「动画当前姿态 → 期望世界净偏角」插值再反解本地写值（满侧偏时净偏角恒为
## 骨盆 30 / 肩 10 / 头 0，与 ADR-0015 一致；lean = 0 时逐笔等价于不写）：
## 只改各骨 euler 的 yaw 分量，动画自带的俯仰 / 侧倾（x/z）与位移原样保留。
##
## 不移植参考实现里「手腕反旋 −15° 让枪口与头始终朝前」那一步：靶子手里的步枪只是视觉挂件
## （挂右手骨，票 05），而曳光与判定的枪口是 `Target.MUZZLE_HEIGHT` 的固定偏移、不挂在骨骼上，
## 没有需要被抵消的偏转。
##
## ❗ **为什么不用 `SkeletonModifier3D`**：它是引擎为「动画之后叠加程序化骨姿势」提供的分层，
## 但本机 4.7.2 上实测**不可用**——KayKit 的 GLB 里 `AnimationPlayer` 与 `Rig`（Skeleton3D）是
## 兄弟节点且动画排在后面，修饰器写进骨姿势后会被同一帧内随后应用的动画覆盖（读回恒为动画值）。
## 已排除的猜测：`process_priority`、`move_child` 调序、`callback_mode_process` 改物理帧——均无效。
## 改为「手动推进动画 + 随后立刻写骨」（`Target._apply_pose`），顺序由调用点自己保证，
## 不依赖引擎的进程顺序；外部写入能稳定活过整帧（已实测）。
##
## Knight.glb 的 hips / spine / chest / head 四根骨 rest 朝向都是单位阵（`tools` 巡检结论），
## 骨本地 Y 就是世界 Y，所以侧偏可以直接写成绕**本地 Y** 的旋转，不必做基变换。

class_name PoseLean
extends RefCounted

const PELVIS_LEAN := 30.0 ## 骨盆朝移动方向的偏角（度；ADR-0015：试玩三轮 45° → 25° → 18° → 30°）
const SHOULDER_LEAN := 10.0 ## 世界肩偏（度；ADR-0015：从参考实现的 15° 收敛，定稿 10°）

var _skeleton: Skeleton3D
var _hips := -1
var _hips_parent := -1
var _spine := -1
var _chest := -1
var _head := -1

## 认领要写的骨；找不到就让 `apply` 整体不生效（不报错，画面退化为「没有侧偏」）。
func setup(skeleton: Skeleton3D) -> void:
	_skeleton = skeleton
	_hips = skeleton.find_bone("hips")
	_hips_parent = skeleton.get_bone_parent(_hips) if _hips >= 0 else -1
	_spine = skeleton.find_bone("spine")
	_chest = skeleton.find_bone("chest")
	_head = skeleton.find_bone("head")

## 把侧偏写进骨姿势。`lean`：+1 全左、−1 全右、0 直立（由纯逻辑 `PoseBlend` 给出）。
## ❗ 必须在动画**之后**调用（`Target._apply_pose` 里紧跟 `AnimationPlayer.advance`），否则会被动画覆盖。
func apply(lean: float) -> void:
	if _skeleton == null or _hips < 0 or _chest < 0:
		return
	var sign := clampf(lean, -1.0, 1.0)
	var k := absf(sign) ## 侧偏强度：0 = 完全交给动画，1 = 满侧偏（世界净偏角到位）
	# 骨盆：世界偏角从「动画自带」拉向「±30°」。反解 hips 本地 = 父骨全局⁻¹ × 目标全局
	# （hips 的父是 root 骨，动画也会拧它，必须一并算进链）。
	var hips_e := _skeleton.get_bone_global_pose(_hips).basis.get_rotation_quaternion().get_euler()
	var hips_yaw := lerpf(hips_e.y, sign * deg_to_rad(PELVIS_LEAN), k)
	var hips_target := Quaternion(Basis.from_euler(Vector3(hips_e.x, hips_yaw, hips_e.z)))
	var hips_chain := Quaternion.IDENTITY
	if _hips_parent >= 0:
		hips_chain = _skeleton.get_bone_global_pose(_hips_parent).basis.get_rotation_quaternion()
	_skeleton.set_bone_pose_rotation(_hips, hips_chain.inverse() * hips_target)
	# 胸腔：世界偏角拉向「肩偏 ±8°」；父链 = 写好的 hips 全局 × spine 动画本地。
	var chest_e := _skeleton.get_bone_global_pose(_chest).basis.get_rotation_quaternion().get_euler()
	var chest_yaw := lerpf(chest_e.y, sign * deg_to_rad(SHOULDER_LEAN), k)
	var q_spine := _spine_pose()
	var parent_chain := _skeleton.get_bone_global_pose(_hips).basis.get_rotation_quaternion() * q_spine
	var chest_target := Quaternion(Basis.from_euler(Vector3(chest_e.x, chest_yaw, chest_e.z)))
	_skeleton.set_bone_pose_rotation(_chest, parent_chain.inverse() * chest_target)
	# 头：世界偏角拉回 0（正对瞄准方向）；链基座换成写好的 chest。
	if _head >= 0:
		var head_e := _skeleton.get_bone_global_pose(_head).basis.get_rotation_quaternion().get_euler()
		var head_yaw := lerpf(head_e.y, 0.0, k)
		var chest_chain := _skeleton.get_bone_global_pose(_chest).basis.get_rotation_quaternion()
		var head_target := Quaternion(Basis.from_euler(Vector3(head_e.x, head_yaw, head_e.z)))
		_skeleton.set_bone_pose_rotation(_head, chest_chain.inverse() * head_target)

## spine 的动画本地旋转（找不到 spine 时视为单位阵，链退化成 hips 直连 chest）。
func _spine_pose() -> Quaternion:
	if _spine < 0:
		return Quaternion.IDENTITY
	return _skeleton.get_bone_pose_rotation(_spine)