## 移动系统：Apex 向量模型（移植自参考实现 movement.ts）。
##
## 水平速度是向量（世界坐标），输入给方向 + 目标速度；方向突变走「转向衰减」；
## 垂直分量独立（跳跃 / 重力）。按固定子步 1/240 做分段线性积分，帧率无关。
##
## 本类是**纯逻辑**：不依赖节点树，可直接构造与断言（ADR-0009 / ADR-0013）。
## 全部数值是 Apex 实测值，不是推导值——任何「看起来更合理」的调整都算有意偏离，必须先记 ADR。
##
## ⚠ 内部一律用标量 double（`_vx` / `_wish_dx` …），**不用 `Vector2`**：
## Godot 的 `Vector2` 分量是 float32，会让 45° 整的斜前方判定（dot 恰等于 cos(π/4)）
## 掉到容差之外、疾跑与滑铲都触发不了，速度也会带上 ~1e-3 的偏差。
## 对外读数仍返回 `Vector2`（float32 精度对外部展示足够）。

class_name MovementSimulator
extends RefCounted

# ---- 常量（Apex 实测值）----

const BASE_SPEED := 199.5 ## 基础速度（前/后/左/右同值）
const MID_SPEED := 125.4 ## 两段式加速分界
const ACCEL_1 := 2612.5 ## 第一段加速斜率
const ACCEL_2 := 522.83 ## 第二段加速斜率
const RELEASE_DECEL := 1399.19 ## 松手减速（摩擦）
const SPRINT_SPEED := 299.0 ## 疾跑目标（= 基础 ×1.5）
const SPRINT_ACCEL := 122.0 ## 越过行走满速后的疾跑慢爬
const SPRINT_DECEL := 1311.0 ## 疾跑松手减速
const CROUCH_SPEED := 92.0 ## 蹲伏行走目标
const SPEED_MULT_GUN := 0.87 ## 持枪修正
const SPEED_MULT_ADS := 0.652 ## 开镜修正
const JUMP_VELOCITY := 286.0 ## 跳跃垂直初速
const GRAVITY := 790.0 ## 重力
const SLIDE_INITIAL_FACTOR := 1.53 ## 滑铲初始速度倍率
const SLIDE_DECEL := 210.0 ## 滑铲减速（×「速度修正器」）
const SLIDE_MIN_SPEED := 200.0 ## 滑铲最低触发速度
const CROUCH_HEIGHT := -30.0 ## 蹲伏高度差
const CROUCH_DOWN_TIME := 0.15 ## 蹲到位时间（滑铲减速由此门控）
const AIR_TURN_RATE := 6.0 ## 空中 / 滑铲转向速率上限（rad/s）
const MAX_AIR_SPEED := 500.0 ## 空中 / 滑铲水平速度上限（覆盖铲跳 ≈480）
const AIR_FRICTION_SLIDE_JUMP := 103.0 ## 滑铲跳跃独有的空中摩擦
const SUBSTEP := 1.0 / 240.0 ## 固定子步

const STICK_DEADZONE := 0.13 ## 左摇杆每轴死区（「摇杆离散」）
const TURN_THRESHOLD := 0.03 ## ~1.7° 视为方向一致
const TURN_SNAP_RATE := 16.0 ## 转向衰减中速度方向向新输入的收敛速率（rad/s）
const FORWARD_CONE := PI / 4.0 ## 疾跑前进半球 ±45°
const ARENA_RADIUS := 1000.0 ## 场地半径：圆心在原点、径向钳制（ADR-0004）

## 速度保留率数据表（0°/45°/90°/180° → 100%/87%/65%/5%）；疾跑更低。
## 公式 cos(θ/2)^1.2 与 45° 实测不符，参考实现已改用实测分段表，此处照抄。
const RET_WALK := [[0.0, 1.0], [45.0, 0.87], [90.0, 0.65], [180.0, 0.05]]
const RET_SPRINT := [[0.0, 1.0], [45.0, 0.73], [90.0, 0.445], [180.0, 0.05]]

## 转向衰减 / 恢复速率的实测点：角度 → [减速速率, 恢复速率]
const TURN_RATE_POINTS := [
	[PI / 4.0, 490.0, 354.0],
	[PI / 2.0, 1080.0, 380.0],
	[PI, 2797.0, 1282.0],
]

## 单帧控制意图：方向（右/前，+1 满幅）与动作位（疾跑 / 蹲 / 跳）。
class MoveControl:
	var right := 0.0
	var fwd := 0.0
	var sprint := false
	var crouch := false
	var jump := false

## 转向衰减 / 恢复会话。
class TurnSession:
	var retained := 0.0 ## 触发时速度 × 保留率
	var dec := 0.0 ## 转向减速速率（角度依赖）
	var rec := 0.0 ## 恢复速率（角度依赖）
	var theta0 := 0.0 ## 触发时夹角（θ 明显变大时重建会话）

## 速度保留率：按实测表分段线性（0°/45°/90°/180°）。
static func retention(angle_rad: float, sprint: bool) -> float:
	var deg := absf(angle_rad) * 180.0 / PI
	var tab: Array = RET_SPRINT if sprint else RET_WALK
	if deg <= float(tab[0][0]):
		return float(tab[0][1])
	if deg >= float(tab[tab.size() - 1][0]):
		return float(tab[tab.size() - 1][1])
	for i in range(1, tab.size()):
		if deg <= float(tab[i][0]):
			var t: float = (deg - float(tab[i - 1][0])) / (float(tab[i][0]) - float(tab[i - 1][0]))
			return float(tab[i - 1][1]) + (float(tab[i][1]) - float(tab[i - 1][1])) * t
	return float(tab[tab.size() - 1][1])

## 滑铲跳跃速度倍率公式（速度越高倍率越低：满速 ≈1.53、低速更高）。
static func slide_jump_ratio(speed: float) -> float:
	return 2.454 - (speed / SPRINT_SPEED) * 0.919

## 世界水平向量 → 自身「朝向」系分量：x = lat（正=右）、y = fwd（正=前）。
## 是 wishDir 那个「局部→世界」映射的逆（同一朝向约定：yaw 绕 +Y 右旋，前向 world = (-sin, -cos)），
## 因此是等距变换——单位向量进、单位向量出。
static func world_to_local(dx: float, dz: float, yaw: float) -> Vector2:
	var c := cos(yaw)
	var s := sin(yaw)
	return Vector2(dx * c - dz * s, -(dx * s + dz * c))

## 转向衰减 / 恢复速率：按角度在三组实测点间线性插值，返回 (dec, rec)。
static func turn_rates(theta: float) -> Vector2:
	var pts: Array = TURN_RATE_POINTS
	var a := absf(theta)
	if a <= float(pts[0][0]):
		return Vector2(float(pts[0][1]), float(pts[0][2]))
	if a >= float(pts[2][0]):
		return Vector2(float(pts[2][1]), float(pts[2][2]))
	for i in range(1, pts.size()):
		if a <= float(pts[i][0]):
			var t: float = (a - float(pts[i - 1][0])) / (float(pts[i][0]) - float(pts[i - 1][0]))
			return Vector2(
				float(pts[i - 1][1]) + (float(pts[i][1]) - float(pts[i - 1][1])) * t,
				float(pts[i - 1][2]) + (float(pts[i][2]) - float(pts[i - 1][2])) * t
			)
	return Vector2(float(pts[2][1]), float(pts[2][2]))

var _radius := ARENA_RADIUS
var _px := 0.0
var _pz := 0.0
var _vx := 0.0 ## 世界水平速度
var _vz := 0.0
var _height_v := 0.0 ## 跳跃高度（≥0）
var _vz_v := 0.0 ## 垂直速度
var _crouch_p := 0.0 ## 0 站 / 1 蹲
var _airborne := false
var _slide := false
var _slide_auto := false ## 注入滑铲（bot 用，ADR-0016）：维持不依赖蹲键
var _slide_friction := false
var _sprint_latch := false ## 疾跑粘滞：Shift 松开但前向输入持续时保持疾跑
var _yaw := 0.0
var _zoom := 0.0
var _ctl_right := 0.0
var _ctl_fwd := 0.0
var _ctl_sprint := false
var _ctl_crouch := false
var _prev_jump := false
var _pending_jump := false
var _wish_dx := 0.0 ## 本步输入方向（世界，单位向量）
var _wish_dz := 0.0
var _has_wish := false
var _state := "idle"
var _turn: TurnSession = null
var _acc := 0.0 ## 子步余量

func _init(radius := ARENA_RADIUS, initial := Vector2.ZERO) -> void:
	_radius = radius
	_px = initial.x
	_pz = initial.y

func set_control(c: MoveControl) -> void:
	if c.jump and not _prev_jump:
		_pending_jump = true
	_prev_jump = c.jump
	_ctl_right = c.right
	_ctl_fwd = c.fwd
	_ctl_sprint = c.sprint
	_ctl_crouch = c.crouch

func set_facing(yaw: float) -> void:
	_yaw = yaw

func get_facing() -> float:
	return _yaw

func set_zoom(p: float) -> void:
	_zoom = clampf(p, 0.0, 1.0)

## 直接注入一次滑铲（bot 用，ADR-0016）：沿世界方向 `dir` 以 `speed` 初速进入滑铲。
## 不要求疾跑前摇与蹲键——玩家不该看到 bot 的滑铲预备；维持不靠蹲键（`_slide_auto`）。
func start_slide(dir: Vector2, speed: float) -> bool:
	if _airborne or _slide or speed <= 0.0:
		return false
	var m := sqrt(dir.x * dir.x + dir.y * dir.y)
	if m < 1e-6:
		return false
	_slide = true
	_slide_auto = true
	_turn = null
	_sprint_latch = false
	_vx = dir.x / m * speed
	_vz = dir.y / m * speed
	_state = "sliding"
	return true

## 提前结束注入滑铲（bot 在随机时刻站起，恢复常规躲避）。
func end_slide() -> void:
	if _slide and _slide_auto:
		_slide = false
		_slide_auto = false

## 蹲伏进度（0 站 / 1 蹲）：命中体压低与滑铲表现共用。
func crouch_progress() -> float:
	return _crouch_p

## 场景层碰撞求解后回写位置（ADR-0002）：`CharacterBody3D.move_and_slide()` 的结果可能与
## 本类的积分位置不同（被箱体/柱体挡住）。把求解后的真实位置同步回来，避免下一帧
## 又从「穿进障碍物里」的位置继续积分。速度不回写——速度仍由本类全权决定。
func sync_position(p: Vector2) -> void:
	_px = p.x
	_pz = p.y

func reset(initial := Vector2.ZERO) -> void:
	_px = initial.x
	_pz = initial.y
	_vx = 0.0
	_vz = 0.0
	_height_v = 0.0
	_vz_v = 0.0
	_crouch_p = 0.0
	_airborne = false
	_slide = false
	_slide_auto = false
	_slide_friction = false
	_sprint_latch = false
	_zoom = 0.0
	_ctl_right = 0.0
	_ctl_fwd = 0.0
	_ctl_sprint = false
	_ctl_crouch = false
	_prev_jump = false
	_pending_jump = false
	_state = "idle"
	_turn = null
	_acc = 0.0

## 推进 dt：每帧完整消费时间，最后不足一个子步的余量也按实际步长推进（不丢时间）。
func advance(dt: float) -> void:
	_acc += dt
	var guard := 4096
	while _acc > 1e-9 and guard > 0:
		guard -= 1
		var h := minf(SUBSTEP, _acc)
		_step(h)
		_acc -= h

func _step(h: float) -> void:
	if _airborne:
		_step_air(h)
	else:
		_step_ground(h)
	# 水平位置积分 + 径向边界钳制（速度保留）
	_px += _vx * h
	_pz += _vz * h
	var d := sqrt(_px * _px + _pz * _pz)
	if d > _radius and d > 1e-9:
		var k := _radius / d
		_px *= k
		_pz *= k

## 空中：垂直积分 + 空气控制。
func _step_air(h: float) -> void:
	_compute_wish()
	if _has_wish:
		var speed := sqrt(_vx * _vx + _vz * _vz)
		if speed > 1e-6:
			var mud := _angle_to_wish()
			if mud > 1e-6:
				_rotate_velocity(minf(mud, AIR_TURN_RATE * h))
	_cap_air_speed()
	if _slide_friction:
		_apply_friction(AIR_FRICTION_SLIDE_JUMP, h)
	_vz_v -= GRAVITY * h
	_height_v += _vz_v * h
	if _height_v <= 0.0 and _vz_v < 0.0:
		_height_v = 0.0
		_vz_v = 0.0
		_airborne = false
		_slide_friction = false
	_state = "airborne" if _airborne else _state

func _step_ground(h: float) -> void:
	var crouch_target := 1.0 if (_ctl_crouch or _slide) else 0.0
	_crouch_p = move_toward(_crouch_p, crouch_target, h / CROUCH_DOWN_TIME)

	var mult := _speed_mult()
	_compute_wish()
	var speed := sqrt(_vx * _vx + _vz * _vz)
	# 疾跑粘滞：进入疾跑后，只要输入仍在前向半球就保持（Shift 松开也维持）；
	# W 松开（无输入）或方向离开前向半球才退出疾跑
	var forward_ok := _forward_hemisphere()
	if not forward_ok:
		_sprint_latch = false
	if _ctl_sprint and forward_ok:
		_sprint_latch = true
	var sprinting := forward_ok and (_ctl_sprint or _sprint_latch)

	# 跳跃（普通与滑铲跳）
	if _pending_jump:
		_pending_jump = false
		if _slide:
			# 滑铲跳跃：水平 × 公式、垂直仍 286、空中带摩擦
			var ratio := slide_jump_ratio(speed)
			_vx *= ratio
			_vz *= ratio
			_slide = false
			_slide_auto = false
			_slide_friction = true
		else:
			_slide = false
			_slide_auto = false
		_vz_v = JUMP_VELOCITY
		_height_v = 0.0
		_airborne = true
		_state = "airborne"
		_turn = null
		return

	# 滑铲触发：疾跑 + 蹲 + 速度达标
	if sprinting and _ctl_crouch and not _slide and speed >= SLIDE_MIN_SPEED:
		_slide = true
		_turn = null
		_vx *= SLIDE_INITIAL_FACTOR
		_vz *= SLIDE_INITIAL_FACTOR

	if _slide:
		if not _ctl_crouch and not _slide_auto:
			_slide = false # 松开蹲提前结束（注入滑铲除外）→ 走普通减速
		else:
			var s := sqrt(_vx * _vx + _vz * _vz)
			if s <= CROUCH_SPEED + 1e-6:
				_slide = false # 降至蹲走速度 → 蹲伏行走
				_state = "crouching"
				_ground_walk(h, CROUCH_SPEED * mult)
				return
			# 滑铲转向：按住方向键时向「移动输入」方向限速收敛——
			# 斜铲（W+A）保持斜向、转镜头可拐弯、换键限速过渡不瞬时切；全松 = 直线滑行。
			if _has_wish:
				var mud := _angle_to_wish()
				if mud > 1e-6:
					_rotate_velocity(minf(mud, AIR_TURN_RATE * h))
			_cap_air_speed()
			# 滑行：蹲到最低点（crouch_p 满）后才开始减速（没蹲到底不减速）
			if _crouch_p >= 1.0 - 1e-6:
				var nd := maxf(s - SLIDE_DECEL * mult * h, 0.0)
				var k := nd / s if s > 1e-9 else 0.0
				_vx *= k
				_vz *= k
			_state = "sliding"
			return

	# 蹲伏行走：蹲到底前匀速继承当前速度（曲线是直线），蹲满后以蹲伏速度为目标
	if _ctl_crouch:
		var goal := CROUCH_SPEED * mult if _crouch_p >= 1.0 - 1e-6 else maxf(speed, CROUCH_SPEED * mult)
		_ground_walk(h, goal)
		return

	# 疾跑 / 行走
	var target := SPRINT_SPEED * mult if sprinting else _walk_target()

	if not _has_wish:
		# 松手：摩擦减速到 0
		var decel_rate := SPRINT_DECEL if speed > _walk_target() else RELEASE_DECEL
		var nd := maxf(speed - decel_rate * h, 0.0)
		var k := nd / speed if speed > 1e-9 else 0.0
		_vx *= k
		_vz *= k
		_state = "decelerating" if speed > 1e-6 else "idle"
		_turn = null
		return

	# 方向突变 → 转向衰减
	var theta := _angle_to_wish()
	if speed > 1e-6 and theta > TURN_THRESHOLD:
		var snap := TURN_SNAP_RATE * h
		if _turn == null or theta > _turn.theta0 + 0.2:
			# 新建 / 重算会话：θ 明显变大（如 WASD 依次换向）按当前 θ 重新定保留率与速率
			var r := turn_rates(theta)
			_turn = TurnSession.new()
			_turn.retained = speed * retention(theta, sprinting)
			_turn.dec = r.x
			_turn.rec = r.y
			_turn.theta0 = theta
		var cur := sqrt(_vx * _vx + _vz * _vz)
		if cur > _turn.retained + 1e-6:
			# 衰减阶段：以 dec 速率降到保留速度，方向朝新输入快收敛
			var nd := maxf(cur - _turn.dec * h, 0.0)
			var k := nd / cur if cur > 1e-9 else 0.0
			_vx *= k
			_vz *= k
			if k > 0.0:
				_rotate_velocity(snap)
			_state = "turnDecay"
		else:
			# 恢复阶段：以 rec 速率爬回目标
			var mag := minf(target, cur + _turn.rec * h)
			var k2 := mag / cur if cur > 1e-9 else 0.0
			_vx *= k2
			_vz *= k2
			_rotate_velocity(snap)
			_state = "turnRecover"
		if _angle_to_wish() <= TURN_THRESHOLD * 0.5:
			_turn = null
		return
	_turn = null

	# 对齐：直接按目标方向推进
	if speed >= target - 1e-6:
		if speed > target + 1e-6:
			# 超目标（滑铲结束后等）→ 摩擦减速
			var nd := maxf(speed - RELEASE_DECEL * h, 0.0)
			_set_velocity_to(nd)
			_state = "decelerating"
		else:
			_set_velocity_to(target)
			_state = "sprinting" if sprinting else "constant"
	else:
		var slope := _accel_slope(speed, sprinting, mult)
		_set_velocity_to(minf(target, speed + slope * h))
		_state = "sprinting" if sprinting else "accelerating"

## 蹲伏行走：无「转向衰减」的匀速段（含 90°/180° 换向）。
func _ground_walk(h: float, target: float) -> void:
	var speed := sqrt(_vx * _vx + _vz * _vz)
	_turn = null
	if not _has_wish:
		_state = "decelerating" if speed > 1e-6 else "idle"
		var nd := maxf(speed - RELEASE_DECEL * h, 0.0)
		_set_velocity_to_current(nd)
		return
	_state = "crouching"
	if speed >= target - 1e-6:
		_set_velocity_to(target)
	else:
		_set_velocity_to(minf(target, speed + ACCEL_1 * h))

func _accel_slope(speed: float, sprinting: bool, mult: float) -> float:
	var walk_cap := BASE_SPEED * mult
	if sprinting and speed >= walk_cap:
		return SPRINT_ACCEL
	if speed < MID_SPEED:
		return ACCEL_1
	return ACCEL_2

func _speed_mult() -> float:
	return SPEED_MULT_ADS if _zoom > 0.0 else SPEED_MULT_GUN

func _walk_target() -> float:
	return BASE_SPEED * _speed_mult()

## 计算本步输入方向（世界单位向量），写入 `_wish_dx` / `_wish_dz`；无输入时置 `_has_wish = false`。
## 朝向约定：yaw 绕 +Y 右旋，前向 world = (-sin, -cos)。
func _compute_wish() -> void:
	var c := cos(_yaw)
	var s := sin(_yaw)
	var dx := _ctl_right * c + _ctl_fwd * -s
	var dz := _ctl_right * -s + _ctl_fwd * -c
	var m := sqrt(dx * dx + dz * dz)
	if m < 1e-6:
		_has_wish = false
		_wish_dx = 0.0
		_wish_dz = 0.0
		return
	_has_wish = true
	_wish_dx = dx / m
	_wish_dz = dz / m

func _forward_hemisphere() -> bool:
	if not _has_wish:
		return false
	if _ctl_fwd <= 1e-6:
		return false
	var c := cos(_yaw)
	var s := sin(_yaw)
	var dot := _wish_dx * -s + _wish_dz * -c
	# 容差：45° 整（斜前方 W+A / W+D）归一化浮点误差会让 dot 略低于 cos(π/4)，必须放行
	return dot >= cos(FORWARD_CONE) - 1e-9

func _angle_to_wish() -> float:
	var s := sqrt(_vx * _vx + _vz * _vz)
	if s < 1e-9:
		return 0.0
	var dot := (_vx * _wish_dx + _vz * _wish_dz) / s
	return acos(clampf(dot, -1.0, 1.0))

## 空中 / 滑铲水平速度上限：转向 / 铲跳不得突破 MAX_AIR_SPEED，防「越转越快」。
func _cap_air_speed() -> void:
	var m := sqrt(_vx * _vx + _vz * _vz)
	if m > MAX_AIR_SPEED and m > 1e-9:
		var k := MAX_AIR_SPEED / m
		_vx *= k
		_vz *= k

func _rotate_velocity(dr: float) -> void:
	if dr <= 0.0:
		return
	var cur := atan2(_vz, _vx)
	var tar := atan2(_wish_dz, _wish_dx)
	var da := atan2(sin(tar - cur), cos(tar - cur))
	var m := sqrt(_vx * _vx + _vz * _vz)
	if m < 1e-9:
		return
	if absf(da) <= dr:
		_vx = m * _wish_dx
		_vz = m * _wish_dz
		return
	var a := cur + signf(da) * dr
	_vx = m * cos(a)
	_vz = m * sin(a)

func _set_velocity_to(mag: float) -> void:
	_vx = _wish_dx * mag
	_vz = _wish_dz * mag

func _set_velocity_to_current(mag: float) -> void:
	var s := sqrt(_vx * _vx + _vz * _vz)
	var k := mag / s if s > 1e-9 else 0.0
	_vx *= k
	_vz *= k

func _apply_friction(rate: float, h: float) -> void:
	var s := sqrt(_vx * _vx + _vz * _vz)
	var nd := maxf(s - rate * h, 0.0)
	var k := nd / s if s > 1e-9 else 0.0
	_vx *= k
	_vz *= k

# ---- 读数 ----

func position() -> Vector2:
	return Vector2(_px, _pz)

func velocity() -> Vector2:
	return Vector2(_vx, _vz)

func speed() -> float:
	return sqrt(_vx * _vx + _vz * _vz)

## 垂直速度（跳跃用）。
func vertical_speed() -> float:
	return _vz_v

## 相机高度：跳跃高度 + 蹲伏位移（−30 × 蹲进度）。
func height() -> float:
	return _height_v + CROUCH_HEIGHT * _crouch_p

func state() -> String:
	return _state