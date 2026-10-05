## Viewmodel 隔离层（ADR-0008）：用 `SubViewportContainer` + `SubViewport` 把武器模型
## 放进一个**独立世界**渲染，再贴回屏幕。
##
## 这样做换来三件事：
## 1) 枪不会被墙/柱子裁掉——武器相机的深度缓冲里根本没有世界几何（验收条件 3）；
## 2) 武器相机的 cull mask 只认武器层，主相机的 cull mask 排除武器层，互不串场；
## 3) 开镜只动武器挂点，不动主相机，FOV 与位移互不耦合。
##
## 几何是程序化拼的（枪管 / 机匣 / 握把 / 红点镜框），Kenney Blaster Kit 的 GLB
## 到位后自动改用模型（ADR-0007）。

class_name Viewmodel
extends SubViewportContainer

## 本帧枪体位姿已定稿（`_process` 应用后坐恢复并刷新 rig 之后）。
## 开火特效按此刻的枪口采样，起点与本帧渲染枪口逐像素重合（ADR-0021）。
signal pose_applied

## 武器层（`VisualInstance3D.layers` 的第 2 位）：只被武器相机看见。
const WEAPON_LAYER := 2

## 腰射基准位姿（参考实现 applyZoom 的 p = 0 端点；票 05 拉近：原 (13, -8, -15) 观感太远）。
const GUN_BASE_POS := Vector3(9.0, -7.0, -10.0)
const GUN_BASE_YAW := -0.08
const GUN_BASE_PITCH := -0.06
## 准镜中线相对武器挂点的高度——只给**程序化兜底几何**用；换 GLB 后由 `_fit_model()`
## 把模型顶面压到 y = 0，`_sight_y` 随之变成 0（ADR-0007）。
const PROC_SIGHT_HEIGHT := 2.6
## 满开镜时武器挂点相对相机的横向/纵深位置（x 居中、向前推远到不糊脸）。
const ADS_Z := -8.0

## 枪口在武器挂点本地坐标 = 拟合后的枪管前端。模型枪改用 **Muzzle 标记**（枪管轴线，
## ADR-0021 二轮），这两个常量只作程序化兜底枪的口径（兜底枪管就在 y = 0）。
const RIFLE_MUZZLE_LOCAL := Vector3(0.0, 0.0, -25.0)
const PISTOL_MUZZLE_LOCAL := Vector3(0.0, 0.0, -7.5)
## 两把枪拟合后的总长（枪口端到握把端）。
const RIFLE_LENGTH := 25.0
const PISTOL_LENGTH := 7.5
## 枪管高度系数（ADR-0021 二轮，截图探针两轮定稿）：Muzzle 标记 y = −拟合高度 × 系数。
## 起点 = 枪管轴线（枪口孔位）而非枪体顶面前角——火光是大球看不出来，曳光细线对起点
## 高度敏感（实测从「枪口上面」出来）。
const RIFLE_BORE_FRAC := 0.36
const PISTOL_BORE_FRAC := 0.34

## Kenney Blaster Kit（CC0）模型路径；文件不存在时回落到程序化几何。
const RIFLE_MODEL := "res://assets/third_party/kenney_blaster-kit/rifle/blaster-d.glb"
const PISTOL_MODEL := "res://assets/third_party/kenney_blaster-kit/pistol/blaster-k.glb"

const METAL := Color(0.16, 0.17, 0.20)
const GRIP := Color(0.28, 0.25, 0.22)
const DOT_COLOR := Color(0.95, 0.22, 0.18)

## 纯视觉后坐力（票 05）：开火瞬间枪体后坐 + 上抬，弹性回位——只动挂点，与开镜基准叠加。
## 票 06 分档：步枪收敛（连发累计大），手枪维持原值（1.8×0.6 / 0.1×0.6）不放大。
const KICK_BACK_RIFLE := 1.1 ## 步枪后坐位移（沿挂点 +Z，朝相机方向）
const KICK_PITCH_RIFLE := 0.06 ## 步枪上抬角（rad）
const KICK_BACK_PISTOL := 1.08 ## 手枪后坐位移（原 1.8 × 0.6，保持不变）
const KICK_PITCH_PISTOL := 0.06 ## 手枪上抬角（原 0.1 × 0.6，保持不变）
const KICK_RECOVER := 14.0 ## 指数回位速率（1/s），两枪共用

@onready var weapon_camera: Camera3D = $SubViewport/WeaponCamera
@onready var rig: Node3D = $SubViewport/WeaponCamera/WeaponRig

var _rifle: Node3D
var _pistol: Node3D
var _weapon: StringName = Weapon.RIFLE
var _zoom := 0.0
## 每把枪的红点镜轴高度（票 06）：两把枪镜高不同，按武器查表——
## 满开镜时挂点 y = -镜高，红点正落准星轴。程序化兜底枪共用 PROC_SIGHT_HEIGHT。
var _sight_heights := {}
## 每把枪的枪口标记（枪管轴线，ADR-0021 二轮）：程序化兜底枪不入表，走本地常量口径。
var _muzzle_markers := {}
## 开镜基准位姿（`apply_zoom` 算好存在这里，`_apply_rig` 把后坐力叠上去）。
var _base_pos := Vector3.ZERO
var _base_rot := Vector3.ZERO
## 当前枪体后坐偏移量（`kick` 注入，`_process` 指数回位）。
var _kick_pos := 0.0
var _kick_pitch := 0.0

func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	weapon_camera.cull_mask = WEAPON_LAYER
	_build_world()
	_rifle = _build_weapon("Rifle", Weapon.RIFLE)
	_pistol = _build_weapon("Pistol", Weapon.PISTOL)
	rig.add_child(_rifle)
	rig.add_child(_pistol)
	apply_zoom(0.0)
	set_weapon(Weapon.RIFLE)

## 独立世界需要自己的环境与光照，否则贴回来是黑的。
func _build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.68, 0.80)
	env.ambient_light_energy = 1.1
	weapon_camera.get_world_3d().environment = env

	# 灯必须挂在 SubViewport 内部才属于那个独立世界。
	var key := DirectionalLight3D.new()
	key.name = "WeaponKeyLight"
	key.light_energy = 1.6
	key.rotation = Vector3(deg_to_rad(-38.0), deg_to_rad(-28.0), 0.0)
	$SubViewport.add_child(key)

func set_weapon(id: StringName) -> void:
	_weapon = id
	if _rifle != null:
		_rifle.visible = Weapon.is_rifle(id)
	if _pistol != null:
		_pistol.visible = not Weapon.is_rifle(id)
	apply_zoom(_zoom) ## 镜高按枪不同（票 06），切枪重算开镜基准

## 开镜进度 p（0 腰射 / 1 满开镜）。
## 俯仰角在满开镜时归零——否则那 −0.06 的枪口下压会把准镜带离准星轴。
func apply_zoom(p: float) -> void:
	_zoom = clampf(p, 0.0, 1.0)
	var sight: float = _sight_heights.get(_weapon, PROC_SIGHT_HEIGHT)
	_base_pos = GUN_BASE_POS.lerp(Vector3(0.0, -sight, ADS_Z), _zoom)
	_base_rot = Vector3(GUN_BASE_PITCH * (1.0 - _zoom), GUN_BASE_YAW * (1.0 - _zoom), 0.0)
	_apply_rig()

## 开火一瞬的后坐注入（player 调用）：按武器取各自档位（票 06 拆档），幅度乘
## 「枪械抖动」倍率（票 08，CONTEXT「后坐力强度」）——每次开火实时读设置，改滑条对下一发生效。
func kick(strong: bool) -> void:
	var gun_mult := GameSettings.recoil_gun_mult_for(_weapon)
	_kick_pos += (KICK_BACK_RIFLE if strong else KICK_BACK_PISTOL) * gun_mult
	_kick_pitch += (KICK_PITCH_RIFLE if strong else KICK_PITCH_PISTOL) * gun_mult

func _process(delta: float) -> void:
	var k := 1.0 - exp(-KICK_RECOVER * delta)
	_kick_pos = lerpf(_kick_pos, 0.0, k)
	_kick_pitch = lerpf(_kick_pitch, 0.0, k)
	_apply_rig()
	pose_applied.emit()

## 挂点位姿 = 开镜基准 + 后坐偏移（后坐沿 +Z 朝相机、上抬绕 X）。
## 开镜枪体行为按武器分档（票 08，CONTEXT「视觉后坐力」）：步枪的**上抬角**随开镜进度
## 收敛到零——红点贴准星轴、枪模不上下跳（前后后坐沿视线轴，红点不出轴心，满开镜呈纯
## 前后震）；手枪**完全不收敛**——开镜与腰射一样上下跳（单发「沉」的手感）。
## 前后位移两枪都满幅保留。
func _apply_rig() -> void:
	var pitch_damp := (1.0 - _zoom) if Weapon.is_rifle(_weapon) else 1.0
	rig.position = _base_pos + Vector3(0.0, 0.0, _kick_pos)
	rig.rotation = _base_rot + Vector3(_kick_pitch * pitch_damp, 0.0, 0.0)

## 当前武器枪口的世界坐标（火光与曳光弹的起点）。
## 模型枪 = Muzzle 标记（枪管轴线，ADR-0021 二轮）；程序化兜底枪 = 挂点本地 (0,0,−len)。
func muzzle_world() -> Vector3:
	var marker: Node3D = _muzzle_markers.get(_weapon)
	if marker != null:
		return marker.global_position
	var local := RIFLE_MUZZLE_LOCAL if Weapon.is_rifle(_weapon) else PISTOL_MUZZLE_LOCAL
	return rig.to_global(local)

func _build_weapon(node_name: String, id: StringName) -> Node3D:
	var root := Node3D.new()
	root.name = node_name
	var rifle := Weapon.is_rifle(id)
	var length := RIFLE_LENGTH if rifle else PISTOL_LENGTH
	var loaded := _try_load_model(RIFLE_MODEL if rifle else PISTOL_MODEL)
	if loaded != null:
		root.add_child(_fit_model(loaded, length, RIFLE_BORE_FRAC if rifle else PISTOL_BORE_FRAC))
		_muzzle_markers[id] = root.get_node("Model/Muzzle")
		# 1x 红点镜骑在枪顶（票 06）：红点即瞄准基线——返回值按枪记录，满开镜时
		# `_base_pos.y = -镜高` 让红点正落准星轴，与准星重合、视野无遮挡。
		_sight_heights[id] = _add_red_dot(root, length)
	else:
		_build_procedural(root, id)
	return root

## 程序化 1x 红点镜（票 06 定稿样式：无环开框式——两侧细柱 + 顶端红段 + 悬浮红点，
## 参照 Apex 1x 红点镜：中间完全开放不挡视野；kit 里没有独立瞄具模型）。
## 返回镜轴相对挂点的高度（模型拟合后顶面在 y = 0，镜轴 = 顶面 + 柱高）。
func _add_red_dot(root: Node3D, length: float) -> float:
	var metal := StandardMaterial3D.new()
	metal.albedo_color = METAL
	metal.metallic = 0.0 ## 武器世界无反射源，与 GLB 材质统一压全 diffuse（票 06）
	metal.metallic_specular = 0.3
	metal.roughness = 0.35
	var glow := StandardMaterial3D.new()
	glow.albedo_color = DOT_COLOR
	glow.emission_enabled = true
	glow.emission = DOT_COLOR
	glow.emission_energy_multiplier = 2.5

	var sight_h := length * 0.098 ## 镜轴高度（步 2.45 / 手 0.74）
	var z := -length * 0.32 ## 骑在机匣上方偏前
	var half_gap := length * 0.055 ## 柱间距一半（步 ±1.38 / 手 ±0.41）
	var pole := Vector3(0.16, sight_h * 0.8, 0.22) ## 深色柱身
	var cap := Vector3(0.16, sight_h * 0.2, 0.22) ## 顶端红段（发光）

	for side in [-1.0, 1.0]:
		var x: float = side * half_gap
		var l: String = "L" if side < 0.0 else "R"
		root.add_child(_box("RedDotPost" + l, pole, Vector3(x, pole.y * 0.5, z), metal))
		root.add_child(_box("RedDotCap" + l, cap, Vector3(x, pole.y + cap.y * 0.5, z), glow))
	root.add_child(_sphere("RedDot", length * 0.006, Vector3(0.0, sight_h, z), glow)) ## 红点很小（步 0.15 / 手 0.045），开镜只是个点
	return sight_h

## 把模型摆进武器挂点空间：Kenney glb 导入后 **+Z 端是枪口**（blaster-d/k 两端端面实测），
## 先绕 Y 转 180° 让枪口朝 −Z 与挂点同向（票 06 修正拿反）；再缩放到约定总长、
## 顶面压到 y = 0（准镜轴）、枪托端 → z = 0、枪口端 → z = −length、左右居中。
## 全部由模型自身的包围盒算出，不含手填数字。
func _fit_model(model: Node3D, length: float, bore_frac: float) -> Node3D:
	model.rotation.y = PI ## 修正枪口朝向（见上）
	var box := _model_aabb(model)
	if box.size.z <= 0.0:
		return model
	var s := length / box.size.z
	var hi := box.position + box.size
	var holder := Node3D.new()
	holder.name = "Model"
	holder.scale = Vector3.ONE * s
	holder.position = Vector3(
		-s * (box.position.x + hi.x) * 0.5, # 左右居中（无翻转 → 取负）
		-hi.y * s, # 顶面 → y = 0
		-length - s * box.position.z # 枪托端 → z = 0、枪口端 → z = −length
	)
	holder.add_child(model)
	# 枪管轴线标记（ADR-0021 二轮）：火光/曳光的起点 = 枪口孔位。坐标与 box 同在
	# **holder 本地空间**（box 不含 holder 自身的缩放与偏移）：
	# z = box.position.z——模型已转 180°、枪口朝 −Z，枪口端面是 min z（holder.position.z
	# 恰好把它映射到 −length）；y = 顶面 hi.y 往下 frac×高（holder 把顶面映射到 y=0，
	# 化简后 rig 空间恰为 (0, −拟合高×frac, −length)，与探针定稿口径一致）；
	# x = 模型自身中心平面（与 holder.position.x 抵消 → rig x=0）。
	var muzzle := Node3D.new()
	muzzle.name = "Muzzle"
	muzzle.position = Vector3(
		(box.position.x + hi.x) * 0.5,
		hi.y - box.size.y * bore_frac,
		box.position.z
	)
	holder.add_child(muzzle)
	return holder

## 模型在其父空间里的包围盒（递归累加各网格的 AABB）。
func _model_aabb(root: Node) -> AABB:
	var boxes: Array[AABB] = []
	_collect_boxes(root, Transform3D.IDENTITY, boxes)
	var out := AABB()
	for i in boxes.size():
		out = boxes[i] if i == 0 else out.merge(boxes[i])
	return out

func _collect_boxes(node: Node, xf: Transform3D, out: Array[AABB]) -> void:
	var local := xf
	if node is Node3D:
		local = xf * (node as Node3D).transform
	if node is MeshInstance3D:
		out.append(local * (node as MeshInstance3D).get_aabb())
	for child in node.get_children():
		_collect_boxes(child, local, out)

func _try_load_model(path: String) -> Node3D:
	if not ResourceLoader.exists(path):
		return null
	var scene := load(path)
	if scene is PackedScene:
		var inst := (scene as PackedScene).instantiate()
		_set_weapon_layers(inst)
		return inst
	return null

## GLB 自带的图层不一定是我们约定的武器层，逐个改掉；同时关掉投影（票 05：FPS 惯例，
## 武器不参与任何阴影计算，也避免独立世界里的自投影杂纹）。
## 另把材质压成全 diffuse（票 06）：blaster-d 等模型自带金属度，而武器世界（SubViewport）
## 没有天空/反射探针，金属反射为零会整枪黑掉；玩具枪本就是 diffuse 风格，统一压平。
func _set_weapon_layers(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		for i in mi.get_surface_override_material_count():
			var mat := mi.get_active_material(i)
			if mat is StandardMaterial3D:
				var sm := (mat as StandardMaterial3D).duplicate()
				sm.metallic = 0.0
				sm.metallic_specular = 0.3
				mi.set_surface_override_material(i, sm)
	if node is VisualInstance3D:
		var vi := node as VisualInstance3D
		vi.layers = WEAPON_LAYER
		vi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		_set_weapon_layers(child)

## 程序化兜底：枪管 + 机匣 + 握把 + 红点镜框。尺寸照参考实现。
func _build_procedural(root: Node3D, id: StringName) -> void:
	var metal := StandardMaterial3D.new()
	metal.albedo_color = METAL
	metal.metallic = 0.7
	metal.roughness = 0.35
	var grip_mat := StandardMaterial3D.new()
	grip_mat.albedo_color = GRIP
	grip_mat.roughness = 0.85
	var dot := StandardMaterial3D.new()
	dot.albedo_color = DOT_COLOR
	dot.emission_enabled = true
	dot.emission = DOT_COLOR
	dot.emission_energy_multiplier = 2.5

	var rifle := Weapon.is_rifle(id)
	var barrel_len := 22.0 if rifle else 8.0
	var barrel_z := -14.0 if rifle else -3.5
	root.add_child(_box("Barrel", Vector3(0.6, 0.6, barrel_len), Vector3(0.0, 0.0, barrel_z), metal))
	root.add_child(_box("Receiver", Vector3(1.6, 1.4, 5.0), Vector3(0.0, -0.2, -2.0 if rifle else -1.0), metal))
	root.add_child(_box("Grip", Vector3(1.1, 3.2, 1.4), Vector3(0.0, -2.0, 1.2), grip_mat))
	if rifle:
		root.add_child(_box("Stock", Vector3(1.2, 1.2, 4.0), Vector3(0.0, -0.5, 3.5), grip_mat))
	# 镜框三边 + 红点（同一款瞄具两把枪共用）；高度取 PROC_SIGHT_HEIGHT，开镜时才落准星轴上。
	var frame_y := PROC_SIGHT_HEIGHT
	var frame_z := -6.0 if rifle else -3.0
	root.add_child(_box("FrameL", Vector3(0.25, 1.8, 0.3), Vector3(-0.9, frame_y, frame_z), metal))
	root.add_child(_box("FrameR", Vector3(0.25, 1.8, 0.3), Vector3(0.9, frame_y, frame_z), metal))
	root.add_child(_box("FrameB", Vector3(2.05, 0.25, 0.3), Vector3(0.0, frame_y - 0.78, frame_z), metal))
	root.add_child(_sphere("Dot", 0.16, Vector3(0.0, frame_y, frame_z + 0.1), dot))

func _box(node_name: String, size: Vector3, at: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.position = at
	mi.layers = WEAPON_LAYER
	return mi

func _sphere(node_name: String, radius: float, at: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 12
	mesh.rings = 6
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.position = at
	mi.layers = WEAPON_LAYER
	return mi
