## 移动积分的行为测试（ADR-0013：本票唯一必须有的测试，核心资产回归网）。
##
## 只断言**外部行为**：给定控制意图与 dt 序列，断言速度 / 位置轨迹与状态。
## 不碰内部字段与私有方法，也不测场景装配、渲染、InputMap 映射、帧率与手感。
##
## 本仓库不引入「空手」（ADR-0010），因此一切速度都带「速度修正器」：
## 持枪 0.87、开镜 0.652。断言里的 *_CAP 即为叠乘后的封顶值。

extends GutTest

const BASE := MovementSimulator.BASE_SPEED
const GUN_CAP := BASE * MovementSimulator.SPEED_MULT_GUN # 199.5 × 0.87 ≈ 173.565
const ADS_CAP := BASE * MovementSimulator.SPEED_MULT_ADS # ≈ 130.074
const SPRINT_CAP := MovementSimulator.SPRINT_SPEED * MovementSimulator.SPEED_MULT_GUN # ≈ 260.13
const CROUCH_CAP := MovementSimulator.CROUCH_SPEED * MovementSimulator.SPEED_MULT_GUN # ≈ 80.04

func ctl(right: float, fwd: float, sprint := false, crouch := false, jump := false) -> MovementSimulator.MoveControl:
	var c := MovementSimulator.MoveControl.new()
	c.right = right
	c.fwd = fwd
	c.sprint = sprint
	c.crouch = crouch
	c.jump = jump
	return c

## 持枪满速前进 1 秒。
func run_full(sim: MovementSimulator) -> void:
	sim.set_control(ctl(0.0, 1.0))
	sim.advance(1.0)

# ---- 朝向约定与坐标换算 ----

func test_world_to_local_yaw0() -> void:
	var right := MovementSimulator.world_to_local(1.0, 0.0, 0.0)
	assert_almost_eq(right.x, 1.0, 1e-9, "yaw=0 时世界 +x 是右")
	assert_almost_eq(right.y, 0.0, 1e-9)
	var fwd := MovementSimulator.world_to_local(0.0, -1.0, 0.0)
	assert_almost_eq(fwd.x, 0.0, 1e-9)
	assert_almost_eq(fwd.y, 1.0, 1e-9, "yaw=0 时世界 −z 是前")

func test_world_to_local_facing_center_at_yaw_90() -> void:
	# 「朝圆心」向量 (−1,0) 落在前向——贴墙内拐的回归判据（符号写反会变成朝墙外）
	var v := MovementSimulator.world_to_local(-1.0, 0.0, PI / 2.0)
	assert_almost_eq(v.x, 0.0, 1e-9)
	assert_almost_eq(v.y, 1.0, 1e-9)

func test_world_to_local_is_isometric() -> void:
	# 容差按 float32 取（`world_to_local` 返回 Godot 的 Vector2，分量是 float32）
	for yaw in [-2.1, -PI / 2.0, -0.3, 0.0, 0.7, PI / 2.0, 2.4]:
		var v := MovementSimulator.world_to_local(-0.6, 0.8, yaw)
		assert_almost_eq(v.length(), 1.0, 1e-6, "yaw=%s 时是等距变换" % yaw)

func test_facing_convention_yaw_90() -> void:
	# yaw=π/2（面向 −X）：W 朝 −X 走、D 朝 −Z 走（不镜像）
	var sim := MovementSimulator.new()
	sim.set_facing(PI / 2.0)
	sim.set_control(ctl(0.0, 1.0))
	sim.advance(1.0)
	assert_almost_eq(sim.velocity().x, -GUN_CAP, 0.01, "前向 world = (-sin90, -cos90) = (-1, 0)")
	assert_almost_eq(sim.velocity().y, 0.0, 1e-3)

	var sim2 := MovementSimulator.new()
	sim2.set_facing(PI / 2.0)
	sim2.set_control(ctl(1.0, 0.0))
	sim2.advance(1.0)
	assert_almost_eq(sim2.velocity().y, -GUN_CAP, 0.01, "右向 world = (cos, -sin) = (0, -1)")
	assert_almost_eq(sim2.velocity().x, 0.0, 1e-3)

# ---- Idle 与输入契约 ----

func test_idle_without_input() -> void:
	var sim := MovementSimulator.new()
	sim.advance(0.5)
	assert_almost_eq(sim.position().x, 0.0, 1e-6)
	assert_almost_eq(sim.position().y, 0.0, 1e-6)
	assert_almost_eq(sim.speed(), 0.0, 1e-6)
	assert_eq(sim.state(), "idle")

func test_jump_is_edge_triggered_no_double_jump() -> void:
	var sim := MovementSimulator.new()
	sim.set_control(ctl(0.0, 0.0, false, false, true))
	sim.advance(0.01)
	assert_gt(sim.height(), 0.0, "起跳当帧离地")
	# 持续按住 jump 不再起跳：先看到下落，再落地
	var watched := sim.height()
	var apex_seen := false
	for i in range(100):
		sim.advance(0.01)
		if sim.height() < watched:
			apex_seen = true
			break
		watched = sim.height()
	assert_true(apex_seen, "按住不放只跳一次，会出现下落段")
	sim.advance(0.5)
	assert_almost_eq(sim.height(), 0.0, 1e-3)
	assert_ne(sim.state(), "airborne")

# ---- 行走加速（两段式剖面） ----

func test_walk_accel_two_stage_gun() -> void:
	var sim := MovementSimulator.new()
	sim.set_control(ctl(0.0, 1.0))
	sim.advance(0.048)
	assert_almost_eq(sim.velocity().y, -MovementSimulator.MID_SPEED, 1e-4, "48ms 到中间速度 125.4")
	sim.advance(0.2)
	assert_almost_eq(sim.velocity().y, -GUN_CAP, 0.01, "越过 125.4 后按第二段爬到持枪封顶")
	sim.advance(0.5)
	assert_almost_eq(sim.velocity().y, -GUN_CAP, 0.01, "持枪封顶后停住")

func test_ads_speed_cap() -> void:
	var sim := MovementSimulator.new()
	sim.set_zoom(1.0)
	sim.set_control(ctl(0.0, 1.0))
	sim.advance(2.0)
	assert_almost_eq(absf(sim.velocity().y), ADS_CAP, 0.01, "开镜封顶 = 199.5 × 0.652 ≈ 130.07")

func test_ads_to_hip_speed_ratio_is_multiplier_ratio() -> void:
	var gun := MovementSimulator.new()
	run_full(gun)
	gun.set_control(ctl(1.0, 0.0))
	gun.advance(0.5)
	var ads := MovementSimulator.new()
	ads.set_zoom(1.0)
	ads.set_control(ctl(1.0, 0.0))
	ads.advance(2.0)
	assert_almost_eq(absf(gun.velocity().x) / absf(ads.velocity().x), 0.87 / 0.652, 1e-3)

func test_multi_axis_input_is_normalized_not_summed() -> void:
	# 多轴合并钳制：W+D 斜走速度等于单轴目标，不是 ×√2
	var sim := MovementSimulator.new()
	sim.set_control(ctl(1.0, 1.0))
	sim.advance(2.0)
	assert_almost_eq(sim.speed(), GUN_CAP, 0.01, "斜向不叠加成 √2 倍")
	var diag := sim.velocity() / sim.speed()
	assert_almost_eq(absf(diag.x), absf(diag.y), 1e-6, "45° 斜向分量等幅")

# ---- 松手减速 ----

func test_release_decel_to_zero_time() -> void:
	var sim := MovementSimulator.new()
	run_full(sim)
	sim.set_control(ctl(0.0, 0.0))
	sim.advance(0.15)
	assert_almost_eq(sim.speed(), 0.0, 1e-4, "持枪满速松手 ≈0.124s 归零")
	assert_eq(sim.state(), "idle")

func test_release_keeps_direction() -> void:
	var sim := MovementSimulator.new()
	sim.set_facing(0.9)
	run_full(sim)
	var angle_before := atan2(sim.velocity().y, sim.velocity().x)
	sim.set_control(ctl(0.0, 0.0))
	sim.advance(0.05)
	assert_almost_eq(atan2(sim.velocity().y, sim.velocity().x), angle_before, 1e-6, "无输入惯性：方向保持")

# ---- 速度保留率与转向衰减 ----

func test_retention_table() -> void:
	assert_almost_eq(MovementSimulator.retention(0.0, false), 1.0, 1e-9)
	assert_almost_eq(MovementSimulator.retention(deg_to_rad(45.0), false), 0.87, 0.001)
	assert_almost_eq(MovementSimulator.retention(deg_to_rad(90.0), false), 0.65, 0.001)
	assert_almost_eq(MovementSimulator.retention(deg_to_rad(180.0), false), 0.05, 0.001)
	assert_almost_eq(MovementSimulator.retention(deg_to_rad(45.0), true), 0.73, 0.001, "疾跑保留率更低")

func test_turn_90_decay_and_recover() -> void:
	var sim := MovementSimulator.new()
	run_full(sim)
	sim.set_control(ctl(-1.0, 0.0))
	var lowest := GUN_CAP
	for i in range(100): # 0.5s @5ms
		sim.advance(0.005)
		lowest = minf(lowest, sim.speed())
	assert_lt(lowest, GUN_CAP * 0.68, "90° 换向掉到 ≈65%")
	assert_gt(lowest, GUN_CAP * 0.6)
	assert_gt(sim.speed(), GUN_CAP * 0.85, "随后恢复")
	assert_lt(sim.velocity().x, -1.0, "方向已转到新输入")

func test_turn_180_near_stop_then_reverse() -> void:
	var sim := MovementSimulator.new()
	run_full(sim)
	sim.set_control(ctl(0.0, -1.0))
	var lowest := GUN_CAP
	for i in range(60): # 0.3s @5ms
		sim.advance(0.005)
		lowest = minf(lowest, sim.speed())
	assert_lt(lowest, GUN_CAP * 0.25, "180° 掉头近停")
	sim.advance(0.5)
	assert_gt(absf(sim.velocity().y), GUN_CAP * 0.7, "反向恢复")

func test_turn_decay_time_to_bottom_is_under_100ms() -> void:
	var sim := MovementSimulator.new()
	run_full(sim)
	sim.set_control(ctl(-1.0, 0.0), )
	var lowest := GUN_CAP
	var t := 0.0
	var bottom_t := 0.0
	while t < 0.5:
		sim.advance(0.005)
		t += 0.005
		if sim.speed() < lowest:
			lowest = sim.speed()
			bottom_t = t
	assert_lt(bottom_t, 0.12, "90° 触底 ≈64ms")

# ---- 疾跑 ----

func test_sprint_accel_profile() -> void:
	var sim := MovementSimulator.new()
	sim.set_control(ctl(0.0, 1.0, true))
	sim.advance(0.048)
	assert_almost_eq(absf(sim.velocity().y), MovementSimulator.MID_SPEED, 1e-3)
	sim.advance(0.4)
	var v_mid := sim.speed()
	assert_gt(v_mid, GUN_CAP, "越过行走封顶后继续爬")
	sim.advance(0.2)
	assert_almost_eq(sim.speed() - v_mid, MovementSimulator.SPRINT_ACCEL * 0.2, 0.5, "越过行走封顶后按 ≈122 u/s² 慢爬")
	sim.advance(2.0)
	assert_almost_eq(sim.speed(), SPRINT_CAP, 0.01, "疾跑封顶 = 299 × 0.87")

func test_sprint_latch_holds_after_shift_release() -> void:
	var sim := MovementSimulator.new()
	sim.set_control(ctl(0.0, 1.0, true))
	sim.advance(3.0)
	assert_almost_eq(sim.speed(), SPRINT_CAP, 0.01)
	sim.set_control(ctl(0.0, 1.0, false))
	sim.advance(0.5)
	assert_almost_eq(sim.speed(), SPRINT_CAP, 0.01, "松开 Shift 但 W 仍按住 → 保持疾跑")
	assert_eq(sim.state(), "sprinting")
	sim.set_control(ctl(0.0, 0.0, false))
	sim.advance(0.02)
	assert_eq(sim.state(), "decelerating", "松开 W → 退出疾跑")
	assert_lt(sim.speed(), SPRINT_CAP)

func test_sprint_requires_shift_to_start() -> void:
	var sim := MovementSimulator.new()
	sim.set_control(ctl(0.0, 1.0, false))
	sim.advance(1.0)
	assert_almost_eq(sim.speed(), GUN_CAP, 0.01, "不按 Shift 不凭空疾跑")
	assert_eq(sim.state(), "constant")

func test_sprint_only_in_forward_hemisphere() -> void:
	var strafe := MovementSimulator.new()
	strafe.set_control(ctl(-1.0, 0.0, true))
	strafe.advance(2.0)
	assert_almost_eq(strafe.speed(), GUN_CAP, 0.01, "纯侧移不进疾跑")

func test_sprint_allowed_on_diagonal_and_exact_45() -> void:
	var diag := MovementSimulator.new()
	diag.set_control(ctl(-0.5, 1.0, true))
	diag.advance(3.0)
	assert_gt(diag.speed(), GUN_CAP)
	assert_lte(diag.speed(), SPRINT_CAP + 1.0)

	var exact := MovementSimulator.new()
	exact.set_control(ctl(-1.0, 1.0, true))
	exact.advance(3.0)
	assert_almost_eq(exact.speed(), SPRINT_CAP, 0.01, "斜前方 45° 整允许疾跑（浮点边界容差）")

func test_sprint_latch_requires_shift_again_after_exit() -> void:
	var sim := MovementSimulator.new()
	sim.set_control(ctl(0.0, 1.0, true))
	sim.advance(3.0)
	sim.set_control(ctl(0.0, 0.0, false))
	sim.advance(0.3)
	sim.set_control(ctl(0.0, 1.0, false))
	sim.advance(2.0)
	assert_almost_eq(sim.speed(), GUN_CAP, 0.01)

# ---- 蹲伏行走 ----

func test_crouch_walk_cap_and_no_turn_decay() -> void:
	var sim := MovementSimulator.new()
	sim.set_control(ctl(0.0, 1.0, false, true))
	sim.advance(1.0)
	assert_almost_eq(absf(sim.velocity().y), CROUCH_CAP, 0.01, "蹲走封顶 92 × 0.87")
	var before := sim.speed()
	sim.set_control(ctl(1.0, 0.0, false, true))
	sim.advance(0.5)
	assert_almost_eq(absf(sim.velocity().x), CROUCH_CAP, 0.01, "90° 换向后仍是蹲走速度")
	assert_almost_eq(before, CROUCH_CAP, 0.01)
	assert_lt(absf(sim.velocity().y), 0.01, "旧方向分量清空（无转向衰减，直接对准）")

func test_crouch_height() -> void:
	var sim := MovementSimulator.new()
	sim.set_control(ctl(0.0, 0.0, false, true))
	sim.advance(0.3)
	assert_almost_eq(sim.height(), MovementSimulator.CROUCH_HEIGHT, 0.1, "蹲伏高度 −30u")
	sim.set_control(ctl(0.0, 0.0, false, false))
	sim.advance(0.3)
	assert_almost_eq(sim.height(), 0.0, 0.1)

func test_crouch_transition_keeps_speed_until_fully_down() -> void:
	var sim := MovementSimulator.new()
	run_full(sim)
	sim.set_control(ctl(0.0, 1.0, false, true))
	sim.advance(0.1) # 蹲进度 ≈0.67 < 1：速度保持（曲线是直线）
	assert_almost_eq(absf(sim.velocity().y), GUN_CAP, 0.5)
	sim.advance(0.1) # 蹲满 → 跳变到蹲伏速度
	assert_almost_eq(absf(sim.velocity().y), CROUCH_CAP, 0.01)
	assert_eq(sim.state(), "crouching")

# ---- 跳跃与空中控制 ----

func test_jump_vertical_speed() -> void:
	var sim := MovementSimulator.new()
	sim.set_control(ctl(0.0, 1.0, false, false, true))
	sim.advance(MovementSimulator.SUBSTEP)
	assert_almost_eq(sim.vertical_speed(), MovementSimulator.JUMP_VELOCITY, 1e-3, "起跳当帧无重力")

func test_jump_airtime_and_landing() -> void:
	var sim := MovementSimulator.new()
	sim.set_control(ctl(0.0, 0.0, false, false, true))
	sim.advance(MovementSimulator.SUBSTEP)
	sim.set_control(ctl(0.0, 0.0))
	var t := 0.0
	var was_up := false
	while t < 2.0:
		sim.advance(0.01)
		t += 0.01
		if sim.height() > 0.0001:
			was_up = true
		elif was_up:
			break
	assert_gt(t, 0.7)
	assert_lt(t, 0.75, "滞空 ≈ 2×286/790 ≈ 0.724s")
	assert_almost_eq(sim.height(), 0.0, 1e-3)
	assert_ne(sim.state(), "airborne")

func test_air_control_turn_is_rate_limited() -> void:
	var sim := MovementSimulator.new()
	run_full(sim)
	sim.set_control(ctl(0.0, 1.0, false, false, true))
	sim.advance(0.05)
	sim.set_control(ctl(0.0, 1.0))
	var s0 := sim.speed()
	var a0 := atan2(sim.velocity().y, sim.velocity().x)
	assert_almost_eq(s0, GUN_CAP, 0.01)
	assert_gt(sim.height(), 0.0)
	sim.set_control(ctl(1.0, 0.0))
	sim.advance(0.2)
	var turned := absf(atan2(sim.velocity().y, sim.velocity().x) - a0)
	assert_gt(turned, 0.2, "转过了一些")
	assert_lt(turned, PI / 2.0, "但 0.2s 内转不过 90°（限速 6 rad/s）")

func test_air_no_input_keeps_direction_and_only_gravity() -> void:
	var sim := MovementSimulator.new()
	run_full(sim)
	sim.set_control(ctl(0.0, 1.0, false, false, true))
	sim.advance(MovementSimulator.SUBSTEP)
	sim.set_control(ctl(0.0, 0.0))
	var v0 := sim.velocity()
	sim.set_facing(PI / 2.0) # 甩镜头
	sim.advance(0.3)
	assert_gt(sim.height(), 0.0, "仍滞空")
	assert_almost_eq(sim.velocity().x, v0.x, 0.01, "无输入惯性：水平分量冻结，不随镜头磁吸")
	assert_almost_eq(sim.velocity().y, v0.y, 0.01)
	sim.advance(MovementSimulator.SUBSTEP)
	assert_almost_eq(
		sim.vertical_speed(),
		MovementSimulator.JUMP_VELOCITY - MovementSimulator.GRAVITY * (0.3 + MovementSimulator.SUBSTEP),
		0.1
	)

func test_air_speed_never_exceeds_cap() -> void:
	assert_almost_eq(MovementSimulator.MAX_AIR_SPEED, 500.0, 1e-9, "空中水平速度上限 500 u/s")
	# 铲跳是可达的最快状态；空中持续转向不得越转越快
	var sim := MovementSimulator.new()
	sim.set_control(ctl(0.0, 1.0, true))
	sim.advance(3.0)
	sim.set_control(ctl(0.0, 1.0, true, true))
	sim.advance(MovementSimulator.SUBSTEP) # 触发滑铲
	sim.set_control(ctl(0.0, 1.0, true, true, true)) # 滑铲跳
	sim.advance(MovementSimulator.SUBSTEP) # 起跳当帧仍在地面高度
	sim.advance(0.02) # 再推进一点才真正升空
	assert_true(sim.height() > 0.0, "已升空")
	var peak := 0.0
	for i in range(30):
		sim.set_control(ctl(1.0, 0.0, true, false))
		sim.advance(0.01)
		peak = maxf(peak, sim.speed())
	assert_lte(peak, MovementSimulator.MAX_AIR_SPEED, "铲跳 + 转向不突破上限")

# ---- 滑铲 ----

func test_slide_initial_factor_and_decel_gate() -> void:
	var sim := MovementSimulator.new()
	sim.set_control(ctl(0.0, 1.0, true))
	sim.advance(3.0)
	assert_almost_eq(sim.speed(), SPRINT_CAP, 0.01)
	sim.set_control(ctl(0.0, 1.0, true, true))
	sim.advance(0.02)
	var peak := sim.speed()
	assert_gt(peak, SPRINT_CAP * 1.45, "滑铲初速 ×1.53")
	var after := sim.speed()
	sim.advance(0.06) # 蹲到底前（<0.15s）不减速
	assert_almost_eq(sim.speed(), after, 0.1, "没蹲到底不减速")
	sim.advance(0.3) # 蹲满后开始减速
	assert_lt(sim.speed(), after)
	assert_eq(sim.state(), "sliding")

func test_slide_turns_into_crouch_walk_below_92() -> void:
	var sim := MovementSimulator.new()
	sim.set_control(ctl(0.0, 1.0, true))
	sim.advance(3.0)
	sim.set_control(ctl(0.0, 1.0, true, true))
	sim.advance(2.5)
	assert_eq(sim.state(), "crouching")
	assert_lte(sim.speed(), CROUCH_CAP + 1.0)

func test_slide_ends_early_on_crouch_release() -> void:
	var sim := MovementSimulator.new()
	sim.set_control(ctl(0.0, 1.0, true))
	sim.advance(3.0)
	sim.set_control(ctl(0.0, 1.0, true, true))
	sim.advance(0.3)
	assert_eq(sim.state(), "sliding")
	sim.set_control(ctl(0.0, 1.0, true, false))
	sim.advance(0.05)
	assert_eq(sim.state(), "decelerating", "松开蹲提前结束滑铲")

func test_slide_requires_speed_threshold() -> void:
	var sim := MovementSimulator.new()
	sim.set_control(ctl(0.0, 1.0, false, true)) # 走路速度 < 200
	sim.advance(1.0)
	assert_lt(sim.speed(), MovementSimulator.SLIDE_MIN_SPEED)
	assert_ne(sim.state(), "sliding", "速度不达标不触发滑铲")

func test_diagonal_slide_keeps_its_heading() -> void:
	var sim := MovementSimulator.new()
	sim.set_control(ctl(-1.0, 1.0, true))
	sim.advance(3.0)
	var heading := atan2(sim.velocity().y, sim.velocity().x)
	sim.set_control(ctl(-1.0, 1.0, true, true))
	sim.advance(0.02)
	assert_eq(sim.state(), "sliding")
	sim.advance(0.2)
	assert_almost_eq(atan2(sim.velocity().y, sim.velocity().x), heading, 1e-3, "斜铲保持斜向")

func test_slide_key_change_is_rate_limited() -> void:
	var sim := MovementSimulator.new()
	sim.set_control(ctl(-1.0, 1.0, true))
	sim.advance(3.0)
	sim.set_control(ctl(-1.0, 1.0, true, true))
	sim.advance(0.02)
	var a0 := atan2(sim.velocity().y, sim.velocity().x)
	var s0 := sim.speed()
	sim.set_control(ctl(-1.0, 0.0, true, true))
	sim.advance(0.1)
	var turned := absf(atan2(sim.velocity().y, sim.velocity().x) - a0)
	assert_gt(turned, 0.4, "换键限速过渡，不瞬时切")
	assert_lt(turned, 0.8)
	assert_almost_eq(sim.speed(), s0, 0.5, "未蹲满不减速")

# ---- 滑铲跳跃 ----

func test_slide_jump_ratio_and_air_friction() -> void:
	var sim := MovementSimulator.new()
	sim.set_control(ctl(0.0, 1.0, true))
	sim.advance(3.0)
	sim.set_control(ctl(0.0, 1.0, true, true))
	sim.advance(0.2)
	var s := sim.speed()
	assert_gt(s, MovementSimulator.SLIDE_MIN_SPEED)
	sim.set_control(ctl(0.0, 1.0, true, true, true))
	sim.advance(MovementSimulator.SUBSTEP)
	var boosted := sim.speed()
	assert_gt(boosted, s, "滑铲跳有水平加成")
	assert_almost_eq(boosted / s, MovementSimulator.slide_jump_ratio(s), 0.01, "倍率 = 2.454 − 速度/299 × 0.919")
	assert_almost_eq(sim.vertical_speed(), MovementSimulator.JUMP_VELOCITY, 1e-3, "垂直分量仍 286")
	sim.set_control(ctl(0.0, 1.0, true, true, false))
	sim.advance(0.2)
	assert_lt(sim.speed(), boosted, "滑铲跳独有的空中摩擦")

func test_normal_jump_has_no_air_friction() -> void:
	var sim := MovementSimulator.new()
	run_full(sim)
	sim.set_control(ctl(0.0, 1.0, false, false, true))
	sim.advance(MovementSimulator.SUBSTEP)
	sim.set_control(ctl(0.0, 1.0))
	var v0 := sim.speed()
	sim.advance(0.2)
	assert_almost_eq(sim.speed(), v0, 0.01, "普通跳跃无空气摩擦")

# ---- 场地边界与确定性 ----

func test_radial_clamp_keeps_speed() -> void:
	var sim := MovementSimulator.new(250.0, Vector2(249.0, 0.0))
	sim.set_control(ctl(1.0, 0.0))
	sim.advance(0.2)
	assert_almost_eq(sim.position().x, 250.0, 1e-6, "位置钳制在半径内")
	assert_almost_eq(sim.velocity().x, GUN_CAP, 0.01, "速度保留")

func test_default_radius_is_arena_radius() -> void:
	assert_almost_eq(MovementSimulator.ARENA_RADIUS, 1000.0, 1e-9, "圆形场地半径 1000（ADR-0004）")
	var sim := MovementSimulator.new()
	sim.set_control(ctl(0.0, 1.0))
	sim.advance(10.0)
	assert_lte(sim.position().length(), MovementSimulator.ARENA_RADIUS + 1e-6)

func test_fixed_substep_is_deterministic() -> void:
	var a := _run_scenario(1.0 / 120.0)
	var b := _run_scenario(1.0 / 120.0)
	assert_almost_eq(a.position().x, b.position().x, 1e-6, "同一 dt 逐位可复现")
	assert_almost_eq(a.position().y, b.position().y, 1e-6)
	var coarse := _run_scenario(1.0 / 120.0)
	var fine := _run_scenario(1.0 / 240.0)
	assert_lt(absf(coarse.position().x - fine.position().x), 3.0, "跨 dt 差异仅来自输入采样粒度")
	assert_lt(absf(coarse.position().y - fine.position().y), 3.0)

func _run_scenario(dt: float) -> MovementSimulator:
	var sim := MovementSimulator.new()
	var t := 0.0
	while t < 1.1:
		if t <= 1e-9:
			sim.set_control(ctl(0.0, 1.0))
		elif t >= 0.25 and t < 0.27:
			sim.set_control(ctl(1.0, 1.0))
		elif t >= 0.5 and t < 0.52:
			sim.set_control(ctl(0.0, 1.0))
		sim.advance(dt)
		t += dt
	return sim

func test_state_reporting() -> void:
	var sim := MovementSimulator.new()
	sim.set_control(ctl(0.0, 1.0))
	sim.advance(0.01)
	assert_eq(sim.state(), "accelerating")
	sim.advance(1.0)
	assert_eq(sim.state(), "constant")
	sim.set_control(ctl(0.0, 0.0))
	sim.advance(0.01)
	assert_eq(sim.state(), "decelerating")
	sim.advance(0.2)
	assert_eq(sim.state(), "idle")

# ---- 注入滑铲（bot 用，ADR-0016）----

func test_injected_slide_starts_full_speed_without_prerequisites() -> void:
	# 不疾跑、不蹲、无前摇：注入当帧就是满速滑行
	var sim := MovementSimulator.new()
	assert_true(sim.start_slide(Vector2(0.0, -1.0), 399.0))
	assert_eq(sim.state(), "sliding")
	assert_almost_eq(sim.speed(), 399.0, 0.01)
	assert_almost_eq(sim.velocity().y, -399.0, 0.01)

func test_injected_slide_sustains_without_crouch_key() -> void:
	# bot 不按蹲键（_slide_auto）：不会被「松开蹲」提前掐断
	var sim := MovementSimulator.new()
	sim.start_slide(Vector2(0.0, -1.0), 399.0)
	sim.advance(0.4) # 已越过蹲到底的 0.15s
	assert_eq(sim.state(), "sliding", "没有蹲键输入也维持滑行")
	assert_almost_eq(sim.crouch_progress(), 1.0, 1e-6, "蹲伏进度照常压满（命中体压低共用）")

func test_injected_slide_decelerates_like_normal_slide() -> void:
	var sim := MovementSimulator.new()
	sim.start_slide(Vector2(0.0, -1.0), 399.0)
	sim.advance(0.2) # 蹲满（0.15s）后再滑一小段
	var s := sim.speed()
	sim.advance(0.1)
	assert_almost_eq(
		sim.speed(), s - MovementSimulator.SLIDE_DECEL * MovementSimulator.SPEED_MULT_GUN * 0.1, 0.5,
		"蹲满后按 210 × 速度修正器 减速"
	)

func test_end_slide_stops_injected_slide_only() -> void:
	var sim := MovementSimulator.new()
	sim.start_slide(Vector2(0.0, -1.0), 399.0)
	sim.end_slide()
	sim.advance(0.05)
	assert_ne(sim.state(), "sliding", "手动站起立即退出滑行")
	# 玩家的普通滑铲（非注入）不受 end_slide 影响
	var sim2 := MovementSimulator.new()
	sim2.set_control(ctl(0.0, 1.0, true))
	sim2.advance(3.0)
	sim2.set_control(ctl(0.0, 1.0, true, true))
	sim2.advance(0.2)
	assert_eq(sim2.state(), "sliding")
	sim2.end_slide()
	sim2.advance(0.05)
	assert_eq(sim2.state(), "sliding", "玩家滑铲不吃 end_slide")

func test_start_slide_rejects_airborne_double_and_zero() -> void:
	var sim := MovementSimulator.new()
	sim.start_slide(Vector2(0.0, -1.0), 399.0)
	assert_false(sim.start_slide(Vector2(1.0, 0.0), 399.0), "滑行中不可再次注入")
	var sim2 := MovementSimulator.new()
	sim2.set_control(ctl(0.0, 1.0, false, false, true))
	sim2.advance(0.05)
	assert_true(sim2.height() > 0.0)
	assert_false(sim2.start_slide(Vector2(0.0, -1.0), 399.0), "空中不可注入")
	assert_false(sim.start_slide(Vector2.ZERO, 399.0), "零向量拒绝")

func test_injected_slide_jump_inherits_direction() -> void:
	var sim := MovementSimulator.new()
	sim.start_slide(Vector2(-1.0, 0.0), 399.0)
	sim.advance(0.2)
	var heading := atan2(sim.velocity().y, sim.velocity().x)
	sim.set_control(ctl(0.0, 0.0, false, false, true)) # 铲跳：跳、不松蹲也不需要
	sim.advance(MovementSimulator.SUBSTEP)
	sim.set_control(ctl(0.0, 0.0))
	sim.advance(0.02)
	assert_eq(sim.state(), "airborne", "铲跳升空")
	assert_almost_eq(atan2(sim.velocity().y, sim.velocity().x), heading, 1e-3, "继承滑铲方向")
	assert_almost_eq(sim.vertical_speed(), MovementSimulator.JUMP_VELOCITY - MovementSimulator.GRAVITY * 0.02, 0.5, "垂直仍 286 起步")