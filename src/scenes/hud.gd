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

var _marker := HitMarkerTiming.new()
var _match: DuelMatch = null

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

## 绑定对局数据源；HUD 每帧从它取数，自己不存副本。
func bind(match_state: DuelMatch) -> void:
	_match = match_state

## 命中 / 击杀事件（受「命中提示」开关控制）。
func flash(kind: StringName) -> void:
	if GameSettings.hit_marker_enabled:
		_marker.event(kind)

func _process(delta: float) -> void:
	_marker.tick(delta * 1000.0)
	queue_redraw()

func _draw() -> void:
	_draw_crosshair()
	_draw_marker()
	_draw_text()

func _draw_crosshair() -> void:
	draw_circle(size * 0.5, CROSSHAIR_RADIUS, CROSSHAIR_COLOR)

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
