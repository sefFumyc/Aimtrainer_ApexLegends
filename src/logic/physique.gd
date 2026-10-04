## 命中判定体型（CONTEXT.md「体型」「体型半径」）。
##
## 这里的身体圆柱/头球尺寸只在角色模型缺失时作为兜底命中体（target.gd 的
## `_build_fallback_shapes`）；常态下命中体由模型自身几何构成。总高 72 单位是模型拟合基准，
## 玩家视线高度与头心平齐（66）。
## ❗ 体型半径只缩放**水平**方向（x/z），身高不变——命中面随半径变宽，但瞄准高度不变。
## 纯逻辑：只放数值与换算，不含碰撞体装配（那是场景的事）。

class_name Physique
extends RefCounted

const BODY_RADIUS := 8.0 ## 身体圆柱半径（直径 16）
const BODY_HEIGHT := 60.0
const HEAD_RADIUS := 6.0
const HEAD_CENTER_Y := 66.0
const EYE_HEIGHT := 66.0 ## 玩家视线高度（与 bot 头心平齐）
const TOTAL_HEIGHT := 72.0

const BODY_RADIUS_DEFAULT := 8.0 ## 「体型半径」归一基准：半径 8 = 中性体型不缩放（设置出厂默认 12 见 GameSettings）
const BODY_RADIUS_MIN := 4.0
const BODY_RADIUS_MAX := 60.0

## 水平缩放系数（身体与头一起缩放；y 轴始终保持 1）。
static func horizontal_scale(body_radius: float) -> float:
	return body_radius / BODY_RADIUS_DEFAULT