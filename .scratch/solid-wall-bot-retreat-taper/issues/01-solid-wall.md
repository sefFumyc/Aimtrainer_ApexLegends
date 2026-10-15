# 01 围墙实体化（世界层碰撞）

Status: ready-for-human

## 目标

`arena.gd` 的环形围墙从纯视觉 `MeshInstance3D` 改为**实体**：`StaticBody3D` + 96 个 `BoxShape3D` 盒环（段数沿用 `GROUND_SEGMENTS`，内表面与视觉那个圆同半径 1000，高度沿用 `WALL_HEIGHT`），归世界层（`collision_layer = 1`，与 `_build_static()` 的装配一致）。径向钳制（`movement.gd` L238-251）**保留**为兜底。

## 要点

- 盒环按段数均分圆周，每段盒的**内表面**贴着半径 1000 的圆（即盒体在圆外那一侧），保证内表面就是玩家/ bot 撞到的那一面。
- 顺手改掉「围墙不挂碰撞」的注释；`target.gd` L29-33 那句「世界（地面 / 遮挡物 / 围墙）层」加碰撞后自洽，无需改。
- 不引入 `ConcavePolygonShape3D`（零厚度、可隧穿）——见 ADR-0031 的考虑过的选项。
- 单帧成本：96 个静态盒对性能无感，但**实现后跑一次 `--print-fps` 或 `nvidia-smi pmon` 对照**，确认没有物理陡增。

## 验收

实机（`arena.gd` 不在 GUT 的纯逻辑缝上）：贴墙左右滑 + 往墙里顶，相机（含近裁剪面）不再穿出墙外；玩家与 bot 都被拦在墙内；子弹与曳光打到墙即止。

## Comments

2026-10-15（实现）：`arena.gd` 新增 `WALL_THICKNESS = 40.0` 与 `_build_wall_body()`——1 个 `StaticBody3D` + `GROUND_SEGMENTS` 个 `BoxShape3D`，层 1，盒心在半径 `RADIUS + 20`、局部 +Z 经 `rotation.y = π/2 − α` 转到该段径向朝外，故内表面恰贴半径 1000。盒宽按**外缘半径**（`RADIUS + WALL_THICKNESS`）的切线跨度 ×1.02 算——按内缘算会在外缘相邻盒之间留细缝。

临时探针实测（`.scratch/probe_wall.tscn`，已删）：192 条射线（在 96 段的中点与段缝上交替取向）**零漏缝**，命中半径 1000.00–1000.54（0.54 = 96 边形相对圆的矢高，与视觉网格同量级）；从半径 992 朝外顶的射线命中墙面。

拦截 + 开销实测（`.scratch/probe_wall2.tscn`，已删）：与 Player 同构的胶囊（半径 8、高 72）从半径 992 处每帧 300 u/s 朝墙外顶，**停在 r = 992.53**——进不到墙面（1000）附近，相机近裁剪面因此不可能穿出。物理开销 A/B（同场景、同角色运动，各 300 步取平均）：墙在 **0.442 ms/step** / 摘掉墙环 **0.283 ms/step** ⇒ 整条环的边际成本 ≈ **0.16 ms/step**，60 Hz 下约占单帧预算 1%，无物理陡增。`--headless --path . --quit` 冒烟跑通主场景（Arena 实例化、无脚本报错）。

待用户实机验收本项目标。
