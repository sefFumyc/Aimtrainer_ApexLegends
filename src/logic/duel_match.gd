## 对局统计与双方血量（CONTEXT.md「对局」「玩家血量」「吸血」）。
##
## 双方 HP 600；无尽练习（无局边界）。纯逻辑：不依赖节点树。

class_name DuelMatch
extends RefCounted

const MAX_HP := 600

var player_hp := MAX_HP
var bot_hp := MAX_HP
var kills := 0
var shots := 0
var hits := 0
var deaths := 0
var elapsed := 0.0

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

## 准确率（百分比）；本次对局尚无射弹时返回 -1（无数据）。
func accuracy() -> float:
	return (float(hits) / float(shots)) * 100.0 if shots > 0 else -1.0