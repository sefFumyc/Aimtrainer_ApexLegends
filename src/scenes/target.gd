## 靶（票 01 第 7 节）：只作为**可命中的受击体**存在，不含 AI。
##
## 命中几何与玩家同构（`Physique`）：身体是圆柱（半径 8、高 60、中心 y=30），
## 头是球（半径 6、球心 y=66）；「体型半径」只缩放水平方向，身高与头心高度不变。
## 头部单独挂一个 `Area3D`，射线命中它即判爆头——用节点类型判定，不靠形状下标。
##
## 切片一只做**最简恒定侧移**：沿一个固定轴来回平移，不做躲避、不探测、不开火。

class_name Target
extends StaticBody3D

const MAX_HP := 600
const RESPAWN_DELAY := 1.5 ## 死亡到重新出现的间隔
const STRAFE_SPEED := 70.0 ## 恒定侧移速度
const STRAFE_RANGE := 80.0 ## 侧移往返的半幅

## KayKit Adventurers（CC0）角色模型（ADR-0007）；缺失时回落到程序化圆柱 + 头球。
## 只换**可见外形**，命中几何仍是 `Physique` 的圆柱 + 头球（票 01 第 7 节）。
const MODEL := "res://assets/third_party/kaykit-adventurers/character/Knight.glb"
const MODEL_FACE_YAW := PI ## 模型朝向与玩家视线相反，转 180° 让它面对玩家

signal died

@onready var body_mesh: MeshInstance3D = $BodyMesh
@onready var head_mesh: MeshInstance3D = $HeadMesh
@onready var body_shape: CollisionShape3D = $CollisionShape3D
@onready var head_area: Area3D = $Head

var hp := MAX_HP
var alive := false

var _anchor := Vector3.ZERO
var _axis := Vector3.RIGHT
var _offset := 0.0
var _dir := 1.0
var _respawn_left := 0.0

func _ready() -> void:
	_load_model()

## 把角色模型按「总高 72」缩放并落地对齐，替换掉程序化外形。
func _load_model() -> void:
	if not ResourceLoader.exists(MODEL):
		return
	var packed := load(MODEL)
	if not (packed is PackedScene):
		return
	var inst: Node3D = (packed as PackedScene).instantiate()
	var box := _model_aabb(inst)
	if box.size.y <= 0.0:
		inst.queue_free()
		return
	var hi := box.position + box.size
	var holder := Node3D.new()
	holder.name = "Character"
	holder.scale = Vector3.ONE * (Physique.TOTAL_HEIGHT / box.size.y)
	holder.rotation = Vector3(0.0, MODEL_FACE_YAW, 0.0)
	inst.position = Vector3(
		-(box.position.x + hi.x) * 0.5, -box.position.y, -(box.position.z + hi.z) * 0.5
	)
	holder.add_child(inst)
	add_child(holder)
	body_mesh.visible = false
	head_mesh.visible = false

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
	body_shape.disabled = not on
	head_area.collision_layer = 1 if on else 0
