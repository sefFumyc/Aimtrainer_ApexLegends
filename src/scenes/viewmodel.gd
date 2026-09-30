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

## 武器层（`VisualInstance3D.layers` 的第 2 位）：只被武器相机看见。
const WEAPON_LAYER := 2

## 腰射基准位姿（参考实现 applyZoom 的 p = 0 端点）。
const GUN_BASE_POS := Vector3(13.0, -8.0, -15.0)
const GUN_BASE_YAW := -0.12
const GUN_BASE_PITCH := -0.06
## 准镜中线相对武器挂点的高度——只给**程序化兜底几何**用；换 GLB 后由 `_fit_model()`
## 把模型顶面压到 y = 0，`_sight_y` 随之变成 0（ADR-0007）。
const PROC_SIGHT_HEIGHT := 2.6
## 满开镜时武器挂点相对相机的横向/纵深位置（x 居中、向前推远到不糊脸）。
const ADS_Z := -8.0

## 枪口在武器挂点本地坐标 = 拟合后的枪管前端（参考实现 ADR-0022：步枪 (0,0,-25)）。
const RIFLE_MUZZLE_LOCAL := Vector3(0.0, 0.0, -25.0)
const PISTOL_MUZZLE_LOCAL := Vector3(0.0, 0.0, -7.5)
## 两把枪拟合后的总长（枪口端到握把端）。
const RIFLE_LENGTH := 25.0
const PISTOL_LENGTH := 7.5

## Kenney Blaster Kit（CC0）模型路径；文件不存在时回落到程序化几何。
const RIFLE_MODEL := "res://assets/third_party/kenney_blaster-kit/rifle/blaster-e.glb"
const PISTOL_MODEL := "res://assets/third_party/kenney_blaster-kit/pistol/blaster-k.glb"

const METAL := Color(0.16, 0.17, 0.20)
const GRIP := Color(0.28, 0.25, 0.22)
const DOT_COLOR := Color(0.95, 0.22, 0.18)

@onready var weapon_camera: Camera3D = $SubViewport/WeaponCamera
@onready var rig: Node3D = $SubViewport/WeaponCamera/WeaponRig

var _rifle: Node3D
var _pistol: Node3D
var _weapon: StringName = Weapon.RIFLE
var _zoom := 0.0
## 准镜中线在武器挂点本地的高度；GLB 拟合后模型顶面即 y = 0，这里就是 0。
var _sight_y := PROC_SIGHT_HEIGHT

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

## 开镜进度 p（0 腰射 / 1 满开镜）。
## 俯仰角在满开镜时归零——否则那 −0.06 的枪口下压会把准镜带离准星轴。
func apply_zoom(p: float) -> void:
	_zoom = clampf(p, 0.0, 1.0)
	rig.position = GUN_BASE_POS.lerp(Vector3(0.0, -_sight_y, ADS_Z), _zoom)
	rig.rotation = Vector3(GUN_BASE_PITCH * (1.0 - _zoom), GUN_BASE_YAW * (1.0 - _zoom), 0.0)

## 当前武器枪口的世界坐标（火光与曳光弹的起点）。
func muzzle_world() -> Vector3:
	var local := RIFLE_MUZZLE_LOCAL if Weapon.is_rifle(_weapon) else PISTOL_MUZZLE_LOCAL
	return rig.to_global(local)

func _build_weapon(node_name: String, id: StringName) -> Node3D:
	var root := Node3D.new()
	root.name = node_name
	var rifle := Weapon.is_rifle(id)
	var loaded := _try_load_model(RIFLE_MODEL if rifle else PISTOL_MODEL)
	if loaded != null:
		root.add_child(_fit_model(loaded, RIFLE_LENGTH if rifle else PISTOL_LENGTH))
		_sight_y = 0.0 # 拟合把模型顶面压在 y = 0，准镜轴就是顶面
	else:
		_build_procedural(root, id)
	return root

## 把模型摆进武器挂点空间：沿 Y 翻 180°（模型 +Z 朝前 → 挂点的 −Z 朝前）、
## 缩放到约定总长、顶面压到 y = 0（准镜轴）、枪口端压到 z = −length、左右居中。
## 全部由模型自身的包围盒算出，不含手填数字。
func _fit_model(model: Node3D, length: float) -> Node3D:
	var box := _model_aabb(model)
	if box.size.z <= 0.0:
		return model
	var s := length / box.size.z
	var hi := box.position + box.size
	var holder := Node3D.new()
	holder.name = "Model"
	holder.rotation = Vector3(0.0, PI, 0.0)
	holder.scale = Vector3.ONE * s
	holder.position = Vector3(
		s * (box.position.x + hi.x) * 0.5, # 左右居中
		-hi.y * s, # 顶面 → y = 0
		box.position.z * s # 枪口端 → z = −length
	)
	holder.add_child(model)
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

## GLB 自带的图层不一定是我们约定的武器层，逐个改掉。
func _set_weapon_layers(node: Node) -> void:
	if node is VisualInstance3D:
		(node as VisualInstance3D).layers = WEAPON_LAYER
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
