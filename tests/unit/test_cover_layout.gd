## 场地遮挡物布局的行为测试（ADR-0004 / 票 01 验收条件 7）。
##
## 断言的是「数量、落点范围、避让、可复现、不重叠」这些外部可见性质，
## 不碰随机数内部状态，也不碰节点树。

extends GutTest

const RADIUS := MovementSimulator.ARENA_RADIUS

func test_open_layout_has_no_cover() -> void:
	assert_eq(CoverLayout.generate(CoverLayout.Layout.OPEN).size(), 0, "空旷档不生成遮挡物")

func test_sparse_and_dense_counts() -> void:
	assert_eq(CoverLayout.generate(CoverLayout.Layout.SPARSE).size(), 6, "少量遮挡 = 6")
	assert_eq(CoverLayout.generate(CoverLayout.Layout.DENSE).size(), 14, "多遮挡 = 14")

func test_covers_stay_inside_sampling_band() -> void:
	for c in CoverLayout.generate(CoverLayout.Layout.DENSE):
		var pos: Vector2 = c["pos"]
		var foot: float = c["foot"]
		var r := pos.length()
		assert_gte(r - foot, CoverLayout.BAND_INNER - foot, "落点不进入内圈")
		assert_gte(r, CoverLayout.BAND_INNER, "中心半径不小于内圈")
		assert_lte(r + foot, RADIUS, "含半径在内不越出场地围墙")
		assert_gt(r, 0.0, "不会落在圆心上")

func test_covers_avoid_spawn_points() -> void:
	# 玩家出生点在原点，靶刷新点在玩家前方 target_range 处（默认 120）
	var avoid: Array = [Vector2.ZERO, Vector2(0.0, -120.0)]
	var clearance := CoverLayout.DEFAULT_CLEARANCE
	for c in CoverLayout.generate(CoverLayout.Layout.DENSE, RADIUS, avoid, clearance):
		var pos: Vector2 = c["pos"]
		for p in avoid:
			assert_gte(
				pos.distance_to(p),
				clearance + float(c["foot"]),
				"遮挡物与出生点/刷新点之间留够净距"
			)

func test_layout_is_reproducible_across_runs() -> void:
	var a := CoverLayout.generate(CoverLayout.Layout.DENSE)
	var b := CoverLayout.generate(CoverLayout.Layout.DENSE)
	assert_eq(a.size(), b.size())
	for i in a.size():
		assert_eq(a[i]["pos"], b[i]["pos"], "同种子同档位得到同一套布局")
		assert_eq(a[i]["shape"], b[i]["shape"])

func test_covers_do_not_overlap_each_other() -> void:
	var covers := CoverLayout.generate(CoverLayout.Layout.DENSE)
	for i in covers.size():
		for j in range(i + 1, covers.size()):
			var need: float = float(covers[i]["foot"]) + float(covers[j]["foot"]) + CoverLayout.GAP
			assert_gte(covers[i]["pos"].distance_to(covers[j]["pos"]), need, "遮挡物之间不重叠")

func test_shape_and_size_are_sane() -> void:
	for c in CoverLayout.generate(CoverLayout.Layout.SPARSE):
		assert_true(c["shape"] == CoverLayout.SHAPE_BOX or c["shape"] == CoverLayout.SHAPE_CYLINDER)
		assert_between(float(c["foot"]), CoverLayout.FOOT_MIN, CoverLayout.FOOT_MAX, "底面半径在范围内")
		assert_between(float(c["height"]), CoverLayout.HEIGHT_MIN, CoverLayout.HEIGHT_MAX, "高度在范围内")
