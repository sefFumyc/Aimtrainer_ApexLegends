## 武器节奏与开火缓冲的行为测试。
##
## 只断言外部行为：给定「按下 / 按住 / 推进 dt」的序列，断言开火次数与时机。
## 不测视觉与音频。

extends GutTest

# ---- 武器数据表 ----

func test_rifle_stats() -> void:
	assert_almost_eq(Weapon.interval(Weapon.RIFLE), 0.1, 1e-9, "步枪 10 发/秒")
	assert_eq(Weapon.body_damage(Weapon.RIFLE), 25)
	assert_eq(Weapon.headshot_damage(Weapon.RIFLE), 35)
	assert_true(Weapon.automatic(Weapon.RIFLE), "步枪按住连射")

func test_pistol_stats() -> void:
	assert_almost_eq(Weapon.interval(Weapon.PISTOL), 1.0 / 3.0, 1e-9, "手枪最快 3 发/秒")
	assert_eq(Weapon.body_damage(Weapon.PISTOL), 70)
	assert_eq(Weapon.headshot_damage(Weapon.PISTOL), 110)
	assert_false(Weapon.automatic(Weapon.PISTOL), "手枪单发")

## 注意：CONTEXT.md「爆头」词条写的是「×2 伤害」，但实测数据是步枪 25→35（1.4×）、
## 手枪 70→110（≈1.571×）——参考实现里 35 是从 50（=2×25）再平衡后的值，
## 词条的「×2」是那次再平衡之前的残留。以代码与票面的具体数值为准，此处不加断言。
func test_headshot_damage_is_higher_than_body() -> void:
	assert_gt(Weapon.headshot_damage(Weapon.RIFLE), Weapon.body_damage(Weapon.RIFLE))
	assert_gt(Weapon.headshot_damage(Weapon.PISTOL), Weapon.body_damage(Weapon.PISTOL))

func test_next_weapon_cycles_three() -> void:
	assert_eq(Weapon.next(Weapon.RIFLE), Weapon.PISTOL)
	assert_eq(Weapon.next(Weapon.PISTOL), Weapon.BURST)
	assert_eq(Weapon.next(Weapon.BURST), Weapon.RIFLE)

# ---- 步枪连射 ----

func test_rifle_press_fires_immediately() -> void:
	var w := Weapon.new(Weapon.RIFLE)
	assert_true(w.press(), "按下边沿立即开火")

func test_rifle_held_fires_at_ten_per_second() -> void:
	# 用整间隔推进，避开浮点累积在 0 边界上的 ±1 抖动
	var w := Weapon.new(Weapon.RIFLE)
	w.press() # 第 1 发
	var count := 1
	for i in range(10): # 10 × 0.1s = 1.0s
		count += w.advance(Weapon.RIFLE_INTERVAL, true)
	assert_eq(count, 11, "1 秒含首发共 11 发（10 发/秒）")

func test_rifle_not_held_does_not_fire() -> void:
	var w := Weapon.new(Weapon.RIFLE)
	w.press()
	var count := 1
	for i in range(100):
		count += w.advance(0.01, false)
	assert_eq(count, 1, "松开后不再连射")

func test_rifle_large_dt_catches_up_without_losing_time() -> void:
	# 累加器语义：一帧 dt=0.25 应补足 2 发（0.1 / 0.2 两个到点），不丢时间
	var w := Weapon.new(Weapon.RIFLE)
	w.press()
	assert_eq(w.advance(0.25, true), 2, "0.25s 内到点的 2 发在下一帧补齐")

# ---- 手枪单发与缓冲 ----

func test_pistol_click_fires_immediately_then_gated() -> void:
	var w := Weapon.new(Weapon.PISTOL)
	assert_true(w.press(), "首次点击立即开火")
	assert_false(w.press(), "冷却中再点不开火")
	assert_eq(w.advance(0.1, true), 0, "冷却未满不补发")

func test_pistol_buffers_one_click_during_cooldown() -> void:
	var w := Weapon.new(Weapon.PISTOL)
	w.press() # 开火，进入冷却
	w.press() # 冷却中：缓冲一发
	assert_eq(w.advance(0.34, true), 1, "冷却结束补发缓冲的那一发")
	assert_eq(w.advance(0.34, true), 0, "补发后无残留")

func test_pistol_absorbs_extra_clicks() -> void:
	var w := Weapon.new(Weapon.PISTOL)
	w.press() # 开火
	w.press() # 缓冲
	w.press() # 被吸收
	w.press() # 被吸收
	assert_eq(w.advance(0.34, true), 1, "多余点击被吸收，只补发一发")

func test_pistol_release_then_cooldown_still_buffers() -> void:
	var w := Weapon.new(Weapon.PISTOL)
	w.press()
	w.press() # 缓冲
	assert_eq(w.advance(0.34, false), 1, "松开按键后冷却照走，缓冲仍会补发")

func test_pistol_no_buffer_no_fire() -> void:
	var w := Weapon.new(Weapon.PISTOL)
	w.press()
	assert_eq(w.advance(1.0, false), 0, "没缓冲就不补发")

func test_burst_stats() -> void:
	assert_almost_eq(Weapon.interval(Weapon.BURST), 0.05, 1e-9, "组内弹间隔 50ms")
	assert_eq(Weapon.body_damage(Weapon.BURST), 20)
	assert_eq(Weapon.headshot_damage(Weapon.BURST), 30)
	assert_false(Weapon.automatic(Weapon.BURST), "冲锋枪是点击边沿武器（点一组）")
	assert_true(Weapon.is_auto_tier(Weapon.BURST), "躲避/收敛归连发压迫档")
	assert_almost_eq(Weapon.sound_pitch(Weapon.BURST), 1.15, 1e-9, "冲锋枪音高 ×1.15")

## 每步推 0.01s（近似连续时间），累计开火次数。
func _run(w: Weapon, steps: int, held: bool) -> int:
	var total := 0
	for i in steps:
		total += w.advance(0.01, held)
	return total

# ---- 冲锋枪整组连发（ADR-0026）----

func test_burst_click_fires_group_of_five() -> void:
	var w := Weapon.new(Weapon.BURST)
	assert_true(w.press(), "点击立即开组（首发当场响）")
	assert_eq(_run(w, 25, false), 4, "组内余 4 发在 0.25s 内按 50ms 间隔跟进，组完不再有")
	assert_eq(_run(w, 25, false), 0, "无缓冲不续组")

func test_burst_group_window_opens_430ms_from_group_start() -> void:
	var w := Weapon.new(Weapon.BURST)
	w.press() # t=0 组1
	assert_eq(_run(w, 42, true), 4, "t=0.42 组1 余 4 发全出，窗口未到")
	assert_eq(_run(w, 1, true), 1, "t=0.43 窗口开：按住即连组2 首发（组首起算 430ms）")

func test_burst_click_during_cooldown_buffers_whole_group() -> void:
	var w := Weapon.new(Weapon.BURST)
	w.press() # 组1
	w.press() # 组中点击 → 缓冲一整组
	assert_eq(_run(w, 63, false), 9, "松键：组1 余 4 发打完，t=0.43 窗口补缓冲组，至 t=0.63 共 9 发")
	assert_eq(_run(w, 50, false), 0, "缓冲组打完无残留")

func test_burst_absorbs_extra_clicks_per_window() -> void:
	var w := Weapon.new(Weapon.BURST)
	w.press()
	w.press() # 缓冲
	w.press() # 被吸收
	w.press() # 被吸收
	assert_eq(_run(w, 63, false), 9, "同一窗口多次点击只缓冲一组")

func test_burst_release_mid_group_does_not_interrupt() -> void:
	var w := Weapon.new(Weapon.BURST)
	w.press()
	# 按住 2 帧后松开，组仍打完（fire-and-forget）
	assert_eq(w.advance(0.01, true), 0)
	assert_eq(_run(w, 40, false), 4, "松键不打断整组")

func test_burst_hold_fires_continuous_groups() -> void:
	var w := Weapon.new(Weapon.BURST)
	var total := 1 if w.press() else 0 # t=0 组1 首发
	total += _run(w, 100, true) # t=0..1.0
	assert_eq(total, 13, "1 秒按住：组1(5) + 组2@0.43(5) + 组3@0.86 前 3 发 = 13")

func test_burst_reset_drops_group_and_buffer() -> void:
	var w := Weapon.new(Weapon.BURST)
	w.press() # 组1
	w.press() # 缓冲
	w.advance(0.1, false) # 组1 推进（打出 2 发，余 2 发连同缓冲被切换武器丢弃）
	w.reset() # 切换武器
	assert_eq(_run(w, 50, false), 0, "缓冲已丢弃")
	assert_true(w.press(), "切换武器后立即开新组")
	assert_eq(_run(w, 25, true), 4, "新组余 4 发照常打完")

func test_switch_weapon_discards_buffer_and_resets_cooldown() -> void:
	var w := Weapon.new(Weapon.PISTOL)
	w.press() # 开火
	w.press() # 缓冲
	w.reset() # 切换武器
	assert_true(w.press(), "切换武器后下一发立即就绪（冷却清零）")
	# 缓冲已丢弃：再等一个间隔回来也不该有额外补发
	var extra := 0
	for i in range(10):
		extra += w.advance(0.1, false)
	assert_eq(extra, 0, "切换武器丢弃缓冲")