## 基础 HUD（票 01 第 8 节）：准星、命中/击杀提示、对局数字。
##
## 绘制全部走 `_draw()`，不依赖贴图资源。命中提示的时序交给纯逻辑类
## `HitMarkerTiming`，这里只负责把状态画出来（ADR-0009 / ADR-0013 的分工）。

class_name Hud
extends Control

const CROSSHAIR_RADIUS := 3.5
const CROSSHAIR_COLOR := Color(1.0, 1.0, 1.0, 0.92)

const FONT_SIZE := 16
const TEXT_COLOR := Color(1.0, 1.0, 1.0, 0.92)

## 演示模式状态字幕（ADR-0033）：左下角一行小字，比主 HUD 数字暗一档、字号更小——
## 它是状态角标，不该抢对局数字的视觉权重。开关即显即隐，不做淡入淡出。
const DEMO_FONT_SIZE := 14
const DEMO_TEXT_COLOR := Color(1.0, 1.0, 1.0, 0.7)
const DEMO_LABEL := "演示模式已启用"
const DEMO_MARGIN := 24.0 ## 距屏幕左 / 下边缘的留白（与左上角对局数字同留白口径）

## 击中提示几何（CONTEXT.md「击中提示」）：白 X 与红 X 的参数互不共享。
## `_INNER` 是内端距准星的直线距离，`_ARM` 是斜线段自身的长度（外端 = 内端 + 臂长）。
const MARKER_INNER_HIT := 22.0
const MARKER_ARM_HIT := 10.0
const MARKER_WIDTH_HIT := 3.0
const MARKER_INNER_KILL := 35.0
const MARKER_ARM_KILL := 32.0
const MARKER_WIDTH_KILL := 5.0
const HIT_COLOR := Color(1.0, 1.0, 1.0, 0.95) ## 命中：白 X
const KILL_COLOR := Color(0.96, 0.16, 0.16, 1.0) ## 击杀：红 X

## 受击红屏（ADR-0020 修订 ADR-0019，CONTEXT「受击红屏」）：玩家被命中时屏幕边缘泛起
## 红晕、随即线性渐隐——径向渐变：中心完全透明，从约 75% 半径处起色，红带只占最外约
## 25%，四角最浓（空区多、红带窄，用户要求不全屏晃眼）。与「击中提示」对偶——那个管
## 打人，这个管被打。时序在纯逻辑类 `HitFlashTiming`（ADR-0009 同 `HitMarkerTiming`
## 的分工），这里只把 alpha 落到节点。纯渲染：不参与任何判定与结算。
const HIT_FLASH_PEAK := 0.32 ## 泛红峰值不透明度
const HIT_FLASH_BAND_START := 0.75 ## 径向渐变起色点（0–1，越大空区越大、红带越窄）
const HIT_FLASH_COLOR := Color(0.82, 0.08, 0.08)

var _marker := HitMarkerTiming.new()
var _flash := HitFlashTiming.new() ## 受击红屏时序（纯逻辑）
var _flash_tex: GradientTexture2D ## 边缘红晕的径向渐变纹理（_ready 建一次，绘制时调 modulate）
var _match: DuelMatch = null
var _zoom := 0.0 ## 开镜进度（票 07）：白准星透明度 = 1 − 进度，随开关镜平滑淡出/渐回
var _demo_active := false ## 演示模式状态（ADR-0033）：左下角字幕的显隐

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash_tex = _make_flash_texture()

## 绑定对局数据源；HUD 每帧从它取数，自己不存副本。
func bind(match_state: DuelMatch) -> void:
	_match = match_state

## 喂开镜进度（main 每帧传 `player.zoom_p`），准星淡出与开镜动画同频（CONTEXT「准星」）。
func set_zoom(p: float) -> void:
	_zoom = clampf(p, 0.0, 1.0)

## 演示模式开关（ADR-0033）：由 main 在 F2 切换时喂入，控制左下角状态字幕的显隐。
func set_demo_active(on: bool) -> void:
	_demo_active = on

## 命中 / 击杀事件（受「命中提示」开关控制）。
func flash(kind: StringName) -> void:
	if GameSettings.hit_marker_enabled:
		_marker.event(kind)

## 受击红屏事件（受「受击红屏」开关控制）：重复命中刷新计时，从峰值重新渐隐。
func flash_hurt() -> void:
	if GameSettings.hit_flash_enabled:
		_flash.flash()

func _process(delta: float) -> void:
	_marker.tick(delta * 1000.0)
	_flash.tick(delta)
	queue_redraw()

func _draw() -> void:
	_draw_hurt_flash()
	_draw_crosshair()
	_draw_marker()
	_draw_text()

func _draw_hurt_flash() -> void:
	var ratio := _flash.tick(0.0) # 0–1；_process 已推进，这里只读当前值
	if ratio <= 0.0:
		return
	# 纹理已含红色与径向 alpha 分布，绘制时只调整体透明度（峰值 × 渐隐比例）。
	draw_texture_rect(_flash_tex, Rect2(Vector2.ZERO, size), false, Color(1.0, 1.0, 1.0, HIT_FLASH_PEAK * ratio))

## 边缘红晕纹理（ADR-0020）：256² 径向渐变拉伸铺满屏幕——UV 空间从中心到各边中点
## 等距，故四边红带起点一致；四角 UV 距离更远、更早饱和，天然「四角最浓」。
func _make_flash_texture() -> GradientTexture2D:
	var tex := GradientTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5) # 圆心 = 屏幕中心
	tex.fill_to = Vector2(0.5, 0.0) # 半径 = 中心到边中点（UV 0.5）
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, HIT_FLASH_BAND_START, 1.0])
	grad.colors = PackedColorArray([
		Color(HIT_FLASH_COLOR.r, HIT_FLASH_COLOR.g, HIT_FLASH_COLOR.b, 0.0),
		Color(HIT_FLASH_COLOR.r, HIT_FLASH_COLOR.g, HIT_FLASH_COLOR.b, 0.0),
		Color(HIT_FLASH_COLOR.r, HIT_FLASH_COLOR.g, HIT_FLASH_COLOR.b, 1.0),
	])
	tex.gradient = grad
	return tex

func _draw_crosshair() -> void:
	# 淡出只作用于白准星（票 07）：让位给红点镜；命中 X 与数字不受影响。
	var alpha := (1.0 - _zoom) * CROSSHAIR_COLOR.a
	if alpha <= 0.004:
		return
	draw_circle(size * 0.5, CROSSHAIR_RADIUS, Color(CROSSHAIR_COLOR.r, CROSSHAIR_COLOR.g, CROSSHAIR_COLOR.b, alpha))

func _draw_marker() -> void:
	if _marker.is_idle():
		return
	var kill := _marker.kind == HitMarkerTiming.KIND_KILL
	# 保持期满尺寸；消失动画以准星为锚点，缩放与不透明度同步线性收缩。
	var t := 1.0
	if _marker.phase == HitMarkerTiming.PHASE_FADE:
		var total := HitMarkerTiming.KILL_FADE_MS if kill else HitMarkerTiming.HIT_FADE_MS
		t = clampf(_marker.remaining_ms / total, 0.0, 1.0)
	var base := KILL_COLOR if kill else HIT_COLOR
	var col := Color(base.r, base.g, base.b, base.a * t)
	var inner := (MARKER_INNER_KILL if kill else MARKER_INNER_HIT) * t
	var outer := inner + (MARKER_ARM_KILL if kill else MARKER_ARM_HIT) * t
	var width := MARKER_WIDTH_KILL if kill else MARKER_WIDTH_HIT
	var center := size * 0.5
	for i in 4:
		var ang := PI * 0.25 + float(i) * PI * 0.5
		var d := Vector2(cos(ang), sin(ang))
		draw_line(center + d * inner, center + d * outer, col, width)

func _draw_text() -> void:
	var font := ThemeDB.fallback_font
	var lines := _lines()
	var y := 24.0
	for entry in lines:
		var text: String = entry[0]
		var col: Color = entry[1]
		draw_string(font, Vector2(24.0, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, col)
		y += FONT_SIZE + 6.0
	# 演示模式字幕走**左下角**（ADR-0033）：与左上角的对局数字分居两角、互不干扰。
	if _demo_active:
		draw_string(
			font,
			Vector2(DEMO_MARGIN, size.y - DEMO_MARGIN),
			DEMO_LABEL,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			DEMO_FONT_SIZE,
			DEMO_TEXT_COLOR
		)

func _lines() -> Array:
	if _match == null:
		return []
	var m := _match
	var acc := m.accuracy()
	var acc_text := "—" if acc < 0.0 else "%.1f%%" % acc # 0 发显示「—」（CONTEXT「准确率」）
	var minutes := int(m.elapsed) / 60
	var seconds := int(m.elapsed) % 60
	return [
		["命中 / 射击：%d / %d" % [m.hits, m.shots], TEXT_COLOR],
		["准确率：%s" % acc_text, TEXT_COLOR],
		["玩家血量：%d / %d" % [m.player_hp, DuelMatch.MAX_HP], TEXT_COLOR],
		["靶血量：%d / %d" % [m.bot_hp, DuelMatch.MAX_HP], TEXT_COLOR],
		["击杀：%d" % m.kills, TEXT_COLOR],
		["计时：%02d:%02d" % [minutes, seconds], TEXT_COLOR],
	]
