## 演示模式追踪数学（ADR-0033 / ADR-0034）的纯逻辑测试：限速转向、无过冲收敛、到位阈值、
## 三态切换（看得见 / 看不见 / 死亡空窗）、宽限期、滑行指数衰减与方向、重新可见立即恢复。

extends GutTest

const DT := 1.0 / 60.0
## 目标横移速度（u/s）：造出持续跟枪的角速度，滑行才有「惯性」可继承。
const STRAFE := 60.0

var _aim: DemoAim
var _target := Vector3.ZERO
var _pose := Vector2.ZERO

func before_each() -> void:
	_aim = DemoAim.new()
	_target = Vector3(-140.0, 0.0, -140.0)
	_pose = Vector2.ZERO

## 当前朝向与「眼位 → 目标」的夹角（rad）——断言用口径，与实现解耦（只认方向，不认 yaw 的分支）。
func _err(eye: Vector3, target: Vector3, yaw: float, pitch: float) -> float:
	var f := DemoAim.forward(yaw, pitch).normalized()
	var d := (target - eye).normalized()
	return acos(clampf(f.dot(d), -1.0, 1.0))

## 推进若干帧；`strafe` 为真时目标每帧继续横移（bot 边跑边被跟）。
func _advance(frames: int, visible := true, has_target := true, strafe := true) -> void:
	for i in frames:
		_pose = _aim.update(Vector3.ZERO, _target, _pose.x, _pose.y, DT, has_target, visible)
		if strafe:
			_target.x += STRAFE * DT

## 稳定跟枪若干帧后，返回**最后一帧**的 yaw 角速度（rad/s）——滑行的初速来源。
func _settle(frames := 90) -> float:
	_advance(frames)
	var prev := _pose.x
	_advance(1)
	return (_pose.x - prev) / DT

func test_hold_freezes_pose_when_target_gone() -> void:
	# bot 死亡空窗：冻结保持（不滑行——ADR-0034 明确与「看不见」区别对待）
	_pose = Vector2(1.2, -0.3)
	_advance(1, true, false, false)
	assert_almost_eq(_pose.x, 1.2, 1e-6) # Vector2 是 float32：容差按单精度给
	assert_almost_eq(_pose.y, -0.3, 1e-6)
	assert_eq(_aim.mode(), DemoAim.Mode.HOLD, "死亡空窗 = HOLD")

func test_max_turn_rate_limits_first_frame() -> void:
	# 目标在正后方（夹角 π）：第一步必须被限速钳住，且确实在转
	_target = Vector3(0.0, 0.0, 50.0)
	_advance(1, true, true, false)
	var turned := absf(wrapf(_pose.x - 0.0, -PI, PI))
	assert_lte(turned, DemoAim.MAX_TURN_RATE * DT + 1e-6, "单帧转角不超限速")
	assert_gt(turned, 0.0, "确实在转")

func test_converges_monotonically_without_overshoot() -> void:
	_target = Vector3(0.0, 6.0, 50.0) # 正后方且略高：水平与俯仰都要转
	var prev := _err(Vector3.ZERO, _target, _pose.x, _pose.y)
	for i in 200:
		_advance(1, true, true, false)
		var now := _err(Vector3.ZERO, _target, _pose.x, _pose.y)
		assert_lte(now, prev + 1e-9, "误差单调不增（不过冲）")
		prev = now
	assert_almost_eq(prev, 0.0, 1e-6, "最终精确贴齐（死区吸附）")
	assert_true(DemoAim.on_target(Vector3.ZERO, _target, _pose.x, _pose.y), "收敛后判定为可开火")

func test_already_aligned_leaves_pose_untouched() -> void:
	_target = Vector3(0.0, 0.0, -50.0) # 正前方（yaw = 0 朝 −Z）
	_advance(1, true, true, false)
	assert_almost_eq(_pose.x, 0.0, 1e-6, "已在目标上：不动")
	assert_almost_eq(_pose.y, 0.0, 1e-6)

func test_on_target_threshold() -> void:
	var eye := Vector3.ZERO
	var tgt := Vector3(0.0, 0.0, -50.0) # 正前方（yaw = 0 朝 −Z）
	assert_true(DemoAim.on_target(eye, tgt, 0.0, 0.0), "正对目标")
	assert_true(DemoAim.on_target(eye, tgt, deg_to_rad(1.5), 0.0), "1.5° 内算到位")
	assert_false(DemoAim.on_target(eye, tgt, deg_to_rad(3.0), 0.0), "3° 外不算到位")

func test_on_target_false_when_invisible_or_dead() -> void:
	# 开火门控 = 可见 ∧ 到位（ADR-0034）：只要看不见就一颗子弹都不出膛
	var eye := Vector3.ZERO
	var tgt := Vector3(0.0, 0.0, -50.0)
	assert_false(DemoAim.on_target(eye, tgt, 0.0, 0.0, true, false), "看不见恒不可开火")
	assert_false(DemoAim.on_target(eye, tgt, 0.0, 0.0, false, true), "无目标恒不可开火")

func test_single_frame_occlusion_does_not_coast() -> void:
	# 宽限的全部价值：别对一帧遮挡抽手（贴掩体边缘的逐帧翻转不该引起滑行）
	_settle(60)
	_advance(1, false)
	assert_eq(_aim.mode(), DemoAim.Mode.TRACK, "一帧遮挡仍在宽限期内，继续跟枪")

func test_sustained_occlusion_starts_coasting() -> void:
	_settle(60)
	_advance(20, false)
	assert_eq(_aim.mode(), DemoAim.Mode.COAST, "持续看不见才进入滑行")

func test_coast_decays_monotonically_keeps_direction_and_sweeps_v0_over_decay() -> void:
	_settle(90)
	# 宽限 0.1s = 6 帧：走完这 6 帧仍停在跟枪态，第 7 帧才是滑行首帧
	_advance(6, false)
	assert_eq(_aim.mode(), DemoAim.Mode.TRACK, "宽限内仍跟枪（第 7 帧才滑行）")
	var deltas: Array[float] = []
	var total := 0.0
	for i in 40:
		var before := _pose.x
		_advance(1, false)
		assert_eq(_aim.mode(), DemoAim.Mode.COAST, "宽限后持续不可见应一直处于滑行态")
		var d := _pose.x - before
		deltas.append(d)
		total += d
	# 由滑行首帧位移反推初速：delta_0 = v0·(1−e^{−k·dt})/k（证明滑行确实继承了跟枪末帧的角速度）
	var v0 := deltas[0] * DemoAim.COAST_DECAY / (1.0 - exp(-DemoAim.COAST_DECAY * DT))
	assert_gt(absf(v0), 0.05, "确有滑行初速（不是一帧静止）")
	var sign_ref := signf(v0)
	for i in deltas.size():
		if deltas[i] == 0.0:
			continue
		assert_eq(signf(deltas[i]), sign_ref, "滑行方向不变（不回头）")
		if i > 0:
			assert_lt(absf(deltas[i]), absf(deltas[i - 1]) + 1e-9, "滑行角速度单调递减")
	# 滑出总角度 ≈ v0 / 衰减率（40 帧 ≈ 0.67s 后残量 e^{−6.7} ≈ 0.12%，可忽略）
	var swept := v0 / DemoAim.COAST_DECAY
	assert_almost_eq(total, swept, absf(swept) * 0.15, "滑出角度 ≈ v0 / 衰减率")

func test_death_during_coast_freezes_immediately() -> void:
	# 死亡优先于看不见：正滑行时 bot 死 → 立刻切冻结（ADR-0034 不加惯性）
	_settle(60)
	_advance(20, false) # 进入滑行
	assert_eq(_aim.mode(), DemoAim.Mode.COAST)
	var frozen := _pose
	_advance(5, false, false) # 无目标 + 不可见
	assert_eq(_aim.mode(), DemoAim.Mode.HOLD, "滑行中途死亡 → 立刻冻结")
	assert_almost_eq(_pose.x, frozen.x, 1e-6, "冻结保持：不再滑行")
	assert_almost_eq(_pose.y, frozen.y, 1e-6)

func test_respawn_restarts_grace_from_zero() -> void:
	# 重生后宽限从零重新计（HOLD 清零 _invisible_time）：再次被挡住时先跟枪不滑行
	_settle(60)
	_advance(20, false)
	_advance(5, false, false) # 死亡 → HOLD
	assert_eq(_aim.mode(), DemoAim.Mode.HOLD)
	_advance(1, false, true, false) # 重生但不可见：应为 TRACK（宽限从零起）
	assert_eq(_aim.mode(), DemoAim.Mode.TRACK, "重生后宽限从零重新计")

func test_reacquire_resumes_tracking_immediately() -> void:
	_settle(60)
	_advance(30, false) # 进入滑行并滑一段，准星已甩离目标
	assert_eq(_aim.mode(), DemoAim.Mode.COAST)
	var err_before := _err(Vector3.ZERO, _target, _pose.x, _pose.y)
	_advance(1, true, true, false) # 重新可见（目标定住，只看它是否立即回头拉枪）
	assert_eq(_aim.mode(), DemoAim.Mode.TRACK, "重新可见立刻恢复追踪")
	var err_after := _err(Vector3.ZERO, _target, _pose.x, _pose.y)
	assert_lt(err_after, err_before, "误差在缩小：真的在往目标上拉")
