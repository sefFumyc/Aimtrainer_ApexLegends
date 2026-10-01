## 躲避控制的行为测试（票 02 验收条件 2 / 9；ADR-0013 的「纯逻辑缝」）。
##
## 只断言**外部行为**：给定随机源（固定种子）与经过时间，断言变向序列与间隔、
## 「最短躲避时间」的丢弃语义、撞墙反向的计时语义、前后分量的重掷点。
## 不碰私有方法，也不依赖节点树。

extends GutTest

## 测试用「冻结表」：变向间隔长到测试期间绝不会自然变向，把行为留给被测的那一个事件。
const FROZEN := [100.0, 100.0, 100.0]
## 固定间隔表（0.4s）：自然变向发生在可预测的时刻。
const FIXED := [0.4, 0.4, 0.4]

func rng(seed_value: int) -> RandomNumberGenerator:
	var out := RandomNumberGenerator.new()
	out.seed = seed_value
	return out

func config() -> AvoidanceController.Config:
	return AvoidanceController.Config.new()

## 变向间隔长到不会自然触发的配置（隔离「躲避 / 撞墙」这些被测事件）。
func frozen_config() -> AvoidanceController.Config:
	var cfg := config()
	cfg.switch_min = 100.0
	cfg.switch_max = 100.0
	return cfg

func frozen_controller(cfg: AvoidanceController.Config, seed_value := 3) -> AvoidanceController:
	var ctrl := AvoidanceController.new(rng(seed_value), cfg, FROZEN, FROZEN)
	ctrl.spawn()
	return ctrl

## 跑 `seconds` 秒，返回每次自然变向**当刻重抽到的间隔**及各次变向生效的模式。
##
## 这是「间隔落在模式区间内」的可断言口径：模式切换会重排下一次变向（参考实现的既有语义），
## 因此挂钟间隔可以跨模式、不等于任何单档区间；重抽值才是模式区间的直接产物。
func rolled_intervals(weights: Array, seconds: float, seed_value := 11) -> Dictionary:
	var cfg := config()
	cfg.weights = weights
	var ctrl := AvoidanceController.new(rng(seed_value), cfg)
	ctrl.spawn()
	var last_dir := ctrl.dir
	var now := 0.0
	var step := 0.005
	var intervals: Array = []
	var modes: Array = []
	while now < seconds:
		ctrl.update(step)
		now += step
		if ctrl.dir != last_dir:
			intervals.append(ctrl.flip_timer)
			modes.append(ctrl.mode)
			last_dir = ctrl.dir
	return {"intervals": intervals, "modes": modes}

## 断言一串「变向当刻重抽的间隔」都落在各自模式的区间内。
func assert_inside_mode_ranges(rolled: Dictionary, label: String) -> void:
	var intervals: Array = rolled["intervals"]
	var modes: Array = rolled["modes"]
	assert_eq(intervals.size(), modes.size())
	for i in intervals.size():
		var m: int = modes[i]
		assert_between(
			intervals[i],
			float(AvoidanceController.STRAFE_MIN[m]) - 0.01,
			float(AvoidanceController.STRAFE_MAX[m]) + 0.01,
			"%s：第 %d 次变向重抽的间隔落在 %d 档区间内" % [label, i, m]
		)

# ---- 变向节奏与模式权重 ----

func test_flip_intervals_stay_inside_mode_ranges() -> void:
	var rolled := rolled_intervals([0.3, 0.4, 0.3], 30.0)
	var intervals: Array = rolled["intervals"]
	assert_gt(intervals.size(), 25, "30 秒内变向足够密（没有静止空窗）")
	assert_inside_mode_ranges(rolled, "默认权重")

func test_flip_intervals_are_irregular() -> void:
	var intervals: Array = rolled_intervals([0.3, 0.4, 0.3], 30.0)["intervals"]
	var distinct := {}
	for iv in intervals:
		distinct[snappedf(iv, 0.01)] = true
	assert_gt(distinct.size(), 8, "每次自然变向从当前模式区间重抽，不是固定频率")

func test_extreme_weights_change_pace() -> void:
	var fast := rolled_intervals([0.0, 0.0, 1.0], 30.0)
	var long := rolled_intervals([1.0, 0.0, 0.0], 30.0)
	var fast_intervals: Array = fast["intervals"]
	var long_intervals: Array = long["intervals"]
	assert_gt(fast_intervals.size(), 0)
	assert_gt(long_intervals.size(), 0)
	for m in fast["modes"]:
		assert_eq(m, AvoidanceController.Mode.FAST, "全快档只抽到快档")
	for m in long["modes"]:
		assert_eq(m, AvoidanceController.Mode.LONG, "全长档只抽到长档")
	assert_inside_mode_ranges(fast, "全快档")
	assert_inside_mode_ranges(long, "全长档")
	assert_gt(fast_intervals.size(), long_intervals.size() * 2, "全快档的变向节奏明显更密")

func test_all_zero_weights_fall_back_to_equal_weights() -> void:
	var rolled := rolled_intervals([0.0, 0.0, 0.0], 30.0)
	var intervals: Array = rolled["intervals"]
	var seen := {}
	for m in rolled["modes"]:
		seen[m] = true
	assert_gt(intervals.size(), 20, "权重全 0 不会让 bot 卡死在单侧横移")
	assert_eq(seen.size(), 3, "回落等权后三档都能抽到，不会卡死在单档")
	assert_inside_mode_ranges(rolled, "权重全 0")

# ---- 最短躲避时间 ----

func test_dodge_within_min_interval_is_dropped() -> void:
	var cfg := frozen_config()
	cfg.dodge_min = 0.15
	var ctrl := frozen_controller(cfg)
	var dir := ctrl.dir
	ctrl.update(0.05)
	assert_false(ctrl.dodge(1.0), "门槛内掷中的躲避被丢弃")
	assert_eq(ctrl.dir, dir, "被丢弃时不翻向")
	ctrl.update(0.2)
	assert_true(ctrl.dodge(1.0), "越过门槛后躲避生效")
	assert_eq(ctrl.dir, -dir, "生效的躲避翻向")

func test_dodge_min_zero_disables_the_gate() -> void:
	var cfg := frozen_config()
	cfg.dodge_min = 0.0
	var ctrl := frozen_controller(cfg)
	var dir := ctrl.dir
	ctrl.update(0.01)
	assert_true(ctrl.dodge(1.0), "0 = 关闭门槛")
	assert_eq(ctrl.dir, -dir)

func test_dropped_dodge_consumes_no_random_numbers() -> void:
	# 两台同种子控制器走同一条时间线，只有 A 多掷了一次「门槛内被丢弃的躲避」。
	# 若那次丢弃消耗了随机数，两台之后的模式抽取与变向排期就会分道扬镳。
	var a := AvoidanceController.new(rng(99), config())
	var b := AvoidanceController.new(rng(99), config())
	a.spawn()
	b.spawn()
	a.update(0.05)
	b.update(0.05)
	assert_false(a.dodge(1.0), "门槛内丢弃")
	var diverged := -1
	for i in 1000:
		a.update(0.01)
		b.update(0.01)
		if a.dir != b.dir or absf(a.flip_timer - b.flip_timer) > 1e-9 or a.mode != b.mode:
			diverged = i
			break
	assert_eq(diverged, -1, "1000 步内两台始终一致——丢弃的躲避没有消耗随机数")

func test_long_run_dodge_gate_keeps_flip_gaps_above_min() -> void:
	# 240Hz 推进 120 秒，其间以 10 次/秒的频率掷躲避（概率 0.5）：没有门槛时会出现
	# 毫秒级接连翻向；有门槛后任意两次变向的间隔都被抬到门槛以上。
	var ctrl := AvoidanceController.new(rng(17), config())
	ctrl.spawn()
	var dt := 1.0 / 240.0
	var times: Array = []
	var last_dir := ctrl.dir
	var t := 0.0
	var next_dodge := 0.1
	for i in 240 * 120:
		ctrl.update(dt)
		t += dt
		if t >= next_dodge:
			next_dodge += 0.1
			ctrl.dodge(0.5)
		if ctrl.dir != last_dir:
			times.append(t)
			last_dir = ctrl.dir
	assert_gt(times.size(), 50, "长跑里变向足够多")
	var smallest := 1e9
	for i in range(1, times.size()):
		smallest = minf(smallest, times[i] - times[i - 1])
	assert_true(smallest >= 0.15 - 1e-9, "最小变向间隔被门槛抬到 0.15s 以上（实测 %.4f）" % smallest)

func test_natural_flip_resets_dodge_min_clock() -> void:
	var cfg := frozen_config()
	var ctrl := AvoidanceController.new(rng(6), cfg, FIXED, FIXED)
	ctrl.spawn()
	for i in 45:
		ctrl.update(0.01) # 第 41 步（0.41s）自然变向，之后只过了 ~0.04s
	assert_false(ctrl.dodge(1.0), "自然变向后时钟已清零，门槛内的躲避被丢弃")

# ---- 撞墙反向的计时语义 ----

func test_wall_flip_does_not_reschedule_natural_flip() -> void:
	# 两台同种子：a 在自然变向前多撞了一次墙。若撞墙改写了变向排期，两台的
	# 「自然变向发生在第几步」就会不同。
	var a := AvoidanceController.new(rng(5), frozen_config(), FIXED, FIXED)
	var b := AvoidanceController.new(rng(5), frozen_config(), FIXED, FIXED)
	a.spawn()
	b.spawn()
	a.update(0.2)
	b.update(0.2)
	a.wall_flip()
	var a_flip_at := -1
	var b_flip_at := -1
	var a_dir := a.dir
	var b_dir := b.dir
	for i in 60:
		a.update(0.01)
		b.update(0.01)
		if a_flip_at < 0 and a.dir != a_dir:
			a_flip_at = i
		if b_flip_at < 0 and b.dir != b_dir:
			b_flip_at = i
	assert_gt(a_flip_at, 0, "a 的自然变向仍然发生")
	assert_eq(a_flip_at, b_flip_at, "撞墙反向没有推迟自然变向（计时未被重置）")
	assert_ne(a.dir, b.dir, "a 比 b 多翻了一次（撞墙那一次）")

func test_wall_flip_resets_dodge_min_clock() -> void:
	var cfg := frozen_config()
	var ctrl := frozen_controller(cfg)
	var twin := frozen_controller(cfg)
	ctrl.spawn()
	twin.spawn()
	ctrl.update(0.5)
	twin.update(0.5)
	assert_true(twin.dodge(1.0), "对照组：同一时刻躲避可以生效")
	ctrl.wall_flip()
	assert_false(ctrl.dodge(1.0), "撞墙反向把最短躲避时间时钟清零")

func test_wall_flip_keeps_fore_mix() -> void:
	var cfg := frozen_config()
	cfg.wander = 1.0
	cfg.aggression = 1.0
	cfg.retreat = 0.0
	var ctrl := frozen_controller(cfg)
	ctrl.spawn()
	assert_eq(ctrl.fore_mix, AvoidanceController.FORE_FORWARD, "刷新时掷出前压")
	# 把掷骰结果改成必然退开：撞墙反向若真的重掷，fore_mix 会立刻变
	cfg.aggression = 0.0
	cfg.retreat = 1.0
	ctrl.update(0.2)
	ctrl.wall_flip()
	assert_eq(ctrl.fore_mix, AvoidanceController.FORE_FORWARD, "撞墙反向不重掷前后分量")

# ---- 前后分量的重掷点 ----

func test_fore_mix_rerolls_only_on_natural_flip_and_spawn() -> void:
	var cfg := frozen_config()
	cfg.wander = 1.0
	cfg.aggression = 1.0
	cfg.retreat = 0.0
	var ctrl := AvoidanceController.new(rng(4), cfg, FIXED, FIXED)
	ctrl.spawn()
	assert_eq(ctrl.fore_mix, AvoidanceController.FORE_FORWARD, "刷新时掷出前压")
	cfg.aggression = 0.0
	cfg.retreat = 1.0
	ctrl.update(0.2)
	assert_true(ctrl.dodge(1.0), "越过门槛后躲避生效")
	assert_eq(ctrl.fore_mix, AvoidanceController.FORE_FORWARD, "躲避不重掷前后分量")
	for i in 45:
		ctrl.update(0.01) # 躲避重抽的 0.4s 排期到点 → 自然变向
	assert_eq(ctrl.fore_mix, AvoidanceController.FORE_BACK, "自然变向重掷前后分量")

func test_wander_zero_never_mixes_fore() -> void:
	var cfg := frozen_config()
	cfg.wander = 0.0
	var ctrl := AvoidanceController.new(rng(8), cfg, FIXED, FIXED)
	ctrl.spawn()
	for i in 200:
		ctrl.update(0.01)
		assert_eq(ctrl.fore_mix, AvoidanceController.FORE_NONE, "游走倾向 0 时永远纯横移")

# ---- 刷新 ----

func test_spawn_picks_mode_direction_and_timers() -> void:
	var ctrl := AvoidanceController.new(rng(12), config())
	ctrl.spawn()
	assert_true(ctrl.dir == AvoidanceController.DIR_LEFT or ctrl.dir == AvoidanceController.DIR_RIGHT, "刷新时方向是左右之一")
	assert_between(ctrl.flip_timer, float(AvoidanceController.STRAFE_MIN[2]), float(AvoidanceController.STRAFE_MAX[0]), "变向计时落在三档并集内")
	assert_between(ctrl.switch_timer, 1.0, 1.5, "切换计时落在设定区间内")
	assert_almost_eq(ctrl.since_flip, 0.0, 1e-9, "刷新是方向确定事件：时钟归零")