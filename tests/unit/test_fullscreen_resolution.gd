## 「全屏宽高比」分辨率换算的纯逻辑测试（ADR-0029）：屏高为分母、按 16:aspect 算宽。

extends GutTest

const GS := preload("res://src/autoload/game_settings.gd")

func test_16_9_matches_desktop_native() -> void:
	assert_eq(GS.fullscreen_resolution(Vector2i(2560, 1440), 9), Vector2i(2560, 1440), "16:9 恰为桌面原生")
	assert_eq(GS.fullscreen_resolution(Vector2i(1920, 1080), 9), Vector2i(1920, 1080))

func test_16_10_narrower_than_screen() -> void:
	assert_eq(GS.fullscreen_resolution(Vector2i(2560, 1440), 10), Vector2i(2304, 1440), "16:10 窄于屏幕，驱动拉伸铺满")
	assert_eq(GS.fullscreen_resolution(Vector2i(1920, 1080), 10), Vector2i(1728, 1080))

func test_ultrawide_uses_height_only() -> void:
	assert_eq(GS.fullscreen_resolution(Vector2i(3440, 1440), 10), Vector2i(2304, 1440), "只取屏高，宽随比例")
	assert_eq(GS.fullscreen_resolution(Vector2i(3440, 1440), 9), Vector2i(2560, 1440))

func test_odd_height_rounds() -> void:
	assert_eq(GS.fullscreen_resolution(Vector2i(1000, 1001), 10), Vector2i(1602, 1001), "1001×1.6 = 1601.6 → 1602")
