## 角色姿势混合的行为测试（票 04，CONTEXT.md「侧偏」）。
##
## 断言的是「姿势 / 侧偏 / 步频 / 过渡时长」这组对外读数，不碰骨骼与动画播放器。

extends GutTest

const EPS := 1e-4

## 走一帧并返回读数。`lateral` 正 = 向右手侧、`forward` 正 = 朝自身前方。
func _step(
	pose: PoseBlend, dt: float, speed: float, lateral: float, forward: float
) -> PoseBlend.Frame:
	return pose.update(dt, speed, lateral, forward)

## 连续推进 `total` 秒（每帧 1/60 秒），返回最后一帧读数。
func _settle(
	pose: PoseBlend, total: float, speed: float, lateral: float, forward: float
) -> PoseBlend.Frame:
	var frame := _step(pose, 0.0, speed, lateral, forward)
	var left := total
	while left > EPS:
		var dt := minf(1.0 / 60.0, left)
		frame = _step(pose, dt, speed, lateral, forward)
		left -= dt
	return frame

# ---- 静止判据 ----

func test_still_is_idle_and_no_blend() -> void:
	var frame := _step(PoseBlend.new(), 1.0 / 60.0, 0.0, 0.0, 0.0)
	assert_eq(frame.motion, PoseBlend.Motion.IDLE)
	assert_almost_eq(frame.lean, 0.0, EPS, "静止不侧偏")
	assert_almost_eq(frame.gait, 0.0, EPS, "静止步频为 0")
	assert_almost_eq(frame.blend, 0.0, EPS, "首帧无切换就无过渡")

func test_speed_below_epsilon_counts_as_still() -> void:
	var pose := PoseBlend.new()
	assert_eq(_step(pose, 0.1, 0.4, 0.0, 0.0).motion, PoseBlend.Motion.IDLE, "阈值内视为静止")

# ---- 分类 ----

func test_lateral_sign_picks_side_and_lean() -> void:
	var pose := PoseBlend.new()
	var left := _settle(pose, 1.0, 100.0, -100.0, 0.0)
	assert_eq(left.motion, PoseBlend.Motion.LEFT, "向左手侧 = LEFT")
	assert_almost_eq(left.lean, 1.0, EPS, "左走侧偏 +1")

	pose.reset()
	var right := _settle(pose, 1.0, 100.0, 100.0, 0.0)
	assert_eq(right.motion, PoseBlend.Motion.RIGHT, "向右手侧 = RIGHT")
	assert_almost_eq(right.lean, -1.0, EPS, "右走侧偏 −1")

func test_forward_dominant_is_straight_and_upright() -> void:
	var frame := _settle(PoseBlend.new(), 1.0, 100.0, 10.0, 100.0)
	assert_eq(frame.motion, PoseBlend.Motion.STRAIGHT)
	assert_almost_eq(frame.lean, 0.0, EPS, "直立不侧偏")

func test_strafe_dominance_threshold() -> void:
	var pose := PoseBlend.new()
	# 默认阈值 0.5：|lat| 必须**严格大于** 0.5 × |fwd| 才算侧走。
	assert_eq(_step(pose, 0.1, 100.0, 50.0, 100.0).motion, PoseBlend.Motion.STRAIGHT, "恰在阈值上算直立")
	assert_eq(_step(pose, 0.1, 100.0, 51.0, 100.0).motion, PoseBlend.Motion.RIGHT, "超过阈值算侧走")

func test_lean_of_static_table() -> void:
	assert_almost_eq(PoseBlend.lean_of(PoseBlend.Motion.LEFT), 1.0, EPS)
	assert_almost_eq(PoseBlend.lean_of(PoseBlend.Motion.RIGHT), -1.0, EPS)
	assert_almost_eq(PoseBlend.lean_of(PoseBlend.Motion.IDLE), 0.0, EPS)
	assert_almost_eq(PoseBlend.lean_of(PoseBlend.Motion.STRAIGHT), 0.0, EPS)

# ---- 步频 ----

func test_gait_normalizes_by_full_speed() -> void:
	var pose := PoseBlend.new()
	var target := PoseBlend.TARGET_SPEED
	assert_almost_eq(_step(pose, 0.1, target, 100.0, 0.0).gait, 1.0, EPS, "满速 = 1")
	assert_almost_eq(_step(pose, 0.1, target * 0.5, 100.0, 0.0).gait, 0.5, EPS, "半速 = 0.5")

func test_gait_clamps_above_full_speed() -> void:
	assert_almost_eq(
		_step(PoseBlend.new(), 0.1, PoseBlend.TARGET_SPEED * 2.0, 100.0, 0.0).gait, 1.0, EPS
	)

# ---- 过渡时长 ----

func test_idle_to_walk_takes_250ms() -> void:
	var pose := PoseBlend.new()
	var first := _step(pose, 0.0, 100.0, -100.0, 0.0) # dt=0：只观察切换，不推进混合
	assert_almost_eq(first.blend, 0.25, EPS, "直立 → 侧向 250ms")
	var half := _settle(pose, 0.125, 100.0, -100.0, 0.0)
	assert_almost_eq(half.lean, 0.5, 1e-3, "半程侧偏到一半")
	var done := _settle(pose, 0.13, 100.0, -100.0, 0.0)
	assert_almost_eq(done.lean, 1.0, 1e-3, "到期侧偏到位")

func test_walk_to_idle_takes_200ms() -> void:
	var pose := PoseBlend.new()
	_settle(pose, 1.0, 100.0, -100.0, 0.0)
	var first := _step(pose, 1.0 / 60.0, 0.0, 0.0, 0.0)
	assert_eq(first.motion, PoseBlend.Motion.IDLE)
	assert_almost_eq(first.blend, 0.20, EPS, "侧向 → 直立 200ms")
	var done := _settle(pose, 0.25, 0.0, 0.0, 0.0)
	assert_almost_eq(done.lean, 0.0, 1e-3, "到期回到直立")

func test_left_right_switch_takes_250ms_and_crosses_zero() -> void:
	var pose := PoseBlend.new()
	_settle(pose, 1.0, 100.0, -100.0, 0.0) # 先到位在 LEFT
	var first := _step(pose, 0.0, 100.0, 100.0, 0.0) # dt=0：只观察切换，不推进混合
	assert_eq(first.motion, PoseBlend.Motion.RIGHT)
	assert_almost_eq(first.blend, 0.25, EPS, "左 ↔ 右 250ms")
	var mid := _settle(pose, 0.125, 100.0, 100.0, 0.0)
	assert_almost_eq(mid.lean, 0.0, 1e-3, "中途穿过直立")
	var done := _settle(pose, 0.13, 100.0, 100.0, 0.0)
	assert_almost_eq(done.lean, -1.0, 1e-3, "到期到反向")

func test_upright_to_upright_does_not_blend_lean() -> void:
	var pose := PoseBlend.new()
	_settle(pose, 1.0, 100.0, 0.0, 100.0) # STRAIGHT
	var frame := _step(pose, 1.0 / 60.0, 0.0, 0.0, 0.0)
	assert_eq(frame.motion, PoseBlend.Motion.IDLE)
	assert_almost_eq(frame.lean, 0.0, EPS, "直立两侧偏都是 0，没有可过渡的量")
	assert_almost_eq(frame.blend, 0.20, EPS, "但动作仍要交叉淡入，时长照给")

func test_blend_is_reported_only_on_the_switching_frame() -> void:
	var pose := PoseBlend.new()
	_step(pose, 1.0 / 60.0, 100.0, -100.0, 0.0)
	assert_almost_eq(_step(pose, 1.0 / 60.0, 100.0, -100.0, 0.0).blend, 0.0, EPS)

func test_interrupted_transition_restarts_from_current_lean() -> void:
	var pose := PoseBlend.new()
	_step(pose, 0.125, 100.0, -100.0, 0.0) # 走到一半（lean ≈ 0.5）
	var mid := _step(pose, 1e-6, 100.0, -100.0, 0.0)
	assert_almost_eq(mid.lean, 0.5, 1e-3)
	# 中途改判为 RIGHT：从当前 0.5 起步、接全新 250ms，不排队、不跳变。
	var cut := _step(pose, 1e-6, 100.0, 100.0, 0.0)
	assert_almost_eq(cut.blend, 0.25, EPS)
	assert_almost_eq(cut.lean, 0.5, 1e-3, "打断不跳变，从当前值续上")
	var done := _settle(pose, 0.3, 100.0, 100.0, 0.0)
	assert_almost_eq(done.lean, -1.0, 1e-3)

# ---- reset ----

func test_reset_returns_to_upright_without_transition() -> void:
	var pose := PoseBlend.new()
	_settle(pose, 1.0, 100.0, -100.0, 0.0)
	pose.reset()
	var frame := _step(pose, 1.0 / 60.0, 0.0, 0.0, 0.0)
	assert_eq(frame.motion, PoseBlend.Motion.IDLE)
	assert_almost_eq(frame.lean, 0.0, EPS)
	assert_almost_eq(frame.blend, 0.0, EPS, "reset 后首帧不再补一次过渡")