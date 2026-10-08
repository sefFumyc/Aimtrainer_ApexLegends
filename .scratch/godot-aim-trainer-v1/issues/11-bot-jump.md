# 11 — bot 跳跃：独立随机计时的对枪跳跃

Status: done

术语以 `CONTEXT.md` 为准（「bot 跳跃」为本票新增，已落稿）。设计偏离见 ADR-0023（独立计时器、不绑变向/受击）。依赖票 01–09（全部已 done）。

## 目标

bot 平地对枪时时不时跳起来，给玩家加垂直维度的 tracking 目标。触发**不绑变向、不绑受击**——独立随机计时器驱动（实战观察：真人按住一个方向键的中途也会跳）。

## grilling 定稿（2026-10-09）

- **触发源**：独立间隔计时器，每轮在 `[min, max]` 秒窗口内随机等待，到点起跳并重抽下一轮；绑变向/受击被否决（跳跃会几乎只在转向瞬间出现 / 频率被命中率绑架）；
- **门控三件套**：仅地面（空中发 jump 会锁存到落地违跳）、非「bot 滑铲」（滑铲中的跳归铲跳管）、「视线判定」通畅（视线被挡时跳浪费频率配额）；到点不满足即本轮**作废重抽**，不排队等待；「刷新」时重抽首跳间隔；
- **空中零特判**：开火照常（命中骰照掷不衰减）、躲避翻向照常（空中 6 rad/s 慢转向即真实感）、落地无特殊处理、表现复用 `jump_height()` 抬升路径（铲跳已建）；
- **不与「bot 开镜」互锁**（bot 开镜无视觉表现，空中开镜不矛盾；滑铲互锁是躺姿穿帮问题）；
- **跳跃骰用独立 RNG**（种子派生同 `avoid_rng` 模式），不污染开火/滑铲随机序列；
- **频率**：间隔双滑条 0.5–15s、步进 0.1、默认 4–12s；**下限 0.5 是故意的**——压进滞空（约 0.72s）以下即得落地即跳的连跳 bot；
- **预设 23 → 26 项**（`bot_jump_enabled` / `bot_jump_min` / `bot_jump_max`）。

## 清单与验收

### 1. BotAi 跳跃计时器（ADR-0023）

`bot_ai.gd` 新增独立跳跃 RNG（种子派生）+ 间隔计时器（spawn 重抽）；`update` 常规路径到点判定门控三件套，满足则本帧 `ctl.jump = true`（`MovementSimulator` 普通 jump 分支接管），不满足作废重抽；滑铲分支/死亡/重置同步清态。
- 验收：概率窗口到点在地面且视线通畅才跳；空中/滑铲/视线被挡到点作废重抽；跳跃不改变开火骰序列（固定种子对照）；jump 信号仅一帧。

### 2. 设置与预设

`game_settings.gd` 新增 3 键（`bot_jump_enabled` 默认 true / `bot_jump_min` 4.0 / `bot_jump_max` 12.0），settings.cfg `bot` 段即改即存；`preset_store.gd` FIELDS/DEFAULTS 扩到 26 项。
- 验收：老预设加载不丢、缺项补默认；重开游戏数值保留。

### 3. 场景装配

`main.gd` 感知装配 `jump_enabled` / `jump_min` / `jump_max` 三字段（Perception 扩容）。
- 验收：设置面板改动即改即生效（下一帧感知刷新）。

### 4. 设置页 UI

设置面板新增「bot 跳跃」分组（与「bot 滑铲」并列）：勾选框 + 两条时间滑条（0.5–15s、步进 0.1、两位小数数显）；关闭时滑条置灰。
- 验收：置灰行为与滑铲组一致；主题无差。

### 5. 测试

`test_bot_ai.gd` 补跳跃决策用例（门控组合 / 作废重抽 / RNG 隔离 / 单帧信号）；`test_movement.gd` 如需补普通跳复用用例；全量回归。
- 验收：GUT 全绿。

### 6. 收尾

导出 `build/aim-trainer.exe`；code-review；提交 master。

## Comments / 2026-10-09 — 实现收尾（agent）

**跳跃决策**（`bot_ai.gd`）：新增「bot 跳跃」段——`_tick_jump(dt, p)` 推进计时器并返回本帧是否发跳跃信号（挂到常规路径 `ctl.jump`）；`_roll_jump_wait(p)` 在窗口内抽下一轮间隔（min>max 归一）。跳跃骰独立 RNG（seed ^ 0x1B8C9A5F，学 `avoid_rng` 派生模式）。到点重抽先于门控判定（跳/废都从当帧起算下一轮）；门控三件套 = 非滑铲（`_sliding` 或 state=="sliding"）、仅地面（新 `MovementSimulator.airborne()` 读数，替代字符串比对）、视线通畅。到点判定挂在滑铲分支**之前**：滑铲中到点作废重抽；跳跃门控要求视线通畅、攻击滑铲要求被挡，两者天然互斥不同帧。开关关闭计时器冻结；`spawn()` 与致死分支均置 `_jump_wait = -1.0`（首帧落窗重抽首跳间隔）。

**设置与预设**：`game_settings.gd` 3 键进 `settings.cfg` `bot` 段（间隔 clamp 0.5–15）+ `JUMP_INTERVAL_MIN/MAX` 常量；`preset_store.gd` FIELDS/DEFAULTS 扩到 26 项，注释同步。

**场景装配**：`main.gd` 感知装配 `jump_enabled/jump_min/jump_max` 三字段。表现零改动——普通跳走 `jump_height()` 既有抬升路径（视觉模型/命中体/枪口一起升空，影子留地）。

**UI**：`settings_panel.gd`「躲避与移动」页滑铲组之后新增「bot 跳跃」分组：开关 + 跳跃间隔下限/上限双滑条（0.5–15、步进 0.1、两位小数数值框）；关闭时两条滑条与数值框一并置灰（`_sync_jump_grey`，签名收 bool——票 09 同款教训）；`_sync_controls` 切预设后同步置灰态。

**测试**（TDD 红→绿）：`test_bot_ai.gd` 新增 6 条——开关开着跳且能落地（连跳节奏采样修 assert）、开关关不跳、到点作废不排队（固定 1s 间隔 + 1.2s 恢复视野）、滑铲中不起跳（`_begin_slide` 注入，ADR-0017 豁免同款）、跳跃骰不扰动开火序列（同种子双 bot 逐发比对）、滞空不重跳（固定 0.05s 间隔，上升沿间隔 >0.6s）。

**验收**：GUT 全量回归 176 tests / 1252 asserts 全绿（本票 bot_ai +6）。导出 `build/aim-trainer.exe`。code-review 双轴：Standards 无硬违规；Spec 两处收口（致死分支清 `_jump_wait`、补滞空不重跳直接断言）均已落实，两条自定防御行为补进 ADR-0023 留痕。
