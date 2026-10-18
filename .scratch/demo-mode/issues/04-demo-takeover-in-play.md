# 04 — 视角与开火接管、目标点喂给、玩家血量封底

Status: ready-for-agent

Blocked by: 01, 02, 03

## 目标

在演示模式开启时，让脚本接管玩家的**视角**与**开火**，其余输入照旧。

## 内容

- `player.gd`：
  - 视角接管：演示开启时跳过鼠标 / 右摇杆的视角输入，改为每帧用 `DemoAim.step(eye, target_point, yaw, pitch, dt)` 得到的新朝向写入 `yaw/pitch`（顺序需在既有「写相机旋转」之前，参照 `_tick_look` 在 `_physics_process` 中的位置）。
  - 开火接管：演示开启时忽略开火键输入，改为 `DemoAim.on_target(...)` 为真时击发（非全自动武器取「由未到位变为到位」的上升沿击发一次；全自动按既有 `advance(delta, held)` 语义持续按压）。**定稿替代**：到位判定改取「电平」而非「上升沿」——理由见 `docs/adr/0033-demo-mode-locked-aim.md`「开火」段（上升沿会让手枪一次对局只响一发）。
  - 开镜 / 移动 / 跳跃 / 蹲滑铲 / 换枪**不受影响**。
- `main.gd`：
  - 每帧（在 bot 推进之后、玩家 tick 之前）把 `target.aim_point_world()` 喂给 player；bot 死亡空窗期改喂「无目标」哨兵，使相机冻结保持、且不开火。
  - 玩家受伤路径（既有 `_resolve_bot_shot`）：演示开启时把血量钳在**最低 1**、跳过「玩家重生」；受击红屏等既有反馈照常。
- 命中与射击照常计入既有统计（不改 `_on_shot_fired`）。

## 验收

见 `spec.md`「验收标准」第 1、3、4、5、6、7、8 条。

## 验证

实机逐条验收 + `godot --headless -s addons/gut/gut_cmdln.gd` 全绿。
