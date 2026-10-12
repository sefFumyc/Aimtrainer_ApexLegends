# 全屏宽高比：16:10 引擎内拉伸（content scale），CS/Apex stretched 语义

玩家要 CS/Apex 的 stretched resolution 观感：16:10 内容横向拉伸铺满 16:9 面板，东西看着「扁」。决策：设置面板「画面与输入」页新增「全屏宽高比」设置项（16:9 默认 / 16:10），**只作用于 F11 独占全屏**——16:9 档原生直渲（与旧行为完全一致）；16:10 档用引擎内 **Window content scale**（`CONTENT_SCALE_MODE_VIEWPORT` + `CONTENT_SCALE_ASPECT_IGNORE`，`content_scale_size` = 屏高为分母、16:10 算宽，如 2560×1440 屏 → 渲染 2304×1440）——3D 与 UI 按 16:10 渲染后横向拉满原生屏幕，竖直 FOV 恒定（`keep_height` 现状）、水平 FOV 收窄再被拉宽，正是 CS stretched 的语义（2026-10-12 拷问会话定稿 + 实测修正）。

## 实测修正：显示模式切换在 Godot 4.7 不存在（首轮路线 A 已否决）

初版走「路线 A：独占全屏 + `window.size` 设非原生分辨率、靠驱动拉伸铺满」，用户实测两档毫无区别。读 Godot 4.7.2 源码定案（`platform/windows/display_server_windows.cpp`）：`window_set_mode` 进入全屏时无条件 `MoveWindow` 到 `screen_get_size()`，且**全文件 `ChangeDisplaySettings` 零调用**——Godot 4.7 根本不做显示模式切换，任何非原生 `window.size` 在进全屏时被静默覆盖回桌面分辨率。此路线在该引擎版本物理不可能，非驱动设置问题。

## 修订 ADR-0019 的边界

ADR-0019 定下「F11 不进设置面板、不持久化」——指的是全屏**状态**。本次在其上正交新增宽高比**设置项**：进「画面与输入」页、持久化（settings.cfg `[video]` 段 `aspect`，9/10，默认 9）、不进「预设」。F11 本身仍是会话级热键，全屏状态照旧不持久化、每次启动回窗口模式。

## Considered Options

- **驱动缩放（原路线 A，否决）**：Godot 4.7 无显示模式切换（见上节），源码实锤，不可行。
- **主场景渲到 16:10 SubViewport 再拉伸 blit**：效果等价但主渲染管线大改（武器视角、曳光重投影、FX 采样全要重接），成本高一个量级，否决——content scale 是引擎内置的同一机制零成本版。
- **锁水平 FOV**：竖直视野随比例增多，不是 CS 的语义，否决。
- **窗口化也套用比例**：窗口自由缩放本就是现状，拉伸只在独占全屏下有意义，否决。
- **分辨率设置独立成页**：单设置项占一个页签太空，并入「画面与输入」页 + 只读信息行。

## Consequences

- **鼠标输入补偿（关键）**：content scale 的非均匀缩放会被 Godot 反向写进 `InputEventMouseMotion.relative`（`Viewport._make_input_local` → `xformed_by`），横向灵敏度会被除以拉伸比。玩家侧在视角输入处乘回 `window.size.x / content_scale_size.x`（`player._look_stretch_x`），保证水平与垂直每像素角速度一致——CS stretched 的灵敏度语义，瞄准训练器的硬要求。
- **集成面已核对**：武器视口是 `SubViewportContainer`（`stretch = true`，画布子节点）随 content scale 同步拉伸；`MuzzleReproject` 取两视口实际 aspect（content 尺寸下同为 16:10）自洽；HUD 画布坐标整体拉伸（CS HUD 同样被拉）。
- 16:10 档渲染分辨率低于原生（如 2304×1440@1440p），GPU 略省；16:9 档完全走旧直渲路径零变化。
- 不依赖任何驱动设置（N 卡缩放模式无关），任何显卡/面板表现一致。
- 切换时机：全屏状态下于设置页切档立即生效；窗口化仅记录、下次 F11 生效；退回窗口化恢复进全屏前的窗口尺寸。
- 16:10 档水平视野比 16:9 窄是**观感设计本体**（水平收窄 + 横向拉宽 = 目标变胖变扁），不是缺陷。
