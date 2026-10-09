## 靶子的完整 AI（CONTEXT.md「移动靶」「距离保持」「贴墙内拐」「前向探测」「视线判定」「瞄准视锥」「受击反击」「攻击锁定」）。
##
## 语义移植自参考实现 `src/game/bot.ts`，并按本项目新增两条决策：
## - **前向探测**（ADR-0005）：无寻路，沿移动方向探到「遮挡物」或边界时提前触发变向，
##   复用撞墙反向的优惠语义（只翻方向、不重掷前后分量、不重置变向/切换计时，但重置最短躲避时间时钟）。
##   翻向带 0.3s 承诺窗口，且物理受阻时由 `on_blocked` 用同一语义兜底（ADR-0014）。
## - **视线判定**（ADR-0006）：被遮挡物阻断时本发**不开火**——不掷骰、不消耗随机数。
##
## 本类是**纯逻辑**：不依赖节点树（ADR-0009 / ADR-0013）。它对世界的两处探知都由外部注入：
## - `_probe(origin, dir, length) -> bool`：前向探测的射线（场景提供；纯逻辑测试可注入假实现）；
## - `Perception.line_of_sight`：本帧 bot → 玩家的视线是否通畅（场景每帧算好）。
## 边界是解析判定（半径圆），由本类自己算，不依赖注入。

class_name BotAi
extends RefCounted

const MAX_HP := 600
const RESPAWN_DELAY := 1.5 ## 死亡到重新出现的间隔
const RANGE_DEADBAND := 25.0 ## 「死区带」半宽（「保持距离」档）
const RANGE_PROPORTIONAL_SPAN := 150.0 ## 距离误差映射到满幅推力所需跨度
const FIRE_INTERVAL := 0.1 ## 开火间隔（与玩家步枪同射速 10 发/秒）
const AIM_CONE_HALF := PI / 18.0 ## 「瞄准视锥」半角（总角 20°）
const AIM_HOLD := 0.35 ## 视锥内连续满 350ms 才触发开火
const BODY_HEIGHT := 72.0 ## bot 通体高度（视锥俯仰跨度 0→72）
const WALL_EPS := 1e-4
const BOT_DAMAGE := 25 ## bot 每发命中扣玩家的血量（永不爆头）
## 「前向探测」长度（单位），按「场地布局」档位：空旷 / 少量遮挡 / 多遮挡。
const PROBE_LENGTHS := [60.0, 120.0, 180.0]
## 「探测 / 受阻」翻向后的承诺窗口（秒）。两个侧向都被探到受阻时若不设窗口就会**每帧翻向**，
## 而每次翻向都重触发一次「转向衰减」（90° 只保留 65% 速度），逐帧相乘把速度抖到近 0。
const FLIP_COMMIT := 0.3
## 物理实际位移低于纯逻辑步长的这个比例即视为「被挡住」。
const BLOCK_RATIO := 0.5

## 「bot 滑铲」（票 09 / ADR-0016）：注入初速定稿 399 u/s——玩家看不见前摇，直接满速滑出。
const SLIDE_INJECT_SPEED := 399.0
## 滑行时长随机窗口（秒）：到点站起恢复常规躲避。
const SLIDE_MIN_T := 0.35
const SLIDE_MAX_T := 0.9
## 铲跳时刻随机窗口（秒，从滑铲开始计；不超过站起时刻）。
const SLIDE_JUMP_MIN_T := 0.1
const SLIDE_JUMP_MAX_T := 0.6
## 攻击滑铲方向采样次数（玩家连线 ±90° 内随机取向，避障失败重掷）。
const SLIDE_DIR_TRIES := 3
## 滑铲结束后的冷却（秒）：防「视线持续被挡」时落地即连滑。
const SLIDE_CD := 1.0
## 滑铲起步转身时长：面向玩家 → 面向滑行方向（ADR-0017）。
const SLIDE_TURN_TO_DIR_T := 0.1
## 滑铲中回头角速度 rad/s（= 360°/s，ADR-0017）。
const SLIDE_TURN_SPEED := TAU
## 「瞄住」容差：滑铲中与玩家方向夹角 ≤10° 恢复开火（ADR-0017）。
const SLIDE_AIM_TOL := deg_to_rad(10.0)

## 每帧感知（由场景装配；纯逻辑测试直接构造）。
class Perception:
	var player_x := 0.0 ## 玩家水平位置
	var player_z := 0.0
	var player_eye_y := 0.0 ## 玩家视线高度（视锥俯仰判定用）
	var player_yaw := 0.0
	var player_pitch := 0.0
	var target_range := 120.0 ## 「目标距离」
	var wander_mode := false ## 「移动模式」：false 保持距离 / true 动态游走
	var range_amp := 25.0 ## 「走廊」半宽（远近变化幅度）
	var fire_enabled := false ## 「开火开关」
	var hit_rate := 68 ## 「命中率」（整数 0–100）
	var body_radius := 8.0 ## 「体型半径」（视锥水平半宽角用）
	var ads := false ## bot 常驻开镜（只体现为移速变慢）
	var line_of_sight := true ## 「视线判定」（场景每帧对玩家做一次遮挡射线）
	var dodge_chance := 0.0 ## 「躲避概率」（按玩家当前武器分连发/单发两档）
	var arena_layout := 1 ## 「场地布局」档位（驱动前向探测长度）
	var slide_attack := false ## 「攻击滑铲」开关（视线被挡时触发）
	var slide_jump := false ## 「铲跳」开关（滑铲中不松蹲跳起晃子弹）
	var slide_jump_prob := 0.3 ## 「铲跳概率」（每次滑铲独立掷骰）
	var jump_enabled := false ## 「bot 跳跃」开关（票 11 / ADR-0023）
	var jump_min := 4.0 ## 「跳跃间隔」下限（秒）
	var jump_max := 12.0 ## 「跳跃间隔」上限（秒）

var sim := MovementSimulator.new()
var avoidance: AvoidanceController
var hp := MAX_HP
var alive := true
var respawn_left := 0.0

var _rng: RandomNumberGenerator
var _probe: Callable
var _fire_timer := 0.0
var _aim_timer := 0.0
var _fire_lock := false
var _flip_hold := 0.0 ## 距下一次允许「探测 / 受阻」翻向的剩余秒数（承诺窗口）
var _sliding := false ## 注入滑铲进行中（全程冻结躲避与探测，只保留开火）
var _slide_t := 0.0 ## 已滑行秒数
var _slide_end_at := 0.0 ## 本次站起时刻
var _slide_jump := false ## 本次滑铲是否已决定铲跳
var _slide_jump_at := 0.0 ## 铲跳时刻
var _slide_cd := 0.0 ## 滑铲结束后的攻击滑铲冷却
var _slide_dir := Vector2.ZERO ## 本次滑铲的世界方向（起步转身段的目标朝向，ADR-0017）
var _slide_face_from := 0.0 ## 滑铲起始朝向（起步段从这里插值到滑行方向，ADR-0017）
var _jump_rng: RandomNumberGenerator ## 跳跃骰独立随机源：不污染开火/滑铲序列（ADR-0023）
var _jump_wait := -1.0 ## 距下一次跳跃判定的秒数；<0 = 待落窗（spawn 后首帧重抽首跳间隔）
## bot 空中机动三态（票 12 / ADR-0024）：
var _air_strafe := 0.0 ## 空中侧向快照：起跳沿锁定当前方向，apex 沿与安全翻向处跟进
var _air_armed := false ## 上升期已挂起一个待应用的自然变向（挂起唯一，后到作废）
var _air_prev := false ## 上一帧是否滞空（起跳 / 落地沿检测）

## `probe` 签名 `(origin: Vector2, dir: Vector2, length: float) -> bool`，可为空（则只做解析边界探测）。
func _init(rng: RandomNumberGenerator, config: AvoidanceController.Config, probe := Callable()) -> void:
	_rng = rng
	_probe = probe
	# 躲避控制独立随机源：与开火骰分开，避免共享序列改变既有开火行为。
	var avoid_rng := RandomNumberGenerator.new()
	avoid_rng.seed = rng.seed ^ 0x5F356495
	avoidance = AvoidanceController.new(avoid_rng, config)
	# 跳跃骰独立随机源（ADR-0023）：与开火骰、躲避骰都分开——固定种子测试不因新增跳跃而连锁改。
	_jump_rng = RandomNumberGenerator.new()
	_jump_rng.seed = rng.seed ^ 0x1B8C9A5F

## 在指定位置出现：满血、存活、清空开火状态、重抽躲避节奏。
func spawn(at: Vector2) -> void:
	sim.reset(at)
	hp = MAX_HP
	alive = true
	respawn_left = 0.0
	_reset_fire()
	_flip_hold = 0.0
	_sliding = false
	_slide_jump = false
	_slide_cd = 0.0
	_jump_wait = -1.0
	_air_strafe = 0.0
	_air_armed = false
	_air_prev = false
	avoidance.spawn()

## 清除攻击锁定与两项计时（玩家重生时调用）：bot 之后重新按视锥计时。
func stop_firing() -> void:
	_reset_fire()

## 推进一帧。返回本帧的开火结果列表（每项 = 该发是否命中玩家），由场景结算扣血与表现。
func update(dt: float, p: Perception) -> Array:
	var shots: Array = []
	if not alive:
		respawn_left = maxf(0.0, respawn_left - dt)
		return shots

	# 空中机动沿检测（票 12 / ADR-0024）：起跳沿锁定侧向快照；落地沿清挂起；
	# 多跳连跳帧级 airborne 连成一段（无落地沿）→ 挂起清零改挂 apex 沿：过最高点即消费挂起的
	# 变向（快照跟进到已翻方向）。快照记录先于本帧变向判定（起跳沿先跑）。
	var air := sim.airborne()
	var rising := air and sim.vertical_speed() > 0.0
	if air and not _air_prev:
		_air_strafe = float(avoidance.dir)
		_air_armed = false
	elif not air and _air_prev:
		_air_armed = false
	elif _air_armed and not rising:
		_air_armed = false
		_air_strafe = float(avoidance.dir)
	_air_prev = air
	# 自然变向分段（ADR-0024）：空中挂起中后到作废、下降期丢弃；地面与空中上升期未挂起照常。
	var allow := not (air and (_air_armed or not rising))
	var flipped := avoidance.update(dt, allow)
	if flipped and air:
		_air_armed = true
	_flip_hold = maxf(0.0, _flip_hold - dt)
	var pos := sim.position()
	# 「朝向」= 指向玩家的水平方向（yaw 绕 +Y 右旋，前向 world = (-sin, -cos)）；
	# 「bot 滑铲」期间下面由 _slide_face 改写（先转向滑行方向、再按角速度回头，ADR-0017）。
	sim.set_facing(_player_yaw(pos, p))
	_slide_cd = maxf(0.0, _slide_cd - dt)
	var jump_now := _tick_jump(dt, p) # 到点判定先于滑铲分支：信号只在常规路径消费
	# 「滑铲全程」（ADR-0016 + 0017）：零输入直线滑行、随机时刻铲跳或站起；
	# 朝向先转向滑行方向再按 360°/s 转回玩家，瞄住（夹角 ≤10°）前开火闸关闭。
	if _sliding:
		_slide_face(dt, pos, p)
		_tick_slide(dt)
		sim.advance(dt)
		if sim.state() != "sliding":
			_end_slide_state()
		_handle_walls()
		return _update_firing(dt, p, _slide_aimed(pos, p))
	# 「攻击滑铲」触发：视线被挡（bot 透视知道玩家在哪）且冷却已过 → 滑铲抢位。
	if p.slide_attack and _slide_cd <= 0.0 and not p.line_of_sight and _try_attack_slide(pos, p):
		sim.advance(dt)
		_handle_walls()
		return _update_firing(dt, p, false) # 刚注入仍在起步转身段：必然未瞄住，不开火
	var strafe := float(avoidance.dir)
	var fwd := _fore_input(p)

	var r := pos.length()
	if r >= MovementSimulator.ARENA_RADIUS - WALL_EPS:
		# 贴墙内拐：本帧输入整体替换为「朝圆心」——速度弧线回内、不沿墙切线滑行。
		var inward := MovementSimulator.world_to_local(-pos.x / r, -pos.y / r, sim.get_facing())
		strafe = inward.x
		fwd = inward.y
	else:
		# 空中机动（票 12 / ADR-0024）：前后输入归零——空中无加减速，前向输入只会把速度
		# 整体拉向面朝方向（bot 面朝玩家 = 空中朝玩家窜）；侧向上升期喂起跳快照
		# （自然变向挂起到最高点）、下降期喂当前方向（已翻即已应用，丢弃者方向未变）。
		# 贴墙内拐分支整体豁免（安全行为优先），本覆盖只在常规路径生效。
		if air:
			fwd = 0.0
			strafe = _air_strafe if rising else float(avoidance.dir)
		# 前向探测（ADR-0005）：提前变向，复用撞墙反向的优惠语义。
		# 承诺窗口内不翻——两个侧向都被探到受阻时，每帧翻向会把速度抖没。
		var probe_len := _probe_length(p)
		if probe_len > 0.0 and _flip_hold <= 0.0 and _probe_blocked(pos, strafe, fwd, probe_len):
			_wall_flip()
			strafe = float(avoidance.dir)
			_flip_hold = FLIP_COMMIT

	var ctl := MovementSimulator.MoveControl.new()
	ctl.right = strafe
	ctl.fwd = fwd
	ctl.jump = jump_now # 一帧信号：movement 普通跳分支接管（垂直 286、水平继承、空中照常输入）
	sim.set_control(ctl)
	sim.set_zoom(1.0 if p.ads else 0.0) # 常驻开镜只体现为移速封顶，无视觉开镜
	sim.advance(dt)

	_handle_walls()
	return _update_firing(dt, p)

## 受一次伤害。返回本次是否致命。「致命」那一发不躲避；非致命则躲避 + 受击反击。
func take_damage(damage: int, p: Perception) -> bool:
	if not alive:
		return false
	hp -= damage
	if hp <= 0:
		hp = 0
		alive = false
		respawn_left = RESPAWN_DELAY
		sim.reset()
		_sliding = false
		_slide_jump = false
		_jump_wait = -1.0
		_air_strafe = 0.0
		_air_armed = false
		_air_prev = false
		_reset_fire()
		return true
	_try_dodge(p)
	# 受击反击：跳过视锥 350ms 连续计时，立即进入攻击锁定。
	_fire_lock = true
	_aim_timer = 0.0
	_fire_timer = 0.0
	return false

## 本帧的开火结果是否为空（供场景少走一次分支）。
func can_fire() -> bool:
	return alive and _fire_lock

## 物理求解确认本帧几乎没动（撞上遮挡物或柱角）时的兜底：复用撞墙反向的优惠语义。
## `intended` / `actual` 是本帧「纯逻辑步长」与「物理实际位移」（世界单位）。
## 探测是预测、物理是事实——探测射线从身体中心发出，探不到身体边缘已经剐上的柱角，
## 于是会出现「纯逻辑满速、物理位移归零」的原地卡死，这里用同一套翻向把它解开。
## 与「前向探测」共用承诺窗口：否则每帧翻向会让「转向衰减」反复重触发、速度塌到近 0。
func on_blocked(intended: float, actual: float) -> bool:
	if intended <= 1e-6 or actual >= intended * BLOCK_RATIO:
		return false
	if _flip_hold > 0.0 or avoidance.dir == AvoidanceController.DIR_NONE:
		return false
	_wall_flip()
	_flip_hold = FLIP_COMMIT
	return true

# ---- 进退 ----

func _fore_input(p: Perception) -> float:
	return _wander_input(p) if p.wander_mode else -_range_input(p)

## 「保持距离」：距离误差的比例控制，误差越大推力越满（封顶 ±1），避免开关式往返振荡。
func _range_input(p: Perception) -> float:
	var e := sim.position().distance_to(Vector2(p.player_x, p.player_z)) - p.target_range
	if absf(e) <= RANGE_DEADBAND:
		return 0.0
	var sign := -1.0 if e > 0.0 else 1.0
	return sign * minf(1.0, (absf(e) - RANGE_DEADBAND) / RANGE_PROPORTIONAL_SPAN)

## 「动态游走」：「走廊」硬约束优先（越界不看掷骰、直接满幅归位），走廊内用当前掷出的前后分量。
func _wander_input(p: Perception) -> float:
	var e := sim.position().distance_to(Vector2(p.player_x, p.player_z)) - p.target_range
	if e > p.range_amp:
		return 1.0
	if e < -p.range_amp:
		return -1.0
	if avoidance.fore_mix == AvoidanceController.FORE_FORWARD:
		return 1.0
	if avoidance.fore_mix == AvoidanceController.FORE_BACK:
		return -1.0
	return 0.0

# ---- 前向探测与撞墙 ----

func _probe_length(p: Perception) -> float:
	return probe_length_for(p.arena_layout)

## 「前向探测」长度的静态取值（场景在「重生滑铲」时用同一口径）。
static func probe_length_for(layout: int) -> float:
	return float(PROBE_LENGTHS[clampi(layout, 0, PROBE_LENGTHS.size() - 1)])

## 沿本帧移动方向探测：解析边界优先，其次交给注入的射线（遮挡物）。
func _probe_blocked(pos: Vector2, strafe: float, fwd: float, length: float) -> bool:
	var yaw := sim.get_facing()
	var c := cos(yaw)
	var s := sin(yaw)
	var dx := strafe * c + fwd * -s
	var dz := strafe * -s + fwd * -c
	var m := sqrt(dx * dx + dz * dz)
	if m < 1e-6:
		return false
	var dir := Vector2(dx / m, dz / m)
	if _hits_boundary(pos, dir, length):
		return true
	return bool(_probe.call(pos, dir, length)) if _probe.is_valid() else false

## 沿 `dir` 的射线是否在 `length` 内打到半径 `ARENA_RADIUS` 的圆边界。
func _hits_boundary(pos: Vector2, dir: Vector2, length: float) -> bool:
	var radius := MovementSimulator.ARENA_RADIUS
	var b := pos.dot(dir)
	var disc := b * b - (pos.dot(pos) - radius * radius)
	if disc < 0.0:
		return false
	var t := -b + sqrt(disc)
	return t > 0.0 and t <= length

func _handle_walls() -> void:
	if avoidance.dir == AvoidanceController.DIR_NONE:
		return
	var pos := sim.position()
	if pos.length() < MovementSimulator.ARENA_RADIUS - WALL_EPS:
		return
	if _pushes_outward(pos, _strafe_dir_vec(avoidance.dir, sim.get_facing())):
		_wall_flip()

## 「撞墙反向」统一入口（票 12 / ADR-0024）：翻向 + 空中侧向快照同步。
## 安全纠正（前向探测 / 贴墙外推 / 物理受阻）不受空中变向分段管制，当帧立即生效；
## 不同步快照的话，上升期的翻向会被旧快照滞留到 apex 才体现（违反「立即生效」）。
func _wall_flip() -> void:
	avoidance.wall_flip()
	_air_strafe = float(avoidance.dir)

## 「侧向」方向在世界坐标下的单位向量（相对自身朝向，与移动模型的 right 轴约定一致）。
func _strafe_dir_vec(dir: int, yaw: float) -> Vector2:
	var c := cos(yaw)
	var s := sin(yaw)
	return Vector2(-c, s) if dir < 0 else Vector2(c, -s)

func _pushes_outward(pos: Vector2, v: Vector2) -> bool:
	return pos.dot(v) > 0.0

# ---- bot 滑铲（ADR-0016）----

## 「重生滑铲」：刷新瞬间沿玩家连线垂直方向（左右各 50%）注入滑铲；两侧都受阻则放弃。
## 由场景在 `spawn()` 之后调用一次。
func try_respawn_slide(player_pos: Vector2, probe_len: float, jump: bool, jump_prob: float) -> void:
	if not alive or _sliding:
		return
	var pos := sim.position()
	var line := player_pos - pos
	if line.length() < 1e-6:
		return
	var perp := Vector2(-line.y, line.x).normalized()
	var dir := perp if _rng.randf() < 0.5 else -perp
	if _slide_dir_blocked(pos, dir, probe_len):
		dir = -dir
		if _slide_dir_blocked(pos, dir, probe_len):
			return
	_begin_slide(dir, jump, jump_prob)

## 「攻击滑铲」方向采样：玩家连线 ±90° 内随机取向，最多 SLIDE_DIR_TRIES 次避障重试。
func _try_attack_slide(pos: Vector2, p: Perception) -> bool:
	var line := Vector2(p.player_x, p.player_z) - pos
	if line.length() < 1e-6:
		return false
	var base := atan2(line.y, line.x)
	for i in SLIDE_DIR_TRIES:
		var a := base + (_rng.randf() * 2.0 - 1.0) * PI * 0.5
		var dir := Vector2(cos(a), sin(a))
		if not _slide_dir_blocked(pos, dir, _probe_length(p)) \
				and _begin_slide(dir, p.slide_jump, p.slide_jump_prob):
			return true
	return false

## 注入滑铲并掷本次的随机节奏：滑行时长、是否铲跳与铲跳时刻（不晚于站起时刻）。
func _begin_slide(dir: Vector2, jump: bool, jump_prob: float) -> bool:
	if not sim.start_slide(dir, SLIDE_INJECT_SPEED):
		return false
	_sliding = true
	_slide_t = 0.0
	_slide_end_at = _rng.randf_range(SLIDE_MIN_T, SLIDE_MAX_T)
	_slide_jump = jump and _rng.randf() < jump_prob
	_slide_jump_at = minf(_rng.randf_range(SLIDE_JUMP_MIN_T, SLIDE_JUMP_MAX_T), _slide_end_at)
	# 朝向状态机（ADR-0017）：起步段从当前朝向插值到滑行方向，之后按角速度转回玩家。
	_slide_dir = dir
	_slide_face_from = sim.get_facing()
	return true

## 滑铲推进：零输入（继承滑铲方向）、到点铲跳（不松蹲）、到点站起。
func _tick_slide(dt: float) -> void:
	_slide_t += dt
	var ctl := MovementSimulator.MoveControl.new()
	if _slide_jump and _slide_t >= _slide_jump_at:
		_slide_jump = false
		ctl.jump = true # movement.gd 的滑铲跳分支处理：继承方向、垂直 286、空中带摩擦
	sim.set_control(ctl)
	if _slide_t >= _slide_end_at and sim.state() == "sliding":
		sim.end_slide() # 随机时刻站起

## 滑铲状态收尾（滑完 / 铲跳升空 / 手动站起统一走这里）。
func _end_slide_state() -> void:
	_sliding = false
	_slide_jump = false
	_slide_cd = SLIDE_CD

## 滑铲朝向状态机（ADR-0017）：起步 SLIDE_TURN_TO_DIR_T 秒内从起始朝向插值到滑行方向，
## 之后以 SLIDE_TURN_SPEED 角速度转回玩家。常规路径的 set_facing（指向玩家）在这里被改写。
func _slide_face(dt: float, pos: Vector2, p: Perception) -> void:
	if _slide_t < SLIDE_TURN_TO_DIR_T:
		var k := clampf(_slide_t / SLIDE_TURN_TO_DIR_T, 0.0, 1.0)
		sim.set_facing(lerp_angle(_slide_face_from, _dir_yaw(_slide_dir), k))
		return
	var to_player := _player_yaw(pos, p)
	var step := clampf(
		wrapf(to_player - sim.get_facing(), -PI, PI), -SLIDE_TURN_SPEED * dt, SLIDE_TURN_SPEED * dt
	)
	sim.set_facing(sim.get_facing() + step)

## 滑铲中是否已「瞄住」玩家：起步转身段不算，之后与玩家方向夹角 ≤ SLIDE_AIM_TOL 即瞄住。
func _slide_aimed(pos: Vector2, p: Perception) -> bool:
	if _slide_t < SLIDE_TURN_TO_DIR_T:
		return false
	return absf(wrapf(_player_yaw(pos, p) - sim.get_facing(), -PI, PI)) <= SLIDE_AIM_TOL

## 玩家方向 → 朝向 yaw（前向 world = (-sin, -cos)）。
func _player_yaw(pos: Vector2, p: Perception) -> float:
	return atan2(-(p.player_x - pos.x), -(p.player_z - pos.y))

## 世界方向 → 朝向 yaw（前向 world = (-sin, -cos)）。
func _dir_yaw(dir: Vector2) -> float:
	return atan2(-dir.x, -dir.y)

## 滑铲方向的避障探测：解析边界 + 注入射线（与「前向探测」同一套判据）。
func _slide_dir_blocked(pos: Vector2, dir: Vector2, length: float) -> bool:
	if _hits_boundary(pos, dir, length):
		return true
	return bool(_probe.call(pos, dir, length)) if _probe.is_valid() else false

# ---- bot 跳跃（票 11 / ADR-0023）----

## 推进「bot 跳跃」计时器，到点判定是否发本帧跳跃信号（一帧即逝，movement 普通跳分支接管）。
## 门控：非滑铲（滑铲中的跳归铲跳管）、视线通畅（被挡时跳浪费频率配额）。
## 空中到点**放行**（票 12 / ADR-0024 修订）：movement 的 `_pending_jump` 把信号锁存到落地帧消费——
## 落地瞬间立即起跳（bhop），连跳节奏 = 滞空周期，地面间隙归零。到点不满足 → 本轮作废、
## 立即重抽下一轮间隔，不排队等待。开关关闭时计时器冻结（重开后从原值继续倒数）。
func _tick_jump(dt: float, p: Perception) -> bool:
	if not p.jump_enabled:
		return false
	if _jump_wait < 0.0:
		_jump_wait = _roll_jump_wait(p) # 「刷新」后的首帧：重抽首跳间隔，本轮不判定
		return false
	_jump_wait -= dt
	if _jump_wait > 0.0:
		return false
	_jump_wait = _roll_jump_wait(p) # 跳了或作废都从这里起算下一轮
	if _sliding or sim.state() == "sliding" or not p.line_of_sight:
		return false
	return true

## 在「跳跃间隔」窗口内抽下一轮等待秒数（min > max 时归一，防设置手滑）。
func _roll_jump_wait(p: Perception) -> float:
	return _jump_rng.randf_range(minf(p.jump_min, p.jump_max), maxf(p.jump_min, p.jump_max))

# ---- 躲避 ----

## 被命中时按概率立刻翻向。贴墙且翻出去的新方向朝外时这次不生效
## （否则下一帧的墙逻辑会把它翻回来，等于骰子白掷却偷偷改了变向计时）。
func _try_dodge(p: Perception) -> void:
	if not alive or avoidance.dir == AvoidanceController.DIR_NONE:
		return
	var chance: float = p.dodge_chance
	if chance <= 0.0:
		return
	var pos := sim.position()
	if pos.length() >= MovementSimulator.ARENA_RADIUS - WALL_EPS:
		if _pushes_outward(pos, _strafe_dir_vec(-avoidance.dir, sim.get_facing())):
			return
	# 躲避是方向确定事件（ADR-0024）：空中翻向立即生效，同步侧向快照（同 _wall_flip）。
	if avoidance.dodge(chance):
		_air_strafe = float(avoidance.dir)

# ---- 开火 ----

func _update_firing(dt: float, p: Perception, aimed := true) -> Array:
	var shots: Array = []
	if not p.fire_enabled:
		_reset_fire()
		return shots
	if not aimed:
		# 「滑铲未瞄住」（ADR-0017）：开火闸关闭——不掷骰、不积累瞄准、不清锁定
		# （锁已持有则瞄住瞬间恢复开火；未持有则照常走瞄准积累）。
		return shots
	if not _fire_lock:
		_aim_timer = _aim_timer + dt if _in_aim_cone(p) else 0.0
		if _aim_timer >= AIM_HOLD:
			_fire_lock = true
			_aim_timer = 0.0
			_fire_timer = 0.0 # 触发瞬间立即开火
	if not _fire_lock:
		return shots
	_fire_timer -= dt
	while _fire_timer <= 0.0:
		_fire_timer += FIRE_INTERVAL
		if not _fire_lock:
			break
		# 「视线判定」（ADR-0006）：被遮挡则本发不开火——不掷骰、不消耗随机数。
		if not p.line_of_sight:
			continue
		shots.append(_rng.randf() < float(p.hit_rate) / 100.0)
	return shots

## 「瞄准视锥」：视线到 bot 通体包络（底 0 → 顶 72、水平半宽 = 体型半径）的角误差 < 半角 10°。
## 做成 static 是为了让「刷新点筛选」用同一套判据（口径只有一处，不重复实现）。
static func in_aim_cone(
	player_x: float,
	player_z: float,
	player_eye_y: float,
	player_yaw: float,
	player_pitch: float,
	body_radius: float,
	bot_x: float,
	bot_z: float
) -> bool:
	var dx := bot_x - player_x
	var dz := bot_z - player_z
	var horiz := sqrt(dx * dx + dz * dz)
	if horiz < 1e-6:
		return true # 叠位贴脸视为锥内
	var yaw_to_bot := atan2(-dx, -dz)
	var half_w := atan2(body_radius, horiz) # 水平看偏先扣通体半宽角
	var yaw_err := maxf(0.0, _ang_dist(player_yaw, yaw_to_bot) - half_w)
	var p_feet := atan2(-player_eye_y, horiz)
	var p_top := atan2(BODY_HEIGHT - player_eye_y, horiz)
	var elev_err := 0.0
	if player_pitch < p_feet:
		elev_err = p_feet - player_pitch
	elif player_pitch > p_top:
		elev_err = player_pitch - p_top
	return sqrt(yaw_err * yaw_err + elev_err * elev_err) < AIM_CONE_HALF

func _in_aim_cone(p: Perception) -> bool:
	var pos := sim.position()
	return in_aim_cone(
		p.player_x, p.player_z, p.player_eye_y, p.player_yaw, p.player_pitch, p.body_radius, pos.x, pos.y
	)

func _reset_fire() -> void:
	_fire_timer = 0.0
	_aim_timer = 0.0
	_fire_lock = false

## [-π, π] 内的最小夹角。
static func _ang_dist(a: float, b: float) -> float:
	return absf(atan2(sin(a - b), cos(a - b)))