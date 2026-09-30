## 全局设置单例（Autoload，ADR-0009）：替代原版的 localStorage，持久化到 `user://settings.cfg`。
##
## 只承载**全局设置项**；对局状态（HP / 击杀 / 命中）属于 DuelMatch 纯逻辑类。

extends Node

const PATH := "user://settings.cfg"

## 「场地布局」三档：空旷 / 少量遮挡 / 多遮挡。
enum Layout { OPEN, SPARSE, DENSE }

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
## 靶的刷新距离（40–800，默认 120）：靶在玩家前方这个距离处出现。
var target_range := 120.0
## 「场地布局」。
var arena_layout: Layout = Layout.SPARSE

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
	cfg.save(PATH)