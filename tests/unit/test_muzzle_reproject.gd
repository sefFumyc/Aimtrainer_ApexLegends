## FOV 差补偿（ADR-0021 二轮）的纯逻辑测试：恒等退化与开镜差下的投影一致性。

extends GutTest

const ASPECT := 16.0 / 9.0

## 手工投影：相机局部点 → NDC（与实现同式，用于验证「重投影前后 NDC 相等」这一性质）。
func _ndc(local: Vector3, fov: float, aspect: float) -> Vector2:
	var depth := -local.z
	var t := tan(deg_to_rad(fov) * 0.5)
	return Vector2(local.x / (depth * t * aspect), local.y / (depth * t))

func test_identity_when_fovs_equal_and_transforms_shared() -> void:
	# 腰射退化：两相机同变换同 FOV → 数学恒等，原样返回
	var xf := Transform3D(Basis.from_euler(Vector3(0.1, 0.4, 0.0)), Vector3(1.0, 2.0, 3.0))
	var pt := xf * Vector3(0.5, -0.3, -10.0)
	var out := MuzzleReproject.reproject(pt, xf, 92.35, xf, 92.35, ASPECT)
	assert_almost_eq(out.x, pt.x, 1e-6)
	assert_almost_eq(out.y, pt.y, 1e-6)
	assert_almost_eq(out.z, pt.z, 1e-6)

func test_ads_fov_gap_keeps_ndc_and_depth_through_main_camera() -> void:
	# 开镜差（92.35 → 76.64，zoom_p = 1）：重投影后的点经主相机投影出的 NDC
	# 必须与原点经武器相机投影的 NDC 一致，且深度不变（同深度重投影的定义）。
	var weapon_xf := Transform3D(Basis.from_euler(Vector3(0.05, 0.3, 0.0)), Vector3(1.0, 2.0, 3.0))
	var main_xf := Transform3D(Basis.from_euler(Vector3(0.0, 0.0, 0.0)), Vector3.ZERO)
	var pt := weapon_xf * Vector3(0.8, -0.4, -12.0)
	var out := MuzzleReproject.reproject(pt, weapon_xf, 92.35, main_xf, 76.64, ASPECT)
	var ndc_weapon := _ndc(weapon_xf.affine_inverse() * pt, 92.35, ASPECT)
	var local_main := main_xf.affine_inverse() * out
	var ndc_main := _ndc(local_main, 76.64, ASPECT)
	assert_almost_eq(ndc_main.x, ndc_weapon.x, 1e-6)
	assert_almost_eq(ndc_main.y, ndc_weapon.y, 1e-6)
	assert_almost_eq(-local_main.z, -(weapon_xf.affine_inverse() * pt).z, 1e-6, "同深度")

func test_ads_gap_moves_offaxis_point_and_keeps_axis_point() -> void:
	# 离轴点：FOV 有差时输出必须偏离输入（防「恒等」回归）——满开镜枪口离轴越远偏得越多。
	var weapon_xf := Transform3D(Basis.from_euler(Vector3(0.05, 0.3, 0.0)), Vector3(1.0, 2.0, 3.0))
	var main_xf := Transform3D(Basis.from_euler(Vector3(0.0, 0.0, 0.0)), Vector3.ZERO)
	var pt := weapon_xf * Vector3(0.8, -0.4, -12.0)
	var out := MuzzleReproject.reproject(pt, weapon_xf, 92.35, main_xf, 76.64, ASPECT)
	assert_gt((out - pt).length(), 1e-3, "离轴点被移动")
	# 轴上点：NDC 恒为 (0, 0)，无论 FOV 与变换如何都落在主相机轴上同深度处
	# （float32 在带旋转变换下的噪声 ~1e-7 量级，容差放宽到 1e-5）。
	var axis_pt := weapon_xf * Vector3(0.0, 0.0, -10.0)
	var axis_out := MuzzleReproject.reproject(axis_pt, weapon_xf, 92.35, main_xf, 76.64, ASPECT)
	assert_almost_eq(axis_out.x, 0.0, 1e-5)
	assert_almost_eq(axis_out.y, 0.0, 1e-5)
	assert_almost_eq(axis_out.z, -10.0, 1e-5)
