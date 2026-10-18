## 演示模式追踪数学（ADR-0033）的纯逻辑测试：限速转向、无过冲收敛、到位阈值、无目标冻结。

extends GutTest

const DT := 1.0 / 60.0

## 当前朝向与「眼位 → 目标」的夹角（rad）——断言用口径，与实现解耦（只认方向，不认 yaw 的分支）。
func _err(eye: Vector3, target: Vector3, yaw: float, pitch: float) -> float:
	var f := DemoAim.forward(yaw, pitch).normalized()
	var d := (target - eye).normalized()
	return acos(clampf(f.dot(d), -1.0, 1.0))

func test_step_without_target_holds_pose() -> void:
	# bot 死亡空窗期：相机冻结保持（原样返回，不做任何转向）
	var out := DemoAim.step(Vector3.ZERO, Vector3(10.0, 0.0, -10.0), 1.2, -0.3, DT, false)
	assert_almost_eq(out.x, 1.2, 1e-6) # Vector2 是 float32：容差按单精度给
	assert_almost_eq(out.y, -0.3, 1e-6)

func test_step_respects_max_turn_rate() -> void:
	# 目标在正后方（初始夹角 π）：第一步必须被限速钳住，且确实在转
	var eye := Vector3.ZERO
	var target := Vector3(0.0, 0.0, 50.0)
	var out := DemoAim.step(eye, target, 0.0, 0.0, DT)
	var turned := absf(wrapf(out.x - 0.0, -PI, PI))
	assert_lte(turned, DemoAim.MAX_TURN_RATE * DT + 1e-6, "单帧转角不超限速")
	assert_gt(turned, 0.0, "确实在转")

func test_step_converges_monotonically_without_overshoot() -> void:
	var eye := Vector3.ZERO
	var target := Vector3(0.0, 6.0, 50.0) # 正后方且略高：水平与俯仰都要转
	var pose := Vector2(0.0, 0.0)
	var prev := _err(eye, target, pose.x, pose.y)
	for i in 200:
		pose = DemoAim.step(eye, target, pose.x, pose.y, DT)
		var now := _err(eye, target, pose.x, pose.y)
		assert_lte(now, prev + 1e-9, "误差单调不增（不过冲）")
		prev = now
	assert_almost_eq(prev, 0.0, 1e-6, "最终精确贴齐（死区吸附）")
	assert_true(DemoAim.on_target(eye, target, pose.x, pose.y), "收敛后判定为到位")

func test_step_leaves_pose_untouched_when_already_aligned() -> void:
	var eye := Vector3.ZERO
	var target := Vector3(0.0, 0.0, -50.0)
	var out := DemoAim.step(eye, target, 0.0, 0.0, DT)
	assert_almost_eq(out.x, 0.0, 1e-6, "已在目标上：不动")
	assert_almost_eq(out.y, 0.0, 1e-6)

func test_on_target_threshold() -> void:
	var eye := Vector3.ZERO
	var target := Vector3(0.0, 0.0, -50.0) # 正前方（yaw = 0 朝 −Z）
	assert_true(DemoAim.on_target(eye, target, 0.0, 0.0), "正对目标")
	assert_true(DemoAim.on_target(eye, target, deg_to_rad(1.5), 0.0), "1.5° 内算到位")
	assert_false(DemoAim.on_target(eye, target, deg_to_rad(3.0), 0.0), "3° 外不算到位")
	assert_false(DemoAim.on_target(eye, target, 0.0, 0.0, false), "无目标恒为假")
