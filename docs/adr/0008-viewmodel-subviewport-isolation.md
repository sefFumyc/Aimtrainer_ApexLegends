# Viewmodel 用 SubViewport 做深度隔离

原版的武器模型靠渲染层隔离避免穿模。Godot 没有内建的 WeaponCamera 节点，标准做法是 `SubViewportContainer` + `SubViewport`（透明背景）+ 独立武器相机 + `RemoteTransform3D` 跟随主相机，并用 cull mask 把武器几何隔离到独立视觉层。本项目认为这个开销值得：场地的「遮挡物」是程序化柱体与箱体，玩家贴上去时单相机方案会让枪直接插进柱子，而「不被遮挡物穿透」是 CONTEXT 里 Viewmodel 词条的明确要求。

_考虑过更省帧率的「单相机 + 视觉层隔离」（无深度隔离），在开阔场地里足够。因为本项目已确定引入遮挡物，故不采用。_

**Consequences**: 多一个视口即多一次渲染 pass 与透明混合，对追求高帧率的训练器需要在实机测量；若帧率不达标，回退点是单相机方案（同时需要放宽 Viewmodel 词条里「不被穿透」的承诺）。