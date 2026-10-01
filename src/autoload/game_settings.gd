## 全局设置单例（Autoload，ADR-0009）：替代原版的 localStorage，持久化到 `user://settings.cfg`。
##
## 只承载**全局设置项**；对局状态（HP / 击杀 / 命中）属于 DuelMatch 纯逻辑类。

extends Node

const PATH := "user://settings.cfg"

## 「场地布局」三档：空旷 / 少量遮挡 / 多遮挡。
enum Layout { OPEN, SPARSE, DENSE }

## 「移动模式」二选一：保持距离 / 动态游走。
enum BotMovement { RANGE, WANDER }

## 三档「模式权重」的取值边界（「模式权重」要求 0–1、步进 0.05）。
const WEIGHT_MIN := 0.0
const WEIGHT_MAX := 1.0
const SWITCH_MIN := 0.2 ## 「模式切换」间隔边界（秒）
const SWITCH_MAX := 10.0
const RANGE_AMP_MIN := 0.0 ## 「走廊」半宽边界
const RANGE_AMP_MAX := 300.0
const HIT_RATE_MIN := 0 ## 「命中率」边界（整数 0–100）
const HIT_RATE_MAX := 100
const DODGE_MIN_TIME_MIN := 0.0 ## 「最短躲避时间」边界（秒，0 = 关闭）
const DODGE_MIN_TIME_MAX := 1.0

## 鼠标灵敏度（1 度 ≈ 多少 rad；与参考实现同一量纲）。
var mouse_sensitivity := 0.0022
## 开镜灵敏度倍率（沿用参考实现 ADR-0021 的内置默认值）。
var ads_sens_mult := 0.751654
## 开关项。
var muzzle_flash_enabled := true
var tracer_enabled := true
var hit_marker_enabled := true
## 靶的「体型半径」（4–60，默认 8）。
var body_radius := Physique.BODY_RADIUS_DEFAULT
## 「目标距离」（40–800，默认 120）：bot 与玩家的理想平面距离，也是「刷新」的生成距离。
var target_range := 120.0
## 「场地布局」。
var arena_layout: Layout = Layout.SPARSE

## 「开火开关」（默认关）：关掉时 bot 只是移动靶，不造成任何伤害。
var bot_fire_enabled := false
## 「命中率」（0–100，默认 68）：bot 每发开火掷骰命中玩家的概率。
var bot_hit_rate := 68
## 「bot 开镜」（默认关）：只体现为移速封顶降到开镜档。
var bot_ads_enabled := false
## 「模式权重」三档（长 / 中 / 快，默认 0.3 / 0.4 / 0.3）：按总和归一化，不要求和为 1。
var bot_weight_long := 0.3
var bot_weight_mid := 0.4
var bot_weight_fast := 0.3
## 「模式切换」间隔区间（秒，默认 1.0–1.5）。
var bot_switch_min := 1.0
var bot_switch_max := 1.5
## 「移动模式」（默认「保持距离」）。
var bot_movement_mode: BotMovement = BotMovement.RANGE
## 「游走倾向」（0–1，默认 0.5）：变向时混入「前后分量」的概率。
var bot_wander := 0.5
## 「进攻倾向」/「撤退倾向」（0–1，默认 0.5）：混入的那一份选 W / S 的加权比例。
var bot_aggression := 0.5
var bot_retreat := 0.5
## 「走廊」半宽（0–300，默认 25）：动态游走时允许的距离波动幅度。
var bot_range_amp := 25.0
## 「躲避概率」（0–1）：连发（步枪）默认 0.1、单发（手枪）默认 0.4。
var bot_dodge_auto := 0.1
var bot_dodge_semi := 0.4
## 「最短躲避时间」（0–1.0 秒，默认 0.15，0 = 关闭）：只约束躲避。
var bot_dodge_min_time := 0.15

func _ready() -> void:
	load_settings()

func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	mouse_sensitivity = cfg.get_value("input", "mouse_sensitivity", mouse_sensitivity)
	ads_sens_mult = cfg.get_value("input", "ads_sens_mult", ads_sens_mult)
	muzzle_flash_enabled = cfg.get_value("fx", "muzzle_flash", muzzle_flash_enabled)
	tracer_enabled = cfg.get_value("fx", "tracer", tracer_enabled)
	hit_marker_enabled = cfg.get_value("fx", "hit_marker", hit_marker_enabled)
	body_radius = clampf(
		cfg.get_value("bot", "body_radius", body_radius), Physique.BODY_RADIUS_MIN, Physique.BODY_RADIUS_MAX
	)
	target_range = clampf(cfg.get_value("bot", "target_range", target_range), 40.0, 800.0)
	arena_layout = cfg.get_value("arena", "layout", arena_layout) as Layout
	bot_fire_enabled = cfg.get_value("bot", "fire_enabled", bot_fire_enabled)
	bot_hit_rate = clampi(
		cfg.get_value("bot", "hit_rate", bot_hit_rate), HIT_RATE_MIN, HIT_RATE_MAX
	)
	bot_ads_enabled = cfg.get_value("bot", "ads_enabled", bot_ads_enabled)
	bot_weight_long = clampf(cfg.get_value("bot", "weight_long", bot_weight_long), WEIGHT_MIN, WEIGHT_MAX)
	bot_weight_mid = clampf(cfg.get_value("bot", "weight_mid", bot_weight_mid), WEIGHT_MIN, WEIGHT_MAX)
	bot_weight_fast = clampf(cfg.get_value("bot", "weight_fast", bot_weight_fast), WEIGHT_MIN, WEIGHT_MAX)
	bot_switch_min = clampf(cfg.get_value("bot", "switch_min", bot_switch_min), SWITCH_MIN, SWITCH_MAX)
	bot_switch_max = clampf(cfg.get_value("bot", "switch_max", bot_switch_max), SWITCH_MIN, SWITCH_MAX)
	bot_movement_mode = (
		cfg.get_value("bot", "movement_mode", bot_movement_mode) as BotMovement
	)
	bot_wander = clampf(cfg.get_value("bot", "wander", bot_wander), WEIGHT_MIN, WEIGHT_MAX)
	bot_aggression = clampf(cfg.get_value("bot", "aggression", bot_aggression), WEIGHT_MIN, WEIGHT_MAX)
	bot_retreat = clampf(cfg.get_value("bot", "retreat", bot_retreat), WEIGHT_MIN, WEIGHT_MAX)
	bot_range_amp = clampf(cfg.get_value("bot", "range_amp", bot_range_amp), RANGE_AMP_MIN, RANGE_AMP_MAX)
	bot_dodge_auto = clampf(cfg.get_value("bot", "dodge_auto", bot_dodge_auto), WEIGHT_MIN, WEIGHT_MAX)
	bot_dodge_semi = clampf(cfg.get_value("bot", "dodge_semi", bot_dodge_semi), WEIGHT_MIN, WEIGHT_MAX)
	bot_dodge_min_time = clampf(
		cfg.get_value("bot", "dodge_min_time", bot_dodge_min_time), DODGE_MIN_TIME_MIN, DODGE_MIN_TIME_MAX
	)

## 把当前设置**就地**写进躲避控制器读的配置（「躲避控制」只读，不反向写回设置）。
## 就地填充是为了让靶持有的那一个 `Config` 实例实时跟随设置变化，不必每帧重建。
func apply_avoidance_config(out: AvoidanceController.Config) -> void:
	out.weights[0] = bot_weight_long
	out.weights[1] = bot_weight_mid
	out.weights[2] = bot_weight_fast
	out.switch_min = bot_switch_min
	out.switch_max = bot_switch_max
	out.wander = bot_wander
	out.aggression = bot_aggression
	out.retreat = bot_retreat
	out.dodge_min = bot_dodge_min_time

## `apply_avoidance_config` 的一次性薄包装（只读快照）。
func avoidance_config() -> AvoidanceController.Config:
	var out := AvoidanceController.Config.new()
	apply_avoidance_config(out)
	return out

## 按玩家当前武器取「躲避概率」：连发（步枪）用「连发」档，单发（手枪）用「单发」档。
func dodge_chance_for(weapon_id: StringName) -> float:
	return bot_dodge_auto if Weapon.automatic(weapon_id) else bot_dodge_semi

func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("input", "mouse_sensitivity", mouse_sensitivity)
	cfg.set_value("input", "ads_sens_mult", ads_sens_mult)
	cfg.set_value("fx", "muzzle_flash", muzzle_flash_enabled)
	cfg.set_value("fx", "tracer", tracer_enabled)
	cfg.set_value("fx", "hit_marker", hit_marker_enabled)
	cfg.set_value("bot", "body_radius", body_radius)
	cfg.set_value("bot", "target_range", target_range)
	cfg.set_value("arena", "layout", arena_layout)
	cfg.set_value("bot", "fire_enabled", bot_fire_enabled)
	cfg.set_value("bot", "hit_rate", bot_hit_rate)
	cfg.set_value("bot", "ads_enabled", bot_ads_enabled)
	cfg.set_value("bot", "weight_long", bot_weight_long)
	cfg.set_value("bot", "weight_mid", bot_weight_mid)
	cfg.set_value("bot", "weight_fast", bot_weight_fast)
	cfg.set_value("bot", "switch_min", bot_switch_min)
	cfg.set_value("bot", "switch_max", bot_switch_max)
	cfg.set_value("bot", "movement_mode", bot_movement_mode)
	cfg.set_value("bot", "wander", bot_wander)
	cfg.set_value("bot", "aggression", bot_aggression)
	cfg.set_value("bot", "retreat", bot_retreat)
	cfg.set_value("bot", "range_amp", bot_range_amp)
	cfg.set_value("bot", "dodge_auto", bot_dodge_auto)
	cfg.set_value("bot", "dodge_semi", bot_dodge_semi)
	cfg.set_value("bot", "dodge_min_time", bot_dodge_min_time)
	cfg.save(PATH)