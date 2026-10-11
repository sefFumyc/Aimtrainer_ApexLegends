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

func test_fast_interval_chains_continuous_air() -> void:
	# 固定 0.05s 间隔（远小于滞空 0.72s）：每轮到点都在空中、照发锁存信号，落地帧立即起跳
	# （票 12 / ADR-0024 锁存 bhop）——首跳之后帧级不应再有落地帧。
	# 旧「作废」语义下每跳都有地面停留（landings ≥ 2）。
	var bot := bot_at(Vector2(0.0, -120.0))
	var p := jump_perception(0.05, 0.05)
	var took_off := false
	var landings := 0
	var was_air := false
	var elapsed := 0.0
	while elapsed < 2.0:
		bot.update(0.01, p)
		var air := bot.sim.airborne()
		if air:
			took_off = true
		elif was_air:
			landings += 1
		was_air = air
		elapsed += 0.01
	assert_true(took_off, "起跳过")
	assert_eq(landings, 0, "连跳成立：0.05s 间隔全程锁存，帧级无落地帧")

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

# ---- bot 跳跃满速门 + RAS（票 13 / ADR-0028）----

## 跑到首次离地为止，返回 `[起跳时刻, 起跳瞬间速率]`；`seconds` 内未离地返回 [-1.0, 0.0]。
func first_takeoff(bot: BotAi, p: BotAi.Perception, seconds: float) -> Array:
	var was_air := false
	var elapsed := 0.0
	while elapsed < seconds:
		bot.update(0.01, p)
		if bot.sim.airborne() and not was_air:
			return [elapsed + 0.01, bot.sim.speed()]
		was_air = bot.sim.airborne()
		elapsed += 0.01
	return [-1.0, 0.0]

func test_jump_pends_until_max_speed() -> void:
	# 满速门（普适无开关）：静止起跑约 0.14s 才满速——0.05s 首跳到点未满速 → 挂起，
	# 满速瞬间才跳；旧语义 0.05s 即离地。起跳瞬间必须已达持枪满速（ε=1.0）。
	var bot := bot_at(Vector2(0.0, -120.0))
	var result := first_takeoff(bot, jump_perception(0.05, 0.05), 1.0)
	assert_gt(result[0], 0.10, "未满速的到点被挂起顺延（旧语义 0.05s 即跳）")
	assert_gte(result[1], GUN_CAP - 1.0, "起跳瞬间已达持枪满速（满速门 ε=1.0）")

func test_ads_shrinks_the_speed_gate() -> void:
	# 满速门每帧按当前开镜状态取修正器：开镜档目标更低（130.1），满速时刻早于持枪档。
	var bot := bot_at(Vector2(0.0, -120.0))
	var p := jump_perception(0.05, 0.05)
	p.ads = true
	var result := first_takeoff(bot, p, 1.0)
	assert_gt(result[0], 0.045, "开镜档未满速同样挂起")
	assert_gte(result[1], ADS_CAP - 1.0, "起跳瞬间达开镜档满速")
	assert_lt(result[0], 0.14, "开镜档目标更低：满速时刻早于持枪档（约 0.057s vs 0.14s）")

func test_ras_prob_zero_jumps_immediately_when_fast() -> void:
	# P=0：不掷 RAS 骰（序列与旧版逐发一致的前提）——满速状态下到点当帧起跳、无挂起。
	var bot := bot_at(Vector2(0.0, -120.0))
	var p := perception()
	# 热身前压住变向/模式切换：0.3s 热身窗口内若发生自然变向，热身结束时仍在恢复期（未满速）。
	bot.avoidance.flip_timer = 999.0
	bot.avoidance.switch_timer = 999.0
	run(bot, p, 0.3) # 热身（跳跃关）：纯加速到满速
	p.jump_enabled = true
	p.jump_min = 0.05
	p.jump_max = 0.05
	var jumped := false
	var elapsed := 0.0
	while elapsed < 0.3:
		bot.update(0.01, p)
		if bot.sim.airborne():
			jumped = true
			break
		elapsed += 0.01
	assert_true(jumped, "满速 + P=0：到点立即起跳")
	assert_lt(elapsed, 0.10, "首跳到点（0.05s）当帧离地，无挂起延迟")

func test_ras_waits_for_direction_flip_then_max_speed() -> void:
	# P=1 + 已满速到点 → RAS 挂起等变向：压住变向计时器期间永不跳；手动翻向（dir 翻转
	# 统一口径，模拟躲避/撞墙翻向）→ 等满速恢复 → 恢复瞬间起跳且仍是满速跳。
	var bot := bot_at(Vector2(0.0, -120.0))
	var p := jump_perception(0.05, 0.05)
	p.jump_ras_prob = 1.0
	p.jump_enabled = false
	bot.avoidance.flip_timer = 5.0 # 压住自然变向（热身前压：0.3s 热身内变向会让热身停在恢复期）
	bot.avoidance.switch_timer = 5.0 # 压住模式切换（切换会重抽变向计时）
	run(bot, p, 0.3) # 热身：纯加速到满速
	p.jump_enabled = true
	var jumped := false
	var elapsed := 0.0
	while elapsed < 0.4 and not jumped:
		bot.update(0.01, p)
		jumped = bot.sim.airborne()
		elapsed += 0.01
	assert_false(jumped, "RAS 等变向阶段：dir 未翻转不跳")
	bot.avoidance.dir = -bot.avoidance.dir # 手动翻向 → 进等满速阶段（速度被转向衰减压低）
	var result := first_takeoff(bot, p, 1.0)
	assert_gt(result[0], 0.0, "变向后满速瞬间起跳")
	assert_gte(result[1], GUN_CAP - 1.0, "RAS 跳仍是满速跳")

func test_ras_in_recovery_goes_straight_to_speed_wait() -> void:
	# P=1 + 到点时未满速（起跑加速段）→ 不等下一次变向、直接等满速（Q8=A）：
	# 错误实现（一律等变向）会让起跳落到 flip_timer 自然到点之后（>0.5s）。
	var bot := bot_at(Vector2(0.0, -120.0))
	var p := jump_perception(0.05, 0.05)
	p.jump_ras_prob = 1.0
	var result := first_takeoff(bot, p, 1.0)
	assert_gt(result[0], 0.10, "未满速到点挂起等满速")
	assert_lt(result[0], 0.35, "不等下一次变向：满速瞬间即跳")

func test_pending_discarded_when_los_drops() -> void:
	# 0.05s 到点（未满速）→ 挂起；0.08s 视线被挡 → 挂起作废；0.30s 恢复视野不补跳
	# （作废语义——计时器从冻结值继续倒数，下轮到点满速照常跳）。
	var bot := bot_at(Vector2(0.0, -120.0))
	var p := jump_perception(0.05, 0.05)
	var jumped_while_blocked := false
	var jumped_right_after_open := false
	var jumped_later := false
	var was_air := false
	var elapsed := 0.0
	while elapsed < 1.0 and not (jumped_while_blocked or jumped_right_after_open or jumped_later):
		p.line_of_sight = elapsed < 0.08 or elapsed >= 0.30
		bot.update(0.01, p)
		if bot.sim.airborne() and not was_air:
			if elapsed < 0.30:
				jumped_while_blocked = true
			elif elapsed < 0.33:
				jumped_right_after_open = true
			else:
				jumped_later = true
		was_air = bot.sim.airborne()
		elapsed += 0.01
	assert_false(jumped_while_blocked, "挂起中视线丢 → 作废不跳")
	assert_false(jumped_right_after_open, "视野恢复不补跳（作废语义）")
	assert_true(jumped_later, "下轮到点满速照常跳")

func test_pending_timeout_discards() -> void:
	# 挂起超 2s 作废（兜底）：0.05s 到点（未满速）挂起，挂起时钟拨到阈值边缘——
	# 下一帧超时作废（哪怕随后爬到满速也不跳）；冻结计时器继续倒数、下轮到点照常判定。
	var bot := bot_at(Vector2(0.0, -120.0))
	var p := jump_perception(0.05, 0.05)
	var elapsed := 0.0
	while elapsed < 0.2 and not bot._jump_pending:
		bot.update(0.01, p)
		elapsed += 0.01
	assert_true(bot._jump_pending, "前置：未满速到点进入挂起")
	bot._jump_pend_t = BotAi.JUMP_PENDING_TIMEOUT - 0.005
	var air_frames := 0
	for i in 5:
		bot.update(0.01, p)
		air_frames += 1 if bot.sim.airborne() else 0
	assert_false(bot._jump_pending, "超时作废：挂起解除")
	assert_eq(air_frames, 0, "作废瞬间不跳")
	var result := first_takeoff(bot, p, 1.0)
	assert_gt(result[0], 0.0, "超时作废不排队：下轮到点满速照常跳")

func test_pending_freezes_jump_timer() -> void:
	# 挂起期间计时器冻结（Q9=A 零 RNG 消耗）：_jump_wait 保持到点时重抽的值不动，
	# 挂起解除后从冻结值继续倒数。
	var bot := bot_at(Vector2(0.0, -120.0))
	var p := jump_perception(0.05, 0.05)
	var elapsed := 0.0
	while elapsed < 0.2 and not bot._jump_pending:
		bot.update(0.01, p)
		elapsed += 0.01
	assert_true(bot._jump_pending, "前置：挂起中")
	var frozen := bot._jump_wait
	for i in 5: # 挂起 0.05s（0.14s 满速起跳前有 9 帧，取 5 帧窗口）
		bot.update(0.01, p)
		assert_eq(bot._jump_wait, frozen, "挂起期间计时器冻结")

func test_pending_discarded_when_slide_starts() -> void:
	# 挂起中进入滑铲 → 作废（ADR-0028 作废路径之一）；作废不跳。
	var bot := bot_at(Vector2(0.0, -120.0))
	var p := jump_perception(0.05, 0.05)
	var elapsed := 0.0
	while elapsed < 0.2 and not bot._jump_pending:
		bot.update(0.01, p)
		elapsed += 0.01
	assert_true(bot._jump_pending, "前置：挂起中")
	bot._sliding = true # 滑铲注入（ADR-0017 先例：公共触发链方向由 rng 决定，直接注入确定状态）
	bot.update(0.01, p)
	assert_false(bot._jump_pending, "挂起中进入滑铲 → 作废")
	assert_false(bot.sim.airborne(), "作废瞬间不跳")

func test_pending_discarded_on_death() -> void:
	# 挂起中受致命伤 → 清挂起（跳跃时钟一并复位，「刷新」后从首抽重开）；
	# 非致命受击不清挂起（躲避翻向反而是 RAS 等变向阶段的合法锚点）。
	var bot := bot_at(Vector2(0.0, -120.0))
	var p := jump_perception(0.05, 0.05)
	var elapsed := 0.0
	while elapsed < 0.2 and not bot._jump_pending:
		bot.update(0.01, p)
		elapsed += 0.01
	assert_true(bot._jump_pending, "前置：挂起中")
	assert_true(bot.take_damage(999, p), "致命一击")
	assert_false(bot._jump_pending, "死亡清挂起")

func test_pending_cleared_on_respawn() -> void:
	# 「刷新」（spawn）清挂起并重抽首跳间隔（ADR-0028）。
	var bot := bot_at(Vector2(0.0, -120.0))
	var p := jump_perception(0.05, 0.05)
	var elapsed := 0.0
	while elapsed < 0.2 and not bot._jump_pending:
		bot.update(0.01, p)
		elapsed += 0.01
	assert_true(bot._jump_pending, "前置：挂起中")
	bot.spawn(Vector2(60.0, -120.0))
	assert_false(bot._jump_pending, "刷新清挂起")
	assert_lt(bot._jump_wait, 0.0, "刷新重抽首跳间隔（_jump_wait = -1 待首帧重抽）")

func test_pending_survives_toggle_off_and_resumes() -> void:
	# 跳跃开关关闭 → 计时器与挂起一并冻结（挂起保留）；重开后挂起继续（ADR-0028）。
	var bot := bot_at(Vector2(0.0, -120.0))
	var p := jump_perception(0.05, 0.05)
	var elapsed := 0.0
	while elapsed < 0.2 and not bot._jump_pending:
		bot.update(0.01, p)
		elapsed += 0.01
	assert_true(bot._jump_pending, "前置：挂起中")
	var frozen := bot._jump_wait
	p.jump_enabled = false
	for i in 5:
		bot.update(0.01, p)
	assert_true(bot._jump_pending, "开关关闭：挂起保留（冻结）")
	assert_eq(bot._jump_wait, frozen, "开关关闭：计时器冻结")
	p.jump_enabled = true
	bot.update(0.01, p)
	assert_true(bot._jump_pending, "重开后挂起继续")

func test_ras_dice_do_not_disturb_fire_sequence() -> void:
	# P=1（每轮到点都掷 RAS 骰）开火序列仍与无跳跃 bot 逐发一致：RAS 骰走跳跃独立源。
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
	pb.jump_ras_prob = 1.0
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
	assert_false(mismatch, "命中/失手序列逐发一致（RAS 骰不污染开火序列）")

# ---- bot 空中机动（票 12 / ADR-0024、ADR-0027）----

## 玩家每帧跟随 bot 正前方 dist 处：锁定面朝 yaw = π（侧向轴恒 ±x）、距离恒定。
func follow_player(p: BotAi.Perception, bot: BotAi, dist := 120.0) -> void:
	var pos := bot.sim.position()
	p.player_x = pos.x
	p.player_z = pos.y + dist

func test_half_second_interval_chains_bhop() -> void:
	# 0.5s 间隔 < 滞空 0.724s：空中到点锁存、落地帧立即起跳——空中区间至少两跳连贯（≥1.4s）。
	# 旧「作废」语义下最长区间只有单跳 ≈0.73s，地面间隙 2I − 滞空 恒存（用户实测的「站稳才跳」）。
	var bot := bot_at(Vector2(0.0, -120.0))
	var p := jump_perception(0.5, 0.5)
	var stretch := 0.0
	var cur := 0.0
	var elapsed := 0.0
	while elapsed < 3.0:
		bot.update(0.01, p)
		if bot.sim.airborne():
			cur += 0.01
			stretch = maxf(stretch, cur)
		else:
			cur = 0.0
		elapsed += 0.01
	assert_gt(stretch, 1.4, "锁存 bhop：空中区间至少两跳连贯")

func test_air_cuts_forward_input() -> void:
	# 游走必掷前压（W）：地面阶段斜前移动；起跳后空中 fwd 强制归零——
	# 0.35s 内速度被 6 rad/s 空中转向转回纯侧向（朝向锁死），朝玩家分量衰减到 0。
	# 旧语义空中照喂 W：wish 保持斜前，朝玩家分量不减。
	var cfg := config()
	cfg.wander = 1.0
	cfg.aggression = 1.0
	cfg.retreat = 0.0
	var bot := bot_at(Vector2(0.0, -120.0), Callable(), cfg)
	var p := perception()
	p.wander_mode = true
	p.range_amp = 25.0
	p.jump_enabled = true
	p.jump_min = 0.1
	p.jump_max = 0.1
	bot.avoidance.dir = AvoidanceController.DIR_RIGHT
	bot.avoidance.flip_timer = 999.0
	bot.avoidance.switch_timer = 999.0
	var vz_takeoff := 0.0
	var vz_late := 0.0
	var elapsed := 0.0
	while elapsed < 0.5:
		follow_player(p, bot)
		bot.update(0.01, p)
		if bot.sim.airborne() and vz_takeoff == 0.0:
			vz_takeoff = bot.sim.velocity().y
		if elapsed >= 0.45:
			vz_late = bot.sim.velocity().y
		elapsed += 0.01
	assert_gt(absf(vz_takeoff), 60.0, "前置：起跳时带着明显的朝玩家分量（W 生效）")
	assert_lt(absf(vz_late), 20.0, "空中前后输入归零：朝玩家分量被转回纯侧向")

func test_air_flip_pinned_at_half_ascent() -> void:
	# 升程内到点的自然变向钉到升程一半执行（ADR-0027）：到点帧（t≈0.35）只作废不翻向，
	# 钉点（起跳≈0.30 + 0.18 ≈ 0.48，早于 apex≈0.66）才翻向并立刻切换输入——
	# 剩余滞空 0.54s × 6 rad/s 足以转满 180°，落地前完成反向。
	var bot := bot_at(Vector2(0.0, -120.0))
	var p := jump_perception(0.3, 0.3)
	bot.avoidance.dir = AvoidanceController.DIR_LEFT
	bot.avoidance.flip_timer = 0.35 # flip_timer 自 spawn 起倒数：t≈0.35 到点（起跳 t≈0.30 后）
	bot.avoidance.switch_timer = 999.0
	var flip_at := -1.0
	var dir_at_due := 0
	var vx_late := 0.0
	var elapsed := 0.0
	while elapsed < 1.05:
		follow_player(p, bot)
		bot.update(0.01, p)
		if flip_at < 0.0 and bot.avoidance.dir == AvoidanceController.DIR_RIGHT:
			flip_at = elapsed
		if elapsed >= 0.42 and elapsed < 0.43:
			dir_at_due = bot.avoidance.dir
		if elapsed >= 0.80 and elapsed < 0.81:
			vx_late = bot.sim.velocity().x
		elapsed += 0.01
	assert_eq(dir_at_due, AvoidanceController.DIR_LEFT, "到点帧只作废：变向内容不在到点生效")
	assert_gt(flip_at, 0.44, "钉点在升程一半（起跳≈0.30 + 0.18），不在到点帧（≈0.35）")
	assert_lt(flip_at, 0.62, "钉点早于 apex（≈0.66）")
	assert_lt(vx_late, 0.0, "钉点后 0.32s 速度已越过 90° 反向（旧 apex 规则此刻仍朝起跳方向）")

func test_air_flip_descending_due_also_pinned() -> void:
	# 下降期到点不再丢弃（ADR-0027）：只要起跳沿预读命中（剩余 ≤ 滞空时长），下降期原定的
	# 到点同样钉到升程一半执行——到点帧（t≈0.80）不翻、钉点（≈0.48）翻；计时器不动，
	# 原定到点在空中走「作废重抽」。
	var bot := bot_at(Vector2(0.0, -120.0))
	var p := jump_perception(0.3, 0.3)
	bot.avoidance.dir = AvoidanceController.DIR_LEFT
	bot.avoidance.flip_timer = 0.8 # t≈0.80 到点：旧规则属下降期（apex≈0.66、落地≈1.02 之间）
	bot.avoidance.switch_timer = 999.0
	var flip_at := -1.0
	var timer_after_pin := -1.0
	var timer_after_reroll := -1.0
	var prev_timer := 999.0
	var vx_late := 0.0
	var elapsed := 0.0
	while elapsed < 1.05:
		follow_player(p, bot)
		bot.update(0.01, p)
		if flip_at < 0.0 and bot.avoidance.dir == AvoidanceController.DIR_RIGHT:
			flip_at = elapsed
		elif flip_at >= 0.0 and timer_after_pin < 0.0:
			timer_after_pin = bot.avoidance.flip_timer # 钉点后第一帧的计时器读数
		if prev_timer <= 0.02 and bot.avoidance.flip_timer > 0.1 and timer_after_reroll < 0.0:
			timer_after_reroll = bot.avoidance.flip_timer # 到点作废后的重抽值
		prev_timer = bot.avoidance.flip_timer
		if elapsed >= 1.0:
			vx_late = bot.sim.velocity().x
		elapsed += 0.01
	assert_gt(flip_at, 0.44, "下降期原定的到点提前到升程一半（≈0.48）执行")
	assert_lt(flip_at, 0.62, "早于 apex（≈0.66）")
	# 钉点后第一帧读数 = 原定到点(0.8) − 实际钉点时刻 − 两帧 dt（钉点帧与捕获帧各减一次）：
	# 精确等式证明「不动也不重抽」——重抽值只会落在模式区间 [0.2, 1.0]，与读数无关。
	assert_almost_eq(timer_after_pin, 0.8 - flip_at, 0.021, "钉点不动计时器：仍朝原定到点（0.8s）倒数")
	var range_lo: float = AvoidanceController.STRAFE_MIN[bot.avoidance.mode]
	var range_hi: float = AvoidanceController.STRAFE_MAX[bot.avoidance.mode]
	assert_gte(timer_after_reroll, range_lo - 0.011, "原定到点在空中作废，间隔照常重抽")
	assert_lte(timer_after_reroll, range_hi + 0.011, "重抽落在当前模式区间")
	assert_eq(bot.avoidance.dir, AvoidanceController.DIR_RIGHT, "到点作废不翻回：方向保持钉点那一次")
	assert_lt(vx_late, 0.0, "整跳反向完成")

func test_air_flip_second_due_discarded() -> void:
	# 钉点执行后同一滞空内再到的点作废（一次滞空一次，ADR-0027）：第二次到点不翻向、
	# 间隔照常重抽，方向保持钉点应用的那一次。
	var bot := bot_at(Vector2(0.0, -120.0))
	var p := jump_perception(0.3, 0.3)
	bot.avoidance.dir = AvoidanceController.DIR_LEFT
	bot.avoidance.flip_timer = 0.35 # 第一次到点 t≈0.35（升程内）→ 作废；钉点 t≈0.48 → RIGHT
	bot.avoidance.switch_timer = 999.0
	var pinned_seen := false
	var rerolled := -1.0
	var prev_timer := 999.0
	var vx_late := 0.0
	var elapsed := 0.0
	while elapsed < 1.05:
		follow_player(p, bot)
		bot.update(0.01, p)
		if not pinned_seen and bot.avoidance.dir == AvoidanceController.DIR_RIGHT:
			pinned_seen = true
			bot.avoidance.flip_timer = 0.05 # 压第二次到点 t≈0.53，仍在空中（<1.02）
		elif pinned_seen and rerolled < 0.0 and prev_timer <= 0.02 and bot.avoidance.flip_timer > 0.1:
			rerolled = bot.avoidance.flip_timer # 第二次到点的作废重抽
		prev_timer = bot.avoidance.flip_timer
		if elapsed >= 1.0:
			vx_late = bot.sim.velocity().x
		elapsed += 0.01
	assert_true(pinned_seen, "前置：钉点已翻向")
	assert_gt(rerolled, 0.0, "前置：第二次到点已发生（作废重抽）")
	var range_lo: float = AvoidanceController.STRAFE_MIN[bot.avoidance.mode]
	var range_hi: float = AvoidanceController.STRAFE_MAX[bot.avoidance.mode]
	assert_gte(rerolled, range_lo - 0.011, "作废照常重抽")
	assert_lte(rerolled, range_hi + 0.011, "重抽落在当前模式区间")
	assert_eq(bot.avoidance.dir, AvoidanceController.DIR_RIGHT, "一次滞空一次：不再翻回")
	assert_lt(vx_late, 0.0, "钉点方向保持到落地")

func test_air_flip_not_armed_when_due_beyond_air() -> void:
	# 起跳沿预读未命中（剩余 > 滞空时长）：空中无变向——整跳方向稳定，到点落在地面照常。
	var bot := bot_at(Vector2(0.0, -120.0))
	var p := jump_perception(0.3, 0.3)
	bot.avoidance.dir = AvoidanceController.DIR_LEFT
	bot.avoidance.flip_timer = 3.0 # 起跳（t≈0.30）时剩余 ≈2.7 > 0.724 → 不预约
	bot.avoidance.switch_timer = 999.0
	var vx_late := 0.0
	var elapsed := 0.0
	while elapsed < 1.05:
		follow_player(p, bot)
		bot.update(0.01, p)
		if elapsed >= 1.0:
			vx_late = bot.sim.velocity().x
		elapsed += 0.01
	assert_eq(bot.avoidance.dir, AvoidanceController.DIR_LEFT, "预读未命中：空中无变向")
	assert_gt(vx_late, 150.0, "整跳方向稳定：速度保持起跳方向")

func test_air_block_flip_immediate_mid_air() -> void:
	# 防撞翻向（on_blocked）不受钉点管制：上升期翻向当帧生效——空中侧向直读
	# avoidance.dir，不被预约/钉点机制滞留（守恒测试：现实现即绿）。
	var bot := bot_at(Vector2(0.0, -120.0))
	var p := jump_perception(0.3, 0.3)
	bot.avoidance.dir = AvoidanceController.DIR_LEFT
	bot.avoidance.flip_timer = 999.0
	bot.avoidance.switch_timer = 999.0
	var elapsed := 0.0
	var flipped := false
	var vx_after := 0.0
	while elapsed < 0.6:
		follow_player(p, bot)
		bot.update(0.01, p)
		if not flipped and bot.sim.airborne() and elapsed > 0.35:
			assert_true(bot.on_blocked(2.9, 0.0), "上升期物理受阻 → 立即翻向")
			flipped = true
		if flipped:
			vx_after = bot.sim.velocity().x
		elapsed += 0.01
	assert_true(flipped, "前置：空中已完成翻向注入")
	assert_lt(vx_after, 100.0, "翻向当帧起速度转向新方向（不被快照滞留）")

func test_air_dodge_flip_immediate_mid_air() -> void:
	# 受击躲避不受钉点管制：上升期躲避翻向当帧生效（空中侧向直读 avoidance.dir，
	# 守恒测试：现实现即绿）。
	var bot := bot_at(Vector2(0.0, -120.0))
	var p := jump_perception(0.3, 0.3)
	p.dodge_chance = 1.0
	bot.avoidance.dir = AvoidanceController.DIR_LEFT
	bot.avoidance.flip_timer = 999.0
	bot.avoidance.switch_timer = 999.0
	var elapsed := 0.0
	var flipped := false
	var vx_after := 0.0
	while elapsed < 0.6:
		follow_player(p, bot)
		bot.update(0.01, p)
		if not flipped and bot.sim.airborne() and elapsed > 0.35:
			assert_false(bot.take_damage(25, p), "非致命受击")
			flipped = true
		if flipped:
			vx_after = bot.sim.velocity().x
		elapsed += 0.01
	assert_ne(bot.avoidance.dir, AvoidanceController.DIR_LEFT, "躲避翻向已发生")
	assert_lt(vx_after, 100.0, "躲避翻向当帧起生效（不被快照滞留）")
