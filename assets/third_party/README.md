# 第三方美术资源（assets/third_party）

本目录存放本项目使用的第三方美术资源。依据 ADR-0007：

- 只收录 **CC0（零署名、零商用限制）** 资源；
- **只提交项目实际用到的文件**，其余格式版本一律不入库；
- **不使用 Git LFS**，因此严格控制入库体积。

获取日期：**2026-09-30**（blaster-d 于 2026-10-02 补充、blaster-g 于 2026-10-09 补充，见下）。
本目录当前入库文件共 9 个，合计约 **3.59 MiB**（3,820,160 字节），远低于 20 MiB 上限。

---

## 1. Kenney Blaster Kit（2.1）

- **包名**：Blaster Kit 2.1
- **作者**：Kenney（https://www.kenney.nl）
- **来源 URL**：https://kenney.nl/assets/blaster-kit
- **下载直链**：https://kenney.nl/media/pages/assets/blaster-kit/261d80a716-1753959510/kenney_blaster-kit_2.1.zip
- **许可**：Creative Commons Zero（CC0 1.0 Universal）—— https://creativecommons.org/publicdomain/zero/1.0/
- **许可文件**：`kenney_blaster-kit/License.txt`
- **获取日期**：2026-09-30

### 实际入库文件

| 文件（相对本目录） | 字节数 | 用途 |
| --- | --- | --- |
| `kenney_blaster-kit/rifle/blaster-d.glb` | 36,452 | 步枪模型（票 06 换入，2026-10-02 从同一 2.1 完整包补充） |
| `kenney_blaster-kit/rifle/Textures/colormap.png` | 10,223 | 步枪模型引用的贴图（blaster-d 与原 blaster-e 同用一份） |
| `kenney_blaster-kit/pistol/blaster-k.glb` | 35,676 | 手枪模型 |
| `kenney_blaster-kit/pistol/Textures/colormap.png` | 10,223 | 手枪模型引用的贴图 |
| `kenney_blaster-kit/smg/blaster-g.glb` | 56,240 | 冲锋枪模型（ADR-0026 换入，2026-10-09 从同一 2.1 完整包补充） |
| `kenney_blaster-kit/smg/Textures/colormap.png` | 10,223 | 冲锋枪模型引用的贴图 |
| `kenney_blaster-kit/License.txt` | 700 | 资源包许可 |

### 其余文件未入库说明

原包共 40 个模型，另有 FBX、OBJ 两种格式版本以及全部 Preview 预览图，均**未入库**：

- 每个模型只保留 **.glb** 一种格式（原包同时提供 .glb / .fbx / .obj，已全部丢弃）；
- 40 个模型中只保留本次用到的 3 个（步枪、手枪、冲锋枪各一）；其余 `blaster-a`~`blaster-r` 中的 15 个、以及 bullet / clip / crate / grenade / scope / silencer / smoke / target 等配件模型全部丢弃；
- 原包根目录的 `Overview.html`、`Preview.png`、`Preview (Variation A).png`、`Previews/` 全部 Preview 图、`View Documentation.url`、`Visit Kenney.url`、`Visit Patreon.url` 均丢弃；
- 原包 `Models/Textures/variation-a.png`（备用配色贴图）未入库，只保留模型实际引用的 `colormap.png`。

### 挑选与降级说明

- 该资源包的模型文件名全部是 `blaster-a` ~ `blaster-r`，**没有** rifle / pistol 之类的语义命名。因此按“模型包围盒最长边”排序并结合官方渲染预览图判断：初版取最长的 `blaster-e`（长边约 1.39 单位，带枪托与瞄具）作为**步枪**；票 06 换成同包的 `blaster-d`（突击步枪造型，长边约 0.86 单位），`blaster-e` 随之移出仓库。手枪维持短小一档的 `blaster-k`（长边约 0.46 单位）。
- 冲锋枪（ADR-0026，2026-10-09）：目标是 P90 风格（短粗 bullpup、顶部弹匣），逐张对照官方预览图后选 `blaster-g`（长边约 0.79 单位）——紧凑机匣 + 后伸枪托管，是包内 SMG 感最强的候选；严格 P90 造型无现成模型，按 ADR-0026「找不到就选 SMG 感最强的替代」执行。**注意**：官方预览图是等距视角、朝向约定不可靠——`blaster-g` 实际结构为黄色机匣（前端带粗枪管口）+ 灰色后伸托管（端面开口槽），已用 Muzzle 标记挂亮球的渲染探针实锤枪口端，与 Kenney「+Z 是枪口」的 GLB 约定一致。
- 模型的 .glb 通过外部相对路径 `Textures/colormap.png` 引用贴图，为保持该相对路径在 Godot 中可直接解析，**每个模型目录下各保留一份相同的 `colormap.png`**（10,223 字节，重复两份，属于必要冗余）。

---

## 2. KayKit Adventurers（Character Pack: Adventurers 1.0）

- **包名**：KayKit - Character Pack: Adventurers 1.0
- **作者**：Kay Lousberg（https://www.kaylousberg.com）
- **来源 URL（官方 itch.io 页面）**：https://kaylousberg.itch.io/kaykit-adventurers
- **实际获取地址**：https://github.com/KayKit-Game-Assets/KayKit-Character-Pack-Adventures-1.0 （官方 GitHub 镜像仓库，内容与 itch.io 免费版一致）
- **许可**：Creative Commons Zero（CC0 1.0 Universal）—— https://creativecommons.org/publicdomain/zero/1.0/
- **许可文件**：`kaykit-adventurers/License.txt`（取自包内 `addons/kaykit_character_pack_adventures/LICENSE.txt`）
- **获取日期**：2026-09-30

### 实际入库文件

| 文件（相对本目录） | 字节数 | 用途 |
| --- | --- | --- |
| `kaykit-adventurers/character/Knight.glb` | 3,659,532 | 绑骨 + 76 段动画的角色模型（含内嵌贴图） |
| `kaykit-adventurers/License.txt` | 891 | 资源包许可 |

### 其余文件未入库说明

- 原包提供 **.FBX / .GLTF（含 .bin 与外部贴图）** 等多种格式版本，一律丢弃，只保留 **.glb**；
- 原包另有 Barbarian / Mage / Rogue / Rogue_Hooded 四个角色，只保留 **Knight** 一个；
- 25+ 武器配件（sword / shield / axe / crossbow / staff / wand / arrow / mug / quiver / spellbook / smokebomb 等）全部丢弃；
- GitHub 镜像仓库中的 Godot 插件部分（`addons/kaykit_character_pack_adventures/` 的脚本、`.tres` 资源配置等）未入库。

### 降级说明

itch.io 的免费下载需要浏览器 JS 交互（页面为动态渲染，无法直接取得静态下载直链），因此**改用作者官方的 GitHub 镜像仓库**获取同一 CC0 资源包（版本 1.0，与免费版内容一致）。资源本身内容、许可证均无变化；此处仅记录来源差异，无资源缺失。

---

## 汇总

| 资源包 | 入库文件数 | 入库体积 |
| --- | --- | --- |
| Kenney Blaster Kit 2.1 | 7 | 159,737 字节 |
| KayKit Adventurers 1.0 | 2 | 3,660,423 字节 |
| **合计** | **9** | **3,820,160 字节（约 3.64 MiB）** |
