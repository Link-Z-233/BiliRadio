# bugfix（v0.6-part3-sub-manage）

直接修复缺陷登记（不走 SDD 任务的修复；按发生顺序编号分节追加，不带日期戳）。

## 1. 非编辑态卡片边缘长按触发系统拖拽排序

- 现象：首页未进排序模式时，长按条目边缘（上/下/右 padding 带，首版修复后残留最左端 ~12vp）直接进入 List 系统拖拽视觉；抬手落子被 `applyDragOrder` 编辑态闸拒绝不改序，但拖拽已发生。
- 根因（两段叠加）：① `subRowItem` 根 Row 保留行 padding（L12/R12/T10/B10），padding 带无任何手势认领；内容包装 Row 的 LongPressGesture 只覆盖自身盒区，List 恒绑 `onMove`（US8 FR-023）的内建长按拖拽在未认领区仲裁胜出——与「行级手势阻塞系统拖拽」同一机制的补集面。② 首版修复（padding 迁移）后真机复测最左端仍误触：把手容器 `width(0)+padding({left:12})`——ArkUI `.width()` 是内容宽、padding 在外另加（与 `layoutWeight` 含 padding 分配语义相反），正常态把手实占 12vp 残带；残带仅 pan 认领（移动触发），长按无人认领漏给 List 内建拖拽。定位：`ui longclick` 逐点探测（x=40 无菜单 / x=600 弹菜单二分）+ a11y 叶子坐标反推（容器 bounds 不可靠）。
- 修复：① 行 padding 从根 Row 迁入内容包装 Row（恒值），把手容器 padding 由 right 改 left。② 把手 padding 随宽度同条件归零（`editMode ? TOKEN_SPACE_M : 0`）——正常态把手真零宽、残带消除，内容起点回正与本轮前基线一致（残带致 24 的中间态漂移消除；编辑态起点不变）。把手长按触发的系统拖拽兜底同轮去除（空 LongPressGesture 认领阻断，FR-026 修正项，非本缺陷）。
- 涉及：`entry/src/main/ets/pages/HomePage.ets`（subRowItem：根 Row 去 padding、把手 padding 换向+条件归零、内容包装补 padding）
- 验证：arkts_check 6 条 SDK 误报基线 + `devecocli build` 成功；真机复测——`ui longclick 40 420`（最左缘）长按弹菜单（修复前无菜单、进系统拖拽），`ui longclick 600 420`（中部）弹菜单，非编辑态整卡长按全域认领；把手 pan-only/并行组行为见 FR-026 真机自查。
