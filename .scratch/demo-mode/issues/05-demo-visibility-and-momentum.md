# 05 — 「可见性」门控 + 拉枪惯性滑行（ADR-0034）

Status: ready-for-agent

Blocked by: 01, 04

## 目标

演示模式下当 bot 被人看不见时（被「遮挡物」/「围墙」挡住），不锁定、不按住开火；正在进行的拉枪带惯性滑行收住（不是一帧急停），bot 重新可见后立即恢复拉枪、瞄到位再开火。bot 死亡空窗仍是冻结保持（不滑行）。

## 内容

- `demo_aim.gd`：由无状态静态函数改为**有状态实例类**——
  - 新增三态 `Mode { TRACK, COAST, HOLD }`，暴露 `mode()` 供探针读取。
  - `update(...)` 加 `visible` 形参：看得见（或仍在宽限内）→ 拉枪追踪并刷新末帧角速度 `_vel`；连续看不见满 `LOST_GRACE` → 继承 `_vel` 按 `COAST_DECAY` 指数衰减滑行；`has_target = false` → `HOLD` 冻结保持（不滑行）。
  - `on_target(...)` 加 `visible` 形参：`has_target ∧ visible ∧ 到位` 才可开火。
  - 参数硬编码：`COAST_DECAY = 10.0`（不复用 `EASE_RATE`，后者约 25ms 太快、看不出余势）、`LOST_GRACE = 0.1`。
- `player.gd`：
  - 持有 `_demo_aim := DemoAim.new()` 实例与 `_demo_visible` 状态；`set_demo_target(point, has_target, visible)` 加第三个形参。
  - `_tick_demo_aim` 改用实例 `update(...)`，pitch 仍按 `PITCH_LIMIT` 钳制。
  - `_tick_weapon` 的演示开火门控改用 `DemoAim.on_target(..., _demo_visible)`。
- `main.gd`：
  - 新增 `_player_sees_target()`：`player.eye_position() → target.aim_point_world()`，mask `WORLD_LAYER | BOT_LAYER`，exclude player rid，`hit.is_empty() or hit["collider"] == target.hit_body()`。
  - 喂目标点时传入第三参数 `_player_sees_target()`。
- `tests/unit/test_demo_aim.gd`：新增覆盖三态 / 宽限 / 滑行指数衰减与方向 / 重新可见即时恢复的用例；死亡空窗断言改为 `HOLD`。

## 验收

见 `spec.md`「验收标准」第 11–15 条。

## 验证

实机逐条验收（站到「遮挡物」后确认不开火、准星惯性滑停、绕出后恢复拉枪）+ `godot --headless -s addons/gut/gut_cmdln.gd` 全绿（脚本数 / 用例数与新增一致）。
