## 主场景：把场地、玩家、靶、HUD、界面与设置串成完整闭环。
##
## 开火判定、伤害、双方的刷新与特效都收在这里——它是唯一同时握着玩家、设置、场地与物理空间
## 的地方；`Target` 只做 AI 的碰撞载体与表现层（ADR-0009 三层分离）。
##
## 舞台机（票 03）：主菜单 → 对局 → 结算；「间隔计时器」开启时走
## 准备段 → 游玩段 → 休息段 → … → 最终结算（无尾休息）。计时会话只能从主菜单「开始」触发，
## 结算屏「新开一局」永远是普通对局（CONTEXT「间隔计时器」）。

extends Node3D

## 舞台：主菜单 / 对局（普通或计时游玩段共用）/ 计时准备段 / 计时休息段 / 结算。
enum Stage { MENU, PLAY, TIMER_PREPARE, TIMER_REST, SETTLEMENT }

const FIRE_RANGE := 3000.0 ## 射线最大长度（与相机远裁剪面同量级）
const FLASH_LIFE := 0.05 ## 枪口火光存活时长（秒，取自参考实现 flashTotal）
const TRACER_LIFE := 0.1 ## 曳光弹飞行全程时长（秒，取自参考实现 tracerTotal）
const TRACER_SEG := 12.0 ## 飞行弹段的视觉长度（ADR-0021 五轮：弹丸短亮条，非全长静止线）
const TRACER_MISS_LEN := 200.0 ## 未命中时曳光弹的固定长度
const TRACER_WIDTH := 0.4 ## 曳光弹宽度（取自参考实现 tracerWidth）
const FLASH_RADIUS := 4.0 ## 火光半径（参考实现火光贴图 8u 见方 → 半径 4）
const FLASH_PEAK_ENERGY := 5.0
const FLASH_HIDE_THRESHOLD := 0.02 ## 火光体积收敛到此以下直接隐藏（ADR-0021 开镜只留照亮）
const SPAWN_SPREAD := PI / 2.0 ## 刷新方向的随机扇角（±90°，CONTEXT「刷新」）
const SPAWN_ATTEMPTS := 12
const SPAWN_CLEARANCE := 30.0 ## 刷新点与遮挡物的最小余量
const SPAWN_BOUNDARY_MARGIN := 60.0 ## 刷新点与场地边界的最小余量
const BOT_TRACER_HEIGHT := 33.0 ## bot 曳光终点高度（玩家身体中段，纯视觉）
const RESPAWN_OFFSET_MARGIN := PI / 36.0 ## 「玩家重生」朝向的额外缓冲（5°）
const TIMER_DT_CLAMP := 0.1 ## 计时器单帧最大推进量：保证 `tick` 每帧最多跨一个整秒边界

## 碰撞层（票 02）：世界（地面 / 遮挡物）/ 靶命中体 / 玩家本体。靶的**移动本体**另占一层
## （`Target.MOVE_LAYER`）且不在任何射线的 mask 里——命中体与移动碰撞体是两件事（ADR-0014）。
const WORLD_LAYER := 1
const BOT_LAYER := 2
const PLAYER_LAYER := 4

## 音频：五份定频资产入库，音高微差靠播放器 pitch_scale，不预生成变体（ADR-0012）。
## 音量与爆头音高取自参考实现 playShotSound / playHitSound / playKillSound。
const SHOT_SOUND := "res://assets/audio/shot.wav"
const HIT_SOUND := "res://assets/audio/hit.wav"
const KILL_SOUND := "res://assets/audio/kill.wav"
const PRE_BEEP_SOUND := "res://assets/audio/pre_beep.wav"
const START_BEEP_SOUND := "res://assets/audio/start_beep.wav"
const RESPAWN_SOUND := "res://assets/audio/respawn.wav"
const SHOT_VOLUME := 0.18
const HIT_VOLUME := 0.29
const HEADSHOT_VOLUME := 0.36
const KILL_VOLUME := 0.42
const PRE_BEEP_VOLUME := 0.26
const START_BEEP_VOLUME := 0.32
const RESPAWN_VOLUME := 0.32
## 刷新音 3D 衰减基准（ADR-0019）：拉到 400 保证「目标距离」上限 800u 处仍可闻——
## 方位感由声像偏移给出，音量只在远近距离间小幅收敛，不做 2D 保底双播。
const RESPAWN_UNIT_SIZE := 400.0
const RESPAWN_HEIGHT := BOT_TRACER_HEIGHT ## 刷新音高度 = bot 身体中段，与曳光终点同一口径
const PITCH_JITTER := 0.05 ## ±5% 音高微差
const HEADSHOT_PITCH := 1.122462 ## 2^(2/12)，爆头 +2 半音
const PRE_BEEP_SECONDS := 5 ## 「预哔」：环节切换前 5 秒每秒一声

## 一组「枪口火光 + 曳光弹」表现节点：玩家与 bot 各一组，互不抢用。
class Fx:
	var flash: MeshInstance3D
	var light: OmniLight3D
	var tracer: MeshInstance3D
	var flash_left := 0.0
	var tracer_left := 0.0
	## 飞行弹段状态（ADR-0021 五轮）：出膛点/弹道方向/全程长在落位帧定死——弹段出膛后
	## 钉死弹道，不跟枪不跟发射者（物理正确）；存活期由 `_tick_fx` 沿弹道推进、到达即消失。
	var tracer_from := Vector3.ZERO
	var tracer_dir := Vector3.FORWARD
	var tracer_len := 0.0
	var tracer_seg := 0.0 ## 弹段长度：min(TRACER_SEG, tracer_len)，近距弹道截断
	## 是否命中 bot（ADR-0021 四轮保留）：true 时弹段终点每帧用 `tracer_to_local`（命中体
	## 局部坐标）换算回世界——bot 走了弹段追着飞到它身上；false 时沿直线飞到全程终点。
	var tracer_on_bot := false
	var tracer_to_local := Vector3.ZERO

@onready var arena: Arena = $Arena
@onready var player: Player = $Player
@onready var target: Target = $Target
@onready var hud: Hud = $HudLayer/Hud
@onready var timer_overlay: TimerOverlay = $HudLayer/TimerOverlay
@onready var main_menu: MainMenu = $HudLayer/MainMenu
@onready var settlement: SettlementScreen = $HudLayer/SettlementScreen
@onready var settings_panel: SettingsPanel = $HudLayer/SettingsPanel
@onready var world_env: WorldEnvironment = $WorldEnvironment
@onready var sun: DirectionalLight3D = $Sun

var match_state := DuelMatch.new()
var stage: Stage = Stage.MENU

var _timer := IntervalTimer.new()
## 本次对局是不是「计时会话」里的游玩段（决定 ESC / 段结束的结算口径）。
var _timer_active := false
## 「演示模式」（ADR-0033）：F2 在「对局」中切换的会话级开关——视角与开火交给脚本、
## 左下角字幕提示；不持久化、不进「设置」，离开对局自动关闭。
var _demo_mode := false
## 刚结束那一段的战绩（休息覆盖层显示「本轮战绩」）。
var _last_round_stats: IntervalTimer.RoundStats = null
## 本次会话的自动调径记录（「半径 旧→新」逐段追加，最终结算一并列出）。
var _radius_log: Array[String] = []

var _fx: Fx
var _bot_fx: Fx
## 玩家本帧待播的开火特效（ADR-0021）：物理帧只记命中终点，渲染帧等枪体位姿定稿再播。
var _pending_player_fx := false
var _pending_player_impact := Vector3.ZERO
## 本发是否命中 bot（ADR-0021 四轮）：命中时曳光终点绑命中体（局部坐标跟随），
## 未命中/遮挡则终点钉世界位置。
var _pending_player_on_bot := false

var _shot_audio: AudioStreamPlayer
var _hit_audio: AudioStreamPlayer
var _kill_audio: AudioStreamPlayer
var _pre_beep_audio: AudioStreamPlayer
var _start_beep_audio: AudioStreamPlayer
var _respawn_audio: AudioStreamPlayer3D ## 刷新三维定位音（ADR-0019）：全套音效里唯一带方位感的
## 进独占全屏前的窗口尺寸（ADR-0029）：退回窗口化时恢复。
var _pre_fullscreen_size := Vector2i.ZERO

## 每帧装配一次的 bot 感知；玩家开火（物理帧）也复用它，不必重算。
var _perception := BotAi.Perception.new()

func _ready() -> void:
	hud.bind(match_state)
	_build_fx()
	_build_audio()
	player.shot_fired.connect(_on_shot_fired)
	# 玩家开火特效延迟到 viewmodel 位姿定稿（pose_applied）后采样（ADR-0021）。
	player.viewmodel.pose_applied.connect(_sync_player_fx)
	settings_panel.opened.connect(_refresh_input)
	settings_panel.closed.connect(_refresh_input)
	# 主菜单提示随「间隔计时器」开关即时刷新（CONTEXT「主菜单」）：设置一关立刻重算。
	settings_panel.closed.connect(main_menu.refresh_hint)
	settings_panel.changed.connect(_apply_settings)
	# 「全屏宽高比」在全屏状态下切档 → 立即重设分辨率（ADR-0029）。
	settings_panel.fullscreen_aspect_changed.connect(_apply_fullscreen_resolution)
	main_menu.start_pressed.connect(_on_menu_start)
	main_menu.settings_pressed.connect(func() -> void: settings_panel.toggle())
	settlement.new_round_pressed.connect(_start_duel)
	settlement.menu_pressed.connect(_show_menu)
	_apply_settings()
	_show_menu()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		GameSettings.save_settings()

## 靶的推进放在**物理帧**（与 Player 同构）：`move_and_slide()` 用的是物理帧 delta，
## 若从 `_process` 调用，靶的移速会随显示刷新率变化（高刷屏上快好几倍）。
## 只有对局进行中才推进——主菜单 / 准备段 / 休息段 / 结算时靶被撤下且不结算。
func _physics_process(delta: float) -> void:
	if stage != Stage.PLAY:
		# 离开对局即自动关闭演示模式（ADR-0033）：准备 / 休息 / 结算 / 主菜单都不留它开着。
		if _demo_mode:
			_set_demo(false)
		return
	_build_perception()
	for hit in target.tick(delta, _perception):
		_resolve_bot_shot(hit)
	if target.needs_respawn():
		_respawn_target()
	match_state.bot_hp = target.hp()
	if _demo_mode:
		# 演示模式（ADR-0033 / ADR-0034）：把本帧的锁定点与「可见性」喂给玩家（推在本节点 tick
		# 之后、玩家 tick 之前）。锁定点是 bot 命中体躯干中心的世界坐标——躺姿压深与铲跳升空
		# 一并跟随，否则准星会锁在空气上、自动开火打空。bot 死亡空窗期喂「无目标」：相机冻结
		# 保持，重生后从当前姿态重新限速甩向新生点；被「遮挡物」/「围墙」挡住则喂「不可见」：
		# 不锁定、不按住开火，拉枪带惯性滑行收住。
		player.set_demo_target(target.aim_point_world(), target.ai.alive, _player_sees_target())

## 表现与热键留在渲染帧：特效的存活时长按渲染 delta 走，不必跟物理帧对齐。
func _process(delta: float) -> void:
	if stage == Stage.PLAY:
		match_state.elapsed += delta
	hud.set_zoom(player.zoom_p) # 准星淡出随开镜进度（票 07）
	if _timer_active:
		_drive_timer(minf(delta, TIMER_DT_CLAMP))
	_tick_fx(_fx, delta, 1.0 - player.zoom_p)
	_tick_fx(_bot_fx, delta)
	_tick_hotkeys()

func _tick_hotkeys() -> void:
	# 改键采集期间热键全部让位（ADR-0025）：Back/Tab/Esc 是可绑键，此刻只归采集——
	# 轮询读的是 Input 单例的既有动作状态，吞事件拦不住它，必须在源头短路。
	if settings_panel.is_capturing():
		return
	if Input.is_action_just_pressed("toggle_fullscreen"):
		_toggle_fullscreen()
	if Input.is_action_just_pressed("toggle_demo"):
		_toggle_demo()
	if Input.is_action_just_pressed("toggle_settings"):
		settings_panel.toggle()
		return
	if Input.is_action_just_pressed("ui_cancel"):
		_on_escape()

## F11 切换 窗口 ↔ 独占全屏（ADR-0019/0029）：会话级热键，不持久化、任何舞台可用。
## Godot 4.7 的独占全屏**不做显示模式切换**（window_set_mode 强制窗口尺寸 = 屏幕分辨率，
## ChangeDisplaySettings 零调用），16:10 档拉伸改走引擎内 content scale：
## 按 16:10 渲染再横向拉满原生屏幕（CS/Apex stretched 语义）。进全屏前记住窗口
## 尺寸、退回时恢复。
func _toggle_fullscreen() -> void:
	var window := get_window()
	if window.mode == Window.MODE_EXCLUSIVE_FULLSCREEN:
		window.mode = Window.MODE_WINDOWED
		_apply_fullscreen_stretch(Vector2i.ZERO, Vector2i.ZERO) # 全零 = 无条件关拉伸
		window.size = _pre_fullscreen_size
		return
	_pre_fullscreen_size = window.size
	window.mode = Window.MODE_EXCLUSIVE_FULLSCREEN
	var screen := DisplayServer.screen_get_size(window.current_screen)
	_apply_fullscreen_stretch(screen, GameSettings.fullscreen_resolution(screen, GameSettings.fullscreen_aspect))

## F2 演示模式（ADR-0033）：**只在「对局」中可切**（主菜单 / 准备段 / 休息段 / 结算 /
## 设置面板按下均无反应），会话级、不持久化、不进「设置」面板；离开对局由
## `_physics_process` 自动关闭（字幕随之消失）。
func _toggle_demo() -> void:
	if stage != Stage.PLAY or settings_panel.visible:
		return
	_set_demo(not _demo_mode)

## 开关落到两处：玩家接管视角 / 开火（`demo_active`），HUD 左下角状态字幕。
func _set_demo(on: bool) -> void:
	_demo_mode = on
	player.demo_active = on
	hud.set_demo_active(on)

## 「全屏宽高比」切档时由设置面板触发（ADR-0029）：正在独占全屏则立即按新档位
## 重设引擎内拉伸；窗口化则仅由下次 F11 生效。
func _apply_fullscreen_resolution() -> void:
	if get_window().mode != Window.MODE_EXCLUSIVE_FULLSCREEN:
		return
	var screen := DisplayServer.screen_get_size(get_window().current_screen)
	_apply_fullscreen_stretch(screen, GameSettings.fullscreen_resolution(screen, GameSettings.fullscreen_aspect))

## 按档位设置引擎内拉伸（ADR-0029）：渲染尺寸 == 屏幕原生（16:9 档）或全零（退出
## 全屏）时关闭拉伸、回到默认直渲；否则 VIEWPORT + IGNORE，把 16:10 画面横向
## 拉满 16:9 屏（拉伸对 3D 与 UI 一体生效，武器视口随画布同步，见 ADR-0029）。
func _apply_fullscreen_stretch(screen_size: Vector2i, render_size: Vector2i) -> void:
	var window := get_window()
	if render_size == Vector2i.ZERO or render_size == screen_size:
		window.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
		return
	window.content_scale_size = render_size
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT

## ESC：菜单 / 结算下不做事；对局与计时会话的任一阶段都结束本局并给出结算。
func _on_escape() -> void:
	if settings_panel.visible:
		settings_panel.toggle()
		return
	match stage:
		Stage.PLAY, Stage.TIMER_PREPARE, Stage.TIMER_REST:
			_end_session()

## 输入闸门：只有「对局进行中且设置面板没打开」时才captured 键鼠（ADR-0003 的输入独占不变）。
func _refresh_input() -> void:
	var playing := stage == Stage.PLAY and not settings_panel.visible
	player.input_enabled = playing
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if playing else Input.MOUSE_MODE_VISIBLE

# ---- 舞台切换 ----

## 主菜单（CONTEXT「主菜单」）：撤下靶、取消计时会话、交还鼠标。
func _show_menu() -> void:
	stage = Stage.MENU
	_timer_active = false
	_timer.cancel()
	target.despawn()
	timer_overlay.hide_overlay()
	settlement.visible = false
	main_menu.open()
	_refresh_input()

func _on_menu_start() -> void:
	main_menu.visible = false
	if GameSettings.timer_enabled:
		_start_timer_session()
	else:
		_start_duel()

## 普通对局（含结算屏「新开一局」）：无计时，无尽练习。
func _start_duel() -> void:
	_timer_active = false
	_timer.cancel()
	_radius_log.clear()
	_last_round_stats = null
	main_menu.visible = false
	settlement.visible = false
	timer_overlay.hide_overlay()
	_begin_play_round()

## 计时会话（CONTEXT「计时会话」）：先进入准备段，5 秒后自动开始第一游玩段。
func _start_timer_session() -> void:
	_timer_active = true
	_radius_log.clear()
	_last_round_stats = null
	settlement.visible = false
	_timer.start(GameSettings.timer_play_seconds, GameSettings.timer_rest_seconds, GameSettings.timer_repeat)
	stage = Stage.TIMER_PREPARE
	match_state.reset()
	target.despawn()
	timer_overlay.show_prepare(IntervalTimer.PREPARE_SECONDS)
	_play_sound(_pre_beep_audio, PRE_BEEP_VOLUME, 1.0) # 准备段第一秒也发一声
	_refresh_input()

## 开始一个游玩段：每段 = 新的一局（对局数据清零重计，CONTEXT「游玩段」）。
func _begin_play_round() -> void:
	match_state.reset()
	stage = Stage.PLAY
	timer_overlay.hide_overlay()
	_respawn_target()
	_refresh_input()

# ---- 计时会话 ----

func _drive_timer(dt: float) -> void:
	var event := _timer.tick(dt)
	match event.type:
		IntervalTimer.Event.SECOND:
			if event.remaining <= PRE_BEEP_SECONDS:
				_play_sound(_pre_beep_audio, PRE_BEEP_VOLUME, 1.0)
			timer_overlay.set_seconds(event.remaining)
		IntervalTimer.Event.PREPARE_END:
			_play_sound(_start_beep_audio, START_BEEP_VOLUME, 1.0)
			_begin_play_round()
		IntervalTimer.Event.PLAY_END:
			_end_play_round(event.last)
		IntervalTimer.Event.REST_END:
			_play_sound(_start_beep_audio, START_BEEP_VOLUME, 1.0)
			_begin_play_round()

## 游玩段结束：累计本段战绩 → 自动调径 → 进休息段或直接结算（无尾休息）。
func _end_play_round(is_last: bool) -> void:
	_accumulate_round()
	_apply_auto_radius()
	if is_last:
		_show_settlement(true)
	else:
		_begin_rest()

func _begin_rest() -> void:
	stage = Stage.TIMER_REST
	_play_sound(_start_beep_audio, START_BEEP_VOLUME, 1.0) # 休息开始与游玩开始共用同一「开始哔」
	target.despawn()
	timer_overlay.show_rest(
		_timer.rest_seconds, _timer.round, _timer.repeat, _round_stats_text(), _radius_log
	)
	_refresh_input()

## 把本局数据计入会话累计（CONTEXT「游玩段」）。
func _accumulate_round() -> void:
	var stats := IntervalTimer.RoundStats.new()
	stats.kills = match_state.kills
	stats.shots = match_state.shots
	stats.hits = match_state.hits
	stats.deaths = match_state.deaths
	stats.seconds = match_state.elapsed
	_last_round_stats = stats
	_timer.accumulate(stats)

## 自动调径（CONTEXT「自动调径」）：按本段准确率调整「体型半径」，本段 0 发则跳过。
## `write_param` 会在选中预设时写回该预设的半径，否则写全局设置。
func _apply_auto_radius() -> void:
	if not GameSettings.auto_adjust_radius:
		return
	var accuracy := match_state.accuracy()
	if accuracy < 0.0:
		return
	var old_radius := GameSettings.body_radius
	var fresh := clampf(
		roundf(AutoRadius.adjust(old_radius, accuracy / 100.0)),
		Physique.BODY_RADIUS_MIN,
		Physique.BODY_RADIUS_MAX
	)
	if not is_equal_approx(fresh, old_radius):
		GameSettings.write_param(&"body_radius", fresh)
		target.apply_body_radius(fresh)
	# 每段（含末段）都追加一行；只有本段 0 发才跳过（accuracy < 0 已在上方提前返回）
	_radius_log.append("半径 %d → %d" % [int(old_radius), int(fresh)])

func _round_stats_text() -> String:
	var stats := _last_round_stats
	if stats == null:
		return ""
	var acc := DuelMatch.accuracy_percent(stats.hits, stats.shots)
	var accuracy := "—" if acc < 0.0 else "%.1f%%" % acc
	return (
		"本轮：击杀 %d　命中 %d/%d　准确率 %s　死亡 %d"
		% [stats.kills, stats.hits, stats.shots, accuracy, stats.deaths]
	)

## 结束本局 / 整个计时会话（ESC 等价）：计时会话按**会话累计**结算，普通对局按本局快照结算。
func _end_session() -> void:
	if _timer_active:
		if _timer.phase == IntervalTimer.Phase.PLAY:
			_accumulate_round()
			_apply_auto_radius()
		_timer.cancel()
	_show_settlement(_timer_active)

func _show_settlement(from_timer: bool) -> void:
	stage = Stage.SETTLEMENT
	_timer_active = false
	target.despawn()
	timer_overlay.hide_overlay()
	var lines: Array = []
	if from_timer:
		var minutes := int(_timer.total_play_seconds) / 60
		var seconds := int(_timer.total_play_seconds) % 60
		lines.append("会话累计准确率：%s" % _accuracy_text(_timer.total_accuracy()))
		lines.append("击杀：%d　　死亡：%d" % [_timer.total_kills, _timer.total_deaths])
		lines.append("游玩时长：%02d:%02d" % [minutes, seconds])
		lines.append_array(_radius_log)
	else:
		var snapshot := match_state.settle()
		var minutes := int(snapshot.elapsed) / 60
		var seconds := int(snapshot.elapsed) % 60
		lines.append("准确率：%s" % _accuracy_text(snapshot.accuracy))
		lines.append("击杀：%d　　死亡：%d" % [snapshot.kills, snapshot.deaths])
		lines.append("用时：%02d:%02d" % [minutes, seconds])
	settlement.show_result(lines)
	_refresh_input()

## 「—」表示无数据；否则一位小数、不带百分号（CONTEXT「结算快照」）。
func _accuracy_text(value: float) -> String:
	return "—" if value < 0.0 else "%.1f" % value

# ---- 设置 ----

func _apply_settings() -> void:
	var avoid: Array = [Vector2(player.global_position.x, player.global_position.z)]
	if target.ai.alive:
		avoid.append(Vector2(target.global_position.x, target.global_position.z))
	arena.configure(GameSettings.arena_layout, avoid)
	target.apply_body_radius(GameSettings.body_radius)
	# 躲避配置与 `Target` 共用同一实例，就地刷新即可实时生效
	GameSettings.apply_avoidance_config(target.config)
	_apply_quality()

## 「画面质量」两档映射到后处理开关与阴影精度（CONTEXT「画面质量」；
## SDFGI / SSIL / 体积雾是性能大户，低档全关）。
func _apply_quality() -> void:
	var low := GameSettings.graphics_quality == GameSettings.Quality.LOW
	var env := world_env.environment
	env.glow_enabled = not low
	env.ssao_enabled = not low
	env.ssil_enabled = false
	env.sdfgi_enabled = false
	env.ssr_enabled = false
	env.volumetric_fog_enabled = false
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.0 if low else 1.06
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 300.0 if low else 800.0
	RenderingServer.directional_shadow_atlas_set_size(1024 if low else 4096, true)

# ---- 靶：刷新 ----

func _respawn_target() -> void:
	var at := _pick_spawn()
	target.spawn(Vector2(at.x, at.z))
	_play_respawn_sound() # 「刷新音效」（ADR-0019）：每次刷新都响，含开局首刷
	# 「重生滑铲」（ADR-0016）：刷新瞬间沿玩家连线垂直方向滑出，探测长度与「前向探测」同一口径。
	if GameSettings.bot_respawn_slide_enabled:
		target.ai.try_respawn_slide(
			Vector2(player.global_position.x, player.global_position.z),
			BotAi.probe_length_for(GameSettings.arena_layout),
			GameSettings.bot_slide_jump_enabled,
			GameSettings.bot_slide_jump_prob
		)

## 刷新音（ADR-0019）：三维定位音挂在 bot 刷新点，玩家凭声像判断方位。
func _play_respawn_sound() -> void:
	if _respawn_audio.stream == null:
		return
	_respawn_audio.global_position = Vector3(
		target.global_position.x, RESPAWN_HEIGHT, target.global_position.z
	)
	_respawn_audio.play()

## 在玩家前方 ±90° 的半圆弧上取「目标距离」处的点：避开围墙、遮挡物，
## 且不落在玩家当前的「瞄准视锥」内（票 02 验收 8）。
## 点越出场地时沿场心方向缩回界内（ADR-0030，与「刷新」词条 / `_pick_player_spawn` 同款）——
## 目标距离可设到场地直径，出生弧整段越界时落回「尽可能远」而非作废重试或落点出界。
func _pick_spawn() -> Vector3:
	var dist := GameSettings.target_range
	var limit := MovementSimulator.ARENA_RADIUS - SPAWN_BOUNDARY_MARGIN
	for attempt in SPAWN_ATTEMPTS:
		var a := player.yaw + randf_range(-SPAWN_SPREAD, SPAWN_SPREAD)
		var dir := Vector3(-sin(a), 0.0, -cos(a))
		var p := player.global_position + dir * dist
		var flat := Vector2(p.x, p.z).limit_length(limit)
		if arena.is_blocked(flat, SPAWN_CLEARANCE):
			continue
		if _player_aims_at(flat):
			continue
		return Vector3(flat.x, 0.0, flat.y)
	var fallback := Vector3(-sin(player.yaw), 0.0, -cos(player.yaw))
	var fallback_flat := Vector2(
		player.global_position.x + fallback.x * dist, player.global_position.z + fallback.z * dist
	).limit_length(limit)
	return Vector3(fallback_flat.x, 0.0, fallback_flat.y)

## 玩家当前的视线是否正落在这个平面点上（「瞄准视锥」与 bot 自己用的是同一套判据）。
func _player_aims_at(p: Vector2) -> bool:
	return BotAi.in_aim_cone(
		player.global_position.x,
		player.global_position.z,
		player.eye_position().y,
		player.yaw,
		player.pitch,
		GameSettings.body_radius,
		p.x,
		p.y,
	)

# ---- 玩家：重生 ----

## 玩家 HP 归零（CONTEXT「玩家重生」）：满血重生到 bot 周边圆周点，朝向偏置到视锥之外；
## bot 血量回满（正处死亡倒计时则立即复活），攻击锁定解除。
func _respawn_player() -> void:
	match_state.record_death()
	match_state.player_hp = DuelMatch.MAX_HP

	var bot_flat := Vector2(target.global_position.x, target.global_position.z)
	var at := _pick_player_spawn(bot_flat)
	player.sim.reset(at)
	player.global_position = Vector3(at.x, 0.0, at.y)

	var to_bot := bot_flat - at
	if to_bot.length() > 1e-6:
		var horiz := to_bot.length()
		# 偏置下限 = 视锥半角 + bot 通体半宽角 + 缓冲（任何距离/体型下朝向都落在视锥外）
		var min_offset := BotAi.AIM_CONE_HALF + atan2(GameSettings.body_radius, horiz) + RESPAWN_OFFSET_MARGIN
		var spread := maxf(0.0, SPAWN_SPREAD - min_offset)
		var offset := (min_offset + randf() * spread) * (1.0 if randf() < 0.5 else -1.0)
		player.yaw = atan2(-to_bot.x, -to_bot.y) + offset
		player.pitch = 0.0 # bot 头心与玩家眼高同为 66，平视即对准

	target.ai.stop_firing()
	if target.ai.alive:
		target.ai.hp = BotAi.MAX_HP
	else:
		_respawn_target()

## 玩家重生点：以 bot 为圆心、「目标距离」为半径的圆周随机点，越出场地沿方向缩回、避开遮挡物。
func _pick_player_spawn(center: Vector2) -> Vector2:
	var radius := GameSettings.target_range
	var limit := MovementSimulator.ARENA_RADIUS - SPAWN_BOUNDARY_MARGIN
	for attempt in SPAWN_ATTEMPTS:
		var a := randf() * TAU
		var p := (center + Vector2(cos(a), sin(a)) * radius).limit_length(limit)
		if not arena.is_blocked(p, SPAWN_CLEARANCE):
			return p
	return center # 兜底：实在找不到就贴着 bot 重生

# ---- 开火：玩家 ----

func _on_shot_fired(id: StringName) -> void:
	var origin := player.eye_position()
	var direction := player.aim_direction()
	# mask 含靶层：命中靶本体；世界层仍参与（遮挡物挡枪）
	var ray := PhysicsRayQueryParameters3D.create(
		origin, origin + direction * FIRE_RANGE, WORLD_LAYER | BOT_LAYER
	)
	ray.exclude = [player.get_rid()]
	var hit := player.get_world_3d().direct_space_state.intersect_ray(ray)

	var impact := origin + direction * TRACER_MISS_LEN
	var shot_target: Target = null
	var headshot := false
	if not hit.is_empty():
		impact = hit["position"]
		# 靶的命中体是靶本体的子节点（ADR-0014）：命中体只负责「打得到」，移动由靶本体求解。
		var body := hit["collider"] as CollisionObject3D
		if body != null and body == target.hit_body():
			shot_target = target
			# 命中形状所属部件名含 head/helmet 即爆头（靶命中体由模型部件几何构成）
			headshot = Target.is_headshot(body, hit["shape"])

	_play_sound(_shot_audio, SHOT_VOLUME, _shot_pitch() * Weapon.sound_pitch(id)) ## 枪声两分支同款，上提
	if shot_target == null:
		match_state.record_shot(false)
	else:
		var damage := Weapon.headshot_damage(id) if headshot else Weapon.body_damage(id)
		match_state.record_shot(true)
		_play_sound(
			_hit_audio,
			HEADSHOT_VOLUME if headshot else HIT_VOLUME,
			HEADSHOT_PITCH if headshot else 1.0
		)
		if GameSettings.lifesteal_enabled:
			match_state.heal_player(damage) # 「吸血」：按本次伤害回血，封顶 600
		if shot_target.take_hit(damage, _perception):
			match_state.record_kill()
			match_state.player_hp = DuelMatch.MAX_HP # 击杀回满（与吸血叠加，不溢出）
			_play_sound(_kill_audio, KILL_VOLUME, 1.0) # 与击中音叠加
			hud.flash(HitMarkerTiming.KIND_KILL)
		else:
			hud.flash(HitMarkerTiming.KIND_HIT)
	# 特效延后到渲染帧播放（ADR-0021）：物理帧只记命中终点。
	_pending_player_impact = impact
	_pending_player_on_bot = shot_target != null
	_pending_player_fx = true

## 玩家开火特效的渲染帧落位（ADR-0021）：viewmodel 位姿定稿（后坐恢复已应用）后采样枪口，
## 特效起点与本帧渲染枪口逐像素重合；火光与光源在存活期内每帧跟随枪口（转身时火光是枪的一部分）。
## 曳光是飞行弹段（ADR-0021 五轮）：落位帧从枪口发出后钉死弹道，由 `_tick_fx` 统一推进，
## 这里不做曳光跟随。
func _sync_player_fx() -> void:
	if _pending_player_fx:
		_pending_player_fx = false
		_play_fx(
			_fx, player.muzzle_world(), _pending_player_impact, 1.0 - player.zoom_p,
			_pending_player_on_bot
		)
		return # 落位当帧位置已由 _play_fx 写好，存活帧才走下面的跟随
	if _fx.flash_left > 0.0:
		var muzzle := player.muzzle_world()
		_fx.flash.global_position = muzzle
		_fx.light.global_position = muzzle

# ---- 开火：bot ----

## bot 每发开火的结算：音效 → 枪口火光 → 曳光（bot 枪口 → 玩家当前坐标，纯视觉）→ 命中扣血。
## 曳光起点用 `muzzle_world_visual()`：铲跳升空时跟着抬（ADR-0018）；视线判定仍走地面口径。
## 曳光是飞行弹段（ADR-0021 五轮）：从 bot 枪口发出后钉死弹道，不跟随玩家跑动——
## 玩家侧与 bot 侧同构，推进统一走 `_tick_fx`。
func _resolve_bot_shot(hit: bool) -> void:
	var muzzle := target.muzzle_world_visual()
	_play_sound(_shot_audio, SHOT_VOLUME, _shot_pitch())
	_play_fx(
		_bot_fx,
		muzzle,
		Vector3(player.global_position.x, BOT_TRACER_HEIGHT, player.global_position.z)
	)
	if not hit:
		return
	hud.flash_hurt() # 「受击红屏」（ADR-0019）：被打侧的即时视觉反馈，与命中提示对偶
	if GameSettings.lifesteal_enabled:
		match_state.heal_bot(BotAi.BOT_DAMAGE) # 「吸血」：bot 命中固定回 25
	match_state.player_hp = maxi(0, match_state.player_hp - BotAi.BOT_DAMAGE)
	if _demo_mode:
		# 演示模式（ADR-0033）：bot 照常开枪、受击红屏照常，只把「死亡」冻住——血量封底 1、
		# 永不触发「玩家重生」，否则演示会被瞬移重生反复打断（观感与「照常开枪」的反馈都保留）。
		match_state.player_hp = maxi(1, match_state.player_hp)
		return
	if match_state.player_hp <= 0:
		_respawn_player()

# ---- bot 感知装配 ----

## 把玩家、设置与场地状态装进 `BotAi.Perception`（每帧一次；纯逻辑类不认识节点树）。
func _build_perception() -> void:
	var p := _perception
	p.player_x = player.global_position.x
	p.player_z = player.global_position.z
	p.player_eye_y = player.eye_position().y
	p.player_yaw = player.yaw
	p.player_pitch = player.pitch
	p.target_range = GameSettings.target_range
	p.wander_mode = GameSettings.bot_movement_mode == GameSettings.BotMovement.WANDER
	p.range_amp = GameSettings.bot_range_amp
	p.fire_enabled = GameSettings.bot_fire_enabled
	p.hit_rate = GameSettings.bot_hit_rate
	p.body_radius = GameSettings.body_radius
	# ADS 与 bot 滑铲互锁（ADR-0016）：任一滑铲开启时「bot 常驻开镜」失效——
	# 开镜封速 130 < 滑铲门槛 200，同时开启会把注入滑铲直接废掉。
	p.ads = GameSettings.bot_ads_enabled and not GameSettings.bot_slide_any_enabled()
	p.slide_attack = GameSettings.bot_attack_slide_enabled
	p.slide_jump = GameSettings.bot_slide_jump_enabled and GameSettings.bot_slide_any_enabled()
	p.slide_jump_prob = GameSettings.bot_slide_jump_prob
	p.jump_enabled = GameSettings.bot_jump_enabled
	p.jump_min = GameSettings.bot_jump_min
	p.jump_max = GameSettings.bot_jump_max
	p.jump_ras_prob = GameSettings.bot_jump_ras_prob
	p.line_of_sight = _bot_has_sight()
	p.dodge_chance = GameSettings.dodge_chance_for(player.weapon)
	p.arena_layout = GameSettings.arena_layout

## 「视线判定」（ADR-0006）：bot 枪口 → 玩家眼，先撞到的若不是玩家就是被遮挡物挡了。
func _bot_has_sight() -> bool:
	if not target.ai.alive:
		return false
	var query := PhysicsRayQueryParameters3D.create(
		target.muzzle_world(), player.eye_position(), WORLD_LAYER | PLAYER_LAYER
	)
	query.exclude = [target.get_rid()]
	var hit := player.get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit["collider"] == player

## 「可见性」（ADR-0034）：与「视线判定」方向相反——玩家眼位 → bot 瞄准点，先撞到的若不是
## bot 命中体就是被「遮挡物」/「围墙」挡了。只算几何遮挡、**不算** FOV（bot 不在画面里不算
## 看不见，相机本就一直在追它）；单根射线射向瞄准点，「锁定」与「开火」共用它。
func _player_sees_target() -> bool:
	var query := PhysicsRayQueryParameters3D.create(
		player.eye_position(), target.aim_point_world(), WORLD_LAYER | BOT_LAYER
	)
	query.exclude = [player.get_rid()]
	var hit := player.get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit["collider"] == target.hit_body()

# ---- 音频：定频资产入库，音高微差靠播放器 pitch_scale，不预生成变体（ADR-0012）----

func _build_audio() -> void:
	_shot_audio = _make_audio("ShotAudio", SHOT_SOUND)
	_hit_audio = _make_audio("HitAudio", HIT_SOUND)
	_kill_audio = _make_audio("KillAudio", KILL_SOUND)
	_pre_beep_audio = _make_audio("PreBeepAudio", PRE_BEEP_SOUND)
	_start_beep_audio = _make_audio("StartBeepAudio", START_BEEP_SOUND)
	_respawn_audio = AudioStreamPlayer3D.new()
	_respawn_audio.name = "RespawnAudio"
	if ResourceLoader.exists(RESPAWN_SOUND):
		_respawn_audio.stream = load(RESPAWN_SOUND)
	_respawn_audio.volume_db = linear_to_db(RESPAWN_VOLUME)
	_respawn_audio.unit_size = RESPAWN_UNIT_SIZE
	add_child(_respawn_audio)

func _make_audio(node_name: String, path: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = node_name
	if ResourceLoader.exists(path):
		player.stream = load(path)
	add_child(player)
	return player

## 枪声每发都叠 ±5% 音高微差（参考实现 setPlaybackRate(0.95 + random×0.1)）。
func _shot_pitch() -> float:
	return randf_range(1.0 - PITCH_JITTER, 1.0 + PITCH_JITTER)

## 命中/击杀用固定音高，爆头 +2 半音。
func _play_sound(player: AudioStreamPlayer, volume: float, pitch: float) -> void:
	if player.stream == null:
		return
	player.volume_db = linear_to_db(volume)
	player.pitch_scale = pitch
	player.play()

# ---- 特效：枪口火光 + 曳光弹（各受一个开关控制；玩家与 bot 各一组）----

func _build_fx() -> void:
	_fx = _make_fx("MuzzleFlash", "MuzzleLight", "Tracer")
	_bot_fx = _make_fx("BotMuzzleFlash", "BotMuzzleLight", "BotTracer")

func _make_fx(flash_name: String, light_name: String, tracer_name: String) -> Fx:
	var out := Fx.new()

	var flash_mesh := SphereMesh.new()
	flash_mesh.radius = FLASH_RADIUS
	flash_mesh.height = FLASH_RADIUS * 2.0
	flash_mesh.radial_segments = 10
	flash_mesh.rings = 5
	var flash_mat := StandardMaterial3D.new()
	flash_mat.albedo_color = Color(1.0, 0.78, 0.35)
	flash_mat.emission_enabled = true
	flash_mat.emission = Color(1.0, 0.72, 0.28)
	flash_mat.emission_energy_multiplier = 6.0
	flash_mesh.material = flash_mat
	out.flash = MeshInstance3D.new()
	out.flash.name = flash_name
	out.flash.mesh = flash_mesh
	out.flash.visible = false
	# 火光是发光体不是实体（票 05）：默认的 cast_shadow=ON 会让它在地面上投出短促光斑影。
	out.flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(out.flash)

	out.light = OmniLight3D.new()
	out.light.name = light_name
	out.light.light_color = Color(1.0, 0.78, 0.42)
	out.light.omni_range = 20.0
	out.light.light_energy = 0.0
	add_child(out.light)

	var tracer_mesh := BoxMesh.new()
	tracer_mesh.size = Vector3(TRACER_WIDTH, TRACER_WIDTH, 1.0) # 沿本地 −Z 延伸，长度靠网格改
	var tracer_mat := StandardMaterial3D.new()
	tracer_mat.albedo_color = Color(1.0, 0.95, 0.75)
	tracer_mat.emission_enabled = true
	tracer_mat.emission = Color(1.0, 0.85, 0.45)
	tracer_mat.emission_energy_multiplier = 3.0
	tracer_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	out.tracer = MeshInstance3D.new()
	out.tracer.name = tracer_name
	out.tracer.mesh = tracer_mesh
	out.tracer.material_override = tracer_mat
	out.tracer.visible = false
	# 同火光：曳光弹是发光弹道不是实体，不投影（票 05）。
	out.tracer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(out.tracer)
	return out

## `flash_damp`：火光体积收敛系数（ADR-0021）——玩家按 (1 − 开镜进度) 传入，满开镜时
## 只留点光源照亮、光斑体积隐藏；bot 走默认 1.0 不收敛。
## `on_bot`（ADR-0021 四轮）：终点是否命中 bot——true 时弹段追着 bot 身上命中点飞
## （`tracer_to_local` 每帧换算）；false 时沿直线飞到全程终点（未命中/遮挡）。
func _play_fx(fx: Fx, muzzle: Vector3, to: Vector3, flash_damp := 1.0, on_bot := false) -> void:
	if GameSettings.muzzle_flash_enabled:
		fx.flash_left = FLASH_LIFE
		fx.flash.global_position = muzzle
		fx.flash.scale = Vector3.ONE * flash_damp
		fx.flash.visible = flash_damp > FLASH_HIDE_THRESHOLD
		fx.light.global_position = muzzle
		fx.light.light_energy = FLASH_PEAK_ENERGY
	if GameSettings.tracer_enabled:
		var delta_v := to - muzzle
		var length := delta_v.length()
		if length > 0.001:
			fx.tracer_left = TRACER_LIFE
			# 飞行弹段（ADR-0021 五轮）：出膛点/方向/全程长落位帧定死，之后由 _tick_fx 推进
			fx.tracer_from = muzzle
			fx.tracer_dir = delta_v / length
			fx.tracer_len = length
			fx.tracer_seg = minf(TRACER_SEG, length)
			fx.tracer_on_bot = on_bot
			fx.tracer_to_local = target.tracer_hit_local(to) if on_bot else Vector3.ZERO
			_place_tracer_seg(fx, 0.0)

## 弹段落位（ADR-0021 五轮）：`head` = 弹段头端沿弹道的行进距离。发射初期段从枪口伸出
## （head < 段长时尾端钉在枪口、段长 = head），之后整段匀速推进，头端到达即整段消失。
func _place_tracer_seg(fx: Fx, head: float) -> void:
	var seg := minf(fx.tracer_seg, head)
	if seg <= 0.001:
		return
	var center := fx.tracer_from + fx.tracer_dir * (head - seg * 0.5)
	fx.tracer.global_position = center
	# 朝向交给 look_at，它把本地 −Z 对准弹道远端；up 在弹道接近竖直时换轴防共线
	var up := Vector3.UP if absf(fx.tracer_dir.y) < 0.99 else Vector3.FORWARD
	fx.tracer.look_at(center + fx.tracer_dir, up)
	# 长度写进网格本体（避免节点缩放在旋转基上产生歧义）
	(fx.tracer.mesh as BoxMesh).size = Vector3(TRACER_WIDTH, TRACER_WIDTH, seg)
	fx.tracer.visible = true

func _tick_fx(fx: Fx, delta: float, flash_damp := 1.0) -> void:
	if fx.flash_left > 0.0:
		fx.flash_left -= delta
		if fx.flash_left > 0.0:
			fx.light.light_energy = FLASH_PEAK_ENERGY * (fx.flash_left / FLASH_LIFE)
			# 火光体积逐帧重套收敛系数（ADR-0021）：存活期内开镜进度变化也跟着收敛。
			fx.flash.scale = Vector3.ONE * flash_damp
			fx.flash.visible = flash_damp > FLASH_HIDE_THRESHOLD
		else:
			fx.flash.visible = false
			fx.light.light_energy = 0.0
	# 飞行弹段推进（ADR-0021 五轮）：head 按「已飞行时间比例 × 当前全程长」线性推进，
	# 头端到达（tracer_left 归零）即整段消失。命中 bot 时终点每帧换算——弹段追着命中点飞，
	# bot 死亡/撤下（visible=false）后方向冻结为直线（0.1s 寿命内不会撞上 respawn 跳位）。
	if fx.tracer_left > 0.0:
		fx.tracer_left = maxf(fx.tracer_left - delta, 0.0)
		if fx.tracer_left <= 0.0:
			fx.tracer.visible = false
		else:
			if fx.tracer_on_bot and target.visible:
				var hit_to := target.tracer_hit_world(fx.tracer_to_local)
				fx.tracer_dir = (hit_to - fx.tracer_from).normalized()
				fx.tracer_len = (hit_to - fx.tracer_from).length()
				fx.tracer_seg = minf(TRACER_SEG, fx.tracer_len)
			var head := fx.tracer_len * (1.0 - fx.tracer_left / TRACER_LIFE)
			_place_tracer_seg(fx, minf(head, fx.tracer_len))