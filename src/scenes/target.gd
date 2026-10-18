## 靶（票 02）：移动与决策全在纯逻辑类 `BotAi` 里，本节点只是它的**碰撞载体与表现层**。
##
## `CharacterBody3D` 只做碰撞求解（与 Player 同构）：水平位移由 `BotAi.sim` 按固定子步算好，
## 这里每帧把「本帧位移 ÷ delta」喂给 `velocity`，`move_and_slide()` 后再把真实位置回写给 sim。
## 朝向每帧跟随 `BotAi.sim`（CONTEXT「朝向」：常规指向玩家，滑铲中由其朝向状态机驱动，
## ADR-0017）——侧移方向是相对朝向的，所以表现为围着玩家画弧。
##
## ❗ **移动碰撞体**与**命中体**是两件事（ADR-0014）：
## - 移动 = 半径 8、高 72 的胶囊（与 Player 同构），只挡遮挡物与地面，任何射线都看不见它；
## - 命中 = 模型各部件自身的几何：把每个网格在「靶」局部空间里的包围盒做成盒子碰撞形状，
##   逐个挂在子 `StaticBody3D` 上，所见即所中——打中手臂、腿都算命中，打空气不算
##   （Knight 内置的剑/盾网格已隐藏且不再生成命中盒，bot 改持步枪，票 05）。
##
## 之所以分开：KayKit 骑士是 T 字绑定姿势，剑与盾横向伸出约 40 单位；若让部件盒同时充当移动碰撞体，
## 靶会在多遮挡布局下被柱角剐住——纯逻辑满速而 `move_and_slide()` 位移归零，原地卡死。
## 爆头靠命中形状所属的部件名判定（名字含 head / helmet），见 `is_headshot`。
## 模型缺失时回落到程序化圆柱 + 头球，保证靶始终打得中。
##
## 分层：移动本体在「靶移动层」（8）、命中体在「靶层」（2）、只与「世界层」（1）碰撞；
## 玩家本体在「玩家层」（4）。于是玩家与靶互不碰撞，而玩家开火射线（mask 1|2）只看得见命中体、
## bot 视线射线（mask 1|4）与探测射线（mask 1）只看得见世界。

class_name Target
extends CharacterBody3D

## 命中体所在层（玩家开火射线的 mask 含此层）。
const HIT_LAYER := 2
## 靶**移动本体**所在层：单独占一层，任何射线都不含它——它不是隐形 hitbox（CONTEXT「体型」）。
const MOVE_LAYER := 8
## 世界（地面 / 遮挡物 / 围墙）层：靶只与它碰撞。
const WORLD_LAYER := 1
## bot 枪口相对脚底的高度（曳光起点与视线射线起点）。
const MUZZLE_HEIGHT := 45.0

## KayKit Adventurers（CC0）角色模型（ADR-0007）。
const MODEL := "res://assets/third_party/kaykit-adventurers/character/Knight.glb"
## 模型自带朝向的补偿角：本体 `rotation.y` 已指向玩家，这里只补模型与 Godot −Z 前向的差。
const MODEL_FACE_YAW := PI

## 判为「头」的部件名关键词（小写包含匹配）。
const HEAD_PART_KEYWORDS: Array[String] = ["head", "helmet"]

## 判为「武器」的部件名关键词（小写包含匹配）：Knight 内置的剑/盾网格隐藏、命中盒一并移除，
## bot 改挂步枪（票 05：刀盾违和）。
const WEAPON_PART_KEYWORDS: Array[String] = ["sword", "shield"]

## bot 手持步枪（票 05，票 06 换 blaster-d 突击步枪造型）：Kenney blaster-kit（与玩家第一人称同款资产）挂到右手骨。
const WEAPON_MODEL := "res://assets/third_party/kenney_blaster-kit/rifle/blaster-d.glb"
const WEAPON_BONE := "handslot.r" ## KayKit 骨架预留的右手持物槽位
const WEAPON_LENGTH := 30.0 ## 步枪的期望长度（骑士总高 72，原剑的伸出量约 40）
## 步枪在手骨上的姿态补偿（模型原始朝向 → 枪口朝角色前方、枪身水平）。
## 相对 handslot.r 的**绑定 rest 姿态**反解得出（探针两轮均值，票 05）；枪随走动动画自然摆手。
const WEAPON_ROT := Vector3(deg_to_rad(61.0), deg_to_rad(-147.5), deg_to_rad(-148.3))

## 走动动作（票 04）：按 `PoseBlend` 判出的姿势选一支。
## 靶的主体运动就是横移，所以侧走用 KayKit 的横移跑；直走按前后分量分正走 / 倒走。
const CLIP_IDLE := "Idle"
const CLIP_LEFT := "Running_Strafe_Left"
const CLIP_RIGHT := "Running_Strafe_Right"
const CLIP_FORWARD := "Walking_A"
const CLIP_BACKWARD := "Walking_Backwards"
## 滑铲姿势（ADR-0018）：模型自带「躺地」三件套——扑倒（一次性）→ 躺姿滑行（循环）→ 爬起（一次性）。
## 原速 3.0 / 2.67 / 2.33s 远超滑铲全程 0.35–0.9s（探针实测），倒地与爬起按段快放。
const CLIP_SLIDE_DOWN := "Lie_Down"
const CLIP_SLIDE_IDLE := "Lie_Idle"
const CLIP_SLIDE_UP := "Lie_StandUp"
## 躺地三件套快放倍数（ADR-0018）：×4 → 0.75s 倒平、×2.5 → 0.93s 爬起；躺姿循环原速。
const SLIDE_DOWN_SPEED := 4.0
const SLIDE_UP_SPEED := 2.5
## 滑铲躺姿的命中体压深（ADR-0018）：躺姿视觉最高点 ≈20u，72−50=22 的判定轮廓与之贴合。
## 不复用玩家的 CROUCH_HEIGHT（−30 是坐姿口径，坐改躺后判定会悬在半空）。
const SLIDE_SINK := -50.0
## 姿势机切换动作用的过渡时长：比走跑混合（250/200ms）更快，滑铲 0.35–0.9s 里不显拖沓。
const SLIDE_POSE_BLEND := 0.15
## 本票会播的全部动作：KayKit 的 GLB 里它们是按「不循环」导入的，`_setup_animation` 要逐个改成循环。
const CLIPS: Array[String] = [
	CLIP_IDLE, CLIP_LEFT, CLIP_RIGHT, CLIP_FORWARD, CLIP_BACKWARD
]

## 脚底接触暗影（票 04）：程序化径向渐变贴在脚下一层，随靶移动，不参与任何碰撞与射线。
const SHADOW_TEXTURE_SIZE := 128
const SHADOW_LIFT := 0.6 ## 离地高度（避免与地面共面产生 z-fighting）
const SHADOW_ALPHA := 0.55

var ai: BotAi
## 躲避与移动配置：与 `BotAi` 共用同一实例，设置改动就地生效（见 `main._apply_settings`）。
var config: AvoidanceController.Config

var _rng := RandomNumberGenerator.new()
## 命中体节点（模型部件盒挂它下面，只参与射线、不参与移动）。
var _hit_body: StaticBody3D
## 命中体的全部命中形状（模型部件盒，或模型缺失时的兜底形状）。
var _hit_shapes: Array[CollisionShape3D] = []
## 模型实例（GLB 根）；模型缺失时为 null。走动动作与骨骼都在它里面。
var _model: Node3D
## 视觉模型的外层 holder（缩放与朝向补偿挂它上面）：铲跳升空时按 sim 跳跃高度整体抬升（ADR-0018）。
var _model_holder: Node3D
## 模型自带的动画播放器（`Idle` / `Walking_*` / `Running_Strafe_*` 等）。
var _anim: AnimationPlayer
## 骨级侧偏：在动画**之后**写 hips / chest（为什么不是 `SkeletonModifier3D`，见 `pose_lean.gd` 头注）。
var _pose_lean: PoseLean
## bot 手持步枪（票 05）：挂在 Target 根下，每帧手动对齐右手骨（见 `_attach_weapon`）。
var _gun: Node3D
var _gun_bone := -1 ## 枪对齐的手骨索引
var _gun_len_scale := 1.0 ## 枪的世界级缩放（最长边归一到 WEAPON_LENGTH）
var _skeleton: Skeleton3D ## Knight 骨架（_attach_weapon 缓存，_sync_gun 每帧读手骨用）
## 枪口标记（枪管轴线，ADR-0021 二轮）：挂在枪下随 `_sync_gun` 的全局变换逐帧跟随，
## `muzzle_world_visual()` 优先读它；模型缺失时为 null，回落到地面 + MUZZLE_HEIGHT 口径。
var _gun_muzzle: Node3D
## 姿势混合（纯逻辑）：读实际速度，产出姿势 / 侧偏 / 步频。
var _pose := PoseBlend.new()
## 当前在播的动作名（只在切换时调 `play`，避免每帧重启动画）。
var _clip := ""
## 滑铲姿势机状态（ADR-0017 引入、ADR-0018 换躺姿、ADR-0032 铲跳交回常规）：NONE = 不接管（常规走/跑）。
enum SlidePose { NONE, DOWN, LIE, UP }
var _slide_pose := SlidePose.NONE
## 模型是否带齐躺地三件套（缺任何一支则姿势机不接管，回落到只压低命中体）。
var _slide_pose_clips := false

func _ready() -> void:
	visible = false
	_rng.randomize()
	config = AvoidanceController.Config.new()
	ai = BotAi.new(_rng, config, _probe_ray)
	_build_move_body()
	_build_hit_body()
	_build_contact_shadow()
	_setup_animation()
	_set_hittable(false)

# ---- 对外接口 ----

## 在指定平面位置出现：满血、可见、可命中、清空开火状态。
func spawn(at: Vector2) -> void:
	ai.spawn(at)
	global_position = Vector3(at.x, 0.0, at.y)
	_pose.reset()
	_slide_pose = SlidePose.NONE
	_clip = "" # 强制下一帧重新 play：上一条命可能定格在任意动作的半截（含滑铲姿势）
	# 抬升 / 压深立即归零：上命可能死在铲跳空中，spawn 当帧就该贴地（等不到下一帧 _apply_motion）
	_hit_body.position.y = 0.0
	if _model_holder != null:
		_model_holder.position.y = 0.0
	if _pose_lean != null:
		_pose_lean.apply(0.0)
	visible = true
	_set_hittable(true)

## 推进一帧：先让纯逻辑决策并积分，再把位移交给物理求解、位置回写。
## 返回本帧的开火结果（每项 = 该发是否命中玩家），由 main 结算扣血与表现。
func tick(delta: float, perception: BotAi.Perception) -> Array:
	var before := ai.sim.position()
	var shots := ai.update(delta, perception)
	if ai.alive:
		_apply_motion(delta, before, perception)
		_apply_pose(delta)
	visible = ai.alive
	_set_hittable(ai.alive)
	return shots

## 命中一次（伤害与感知一起交给 AI：非致命会触发躲避与受击反击）。返回本次是否击杀。
func take_hit(damage: int, perception: BotAi.Perception) -> bool:
	if not ai.alive:
		return false
	var lethal := ai.take_damage(damage, perception)
	if lethal:
		visible = false
		_set_hittable(false)
	return lethal

## 从场上撤下（回主菜单 / 计时准备段用）：不可见、不可命中。
## AI 状态保留，下一次 `spawn()` 会整体覆盖。
func despawn() -> void:
	visible = false
	_set_hittable(false)

## 死亡后的刷新倒计时是否已走完（由 main 决定刷到哪）。
func needs_respawn() -> bool:
	return not ai.alive and ai.respawn_left <= 0.0

func hp() -> int:
	return ai.hp

## bot 枪口的世界坐标：**视线判定射线**的起点（main._bot_has_sight），保持地面口径——
## 铲跳升空不得改变视线判定（ADR-0018：bot 决策零改动）。
func muzzle_world() -> Vector3:
	return global_position + Vector3(0.0, MUZZLE_HEIGHT, 0.0)

## 曳光 / 火光等**纯视觉**特效的枪口起点（ADR-0021 二轮）：优先读枪上的 Muzzle 标记
## （枪管轴线，随 `_sync_gun` 逐帧跟随——走动摆手 / 铲跳升空所见即所发）；模型缺失时
## 回落到地面 + MUZZLE_HEIGHT + 跳跃高度的旧口径。视线判定口径（`muzzle_world`）不变。
func muzzle_world_visual() -> Vector3:
	if _gun_muzzle != null:
		return _gun_muzzle.global_position
	return muzzle_world() + Vector3(0.0, ai.sim.jump_height(), 0.0)

## 曳光命中点换算（ADR-0021 四轮）：命中时把世界命中点转存为**命中体局部坐标**，
## 存活期每帧用 `tracer_hit_world` 换算回世界——bot 平移/转向/躺姿压深（SLIDE_SINK）/
## 铲跳升空（lift）全部跟随，线远端始终贴在 bot 身上被打中的那个点。
func tracer_hit_local(world: Vector3) -> Vector3:
	return _hit_body.global_transform.affine_inverse() * world

func tracer_hit_world(local: Vector3) -> Vector3:
	return _hit_body.to_global(local)

## 演示模式（ADR-0033）的锁定点：命中体**当前悬于地面之上那一段**的垂直中心，换算到世界。
## 站立 ≈ 36（躯干中心）；滑铲躺姿压深 −50 时可见段只剩 0–22、中心抬到 11 仍落在身体上；
## 铲跳升空时随命中体整体跟抬。之所以不用固定的「世界坐标 + 躯干高度」：躺姿压深与升空
## 会让准星锁在空气里，自动开火必打空。纯读数：不参与任何碰撞与命中判定。
func aim_point_world() -> Vector3:
	var base := _hit_body.position.y # 躺姿压深（SLIDE_SINK）+ 铲跳升空（lift）
	var bottom := maxf(base, 0.0)
	var top := base + Physique.TOTAL_HEIGHT
	var point := _hit_body.to_global(Vector3.ZERO)
	point.y = (bottom + top) * 0.5
	return point

## 命中体节点：开火射线打到的是它（不是本节点），调用方用它来判断「命中的是不是这个靶」。
func hit_body() -> CollisionObject3D:
	return _hit_body

## 射线命中的形状是否属于头部部件——`hit_body` 是射线命中的碰撞对象（本靶的命中体节点），
## `shape_index` 取自 `intersect_ray` 的 `"shape"`。做成 static 是因为命中的是命中体、不是本节点。
static func is_headshot(hit_body: CollisionObject3D, shape_index: int) -> bool:
	if hit_body == null:
		return false
	var owner_id := hit_body.shape_find_owner(shape_index)
	if owner_id < 0:
		return false
	var collider := hit_body.shape_owner_get_owner(owner_id)
	if collider == null:
		return false
	var lower := str(collider.name).to_lower()
	for keyword in HEAD_PART_KEYWORDS:
		if lower.contains(keyword):
			return true
	return false

## 设置「体型半径」：只缩放水平（x/z），身高与头心高度不变。
func apply_body_radius(body_radius: float) -> void:
	var s := Physique.horizontal_scale(body_radius)
	scale = Vector3(s, 1.0, s)

# ---- 移动表现 ----

## 把纯逻辑算出的本帧位移交给物理求解，再把求解结果回写给 sim（与 Player `_tick_move` 同构）。
## 「纯逻辑步长」与「物理实际位移」相差过大时交给 `BotAi.on_blocked` 兜底（ADR-0014）。
func _apply_motion(delta: float, before: Vector2, perception: BotAi.Perception) -> void:
	var after := ai.sim.position()
	var intended := after - before
	var step := intended / delta if delta > 1e-6 else Vector2.ZERO
	var start := global_position
	velocity = Vector3(step.x, 0.0, step.y)
	move_and_slide()
	ai.on_blocked(
		intended.length(), Vector2(global_position.x - start.x, global_position.z - start.z).length()
	)

	global_position.y = 0.0
	ai.sim.sync_position(Vector2(global_position.x, global_position.z))
	# 滑铲躺姿命中体压深（ADR-0018：SLIDE_SINK 独立常量）+ 铲跳升空抬升（ADR-0018：
	# sim 跳跃高度喂给命中体与视觉模型，所见即所中；影子留地、移动碰撞贴地不跟）。
	# 铲跳空中压深解除（ADR-0032：空中不再播躺姿），命中体按站姿判定（「空中打其身体上部照样算中」）；
	# sim 的 crouch_p 只在地面积分、空中会冻结在 1，不能直接乘。
	var sink := 0.0 if ai.sim.state() == "airborne" else SLIDE_SINK * ai.sim.crouch_progress()
	var lift := ai.sim.jump_height()
	_hit_body.position.y = sink + lift
	if _model_holder != null:
		_model_holder.position.y = lift
	# 「朝向」跟随 sim（ADR-0017）：常规 = 指向玩家；滑铲中由 BotAi 的朝向状态机驱动
	# （先转向滑行方向、再按角速度转回）。命中体与模型同为根子节点，随根一起转——所见即所中。
	rotation.y = ai.sim.get_facing()

## 「前向探测」的射线实现（ADR-0005）：只探世界层（遮挡物），不探玩家与自身。
## 起点已在遮挡物内部时 `intersect_ray` 默认不报（`hit_from_inside = false`），
## 所以贴着柱子不会每帧都翻向、不会抖动。
func _probe_ray(origin: Vector2, dir: Vector2, length: float) -> bool:
	var from := Vector3(origin.x, MUZZLE_HEIGHT, origin.y)
	var query := PhysicsRayQueryParameters3D.create(
		from, from + Vector3(dir.x, 0.0, dir.y) * length, WORLD_LAYER
	)
	query.exclude = [get_rid()]
	return not get_world_3d().direct_space_state.intersect_ray(query).is_empty()

# ---- 动画与特效（票 04）----

## 用**实际水平速度**驱动表现：选动作 / 调播放速率 / 写骨级侧偏。
## 只读 `ai.sim`，不写回任何位移，也不认识任何开关——所以动画与特效都不可能挪动靶子（验收 7）。
func _apply_pose(delta: float) -> void:
	var v := ai.sim.velocity()
	var local := MovementSimulator.world_to_local(v.x, v.y, ai.sim.get_facing())
	var frame := _pose.update(delta, ai.sim.speed(), local.x, local.y)
	# 滑铲姿势机（ADR-0018，ADR-0032 起铲跳空中交回常规）：返回非空 = 接管本帧动作（躺地 / 爬起），并压掉侧偏。
	var pose_clip := _slide_pose_clip()
	if _anim != null:
		var clip := _clip_for(frame.motion, local.y)
		var blend := frame.blend
		if pose_clip != "":
			clip = pose_clip
			blend = SLIDE_POSE_BLEND
		if clip != _clip:
			_clip = clip
			_anim.play(clip, blend) # 过渡时长就取姿势混合的 250/200/250ms
		# 步频跟随速度：静止不缩放；姿势机动作按「躺地三件套快放表」（ADR-0018）；
		# 走动动作按归一化速率调速，与当前速率**等比例**（CONTEXT「步态周期」）。
		if pose_clip != "":
			_anim.speed_scale = _slide_pose_speed(clip)
		elif clip == CLIP_IDLE:
			_anim.speed_scale = 1.0
		else:
			_anim.speed_scale = frame.gait
		# 动画走 MANUAL：由这里推进，好让紧接着的侧偏写骨确定地落在动画**之后**（见 pose_lean.gd 头注）。
		_anim.advance(delta)
	if _pose_lean != null:
		_pose_lean.apply(0.0 if pose_clip != "" else frame.lean)
	_sync_gun() # 手动同步枪到右手骨（为什么不用 BoneAttachment3D，见 _attach_weapon）

## 滑铲姿势机（ADR-0017 引入、ADR-0018 换躺姿、ADR-0032 铲跳交回常规）：返回本帧应播的动作；
## 空串 = 不接管（常规走/跑）。迁移只由 `ai.sim.state()` 驱动：sliding → 躺（Down→Idle）；
## 滑铲结束（地面）→ Up 一次性收尾；**铲跳升空 → 立即交回常规动作**。
## ADR-0032：铲跳空中不持有任何专用 clip——连跳链里 state 恒为 "airborne"（落地帧立即起跳），
## 专用循环动作会被长期占用并定格，铲跳空中从此与普通跳（ADR-0023 空中零特判）同一条路径。
## （唯一未覆盖：UP 收尾被普通跳打断 → 空中播完 Lie_StandUp，有界 ≤0.93s，见 ADR-0032 已知边界。）
## 一次性动作播完用播放位置判据（MANUAL 推进不依赖信号）。
func _slide_pose_clip() -> String:
	if not _slide_pose_clips:
		return ""
	var state := ai.sim.state()
	match _slide_pose:
		SlidePose.NONE:
			if state == "sliding":
				_slide_pose = SlidePose.DOWN
				return CLIP_SLIDE_DOWN
			return ""
		SlidePose.DOWN:
			if state == "sliding":
				if _pose_anim_done(CLIP_SLIDE_DOWN):
					_slide_pose = SlidePose.LIE
					return CLIP_SLIDE_IDLE
				return CLIP_SLIDE_DOWN
			if state == "airborne": # 铲跳（主路径：倒地未播完 0.75s 即到铲跳时刻 ≤0.6s）：交回常规
				_slide_pose = SlidePose.NONE
				return ""
			_slide_pose = SlidePose.UP
			return CLIP_SLIDE_UP
		SlidePose.LIE:
			if state == "sliding":
				return CLIP_SLIDE_IDLE
			if state == "airborne": # 铲跳：躺姿升空即交回常规走/跑
				_slide_pose = SlidePose.NONE
				return ""
			_slide_pose = SlidePose.UP
			return CLIP_SLIDE_UP
		SlidePose.UP:
			if state == "sliding": # 爬起动画未播完又注入滑铲（冷却边界）：重新扑倒
				_slide_pose = SlidePose.DOWN
				return CLIP_SLIDE_DOWN
			if _pose_anim_done(CLIP_SLIDE_UP):
				_slide_pose = SlidePose.NONE
				return ""
			return CLIP_SLIDE_UP
	return ""

## 姿势机动作的播放倍速（ADR-0018）：倒地/爬起快放（原速远超滑铲时长），其余原速。
func _slide_pose_speed(clip: String) -> float:
	match clip:
		CLIP_SLIDE_DOWN:
			return SLIDE_DOWN_SPEED
		CLIP_SLIDE_UP:
			return SLIDE_UP_SPEED
		_:
			return 1.0

## 一次性动作是否已播完（MANUAL 推进下用播放位置判据，不依赖信号时序）。
func _pose_anim_done(clip: String) -> bool:
	return _anim.current_animation != clip \
		or _anim.current_animation_position >= _anim.get_animation(clip).length

## 把枪的世界变换对齐到右手骨**当前位置 + 纯旋转**（丢弃骨链缩放），缩放直接用世界级标量。
func _sync_gun() -> void:
	if _gun == null or _gun_bone < 0 or _skeleton == null:
		return
	var bone_xf := _skeleton.global_transform * _skeleton.get_bone_global_pose(_gun_bone)
	var basis := Basis(bone_xf.basis.get_rotation_quaternion()) * Basis.from_euler(WEAPON_ROT)
	_gun.global_transform = Transform3D(
		basis * Basis.from_scale(Vector3.ONE * _gun_len_scale), bone_xf.origin)

## 姿势 → 动作名。直立按前后分量分正走 / 倒走（侧走本就是横移跑，不分正反）。
func _clip_for(motion: PoseBlend.Motion, fwd: float) -> String:
	match motion:
		PoseBlend.Motion.LEFT:
			return CLIP_LEFT
		PoseBlend.Motion.RIGHT:
			return CLIP_RIGHT
		PoseBlend.Motion.STRAIGHT:
			return CLIP_FORWARD if fwd >= 0.0 else CLIP_BACKWARD
		_:
			return CLIP_IDLE

## 认领模型里的动画与骨骼，挂上侧偏叠加器，并先播好「静止」——
## Knight 是 T 字绑定姿势，不播任何动作时双臂会一直横伸。
func _setup_animation() -> void:
	if _model == null:
		return
	_anim = _find_animation(_model)
	var skeleton := _find_skeleton(_model)
	if _anim == null or skeleton == null:
		return
	# ❗ KayKit 的动作在 GLB 里按「不循环」导入（实测 `loop_mode == LOOP_NONE`）：不改的话
	# 走一步（约 1.07s）就定格在最后一帧、腿不再迈，看起来恰好就是验收 1 要排除的「原地滑步」。
	# 本票播的这几支都该循环，就地改（运行时改，不动资产的导入设置）。
	for name in CLIPS:
		var clip_anim := _anim.get_animation(name)
		if clip_anim != null:
			clip_anim.loop_mode = Animation.LOOP_LINEAR
	# 滑铲姿势三件套（ADR-0018，躺地）：Down / Up 保持导入的「不循环」，Idle 改循环。
	# 任一缺失则整个姿势机不接管（回落到走/跑动画 + 只压低命中体）。
	_slide_pose_clips = _anim.has_animation(CLIP_SLIDE_DOWN) \
		and _anim.has_animation(CLIP_SLIDE_IDLE) and _anim.has_animation(CLIP_SLIDE_UP)
	if _slide_pose_clips:
		_anim.get_animation(CLIP_SLIDE_IDLE).loop_mode = Animation.LOOP_LINEAR
	_pose_lean = PoseLean.new()
	_pose_lean.setup(skeleton)
	_attach_weapon(skeleton)
	# 动画改由 `_apply_pose` 手动推进（MANUAL）：只有这样才能保证侧偏写骨落在动画之后。
	_anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_anim.play(CLIP_IDLE)
	_clip = CLIP_IDLE

## 把步枪挂到右手骨（票 05）：**不用 BoneAttachment3D**——Knight.glb 的骨链自带非均匀缩放
## （handslot.r 全局 scale ≈ 29/26/26），BoneAttachment 会把这份剪切传给枪：枪挂上去被
## 撕成几块看不见的碎片（本票排查实锤）。改为枪挂在 Target 根下（父链均匀缩放），
## 每帧由 `_sync_gun` 把世界变换对齐到手骨的位置 + 纯旋转，缩放直接用世界级标量。
func _attach_weapon(skeleton: Skeleton3D) -> void:
	if not ResourceLoader.exists(WEAPON_MODEL):
		return
	var packed := load(WEAPON_MODEL)
	if not (packed is PackedScene):
		return
	var gun := (packed as PackedScene).instantiate() as Node3D
	if gun == null:
		return
	var box := _model_aabb(gun)
	var longest := maxf(box.size.x, maxf(box.size.y, box.size.z))
	if longest <= 0.0:
		return
	# 朝向说明（票 06 探针实测）：blaster-d 导入后 +Z 端是枪口，WEAPON_ROT 标定的合成
	# 结果恰好把模型 +Z 端对到角色前方——**不需要翻转**；且 _sync_gun 每帧覆写 _gun
	# 的全局变换，任何挂在枪根上的本地翻转都活不过一帧（曾试过包 holder 转 180°，
	# 被覆写成恒等，已删）。
	_gun = gun
	_gun_bone = skeleton.find_bone(WEAPON_BONE)
	_skeleton = skeleton
	# 枪口标记（ADR-0021 二轮）：此刻 gun 本地变换还是恒等，box 即**原始模型空间**——
	# 标记钉在枪网格最前端（+Z 端是枪口，票 06 探针实测）的枪管轴线上，高度系数与玩家
	# 第一人称共用同一探针定稿值（blaster-d 同款资产，Viewmodel.RIFLE_BORE_FRAC），随
	# `_sync_gun` 的全局变换（含 34.88× 缩放）逐帧跟随：所见即所发。
	var muzzle := Node3D.new()
	muzzle.name = "Muzzle"
	muzzle.position = Vector3(
		(box.position.x + box.end.x) * 0.5,
		box.end.y - box.size.y * Viewmodel.RIFLE_BORE_FRAC,
		box.end.z
	)
	gun.add_child(muzzle)
	_gun_muzzle = muzzle
	# 枪直接挂 Target 根下：全局变换由 _sync_gun 每帧写，绕开骨链的非均匀缩放
	add_child(gun)
	_gun_len_scale = WEAPON_LENGTH / longest # 世界级缩放：最长边归一到期望长度

## 脚底接触暗影：程序化径向渐变（中心黑半透明 → 边缘全透明）贴在地面上一层。
## 不参与碰撞、不投影、不被射线看见；作为本节点的子节点，随「体型半径」的水平缩放一起变大。
func _build_contact_shadow() -> void:
	var grad := Gradient.new()
	grad.set_color(0, Color(0.0, 0.0, 0.0, SHADOW_ALPHA))
	grad.set_color(1, Color(0.0, 0.0, 0.0, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = SHADOW_TEXTURE_SIZE
	tex.height = SHADOW_TEXTURE_SIZE
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = tex
	var quad := PlaneMesh.new()
	var side := Physique.BODY_RADIUS * 4.0
	quad.size = Vector2(side, side)
	var shadow := MeshInstance3D.new()
	shadow.name = "ContactShadow"
	shadow.mesh = quad
	shadow.material_override = mat
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shadow.position = Vector3(0.0, SHADOW_LIFT, 0.0)
	add_child(shadow)

## GLB 导出的节点名不保证，所以按**类型**而不是按名字在模型子树里找。
func _find_animation(root: Node) -> AnimationPlayer:
	if root is AnimationPlayer:
		return root as AnimationPlayer
	for child in root.get_children():
		var found := _find_animation(child)
		if found != null:
			return found
	return null

func _find_skeleton(root: Node) -> Skeleton3D:
	if root is Skeleton3D:
		return root as Skeleton3D
	for child in root.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null

# ---- 碰撞载体 ----

## 移动碰撞体：半径 8、高 72 的胶囊（与 `player.tscn` 同一形状），只与「世界层」碰撞。
## 它承担靶与遮挡物/地面的碰撞求解，射线一律看不见它（不在任何射线的 mask 里）。
func _build_move_body() -> void:
	var shape := CapsuleShape3D.new()
	shape.radius = Physique.BODY_RADIUS
	shape.height = Physique.TOTAL_HEIGHT
	var collider := CollisionShape3D.new()
	collider.name = "MoveShape"
	collider.shape = shape
	collider.position = Vector3(0.0, Physique.TOTAL_HEIGHT * 0.5, 0.0)
	add_child(collider)

## 用模型自身几何建命中体；模型缺失时回落到程序化兜底。
## 形状挂在本节点（靶本体的原点）下的 `HitBody` 上，变换与视觉 holder 一致。
func _build_hit_body() -> void:
	_hit_body = StaticBody3D.new()
	_hit_body.name = "HitBody"
	_hit_body.collision_layer = HIT_LAYER
	_hit_body.collision_mask = 0 # 只被射线打到，不推任何东西
	add_child(_hit_body)
	var inst := _instantiate_model()
	if inst == null:
		_build_fallback_shapes()
		return
	var box := _model_aabb(inst)
	if box.size.y <= 0.0:
		inst.queue_free()
		_build_fallback_shapes()
		return
	# 动画与骨骼都在这个实例里（`_setup_animation` 认领），模型缺失时它保持为 null。
	_model = inst
	# 模型按「总高 72」缩放并落地对齐（可尺寸之外的位置与朝向都由这个 holder 承担）。
	# ❗ 水平方向**不**做居中：KayKit 骑士把剑与盾向一侧伸出（AABB 单边到 2.0、另一边只到 -0.6），
	# 按 AABB 居中会把角色整体推离逻辑原点约 20 单位——准星与骑士错位、移动碰撞体也贴着空气。
	# 模型原点本身就是「角色脚下的中心」，只把脚底对到 y=0 即可。
	var holder := Node3D.new()
	holder.name = "Character"
	holder.scale = Vector3.ONE * (Physique.TOTAL_HEIGHT / box.size.y)
	holder.rotation = Vector3(0.0, MODEL_FACE_YAW, 0.0)
	inst.position = Vector3(0.0, -box.position.y, 0.0)
	holder.add_child(inst)
	add_child(holder)
	_model_holder = holder # 铲跳升空时按 sim 跳跃高度整体抬升（ADR-0018）
	_add_part_shapes(inst, Transform3D.IDENTITY, holder.transform)

func _instantiate_model() -> Node3D:
	if not ResourceLoader.exists(MODEL):
		return null
	var packed := load(MODEL)
	if not (packed is PackedScene):
		return null
	return (packed as PackedScene).instantiate() as Node3D

## 递归遍历模型，把每个网格在「靶」局部空间里的包围盒做成一个盒子碰撞形状。
## 名字含武器关键词的网格（Knight 内置剑/盾）跳过且隐藏——bot 改持步枪（票 05）。
func _add_part_shapes(node: Node, xf: Transform3D, holder_xf: Transform3D) -> void:
	var local := xf
	if node is Node3D:
		local = xf * (node as Node3D).transform
	if node is MeshInstance3D:
		var lower := str(node.name).to_lower()
		var is_weapon := false
		for keyword in WEAPON_PART_KEYWORDS:
			if lower.contains(keyword):
				is_weapon = true
				break
		if is_weapon:
			(node as MeshInstance3D).visible = false
		else:
			_add_box_shape(str(node.name), holder_xf * local * (node as MeshInstance3D).get_aabb())
	for child in node.get_children():
		_add_part_shapes(child, local, holder_xf)

func _add_box_shape(part_name: String, box: AABB) -> void:
	if box.size.x <= 0.0 or box.size.y <= 0.0 or box.size.z <= 0.0:
		return
	var shape := BoxShape3D.new()
	shape.size = box.size
	var collider := CollisionShape3D.new()
	collider.name = part_name
	collider.shape = shape
	collider.position = box.position + box.size * 0.5
	_hit_body.add_child(collider)
	_hit_shapes.append(collider)

## 模型缺失时的兜底命中体：圆柱身体 + 头球，尺寸取 `Physique` 的参考体型。
func _build_fallback_shapes() -> void:
	var body := CollisionShape3D.new()
	body.name = "FallbackBody"
	var body_shape := CylinderShape3D.new()
	body_shape.radius = Physique.BODY_RADIUS
	body_shape.height = Physique.BODY_HEIGHT
	body.shape = body_shape
	body.position = Vector3(0.0, Physique.BODY_HEIGHT * 0.5, 0.0)
	_hit_body.add_child(body)
	_hit_shapes.append(body)

	var head := CollisionShape3D.new()
	head.name = "FallbackHead"
	var head_shape := SphereShape3D.new()
	head_shape.radius = Physique.HEAD_RADIUS
	head.shape = head_shape
	head.position = Vector3(0.0, Physique.HEAD_CENTER_Y, 0.0)
	_hit_body.add_child(head)
	_hit_shapes.append(head)

## 模型在其父空间里的包围盒（递归累加各网格的 AABB）。
func _model_aabb(root: Node) -> AABB:
	var boxes: Array[AABB] = []
	_collect_boxes(root, Transform3D.IDENTITY, boxes)
	var out := AABB()
	for i in boxes.size():
		out = boxes[i] if i == 0 else out.merge(boxes[i])
	return out

func _collect_boxes(node: Node, xf: Transform3D, out: Array[AABB]) -> void:
	var local := xf
	if node is Node3D:
		local = xf * (node as Node3D).transform
	if node is MeshInstance3D:
		out.append(local * (node as MeshInstance3D).get_aabb())
	for child in node.get_children():
		_collect_boxes(child, local, out)

func _set_hittable(on: bool) -> void:
	for collider in _hit_shapes:
		collider.disabled = not on