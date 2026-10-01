## 玩家：移动（ADR-0002）、视角、开镜、切枪与开火节奏。
##
## `CharacterBody3D` **只做碰撞求解**：水平速度全部由 `MovementSimulator` 按固定子步 1/240
## 算好，这里每帧只把「本帧位移 ÷ delta」喂给 `velocity` 交给 `move_and_slide()`，
## 再把求解后的真实位置回写给 sim——不使用 Godot 自带的加速与摩擦。
##
## 垂直方向不走物理：跳跃高度由 sim 的 `height()` 决定，相机跟着抬（与参考实现同构）。

class_name Player
extends CharacterBody3D

## 开火一次（含连射的每一发）。由 main 接走去射线判定与特效。
signal shot_fired(id: StringName)
signal weapon_changed(id: StringName)

const PITCH_LIMIT := 1.55
## 右摇杆满推时的角速度基准（rad/s），乘以「手柄灵敏度」倍率（`GameSettings.gamepad_sensitivity`）。
const GAMEPAD_LOOK_BASE := 2.5
const ZOOM_IN_TIME := 0.22
const ZOOM_OUT_TIME := 0.088
const FOV := 92.35
const ZOOM_FOV := 76.64

## 纯视觉后坐力（票 05）：开火瞬间相机轻踢上抬再回中，COD/Apex 手感——
## **只动渲染**：弹道方向永远取逻辑 yaw/pitch（见 `aim_direction`），后坐力不影响任何命中。
const RECOIL_PITCH_RIFLE := 0.018 ## 步枪单发上踢（rad，约 1.0°）；连发累计大，幅度收敛（票 06）
const RECOIL_PITCH_PISTOL := 0.028 ## 手枪单发上踢（rad，约 1.6°）：单发间隔长，相机踢更大更「沉」
const RECOIL_YAW_RIFLE := 0.005 ## 每发随机水平抖动幅度（±rad），按武器分档（票 06）
const RECOIL_YAW_PISTOL := 0.012 ## 手枪水平抖略大：单发大间歇配一个明显的小甩头
const RECOIL_RECOVER_RIFLE := 10.0 ## 指数回中速率（1/s）：连发要回得快，否则糊成一团
const RECOIL_RECOVER_PISTOL := 5.0 ## 手枪回中减半：单发要「沉」的手感（CONTEXT「视觉后坐力」）

@onready var camera: Camera3D = $Camera3D
@onready var viewmodel: Viewmodel = $Viewmodel

var sim := MovementSimulator.new()
var weapon: StringName = Weapon.RIFLE
var yaw := 0.0
var pitch := 0.0
var zoom_p := 0.0
## 关掉后不再响应键鼠/手柄（失焦、菜单打开时用）。
var input_enabled := true

var _fire := Weapon.new(Weapon.RIFLE)
var _pad := -1
## 视觉后坐力的当前偏移量（渲染专用，不进 yaw/pitch 逻辑状态）。
var _recoil_pitch := 0.0
var _recoil_yaw := 0.0

func _ready() -> void:
	# 主相机不看武器层；武器相机只看武器层（ADR-0008 的几何隔离）。
	camera.cull_mask = 0xFFFFF & ~Viewmodel.WEAPON_LAYER
	camera.fov = FOV
	viewmodel.set_weapon(weapon)
	_refresh_gamepad()

func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled or _pad >= 0:
		return # 手柄连着就忽略鼠标（ADR-0003）
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		apply_look(-mm.relative.x * _sensitivity(), -mm.relative.y * _sensitivity())

func _physics_process(delta: float) -> void:
	_refresh_gamepad()
	_tick_recoil(delta)
	if input_enabled:
		_tick_look(delta)
		_tick_weapon(delta)
	_tick_zoom(delta)
	_tick_move(delta)

# ---- 视角 ----

## 鼠标/摇杆直接叠加视角增量（俯仰上限 ±1.55 rad）。
func apply_look(d_yaw: float, d_pitch: float) -> void:
	yaw += d_yaw
	pitch = clampf(pitch + d_pitch, -PITCH_LIMIT, PITCH_LIMIT)

## 当前生效的鼠标灵敏度：滑条是倍率（票 05 改量纲），乘基准换算成 rad/px；
## 开镜时再按 ADS 倍率缩放（参考实现 ADR-0021）。
func _sensitivity() -> float:
	var mult := 1.0 - (1.0 - GameSettings.ads_sens_mult) * zoom_p
	return InputSensitivity.mouse_rad_per_px(GameSettings.mouse_sensitivity) * mult

## 手柄灵敏度与鼠标分开设定（CONTEXT「灵敏度」），开镜倍率共用。
func _pad_sensitivity() -> float:
	var mult := 1.0 - (1.0 - GameSettings.ads_sens_mult) * zoom_p
	return GameSettings.gamepad_sensitivity * mult

func _tick_look(delta: float) -> void:
	if _pad < 0:
		return
	var x := Input.get_joy_axis(_pad, JOY_AXIS_RIGHT_X)
	var y := Input.get_joy_axis(_pad, JOY_AXIS_RIGHT_Y)
	var k := GAMEPAD_LOOK_BASE * _pad_sensitivity() * delta
	apply_look(-x * k, -y * k)

# ---- 开镜 ----

func _tick_zoom(delta: float) -> void:
	var want := 0.0
	if input_enabled and Input.is_action_pressed("ads"):
		want = 1.0
	var rate := 1.0 / (ZOOM_IN_TIME if want > zoom_p else ZOOM_OUT_TIME)
	zoom_p = move_toward(zoom_p, want, rate * delta)
	camera.fov = lerpf(FOV, ZOOM_FOV, zoom_p)
	sim.set_zoom(zoom_p)
	viewmodel.apply_zoom(zoom_p)

# ---- 移动 ----

func _tick_move(delta: float) -> void:
	sim.set_facing(yaw)
	sim.set_control(_read_control())
	var before := sim.position()
	sim.advance(delta)
	var after := sim.position()
	var step := (after - before) / delta if delta > 1e-6 else Vector2.ZERO

	# 垂直交给 sim（跳跃高度由 height() 决定），物理只解水平碰撞。
	velocity = Vector3(step.x, 0.0, step.y)
	move_and_slide()

	# 位置回写与强制贴地：碰撞求解的结果才是下一帧的起点。
	global_position.y = 0.0
	sim.sync_position(Vector2(global_position.x, global_position.z))
	camera.position = Vector3(0.0, Physique.EYE_HEIGHT + sim.height(), 0.0)
	# 相机 = 逻辑朝向 + 视觉后坐力偏移；后者是纯渲染量，弹道不读它。
	camera.rotation = Vector3(pitch + _recoil_pitch, yaw + _recoil_yaw, 0.0)

## 视觉后坐力：开火时上踢，指数回中（票 05）；回中速率按武器分档（票 06）。
func _tick_recoil(delta: float) -> void:
	var recover := RECOIL_RECOVER_RIFLE if Weapon.is_rifle(weapon) else RECOIL_RECOVER_PISTOL
	var k := 1.0 - exp(-recover * delta)
	_recoil_pitch = lerpf(_recoil_pitch, 0.0, k)
	_recoil_yaw = lerpf(_recoil_yaw, 0.0, k)

func _add_recoil() -> void:
	var strong := Weapon.is_rifle(weapon)
	_recoil_pitch += RECOIL_PITCH_RIFLE if strong else RECOIL_PITCH_PISTOL
	var jitter := RECOIL_YAW_RIFLE if strong else RECOIL_YAW_PISTOL
	_recoil_yaw += randf_range(-jitter, jitter)
	viewmodel.kick(strong)

func _read_control() -> MovementSimulator.MoveControl:
	var c := MovementSimulator.MoveControl.new()
	if not input_enabled:
		return c
	if _pad >= 0:
		var sm := StickMove.from_axes(
			Input.get_joy_axis(_pad, JOY_AXIS_LEFT_X), Input.get_joy_axis(_pad, JOY_AXIS_LEFT_Y)
		)
		c.right = sm.right
		c.fwd = sm.fwd
		c.sprint = sm.sprint
	else:
		c.right = float(Input.is_action_pressed("move_right")) - float(Input.is_action_pressed("move_left"))
		c.fwd = float(Input.is_action_pressed("move_forward")) - float(Input.is_action_pressed("move_back"))
		c.sprint = Input.is_action_pressed("sprint")
	c.crouch = Input.is_action_pressed("crouch")
	c.jump = Input.is_action_pressed("jump")
	return c

# ---- 武器 ----

func set_weapon(id: StringName) -> void:
	if id == weapon:
		return
	weapon = id
	_fire = Weapon.new(id)
	viewmodel.set_weapon(id)
	weapon_changed.emit(id)

func switch_weapon() -> void:
	set_weapon(Weapon.other(weapon))

func _tick_weapon(delta: float) -> void:
	# 切枪：1 / 2 直接选，Q（手柄 Y）就近切。切枪会丢弃手枪缓冲并让下一发立即就绪。
	if Input.is_action_just_pressed("weapon_rifle"):
		set_weapon(Weapon.RIFLE)
	elif Input.is_action_just_pressed("weapon_pistol"):
		set_weapon(Weapon.PISTOL)
	elif Input.is_action_just_pressed("weapon_switch"):
		switch_weapon()

	var held := Input.is_action_pressed("fire")
	# 手枪是单发：点击边沿喂一发；`press()` 返回 true 表示「冷却就绪、当场开火」，
	# 返回 false 表示冷却中、已缓冲一发（交给 advance 在冷却结束时补发）。
	if not Weapon.automatic(weapon) and Input.is_action_just_pressed("fire"):
		if _fire.press():
			_add_recoil()
			shot_fired.emit(weapon)
	for i in _fire.advance(delta, held):
		_add_recoil()
		shot_fired.emit(weapon)

## 当前武器枪口的世界坐标（火光与曳光弹起点）。
func muzzle_world() -> Vector3:
	return viewmodel.muzzle_world()

## 玩家眼位（射线起点）。
func eye_position() -> Vector3:
	return camera.global_position

## 当前准星方向（射线方向）：只取**逻辑** yaw/pitch——视觉后坐力只踢渲染相机，
## 弹道不能跟着抖（票 05「不要产生实际的后座」）。`from_euler` 默认 YXZ 序，与相机一致。
func aim_direction() -> Vector3:
	return -Basis.from_euler(Vector3(pitch, yaw, 0.0)).z

func _refresh_gamepad() -> void:
	var pads := Input.get_connected_joypads()
	_pad = pads[0] if pads.size() > 0 else -1
