## 场地遮挡物布局生成（ADR-0004）：程序化箱体与柱体，**参与碰撞且参与射线**。
##
## 本类是**纯逻辑**：只产出「形状 + 位置 + 尺寸」，不碰节点树（ADR-0009 / ADR-0013），
## 因此「不生成在出生点与刷新点上」这条验收条件可以用 GUT 直接断言。
## 场景层（`src/scenes/arena.gd`）负责把这份清单变成 StaticBody3D + Mesh。

class_name CoverLayout
extends RefCounted

## 「场地布局」三档：空旷 / 少量遮挡 / 多遮挡。默认「少量遮挡」。
enum Layout { OPEN, SPARSE, DENSE }

## 各档遮挡物数量，下标即 Layout 的值。
const COUNTS := [0, 6, 14]

## 形状：0 = 箱体（方形底面，边长 = 2 × footprint），1 = 柱体（圆底，半径 = footprint）。
const SHAPE_BOX := 0
const SHAPE_CYLINDER := 1

## 固定随机种子：同一档位每次启动得到同一套布局（可复现、可背记）。
const SEED := 20260930

## 环形采样带：内半径 200 已越过原点出生点与默认刷新距离 120，外半径留给围墙。
const BAND_INNER := 200.0
const BAND_OUTER_MARGIN := 150.0

## 遮挡物底面「半径」范围（箱体取半边长）。
const FOOT_MIN := 45.0
const FOOT_MAX := 95.0
## 高度范围。
const HEIGHT_MIN := 120.0
const HEIGHT_MAX := 320.0

## 遮挡物之间的最小净间隙。
const GAP := 90.0
## 与避让点（玩家出生点 / 靶刷新点）之间除遮具体半径外另留的净距。
const DEFAULT_CLEARANCE := 120.0

## 生成一份布局清单。每项：`{ shape: int, pos: Vector2, foot: float, height: float }`。
##
## `avoid` 是必须避开的点（玩家出生点、靶刷新点）；`clearance` 是这些点周围的最小净距。
## 采样密度不够时（例如场地被避让点占满）宁少不重叠：尝试次数耗尽即返回已放置的部分。
static func generate(
	layout: int,
	arena_radius: float = MovementSimulator.ARENA_RADIUS,
	avoid: Array = [],
	clearance: float = DEFAULT_CLEARANCE
) -> Array:
	var out: Array = []
	var count: int = 0
	if layout >= 0 and layout < COUNTS.size():
		count = COUNTS[layout]
	if count <= 0:
		return out

	var inner := maxf(BAND_INNER, clearance + FOOT_MAX)
	var outer := arena_radius - BAND_OUTER_MARGIN - FOOT_MAX
	if outer <= inner:
		return out

	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var attempts := 0
	var max_attempts := count * 80
	while out.size() < count and attempts < max_attempts:
		attempts += 1
		var angle := rng.randf_range(0.0, TAU)
		# 半径按面积均匀采样（对 r 取平方根），否则遮挡物会全挤在内圈。
		var r := sqrt(rng.randf_range(inner * inner, outer * outer))
		var foot := rng.randf_range(FOOT_MIN, FOOT_MAX)
		var pos := Vector2(cos(angle), sin(angle)) * r
		if not _fits(pos, foot, out, avoid, clearance):
			continue
		out.append({
			"shape": SHAPE_BOX if rng.randf() < 0.55 else SHAPE_CYLINDER,
			"pos": pos,
			"foot": foot,
			"height": rng.randf_range(HEIGHT_MIN, HEIGHT_MAX),
		})
	return out

## 候选位置是否与避让点、已放置遮具都留够净距。
static func _fits(pos: Vector2, foot: float, placed: Array, avoid: Array, clearance: float) -> bool:
	for p in avoid:
		if pos.distance_to(p) < clearance + foot:
			return false
	for c in placed:
		if pos.distance_to(c["pos"]) < float(c["foot"]) + foot + GAP:
			return false
	return true
