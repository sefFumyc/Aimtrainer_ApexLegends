## 骨级「朝向侧偏」（票 04）：把躯干朝移动方向偏一点，叠在靶子**正在播的动作之上**。
##
## 侧偏量取自参考实现 `src/render/character.ts` 的 `CharacterRig.apply`：
## 骨盆朝移动方向偏 45°、胸腔相对骨盆反向 −30°，合成「世界肩偏 15°」——
## 于是下半身明显朝移动方向、上半身明显仍朝瞄准方向，这才是「侧偏」而不是「整体瞬转」。
## 颈以上再反向 −15° 把肩偏抵消掉，使**头的世界朝向与瞄准方向一致**（CONTEXT「头不动（≈0°）」：
## 肩偏是「肩在动、头没动」，不是「整个上半身一起歪」）。
##
## 不移植参考实现里「手腕反旋 −15° 让枪口与头始终朝前」那一步：靶子手里是 KayKit 的剑，
## 而枪口是 `Target.MUZZLE_HEIGHT` 的固定偏移、不挂在骨骼上，没有需要被抵消的偏转。
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

const PELVIS_LEAN := 45.0 ## 骨盆朝移动方向的偏角（度）
const SHOULDER_LEAN := 15.0 ## 骨盆 + 胸腔合成后的世界肩偏（度）

var _skeleton: Skeleton3D
var _hips := -1
var _chest := -1
var _head := -1

## 认领要写的三根骨；找不到就让 `apply` 整体不生效（不报错，画面退化为「没有侧偏」）。
func setup(skeleton: Skeleton3D) -> void:
	_skeleton = skeleton
	_hips = skeleton.find_bone("hips")
	_chest = skeleton.find_bone("chest")
	_head = skeleton.find_bone("head")

## 把侧偏写进骨姿势。`lean`：+1 全左、−1 全右、0 直立（由纯逻辑 `PoseBlend` 给出）。
## ❗ 必须在动画**之后**调用（`Target._apply_pose` 里紧跟 `AnimationPlayer.advance`），否则会被动画覆盖。
func apply(lean: float) -> void:
	if _skeleton == null or _hips < 0 or _chest < 0:
		return
	var sign := clampf(lean, -1.0, 1.0)
	_pose_yaw(_hips, sign * deg_to_rad(PELVIS_LEAN))
	_pose_yaw(_chest, sign * deg_to_rad(SHOULDER_LEAN - PELVIS_LEAN))
	if _head >= 0: # 头是胸腔的子节点，这一笔把继承来的肩偏抵消掉，世界净偏角归零
		_pose_yaw(_head, sign * deg_to_rad(-SHOULDER_LEAN))

## 把「相对静止姿态再绕世界 Y 偏 `yaw`」写进这根骨。
## rest 朝向为单位阵 ⇒ 世界 Y 就是骨本地 Y，叠加量直接写成 rest × 绕本地 Y 的旋转。
func _pose_yaw(bone: int, yaw: float) -> void:
	var rest := _skeleton.get_bone_rest(bone).basis.get_rotation_quaternion()
	_skeleton.set_bone_pose_rotation(bone, rest * Quaternion(Vector3.UP, yaw))