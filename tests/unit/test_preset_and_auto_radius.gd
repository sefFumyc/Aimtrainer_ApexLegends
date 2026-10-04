## 预设表与自动调径的纯逻辑测试（票 03 第 3、4 节）。

extends GutTest

## 造一份完整的 19 项快照，指定体型半径。
func _full(radius: float) -> Dictionary:
	var out := {}
	for field in PresetStore.FIELDS:
		out[field] = PresetStore.DEFAULTS[field]
	out["body_radius"] = radius
	return out

func test_auto_radius_moves_toward_target_accuracy() -> void:
	assert_almost_eq(AutoRadius.adjust(8.0, 0.6827), 8.0, 1e-9, "命中率恰为目标准确率时半径不变")
	assert_true(AutoRadius.adjust(8.0, 1.0) < 8.0, "越准半径越小")
	assert_true(AutoRadius.adjust(8.0, 0.0) > 8.0, "越偏半径越大")
	assert_almost_eq(
		AutoRadius.adjust(8.0, 1.0), 8.0 * pow(10.0, 0.3 * (0.6827 - 1.0)), 1e-9
	)

func test_preset_store_capture_and_duplicate_guard() -> void:
	var ps := PresetStore.new()
	assert_true(ps.store("练枪 A", _full(12.0)))
	assert_false(ps.store("练枪 A", _full(20.0)), "重名不覆盖已有预设")
	assert_false(ps.store("   ", _full(9.0)), "空名拒绝")
	assert_eq(ps.active(), "练枪 A", "新建即选中")
	assert_true(ps.has("练枪 A"))
	assert_almost_eq(ps.capture("练枪 A")["body_radius"], 12.0, 1e-9)
	assert_eq(ps.capture("不存在的预设").size(), 0)

func test_select_falls_back_to_global_when_missing() -> void:
	var ps := PresetStore.new()
	ps.store("A", _full(10.0))
	ps.store("B", _full(20.0))
	ps.select("A")
	assert_eq(ps.active(), "A")
	ps.select("不存在")
	assert_eq(ps.active(), "", "选不存在的名字回落「不选预设」")
	ps.select("B")
	ps.erase("B")
	assert_eq(ps.active(), "", "删掉当前选中即回落「不选预设」")
	assert_false(ps.has("B"))

func test_write_back_is_live_document() -> void:
	var ps := PresetStore.new()
	ps.store("A", _full(10.0))
	ps.write_back(_full(30.0))
	assert_almost_eq(ps.capture("A")["body_radius"], 30.0, 1e-9, "选中期间的改动自动写回该预设")
	ps.select("")
	ps.write_back(_full(50.0))
	assert_almost_eq(ps.capture("A")["body_radius"], 30.0, 1e-9, "不选预设时写回是空操作")

func test_from_dict_fills_missing_and_skips_corrupt() -> void:
	var ps := PresetStore.new()
	ps.from_dict(
		{
			"presets":
			{
				"完整": _full(15.0),
				"老预设":
				{
					"target_range": 300.0,
					"body_radius": 20.0,
					"bot_hit_rate": 50,
					"bot_fire_enabled": true,
					"bot_ads_enabled": false,
					"lifesteal_enabled": true,
				},
				"损坏": {"body_radius": 8.0},
			},
			"active": "老预设",
		}
	)
	assert_true(ps.has("完整"))
	assert_true(ps.has("老预设"))
	assert_false(ps.has("损坏"), "核心六项缺失视为损坏，整条跳过")
	var old := ps.capture("老预设")
	assert_almost_eq(old["body_radius"], 20.0, 1e-9)
	assert_almost_eq(old["bot_aggression"], 0.5, 1e-9, "缺项按出厂默认补齐")
	assert_eq(old["bot_weight_mid"], 0.3)
	assert_eq(ps.active(), "老预设")

	ps.from_dict({"presets": {}, "active": "幽灵"})
	assert_eq(ps.active(), "", "选中项不存在时回落「不选预设」")

func test_round_trip_keeps_presets_and_selection() -> void:
	var ps := PresetStore.new()
	ps.store("A", _full(11.0))
	ps.store("B", _full(22.0))
	var ps2 := PresetStore.new()
	ps2.from_dict(ps.to_dict())
	assert_eq(ps2.names().size(), 2)
	assert_almost_eq(ps2.capture("B")["body_radius"], 22.0, 1e-9)
	assert_eq(ps2.active(), "B", "另存选中项")