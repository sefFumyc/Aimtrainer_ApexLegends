## 主场景：把场地、玩家、靶、HUD 与设置串成最小可玩闭环（票 01）。
##
## 开火判定、伤害、靶的刷新与特效都收在这里——切片一只有一个受击体，不值得再拆一层。

extends Node3D

const FIRE_RANGE := 3000.0 ## 射线最大长度（与相机远裁剪面同量级）
const FLASH_LIFE := 0.05 ## 枪口火光存活时长（秒，取自参考实现 flashTotal）
const TRACER_LIFE := 0.1 ## 曳光弹存活时长（秒，取自参考实现 tracerTotal）
const TRACER_MISS_LEN := 200.0 ## 未命中时曳光弹的固定长度
const TRACER_WIDTH := 0.4 ## 曳光弹宽度（取自参考实现 tracerWidth）
const FLASH_RADIUS := 4.0 ## 火光半径（参考实现火光贴图 8u 见方 → 半径 4）
const FLASH_PEAK_ENERGY := 5.0
const SPAWN_SPREAD := 0.9 ## 刷新方向的随机扇角（±弧度）
const SPAWN_ATTEMPTS := 12

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

@onready var arena: Arena = $Arena
@onready var player: Player = $Player
@onready var target: Target = $Target
@onready var hud: Hud = $HudLayer/Hud
@onready var settings_panel: SettingsPanel = $HudLayer/SettingsPanel

var match_state := DuelMatch.new()

var _flash: MeshInstance3D
var _flash_light: OmniLight3D
var _tracer: MeshInstance3D
var _flash_left := 0.0
var _tracer_left := 0.0

var _shot_audio: AudioStreamPlayer
var _hit_audio: AudioStreamPlayer
var _kill_audio: AudioStreamPlayer

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
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		GameSettings.save_settings()

func _process(delta: float) -> void:
	match_state.elapsed += delta
	if target.advance(delta):
		_respawn_target()
	match_state.bot_hp = target.hp
	_tick_fx(delta)
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
	if target.alive:
		avoid.append(Vector2(target.global_position.x, target.global_position.z))
	arena.configure(GameSettings.arena_layout, avoid)
	target.apply_body_radius(GameSettings.body_radius)

# ---- 靶 ----

func _respawn_target() -> void:
	var at := _pick_spawn()
	var dir := at - player.global_position
	target.spawn(at, Vector3(-dir.z, 0.0, dir.x))

## 在玩家前方 `target_range` 处取点，避开围墙与遮挡物。
func _pick_spawn() -> Vector3:
	var dist := GameSettings.target_range
	var limit := MovementSimulator.ARENA_RADIUS - 60.0
	for attempt in SPAWN_ATTEMPTS:
		var a := player.yaw + randf_range(-SPAWN_SPREAD, SPAWN_SPREAD)
		var dir := Vector3(-sin(a), 0.0, -cos(a))
		var p := player.global_position + dir * dist
		var flat := Vector2(p.x, p.z)
		if flat.length() > limit or arena.is_blocked(flat, 30.0):
			continue
		return Vector3(flat.x, 0.0, flat.y)
	var fallback := Vector3(-sin(player.yaw), 0.0, -cos(player.yaw))
	return player.global_position + fallback * dist

# ---- 开火 ----

func _on_shot_fired(id: StringName) -> void:
	var origin := player.eye_position()
	var direction := player.aim_direction()
	var ray := PhysicsRayQueryParameters3D.create(origin, origin + direction * FIRE_RANGE, 1)
	ray.exclude = [player.get_rid()]
	var hit := player.get_world_3d().direct_space_state.intersect_ray(ray)

	var impact := origin + direction * TRACER_MISS_LEN
	var shot_target: Target = null
	var headshot := false
	if not hit.is_empty():
		impact = hit["position"]
		var collider: Object = hit["collider"]
		if collider is Target:
			shot_target = collider
			# 命中形状所属部件名含 head/helmet 即爆头（靶命中体由模型部件几何构成）
			headshot = shot_target.is_headshot(hit["shape"])

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
		if shot_target.take_hit(damage):
			match_state.record_kill()
			_play_sound(_kill_audio, KILL_VOLUME, 1.0) # 与击中音叠加
			hud.flash(HitMarkerTiming.KIND_KILL)
		else:
			hud.flash(HitMarkerTiming.KIND_HIT)
	_play_fx(impact)

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

# ---- 特效：枪口火光 + 曳光弹（各受一个开关控制）----

func _build_fx() -> void:
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
	_flash = MeshInstance3D.new()
	_flash.name = "MuzzleFlash"
	_flash.mesh = flash_mesh
	_flash.visible = false
	add_child(_flash)

	_flash_light = OmniLight3D.new()
	_flash_light.name = "MuzzleLight"
	_flash_light.light_color = Color(1.0, 0.78, 0.42)
	_flash_light.omni_range = 20.0
	_flash_light.light_energy = 0.0
	add_child(_flash_light)

	var tracer_mesh := BoxMesh.new()
	tracer_mesh.size = Vector3(TRACER_WIDTH, TRACER_WIDTH, 1.0) # 沿本地 −Z 延伸，长度靠节点缩放
	var tracer_mat := StandardMaterial3D.new()
	tracer_mat.albedo_color = Color(1.0, 0.95, 0.75)
	tracer_mat.emission_enabled = true
	tracer_mat.emission = Color(1.0, 0.85, 0.45)
	tracer_mat.emission_energy_multiplier = 3.0
	tracer_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_tracer = MeshInstance3D.new()
	_tracer.name = "Tracer"
	_tracer.mesh = tracer_mesh
	_tracer.material_override = tracer_mat
	_tracer.visible = false
	add_child(_tracer)

func _play_fx(to: Vector3) -> void:
	var muzzle := player.muzzle_world()
	if GameSettings.muzzle_flash_enabled:
		_flash_left = FLASH_LIFE
		_flash.global_position = muzzle
		_flash.visible = true
		_flash_light.global_position = muzzle
		_flash_light.light_energy = FLASH_PEAK_ENERGY
	if GameSettings.tracer_enabled:
		var delta := to - muzzle
		var length := delta.length()
		if length > 0.001:
			_tracer_left = TRACER_LIFE
			var dir := delta / length
			# 长度写进网格本体（避免节点缩放在旋转基上产生歧义）；朝向交给 look_at，它把本地 −Z 对准终点
			(_tracer.mesh as BoxMesh).size = Vector3(TRACER_WIDTH, TRACER_WIDTH, length)
			_tracer.global_position = muzzle + dir * (length * 0.5)
			var up := Vector3.UP if absf(dir.y) < 0.99 else Vector3.FORWARD
			_tracer.look_at(_tracer.global_position + dir, up)
			_tracer.visible = true

func _tick_fx(delta: float) -> void:
	if _flash_left > 0.0:
		_flash_left -= delta
		if _flash_left > 0.0:
			_flash_light.light_energy = FLASH_PEAK_ENERGY * (_flash_left / FLASH_LIFE)
		else:
			_flash.visible = false
			_flash_light.light_energy = 0.0
	if _tracer_left > 0.0:
		_tracer_left -= delta
		if _tracer_left <= 0.0:
			_tracer.visible = false
