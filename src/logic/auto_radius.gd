## 自动调径（票 03 第 3 节 / CONTEXT.md「自动调径」）：按每游玩段的准确率调整「体型半径」。
##
## 数值与参考实现 `src/settings.ts` 的 `autoAdjustRadius` 逐字一致。

class_name AutoRadius
extends RefCounted

## 固定目标准确率（≈默认「命中率」68%）。
const TARGET_ACCURACY := 0.6827
## 指数系数：越准越小、越偏越大。
const EXPONENT := 0.3

## 新半径 = 旧半径 × 10^(0.3·(0.6827−准确率))；`accuracy` 是小数 0–1。
## 返回**未钳制**值——钳制到「体型半径」边界（4–60）由调用方负责。
static func adjust(old_radius: float, accuracy: float) -> float:
	return old_radius * pow(10.0, EXPONENT * (TARGET_ACCURACY - accuracy))