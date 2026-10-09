# Implementation Plan: UX 反馈第 8 轮（R8）——Debug 模式门控 Logger 双写与工程债修复

**Input**: Feature specification from `spec/ux-feedback-round8/spec.md`

## Summary

引入 **debug 模式**：设置页「关于」面板应用图标 2 秒窗三连击开启（持久化 + toast 反馈），开启后同面板展示「调试模式」开关，关闭需二次确认；**debug 模式开启期间** `Logger.log` 在内存+落盘基础上同步双写 hilog 总线（外部 CLI 可实时读取），默认关闭仅落盘+内存——根治 R7 验证「日志只能翻 UI 取证」的根源问题。同步修复四项工程债：连点订阅重复记录、手动刷新不延长 TTL、两处死 onPop 回调、源页过冲提示未统一。

## Technical Context

**Language/Version**: ArkTS（HarmonyOS NEXT，compatibleSdkVersion 24）  
**Primary Dependencies**: ArkUI（V1 状态管理）、`@kit.ArkData`（preferences）、`@kit.PerformanceAnalysisKit`（hilog）、`@kit.CoreFileKit`（fileIo）  
**State Management**: 保留项目既有 V1（`@State`/`@StorageProp`/`@Watch`），不引入 V2  
**Storage**: Preferences（`AppStore.getNumber/putNumber` 既有模式）+ 沙箱日志文件（既有 Logger 落盘链）  
**Testing**: 无测试套件；验证 = `arkts_check` 预检 + `devecocli build` + API 24 平板虚拟机 UI 实测；**新增 CLI 取证通道**：debug 开启时 `devecocli log | grep BiliRadio`  
**Target Platform**: HarmonyOS NEXT 手机/平板  
**Project Type**: 单模块移动应用（entry）  
**Performance Goals**: 三连击判定零感知；hilog 双写微秒级非阻塞；无性能影响  
**Constraints**: ArkTS 严格模式（禁 any/unknown/as 断言、解构）；代码零注释（`ponytail:` 除外）；Constants.ets 唯一真相源；日志内容含请求路径（已截 query string），双写沿用 `%{public}s` 格式符  
**Scale/Scope**: 改动 5 个既有文件（Logger/Constants/SettingsPage/HomePage/SourcePage）+ 可选 SubscriptionStore；无新增组件（复用 R7 SettingsRow）；单一 feature 目录

## Project Structure

### Documentation (this feature)

```text
spec/ux-feedback-round8/
├── spec.md              # 需求规格（已评审）
├── plan.md              # 本文件
└── tasks.md             # 任务拆解（Phase 3 生成）
```

### Source Code (repository root)

```text
entry/src/main/ets/
├── pages/
│   ├── SettingsPage.ets      # 改：关于面板图标三连击 + 调试开关行 + 二次确认（US1/US2）；删死 onPop 回调（US6）
│   ├── HomePage.ets          # 改：addSubscription 内存去重（US4）；删死 onPop 回调（US6）
│   └── SourcePage.ets        # 改：手动刷新后元数据落盘（US5）；过冲提示统一（US7）
├── service/
│   ├── Logger.ets            # 改：debugMode 静态门控 + hilog 双写（US3）
│   ├── Constants.ets         # 改：新增 KEY_DEBUG_MODE / DEBUG_TAP_WINDOW_MS
│   └── SubscriptionStore.ets # 可选：persistRefreshedSub 公共方法（US5，供 SourcePage 复用 HomePage 模式）
└── （component/SettingsRow.ets 复用不改：showToggle 槽承载调试开关）
```

**Structure Decision**: 遵循项目既有架构（单模块、V1 状态管理、service 单例范式），不做 MVVM 迁移、不新增目录。改动全部落在既有文件的既有结构内（Logger 加静态标志、SettingsPage 关于面板加交互、Constants 加键），仅 SubscriptionStore 可能加一个公共方法消除 HomePage/SourcePage 的重复落盘逻辑——属最小 diff 范围内。

## Complexity Tracking

无违规模板项：全部改动为单文件内小改（<30 行/文件），无新组件、无新目录、无持久化模型变更。

## Research & Decisions

### D1: Debug 模式状态与持久化（US1/US2 / FR-001~003）

- **Decision**: 新增 `Constants.KEY_DEBUG_MODE: string = 'debugMode'`（存 number 0/1，沿用 `AppStore.getNumber/putNumber` 既有模式）；`Logger` 新增 `static debugEnabled: boolean` 与 `static setDebugMode(on: boolean)`。启动恢复：`Logger.init(context)` 内用 `preferences.getPreferencesSync` 直接读持久化值（**Appearance.init 同款模式**，不依赖 AppStore.init 时机），重启后无需重新三连击。
- **Rationale**: 用户明确要求持久化（跨重启保留）；AppStorage 是瞬态不持久化，Preferences 是项目既有偏好存储范式；Logger.init 已在 EntryAbility.onCreate 被调用，顺手恢复标志零额外挂点。
- **Alternatives considered**: AppStore 启动链读取（依赖 PlayerController 的 AppStore.init 时机，可能晚于首次日志调用）；内存态不持久化（违背用户明确要求）。

### D2: 三连击判定与反馈（US1 / FR-001）

- **Decision**: 关于面板图标 `Image($r('app.media.startIcon'))` 挂 onClick，SettingsPage 维护 `tapCount`/`lastTapTs` 两个私有成员：与上次点击间隔 ≤ `Constants.DEBUG_TAP_WINDOW_MS`（2000ms）则计数+1，否则重置为 1；计数达 3 → 置 debug 模式开 + toast「已开启调试模式」+ 计数清零。已在 debug 模式时三连击仅 toast「调试模式已开启，可在下方开关关闭」，不重复弹确认。
- **Rationale**: 用户确认 2 秒窗口 + toast + 开关关闭（「参考上一问」= 采纳推荐的 2 秒窗+toast+开关切换方案，且开启路径只需一次确认即三连击本身）；开启动作不二次确认（与 spec Assumptions 一致）。
- **Alternatives considered**: 长按/手势（无先例且难发现）；无条件每次点击即切换（易误触，违背「关闭需二次确认」）。

### D3: 调试开关与二次确认（US2 / FR-003）

- **Decision**: debug 开启后，关于面板图标下方追加一行 `SettingsRow`（title「调试模式」、subtitle 说明、`showToggle: true`、`toggleOn: debugEnabled`）；Toggle 关闭时弹 `AlertDialog.show` 二次确认（「退出调试模式？」确认/取消），确认→`Logger.setDebugMode(false)` + `AppStore.putNumber(KEY_DEBUG_MODE, 0)` + toast「已退出调试模式」；取消→状态不变。开关行仅在 debug 开启时渲染（未开启不展示，符合 spec）。
- **Rationale**: SettingsRow 是 R7 新增共用组件，showToggle 槽已支持；二次确认用项目既有 AlertDialog.show 模式（设置页已多处使用）；状态单一真相源 = Logger.debugEnabled + 持久化键同步。
- **Alternatives considered**: 开关放设置主页（spec Assumptions 明确仅关于面板）；Toggle 直改不确认（违背 FR-003）。

### D4: Logger 双写门控（US3 / FR-004~005）

- **Decision**: `Logger.log()` 在既有内存 push + appendFile 之后追加：`if (Logger.debugEnabled) { hilog.debug(Constants.LOG_DOMAIN, Constants.LOG_TAG, '%{public}s', line); }`（复用 `buildFileLine` 产物，格式与落盘一致）。落盘失败告警 `warnFileFailOnce` 的 hilog.warn 保持无条件（错误路径，与业务日志门控解耦）。写入失败 try/catch 静默，不影响主链路。
- **Rationale**: 双写内容与落盘一致（含已截 query string）；hilog.debug 级别可被过滤、环形缓冲不上传；门控在 Logger 内部实现，所有调用点零改动。
- **Alternatives considered**: 调用点逐个加判断（改动面大）；无条件双写（用户明确否决——刷屏/隐私外溢风险）。

### D5: addSubscription 内存去重（US4 / FR-006）

- **Decision**: `HomePage.addSubscription` push 前遍历 `this.subs` 按 `id`（或 sourceId）判重：已存在 → toast「已订阅该源」+ 直接 return（不 push/不 save/不刷新）；不存在才走既有流程。`SubscriptionStore.subExists`（磁盘判重）保留作纵深防御（AddSubscriptionSheet 打开时旧列表判重不变）。
- **Rationale**: 根因是 AddSubscriptionSheet 判重用「打开时旧列表」，会话内连点第二次时旧列表未含刚加的源 → 重复记录 → LazyForEach 重复键幽灵行。HomePage 内存数组是会话内唯一事实源，此处判重最可靠。
- **Alternatives considered**: 仅依赖 Sheet 内判重（根因不改仍复现）；SubscriptionStore 层去重（写盘层兜底但无法阻止幽灵行出现前的一致性问题）。

### D6: 手动刷新元数据落盘（US5 / FR-007）

- **Decision**: `SourcePage.refreshSource` 成功回调中，在 `loadFromCache()` 前将刷新后的 `this.sub` 元数据落盘：从 `SubscriptionStore.loadSubscriptions()` 重载磁盘列表 → 定位同 id → 覆盖 `lastRefreshAt/latestPubAt/cover/upperName` → `saveSubscriptions`。若 HomePage 的 `persistRefreshedSub` 同构逻辑抽为 `SubscriptionStore.persistRefreshedSub(sub, ok)` 公共方法则 SourcePage 直接复用（实现阶段裁决，目标是最小 diff + 消除重复）。
- **Rationale**: `refreshSubscription` 已就地更新 `sub.lastRefreshAt`/`latestPubAt`（SubscriptionStore L175-178），但只改内存对象不写盘；SourcePage 的 `this.sub` 是导航 param 载入的独立副本，刷新后从不回写磁盘 → TTL 判定（`Subscription.isCacheFresh`）持续基于陈旧时间。落盘即修复。
- **Alternatives considered**: refreshSubscription 内部直接 saveSubscriptions（会覆盖未保存的 lastSeenAt/sortOrder 等并发字段，有回写风险）；仅 SourcePage 就地落盘（可能留 HomePage 重复逻辑）。

### D7: 死 onPop 回调删除（US6 / FR-008）

- **Decision**: 删除两处死回调第三参：`HomePage.subRowItem` 的 `pushPathByName('sourcePage', row.sub.id, (popInfo: PopInfo) => { this.rebuild(); })`（onPop 对无参 pop() 永不回调，首页已由 AppStorage tick 驱动 rebuild）；`SettingsPage.openLogPage` 的 `pushPathByName('logPage', '', (popInfo) => { this.logCount = Logger.count(); })`（已由 `.onShown` 重读 logCount 取代）。相关误导性注释一并清理。
- **Rationale**: R7 验证实锤 onPop 仅 `pop(result)` 触发（navigation.d.ts L392-399 明载），本应用全部 pop() 无参 → 这两处回调是死代码且有误导性（初看以为返回时会刷新）。
- **Alternatives considered**: 保留（代码卫生要求删除，且 spec 明确 FR-008）。

### D8: 源页过冲提示统一（US7 / FR-009）

- **Decision**: `SourcePage` 列表对齐 HomePage R7 修复模式：`@State dragging` 守卫 + `.onWillStartDragging` 置位 + `.onReachStart` 置顶部提示「已经到顶了」（仅拖拽中）+ `.onReachEnd` 触底加载（既有）+ `.edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })`；顶部提示在 `.onScrollStop` 清空。底部「没有更多了」仍由既有常驻 footer / `bottomHintText` 承载（FR-003 已验证，不动）。
- **Rationale**: 源页现仅 onWillScroll 路径，纯边界过冲（偏移量不再变化）时不回调 → 顶部提示失效，与首页/历史面板行为不一致。R7 首页同款修复已验证有效（HomePage L366-400），直接对齐。
- **Alternatives considered**: 不修（spec 明确要求统一）；改用 onScrollEdge（List 无该接口，HomePage 已实证 onReachStart/onReachEnd 有效）。

## Data Model

无新增持久化实体。变更点：

- **`Constants.KEY_DEBUG_MODE: string`**（值 `'debugMode'`）——debug 模式持久化键，number 0/1，置于 Constants「Preferences 持久化键」段。
- **`Constants.DEBUG_TAP_WINDOW_MS: number`**（值 `2000`）——三连击时间窗，置于 Constants 魔法数段。
- **`Logger.debugEnabled: boolean`**（静态，默认 false）——hilog 双写门控标志，进程级单一真相源；由 `Logger.setDebugMode(on)` 变更、`Logger.init` 从 Preferences 恢复。
- 既有模型（Subscription/BiliVideo/LogEntry）零变更。

## Contracts & Interfaces

- **Logger 新增**:
  - `static setDebugMode(on: boolean): void`——置 `debugEnabled`；
  - `static debugEnabled: boolean`（只读暴露，供 UI 渲染开关态）；
  - `init(context)` 内部追加：从 Preferences 同步读 `KEY_DEBUG_MODE` 恢复 `debugEnabled`（Appearance.init 同款 getPreferencesSync 模式）。
- **Logger 行为变更**: `log()` 末尾，`debugEnabled` 为 true 时追加 `hilog.debug(LOG_DOMAIN, LOG_TAG, '%{public}s', line)`；false 时零 hilog 输出（业务日志）。`warnFileFailOnce` 的 hilog.warn 保持无条件。
- **SettingsPage（关于面板）新增契约**:
  - 图标 onClick：2 秒窗三连击 → debug 开（toast）；已开启时三连击仅 toast 提示；
  - 图标下方条件渲染 `SettingsRow`（调试模式，showToggle）：toggle 关闭 → AlertDialog 确认 → 关 + 持久化 0 + toast；取消 → 不变。
- **HomePage.addSubscription 行为变更**: 已存在同 id 订阅时 toast「已订阅该源」并 return，不重复添加。
- **SourcePage.refreshSource 行为变更**: 成功后刷新元数据写盘（重载磁盘列表→同 id 覆盖→save），或复用 `SubscriptionStore.persistRefreshedSub`（若实现阶段抽公共方法）。
- **删除**: 两处 `pushPathByName` 的第三参 onPop 死回调（HomePage sourcePage / SettingsPage logPage）。
- **SourcePage 列表新增**: `onWillStartDragging` / `onReachStart`（dragging 守卫）/ `edgeEffect(Spring, {alwaysEnabled: true})`；`onScrollStop` 清顶部提示。
