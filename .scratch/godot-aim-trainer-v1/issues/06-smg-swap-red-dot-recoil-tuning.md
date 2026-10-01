# 06 — 连发枪换冲锋枪 + 红点镜 + 后坐力分档调幅

Status: done

术语以 `CONTEXT.md` 为准（「视觉后坐力」词条为本票新增）。依赖票 01–05（全部已 done）。

## 目标

三个诉求，全部是**表现层**，不动伤害、命中判定、移动数值与弹道：

1. 连发枪目前用狙造型（blaster-e），换冲锋枪/步枪模型；
2. 两把枪上 1 倍点镜（红点镜），开镜不挡视野；
3. 视觉后坐力按武器分档调幅：连发太大调小，单发放大且回中变慢（枪体抖动手枪不动）。

## 清单与验收

### 1. 视觉后坐力分档调幅

`player.gd` 与 `viewmodel.gd` 常数直改（不加设置项）：

| 参数 | 步枪（连发） | 手枪（单发） |
|---|---|---|
| 相机踢 pitch（RECOIL_PITCH_*） | 0.03 → 0.018 | 0.02 → 0.028 |
| 相机回中（RECOIL_RECOVER） | 10 保持 | **拆档** 10 → 5 |
| yaw 抖动（RECOIL_YAW_JITTER） | ±0.008 → ±0.005（**拆档**） | ±0.012 |
| 枪体后坐/上抬（KICK_*） | 1.8/0.1 → 1.1/0.06 | **不动**（维持现值 1.08/0.06） |
| 枪体回位（KICK_RECOVER） | 14 共用保持 | 不动 |

实现提示：yaw 抖动与相机回中从共用常数拆成 `*_RIFLE` / `*_PISTOL` 两份；枪体侧手枪维持现值，拆常数或保持 ratio 皆可（以注释清晰为准）。
- 验收：弹着点分布与改前逐帧一致（后坐力纯渲染，`aim_direction` 不读这些值）；GUT 全绿；试玩一轮后用户可再微调数值。

### 2. 连发枪换冲锋枪模型

下载完整 Kenney blaster-kit（CC0，与现有资产同源）到 `assets/third_party/kenney_blaster-kit/`，从中挑一把**冲锋枪（SMG）造型**替换连发枪；`viewmodel.gd` 的 `RIFLE_MODEL` 与 `target.gd` 的 `WEAPON_MODEL` 同步换（玩家 POV 与 bot 手上的枪一致）。手枪 blaster-k 不动。
- 旧枪自带的狙镜 mesh（blaster-e 的 `scope`）随旧枪退役；新枪模若自带大狙镜同样隐藏。
- `target.gd` 里 `find_child("scope")` 等对新模型的依赖点逐一核对。
- 验收：腰射/开镜/bot 手上三处枪模一致且无狙镜；拟合（长度归一、顶面压 y=0）自动生效。

### 3. 两把枪上 1x 红点镜

优先用 kit 里的 1x 瞄具模型；kit 没有合适的就程序化（圆环 + 发光红点，`_build_procedural` 的镜框几何是雏形）。两把枪同款，挂在枪顶，开镜时红点落准星轴（现有 `_sight_y` 拟合机制支持）。开镜 FOV 76.64 保留不动。
- 验收：开镜时视野圈无大遮挡、红点对准准星；截图（腰射 + 开镜 POV）给用户过目。

### 4. 回归与定稿

- GUT 全量（145 tests）+ 主场景带渲染启动无 ERROR/WARNING。
- 截图：腰射、开镜 POV（红点对位）、bot 持新枪——用户过目定稿后清理临时截图脚本。

## 备注

- 全票表现层；`aim_direction` 与命中判定零改动。
- Kenney 资产选型已在 ADR-0007，本票换枪在其修正章节带一笔即可，不另立 ADR。
- 数值定稿沿用票 05 流程：截图/试玩 → 用户点头 → 清理 → 提交。

## Comments

### 2026-10-02 — 实现收尾（agent）

**后坐力分档**：`player.gd` 相机踢/回中/yaw 抖动拆 `*_RIFLE` / `*_PISTOL` 两份（0.018 / 0.028、10 / 5、±0.005 / ±0.012）；`viewmodel.gd` 枪体拆档，步枪 1.1 / 0.06，手枪维持 1.08 / 0.06，回位 14 共用。弹道零改动（`aim_direction` 只读逻辑 yaw/pitch）。

**换枪**：下载完整 Kenney blaster-kit，选 blaster-d（突击步枪造型）；`RIFLE_MODEL` / `WEAPON_MODEL` 同步换。实测发现**两把枪（blaster-d/k）GLB 导入后 +Z 端是枪口**，与旧注释「−Z 是枪口」相反——两端端面渲染实锤后，POV 侧 `_fit_model` 与 bot 侧 `_attach_weapon`（包 holder 翻 180°）统一修正，`WEAPON_ROT` 手骨标定原样复用。旧枪 blaster-e.glb 已被替换不再引用。

**红点镜**：kit 无独立瞄具模型，程序化实现（`_add_red_dot`）。初版圆环式被用户否决（挡视野），按用户提供的 Apex 1x 点镜截图改成**开框式**：两侧细柱（深色柱身 + 顶端发光红段）+ 悬浮发光红点，中间零遮挡；红点从半径 0.014×长 缩到 0.006×长。镜轴高度按枪记录（`_sight_heights` 字典，修复了后建的手枪覆盖步枪镜高导致开镜偏上 ~3.5° 的 bug），满开镜红点正落准星轴。

**黑枪修复**：blaster-d 自带金属材质在武器 SubViewport（无天空/反射探针）整枪黑——`_set_weapon_layers` 把材质压成全 diffuse（metallic=0, specular=0.3）。

**验收**：三张截图（腰射 / 开镜 / bot 持枪）用户定稿通过；GUT 145 tests / 1148 asserts 全绿；带渲染启动无 ERROR。临时文件（capture.gd、check_orient.gd、preview_kit.gd、kit-preview-src/、blasterKit/、kit-preview/、shots/、project.godot.bak）已清理。
