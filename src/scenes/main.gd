## 主场景：把场地、玩家、靶、HUD 与设置串成最小可玩闭环。
##
## 开火判定、伤害、双方的刷新与特效都收在这里——切片一只有一个受击体，不值得再拆一层。
## 切片二起靶有了完整 AI（`BotAi`），但**感知装配**留在本层：它是唯一同时握着玩家、设置、
## 场地与物理空间的地方；`Target` 只做 AI 的碰撞载体与表现层（ADR-0009 三层分离）。

extends Node3D

const FIRE_RANGE := 3000.0 ## 射线最大长度（与相机远裁剪面同量级）
const FLASH_LIFE := 0.05 ## 枪口火光存活时长（秒，取自参考实现 flashTotal）
const TRACER_LIFE := 0.1 ## 曳光弹存活时长（秒，取自参考实现 tracerTotal）
const TRACER_MISS_LEN := 200.0 ## 未命中时曳光弹的固定长度
const TRACER_WIDTH := 0.4 ## 曳光弹宽度（取自参考实现 tracerWidth）
const FLASH_RADIUS := 4.0 ## 火光半径（参考实现火光贴图 8u 见方 → 半径 4）
const FLASH_PEAK_ENERGY := 5.0
const SPAWN_SPREAD := PI / 2.0 ## 刷新方向的随机扇角（±90°，CONTEXT「刷新」）
const SPAWN_ATTEMPTS := 12
const SPAWN_CLEARANCE := 30.0 ## 刷新点与遮挡物的最小余量
const SPAWN_BOUNDARY_MARGIN := 60.0 ## 刷新点与场地边界的最小余量
const BOT_TRACER_HEIGHT := 33.0 ## bot 曳光终点高度（玩家身体中段，纯视觉）
const RESPAWN_OFFSET_MARGIN := PI / 36.0 ## 「玩家重生」朝向的额外缓冲（5°）

## 碰撞层（票 02）：世界（地面 / 遮挡物）/ 靶命中体 / 玩家本体。靶的**移动本体**另占一层
## （`Target.MOVE_LAYER`）且不在任何射线的 mask 里——命中体与移动碰撞体是两件事（ADR-0014）。
const WORLD_LAYER := 1
const BOT_LAYER := 2
const PLAYER_LAYER := 4

## 音频（票 01 第 9 节）：三份定频资产入库，音高微差靠播放器 pitch_scale，不预生成变体。
## 音量与爆头音高取自参考实现 playShotSound / playHitSound / playKillSound。
const SHOT_SOUND := "res://assets/audio/shot.wav"
const HIT_SOUND := "res://assets/audio/hit.wav"
const KILL_SOUND := "res://assets/audio/kill.wav"
const SHOT_VOLUME := 0.18
const HIT_VOLUME := 0.29
const HEADSHOT_VOLUME := 0.36
const KILL_VOLUME := 0.42
const PITCH_JITTER := 0.05 ## ±5% 音高微差
const HEADSHOT_PITCH := 1.122462 ## 2^(2/12)，爆头 +2 半音

## 一组「枪口火光 + 曳光弹」表现节点：玩家与 bot 各一组，互不抢用。
class Fx:
	var flash: MeshInstance3D
	var light: OmniLight3D
	var tracer: MeshInstance3D
	var flash_left := 0.0
	var tracer_left := 0.0

@onready var arena: Arena = $Arena
@onready var player: Player = $Player
@onready var target: Target = $Target
@onready var hud: Hud = $HudLayer/Hud
@onready var settings_panel: SettingsPanel = $HudLayer/SettingsPanel

var match_state := DuelMatch.new()

var _fx: Fx
var _bot_fx: Fx

var _shot_audio: AudioStreamPlayer
var _hit_audio: AudioStreamPlayer
var _kill_audio: AudioStreamPlayer

## 每帧装配一次的 bot 感知；玩家开火（物理帧）也复用它，不必重算。
var _perception := BotAi.Perception.new()

func _ready() -> void:
	hud.bind(match_state)
	_build_fx()
	_build_audio()
	player.shot_fired.connect(_on_shot_fired)
	settings_panel.opened.connect(_set_game_input.bind(false))
	settings_panel.closed.connect(_set_game_input.bind(true))
	settings_panel.changed.connect(_apply_settings)
	_apply_settings()
	_respawn_target()
	_build_perception()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		GameSettings.save_settings()

## 靶的推进放在**物理帧**（与 Player 同构）：`move_and_slide()` 用的是物理帧 delta，
## 若从 `_process` 调用，靶的移速会随显示刷新率变化（高刷屏上快好几倍）。
func _physics_process(delta: float) -> void:
	_build_perception()
	for hit in target.tick(delta, _perception):
		_resolve_bot_shot(hit)
	if target.needs_respawn():
		_respawn_target()
	match_state.bot_hp = target.hp()

## 表现与热键留在渲染帧：特效的存活时长按渲染 delta 走，不必跟物理帧对齐。
func _process(delta: float) -> void:
	match_state.elapsed += delta
	_tick_fx(_fx, delta)
	_tick_fx(_bot_fx, delta)
	_tick_hotkeys()

func _tick_hotkeys() -> void:
	if Input.is_action_just_pressed("toggle_settings"):
		settings_panel.toggle()
		return
	if Input.is_action_just_pressed("ui_cancel") and not settings_panel.visible:
		Input.mouse_mode = (
			Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
			else Input.MOUSE_MODE_CAPTURED
		)

func _set_game_input(on: bool) -> void:
	player.input_enabled = on
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE

# ---- 设置 ----

func _apply_settings() -> void:
	var avoid: Array = [Vector2(player.global_position.x, player.global_position.z)]
	if target.ai.alive:
		avoid.append(Vector2(target.global_position.x, target.global_position.z))
	arena.configure(GameSettings.arena_layout, avoid)
	target.apply_body_radius(GameSettings.body_radius)
	# 躲避配置与 `Target` 共用同一实例，就地刷新即可实时生效
	GameSettings.apply_avoidance_config(target.config)

# ---- 靶：刷新 ----

func _respawn_target() -> void:
	var at := _pick_spawn()
	target.spawn(Vector2(at.x, at.z))

## 在玩家前方 ±90° 的半圆弧上取「目标距离」处的点：避开围墙、遮挡物，
## 且不落在玩家当前的「瞄准视锥」内（票 02 验收 8）。
func _pick_spawn() -> Vector3:
	var dist := GameSettings.target_range
	var limit := MovementSimulator.ARENA_RADIUS - SPAWN_BOUNDARY_MARGIN
	for attempt in SPAWN_ATTEMPTS:
		var a := player.yaw + randf_range(-SPAWN_SPREAD, SPAWN_SPREAD)
		var dir := Vector3(-sin(a), 0.0, -cos(a))
		var p := player.global_position + dir * dist
		var flat := Vector2(p.x, p.z)
		if flat.length() > limit or arena.is_blocked(flat, SPAWN_CLEARANCE):
			continue
		if _player_aims_at(flat):
			continue
		return Vector3(flat.x, 0.0, flat.y)
	var fallback := Vector3(-sin(player.yaw), 0.0, -cos(player.yaw))
	return player.global_position + fallback * dist

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
		var p := center + Vector2(cos(a), sin(a)) * radius
		var d := p.length()
		if d > limit:
			p *= limit / d
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

	if shot_target == null:
		_play_sound(_shot_audio, SHOT_VOLUME, _shot_pitch())
		match_state.record_shot(false)
	else:
		_play_sound(_shot_audio, SHOT_VOLUME, _shot_pitch())
		var damage := Weapon.headshot_damage(id) if headshot else Weapon.body_damage(id)
		match_state.record_shot(true)
		_play_sound(
			_hit_audio,
			HEADSHOT_VOLUME if headshot else HIT_VOLUME,
			HEADSHOT_PITCH if headshot else 1.0
		)
		if shot_target.take_hit(damage, _perception):
			match_state.record_kill()
			_play_sound(_kill_audio, KILL_VOLUME, 1.0) # 与击中音叠加
			hud.flash(HitMarkerTiming.KIND_KILL)
		else:
			hud.flash(HitMarkerTiming.KIND_HIT)
	_play_fx(_fx, player.muzzle_world(), impact)

# ---- 开火：bot ----

## bot 每发开火的结算：音效 → 枪口火光 → 曳光（bot 枪口 → 玩家当前坐标，纯视觉）→ 命中扣血。
func _resolve_bot_shot(hit: bool) -> void:
	var muzzle := target.muzzle_world()
	_play_sound(_shot_audio, SHOT_VOLUME, _shot_pitch())
	_play_fx(
		_bot_fx,
		muzzle,
		Vector3(player.global_position.x, BOT_TRACER_HEIGHT, player.global_position.z)
	)
	if not hit:
		return
	match_state.player_hp = maxi(0, match_state.player_hp - BotAi.BOT_DAMAGE)
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
	p.ads = GameSettings.bot_ads_enabled
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

# ---- 音频：三份定频资产入库，音高微差靠播放器 pitch_scale，不预生成变体（票 01 第 9 节）----

func _build_audio() -> void:
	_shot_audio = _make_audio("ShotAudio", SHOT_SOUND)
	_hit_audio = _make_audio("HitAudio", HIT_SOUND)
	_kill_audio = _make_audio("KillAudio", KILL_SOUND)

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
	add_child(out.tracer)
	return out

func _play_fx(fx: Fx, muzzle: Vector3, to: Vector3) -> void:
	if GameSettings.muzzle_flash_enabled:
		fx.flash_left = FLASH_LIFE
		fx.flash.global_position = muzzle
		fx.flash.visible = true
		fx.light.global_position = muzzle
		fx.light.light_energy = FLASH_PEAK_ENERGY
	if GameSettings.tracer_enabled:
		var delta := to - muzzle
		var length := delta.length()
		if length > 0.001:
			fx.tracer_left = TRACER_LIFE
			var dir := delta / length
			# 长度写进网格本体（避免节点缩放在旋转基上产生歧义）；朝向交给 look_at，它把本地 −Z 对准终点
			(fx.tracer.mesh as BoxMesh).size = Vector3(TRACER_WIDTH, TRACER_WIDTH, length)
			fx.tracer.global_position = muzzle + dir * (length * 0.5)
			var up := Vector3.UP if absf(dir.y) < 0.99 else Vector3.FORWARD
			fx.tracer.look_at(fx.tracer.global_position + dir, up)
			fx.tracer.visible = true

func _tick_fx(fx: Fx, delta: float) -> void:
	if fx.flash_left > 0.0:
		fx.flash_left -= delta
		if fx.flash_left > 0.0:
			fx.light.light_energy = FLASH_PEAK_ENERGY * (fx.flash_left / FLASH_LIFE)
		else:
			fx.flash.visible = false
			fx.light.light_energy = 0.0
	if fx.tracer_left > 0.0:
		fx.tracer_left -= delta
		if fx.tracer_left <= 0.0:
			fx.tracer.visible = false