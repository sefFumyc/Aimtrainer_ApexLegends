# 07 — 开镜准星淡出 + 滑铲镜头动态

Status: done

术语以 `CONTEXT.md` 为准（「准星」词条本票更新、「滑铲镜头动态」为本票新增）。依赖票 01–06（全部已 done）。

## 目标

两个试玩反馈，全部是**表现层**，不动移动数值、伤害、命中判定与弹道：

1. 开镜时白准星与红点镜的红点重合，干扰瞄准——准星随「开镜进度」平滑淡出（透明度 = 1 − 进度）；
2. 滑铲时镜头太僵硬——加「滑铲镜头动态」：动态侧倾 + FOV 微扩（现代 FPS 手感）。

## 清单与验收

### 1. 准星随开镜进度淡出

`hud.gd` 白准星透明度 = 1 − zoom_p（挂在同一根 p 上，开关镜全程无跳变）；「击中提示」X 与对局数字不受影响、全时保留。`main.gd` 每帧把 `player.zoom_p` 喂给 hud。
- 验收：开镜白点渐隐、满开镜完全不可见；命中 X 照常闪现。

### 2. 滑铲镜头动态（纯渲染）

`player.gd`：
- 侧倾（相机 roll）：跟随滑铲速度在视线**左右方向**的分量（直铲几乎不倾、横铲明显侧倾），指数缓入缓出；
- FOV 微扩：在 `lerp(FOV, ZOOM_FOV, zoom_p)` 之上叠加约 +4°，随滑铲指数缓入缓出；
- 两者幅度统一乘 (1 − zoom_p)：满开镜收敛到 0（开镜要稳）。

`movement.gd` 的 Apex 实测数值一律不碰；`aim_direction` 只读逻辑 yaw/pitch，弹道零改动（与「视觉后坐力」同构）。
- 验收：滑铲有侧倾与速度感、松开自然回正；开镜滑铲画面稳；GUT 全绿。

### 3. 开镜枪体 kick 衰减（试玩追加）

试玩反馈：开镜后枪械上下跳（Apex 不这样）。`viewmodel.gd _apply_rig` 枪体 kick（后坐位移 + 上抬角）按 (1 − zoom_p) 衰减——开镜红点要贴准星轴，枪模跳会把它弹离轴心；后坐感由相机踢承担（视角动、红点跟视角走、相对静止）。腰射 kick 不变。
- 验收：满开镜连发枪模几乎不动，红点不弹离准星轴。

## 备注

- 全票表现层；`aim_direction` 与 `movement.gd` 零改动，无新纯逻辑缝（不加测试，跑全量回归）。
- grilling 定稿（2026-10-02）：淡出选平滑（Q1b）、侧倾选动态分量（Q2b）、FOV 加（Q3a）、开镜收敛（Q4a）。
- 数值定稿沿用票 05/06 流程：实现 → 试玩 → 用户点头 → 清理 → 提交。

## Comments / 2026-10-02 — 实现收尾（agent）

**准星淡出**：`hud.gd` 新增 `set_zoom(p)`（clamp 0..1），`_draw_crosshair` 白准星透明度 = (1 − p) × CROSSHAIR_COLOR.a，alpha ≤ 0.004 早退；命中 X 与对局数字不动。`main.gd _process` 每帧把 `player.zoom_p` 喂给 hud，淡出与开镜动画同频、全程无跳变。

**滑铲镜头动态**：`player.gd` 新增常数块（SLIDE_ROLL_MAX=0.061 / SLIDE_ROLL_SPEED_REF=299 / SLIDE_ROLL_RATE=6 / SLIDE_FOV_ADD=4.0 / SLIDE_FOV_RATE=7.0）与 `_tick_slide_cam(delta)`：sim 处于 sliding 时取速度的视线左右分量（lateral = v.x·cos(yaw) − v.y·sin(yaw)）驱动侧倾目标、FOV 目标 +4°，指数缓入缓出，幅度乘 (1 − zoom_p) 满开镜收敛到 0。`camera.rotation` 的 roll 位、`camera.fov` 的开镜缩放叠加位分别接上。`movement.gd` 实测数值零改动，`aim_direction` 只读逻辑 yaw/pitch，弹道零改动。

**开镜枪体 kick 衰减**（试玩追加）：`viewmodel.gd _apply_rig` 枪体后坐位移与上抬角按 (1 − zoom_p) 衰减——开镜红点贴准星轴，后坐感由相机踢承担（Apex 手感），腰射 kick 不变。

**验收**：GUT 全量回归 145 tests / 1148 asserts 全绿；主场景冒烟无报错；用户两轮试玩定稿通过（「还ok」「ok」）。
