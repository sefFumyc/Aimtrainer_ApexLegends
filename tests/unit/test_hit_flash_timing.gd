## 受击红屏时序的行为测试（CONTEXT.md「受击红屏」/ ADR-0019）。
##
## 断言的是「剩余时长 → alpha 比例」这条外部行为，不碰渲染。

extends GutTest

func test_flash_peaks_then_fades_linearly_to_idle() -> void:
	var hf := HitFlashTiming.new()
	assert_true(hf.is_idle(), "初始 idle")
	assert_almost_eq(hf.tick(0.016), 0.0, 1e-9, "idle 时 alpha 恒 0")
	hf.flash()
	assert_almost_eq(hf.tick(0.0), 1.0, 1e-9, "受击瞬间从峰值起步")
	assert_almost_eq(hf.tick(HitFlashTiming.FADE_TIME_S * 0.5), 0.5, 1e-6, "半程 alpha 减半（线性渐隐）")
	assert_almost_eq(hf.tick(HitFlashTiming.FADE_TIME_S), 0.0, 1e-9, "满时长后完全消隐")
	assert_true(hf.is_idle(), "渐隐播完归 idle")

func test_repeated_hits_refresh_from_peak() -> void:
	var hf := HitFlashTiming.new()
	hf.flash()
	hf.tick(HitFlashTiming.FADE_TIME_S * 0.75)
	hf.flash() # 渐隐期内再受击
	assert_almost_eq(hf.tick(0.0), 1.0, 1e-9, "重复受击从峰值重新渐隐")
	assert_false(hf.is_idle())
	hf.tick(HitFlashTiming.FADE_TIME_S)
	assert_true(hf.is_idle())

func test_idle_never_goes_negative() -> void:
	var hf := HitFlashTiming.new()
	hf.flash()
	hf.tick(HitFlashTiming.FADE_TIME_S + 1.0)
	assert_almost_eq(hf.tick(1.0), 0.0, 1e-9, "超量推进不产生负 alpha")
