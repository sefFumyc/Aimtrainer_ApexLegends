## 命中判定体型（CONTEXT.md「体型」「体型半径」）。
##
## 总高 72 单位：圆柱形身体（高 60、直径 16）+ 头顶球体（半径 6）；玩家视线高度与头心平齐（66）。
## ❗ 体型半径只缩放**水平**方向（x/z），身高与头心高度不变——爆头判定面随半径变宽，但瞄准高度不变。
## 纯逻辑：只放数值与换算，不含碰撞体装配（那是场景的事）。

class_name Physique
extends RefCounted

const BODY_RADIUS := 8.0 ## 身体圆柱半径（直径 16）
const BODY_HEIGHT := 60.0
const HEAD_RADIUS := 6.0
const HEAD_CENTER_Y := 66.0
const EYE_HEIGHT := 66.0 ## 玩家视线高度（与 bot 头心平齐）
const TOTAL_HEIGHT := 72.0

const BODY_RADIUS_DEFAULT := 8.0 ## 「体型半径」设置项默认值
const BODY_RADIUS_MIN := 4.0
const BODY_RADIUS_MAX := 60.0

## 水平缩放系数（身体与头一起缩放；y 轴始终保持 1）。
static func horizontal_scale(body_radius: float) -> float:
	return body_radius / BODY_RADIUS_DEFAULT