# Aim Trainer（Apex Legends）

FPS 瞄准练习游戏：玩家与一个会走位、会滑铲、会跳的移动bot对枪。

Godot 4.7.2 + 纯 GDScript 实现，按 Apex（Source 单位体系）所有速度、距离、加速度都是由采样的速度计算的，但并非百分百还原，目前依旧存在一些复杂情况的bug，在跳跃里比较明显。

## 特性

- **更像人类的行为**：bot 与玩家共用同一套移动模型，并配备了比较复杂的行为控制，你可以组合出各种各样的玩家，乃至身法哥。
- **三把武器**：对应FPS游戏中常见的三种枪械：全自动、单发、连发枪（5 发一组），对局中随时切换。
- **间隔计时器（核心）**：游玩、休息的循环，并且会根据你的准确率表现（大于或小于68.3）来调整bot的宽度，让你更容易从中学习到动作的规律。

### 靶子（bot）

- **躲避控制**：长 / 中 / 快横移三档按权重定期切换，变向间隔随机重抽；被命中按概率立刻翻向，受「最短躲避时间」约束。
- **移动模式**：保持距离 / 动态游走（走廊 + 前后分量），后退推力随离墙余量成比例衰减。
- **bot 开火**：每发按「命中率」掷骰，开火前先做「视线判定」（被遮挡物挡住则本发不开枪）；瞄准视锥连续 350ms 触发，或受击立即反击（说人话就是你没瞄着bot，它不会打你，瞄上了或者开火打到它了，就会还手）。
- **bot 滑铲 / 铲跳 / 随机跳跃**：攻击滑铲（视线被挡触发）与重生滑铲（沿出生连线垂直方向）；铲跳继承滑铲方向；跳跃由独立计时器驱动。

### 表现与界面
- **视频设置**：F11 切换独占全屏;允许切换16:9和16:10。
- **预设**：27 项训练参数的命名快照，即改即存（这么多设置，总不能每次练别的都改一遍吧）。
- **视觉后坐力**：按武器分档的枪体后坐 + 相机踢动，只作用于渲染，弹道零影响。
- **演示模式**：F2 Aimbot演示；

## 运行

需要 **Godot 4.7.2-stable**（纯 GDScript，不引入 .NET）。用编辑器打开 `project.godot`，直接运行主场景 `src/scenes/main.tscn` 即可。

导出 Windows 可执行：先建好 `build/` 目录，再执行

```
godot --export-release "Windows Desktop"
```

（导出模板需装在 `%APPDATA%\Godot\export_templates\4.7.2.stable\`；产物 `build/aim-trainer.exe` 不提交入库。）

所有设置持久化在 `user://settings.cfg`，重启不丢。

## 目录结构

```
src/scenes/    场景与节点脚本（.tscn + 挂载脚本）
src/logic/     纯逻辑类（不依赖节点树，GUT 测试缝）
src/autoload/  全局设置单例 GameSettings
tests/unit/    GUT 行为测试
assets/        音频与第三方美术资源
tools/         gen_audio.gd（音效生成）
docs/adr/      架构决策记录（ADR）
CONTEXT.md     领域词汇表
AGENTS.md      仓库约定与 agent 工作流
```

## 文档

- [CONTEXT.md](CONTEXT.md) — **领域词汇表**，本项目的唯一命名来源，动代码前先读。
- [docs/adr/](docs/adr/) — 架构决策记录，从 0001 重新编号；实现取舍与「为什么这么定」都在这里。
- [AGENTS.md](AGENTS.md) — 仓库约定（语言、引擎、结构、测试）与 agent 工作流。
- `.scratch/` — 本地 issue 与 spec（见 `docs/agents/issue-tracker.md`）。
- [assets/third_party/README.md](assets/third_party/README.md) — 第三方资源来源、许可与实际入库清单。

## 第三方资源与许可

- **Kenney Blaster Kit 2.1**（CC0 1.0）— 步枪 / 手枪 / 冲锋枪模型。
- **KayKit Character Pack: Adventurers 1.0**（CC0 1.0）— Knight 角色模型（绑骨 + 多段动画）。

均为 CC0，可商用、免署名；来源、许可文件与入库体积见 [assets/third_party/README.md](assets/third_party/README.md)。仓库当前未附带整体开源许可文件。

## 技术栈

Godot 4.7.2-stable · 纯 GDScript（无 .NET）· Forward+ · 三层分离（场景 / 纯逻辑类 / Autoload 设置单例）· GUT
