## 靶子 AI 的行为测试（票 02 验收条件 1 / 3–7；ADR-0013 的「纯逻辑缝」）。
##
## 只断言**外部行为**：给定感知（玩家位置与视角、设置值）与时间，断言移动、开火门控与开火结果。
## 场景侧的射线由注入的假实现代替，纯逻辑测试不启动场景、不需要渲染与输入设备。
## 唯一例外（ADR-0017）：滑铲朝向/开火闸测试直接调 `_begin_slide` 注入确定几何的滑铲——
## 公共触发链（重生垂直 / 攻击 ±90° 随机采样）方向由 rng 决定，无法保证「朝玩家滑」的断言前提。

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

# ---- bot 滑铲（票 09 / ADR-0016）----

func test_respawn_slide_moves_perpendicular_to_player_line() -> void:
	# 玩家在原点、bot 在 (0,-120)：连线垂直方向 = ±x，滑铲只动 x 不动 z
	var bot := bot_at(Vector2(0.0, -120.0))
	bot.try_respawn_slide(Vector2.ZERO, 120.0, false, 0.0)
	for i in 20:
		bot.update(0.01, perception())
	var pos := bot.sim.position()
	assert_gt(absf(pos.x), 30.0, "沿垂直方向滑出（0.2s × 399 u/s）")
	assert_almost_eq(pos.y, -120.0, 1e-6, "垂直滑铲不沿连线进退")

func test_respawn_slide_avoids_blocked_side() -> void:
	# +x 侧探到受阻：只剩 −x 可滑
	var probe := func(_origin: Vector2, dir: Vector2, _length: float) -> bool: return dir.x > 0.0
	var bot := bot_at(Vector2(0.0, -120.0), probe)
	bot.try_respawn_slide(Vector2.ZERO, 120.0, false, 0.0)
	for i in 20:
		bot.update(0.01, perception())
	assert_lt(bot.sim.position().x, -30.0, "受阻一侧被放弃，滑向另一侧")

func test_respawn_slide_gives_up_when_both_sides_blocked() -> void:
	var probe := func(_origin: Vector2, _dir: Vector2, _length: float) -> bool: return true
	var bot := bot_at(Vector2(0.0, -120.0), probe)
	bot.try_respawn_slide(Vector2.ZERO, 120.0, false, 0.0)
	assert_lt(bot.sim.speed(), 1.0, "两侧都受阻 → 放弃滑铲")

func test_attack_slide_triggers_when_line_of_sight_blocked() -> void:
	var bot := bot_at(Vector2(0.0, -120.0))
	var p := perception()
	p.slide_attack = true
	p.line_of_sight = false
	var fastest := 0.0
	for i in 60:
		bot.update(0.01, p)
		fastest = maxf(fastest, bot.sim.speed())
	assert_gt(fastest, 380.0, "视线被挡 → 注入满速滑铲（≈399，无前摇）")

func test_no_attack_slide_when_line_of_sight_clear() -> void:
	var bot := bot_at(Vector2(0.0, -120.0))
	var p := perception()
	p.slide_attack = true # 视线通畅不触发
	var fastest := 0.0
	for i in 60:
		bot.update(0.01, p)
		fastest = maxf(fastest, bot.sim.speed())
	assert_lt(fastest, GUN_CAP + 1.0)

func test_no_attack_slide_when_switch_off() -> void:
	var bot := bot_at(Vector2(0.0, -120.0))
	var p := perception()
	p.line_of_sight = false # 挡视线但开关没开
	var fastest := 0.0
	for i in 60:
		bot.update(0.01, p)
		fastest = maxf(fastest, bot.sim.speed())
	assert_lt(fastest, GUN_CAP + 1.0)

func test_attack_slide_cooldown_prevents_chain_slides() -> void:
	# 滑行 ≥0.35s + 冷却 1s ⇒ 2 秒内最多 2 次滑铲（无冷却时会落地就连滑）
	var bot := bot_at(Vector2(0.0, -120.0))
	var p := perception()
	p.slide_attack = true
	p.line_of_sight = false
	var starts := 0
	var was_sliding := false
	for i in 200:
		bot.update(0.01, p)
		var sliding := bot.sim.state() == "sliding"
		if sliding and not was_sliding:
			starts += 1
		was_sliding = sliding
	assert_lte(starts, 2, "冷却挡住连环滑铲")

func test_slide_jump_prob_one_leaves_ground() -> void:
	var bot := bot_at(Vector2(0.0, -120.0))
	var p := perception()
	p.slide_attack = true
	p.line_of_sight = false
	p.slide_jump = true
	p.slide_jump_prob = 1.0
	var airborne := false
	for i in 200: # 2 秒足够覆盖铲跳时刻窗口 [0.1, 0.6]
		bot.update(0.01, p)
		if bot.sim.state() == "airborne":
			airborne = true
			break
	assert_true(airborne, "铲跳概率 1.0 ⇒ 滑铲中必定升空")

func test_slide_jump_prob_zero_never_jumps() -> void:
	var bot := bot_at(Vector2(0.0, -120.0))
	var p := perception()
	p.slide_attack = true
	p.line_of_sight = false
	p.slide_jump = true
	p.slide_jump_prob = 0.0
	var airborne := false
	for i in 200:
		bot.update(0.01, p)
		airborne = airborne or bot.sim.state() == "airborne"
	assert_false(airborne, "概率 0 不跳")

# ---- 滑铲朝向与开火闸（ADR-0017）----

func test_slide_facing_turns_to_dir_then_back() -> void:
	var bot := bot_at(Vector2(0.0, -120.0))
	var p := perception()
	bot.try_respawn_slide(Vector2.ZERO, 40.0, false, 0.0)
	assert_true(bot.sim.state() == "sliding", "重生滑铲已注入")
	var turned_away := false
	var back_at_player := false
	# 参考方向每帧按当前位置取（bot 横移数百单位后「指向玩家」的 yaw 已不是初始值）。
	for i in 150:
		bot.update(0.01, p)
		var pos := bot.sim.position()
		var to_player := atan2(-(p.player_x - pos.x), -(p.player_z - pos.y))
		var off := absf(wrapf(bot.sim.get_facing() - to_player, -PI, PI))
		if i >= 6 and i < 14: # 起步转身段：面向滑行方向（垂直连线，偏离玩家 ≥60°）
			turned_away = turned_away or off > deg_to_rad(60.0)
		if i >= 12: # 回头伺服收口（最长约 0.8s）或站起后常规回正——都算「转回」
			back_at_player = back_at_player or off <= BotAi.SLIDE_AIM_TOL + 0.01
	assert_true(turned_away, "起步段先转向滑行方向（偏离玩家连线）")
	assert_true(back_at_player, "回头段（或站起后）转回玩家（≤10° 瞄住）")

func test_slide_turn_back_closes_gap() -> void:
	# 注入垂直于玩家连线的滑铲：起步段结束后回头伺服必须以 360°/s 收口，
	# 扣掉玩家方向随横移的扫动（≈124°/s），0.1s 内与玩家方向的夹角至少收窄 15°。
	var bot := bot_at(Vector2(0.0, -120.0))
	var p := perception()
	assert_true(bot._begin_slide(Vector2(-1.0, 0.0), false, 0.0), "注入垂直滑铲")
	var off_at := func(frame: int) -> float:
		for j in frame:
			bot.update(0.01, p)
		var pos := bot.sim.position()
		var to_player := atan2(-(p.player_x - pos.x), -(p.player_z - pos.y))
		return absf(wrapf(bot.sim.get_facing() - to_player, -PI, PI))
	var early: float = off_at.call(11) # 起步段刚结束
	var late: float = off_at.call(21) # 回头 0.1s 后
	assert_gt(early, deg_to_rad(60.0), "起步段结束仍偏离玩家")
	assert_gt(early - late, deg_to_rad(15.0), "回头伺服按角速度收口")

func test_slide_firing_gated_until_aimed() -> void:
	# 直接注入「朝玩家方向」的滑铲（绕过随机方向采样，几何确定）：
	# 起步转身段（前 0.1s）必未瞄住 → 零开火；之后朝向即对准玩家 → 滑铲中立即开火。
	var bot := bot_at(Vector2(0.0, -120.0))
	var p := perception()
	p.fire_enabled = true
	p.hit_rate = 100
	p.line_of_sight = true
	assert_false(bot.take_damage(1, p), "非致命受击 → 反击锁定立即持有")
	assert_true(bot._begin_slide(Vector2(0.0, 1.0), false, 0.0), "注入朝玩家的滑铲")
	var early_shots := 0
	var aimed_sliding_shots := 0
	for i in 60:
		aim_at(p, bot)
		var shots: Array = bot.update(0.01, p)
		if i < 10:
			early_shots += shots.size()
		elif bot.sim.state() == "sliding":
			aimed_sliding_shots += shots.size()
	assert_eq(early_shots, 0, "起步转身段开火闸关闭：零开火")
	assert_gt(aimed_sliding_shots, 0, "瞄住后滑铲中即开火")

# ---- bot 跳跃（票 11 / ADR-0023）----

## 打开跳跃开关并把间隔窗口压小（快速到点）。
func jump_perception(lo := 0.05, hi := 0.1) -> BotAi.Perception:
	var p := perception()
	p.jump_enabled = true
	p.jump_min = lo
	p.jump_max = hi
	return p

## 跑 seconds 秒，返回 `[离地次数, 离地帧数]`（airborne 上升沿计次）。
func run_jump_phases(bot: BotAi, p: BotAi.Perception, seconds: float) -> Array:
	var phases := 0
	var air_frames := 0
	var was_air := false
	var elapsed := 0.0
	while elapsed < seconds:
		bot.update(0.01, p)
		var air := bot.sim.airborne()
		if air and not was_air:
			phases += 1
		air_frames += 1 if air else 0
		was_air = air
		elapsed += 0.01
	return [phases, air_frames]

func test_jump_enabled_fires_and_lands() -> void:
	var bot := bot_at(Vector2(0.0, -120.0))
	var result := run_jump_phases(bot, jump_perception(), 3.0)
	assert_gt(result[0], 0, "开关开着就该跳起来")
	assert_gt(result[1], 0, "有离地帧")
	assert_lt(result[0], 8, "滞空约 0.72s：3 秒内到点作废重抽，跳次远少于到点次数")
	# 连跳节奏下任意采样点大概率恰在空中——关掉开关（计时器冻结）再跑一段，必须回到地面
	run_jump_phases(bot, jump_perception(999.0, 999.0), 1.5)
	assert_false(bot.sim.airborne(), "不再到点后落地（不会卡在空中）")

func test_jump_disabled_never_jumps() -> void:
	var bot := bot_at(Vector2(0.0, -120.0))
	var p := jump_perception()
	p.jump_enabled = false
	var result := run_jump_phases(bot, p, 2.0)
	assert_eq(result[0], 0, "开关关着不该跳")
	assert_eq(result[1], 0, "也没有离地帧")

func test_no_rejump_mid_air() -> void:
	# 固定 0.05s 间隔（滞空约 0.72s 内到点十余次）：首个上升沿后 0.6s 内不得出现第二个
	# 上升沿——空中重触发或落地即重跳都会把间隔压进 0.6s 以内（单帧信号 + 空中作废的直接观察）。
	var bot := bot_at(Vector2(0.0, -120.0))
	var p := jump_perception(0.05, 0.05)
	var first_at := -1.0
	var gap := -1.0
	var was_air := false
	var elapsed := 0.0
	while elapsed < 3.0 and gap < 0.0:
		bot.update(0.01, p)
		var air := bot.sim.airborne()
		if air and not was_air:
			if first_at < 0.0:
				first_at = elapsed
			elif elapsed - first_at > 0.6:
				gap = elapsed - first_at
			else:
				gap = -2.0 # 滞空未结束又离地——违例
				break
		was_air = air
		elapsed += 0.01
	assert_gt(first_at, 0.0, "起跳了")
	assert_gt(gap, 0.0, "第二次离地发生在滞空结束之后（间隔 >0.6s）")

func test_jump_blocked_at_due_is_discarded_not_queued() -> void:
	# 固定 1s 间隔：1.0s 到点时视线被挡 → 作废重抽（下一轮整整 1s 后）；
	# 1.2s 恢复视野——排队语义会在恢复瞬间立刻补跳，作废重抽不该发生。
	var bot := bot_at(Vector2(0.0, -120.0))
	var p := jump_perception(1.0, 1.0)
	p.line_of_sight = false
	var jumped_while_blocked := false
	var jumped_right_after_open := false
	var was_air := false
	var elapsed := 0.0
	while elapsed < 2.5:
		if elapsed >= 1.2:
			p.line_of_sight = true
		bot.update(0.01, p)
		if bot.sim.airborne() and not was_air:
			if elapsed < 1.2:
				jumped_while_blocked = true
			elif elapsed < 1.7: # 作废重抽的下一轮到点在 2.0s 附近
				jumped_right_after_open = true
		was_air = bot.sim.airborne()
		elapsed += 0.01
	assert_false(jumped_while_blocked, "视线被挡期间不跳")
	assert_false(jumped_right_after_open, "到点作废不排队：视野恢复不立刻补跳")
	assert_true(was_air, "下一轮（2.0s 附近）照常起跳")

func test_jump_skips_while_sliding() -> void:
	var bot := bot_at(Vector2(0.0, -120.0))
	var p := jump_perception(0.05, 0.1)
	assert_true(bot._begin_slide(Vector2(1.0, 0.0), false, 0.0), "注入滑铲（ADR-0017 同款豁免）")
	var saw_sliding := false
	for i in 30: # 滑铲 0.35–0.9s 才站起：0.3s 内全程滑行，期间多个到点全作废
		bot.update(0.01, p)
		saw_sliding = saw_sliding or bot._sliding
		assert_false(bot.sim.airborne(), "滑铲中不起跳（滑铲中的跳跃归铲跳管）")
	assert_true(saw_sliding, "前置：确实处于滑铲中")

func test_jump_dice_do_not_disturb_fire_sequence() -> void:
	# 同种子两台 bot，唯一差别是跳跃开关：开火骰序列必须逐发一致（ADR-0023 随机源隔离）。
	var a := bot_at(Vector2(0.0, -400.0))
	var b := bot_at(Vector2(0.0, -400.0))
	var pa := perception()
	pa.fire_enabled = true
	pa.hit_rate = 50
	pa.line_of_sight = true
	var pb := perception()
	pb.fire_enabled = true
	pb.hit_rate = 50
	pb.line_of_sight = true
	pb.jump_enabled = true
	pb.jump_min = 0.05
	pb.jump_max = 0.1
	var seq_a: Array = []
	var seq_b: Array = []
	var elapsed := 0.0
	while elapsed < 5.0:
		aim_at(pa, a)
		aim_at(pb, b)
		for s in a.update(0.01, pa):
			seq_a.append(s)
		for s in b.update(0.01, pb):
			seq_b.append(s)
		elapsed += 0.01
	assert_eq(seq_a.size(), seq_b.size(), "开火次数一致")
	var mismatch := false
	for i in seq_a.size():
		if seq_a[i] != seq_b[i]:
			mismatch = true
	assert_false(mismatch, "命中/失手序列逐发一致（跳跃骰独立随机源）")