# 02 bot 后退推力随离墙余量衰减

Status: ready-for-human

## 目标（TDD，纯逻辑缝）

`bot_ai.gd` 的**后退**分量（前后分量中远离玩家的那一半）乘一个衰减系数：余量 = 沿后退方向到半径 1000 圆的解析距离 − `Perception.body_radius`；`taper = clamp(余量 / WALL_MARGIN, 0, 1)`；`WALL_MARGIN` 为独立常量、初值 60。**只在负向（后退）输出上生效**，前进方向不动。

## 要点

- 把现有的 `_hits_boundary`（bot_ai.gd L344-346，返回 bool）重构成返回**解析距离** `t` 的辅助函数（无命中返回 `INF`）：前向探测的「探到边界」判据 = `t <= 探测长度`；衰减 = 上面那条式子。一处数学两处用，别写两份。
- 后退方向 = 现有前后分量输出的负向对应的世界方向（与 `_range_input` / `_wander_input` 输出的负半轴一致）。
- 覆盖两种「移动模式」：`保持距离` 与 `动态游走`（后者的走廊硬约束满幅退开同样要过这条衰减）。
- `Perception.body_radius` 复用为实体半径（它就是 `apply_body_radius` 后胶囊的实际半径），不新增字段。

## 验收（GUT）

新增用例（放 `tests/unit/test_bot_ai.gd`）：
1. 近墙后退 → 前后分量趋零（把 bot 放到离场心 ≈ `ARENA_RADIUS − body_radius` 处、意图后退，跑若干帧断言位置不再外移 / 前后分量衰减到 0）。
2. 远离墙 → **与旧值逐发一致**（同一 RNG 种子、bot 在中场，断言数值与旧行为无差异——证明衰减在中场恒等 1）。
3. 动态游走走廊硬约束在墙边不再满幅（`p.wander_mode = true` + 超大 `range_amp`/超远距离 + bot 贴墙）。
4. RNG 消耗顺序不变（衰减是纯函数、不掷骰）。

跑完核对 Scripts/Tests 数；新增 `class_name` 前先 `--headless --path . --import`。

## Comments

2026-10-15（实现，TDD 先红后绿）：`_hits_boundary`（bool）重构为 `_boundary_distance`（返回解析距离，无交 `INF`、已在圆外 0），前向探测的判据变成 `t <= 探测长度`；新增 `WALL_MARGIN = 60.0` 与 `_retreat_taper(pos, fwd, body_radius)`，注入点在 `update()` 常规路径（`if air: fwd = 0.0` 之后、前向探测之前）——两种移动模式的输出都汇到这个前后分量，故一处注入全覆盖。滑铲两条提前返回路径不经过它（滑铲本就零输入）。

新增 6 个用例（恒等 / 按比例 / 归零且不绞住 / 前进意图不受影响 / 走廊硬约束同样被衰减 / RNG 消耗顺序不变）。探针设计要求玩家放在远处、锁死 `fore_mix = FORE_BACK` 与侧向、且朝向不随位移旋转——否则「转向衰减」与「距离保持」会把读数搅乱。全量 GUT：15 scripts / 227 tests / 1418 asserts 全绿（此前基线 219/1400）。
