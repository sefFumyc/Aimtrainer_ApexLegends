## 圆形场地（ADR-0004）：半径 1000 的程序化地面 + 环形围墙 + 可切换布局的遮挡物。
##
## 全部几何由脚本生成，`.tscn` 只挂这个脚本（省掉手写一长串子资源）。
## 边界判定是**径向**的，由 `MovementSimulator` 负责（ADR-0004）；围墙自 ADR-0031 起
## **是实体**（挡移动 + 挡射线 + 吃子弹，与遮挡物同性质），径向钳制退为兜底；
## 遮挡物则**参与碰撞且参与射线**（票 01 第 3 节），层用默认的 1。

class_name Arena
extends Node3D

const RADIUS := MovementSimulator.ARENA_RADIUS
const WALL_HEIGHT := 400.0
## 围墙碰撞环的分段盒的径向厚度：内表面贴在半径 RADIUS 上，盒体全部落在圆外那一侧。
const WALL_THICKNESS := 40.0
## 地面网格径向段数：96 段在 2000 单位直径下看不出多边形棱角。
const GROUND_SEGMENTS := 96

const GROUND_COLOR := Color(0.82, 0.73, 0.50)
const WALL_COLOR := Color(0.70, 0.61, 0.42)
const COVER_COLOR := Color(0.55, 0.48, 0.36)

var _covers_root: Node3D
var _covers: Array = []

## 当前生成的遮挡物清单（每项同 `CoverLayout.generate` 的元素，另加节点引用不对外暴露）。
func covers() -> Array:
	return _covers

func _ready() -> void:
	_build_ground()
	_build_wall()
	_covers_root = Node3D.new()
	_covers_root.name = "Covers"
	add_child(_covers_root)

## 按「场地布局」档位重建遮挡物。`avoid` 是必须避开的点（玩家出生点 / 靶刷新点）。
## 设置里切档后再次调用即可（先清空再重建）。
func configure(layout: int, avoid: Array = [Vector2.ZERO]) -> void:
	for child in _covers_root.get_children():
		_covers_root.remove_child(child)
		child.queue_free()
	_covers = CoverLayout.generate(layout, RADIUS, avoid)
	for c in _covers:
		_covers_root.add_child(_make_cover(c))

## 给定平面点是否落在任一遮挡物内（含余量）——靶刷新点避让与调试用。
func is_blocked(p: Vector2, margin := 0.0) -> bool:
	for c in _covers:
		if p.distance_to(c["pos"]) < float(c["foot"]) + margin:
			return true
	return false

func _build_ground() -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = RADIUS
	mesh.bottom_radius = RADIUS
	mesh.height = 2.0
	mesh.radial_segments = GROUND_SEGMENTS
	mesh.material = _material(GROUND_COLOR, 1.0)

	var shape := CylinderShape3D.new()
	shape.radius = RADIUS
	shape.height = 2.0

	add_child(_build_static("Ground", mesh, shape, Vector3(0.0, -1.0, 0.0)))

func _build_wall() -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = RADIUS
	mesh.bottom_radius = RADIUS
	mesh.height = WALL_HEIGHT
	mesh.radial_segments = GROUND_SEGMENTS
	# 去掉上下封盖：顶盖是一张半径 1000 的圆盘，从圈内看就是一块盖住天空的「天花板」。
	mesh.cap_top = false
	mesh.cap_bottom = false
	# 从圈内看墙，看到的是背面：关掉背面剔除，否则墙会「透明」。
	mesh.material = _material(WALL_COLOR, 1.0, true)

	var mi := MeshInstance3D.new()
	mi.name = "Wall"
	mi.mesh = mesh
	mi.position = Vector3(0.0, WALL_HEIGHT * 0.5, 0.0)
	add_child(mi)
	# 视觉是 96 段圆柱（顶点在半径 RADIUS 上、平面略内凹 0.5u），碰撞环的内表面取 RADIUS：
	# 玩家胶囊半径 8 恒大于这点差，相机不会贴进墙面（ADR-0031）。
	add_child(_build_wall_body())

## 围墙的实体碰撞（ADR-0031）：`GROUND_SEGMENTS` 段盒环近似这个圆，每段盒的**内表面**
## 贴在半径 `RADIUS` 上（盒体在圆外那一侧），归世界层——挡移动、挡射线、吃子弹。
## 用凸盒而非凹面网格：零厚度的凹面在高横向速度下可被隧穿，且去穿透不如凸体稳健。
func _build_wall_body() -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "WallBody"
	body.collision_layer = 1
	body.collision_mask = 1
	# 盒宽取「外缘半径处的切线跨度」再留 2% 重叠：按内缘算会在外缘相邻盒之间漏出细缝，
	# 按外缘算则在整条径向厚度上都互相重叠——静态盒重叠无副作用，留缝却会漏出「钻墙缝」。
	var reach := RADIUS + WALL_THICKNESS
	var width := 2.0 * reach * tan(PI / float(GROUND_SEGMENTS)) * 1.02
	for i in GROUND_SEGMENTS:
		var angle := (float(i) + 0.5) * TAU / float(GROUND_SEGMENTS)
		var bs := BoxShape3D.new()
		bs.size = Vector3(width, WALL_HEIGHT, WALL_THICKNESS)
		var cs := CollisionShape3D.new()
		cs.shape = bs
		cs.position = Vector3(
			(RADIUS + WALL_THICKNESS * 0.5) * cos(angle),
			WALL_HEIGHT * 0.5,
			(RADIUS + WALL_THICKNESS * 0.5) * sin(angle),
		)
		# 盒的局部 +Z 转到该段中点的径向朝外方向（`rotation.y = α` 把 +Z 映射到 (sin α, 0, cos α)），
		# 于是局部 X 自动成为切线方向、宽度沿切线铺开。
		cs.rotation.y = PI * 0.5 - angle
		body.add_child(cs)
	return body

func _make_cover(c: Dictionary) -> StaticBody3D:
	var foot: float = c["foot"]
	var height: float = c["height"]
	var pos: Vector2 = c["pos"]
	var at := Vector3(pos.x, height * 0.5, pos.y)

	if int(c["shape"]) == CoverLayout.SHAPE_CYLINDER:
		var cyl := CylinderMesh.new()
		cyl.top_radius = foot
		cyl.bottom_radius = foot
		cyl.height = height
		cyl.radial_segments = 20
		cyl.material = _material(COVER_COLOR, 0.9)
		var cs := CylinderShape3D.new()
		cs.radius = foot
		cs.height = height
		return _build_static("CoverCylinder", cyl, cs, at)

	var box := BoxMesh.new()
	box.size = Vector3(foot * 2.0, height, foot * 2.0)
	box.material = _material(COVER_COLOR, 0.9)
	var bs := BoxShape3D.new()
	bs.size = Vector3(foot * 2.0, height, foot * 2.0)
	return _build_static("CoverBox", box, bs, at)

## 造一个「网格 + 碰撞」的静态体：移动被它挡住，射击被它挡住（层 1）。**不挂进场景树**，
## 由调用方决定挂到哪（地面挂 Arena，遮挡物挂 Covers）。
func _build_static(node_name: String, mesh: Mesh, shape: Shape3D, at: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = at
	body.collision_layer = 1
	body.collision_mask = 1

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	body.add_child(mi)

	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	return body

func _material(color: Color, roughness: float, cull_disabled := false) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	if cull_disabled:
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat
