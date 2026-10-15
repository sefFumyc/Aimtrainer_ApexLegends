# 03 退役「贴墙内拐」与 `_handle_walls` + 躲避守卫门限重定基

Status: ready-for-human
Blocked by: 01, 02

## 目标

- **删除** bot_ai.gd L210-215 的「贴墙内拐」输入替换分支，以及 L348-369 的 `_handle_walls`（贴墙行为改由实体墙 + 仿真径向钳制承担）。
- **保留** `_pushes_outward`（`_try_dodge` 的贴墙守卫在用）；L543-557 的守卫**保留但门限重定基**：从 `pos.length() >= ARENA_RADIUS - WALL_EPS` 改为 `ARENA_RADIUS − Perception.body_radius` 口径（墙实体化后 bot 最多到 `ARENA_RADIUS − body_radius`，旧门限永不触发 = 墙边躲避白掷并静默重置变向计时器）。
- **保留**「前向探测」的解析边界臂（纯逻辑类在 GUT 里没有物理墙）。
- 删除后清理成为死代码的常量 / 局部变量，不留 `// 已删` 式残留。

## 验收

- GUT：新增「墙边躲避仍被守卫放弃（不白掷、不重置变向计时器）」用例；现有 `test_avoidance.gd` 的 `wall_flip` 三例照旧绿（`wall_flip` 未动）。
- 全量 GUT 绿 + Scripts/Tests 数与预期一致。
- 实机：bot 贴墙时不再「一帧朝内一帧朝外」抖动；被墙顶住时 ≤0.3s 内翻侧向滑走。

## Comments

2026-10-15（实现，依赖 01、02 已完成）：删除 `update()` 的「贴墙内拐」输入替换分支与 `_handle_walls`、常量 `WALL_EPS`，以及滑铲两条提前返回路径上的 `_handle_walls()` 调用。保留 `_wall_flip` / `_strafe_dir_vec` / `_pushes_outward`（前向探测与守卫仍在用）。

守卫门限重定基为 `ARENA_RADIUS − body_radius − WALL_GUARD_SLOP`，新增 `WALL_GUARD_SLOP = 1.0`：物理求解余隙与几何离散让 bot 停在门限外零点几，不留容差守卫永不生效。`_pushes_outward` 另加**相对容差**（实测定稿：真·切向时点积只剩 ±1e-13 浮点残差、符号随朝向抖，原 `> 0.0` 会让守卫在正切位置随机生效）。

新增 2 个用例（贴墙翻向朝外 → 放弃且不重抽变向计时器；同位置切线方向 → 照旧翻）。注意：守卫依赖「朝向」，测试必须先跑一帧（`update(0.0, p)`，零时长、不产生位移）把朝向按玩家方向定下。实机侧的边界抖动验收仍待用户确认。
