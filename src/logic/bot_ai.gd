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

## `probe` 签名 `(origin: Vector2, dir: Vector2, length: float) -> bool`，可为空（则只做解析边界探测）。
func _init(rng: RandomNumberGenerator, config: AvoidanceController.Config, probe := Callable()) -> void:
	_rng = rng
	_probe = probe
	# 躲避控制独立随机源：与开火骰分开，避免共享序列改变既有开火行为。
	var avoid_rng := RandomNumberGenerator.new()
	avoid_rng.seed = rng.seed ^ 0x5F356495
	avoidance = AvoidanceController.new(avoid_rng, config)

## 在指定位置出现：满血、存活、清空开火状态、重抽躲避节奏。
func spawn(at: Vector2) -> void:
	sim.reset(at)
	hp = MAX_HP
	alive = true
	respawn_left = 0.0
	_reset_fire()
	_flip_hold = 0.0
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

	avoidance.update(dt)
	_flip_hold = maxf(0.0, _flip_hold - dt)
	var pos := sim.position()
	# 「朝向」= 始终指向玩家的水平方向（yaw 绕 +Y 右旋，前向 world = (-sin, -cos)）
	sim.set_facing(atan2(-(p.player_x - pos.x), -(p.player_z - pos.y)))
	var strafe := float(avoidance.dir)
	var fwd := _fore_input(p)

	var r := pos.length()
	if r >= MovementSimulator.ARENA_RADIUS - WALL_EPS:
		# 贴墙内拐：本帧输入整体替换为「朝圆心」——速度弧线回内、不沿墙切线滑行。
		var inward := MovementSimulator.world_to_local(-pos.x / r, -pos.y / r, sim.get_facing())
		strafe = inward.x
		fwd = inward.y
	else:
		# 前向探测（ADR-0005）：提前变向，复用撞墙反向的优惠语义。
		# 承诺窗口内不翻——两个侧向都被探到受阻时，每帧翻向会把速度抖没。
		var probe_len := _probe_length(p)
		if probe_len > 0.0 and _flip_hold <= 0.0 and _probe_blocked(pos, strafe, fwd, probe_len):
			avoidance.wall_flip()
			strafe = float(avoidance.dir)
			_flip_hold = FLIP_COMMIT

	var ctl := MovementSimulator.MoveControl.new()
	ctl.right = strafe
	ctl.fwd = fwd
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
	avoidance.wall_flip()
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
	return float(PROBE_LENGTHS[clampi(p.arena_layout, 0, PROBE_LENGTHS.size() - 1)])

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
		avoidance.wall_flip()

## 「侧向」方向在世界坐标下的单位向量（相对自身朝向，与移动模型的 right 轴约定一致）。
func _strafe_dir_vec(dir: int, yaw: float) -> Vector2:
	var c := cos(yaw)
	var s := sin(yaw)
	return Vector2(-c, s) if dir < 0 else Vector2(c, -s)

func _pushes_outward(pos: Vector2, v: Vector2) -> bool:
	return pos.dot(v) > 0.0

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
	avoidance.dodge(chance)

# ---- 开火 ----

func _update_firing(dt: float, p: Perception) -> Array:
	var shots: Array = []
	if not p.fire_enabled:
		_reset_fire()
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