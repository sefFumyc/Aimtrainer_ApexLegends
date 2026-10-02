# 08 — 后坐力设置暴露 + 开镜行为按枪种区分

Status: done

术语以 `CONTEXT.md` 为准（「视觉后坐力」词条本票更新、「后坐力强度」为本票新增，均已落稿）。依赖票 05–07（全部已 done）。

## 目标

两个诉求，全部是**表现层 + 设置面**，不动移动数值、伤害、命中判定与弹道：

1. 把枪械抖动（枪体 kick）与相机抖动（相机踢）暴露成设置参数——4 条倍率滑条，按武器 × 通道分档；
2. 开镜枪体行为按枪种区分（Apex 手感对齐）：单发枪（手枪）开镜保留上下跳；连发枪（步枪）开镜变纯前后震。

## 清单与验收

### 1. 开镜行为按枪种区分（纯视觉）

`viewmodel.gd _apply_rig` 的 kick 衰减按武器拆分：
- **手枪**：kick 完全不衰减（damp 恒 1）——开镜上下跳与腰射一致（单发「沉」的手感）；
- **步枪**：上抬角 kick_pitch × (1 − zoom_p) 收敛到零（红点贴准星轴，枪模不上下跳）、前后位移 kick_pos **满幅保留**——满开镜呈纯前后震。

相机踢两枪开镜均保留现状（`player.gd` 不动开镜逻辑，开镜后坐感由相机踢承担）。
- 验收：满开镜手枪开火枪模上下跳如腰射；满开镜步枪开火枪模只有前后顶、不上跳；弹道不受任何影响。

### 2. GameSettings 新增 4 键 + 持久化

`game_settings.gd` 新增 4 个倍率键（默认 1.0，语义范围 0–2，读入时 clamp）：步枪枪械抖动、手枪枪械抖动、步枪相机抖动、手枪相机抖动。接入 `load_settings()` / `save_settings()` / `write_param()`（即改即存），**不进** `preset_store` 的 19 项训练参数清单——预设只快照训练参数，后坐力是个人手感偏好。
- 验收：改滑条立即生效并写盘；重开游戏数值保留；预设的保存/切换/对比不包含这 4 键。

### 3. 设置页「后坐力」分组

`settings_panel.gd` 新增「后坐力」分组，4 条平铺滑条（标签：步枪枪械抖动 / 手枪枪械抖动 / 步枪相机抖动 / 手枪相机抖动），倍率量纲 0–2 步进 0.01、默认 1.0、显示两位小数，复用 `_bound_slider` + `_value_box` 现成工厂，深色高对比主题一致。
- 验收：滑条拖动即改即存，数显可输入，主题与现有分组无差。

### 4. 倍率注入

- **枪械通道**：`viewmodel.kick(strong)` 注入 `_kick_pos` / `_kick_pitch` 时乘对应武器的「枪械抖动」倍率；
- **相机通道**：`player._add_recoil()` 注入 `_recoil_pitch` / `_recoil_yaw` 时乘对应武器的「相机抖动」倍率；
- 倍率每次开火实时读 `GameSettings`（改滑条对下一发立即生效）。

`aim_direction` 只读逻辑 yaw/pitch 零改动；`movement.gd` 不碰；无 ADR（视觉参数调优，非移动参数偏离）。
- 验收：GUT 全量回归全绿；主场景冒烟无报错；用户试玩定稿。

## 备注

- grilling 定稿（2026-10-02）：Q1 手枪 damp 恒 1 / 步枪前后满幅保留；Q2 相机踢两枪开镜均保留；Q3 四条滑条枪械独立；Q4 倍率 0–2 默认 1.0 两位小数、细项（回中速率/yaw 幅度）不暴露；Q5 进 settings.cfg 持久化、不进预设；Q6 新分组；Q7 平铺 4 条；Q8 立票后实现。
- 全票表现层 + 设置面；无新纯逻辑缝（`GameSettings` 字段读写是否有既有测试覆盖，照现状处理），跑全量回归。
- 数值定稿沿用票 05/06/07 流程：实现 → 试玩 → 用户点头 → 清理 → 提交。

## Comments / 2026-10-02 — 实现收尾（agent）

**开镜行为按枪种**：`viewmodel.gd _apply_rig` 的 kick 衰减从「两枪统一 ×(1 − zoom_p)」拆为按武器——步枪 `pitch_damp = 1 − _zoom`（上抬角收敛到零、红点不出轴心），手枪恒 1（完全不收敛）；前后位移 `kick_pos` 两枪都满幅保留，满开镜步枪呈纯前后震。相机踢零改动（`player.gd` 开镜逻辑未动）。

**倍率注入**：`viewmodel.kick` 注入 `_kick_pos`/`_kick_pitch` 时乘 `GameSettings.recoil_gun_mult_for(_weapon)`；`player._add_recoil` 注入 `_recoil_pitch`/`_recoil_yaw` 时乘 `GameSettings.recoil_cam_mult_for(weapon)`——每次开火实时读设置，改滑条对下一发立即生效。`aim_direction` 零改动，弹道不动。

**设置面**：`game_settings.gd` 新增 4 键 `recoil_gun_rifle` / `recoil_gun_pistol` / `recoil_cam_rifle` / `recoil_cam_pistol`（默认 1.0）与边界常量 `RECOIL_MULT_MIN/MAX`（0–2），`load_settings`/`save_settings` 走 `settings.cfg` 新 `recoil` 段（读入 clamp），不进 `PresetStore.FIELDS`（预设只快照训练参数）。`settings_panel.gd` 新增「后坐力」分页（画面与输入与计时器之间），4 条平铺滑条复用 `_bound_slider`（步进 0.01、两位小数数值框）+ 说明 hint。

**验收**：GUT 全量回归 145 tests / 1148 asserts 全绿；主场景冒烟无报错；用户试玩通过（「ok」）。
