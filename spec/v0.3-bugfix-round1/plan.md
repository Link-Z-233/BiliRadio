# Implementation Plan: v0.3 Bug 修复第一轮

**Input**: Feature specification from `spec/v0.3-bugfix-round1/spec.md`

## Summary

v0.3.0 真机实测 9 项问题一轮修复：播放按钮呼吸浮动与播放/暂停图标抖动（含 MiniPlayer 周期变化）、全页面过冲文字移除、播放页状态行移除、倒序图标旋转 180°、播放页内队列系统返回动画、「仅在 Wi-Fi 环境播放」开关拦截非 Wi-Fi 播放（原 T005 误删已回退）、多选模式退出完整。纯修复轮，不引入新功能，不改数据模型。

## Technical Context

**Language/Version**: ArkTS / HarmonyOS NEXT（API 26 基线，compatibleSdkVersion=26.0.0）
**Primary Dependencies**: @kit.ArkUI（组件/状态）、@kit.AbilityKit、@kit.MediaKit（AVPlayer）
**State Management**: V2（全页面 @ComponentV2/@Local；PlayerController 零装饰器纯类手动广播 subscribe/emitUi）
**Storage**: AppStore（preferences）——本轮不动持久化
**Testing**: arkts_check + devecocli build + 真机 UI 验证（用户实测反馈，模拟器验证已终止）
**Target Platform**: HarmonyOS NEXT API 26 真机
**Project Type**: 移动应用（HarmonyOS），单模块
**Performance Goals**: 无新增性能要求；播放按钮动画不得引入持续运行的无限动画
**Constraints**: 代码零注释（ponytail: 除外）、Constants 唯一真相源、禁 any/unknown/as、V2 装饰器、构建每故事验证
**Scale/Scope**: 7 用户故事 / 8 文件改动 / 无新增文件

## Project Structure

### Documentation (this feature)

```text
spec/v0.3-bugfix-round1/
├── spec.md              # 需求规格
└── plan.md              # 本文件
```

### Source Code (repository root)

```text
entry/src/main/ets/
├── pages/
│   ├── PlayerOverlay.ets      # US1（播放按钮动画/图标）、US3（状态行）、US5（队列返回）
│   ├── Index.ets              # US5（onBackPress 队列动画）、US7（onBackPress 多选优先）
│   ├── HomePage.ets           # US2（EdgeHint 移除）
│   ├── SourcePage.ets         # US2（EdgeHint 移除）
│   └── SettingsPage.ets       # US2（EdgeHint 移除 ×2 面板）
├── component/
│   ├── MiniPlayer.ets         # US1（图标稳定，与 controller 同源修复）
│   ├── QueueSheet.ets         # US2（EdgeHint 移除）、US7（关闭自动退多选）
│   ├── QueueDrawer.ets        # US5（关闭句柄注册保持）
│   └── EdgeHint.ets           # US2（组件整体删除）
├── service/
│   └── PlayerController.ets   # US6（非 Wi-Fi 播放确认拦截，T005 回退）、US1（isPlaying 状态稳定）
```

**Structure Decision**: 遵循既有项目架构（pages/component/service 分层，无 MVVM 迁移——既有工程，非新架构；本轮为增量修复，不引入新目录、新组件，EdgeHint 删除为唯一文件移除）。状态管理沿用 V2（既有已迁移基线）。

## Complexity Tracking

> 无宪章违规项需要论证。全部为既有文件内的定向修改。

## Research & Decisions

### US1 播放按钮呼吸浮动 + 播放/暂停抖动 + MiniPlayer 周期变化

- **现象拆分**：①「呼吸浮动」= 播放态下 `updateGlow()` 启动 `iterations: -1 + PlayMode.Alternate` 无限往复动画（3200ms 周期），驱动封面光晕 `glowStrength`（0.35↔0.8）持续呼吸，视觉上播放按钮区域随之「浮动」；②「播放/暂停来回切换」= `isPlaying` 状态抖动，播放/暂停图标（L1119-1126 渲染分支）随抖动来回切换；③「MiniPlayer 周期变化」= MiniPlayer 经 `syncFromPlayer` 同步同一 `PlayerController.isPlaying`，controller 层抖动 → MiniPlayer 按钮同步抖动（用户观察序：先播放页后首页，源为同一状态）。
- **Decision**：
  - `updateGlow()` 移除无限呼吸（`iterations: -1`）——改为播放/暂停状态切换时**一次性**过渡（播放进入 → glow 淡入至 ACTIVE 后停止；暂停 → 淡出至 IDLE），消除持续呼吸浮动；或按用户意图直接退化光晕为静态两态（IDLE/ACTIVE 随状态切换，无往复动画）。
  - `isPlaying` 抖动收敛在 **PlayerController.onPlayerState**：`playing/paused` 状态写入前加去抖——仅当状态**稳定保持**（如连续 300ms 无翻转）才写 `isPlaying` 并 `emitUi`；避免 AVPlayer stateChange 链路（缓冲暂停/恢复、音频焦点、`playRequest/pauseRequest` 竞态）瞬时翻转传播到 UI。
  - 图标渲染分支收紧：`isPreparing` 期间（LoadingProgress 之外）不渲染 play/pause 图标切换（维持既有 LoadingProgress 分支），仅稳定态渲染图标。
  - MiniPlayer 无独立修复点——controller 状态收敛后自然同步（其 `syncFromPlayer` 已有值比对）。
- **Rationale**: 无限动画是「呼吸浮动」唯一来源（KI-5 遗留观察曾记录「updateGlow 3200ms 往复用户从未观察到」——真机可见即本轮 bug）；isPlaying 抖动根因在状态广播层（单一事实源），收敛 controller 一处即同时修复播放页 + MiniPlayer，符合「修复根因不修表象」。
- **Alternatives considered**: 仅在 PlayerOverlay 渲染层加防抖（状态仍抖，MiniPlayer 漏修）✗；删除整个 updateGlow 光晕（视觉回归：播放态氛围光晕是既有设计）✗。

### US2 移除「已经到顶了/已经到底了」文字提醒

- **现状**：EdgeHint 组件 5 处使用（HomePage L353-354、SourcePage L429-430、SettingsPage 历史面板 L1078-1079 + 设置滚动 L1235-1236、QueueSheet L487-488），16 处赋值（`topHint/bottomHint` 系列状态）。EdgeHint 仅承载文字提示渲染。
- **Decision**: 删除 EdgeHint 组件文件（`component/EdgeHint.ets`）与其全部 5 处 import/调用/赋值状态字段/触发逻辑；滚动过冲**物理回弹**（alwaysEnabled/overScroll）保留不动（用户仅要求去文字，不要求改滚动手感）。
- **Rationale**: 组件唯一用途即文字提示，无其他消费者（全局检索确认仅 5 处 import）→ 整体删除优于留壳。
- **Alternatives considered**: 保留组件但调用处传空串（留死代码）✗。

### US3 移除播放页底部常驻状态行

- **现状**: PlayerOverlay L1272-1281 `statusMsg` 常驻固定底栏（含 isPreparing 时行首 LoadingProgress）。
- **Decision**: 删除该状态行整段 UI（Text + 行首 LoadingProgress 分支）；`statusMsg` 业务赋值（PlayerController 内 40+ 处）**保留不动**（仍是播放逻辑的日志/诊断通道，仅不再展示；MediaSession/历史等消费方不受影响）。
- **Rationale**: 用户明确「删状态行整行」；删 UI 展示即可，动 controller 赋值链路风险大且无收益。
- **Alternatives considered**: 同步删除 statusMsg 赋值（大范围误伤，且未来恢复展示成本高）✗。

### US4 倒序播放图标旋转 180°

- **现状**: `playModeIcon()`（PlayerOverlay L394-405）REVERSE → `sys.symbol.reverse_order`。
- **Decision**: REVERSE 分支改为返回 `sys.symbol.order_play`（与顺序同款），渲染处（L1204 SymbolGlyph）按模式加 `.rotate({ angle: 180 })`——新增 `playModeRotate()`（REVERSE=180，其余=0）与 `playModeIcon()` 并列；仅 REVERSE 旋转。
- **Rationale**: 用户采纳方案——「方向相反=倒序」语义直观；复用既有资源零新增资源文件；rotate 为通用属性，SymbolGlyph 支持。
- **Alternatives considered**: 自绘倒序图标（新增资源/矢量）✗；保持 reverse_order（用户已否）✗。

### US5 播放页内队列系统返回无动画（根因已定位）

- **根因**: Index.onBackPress（L109-117）经 `this.queueClose` 句柄触发滑出动画；该句柄仅由 Index 层 QueueDrawer 的 `onRegisterClose` 上报（L198-202）。播放页打开时 Index 层 QueueDrawer 不渲染（L197 条件 `&& !showPlayerOverlay`），播放页内实例（PlayerOverlay L1324-1327）**未传 onRegisterClose** → 句柄 undefined → 返回走 `showQueueSheet.value = false` 直接卸载，无动画。
- **Decision**: PlayerOverlay 内 QueueDrawer 实例补传 `onRegisterClose`，将滑出句柄上抛至 Index 统一持有（经既有 `onRegisterClose` 契约）；Index.onBackPress 逻辑不变（有句柄→滑出，无→兜底）。实现：PlayerOverlay 增加 `@Param onRegisterClose` 透传（Index 渲染 PlayerOverlay 时传入自身持有的回调，或经共享状态）；QueueDrawer 契约零改动。
- **Rationale**: 复用既有 QueueDrawer 关闭契约（closeWithSlide 已实现动画+延时卸载），不新造机制；Index 单点持有句柄保证两实例行为一致。
- **Alternatives considered**: Index 直接置 false（现状，无动画）✗；PlayerOverlay 自行消费返回键（与 Index 返回拦截重复，风险高）✗。

### US6 「仅在 Wi-Fi 环境播放」开关拦截非 Wi-Fi 播放（原 T005 误删已回退）

- **根因/纠错**: 原 plan D6 将开关误判为「下载」语义（依据内部键名 `KEY_WIFI_ONLY_DOWNLOAD` / 变量 `wifiOnlyDownload` / 旧注释「缓存下载门控」），故决策「移除 playIndex 拦截块」。**实测核对设置页 UI 文案为「仅在 Wi-Fi 环境播放 / 非 Wi-Fi 网络播放需手动确认」——键名是历史遗留误导名，开关实为「非 Wi-Fi 播放确认」功能**。原 T005 删除该块即是「流量下切歌不触发非 Wi-Fi 限制」的直接原因。
- **Decision**: **回退 T005**——`playIndex` 恢复 wifiOnly 确认拦截块（开关开且非 Wi-Fi 时弹 `confirmCellularDownload`，未确认则取消本次播放并 `statusMsg='当前非 Wi-Fi 网络，已取消播放'`）；注释修正为真实语义（非 Wi-Fi 播放确认，非「缓存下载门控」）。拦截点保持 `playIndex`（起播/切歌/切集统一路径）。
- **Rationale**: 以 UI 文案为准，开关的既有功能应保留并正常工作；用户实测期望开关生效。
- **Alternatives considered**: 保留删除（把播放确认功能废掉，用户已否）✗。
- **遗留待验（用户真机）**: 若回退后开关仍不触发确认框，则属独立缺陷（疑点：设置页开关持久化读取 / `confirmCellularDownload` 中已废弃的 `AlertDialog.show` 在 API 26 的实际表现），需真机日志（应用内日志页）核对 `wifiOnly`/`isWifi` 实值。
- **补充（bug#2 修复，真机反馈「阻断太晚」）**: 拦截块 MUST 位于 `playIndex` **任何状态改写之前**（index 校验之后、`currentIndex` 改写与 `emitUi()` 之前）——否则 UI 先切到新曲目（标题/封面/按钮态），取消时旧音频仍在播放而 UI 显示新曲目，三者不一致。原实现把拦截块放在 `emitUi()` 之后即此缺陷。

### US7 队列多选模式退出完整

- **根因**: ① Index.onBackPress 中 `selectMode` 分支（L154-158）排在 `showQueueSheet`（L109-118）之后——队列开着时返回先命中关面板，进不到多选分支；② QueueSheet/QueueDrawer 关闭路径只置 `showQueueSheet=false`，未复位 `selectMode`/`selectedBvids`。
- **Decision**:
  - Index.onBackPress：在 `showQueueSheet` 分支内**先查 selectMode**——`selectMode.value === true` 时仅 `exitSelectMode`（置 false + 清 selectedBvids）并 return true（面板保留）；否则走既有滑出关闭。selectMode 全局分支（L154-158）保留为兜底。
  - QueueSheet 关闭自动退多选：经 `@Monitor('showQueueSheet.value')` 监听——面板关闭（value→false）时自动 `exitSelectMode()`；或复用 QueueSheet 现有 selectMode 消费点统一复位。选择 @Monitor 方案（单一出口，覆盖遮罩/返回/滑出所有关闭路径）。
- **Rationale**: 返回优先退多选符合交互惯例（多选是临时编辑态，返回应退态而非关面板）；@Monitor 单出口保证任意关闭方式无残留。
- **Alternatives considered**: 各关闭路径逐点复位（遮罩/返回/滑出三处易漏）✗。

## Data Model

无新增/变更实体。涉及现有：
- `PlayMode`（PlayerController.ets，SEQUENTIAL/REPEAT_ONE/RANDOM/REVERSE）——仅 REVERSE 图标映射变化
- `Constants.KEY_WIFI_ONLY_DOWNLOAD`——语义边界调整（不再拦截播放），键保留
- `QueueSheet.selectMode` / `selectedBvids`——退出语义补全（返回/关闭复位）
- 删除：`EdgeHint` 组件及其 5 处使用点（无数据实体影响）

## Contracts & Interfaces

### PlayerOverlay 新增对外参数

```text
@Param onRegisterClose: (close: (() => void) | undefined) => void = <no-op>
```
透传给内部 QueueDrawer 的 `onRegisterClose`（既有契约，QueueDrawer 零改动）。

### Index.onBackPress 行为修订

```text
输入: 无（系统返回事件）
行为: showQueueSheet && selectMode → 仅退出多选（面板保留）→ return true
      showQueueSheet && !selectMode → queueClose() 滑出（undefined 兜底直接置 false）→ return true
      selectMode（无队列）→ 退出多选 → return true
```

### PlayerController.isPlaying 状态收敛

```text
onPlayerState('playing'/'paused') → 300ms 稳定窗口去抖后才写 isPlaying + emitUi
（防抖实现细节：状态翻转计时器；翻转后重置窗口；窗口内再次翻转不写状态）
```

### PlayerOverlay 动画契约

```text
updateGlow(): 移除 iterations:-1 无限往复——isPlaying 变化时一次性过渡（淡入 ACTIVE / 淡出 IDLE），无持续动画
playModeIcon(): REVERSE → sys.symbol.order_play
playModeRotate(): REVERSE → 180，其余 → 0（新增，供 SymbolGlyph.rotate 使用）
```

### 移除项清单

```text
EdgeHint.ets（组件文件整体删除）
5 处 EdgeHint import/调用 + 16 处 topHint/bottomHint 赋值与相关状态字段
PlayerOverlay statusMsg 常驻底栏 UI（L1272-1281 段）
```

> 注：`PlayerController playIndex` 内 wifiOnly 拦截块**不删除**（原 T005 误删已回退，见 US6）。

> 无外部 API/网络接口变更；无持久化格式变更。
