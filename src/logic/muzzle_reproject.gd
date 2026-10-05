## 枪口特效起点的开镜 FOV 差补偿（ADR-0021 二轮修订）——纯逻辑缝。
##
## ADR-0008 武器 SubViewport 隔离：两个世界坐标数值等同但相机 FOV 不同
## （开镜只缩主相机 92.35 → 76.64，武器相机恒 92.35），同一个 3D 点投影出的
## 屏幕位置不一致，满开镜时曳光/火光相对准星残留反向偏移。这里把武器相机
## 视锥里的枪口点经 NDC 换算到主相机**同深度**的世界坐标：两相机 FOV 相等
## 时数学上退化为恒等，腰射零改动。供 `Player.muzzle_world`（场景侧只负责
## 取相机与枪口点）调用，GUT 可测。

class_name MuzzleReproject

## 把世界点 `muzzle_pt` 从武器相机视锥重投影到主相机同深度。
## `weapon_xform` / `main_xform` 为两相机的全局变换，`weapon_fov` / `main_fov`
## 为各自垂直 FOV（度），`aspect` 为视口宽高比（两相机相同，KEEP_HEIGHT）。
static func reproject(
	muzzle_pt: Vector3,
	weapon_xform: Transform3D,
	weapon_fov: float,
	main_xform: Transform3D,
	main_fov: float,
	aspect: float,
) -> Vector3:
	var local_pt := weapon_xform.affine_inverse() * muzzle_pt ## 武器相机局部（前方 z < 0）
	var depth := -local_pt.z
	var tan_weapon := tan(deg_to_rad(weapon_fov) * 0.5)
	var tan_main := tan(deg_to_rad(main_fov) * 0.5)
	var ndc := Vector2(
		local_pt.x / (depth * tan_weapon * aspect),
		local_pt.y / (depth * tan_weapon),
	)
	return main_xform * (Vector3(ndc.x * tan_main * aspect, ndc.y * tan_main, -1.0) * depth)
