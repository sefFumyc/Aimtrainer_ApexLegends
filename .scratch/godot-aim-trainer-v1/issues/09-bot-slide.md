# 09 — bot 滑铲：攻击滑铲 + 重生滑铲 + 铲跳

Status: done

术语以 `CONTEXT.md` 为准（「bot 滑铲」「攻击滑铲」「重生滑铲」「铲跳」为本票新增、「滑铲跳跃」限定为玩家动作、「bot 开镜」补互锁，均已落稿）。移动偏离见 ADR-0016（速度直接注入 + ADS 互锁）。依赖票 01–08（全部已 done）。

## 目标

给 bot 加三类滑铲动作，提升对枪真实感：

1. **重生滑铲**：bot「刷新」落地瞬间沿玩家连线**垂直**方向（玩家视角的左/右，各 50%）滑出；
2. **攻击滑铲**：bot「视线判定」被遮挡时（bot 透视），沿玩家连线 ±90° 内随机方向滑出抢位；
3. **铲跳**：滑铲中按概率在随机时刻跳起（不松蹲、继承滑铲方向），晃开玩家子弹。

## grilling 定稿（2026-10-03）

- 滑铲行为各做独立开关（攻击滑铲 / 重生滑铲各一个）；两个开关都没勾时铲跳不可勾、概率滑块隐藏；
- 重生滑铲方向左右各 50%；攻击滑铲方向玩家连线 ±90° 内随机、避障重试 3 次、全失败放弃；
- **直接注入满速**（399 u/s）：玩家看不见前摇——疾跑前摇半秒会被白打高额伤害，且疾跑要求前向输入没法朝向玩家压枪；
- 滑铲全程零输入直线滑行、朝向仍指向玩家（回头射击）、随机时刻站起恢复常规躲避；
- 铲跳继承滑铲方向、不松蹲，每次滑铲独立掷骰；
- 与「bot 开镜」互锁：一个开了另一个开不了（开镜封速 130 < 滑铲门槛 200）；
- 滑铲表现：KayKit 无滑铲/蹲伏动作（已核 GLB 动画名），命中体按蹲伏进度压低 30u；模型带 Crouch 动作时动画自动接管；
- 预设 19 → 23 项（滑铲 4 项进预设）。

## 清单与验收

### 1. MovementSimulator 注入 API（ADR-0016）

`start_slide(dir, speed)`：直接注入滑铲初速、置 `_slide_auto`（维持不依赖蹲键）；`end_slide()`：随机时刻站起；`crouch_progress()`：蹲伏进度读数（命中体压低共用）。reset 与铲跳分支同步清理标志；玩家滑铲行为零变化（`end_slide` 只对注入态生效）。
- 验收：注入当帧满速滑行、无蹲键维持 0.4s+、减速曲线与普通滑铲一致；既有滑铲测试全绿。

### 2. BotAi 滑铲决策

重生滑铲入口 `try_respawn_slide`（场景在 `spawn()` 后调用一次）；攻击滑铲在 `update` 里按「视线被挡 + 冷却过 + 开关开」触发；滑铲全程冻结躲避/探测但保留开火；铲跳按概率在随机时刻起跳；结束后 1s 冷却；死亡清态。
- 验收：垂直方向滑出且受阻换侧；视线通畅不触发；冷却挡住连环滑铲；概率 1 必跳、概率 0 不跳。

### 3. 设置与预设

`game_settings.gd` 新增 4 键（`bot_attack_slide_enabled` / `bot_respawn_slide_enabled` / `bot_slide_jump_enabled` / `bot_slide_jump_prob` 默认 0.3），settings.cfg `bot` 段即改即存；`preset_store.gd` FIELDS/DEFAULTS 扩到 23 项。
- 验收：老预设加载不丢、缺项补默认；重开游戏数值保留。

### 4. 场景装配与表现

`main.gd`：感知装配 3 个滑铲字段 + ADS 互锁保险 + 重生滑铲触发；`target.gd`：命中体按 `crouch_progress` 压低、Crouch 动作可选接管。
- 验收：所见即所中（滑铲中打得到压低后的命中体）。

### 5. 设置页 UI

「躲避与移动」页新增 4 控件；互锁置灰：两滑铲开关都没勾 → 铲跳置灰且概率行隐藏；任一勾上 → 「bot 常驻开镜」置灰并自动取消。
- 验收：互锁行为与 CONTEXT 词条一致；主题无差。

### 6. 测试

`test_movement.gd` 补注入滑铲 6 条；`test_bot_ai.gd` 补滑铲决策 9 条；全量回归。
- 验收：GUT 全绿。

## Comments / 2026-10-03 — 实现收尾（agent）

**注入 API**：`movement.gd` 新增 `start_slide(dir, speed)`（置 `_slide_auto`，维持不依赖蹲键）、`end_slide()`（只对注入态生效，玩家滑铲不受影响）、`crouch_progress()` 读数；`reset` / 普通滑铲跳 / 手动滑铲跳分支同步清理 `_slide_auto`。玩家侧触发链零改动。

**滑铲决策**：`bot_ai.gd` 新增滑铲段（常量：注入速度 399、滑行 0.35–0.9s、铲跳时刻 0.1–0.6s 且不晚于站起、避障重试 3 次、冷却 1s）。`update` 滑铲分支：零输入直线滑行、`avoidance`/探测/贴墙内拐全部冻结、开火照常（`_update_firing` 照常推进）；滑完/铲跳升空/站起统一走 `_end_slide_state` 进冷却。死亡 `take_damage` 同步清 `_sliding`/`_slide_jump`（`spawn` 亦兜底重置）。`probe_length_for` 提为 static 供场景复用同一口径。

**设置与预设**：`game_settings.gd` 4 键进 `settings.cfg` `bot` 段（概率读入 clamp 0–1）+ `bot_slide_any_enabled()` 互锁判定辅助；`preset_store.gd` FIELDS/DEFAULTS 扩到 23 项，注释同步。

**场景装配**：`main.gd` 感知装配 `slide_attack`/`slide_jump`/`slide_jump_prob`，ADS 互锁 = `p.ads = bot_ads_enabled and not bot_slide_any_enabled()`（感知层保险，UI 层另有置灰）；`_respawn_target` 在 `spawn()` 后按开关触发 `try_respawn_slide`。`target.gd`：命中体每帧按 `CROUCH_HEIGHT × crouch_progress` 下沉；`_setup_animation` 检测模型含 `Crouch` 才接管滑铲动画（Knight.glb 已核无此动作，当前走命中体下沉回落路径）。

**UI**：`settings_panel.gd`「躲避与移动」页新增攻击滑铲/重生滑铲/铲跳三开关 + 铲跳概率滑条；`_sync_slide_interlock` 统一互锁：两滑铲全关 → 铲跳置灰、概率行隐藏；任一开 → bot 开镜置灰并自动取消（`write_param` 落盘）。

**验收**：GUT 全量回归 160 tests / 1175 asserts 全绿（本票新增 15 条：movement 6 + bot_ai 9）。提交 `1bb7705`。
