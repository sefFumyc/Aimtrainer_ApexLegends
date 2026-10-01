## 对局统计与双方血量（CONTEXT.md「对局」「玩家血量」「吸血」）。
##
## 双方 HP 600；无尽练习（无局边界）。纯逻辑：不依赖节点树。

class_name DuelMatch
extends RefCounted

const MAX_HP := 600

## 结算快照（CONTEXT.md「结算快照」）：结束对局时定格的数据，读取的是快照不是实时滚动值。
class Snapshot:
	var accuracy := -1.0 ## 百分比、一位小数；0 发为 −1（无数据）
	var kills := 0
	var deaths := 0
	var elapsed := 0.0

var player_hp := MAX_HP
var bot_hp := MAX_HP
var kills := 0
var shots := 0
var hits := 0
var deaths := 0
var elapsed := 0.0

## 最近一次结算的快照；从未结算过为 null（对局中读取返回上一局，见 CONTEXT「结算快照」）。
var _last_snapshot: Snapshot = null

func reset() -> void:
	player_hp = MAX_HP
	bot_hp = MAX_HP
	kills = 0
	shots = 0
	hits = 0
	deaths = 0
	elapsed = 0.0

func record_shot(hit: bool) -> void:
	shots += 1
	if hit:
		hits += 1

func record_kill() -> void:
	kills += 1

func record_death() -> void:
	deaths += 1

## 吸血：按本次伤害回血，封顶最大 HP 不溢出。
func heal_player(amount: int) -> void:
	player_hp = mini(MAX_HP, player_hp + amount)

func heal_bot(amount: int) -> void:
	bot_hp = mini(MAX_HP, bot_hp + amount)

## 命中率 → 百分比（保留一位小数）；0 发返回 -1（无数据）。
## 这是全局唯一的准确率口径：实时 HUD、结算快照、计时会话累计与休息覆盖层共用（票 03 验收 1）。
static func accuracy_percent(hit_count: int, shot_count: int) -> float:
	return snappedf((float(hit_count) / float(shot_count)) * 100.0, 0.1) if shot_count > 0 else -1.0

## 准确率（百分比，保留一位小数）；本次对局尚无射弹时返回 -1（无数据）。
func accuracy() -> float:
	return DuelMatch.accuracy_percent(hits, shots)

## 结束对局并定格结算快照（票 03 第 1 节）：准确率 / 击杀 / 死亡 / 用时。
func settle() -> Snapshot:
	var snap := Snapshot.new()
	snap.accuracy = accuracy()
	snap.kills = kills
	snap.deaths = deaths
	snap.elapsed = elapsed
	_last_snapshot = snap
	return snap

## 最近一次结算的快照；从未结算过返回 null（对局中读取到的是上一局的定格值）。
func last_snapshot() -> Snapshot:
	return _last_snapshot