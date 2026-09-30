## 靶（票 01 第 7 节）：只作为**可命中的受击体**存在，不含 AI。
##
## 命中体不另开隐形 hitbox，直接用角色模型各部件自身的几何：把每个网格在「靶」局部空间里的
## 包围盒做成盒子碰撞形状逐个挂上，所见即所中。「体型半径」只缩放水平方向（x/z），身高不变。
## 爆头靠命中形状所属的部件名判定（名字含 head / helmet），见 `is_headshot`。
## 模型缺失时回落到程序化圆柱 + 头球，保证靶始终打得中。
##
## 切片一只做**最简恒定侧移**：沿一个固定轴来回平移，不做躲避、不探测、不开火。

class_name Target
extends StaticBody3D

const MAX_HP := 600
const RESPAWN_DELAY := 1.5 ## 死亡到重新出现的间隔
const STRAFE_SPEED := 70.0 ## 恒定侧移速度
const STRAFE_RANGE := 80.0 ## 侧移往返的半幅

## KayKit Adventurers（CC0）角色模型（ADR-0007）。
const MODEL := "res://assets/third_party/kaykit-adventurers/character/Knight.glb"
const MODEL_FACE_YAW := PI ## 模型朝向与玩家视线相反，转 180° 让它面对玩家

## 判为「头」的部件名关键词（小写包含匹配）。
const HEAD_PART_KEYWORDS: Array[String] = ["head", "helmet"]

signal died

var hp := MAX_HP
var alive := false

var _anchor := Vector3.ZERO
var _axis := Vector3.RIGHT
var _offset := 0.0
var _dir := 1.0
var _respawn_left := 0.0

## 本体的全部命中形状（模型部件盒，或模型缺失时的兜底形状）。
var _hit_shapes: Array[CollisionShape3D] = []

func _ready() -> void:
	_build_hit_body()

## 用模型自身几何建命中体；模型缺失时回落到程序化兜底。
func _build_hit_body() -> void:
	var inst := _instantiate_model()
	if inst == null:
		_build_fallback_shapes()
		return
	var box := _model_aabb(inst)
	if box.size.y <= 0.0:
		inst.queue_free()
		_build_fallback_shapes()
		return
	# 模型按「总高 72」缩放并落地对齐（可尺寸之外的位置与朝向都由这个 holder 承担）
	var holder := Node3D.new()
	holder.name = "Character"
	holder.scale = Vector3.ONE * (Physique.TOTAL_HEIGHT / box.size.y)
	holder.rotation = Vector3(0.0, MODEL_FACE_YAW, 0.0)
	var hi := box.position + box.size
	inst.position = Vector3(
		-(box.position.x + hi.x) * 0.5, -box.position.y, -(box.position.z + hi.z) * 0.5
	)
	holder.add_child(inst)
	add_child(holder)
	_add_part_shapes(inst, Transform3D.IDENTITY, holder.transform)

func _instantiate_model() -> Node3D:
	if not ResourceLoader.exists(MODEL):
		return null
	var packed := load(MODEL)
	if not (packed is PackedScene):
		return null
	return (packed as PackedScene).instantiate() as Node3D

## 递归遍历模型，把每个网格在「靶」局部空间里的包围盒做成一个盒子碰撞形状。
func _add_part_shapes(node: Node, xf: Transform3D, holder_xf: Transform3D) -> void:
	var local := xf
	if node is Node3D:
		local = xf * (node as Node3D).transform
	if node is MeshInstance3D:
		_add_box_shape(str(node.name), holder_xf * local * (node as MeshInstance3D).get_aabb())
	for child in node.get_children():
		_add_part_shapes(child, local, holder_xf)

func _add_box_shape(part_name: String, box: AABB) -> void:
	if box.size.x <= 0.0 or box.size.y <= 0.0 or box.size.z <= 0.0:
		return
	var shape := BoxShape3D.new()
	shape.size = box.size
	var collider := CollisionShape3D.new()
	collider.name = part_name
	collider.shape = shape
	collider.position = box.position + box.size * 0.5
	add_child(collider)
	_hit_shapes.append(collider)

## 模型缺失时的兜底命中体：圆柱身体 + 头球，尺寸取 `Physique` 的参考体型。
func _build_fallback_shapes() -> void:
	var body := CollisionShape3D.new()
	body.name = "FallbackBody"
	var body_shape := CylinderShape3D.new()
	body_shape.radius = Physique.BODY_RADIUS
	body_shape.height = Physique.BODY_HEIGHT
	body.shape = body_shape
	body.position = Vector3(0.0, Physique.BODY_HEIGHT * 0.5, 0.0)
	add_child(body)
	_hit_shapes.append(body)

	var head := CollisionShape3D.new()
	head.name = "FallbackHead"
	var head_shape := SphereShape3D.new()
	head_shape.radius = Physique.HEAD_RADIUS
	head.shape = head_shape
	head.position = Vector3(0.0, Physique.HEAD_CENTER_Y, 0.0)
	add_child(head)
	_hit_shapes.append(head)

## 射线命中的形状是否属于头部部件——`shape_index` 取自 `intersect_ray` 的 `"shape"`。
func is_headshot(shape_index: int) -> bool:
	var owner_id := shape_find_owner(shape_index)
	if owner_id < 0:
		return false
	var collider := shape_owner_get_owner(owner_id)
	if collider == null:
		return false
	var lower := str(collider.name).to_lower()
	for keyword in HEAD_PART_KEYWORDS:
		if lower.contains(keyword):
			return true
	return false

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

## 在指定位置出现：满血、可见、可命中。
func spawn(at: Vector3, strafe_axis: Vector3 = Vector3.RIGHT) -> void:
	_anchor = at
	_axis = strafe_axis.normalized() if strafe_axis.length() > 1e-6 else Vector3.RIGHT
	_offset = 0.0
	_dir = 1.0
	hp = MAX_HP
	alive = true
	_respawn_left = 0.0
	visible = true
	_set_hittable(true)
	global_position = _anchor

## 命中一次。返回本次是否造成击杀。
func take_hit(damage: int) -> bool:
	if not alive:
		return false
	hp = maxi(hp - damage, 0)
	if hp > 0:
		return false
	alive = false
	_respawn_left = RESPAWN_DELAY
	visible = false
	_set_hittable(false)
	died.emit()
	return true

## 推进计时与侧移。返回本帧是否刚好「该刷新了」（由 main 负责决定刷到哪）。
func advance(delta: float) -> bool:
	if not alive:
		if _respawn_left <= 0.0:
			return false
		_respawn_left -= delta
		return _respawn_left <= 0.0
	if STRAFE_SPEED > 0.0:
		_offset += _dir * STRAFE_SPEED * delta
		if absf(_offset) >= STRAFE_RANGE:
			_offset = clampf(_offset, -STRAFE_RANGE, STRAFE_RANGE)
			_dir = -_dir
		global_position = _anchor + _axis * _offset
	return false

## 设置「体型半径」：只缩放水平（x/z），身高与头心高度不变。
func apply_body_radius(body_radius: float) -> void:
	var s := Physique.horizontal_scale(body_radius)
	scale = Vector3(s, 1.0, s)

func _set_hittable(on: bool) -> void:
	for collider in _hit_shapes:
		collider.disabled = not on
