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
## 手枪 70→110（≈1.571×）——参考实现里 35 是 ADR-0026 从 50（=2×25）再平衡后的值，
## 词条的「×2」是那次再平衡之前的残留。以代码与票面的具体数值为准，此处不加断言。
func test_headshot_damage_is_higher_than_body() -> void:
	assert_gt(Weapon.headshot_damage(Weapon.RIFLE), Weapon.body_damage(Weapon.RIFLE))
	assert_gt(Weapon.headshot_damage(Weapon.PISTOL), Weapon.body_damage(Weapon.PISTOL))

func test_other_weapon_toggles() -> void:
	assert_eq(Weapon.other(Weapon.RIFLE), Weapon.PISTOL)
	assert_eq(Weapon.other(Weapon.PISTOL), Weapon.RIFLE)

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

func test_switch_weapon_discards_buffer_and_resets_cooldown() -> void:
	var w := Weapon.new(Weapon.PISTOL)
	w.press() # 开火
	w.press() # 缓冲
	w.reset() # 切枪
	assert_true(w.press(), "切枪后下一发立即就绪（冷却清零）")
	# 缓冲已丢弃：再等一个间隔回来也不该有额外补发
	var extra := 0
	for i in range(10):
		extra += w.advance(0.1, false)
	assert_eq(extra, 0, "切枪丢弃缓冲")