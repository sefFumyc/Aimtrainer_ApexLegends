# 01 — 纯逻辑类 `DemoAim` + GUT 用例

Status: ready-for-agent

## 目标

把「限速平滑跟枪」与「是否瞄到位」的数学抽成不依赖节点树的纯逻辑类（ADR-0009 / ADR-0013），供场景层每帧调用。

## 接口（建议）

- `DemoAim.step(eye: Vector3, target: Vector3, yaw: float, pitch: float, dt: float) -> Vector2`：返回新的 `(yaw, pitch)`，以最大角速度 + 指数缓动向目标收敛；无目标（传入哨兵或 `target_none`）时原样返回当前朝向。
- `DemoAim.on_target(eye: Vector3, target: Vector3, yaw: float, pitch: float) -> bool`：视线方向与「eye→target」方向的夹角 ≤ 阈值（约 2°）。
- 常量：最大角速度、缓动速率、夹角阈值、锁定高度等硬编码在本类内，注释写明来源 ADR-0033。

## 验收

- 目标在正后方 180° 时按 `step` 连续推进若干帧，朝向单调逼近且单帧转角不超过最大角速度（无过冲、无震荡）。
- 已对齐目标时继续 `step` 不再产生可见抖动（收敛到死区）。
- 夹角略大于阈值时 `on_target` 为 false，略小于时为 true。
- 无目标时不改变传入朝向。

## 验证

新增测试文件后先跑
`godot --headless --path . --import`（新 `class_name` 必须先注册全局类缓存），
再跑 `godot --headless -s addons/gut/gut_cmdln.gd`，并核对脚本数 / 用例数比上轮恰好多出本次新增量。
