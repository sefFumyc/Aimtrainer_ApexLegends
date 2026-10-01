## 靶子 AI 的行为测试（票 02 验收条件 1 / 3–7；ADR-0013 的「纯逻辑缝」）。
##
## 只断言**外部行为**：给定感知（玩家位置与视角、设置值）与时间，断言移动、开火门控与开火结果。
## 场景侧的射线由注入的假实现代替，纯逻辑测试不启动场景、不需要渲染与输入设备。

extends GutTest

const GUN_CAP := MovementSimulator.BASE_SPEED * MovementSimulator.SPEED_MULT_GUN
const ADS_CAP := MovementSimulator.BASE_SPEED * MovementSimulator.SPEED_MULT_ADS

func rng(seed_value: int) -> RandomNumberGenerator:
	var out := RandomNumberGenerator.new()
	out.seed = seed_value
	return out

func config() -> AvoidanceController.Config:
	return AvoidanceController.Config.new()

func perception(player := Vector2.ZERO, yaw := 0.0, pitch := 0.0) -> BotAi.Perception:
	var p := BotAi.Perception.new()
	p.player_x = player.x
	p.player_z = player.y
	p.player_eye_y = Physique.EYE_HEIGHT
	p.player_yaw = yaw
	p.player_pitch = pitch
	p.body_radius = Physique.BODY_RADIUS_DEFAULT
	return p

## 玩家把视线对准 bot 当前位置（视锥判定的正常使用方式）。
func aim_at(p: BotAi.Perception, bot: BotAi) -> void:
	var pos := bot.sim.position()
	p.player_yaw = atan2(-(pos.x - p.player_x), -(pos.y - p.player_z))

func bot_at(at: Vector2, probe := Callable(), cfg: AvoidanceController.Config = null) -> BotAi:
	var out := BotAi.new(rng(17), cfg if cfg != null else config(), probe)
	out.spawn(at)
	return out

## 跑 `seconds` 秒，返回累计开火数。`aim` 为假时保持玩家当前的视线角（测「视锥外」）。
func run(bot: BotAi, p: BotAi.Perception, seconds: float, aim := true) -> int:
	var shots := 0
	var elapsed := 0.0
	while elapsed < seconds:
		if aim:
			aim_at(p, bot)
		shots += bot.update(0.01, p).size()
		elapsed += 0.01
	return shots

## 跑 `seconds` 秒，返回 `[开火数, 命中数]`。
func run_shots(bot: BotAi, p: BotAi.Perception, seconds: float) -> Array:
	var total := 0
	var hits := 0
	var elapsed := 0.0
	while elapsed < seconds:
		aim_at(p, bot)
		for hit in bot.update(0.01, p):
			total += 1
			if hit:
				hits += 1
		elapsed += 0.01
	return [total, hits]

# ---- 移动：持续侧移、共用移动模型 ----

func test_bot_never_stands_still() -> void:
	var bot := bot_at(Vector2(0.0, -120.0))
	var p := perception() # 出生距离正好落在死区带内：进退推力为 0，位移全靠侧移
	var smallest := 1e9
	var prev := bot.sim.position()
	for i in 300:
		bot.update(0.01, p)
		var now := bot.sim.position()
		smallest = minf(smallest, now.distance_to(prev))
		prev = now
	assert_gt(smallest, 0.0, "每一帧都有位移，没有静止空窗")

func test_bot_uses_the_shared_movement_model() -> void:
	var bot := bot_at(Vector2(0.0, -400.0)) # 距离远 → 满幅前压，与侧移合成 45°
	var p := perception()
	var fastest := 0.0
	for i in 400:
		bot.update(0.01, p)
		fastest = maxf(fastest, bot.sim.speed())
	assert_almost_eq(fastest, GUN_CAP, 0.5, "封顶 = 持枪满速（与玩家同一套移动模型），不会更快")

func test_bot_ads_caps_speed() -> void:
	var p := perception()
	p.ads = true
	var bot := bot_at(Vector2(0.0, -400.0))
	var fastest := 0.0
	for i in 400:
		bot.update(0.01, p)
		fastest = maxf(fastest, bot.sim.speed())
	assert_almost_eq(fastest, ADS_CAP, 0.5, "常驻开镜时移速封顶 = 开镜档 130.1")

func test_range_keeping_closes_when_too_far() -> void:
	var bot := bot_at(Vector2(0.0, -500.0))
	var p := perception()
	var before := bot.sim.position().length()
	run(bot, p, 1.0)
	var after := bot.sim.position().length()
	assert_lt(after, before - 30.0, "距离过远 → 前压逼近")

func test_range_keeping_backs_off_when_too_close() -> void:
	var bot := bot_at(Vector2(0.0, -50.0))
	var p := perception()
	var before := bot.sim.position().length()
	run(bot, p, 1.0)
	var after := bot.sim.position().length()
	assert_gt(after, before + 15.0, "距离过近 → 后退拉开")

func test_range_keeping_deadband_does_not_approach() -> void:
	var bot := bot_at(Vector2(0.0, -120.0))
	var p := perception()
	var closest := 1e9
	for i in 40:
		bot.update(0.01, p)
		closest = minf(closest, bot.sim.position().length())
	assert_gt(closest, 118.0, "死区带内不做进退，只侧移")

func test_wander_corridor_override_beats_fore_mix() -> void:
	# 前后分量掷出「退开」，但距离远出走廊 → 硬约束压满前压（不看掷骰）
	var cfg := config()
	cfg.wander = 1.0
	cfg.aggression = 0.0
	cfg.retreat = 1.0
	var bot := bot_at(Vector2(0.0, -400.0), Callable(), cfg)
	var p := perception()
	p.wander_mode = true
	p.range_amp = 25.0
	var before := bot.sim.position().length()
	run(bot, p, 1.0)
	assert_lt(bot.sim.position().length(), before - 30.0, "越出走廊 → 满幅归位，无视掷出的退开")

func test_wander_inside_corridor_uses_fore_mix() -> void:
	var cfg := config()
	cfg.wander = 1.0
	cfg.aggression = 0.0
	cfg.retreat = 1.0
	var bot := bot_at(Vector2(0.0, -120.0), Callable(), cfg)
	var p := perception()
	p.wander_mode = true
	p.range_amp = 25.0
	var before := bot.sim.position().length()
	run(bot, p, 1.0)
	var after := bot.sim.position().length()
	# 走廊内（|距离误差| ≤ 半宽）不看硬约束，按掷出的「退开」后撤；退到外沿
	# 145 = 120 + 25 就被硬约束压回，所以位移量由走廊宽度决定，不会一路退开。
	assert_gt(after, before + 15.0, "走廊内交还给掷骰 → 按「退开」后撤")
	assert_lt(after, before + 30.0, "退到走廊外沿即被硬约束压住，不会一路退开")

# ---- 前向探测（ADR-0005） ----

func test_forward_probe_flips_early_on_obstacle() -> void:
	var probe := func(origin: Vector2, dir: Vector2, length: float) -> bool: return true
	var bot := bot_at(Vector2(0.0, -120.0), probe)
	bot.avoidance.dir = AvoidanceController.DIR_RIGHT
	bot.update(0.01, perception())
	assert_eq(bot.avoidance.dir, AvoidanceController.DIR_LEFT, "探到遮挡物时提前变向")

func test_forward_probe_flip_keeps_fore_mix() -> void:
	var cfg := config()
	cfg.wander = 1.0
	cfg.aggression = 1.0
	cfg.retreat = 0.0
	var probe := func(origin: Vector2, dir: Vector2, length: float) -> bool: return true
	var bot := bot_at(Vector2(0.0, -120.0), probe, cfg)
	assert_eq(bot.avoidance.fore_mix, AvoidanceController.FORE_FORWARD, "刷新时掷出前压")
	cfg.aggression = 0.0
	cfg.retreat = 1.0
	bot.avoidance.dir = AvoidanceController.DIR_RIGHT
	bot.update(0.01, perception())
	assert_eq(bot.avoidance.dir, AvoidanceController.DIR_LEFT, "提前变向")
	assert_eq(bot.avoidance.fore_mix, AvoidanceController.FORE_FORWARD, "复用撞墙反向语义：不重掷前后分量")

func test_forward_probe_length_follows_arena_layout() -> void:
	# 玩家放在 bot 正后方，使「左侧移」正好朝墙外；再关掉前后分量，探测方向即纯侧移。
	var cfg := config()
	cfg.wander = 0.0
	var p := perception(Vector2(120.0, -900.0))
	p.wander_mode = true
	p.range_amp = 25.0
	var lengths: Array = []
	var recorder := func(origin: Vector2, dir: Vector2, length: float) -> bool:
		lengths.append(length)
		return false

	# bot 在 (0,-900)：离墙 100 → 探测 60 够不到，120 / 180 够得到。
	var open_bot := bot_at(Vector2(0.0, -900.0), recorder, cfg)
	open_bot.avoidance.dir = AvoidanceController.DIR_LEFT
	p.arena_layout = CoverLayout.Layout.OPEN
	open_bot.update(0.01, p)
	assert_eq(open_bot.avoidance.dir, AvoidanceController.DIR_LEFT, "空旷档探测短，够不到墙 → 不提前变向")
	assert_eq(lengths.size(), 1, "边界没挡住时交给注入的射线")
	assert_almost_eq(lengths[0], BotAi.PROBE_LENGTHS[0], 1e-6, "空旷档探测长度")

	var sparse_bot := bot_at(Vector2(0.0, -900.0), recorder, cfg)
	sparse_bot.avoidance.dir = AvoidanceController.DIR_LEFT
	p.arena_layout = CoverLayout.Layout.SPARSE
	sparse_bot.update(0.01, p)
	assert_eq(sparse_bot.avoidance.dir, AvoidanceController.DIR_RIGHT, "少量遮挡档探测 120，够得到墙 → 提前变向")

	var dense_bot := bot_at(Vector2(0.0, -900.0), recorder, cfg)
	dense_bot.avoidance.dir = AvoidanceController.DIR_LEFT
	p.arena_layout = CoverLayout.Layout.DENSE
	dense_bot.update(0.01, p)
	assert_eq(dense_bot.avoidance.dir, AvoidanceController.DIR_RIGHT, "多遮挡档探测 180 → 提前变向")

	# 远离墙（离墙 600，三档都够不到）：注入射线收到的长度就是档位阈值本身。
	var far_p := perception(Vector2(120.0, -400.0))
	far_p.wander_mode = true
	far_p.range_amp = 25.0
	var recorded: Array = []
	var far_recorder := func(origin: Vector2, dir: Vector2, length: float) -> bool:
		recorded.append(length)
		return false
	for layout in [CoverLayout.Layout.OPEN, CoverLayout.Layout.SPARSE, CoverLayout.Layout.DENSE]:
		var bot := bot_at(Vector2(0.0, -400.0), far_recorder, cfg)
		bot.avoidance.dir = AvoidanceController.DIR_LEFT
		far_p.arena_layout = layout
		bot.update(0.01, far_p)
		assert_eq(bot.avoidance.dir, AvoidanceController.DIR_LEFT, "空地档不提前变向")
	assert_eq(recorded.size(), 3)
	assert_almost_eq(recorded[0], BotAi.PROBE_LENGTHS[0], 1e-6, "空旷档阈值")
	assert_almost_eq(recorded[1], BotAi.PROBE_LENGTHS[1], 1e-6, "少量遮挡档阈值")
	assert_almost_eq(recorded[2], BotAi.PROBE_LENGTHS[2], 1e-6, "多遮挡档阈值")

# ---- 受阻翻向（ADR-0014）----

## 承诺窗口：两侧都被探到受阻时若不设窗口，就会**每帧翻向**，
## 而每次翻向都重触发「转向衰减」，逐帧相乘把速度抖到近 0（验收 3 的「贴着遮挡物抖动」）。
func test_forward_probe_flip_has_commit_window() -> void:
	var probe := func(origin: Vector2, dir: Vector2, length: float) -> bool: return true
	var bot := bot_at(Vector2(0.0, -120.0), probe)
	# 掐掉自然变向与模式切换，让断言只反映承诺窗口本身
	bot.avoidance.flip_timer = 999.0
	bot.avoidance.switch_timer = 999.0
	bot.avoidance.dir = AvoidanceController.DIR_RIGHT
	bot.update(0.01, perception())
	assert_eq(bot.avoidance.dir, AvoidanceController.DIR_LEFT, "探到受阻即翻向")
	bot.update(0.01, perception())
	assert_eq(bot.avoidance.dir, AvoidanceController.DIR_LEFT, "承诺窗口内不再翻向")
	bot.update(BotAi.FLIP_COMMIT, perception())
	assert_eq(bot.avoidance.dir, AvoidanceController.DIR_RIGHT, "窗口走完仍受阻 → 再翻一次")

## 物理受阻兜底：探测射线从身体中心发出，探不到身体边缘已经剐上的柱角，
## 于是会出现「纯逻辑满速、物理位移归零」的原地卡死——由物理事实来翻向。
func test_blocked_by_physics_flips_with_commit_window() -> void:
	var p := perception()
	p.fire_enabled = false
	var bot := bot_at(Vector2(0.0, -120.0))
	run(bot, p, 0.5, false)
	bot.avoidance.flip_timer = 999.0
	bot.avoidance.switch_timer = 999.0
	var dir := bot.avoidance.dir
	assert_false(bot.on_blocked(2.9, 2.9), "物理位移与纯逻辑步长一致 → 不算受阻")
	assert_eq(bot.avoidance.dir, dir)
	assert_true(bot.on_blocked(2.9, 0.0), "物理位移归零 → 翻向")
	assert_ne(bot.avoidance.dir, dir)
	assert_false(bot.on_blocked(2.9, 0.0), "承诺窗口内不再翻向")
	bot.update(BotAi.FLIP_COMMIT, p)
	assert_true(bot.on_blocked(2.9, 0.0), "窗口走完仍受阻 → 再翻一次")
	assert_false(bot.on_blocked(0.0, 0.0), "纯逻辑本帧没有位移时不算受阻")

# ---- 开火门控 ----

func test_fire_toggle_off_means_no_shots() -> void:
	var bot := bot_at(Vector2(0.0, -120.0))
	var p := perception() # 玩家一直瞄着 bot
	p.fire_enabled = false
	assert_eq(run(bot, p, 5.0), 0, "关掉开火开关后只移动不攻击")

func test_aim_hold_gate_is_350ms() -> void:
	var bot := bot_at(Vector2(0.0, -120.0))
	var p := perception()
	p.fire_enabled = true
	p.hit_rate = 100
	assert_eq(run(bot, p, 0.33), 0, "被瞄上不足 350ms 不开火")
	assert_gt(run(bot, p, 0.3), 0, "越过 350ms 后开始开火")

func test_hit_backlash_fires_immediately() -> void:
	var bot := bot_at(Vector2(0.0, -120.0))
	var p := perception()
	p.fire_enabled = true
	p.hit_rate = 100
	p.player_yaw = PI / 2.0 # 玩家背对 bot：视锥外，靠自身计时永远不开火
	assert_eq(run(bot, p, 5.0, false), 0, "视锥外不开火")
	assert_false(bot.take_damage(25, p), "非致命伤害")
	assert_gt(run(bot, p, 0.05, false), 0, "被打中立刻还手（跳过 350ms 计时）")

func test_fire_lock_keeps_firing_after_player_looks_away() -> void:
	var bot := bot_at(Vector2(0.0, -120.0))
	var p := perception()
	p.fire_enabled = true
	p.hit_rate = 100
	assert_gt(run(bot, p, 0.6), 0, "先靠视锥计时触发开火")
	p.player_yaw = PI / 2.0 # 玩家转开
	assert_gt(run(bot, p, 1.0, false), 0, "攻击锁定：转开视线后仍持续开火")

func test_line_of_sight_blocks_firing() -> void:
	var bot := bot_at(Vector2(0.0, -120.0))
	var p := perception()
	p.fire_enabled = true
	p.hit_rate = 100
	p.line_of_sight = false
	assert_eq(run(bot, p, 3.0), 0, "躲在遮挡物后面时不向玩家开火")
	p.line_of_sight = true
	assert_gt(run(bot, p, 0.5), 0, "视线一恢复即刻恢复开火")

func test_hit_rate_is_a_percentage() -> void:
	var miss := bot_at(Vector2(0.0, -120.0))
	var p_miss := perception()
	p_miss.fire_enabled = true
	p_miss.hit_rate = 0
	var miss_result := run_shots(miss, p_miss, 3.0)
	assert_gt(miss_result[0], 0, "命中率 0 时仍在开火")
	assert_eq(miss_result[1], 0, "命中率 0 → 一发都不掉血")

	var always := bot_at(Vector2(0.0, -120.0))
	var p_always := perception()
	p_always.fire_enabled = true
	p_always.hit_rate = 100
	var always_result := run_shots(always, p_always, 3.0)
	assert_gt(always_result[0], 0, "命中率 100 时确实在开火")
	assert_eq(always_result[1], always_result[0], "命中率 100 → 每发都命中")

	var half := bot_at(Vector2(0.0, -120.0))
	var p_half := perception()
	p_half.fire_enabled = true
	p_half.hit_rate = 50
	var half_result := run_shots(half, p_half, 6.0)
	assert_gt(half_result[0], 20, "6 秒内开火足够多")
	assert_gt(half_result[1], 0, "命中率 50 会命中")
	assert_lt(half_result[1], half_result[0], "命中率 50 也会落空")

func test_dodge_chance_flips_on_hit() -> void:
	var p := perception()
	p.fire_enabled = false
	p.dodge_chance = 1.0
	var bot := bot_at(Vector2(0.0, -120.0))
	run(bot, p, 0.5, false) # 越过最短躲避时间门槛
	var dir := bot.avoidance.dir
	bot.take_damage(25, p)
	assert_ne(bot.avoidance.dir, dir, "躲避概率 1.0 时被命中立刻翻向")

func test_lethal_hit_does_not_dodge() -> void:
	var p := perception()
	p.dodge_chance = 1.0
	var bot := bot_at(Vector2(0.0, -120.0))
	run(bot, p, 0.5, false)
	var dir := bot.avoidance.dir
	assert_true(bot.take_damage(BotAi.MAX_HP, p), "致命一击")
	assert_eq(bot.avoidance.dir, dir, "致命那一发不躲避")
	assert_false(bot.alive)

# ---- 死亡与刷新 ----

func test_dead_bot_respawns_after_delay() -> void:
	var p := perception()
	var bot := bot_at(Vector2(0.0, -120.0))
	bot.take_damage(BotAi.MAX_HP, p)
	assert_eq(bot.respawn_left, BotAi.RESPAWN_DELAY, "死亡后进入刷新倒计时")
	bot.update(BotAi.RESPAWN_DELAY - 0.1, p)
	assert_false(bot.alive, "倒计时未走完仍是死亡状态")
	bot.update(0.2, p)
	assert_true(bot.respawn_left <= 0.0, "倒计时走完，该刷新了")