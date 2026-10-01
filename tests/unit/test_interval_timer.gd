## 间隔计时器阶段机的行为测试（spec `## Testing Decisions` 第 4 项）。
##
## 断言的是「事件序列 + 相位 + 剩余秒数」这组外部可观测输出，不碰内部字段。

extends GutTest

func test_prepare_play_rest_then_final_without_tail_rest() -> void:
	var t := IntervalTimer.new()
	t.start(2.0, 1.0, 2) # 游玩 2s、休息 1s、重复 2 次
	assert_eq(t.phase, IntervalTimer.Phase.PREPARE)
	assert_almost_eq(t.remaining, 5.0, 1e-9, "准备段固定 5 秒")

	assert_eq(t.tick(5.0).type, IntervalTimer.Event.PREPARE_END)
	assert_eq(t.phase, IntervalTimer.Phase.PLAY)
	assert_eq(t.round, 0, "准备段结束还没完成任何游玩段")

	var ev := t.tick(2.0)
	assert_eq(ev.type, IntervalTimer.Event.PLAY_END)
	assert_false(ev.last, "非末段进入休息段")
	assert_eq(t.round, 1)
	assert_eq(t.phase, IntervalTimer.Phase.REST)

	assert_eq(t.tick(1.0).type, IntervalTimer.Event.REST_END)
	assert_eq(t.phase, IntervalTimer.Phase.PLAY)

	ev = t.tick(2.0)
	assert_eq(ev.type, IntervalTimer.Event.PLAY_END)
	assert_true(ev.last, "末段直接结算")
	assert_eq(t.round, 2)
	assert_eq(t.phase, IntervalTimer.Phase.OFF, "无尾休息：末段结束即空闲")
	assert_almost_eq(t.remaining, 0.0, 1e-9)
	assert_eq(t.tick(1.0).type, IntervalTimer.Event.NONE, "结束后不再产生事件")

func test_rest_cannot_be_skipped() -> void:
	var t := IntervalTimer.new()
	t.start(1.0, 3.0, 2)
	t.tick(5.0) # 准备段走满 → prepare-end
	t.tick(1.0) # play-end → 休息段
	assert_eq(t.phase, IntervalTimer.Phase.REST)

	# 休息段没有任何跳过入口：不足满额的推进一律留在休息段
	assert_eq(t.tick(1.0).type, IntervalTimer.Event.SECOND)
	assert_eq(t.phase, IntervalTimer.Phase.REST)
	assert_eq(t.tick(1.5).type, IntervalTimer.Event.SECOND)
	assert_eq(t.phase, IntervalTimer.Phase.REST)
	assert_eq(t.tick(0.5).type, IntervalTimer.Event.REST_END, "休息段只有走满才结束")
	assert_eq(t.phase, IntervalTimer.Phase.PLAY)

func test_second_boundary_events_in_prepare() -> void:
	var t := IntervalTimer.new()
	t.start(60.0, 20.0, 4)
	for expected in [4, 3, 2, 1]:
		var ev := t.tick(1.0)
		assert_eq(ev.type, IntervalTimer.Event.SECOND)
		assert_eq(ev.remaining, expected, "整秒边界按 ceil(remaining) 报数")
	assert_eq(t.tick(1.0).type, IntervalTimer.Event.PREPARE_END, "第 5 秒是相位切换而不是 second")

func test_cancel_returns_to_off() -> void:
	var t := IntervalTimer.new()
	t.start(60.0, 20.0, 4)
	t.cancel()
	assert_eq(t.phase, IntervalTimer.Phase.OFF)
	assert_almost_eq(t.remaining, 0.0, 1e-9)
	assert_eq(t.tick(999.0).type, IntervalTimer.Event.NONE)

func test_start_clamps_and_resets_session_totals() -> void:
	var t := IntervalTimer.new()
	t.start(60.0, 20.0, 4)
	var stats := IntervalTimer.RoundStats.new()
	stats.kills = 5
	stats.shots = 10
	stats.hits = 7
	t.accumulate(stats)
	assert_eq(t.total_kills, 5)

	t.start(0.0, 0.0, 0) # 下界钳制到 1/1/1；累计清零
	assert_eq(t.play_seconds, 1)
	assert_eq(t.rest_seconds, 1)
	assert_eq(t.repeat, 1)
	assert_eq(t.round, 0)
	assert_eq(t.total_kills, 0)
	assert_eq(t.total_shots, 0)
	assert_almost_eq(t.total_accuracy(), -1.0, 1e-9, "清零后无数据")

func test_session_totals_and_accuracy() -> void:
	var t := IntervalTimer.new()
	t.start(60.0, 20.0, 4)
	assert_almost_eq(t.total_accuracy(), -1.0, 1e-9, "尚未积累射弹时无数据")
	var a := IntervalTimer.RoundStats.new()
	a.kills = 2
	a.shots = 4
	a.hits = 3
	a.deaths = 1
	a.seconds = 60.0
	t.accumulate(a)
	var b := IntervalTimer.RoundStats.new()
	b.shots = 6
	b.hits = 1
	b.seconds = 60.0
	t.accumulate(b)
	assert_eq(t.total_kills, 2)
	assert_eq(t.total_deaths, 1)
	assert_eq(t.total_shots, 10)
	assert_eq(t.total_hits, 4)
	assert_almost_eq(t.total_play_seconds, 120.0, 1e-9)
	assert_almost_eq(t.total_accuracy(), 40.0, 1e-9, "会话累计准确率 = 累计命中/累计射击")