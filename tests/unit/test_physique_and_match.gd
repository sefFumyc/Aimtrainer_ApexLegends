## 体型与对局统计的纯逻辑测试。

extends GutTest

func test_physique_geometry() -> void:
	assert_almost_eq(Physique.TOTAL_HEIGHT, 72.0, 1e-9, "总高 72")
	assert_almost_eq(Physique.BODY_HEIGHT, 60.0, 1e-9, "身体圆柱高 60")
	assert_almost_eq(Physique.BODY_RADIUS * 2.0, 16.0, 1e-9, "身体直径 16")
	assert_almost_eq(Physique.HEAD_RADIUS, 6.0, 1e-9, "头球半径 6")
	assert_almost_eq(Physique.HEAD_CENTER_Y, 66.0, 1e-9, "头心高度 66")
	assert_almost_eq(Physique.EYE_HEIGHT, 66.0, 1e-9, "玩家视线高度与 bot 头心平齐")

func test_body_radius_scales_horizontally_only() -> void:
	assert_almost_eq(Physique.horizontal_scale(Physique.BODY_RADIUS_DEFAULT), 1.0, 1e-9, "默认体型不缩放")
	assert_almost_eq(Physique.horizontal_scale(16.0), 2.0, 1e-9, "半径翻倍 → 水平 ×2")
	assert_almost_eq(Physique.horizontal_scale(4.0), 0.5, 1e-9)
	# 身高与头心高度是常量，不随半径变化（瞄准高度不变）
	assert_almost_eq(Physique.HEAD_CENTER_Y, 66.0, 1e-9)
	assert_almost_eq(Physique.BODY_HEIGHT, 60.0, 1e-9)

func test_match_starts_full_and_resets() -> void:
	var m := DuelMatch.new()
	assert_eq(m.player_hp, 600)
	assert_eq(m.bot_hp, 600)
	m.player_hp = 100
	m.kills = 3
	m.reset()
	assert_eq(m.player_hp, 600)
	assert_eq(m.kills, 0)
	assert_eq(m.shots, 0)
	assert_eq(m.hits, 0)
	assert_eq(m.deaths, 0)

func test_accuracy_counts_hits_over_shots() -> void:
	var m := DuelMatch.new()
	assert_almost_eq(m.accuracy(), -1.0, 1e-9, "尚无射弹时无数据")
	m.record_shot(true)
	m.record_shot(false)
	m.record_shot(true)
	m.record_shot(false)
	assert_eq(m.shots, 4)
	assert_eq(m.hits, 2)
	assert_almost_eq(m.accuracy(), 50.0, 1e-9)

func test_heal_caps_at_max_hp() -> void:
	var m := DuelMatch.new()
	m.player_hp = 590
	m.heal_player(70)
	assert_eq(m.player_hp, 600, "回血封顶 600 不溢出")
	m.bot_hp = 100
	m.heal_bot(25)
	assert_eq(m.bot_hp, 125)

func test_stick_8way_discretization() -> void:
	var none := StickMove.from_axes(0.05, -0.05)
	assert_eq(none.right, 0.0, "死区内静止")
	assert_eq(none.fwd, 0.0)
	assert_false(none.sprint)

	var pure_fwd := StickMove.from_axes(0.0, -1.0)
	assert_eq(pure_fwd.right, 0.0)
	assert_eq(pure_fwd.fwd, 1.0, "Y 上负 → 前为正")
	assert_true(pure_fwd.sprint, "前推满幅自动疾跑")

	var diagonal := StickMove.from_axes(0.9, -0.9)
	assert_eq(diagonal.right, 1.0, "每轴独立阈值判向，幅度只做二值化")
	assert_eq(diagonal.fwd, 1.0)

	var back := StickMove.from_axes(0.0, 1.0)
	assert_eq(back.fwd, -1.0)
	assert_false(back.sprint, "后退不自动疾跑")

	var slow_fwd := StickMove.from_axes(0.0, -0.3)
	assert_eq(slow_fwd.fwd, 1.0)
	assert_false(slow_fwd.sprint, "幅度未达阈值不自动疾跑")