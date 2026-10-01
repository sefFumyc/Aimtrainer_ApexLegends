## 靶（票 02）：移动与决策全在纯逻辑类 `BotAi` 里，本节点只是它的**碰撞载体与表现层**。
##
## `CharacterBody3D` 只做碰撞求解（与 Player 同构）：水平位移由 `BotAi.sim` 按固定子步算好，
## 这里每帧把「本帧位移 ÷ delta」喂给 `velocity`，`move_and_slide()` 后再把真实位置回写给 sim。
## 朝向每帧指向玩家（CONTEXT「朝向」）——侧移方向是相对朝向的，所以表现为围着玩家画弧。
##
## ❗ **移动碰撞体**与**命中体**是两件事（ADR-0014）：
## - 移动 = 半径 8、高 72 的胶囊（与 Player 同构），只挡遮挡物与地面，任何射线都看不见它；
## - 命中 = 模型各部件自身的几何：把每个网格在「靶」局部空间里的包围盒做成盒子碰撞形状，
##   逐个挂在子 `StaticBody3D` 上，所见即所中——打中盾牌、手臂、腿都算命中，打空气不算。
##
## 之所以分开：KayKit 骑士是 T 字绑定姿势，剑与盾横向伸出约 40 单位；若让部件盒同时充当移动碰撞体，
## 靶会在多遮挡布局下被柱角剐住——纯逻辑满速而 `move_and_slide()` 位移归零，原地卡死。
## 爆头靠命中形状所属的部件名判定（名字含 head / helmet），见 `is_headshot`。
## 模型缺失时回落到程序化圆柱 + 头球，保证靶始终打得中。
##
## 分层：移动本体在「靶移动层」（8）、命中体在「靶层」（2）、只与「世界层」（1）碰撞；
## 玩家本体在「玩家层」（4）。于是玩家与靶互不碰撞，而玩家开火射线（mask 1|2）只看得见命中体、
## bot 视线射线（mask 1|4）与探测射线（mask 1）只看得见世界。

class_name Target
extends CharacterBody3D

## 命中体所在层（玩家开火射线的 mask 含此层）。
const HIT_LAYER := 2
## 靶**移动本体**所在层：单独占一层，任何射线都不含它——它不是隐形 hitbox（CONTEXT「体型」）。
const MOVE_LAYER := 8
## 世界（地面 / 遮挡物 / 围墙）层：靶只与它碰撞。
const WORLD_LAYER := 1
## bot 枪口相对脚底的高度（曳光起点与视线射线起点）。
const MUZZLE_HEIGHT := 45.0

## KayKit Adventurers（CC0）角色模型（ADR-0007）。
const MODEL := "res://assets/third_party/kaykit-adventurers/character/Knight.glb"
## 模型自带朝向的补偿角：本体 `rotation.y` 已指向玩家，这里只补模型与 Godot −Z 前向的差。
const MODEL_FACE_YAW := PI

## 判为「头」的部件名关键词（小写包含匹配）。
const HEAD_PART_KEYWORDS: Array[String] = ["head", "helmet"]

var ai: BotAi
## 躲避与移动配置：与 `BotAi` 共用同一实例，设置改动就地生效（见 `main._apply_settings`）。
var config: AvoidanceController.Config

var _rng := RandomNumberGenerator.new()
## 命中体节点（模型部件盒挂它下面，只参与射线、不参与移动）。
var _hit_body: StaticBody3D
## 命中体的全部命中形状（模型部件盒，或模型缺失时的兜底形状）。
var _hit_shapes: Array[CollisionShape3D] = []

func _ready() -> void:
	visible = false
	_rng.randomize()
	config = AvoidanceController.Config.new()
	ai = BotAi.new(_rng, config, _probe_ray)
	_build_move_body()
	_build_hit_body()
	_set_hittable(false)

# ---- 对外接口 ----

## 在指定平面位置出现：满血、可见、可命中、清空开火状态。
func spawn(at: Vector2) -> void:
	ai.spawn(at)
	global_position = Vector3(at.x, 0.0, at.y)
	visible = true
	_set_hittable(true)

## 推进一帧：先让纯逻辑决策并积分，再把位移交给物理求解、位置回写。
## 返回本帧的开火结果（每项 = 该发是否命中玩家），由 main 结算扣血与表现。
func tick(delta: float, perception: BotAi.Perception) -> Array:
	var before := ai.sim.position()
	var shots := ai.update(delta, perception)
	if ai.alive:
		_apply_motion(delta, before, perception)
	visible = ai.alive
	_set_hittable(ai.alive)
	return shots

## 命中一次（伤害与感知一起交给 AI：非致命会触发躲避与受击反击）。返回本次是否击杀。
func take_hit(damage: int, perception: BotAi.Perception) -> bool:
	if not ai.alive:
		return false
	var lethal := ai.take_damage(damage, perception)
	if lethal:
		visible = false
		_set_hittable(false)
	return lethal

## 死亡后的刷新倒计时是否已走完（由 main 决定刷到哪）。
func needs_respawn() -> bool:
	return not ai.alive and ai.respawn_left <= 0.0

func hp() -> int:
	return ai.hp

## bot 枪口的世界坐标（曳光起点与视线射线起点）。
func muzzle_world() -> Vector3:
	return global_position + Vector3(0.0, MUZZLE_HEIGHT, 0.0)

## 命中体节点：开火射线打到的是它（不是本节点），调用方用它来判断「命中的是不是这个靶」。
func hit_body() -> CollisionObject3D:
	return _hit_body

## 射线命中的形状是否属于头部部件——`hit_body` 是射线命中的碰撞对象（本靶的命中体节点），
## `shape_index` 取自 `intersect_ray` 的 `"shape"`。做成 static 是因为命中的是命中体、不是本节点。
static func is_headshot(hit_body: CollisionObject3D, shape_index: int) -> bool:
	if hit_body == null:
		return false
	var owner_id := hit_body.shape_find_owner(shape_index)
	if owner_id < 0:
		return false
	var collider := hit_body.shape_owner_get_owner(owner_id)
	if collider == null:
		return false
	var lower := str(collider.name).to_lower()
	for keyword in HEAD_PART_KEYWORDS:
		if lower.contains(keyword):
			return true
	return false

## 设置「体型半径」：只缩放水平（x/z），身高与头心高度不变。
func apply_body_radius(body_radius: float) -> void:
	var s := Physique.horizontal_scale(body_radius)
	scale = Vector3(s, 1.0, s)

# ---- 移动表现 ----

## 把纯逻辑算出的本帧位移交给物理求解，再把求解结果回写给 sim（与 Player `_tick_move` 同构）。
## 「纯逻辑步长」与「物理实际位移」相差过大时交给 `BotAi.on_blocked` 兜底（ADR-0014）。
func _apply_motion(delta: float, before: Vector2, perception: BotAi.Perception) -> void:
	var after := ai.sim.position()
	var intended := after - before
	var step := intended / delta if delta > 1e-6 else Vector2.ZERO
	var start := global_position
	velocity = Vector3(step.x, 0.0, step.y)
	move_and_slide()
	ai.on_blocked(
		intended.length(), Vector2(global_position.x - start.x, global_position.z - start.z).length()
	)

	global_position.y = 0.0
	ai.sim.sync_position(Vector2(global_position.x, global_position.z))
	# 「朝向」= 始终指向玩家的水平方向（yaw 绕 +Y 右旋，前向 world = (-sin, -cos)）
	rotation.y = atan2(
		-(perception.player_x - global_position.x), -(perception.player_z - global_position.z)
	)

## 「前向探测」的射线实现（ADR-0005）：只探世界层（遮挡物），不探玩家与自身。
## 起点已在遮挡物内部时 `intersect_ray` 默认不报（`hit_from_inside = false`），
## 所以贴着柱子不会每帧都翻向、不会抖动。
func _probe_ray(origin: Vector2, dir: Vector2, length: float) -> bool:
	var from := Vector3(origin.x, MUZZLE_HEIGHT, origin.y)
	var query := PhysicsRayQueryParameters3D.create(
		from, from + Vector3(dir.x, 0.0, dir.y) * length, WORLD_LAYER
	)
	query.exclude = [get_rid()]
	return not get_world_3d().direct_space_state.intersect_ray(query).is_empty()

# ---- 碰撞载体 ----

## 移动碰撞体：半径 8、高 72 的胶囊（与 `player.tscn` 同一形状），只与「世界层」碰撞。
## 它承担靶与遮挡物/地面的碰撞求解，射线一律看不见它（不在任何射线的 mask 里）。
func _build_move_body() -> void:
	var shape := CapsuleShape3D.new()
	shape.radius = Physique.BODY_RADIUS
	shape.height = Physique.TOTAL_HEIGHT
	var collider := CollisionShape3D.new()
	collider.name = "MoveShape"
	collider.shape = shape
	collider.position = Vector3(0.0, Physique.TOTAL_HEIGHT * 0.5, 0.0)
	add_child(collider)

## 用模型自身几何建命中体；模型缺失时回落到程序化兜底。
## 形状挂在本节点（靶本体的原点）下的 `HitBody` 上，变换与视觉 holder 一致。
func _build_hit_body() -> void:
	_hit_body = StaticBody3D.new()
	_hit_body.name = "HitBody"
	_hit_body.collision_layer = HIT_LAYER
	_hit_body.collision_mask = 0 # 只被射线打到，不推任何东西
	add_child(_hit_body)
	var inst := _instantiate_model()
	if inst == null:
		_build_fallback_shapes()
		return
	var box := _model_aabb(inst)
	if box.size.y <= 0.0:
		inst.queue_free()
		_build_fallback_shapes()
		return
	# 模型按「总高 72」缩放并落地对齐（可尺寸之外的位置与朝向都由这个 holder 承担）。
	# ❗ 水平方向**不**做居中：KayKit 骑士把剑与盾向一侧伸出（AABB 单边到 2.0、另一边只到 -0.6），
	# 按 AABB 居中会把角色整体推离逻辑原点约 20 单位——准星与骑士错位、移动碰撞体也贴着空气。
	# 模型原点本身就是「角色脚下的中心」，只把脚底对到 y=0 即可。
	var holder := Node3D.new()
	holder.name = "Character"
	holder.scale = Vector3.ONE * (Physique.TOTAL_HEIGHT / box.size.y)
	holder.rotation = Vector3(0.0, MODEL_FACE_YAW, 0.0)
	inst.position = Vector3(0.0, -box.position.y, 0.0)
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
	_hit_body.add_child(collider)
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
	_hit_body.add_child(body)
	_hit_shapes.append(body)

	var head := CollisionShape3D.new()
	head.name = "FallbackHead"
	var head_shape := SphereShape3D.new()
	head_shape.radius = Physique.HEAD_RADIUS
	head.shape = head_shape
	head.position = Vector3(0.0, Physique.HEAD_CENTER_Y, 0.0)
	_hit_body.add_child(head)
	_hit_shapes.append(head)

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

func _set_hittable(on: bool) -> void:
	for collider in _hit_shapes:
		collider.disabled = not on