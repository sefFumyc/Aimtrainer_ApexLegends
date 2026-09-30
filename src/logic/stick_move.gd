## 左摇杆 → 移动意图（「摇杆离散」）。
##
## 离散 8 向：每轴独立阈值（死区 13%）判向，幅度只做阈值判定、不线性调速；
## 前向半球推杆幅度达标自动进「疾跑」（Apex 语义）。
## 纯逻辑：不依赖节点树。

class_name StickMove
extends RefCounted

## 前推自动疾跑的推杆幅度阈值（「推到了那个移速」即开跑）。
const AUTO_SPRINT_MAG := 0.55
const DEADZONE := MovementSimulator.STICK_DEADZONE

var right := 0.0 ## ±1 / 0（8 向：仅轴符号，无幅度）
var fwd := 0.0
var sprint := false

## 摇杆 XY（Godot 约定：X 右正、Y **下**正）→ 离散 8 向移动意图。
static func from_axes(left_x: float, left_y: float) -> StickMove:
	var out := StickMove.new()
	var ax := absf(left_x)
	var ay := absf(left_y)
	if ax <= DEADZONE and ay <= DEADZONE:
		return out # 死区内两轴均判静止
	out.right = signf(left_x) if ax > DEADZONE else 0.0
	out.fwd = -signf(left_y) if ay > DEADZONE else 0.0 # Y 下正 → 上推为前
	var mag := maxf(ax, ay)
	# 疾跑仅前向半球（含前 / 前斜）且幅度达标
	out.sprint = out.fwd > 0.0 and mag >= AUTO_SPRINT_MAG
	return out