# Implementation Plan: UX 反馈轮 R9 —— 队列底部弹出与显示修复

**Input**: Feature specification from `spec/ux-feedback-round9/spec.md`

## Summary

四项修复：QueueDrawer 由右侧抽屉改底部弹出（FR-101）、面板背景近实底（FR-102）、队列 List 补 `alwaysEnabled` 过冲与双向 EdgeHint（FR-103）、时长未知条目隐藏 00:00（FR-104）。全部为既有文件的局部改造，零新增文件，零新依赖。

## Technical Context

**Language/Version**: ArkTS（API 24 兼容，`[API24-COMPAT]` 守卫不动）  
**Primary Dependencies**: 无新增；纯 ArkUI 组件属性与颜色资源调整  
**State Management**: 沿用项目既有 V1（@State/@StorageLink/@StorageProp）  
**Storage**: 不涉及  
**Testing**: 无测试套件；arkts_check + `devecocli build`（build-only，模拟器不可用为既定决议——此前可用，本次系统偶发，用户确认本轮仍跳过 UI 验证）  
**Target Platform**: HarmonyOS NEXT 手机/平板  
**Project Type**: 单模块 HarmonyOS 应用（既有工程，零结构变更）  
**Performance Goals**: 60fps 动画（沿用既有 animateTo 250ms 方案）  
**Constraints**: 规避 KI-5（不用系统半模态）；多选长按滑动多选手势优先级不变  
**Scale/Scope**: 2 个 .ets 文件局部改 + 2 个颜色资源值

## Project Structure

### Documentation (this feature)

```text
spec/ux-feedback-round9/
├── spec.md
├── plan.md
└── tasks.md
```

### Source Code (repository root)

```text
entry/src/main/ets/component/QueueDrawer.ets   # 底部弹出改造（FR-101）
entry/src/main/ets/component/QueueSheet.ets    # alwaysEnabled + 双向 EdgeHint + 00:00 兜底（FR-103/104）
entry/src/main/resources/base/element/color.json   # queue_panel_background 提不透明度（FR-102）
entry/src/main/resources/dark/element/color.json   # 同上深色份
```

**Structure Decision**: 沿用既有项目架构（pages/service/model/component 分层），零新增文件。

## Complexity Tracking

无 Constitution 违规——四项均为最小 diff 局部修复。

## Research & Decisions

### D1 QueueDrawer 底部弹出（FR-101）

- 外层 Stack `alignContent: Alignment.End` → `Alignment.Bottom`；遮罩（mask_heavy + OPACITY 过渡 + 点击关闭）原样保留
- 面板：`.width('100%')`、`.height('65%')`、`.borderRadius({ topLeft: 16, topRight: 16 })`、`.clip(true)`
- 位移：`panelOffsetX`（'100%'↔'0%'）改名 `panelOffsetY` 并改挂 `.translate({ y })`——translate 百分比相对面板自身尺寸，Y 轴滑入滑出机制与 X 轴完全同构
- 删去 `statusBarHeight` 顶部留白（面板已不压状态栏）；`@StorageProp('statusBarHeight')` 引用一并移除
- 动画时长、closeWithSlide、onRegisterClose 句柄、aboutToAppear/aboutToDisappear 生命周期全部不动；文件头注释更新为底部弹出描述
- Index.ets / PlayerOverlay.ets 两处挂载点零改动（形态变化封装在 QueueDrawer 内部）

### D2 面板近实底（FR-102）

- `queue_panel_background`：base `#66FFFFFF` → `#F2FFFFFF`（95%），dark `#A61E1E22` → `#F01E1E22`（94%）
- 仅改资源值，引用点（QueueDrawer backgroundColor）不动；backdropBlur(20) 保留作轻微质感

### D3 alwaysEnabled + 双向 EdgeHint（FR-103）

- QueueSheet List 补 `.edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })`（对齐 HomePage/SettingsPage/SourcePage 三处既有写法）
- 新增 `@State queueTopHint: string = ''`；外层 Stack 增 `EdgeHint({ text: this.queueTopHint, edge: 'top' })`（声明在 List 之前，z 序更低，与既有 bottom EdgeHint 并列）
- 驱动逐行对齐 SettingsPage 历史面板（`historyDragging`/`historyTopHint`/`historyBottomHint` 模式）：
  - `onWillStartDragging` 置 `queueDragging = true`
  - `onReachStart` 拖拽中守卫置「已经到顶了」（守卫 onReachStart 初始化误触发）
  - `onReachEnd` 既有逻辑保留（记录 queueEndY + 拖拽中守卫置「已经到底了」）
  - `onWillScroll`：yOffset<0 清底词、y≤0 置顶词；yOffset>0 清顶词、既有 queueEndY 到底判定保留
  - `onScrollStop` 双词全清 + `queueDragging = false`

### D4 时长显示兜底（FR-104）

- QueueSheet 条目第二行改条件渲染：`item.duration > 0` 显示 `${item.ownerName} · ${formatTime(item.duration * 1000)}`，否则只显示 `item.ownerName`
- 不做入队拉详情回填（播放时既有回填机制自然补齐，重进持久化往返已核实无损）

## Data Model

不涉及。BiliVideo.duration 语义不变（0=未知）。

## Contracts & Interfaces

不涉及新接口。QueueDrawer 对外契约（showQueueSheet @StorageLink、onRegisterClose 回调）不变，两处宿主（Index/PlayerOverlay）零感知。
