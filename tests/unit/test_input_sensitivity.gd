## 鼠标灵敏度倍率量纲的纯逻辑测试（票 05 第 2 项）：迁移守卫与倍率换算。

extends GutTest

func test_migrate_falls_back_for_legacy_rad_per_px_values() -> void:
	# 旧版按 rad/px 存档（0.0005–0.006），全部落在倍率区间 [0.2, 5.0] 之外
	assert_almost_eq(InputSensitivity.migrate_mouse(0.0022), 1.0, 1e-9, "旧默认值回落 1.0")
	assert_almost_eq(InputSensitivity.migrate_mouse(0.0005), 1.0, 1e-9)
	assert_almost_eq(InputSensitivity.migrate_mouse(0.006), 1.0, 1e-9)
	assert_almost_eq(InputSensitivity.migrate_mouse(0.0), 1.0, 1e-9)
	assert_almost_eq(InputSensitivity.migrate_mouse(-1.0), 1.0, 1e-9, "负值回落默认")

func test_migrate_keeps_and_clamps_multiplier_values() -> void:
	assert_almost_eq(InputSensitivity.migrate_mouse(1.0), 1.0, 1e-9, "合法值原样保留")
	assert_almost_eq(InputSensitivity.migrate_mouse(2.5), 2.5, 1e-9)
	assert_almost_eq(InputSensitivity.migrate_mouse(0.2), 0.2, 1e-9, "下边界保留")
	assert_almost_eq(InputSensitivity.migrate_mouse(10.0), 5.0, 1e-9, "越上界夹紧")

func test_mouse_rad_per_px_scales_with_multiplier() -> void:
	assert_almost_eq(InputSensitivity.mouse_rad_per_px(1.0), 0.0022, 1e-9, "倍率 1 = 基准 0.0022 rad/px")
	assert_almost_eq(InputSensitivity.mouse_rad_per_px(2.0), 0.0044, 1e-9)
	assert_almost_eq(InputSensitivity.mouse_rad_per_px(0.5), 0.0011, 1e-9)
