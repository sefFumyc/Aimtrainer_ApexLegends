## 输入灵敏度的纯逻辑缝（票 05 第 2 项）：鼠标滑条从 rad/px 改成「倍率」量纲。
##
## CONTEXT「灵敏度」对鼠标的定义本来就是乘数（「每个鼠标计数转多少 = 基准 × 倍率」），
## 旧实现把 rad/px 直接当滑条值属于实现走样；这里集中放「倍率 → 实际角速度」的换算
## 与旧存档的迁移守卫，供 `GameSettings`（持久化）与 `Player`（换算）共用，GUT 可测。

class_name InputSensitivity

## 鼠标基准：每个鼠标计数（像素）转多少弧度。旧版滑条直存此量纲的默认 0.0022。
const MOUSE_LOOK_BASE := 0.0022

## 鼠标滑条倍率边界与默认（与手柄同量纲同区间，沿用参考实现 settings.ts）。
const MOUSE_SENSITIVITY_MIN := 0.2
const MOUSE_SENSITIVITY_MAX := 5.0
const MOUSE_SENSITIVITY_DEFAULT := 1.0

## 旧版按 rad/px（0.0005–0.006）存档的值在倍率量纲下全部非法 → 一律回落默认；
## 新量纲的合法值原样保留、越界夹紧（与手柄灵敏度的迁移守卫同一模式）。
static func migrate_mouse(stored: float) -> float:
	if stored < MOUSE_SENSITIVITY_MIN:
		return MOUSE_SENSITIVITY_DEFAULT
	return clampf(stored, MOUSE_SENSITIVITY_MIN, MOUSE_SENSITIVITY_MAX)

## 滑条倍率 → 实际角速度（rad/px）。
static func mouse_rad_per_px(mult: float) -> float:
	return MOUSE_LOOK_BASE * mult
