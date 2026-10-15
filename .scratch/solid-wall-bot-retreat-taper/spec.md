# 围墙实体化 + bot 后退推力随离墙余量衰减

设计已定稿，决策与理由见 `docs/adr/0031-solid-wall-and-bot-retreat-boundary-taper.md`；词条口径见 `CONTEXT.md`（「实体围墙」「距离保持」「目标距离」，「贴墙内拐」已登记进已移除清单）。

## 背景（实测 bug）

「目标距离」设大（如 1600）而玩家居场心时，距离需求在几何上不可达（几何上限 = 1000）：bot 一路满幅按 S 退到边界；旧实现在 `r ≥ ARENA_RADIUS` 时把本帧输入整体替换为「朝圆心」（贴墙内拐），与后退 wish 差 180°——180° 的转向衰减保留率只有 5%——于是每帧「朝内一帧、朝外一帧」对打，速度被绞到近零 = 「卡在墙边走不动」。旧实现唯一的边界泄压阀（撞墙反向 / 前向探测）翻的都是侧向（`avoidance.dir`），**前后轴没有泄压阀**。

## 决策

1. 环形围墙从纯视觉改为**实体**：1 个 `StaticBody3D` + 96 个 `BoxShape3D`（段数与 `GROUND_SEGMENTS` 一致，内表面即视觉那个圆），世界层、与「遮挡物」同性质。径向钳制保留为兜底。
2. bot 的**后退**分量随「离墙余量」按比例衰减、余量耗尽即零；**只在后退方向生效**（前进方向朝玩家、连线天然不出凸圆，且已由前向探测管）。
   - 余量 = 沿后退方向到半径 1000 圆的解析距离 − `Perception.body_radius`（bot 移动胶囊被 `apply_body_radius` 连碰撞形状一起缩放，实际半径就是「体型半径」设置）。
   - 余量口径用独立常量（初值 60），不随「场地布局」变。
3. 「贴墙内拐」与 `_handle_walls` 整体退役（贴墙行为交给物理 + 仿真钳制）。
4. 保留项：「躲避」的贴墙守卫（门限从 `ARENA_RADIUS` 重定基到 `ARENA_RADIUS − body_radius`）；`_pushes_outward`（守卫在用）；「前向探测」的解析边界臂（`BotAi` 是纯逻辑、GUT 里没有物理墙，ADR-0009）。

## 事实锚点

- [src/scenes/arena.gd](../../src/scenes/arena.gd) L10-13 常量（`RADIUS` / `WALL_HEIGHT` / `GROUND_SEGMENTS`）；L64-81 `_build_wall()` 目前只建 `MeshInstance3D`（注释「围墙不挂碰撞」）；L108-124 `_build_static()` 的 `StaticBody3D` + `CollisionShape3D`、`collision_layer/mask = 1` 装配模板。
- [src/scenes/main.gd](../../src/scenes/main.gd) L32-36 层常量 `WORLD_LAYER=1 / BOT_LAYER=2 / PLAYER_LAYER=4`；L534-542 玩家开火射线（掩码 `WORLD_LAYER | BOT_LAYER`）；L651-660 bot 视线判定（掩码 `WORLD_LAYER | PLAYER_LAYER`）；未命中曳光长度常量约 L19。
- [src/logic/bot_ai.gd](../../src/logic/bot_ai.gd) L19-33 常量区；L207-240 `update()` 主循环（L210-215 贴墙内拐替换）；L291-313 `_range_input` / `_wander_input`（走廊硬约束满幅退开）；L323-346 前向探测 + `_hits_boundary` 解析边界判定；L348-369 `_handle_walls` / `_pushes_outward`；L543-557 `_try_dodge` 的贴墙守卫。
- [src/logic/movement.gd](../../src/logic/movement.gd) L47-48 `ARENA_RADIUS := 1000.0`；L238-251 径向钳制。
- [src/logic/avoidance.gd](../../src/logic/avoidance.gd) L103-109 `wall_flip()` 语义。
- [src/scenes/target.gd](../../src/scenes/target.gd) L234-236 `apply_body_radius`（缩放整个 Target 节点，含碰撞形状）；L268-277 前向探测射线（仅 `WORLD_LAYER`、排除自身）；L529-537 `_build_move_body`（`shape.radius = Physique.BODY_RADIUS`）；L29-33 注释已写「围墙」在世界层（加碰撞后自洽）。
- [src/scenes/player.gd](../../src/scenes/player.gd) L154-171 `move_and_slide` + `sync_position`；[player.tscn](../../src/scenes/player.tscn) 胶囊半径 8。
- `Perception.body_radius` 字段已存在（现供瞄准视锥用），复用为离墙余量的实体半径，不新增字段。
- [tests/unit/test_bot_ai.gd](../../tests/unit/test_bot_ai.gd) L28 `perception()` 设 `Physique.BODY_RADIUS_DEFAULT`；L99-153 现有距离保持/游走用例，bot 都在离场心 50–500 处（远离 `ARENA_RADIUS`，衰减系数恒 1，**断言不受影响**）；无任何用例覆盖贴墙内拐 / `_handle_walls`。

## 连带效应（已确认，不改代码）

- 墙吃子弹、未命中曳光落点变墙面命中点——掩体语义的正常代价。
- bot 视线判定不受影响（双方都在凸圆内，连接线不出圆）。
- `on_blocked`（实际位移 < 意图一半 → `wall_flip`，0.3s 提交窗）在边界上**今天就已触发**，换了个削减者而已，行为不变；它是墙边滑不动的兜底。
- 玩家胶囊恒 8 → 停在 992，相机不再贴到 1000 墙面上。

## 验收

- `bot` 侧（纯逻辑缝）：GUT 新增用例——近墙后退 → 前后分量趋零；远离墙 → 与旧值逐发一致；动态游走走廊硬约束在墙边同样被衰减；守卫门限重定基后墙边躲避仍被放弃。全量 `godot --headless -s addons/gut/gut_cmdln.gd` 绿，**核对 Scripts/Tests 数与预期一致**（新增 `class_name` 后先 `--headless --path . --import`）。
- 墙侧：实机（`arena.gd` 不在 GUT 缝上）——贴墙左右滑 + 往墙里顶，相机不再穿出、子弹被墙吃；导出 exe 交用户实机验收。
- 收口：`git restore project.godot`（导出会重写该文件）、`启动游戏.bat` 保持 GBK 不动、临时探针清理。
