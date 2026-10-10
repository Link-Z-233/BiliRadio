# Implementation Plan: UX 反馈轮 R10 —— 小白条沉浸 / 隐藏胶囊穿透 / 日志页空白修复

**Input**: Feature specification from `spec/ux-feedback-round10/spec.md`

## Summary

三项修复：移除 Index Navigation 包裹层底部避让 padding 使设置页/日志页内容沉浸至小白条后方、各 NavDestination 页面自行补偿底部避让（FR-101/102）；迷你播放条隐藏时以 `HitTestMode.BLOCK_DESCENDANTS` 令整棵子树退出命中测试（FR-103）；`AS_MINI_PLAYER_VISIBLE` 上报移交 Index 反映真实显隐（FR-104）。全部为既有文件局部改造，零新增文件，零新依赖。

## Technical Context

**Language/Version**: ArkTS（API 24 兼容，`[API24-COMPAT]` 守卫不动）  
**Primary Dependencies**: 无新增；纯 ArkUI 组件属性与布局调整  
**State Management**: 沿用项目既有 V1（@State/@StorageLink/@StorageProp）  
**Storage**: 不涉及  
**Testing**: 无测试套件；arkts_check + `devecocli build`（build-only 既定决议，UI 实测由用户真机执行）  
**Target Platform**: HarmonyOS NEXT 手机/平板  
**Project Type**: 单模块 HarmonyOS 应用（既有工程，零结构变更）  
**Performance Goals**: 60fps 动画（沿用既有 animateTo 250ms 方案）  
**Constraints**: 状态栏顶部避让不动；MiniPlayer margin/PlayerOverlay/队列面板零改动  
**Scale/Scope**: 6 个 .ets 文件局部改

## Project Structure

### Documentation (this feature)

```text
spec/ux-feedback-round10/
├── spec.md
├── plan.md
└── tasks.md
```

### Source Code (repository root)

```text
entry/src/main/ets/pages/Index.ets          # 包裹层 padding + BLOCK_DESCENDANTS + 可见性上报（FR-101/103/104）
entry/src/main/ets/component/MiniPlayer.ets # 删除自身上报（FR-104）
entry/src/main/ets/pages/SettingsPage.ets   # 补 navBarHeight + 底部避让补偿（FR-102）
entry/src/main/ets/pages/LogPage.ets        # 补 navBarHeight + 底部避让补偿（FR-102）
entry/src/main/ets/pages/HomePage.ets       # 补 navBarHeight + 底部避让补偿（FR-102）
entry/src/main/ets/pages/SourcePage.ets     # 补 navBarHeight + 底部避让补偿（FR-102）
```

**Structure Decision**: 沿用既有项目架构（pages/service/model/component 分层），零新增文件、零结构变更。

## Complexity Tracking

无 Constitution 违规——三项均为最小 diff 局部修复。

## Research & Decisions

### D1 沉浸式避让重构（FR-101/102）

- **Decision**: `Index.ets:181` 包裹层 `.padding({ top: statusBarHeight, bottom: navBarHeight })` 改为 `.padding({ top: statusBarHeight })`（仅保留状态栏顶部避让）；底部小白条避让下沉到各 NavDestination 页面自行补偿
- **Rationale**: 父组件 padding 约束子节点绘制区，NavDestination 页面无法自行 `expandSafeArea` 逃出父 padding——移除包裹层 bottom padding 是让内容延伸到小白条后方的唯一路径；各页面避让值 = 原避让 + `navBarHeight`，末行滚动可达
- **Alternatives considered**: 包裹层 padding 条件化（随 onSettingsPage 翻转）——Navigation 承载所有页面共享同一 viewport，条件 padding 会让首页在转场期间反复 resize，弃用

### D2 隐藏胶囊退出命中测试（FR-103）

- **Decision**: `Index.ets:194` `.hitTestBehavior(this.miniHidden ? HitTestMode.None : HitTestMode.Default)` 改为 `HitTestMode.BLOCK_DESCENDANTS`（SDK `enums.d.ts` 实测拼写，since API 20，项目 minSdk 24 可用）
- **Rationale**: SDK 文档实锤——`None` =「自身不响应，但**不阻止子节点**参与命中测试」，故包裹层设 None 而 MiniPlayer 子树仍响应（现有 bug 根因）；`BLOCK_DESCENDANTS` =「自身 + 全部子孙均不响应，不影响祖先/兄弟」，触摸落到下层 Navigation 内容
- **Alternatives considered**: `.enabled(!miniHidden)`——`enabled(false)` 加灰度样式且官方未明确触摸是否穿透到下层兄弟，语义不透明，弃用；`Visibility.None`——瞬时消失打断淡出动画，弃用

### D3 可见性上报移交 Index（FR-104）

- **Decision**: `AS_MINI_PLAYER_VISIBLE` 上报从 MiniPlayer 移交 Index：`aboutToAppear` 初始化 `true`（初始胶囊可见），`onMiniVisibilityChanged` 计算 hidden 后写 `!hidden`；MiniPlayer 删除 `aboutToDisappear:31` 的 false 写入与 `syncFromPlayer:39-44` 的恒 true 上报块
- **Rationale**: MiniPlayer 恒挂载不卸载（避免订阅累积），其 `aboutToDisappear` 永不触发，恒上报 true 与真实显隐脱节——日志/设置页胶囊已隐藏却仍被预留 88px 避让（空白根因）；Index 同时持有 showPlayerOverlay/onSettingsPage 两个显隐条件，是上报真实可见性的唯一真相源；写 `AS_MINI_PLAYER_VISIBLE` 不触发自身 @Watch（watch 只监听两个 StorageLink key），无循环
- **Alternatives considered**: 消费方各自判断显隐条件——四消费方（首页/订阅页/设置页/日志页）重复推导易漂移，弃用

### D4 各页避让补偿值（FR-102）

- 设置页 `SettingsPage:1396`：`bottom: (this.miniPlayerVisible ? Constants.MINI_PLAYER_CLEARANCE : 24) + this.navBarHeight`（显隐标志修正后本页取 24，加小白条避让）
- 日志页 `LogPage:236`：`.padding({ bottom: this.navBarHeight })`（本页胶囊恒隐藏，minPlayerVisible 恒 false，直接简化为小白条避让）
- 首页 `HomePage:345` / 订阅页 `SourcePage:497`：`bottom: (this.miniPlayerVisible ? Constants.MINI_PLAYER_CLEARANCE : 12) + this.navBarHeight`
- 四页均在成员声明区补 `@StorageProp('navBarHeight') navBarHeight: number = 0;`
- 三键导航设备 navBarHeight 较大，补偿按实际值自动缩放；gesture 设备约 16-32px

## Data Model

不涉及。`AS_MINI_PLAYER_VISIBLE`（AppStorage 布尔键）语义修订：恒为 true → 反映真实显隐；四消费方均为只读端自动跟随。

## Contracts & Interfaces

不涉及新接口。唯一契约变化：`AS_MINI_PLAYER_VISIBLE` 值语义（恒 true → 真实显隐），消费方为只读无需改动；MiniPlayer 对外 props 不变。
