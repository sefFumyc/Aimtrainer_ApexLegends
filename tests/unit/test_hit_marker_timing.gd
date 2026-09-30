## 击中提示时序状态机的行为测试（CONTEXT.md「击中提示」）。
##
## 断言的是「kind + phase + 剩余时间」这组外部状态，不碰渲染。

extends GutTest

func test_hit_hold_then_fade_then_idle() -> void:
	var hm := HitMarkerTiming.new()
	assert_true(hm.is_idle(), "初始 idle")
	hm.event(HitMarkerTiming.KIND_HIT)
	assert_eq(hm.kind, HitMarkerTiming.KIND_HIT)
	assert_eq(hm.phase, HitMarkerTiming.PHASE_HOLD)
	assert_almost_eq(hm.remaining_ms, HitMarkerTiming.HIT_HOLD_MS, 1e-9, "命中保持 250ms")
	hm.tick(250.0)
	assert_eq(hm.phase, HitMarkerTiming.PHASE_FADE, "保持到期转淡出")
	assert_almost_eq(hm.remaining_ms, HitMarkerTiming.HIT_FADE_MS, 1e-9, "命中淡出 60ms")
	hm.tick(60.0)
	assert_true(hm.is_idle(), "淡出播完归 idle")

func test_kill_hold_then_fade() -> void:
	var hm := HitMarkerTiming.new()
	hm.event(HitMarkerTiming.KIND_KILL)
	assert_almost_eq(hm.remaining_ms, HitMarkerTiming.KILL_HOLD_MS, 1e-9, "击杀保持 480ms")
	hm.tick(480.0)
	assert_eq(hm.phase, HitMarkerTiming.PHASE_FADE)
	assert_almost_eq(hm.remaining_ms, HitMarkerTiming.KILL_FADE_MS, 1e-9, "击杀淡出 80ms")

func test_idle_does_not_tick() -> void:
	var hm := HitMarkerTiming.new()
	hm.tick(1000.0)
	assert_true(hm.is_idle())
	assert_almost_eq(hm.remaining_ms, 0.0, 1e-9)

func test_repeated_hits_restart_full_hold() -> void:
	var hm := HitMarkerTiming.new()
	hm.event(HitMarkerTiming.KIND_HIT)
	hm.tick(200.0)
	hm.event(HitMarkerTiming.KIND_HIT)
	assert_almost_eq(hm.remaining_ms, HitMarkerTiming.HIT_HOLD_MS, 1e-9, "保持期内再命中重置回完整保持")
	hm.tick(250.0) # 进入淡出
	hm.event(HitMarkerTiming.KIND_HIT)
	assert_eq(hm.phase, HitMarkerTiming.PHASE_HOLD, "淡出期内再命中回到保持")
	assert_almost_eq(hm.remaining_ms, HitMarkerTiming.HIT_HOLD_MS, 1e-9)

func test_hit_is_ignored_while_kill_shown() -> void:
	var hm := HitMarkerTiming.new()
	hm.event(HitMarkerTiming.KIND_KILL)
	hm.tick(100.0)
	hm.event(HitMarkerTiming.KIND_HIT)
	assert_eq(hm.kind, HitMarkerTiming.KIND_KILL, "击杀优先：保持期白命中被忽略")
	assert_almost_eq(hm.remaining_ms, HitMarkerTiming.KILL_HOLD_MS - 100.0, 1e-9, "被忽略的命中不重置计时")
	hm.tick(480.0) # 进入击杀淡出
	hm.event(HitMarkerTiming.KIND_HIT)
	assert_eq(hm.kind, HitMarkerTiming.KIND_KILL, "击杀淡出期白命中同样被忽略")
	assert_eq(hm.phase, HitMarkerTiming.PHASE_FADE)

func test_kill_cuts_in_from_hit_and_restarts() -> void:
	var hm := HitMarkerTiming.new()
	hm.event(HitMarkerTiming.KIND_HIT)
	hm.tick(100.0)
	hm.event(HitMarkerTiming.KIND_KILL)
	assert_eq(hm.kind, HitMarkerTiming.KIND_KILL, "白 X 展示期来击杀即切红")
	assert_eq(hm.phase, HitMarkerTiming.PHASE_HOLD)
	assert_almost_eq(hm.remaining_ms, HitMarkerTiming.KILL_HOLD_MS, 1e-9, "从完整保持重计时")

func test_repeated_kills_restart_hold() -> void:
	var hm := HitMarkerTiming.new()
	hm.event(HitMarkerTiming.KIND_KILL)
	hm.tick(300.0)
	hm.event(HitMarkerTiming.KIND_KILL)
	assert_almost_eq(hm.remaining_ms, HitMarkerTiming.KILL_HOLD_MS, 1e-9)