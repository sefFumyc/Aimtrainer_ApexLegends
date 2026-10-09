## 全局设置单例（Autoload，ADR-0009）：替代原版的 localStorage，持久化到 `user://settings.cfg`。
##
## 只承载**全局设置项**；对局状态（HP / 击杀 / 命中）属于 DuelMatch 纯逻辑类。

extends Node

const PATH := "user://settings.cfg"

## 「场地布局」三档：空旷 / 少量遮挡 / 多遮挡。
enum Layout { OPEN, SPARSE, DENSE }

## 「移动模式」二选一：保持距离 / 动态游走。
enum BotMovement { RANGE, WANDER }

## 「画面质量」两档（CONTEXT「画面质量」）：低 = 直渲 + 调色 + 低分辨率阴影；中 = 全套后处理。
enum Quality { LOW, MEDIUM }

## 鼠标 / 手柄灵敏度都是「无量纲倍率」（票 05 把鼠标从 rad/px 改成倍率——CONTEXT「灵敏度」
## 对鼠标本就是乘数定义，属修正不算偏离）：鼠标乘基准 `InputSensitivity.MOUSE_LOOK_BASE`（rad/px），
## 手柄乘 `Player.GAMEPAD_LOOK_BASE`（rad/s）。区间沿用参考实现 settings.ts 的
## SENSITIVITY_MIN/MAX；出厂默认即玩家实测定稿手感（鼠标 1.0 / 手柄 1.3）。
const GAMEPAD_SENSITIVITY_MIN := 0.2
const GAMEPAD_SENSITIVITY_MAX := 5.0
const GAMEPAD_SENSITIVITY_DEFAULT := 1.3

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
const JUMP_INTERVAL_MIN := 0.5 ## 「跳跃间隔」边界（秒）；下限 0.5 是故意的——压进滞空 0.72s 以下 = 连跳 bot（ADR-0023）
const JUMP_INTERVAL_MAX := 15.0
## 「后坐力强度」四通道倍率边界（倍率量纲 0–2，票 08 / CONTEXT「后坐力强度」）。
const RECOIL_MULT_MIN := 0.0
const RECOIL_MULT_MAX := 2.0

## 鼠标灵敏度：对基准 rad/px 的无量纲倍率（票 05 改量纲；换算与迁移见 `InputSensitivity`）。
var mouse_sensitivity := InputSensitivity.MOUSE_SENSITIVITY_DEFAULT
## 手柄灵敏度（右摇杆 → 角速度的无量纲倍率，默认 1.3 ⇒ 满推 3.25 rad/s，与鼠标分开设定）。
var gamepad_sensitivity := GAMEPAD_SENSITIVITY_DEFAULT
## 开镜灵敏度倍率（出厂默认 ×0.5，玩家实测定稿）。
var ads_sens_mult := 0.5
## 「键位设置」（ADR-0025）：动作 → 手柄绑定描述符（如 "b10" / "a5:1" / ""=未绑定）。
## 与灵敏度同属全局共享，不进预设；描述符语义与回灌见 `GamepadBindings`。
var gamepad_bindings: Dictionary = GamepadBindings.defaults()
## 开关项。
var muzzle_flash_enabled := true
var tracer_enabled := true
var hit_marker_enabled := true
## 「受击红屏」（ADR-0019）：玩家被 bot 命中时全屏泛红渐隐的开关，与「命中提示」对偶。
var hit_flash_enabled := true
## 「后坐力强度」（票 08，CONTEXT）：枪械抖动（枪体 kick）与相机抖动（相机踢）按武器
## 分档的倍率，出厂默认即玩家实测定稿手感（步枪/手枪 × 枪械/相机），0 = 关掉该通道。
## 个人手感偏好，不进预设 26 项。
var recoil_gun_rifle := 1.4
var recoil_gun_pistol := 2.0
var recoil_cam_rifle := 0.72
var recoil_cam_pistol := 2.0
## 「画面质量」两档（默认中）。
var graphics_quality: Quality = Quality.MEDIUM
## 靶的「体型半径」（4–60，默认 12）。
var body_radius := 12.0
## 「目标距离」（40–800，默认 400）：bot 与玩家的理想平面距离，也是「刷新」的生成距离。
var target_range := 400.0
## 「场地布局」。
var arena_layout: Layout = Layout.DENSE

## 「开火开关」（默认开）：关掉时 bot 只是移动靶，不造成任何伤害。
var bot_fire_enabled := true
## 「命中率」（0–100，默认 50）：bot 每发开火掷骰命中玩家的概率。
var bot_hit_rate := 50
## 「bot 开镜」（默认关）：只体现为移速封顶降到开镜档。
var bot_ads_enabled := false
## 「模式权重」三档（长 / 中 / 快，默认 0.5 / 0.3 / 0.3）：按总和归一化，不要求和为 1。
var bot_weight_long := 0.5
var bot_weight_mid := 0.3
var bot_weight_fast := 0.3
## 「模式切换」间隔区间（秒，默认 1.0–1.5）。
var bot_switch_min := 1.0
var bot_switch_max := 1.5
## 「移动模式」（默认「动态游走」）。
var bot_movement_mode: BotMovement = BotMovement.WANDER
## 「游走倾向」（0–1，默认 0.45）：变向时混入「前后分量」的概率。
var bot_wander := 0.45
## 「进攻倾向」/「撤退倾向」（0–1，默认 0.5 / 0.3）：混入的那一份选 W / S 的加权比例。
var bot_aggression := 0.5
var bot_retreat := 0.3
## 「走廊」半宽（0–300，默认 100）：动态游走时允许的距离波动幅度。
var bot_range_amp := 100.0
## 「躲避概率」（0–1）：连发（步枪）默认 0.15、单发（手枪）默认 0.3。
var bot_dodge_auto := 0.15
var bot_dodge_semi := 0.3
## 「最短躲避时间」（0–1.0 秒，默认 0.1，0 = 关闭）：只约束躲避。
var bot_dodge_min_time := 0.1

## 「bot 滑铲」（票 09 / ADR-0016）：攻击滑铲与重生滑铲两个开关 + 铲跳开关与概率
## （出厂默认全开、概率 0.5，玩家实测定稿）。
## 任一滑铲开关开启时「bot 常驻开镜」互锁关闭（开镜封速 130 < 滑铲门槛 200，同时开会废掉滑铲）。
var bot_attack_slide_enabled := true
var bot_respawn_slide_enabled := true
var bot_slide_jump_enabled := true
var bot_slide_jump_prob := 0.5
## 「bot 跳跃」（票 11 / ADR-0023）：独立随机计时的对枪跳跃——开关 + 「跳跃间隔」窗口（秒）。
## 不绑变向/受击；不与「bot 开镜」互锁（bot 开镜无视觉表现，空中开镜不矛盾）。
var bot_jump_enabled := true
var bot_jump_min := 4.0
var bot_jump_max := 12.0
## 「吸血」（默认关）：命中方按本次伤害回血，封顶 600。
var lifesteal_enabled := false
## 「间隔计时器」（默认关）：启用后主菜单「开始」进入计时会话。
var timer_enabled := false
## 「自动调径」（默认开；前置条件 = 计时器勾选）：每游玩段按准确率调整体型半径。
var auto_adjust_radius := true
## 计时会话参数：每段游玩秒数 / 每段休息秒数 / 重复次数（出厂默认 40 / 40 / 8，玩家实测定稿）。
var timer_play_seconds := 40
var timer_rest_seconds := 40
var timer_repeat := 8

## 命名预设表（独立于全局设置持久化；「不选预设」= 全局设置本身）。
var presets := PresetStore.new()

func _ready() -> void:
	load_settings()
	# 键位回灌 InputMap（ADR-0025）：只替换手柄事件、保留键鼠事件，启动即生效。
	GamepadBindings.apply_all(gamepad_bindings)

func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	# 鼠标灵敏度是「对基准 0.0022 rad/px 的无量纲倍率」（票 05 改量纲）。旧版按 rad/px
	# 存成 ~0.0022，那种落在合法区间之外的历史值一律回落默认（与下面的手柄同一守卫模式）。
	mouse_sensitivity = InputSensitivity.migrate_mouse(
		cfg.get_value("input", "mouse_sensitivity", mouse_sensitivity)
	)
	# 手柄灵敏度是「对基准的无量纲倍率」（0.2–5.0）。早期版本误把它按鼠标那种 rad/px 量纲
	# 存成 ~0.0022，那种落在合法区间之外的历史值一律丢弃、回落默认，否则修好之后手感依旧是死的。
	var stored_pad: float = cfg.get_value(
		"input", "gamepad_sensitivity", GAMEPAD_SENSITIVITY_DEFAULT
	)
	gamepad_sensitivity = clampf(
		stored_pad if stored_pad >= GAMEPAD_SENSITIVITY_MIN else GAMEPAD_SENSITIVITY_DEFAULT,
		GAMEPAD_SENSITIVITY_MIN,
		GAMEPAD_SENSITIVITY_MAX
	)
	ads_sens_mult = cfg.get_value("input", "ads_sens_mult", ads_sens_mult)
	gamepad_bindings = GamepadBindings.load_bindings(cfg)
	graphics_quality = cfg.get_value("video", "quality", graphics_quality) as Quality
	muzzle_flash_enabled = cfg.get_value("fx", "muzzle_flash", muzzle_flash_enabled)
	tracer_enabled = cfg.get_value("fx", "tracer", tracer_enabled)
	hit_marker_enabled = cfg.get_value("fx", "hit_marker", hit_marker_enabled)
	hit_flash_enabled = cfg.get_value("fx", "hit_flash", hit_flash_enabled)
	recoil_gun_rifle = clampf(cfg.get_value("recoil", "gun_rifle", recoil_gun_rifle), RECOIL_MULT_MIN, RECOIL_MULT_MAX)
	recoil_gun_pistol = clampf(cfg.get_value("recoil", "gun_pistol", recoil_gun_pistol), RECOIL_MULT_MIN, RECOIL_MULT_MAX)
	recoil_cam_rifle = clampf(cfg.get_value("recoil", "cam_rifle", recoil_cam_rifle), RECOIL_MULT_MIN, RECOIL_MULT_MAX)
	recoil_cam_pistol = clampf(cfg.get_value("recoil", "cam_pistol", recoil_cam_pistol), RECOIL_MULT_MIN, RECOIL_MULT_MAX)
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
	bot_attack_slide_enabled = cfg.get_value("bot", "attack_slide", bot_attack_slide_enabled)
	bot_respawn_slide_enabled = cfg.get_value("bot", "respawn_slide", bot_respawn_slide_enabled)
	bot_slide_jump_enabled = cfg.get_value("bot", "slide_jump", bot_slide_jump_enabled)
	bot_slide_jump_prob = clampf(
		cfg.get_value("bot", "slide_jump_prob", bot_slide_jump_prob), WEIGHT_MIN, WEIGHT_MAX
	)
	bot_jump_enabled = cfg.get_value("bot", "jump_enabled", bot_jump_enabled)
	bot_jump_min = clampf(
		cfg.get_value("bot", "jump_min", bot_jump_min), JUMP_INTERVAL_MIN, JUMP_INTERVAL_MAX
	)
	bot_jump_max = clampf(
		cfg.get_value("bot", "jump_max", bot_jump_max), JUMP_INTERVAL_MIN, JUMP_INTERVAL_MAX
	)
	lifesteal_enabled = cfg.get_value("duel", "lifesteal", lifesteal_enabled)
	timer_enabled = cfg.get_value("timer", "enabled", timer_enabled)
	auto_adjust_radius = cfg.get_value("timer", "auto_adjust_radius", auto_adjust_radius)
	timer_play_seconds = clampi(
		cfg.get_value("timer", "play_seconds", timer_play_seconds),
		IntervalTimer.PLAY_MIN,
		IntervalTimer.PLAY_MAX
	)
	timer_rest_seconds = clampi(
		cfg.get_value("timer", "rest_seconds", timer_rest_seconds),
		IntervalTimer.REST_MIN,
		IntervalTimer.REST_MAX
	)
	timer_repeat = clampi(
		cfg.get_value("timer", "repeat", timer_repeat), IntervalTimer.REPEAT_MIN, IntervalTimer.REPEAT_MAX
	)
	presets.from_dict(
		{
			"presets": cfg.get_value("presets", "table", {}),
			"active": cfg.get_value("presets", "active", ""),
		}
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

## 任一 bot 滑铲开关是否开启（ADS 互锁与铲跳可用性判定共用）。
func bot_slide_any_enabled() -> bool:
	return bot_attack_slide_enabled or bot_respawn_slide_enabled

## 按玩家当前武器取「躲避概率」：连发（步枪）用「连发」档，单发（手枪）用「单发」档。
func dodge_chance_for(weapon_id: StringName) -> float:
	return bot_dodge_auto if Weapon.automatic(weapon_id) else bot_dodge_semi

## 按玩家当前武器取「相机抖动」倍率（票 08，CONTEXT「后坐力强度」）：缩放相机踢与水平抖动。
func recoil_cam_mult_for(weapon_id: StringName) -> float:
	return recoil_cam_rifle if Weapon.automatic(weapon_id) else recoil_cam_pistol

## 按玩家当前武器取「枪械抖动」倍率：缩放枪体后坐位移与上抬角（票 08）。
func recoil_gun_mult_for(weapon_id: StringName) -> float:
	return recoil_gun_rifle if Weapon.automatic(weapon_id) else recoil_gun_pistol

# ---- 键位设置（ADR-0025）----

## 查某动作当前的绑定描述符（"" = 未绑定）。
func gamepad_binding_of(action: StringName) -> String:
	return String(gamepad_bindings.get(action, ""))

## 改绑一个动作：抢占（同键从其他动作摘除）→ 回灌 InputMap → 落盘。
func set_gamepad_binding(action: StringName, desc: String) -> void:
	GamepadBindings.steal(gamepad_bindings, action, desc)
	gamepad_bindings[action] = desc
	GamepadBindings.apply_all(gamepad_bindings)
	save_settings()

## 恢复默认手柄键位（页级唯一恢复口）。
func reset_gamepad_bindings() -> void:
	gamepad_bindings = GamepadBindings.defaults()
	GamepadBindings.apply_all(gamepad_bindings)
	save_settings()

func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("input", "mouse_sensitivity", mouse_sensitivity)
	cfg.set_value("input", "gamepad_sensitivity", gamepad_sensitivity)
	cfg.set_value("input", "ads_sens_mult", ads_sens_mult)
	for action in GamepadBindings.ACTIONS:
		cfg.set_value("input", "bind_" + String(action), String(gamepad_bindings.get(action, "")))
	cfg.set_value("video", "quality", graphics_quality)
	cfg.set_value("fx", "muzzle_flash", muzzle_flash_enabled)
	cfg.set_value("fx", "tracer", tracer_enabled)
	cfg.set_value("fx", "hit_marker", hit_marker_enabled)
	cfg.set_value("fx", "hit_flash", hit_flash_enabled)
	cfg.set_value("recoil", "gun_rifle", recoil_gun_rifle)
	cfg.set_value("recoil", "gun_pistol", recoil_gun_pistol)
	cfg.set_value("recoil", "cam_rifle", recoil_cam_rifle)
	cfg.set_value("recoil", "cam_pistol", recoil_cam_pistol)
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
	cfg.set_value("bot", "attack_slide", bot_attack_slide_enabled)
	cfg.set_value("bot", "respawn_slide", bot_respawn_slide_enabled)
	cfg.set_value("bot", "slide_jump", bot_slide_jump_enabled)
	cfg.set_value("bot", "slide_jump_prob", bot_slide_jump_prob)
	cfg.set_value("bot", "jump_enabled", bot_jump_enabled)
	cfg.set_value("bot", "jump_min", bot_jump_min)
	cfg.set_value("bot", "jump_max", bot_jump_max)
	cfg.set_value("duel", "lifesteal", lifesteal_enabled)
	cfg.set_value("timer", "enabled", timer_enabled)
	cfg.set_value("timer", "auto_adjust_radius", auto_adjust_radius)
	cfg.set_value("timer", "play_seconds", timer_play_seconds)
	cfg.set_value("timer", "rest_seconds", timer_rest_seconds)
	cfg.set_value("timer", "repeat", timer_repeat)
	# 预设表：独立于全局设置的命名快照 + 选中的预设名（空串 = 默认预设）
	var preset_data := presets.to_dict()
	cfg.set_value("presets", "table", preset_data["presets"])
	cfg.set_value("presets", "active", preset_data["active"])
	cfg.save(PATH)

# ---- 预设（票 03 第 4 节 / CONTEXT.md「预设」「活文档」）----

## 取当前 26 项的预设快照（字段清单唯一来源是 `PresetStore.FIELDS`，不在此重复列举）。
func capture_preset() -> Dictionary:
	var values := {}
	for field in PresetStore.FIELDS:
		values[field] = get(field)
	return values

## 把一份 26 项快照写进全局设置（切预设用；不走 `write_param`，避免触发写回）。
func apply_preset(values: Dictionary) -> void:
	for field in PresetStore.FIELDS:
		if values.has(field):
			set(field, values[field])

func preset_names() -> PackedStringArray:
	return presets.names()

## 当前选中的预设名；空串 = 「不选预设」（全局设置本身）。
func active_preset() -> String:
	return presets.active()

## 选中预设：19 项加载进全局设置并持久化；空名 / 不存在则回落「不选预设」。
func select_preset(name: String) -> void:
	if not name.is_empty() and presets.has(name):
		apply_preset(presets.capture(name))
	presets.select(name)
	save_settings()

## 把当前 19 项存为新预设并自动选中；空名或重名返回 false。
func save_preset(name: String) -> bool:
	if not presets.store(name, capture_preset()):
		return false
	save_settings()
	return true

## 删除预设；删的是当前选中则回落「不选预设」。
func erase_preset(name: String) -> void:
	presets.erase(name)
	save_settings()

## 设置一项并持久化；若当前选中预设且该项属于「预设」26 项，改动自动写回该预设（活文档）。
func write_param(prop: StringName, value: Variant) -> void:
	set(prop, value)
	if PresetStore.FIELDS.has(String(prop)):
		presets.write_back(capture_preset())
	save_settings()