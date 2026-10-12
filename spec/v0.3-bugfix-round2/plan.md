# Implementation Plan: v0.3 Bug 修复第二轮（v0.3-bugfix-round2）

**Input**: Feature specification from `spec/v0.3-bugfix-round2/spec.md`

## Summary

十项反馈（9 用户故事 + 1 销项）的技术方案：三处左滑删除升级 SwipeActionItem 双触发（垃圾桶图标点击 + 滑过阈值）并统一二次确认，取消经 `ListScroller.closeAllSwipeActions()` 复位；批量/长按删除补确认；删除变更统一包 `animateTo` 实现补位动画；✓ 标记与「清理已播」改用 PlayerController 内存播放历史的 `progress === -1` 语义（复用 `removeSelectedFromPlaylist` 批量链路，倒序正序同语义）；清空队列经新模块 `service/BackHandler.ets` 自动关两层；四个返回处理点统一调用 `BackHandler.dismissOverlaysForBack()` 关闭序列；CoverThumb `highlight` 补 `@Prop` 修高亮跟随 + 边框改运行时主题色；封面占位换耳机图标。

## Technical Context

**Language/Version**: ArkTS（API 26 基线，compatibleSdkVersion 26.0.0，不做 API<26 兼容设计）  
**Primary Dependencies**: ArkUI（List/LazyForEach/SwipeActionItem/ListScroller/AlertDialog）、@kit.ArkUI promptAction  
**State Management**: 现状保留——模型层 `@ObservedV2`+`@Trace`；页面/挂键组件 `@ComponentV2`（`@Local`/`@Param`/`@Monitor`）；`AS_*` 经 V2State 包装类走 AppStorageV2；`PlayerController` 零装饰器广播（subscribe/emitUi + syncFrom 拷贝）；CoverThumb/SettingsGroup/EdgeHint 免迁 V1（`@Prop`-only），本轮 CoverThumb 仍保持 V1（只加 `@Prop`，不混代）  
**Storage**: 无变更——播放历史仍 AppStore（preferences）+ PlayerController 内存数组；队列仍 PlaylistDataSource  
**Testing**: 无测试套件；`arkts_check`（涉改 .ets）+ `devecocli build`  
**Target Platform**: HarmonyOS NEXT 手机/平板  
**Performance Goals**: 不引入新的整表 reload；沿用 diff 增量删除（notifyDataDelete）  
**Constraints**: 禁 any/unknown/as 断言；魔法值一律入 Constants.ets；代码零注释（`ponytail:` 除外）；已迁 V2 文件内新代码必须 V2 装饰器  
**Scale/Scope**: 单模块应用，改 11 个既有文件 + 新增 1 个 service 文件

## Project Structure

### Documentation (this feature)

```text
spec/v0.3-bugfix-round2/
├── spec.md               # 本轮需求（9 用户故事 + 1 销项）
├── plan.md               # 本文件
└── tasks.md              # Phase 3 产出
```

### Source Code (repository root)

```text
entry/src/main/ets/
├── service/
│   ├── BackHandler.ets        # [新增] 返回分层关闭序列 + 队列关闭句柄注册（D7）
│   ├── Constants.ets          # [改] 新增动画时长/关闭延时常量 + 确认弹窗文案常量（D1/D3/D6）
│   └── PlayerController.ets   # [改] isPlayed/hasPlayedItems 新增；clearPlayedItems 重写（D4/D5）
├── component/
│   ├── QueueSheet.ets         # [改] A1 队列左滑/A2 多选确认/B1 动画/B2 ✓/B3 弹窗/B4 清空关层
│   └── CoverThumb.ets         # [改] highlight @Prop 化 + accent 传递（D8）
└── pages/
    ├── Index.ets              # [改] onBackPress 换用助手；句柄注册改模块级（D7）
    ├── SettingsPage.ets       # [改] 历史左滑 A1+B1；onBackPressed 头部插助手（D1/D3/D7）
    ├── HomePage.ets           # [改] 订阅左滑 A1+B1；长按删除 A2 确认（D1/D2/D3）
    ├── SourcePage.ets         # [改] 补 onBackPressed（D7）
    ├── LogPage.ets            # [改] 补 onBackPressed（D7）
    └── PlayerOverlay.ets      # [改] 封面占位换耳机图标（D9）
```

**Structure Decision**: 沿用既有单模块架构与目录约定（pages/service/component/model 分层、依赖单向），不引入 MVVM 迁移。唯一新增文件 `service/BackHandler.ets` 为四个返回处理点共用的关闭序列模块（四处调用一段逻辑，规则三远超），不建目录、不加层。资源无新增（sys.symbol.trash / sys.symbol.headphones 已验证存在于 sysResource.js；danger_red 色值已存在）。

## Complexity Tracking

无宪法级违规。唯一偏离默认的新增物 `service/BackHandler.ets`：四个调用点（Index/SettingsPage/SourcePage/LogPage）共用同一关闭序列，复制粘贴式分发已产生过三个独立 bug（本轮 D 项根因），抽象由既有缺陷证明必要。

## Research & Decisions

### D1: A1 三处左滑删除——SwipeActionItem 双触发 + 二次确认 + 取消复位

**Decision**: 三处 `swipeAction` 的 `end` 从裸 `@Builder` 按钮升级为 `SwipeActionItem`：`builder` = 红色垃圾桶图标按钮（`sys.symbol.trash` + `$r('app.color.danger_red')` 底 + `$r('app.color.fg_on_dark')` 前景，尺寸对齐现按钮），点击进确认弹窗；`actionAreaDistance` 用默认 56vp；`onAction`（滑过阈值松手）进同一确认弹窗。弹窗复用 `AlertDialog.show` 既有模式（autoCancel、DialogAlignment.Center、取消/删除双钮），三处各自文案常量入 Constants。确认后删除（B1 动画包裹）；**取消后 `ListScroller.closeAllSwipeActions()` 收起滑动行**（faqs-arkui-277；本机 SDK list.d.ts L578 已验证），三处列表 scroller 由 `Scroller` 换 `ListScroller`（`ListScroller extends Scroller`，既有 scrollTo 等用法零影响）。挂点：SettingsPage L1088（历史）、QueueSheet L578（队列）、HomePage L349（订阅）。

**Rationale**: 用户明确要求双触发路径；取消复位是 spec FR-001「行复位收起」的唯一干净 API。

**Alternatives considered**: ①保留裸按钮仅加确认——无滑过阈值路径，不满足需求；②CustomDialog 自制弹窗——AlertDialog 现有模式已统一，无增益；③取消后不管（行保持展开等下次滑动收起）——违反 FR-001。

**已知行为（接受，已向用户说明）**: faqs-arkui-1121——声明 `onAction` 后删除触发区可延伸整行（恰为文件管理器式效果）；faqs-arkui-1556——多行同时滑开互斥收起，保持现状。

### D2: A2 批量移除与长按删除确认

**Decision**: `QueueSheet.removeSelected`（多选移除，L235）与 `HomePage.removeSub`（长按菜单/左滑共用，subRowMenu L254 与 subDeleteAction L271 两入口）头部加 `AlertDialog.show` 确认；确认后才执行（removeSelected 确认后先 `exitSelectMode` 再调 `controller.removeSelectedFromPlaylist`，批量调用包 animateTo 见 D3）。订阅删除与队列左滑/长按共用同一确认文案常量。

**Rationale**: 两处一键直删破坏面大（N 条队列条目/整个订阅）。

**Alternatives considered**: 仅队列加、订阅不加——同一破坏性等级，无差别理由。

### D3: B1 补位动画——一段式 animateTo 包裹删除变更

**Decision**: 全部删除路径的**数据变更调用**包 `this.getUIContext().animateTo({ duration: Constants.TOKEN_DELETE_ANIM_MS(250), curve: Curve.EaseOut }, ...)`。原理（faqs-arkui-910 第二段）：`notifyDataDelete` 落在 animateTo 闭包内时，List 布局变化（下方条目上移补位）按动画曲线过渡。覆盖：队列单删（包 `removeSelectedFromPlaylist([bvid])`——非当前条目路径全同步段内 emitUi→syncFrom diff→notifyDataDelete，闭包内生效）、历史单删（包 `removeHistoryItem`：@State splice + DataSource.notifyDataDelete 均同步）、订阅单删（包 `removeSub`）、批量（多选移除/清理已播/清空队列——包整个批量调用，多下标 diff 一次动画完成）。时长常量入 Constants。

**Rationale**: 一段式拿到核心价值（补位平滑），复杂度减半。

**Alternatives considered**: ①FAQ 910 两段式（先 visibility Hidden+transition 离场编舞，再延时删除）——per-row 可见性记账 × 三个列表 × 批量场景编舞，复杂度高收益低，弃；②仅 transition 离场不做补位——不满足需求本义。

**已知局限（接受）**: 队列删除**当前播放条目**时 `removeSelectedFromPlaylist` 内 `await playIndex(target)` → `emitUi` 落在动画闭包外 → 该次补位跳变；当前条目删除伴随自动切播，视觉重点转移，可接受。

### D4: B2 ✓ 标记——PlayerController.isPlayed(bvid)

**Decision**: `PlayerController` 新增只读方法 `isPlayed(bvid: string): boolean`（内存 `playHistory` 中命中 bvid 且 `progress === -1`）。QueueSheet 行内（非多选态）对 `isPlayed(item.bvid)` 为真的条目渲染 ✓：`sys.symbol.checkmark_circle` + success_green，视觉与 SourcePage L435-440 同款，位置实施时对齐（行尾/文字行内）。反应性链路：完播 → `markCurrentHistoryCompleted`（内存 progress=-1 + playHistoryVersion++）→ emitUi → QueueSheet.syncFrom → 重渲染取新值，**无需 QueueSheet 自建 Set 或自读 AppStore**。

**Rationale**: 数据源单点（controller 内存历史即真相），零重复加载。

**Alternatives considered**: QueueSheet 挂载时从 `AppStore.loadPlayHistoryFile()` 自建 playedSet（SourcePage 同款）——面板打开期间完播不刷新、重复 IO，弃。

### D5: B3 清理已播——clearPlayedItems 按 playedSet 重写

**Decision**: `clearPlayedItems` 重写：计算 `toRemove = playlist 中 isPlayed(bvid) 且 bvid ≠ 当前播放条目` 的 bvid 集合；空集 return（现状静默语义保留）；非空复用 `removeSelectedFromPlaylist(toRemove)`（removingCurrent/removedBeforeCurrent 索引修正、空队列重置、持久化全套语义白拿）。`currentItemEnded` 不再参与清理判定——当前条目永远保留（spec FR-003）。`QueueSheet.confirmClearPlayed`（L255）联动：可清判定改用 controller 新增 `hasPlayedItems(): boolean`（playlist 存在非当前且 isPlayed 的条目），无可清 toast 保留；确认弹窗 message 改计数式新常量（「确定清除 N 首已播条目吗？」），弃 ENDED/PLAYING 双态文案常量（语义不再分支）。

**Rationale**: 复用既有批量移除链路，正序/倒序/随机同语义，根除方向性 bug。

**Alternatives considered**: 保留前缀逻辑 + 倒序特判——两套语义并存，随机模式仍错，弃。

### D6: B4 清空队列自动关两层——BackHandler.closeQueueAndOverlay

**Decision**: `QueueSheet.clearQueue` 确认按钮 action 内追加 `BackHandler.closeQueueAndOverlay()`：①调全局注册的队列滑出句柄（250ms 滑出 + 260ms 后卸载，QueueDrawer.closeWithSlide 既有路径）；②`setTimeout(DRAWER_CLOSE_DELAY_MS)` 后置 `AS_SHOW_PLAYER_OVERLAY = false`（已 false 为 no-op）——浮层收起自带 350ms translate 转场（Index L222-223），形成「面板滑出→浮层滑落」由深到浅。QueueDrawer 本地常量 `DRAWER_CLOSE_DELAY_MS(260)` 上移 Constants（BackHandler 复用，避免双处硬编码）；`DRAWER_SLIDE_MS(250)` 保持组件内私有（无第二消费方）。Index 层队列（无浮层叠放）清空同函数，overlay 置 false 无副作用。

**Rationale**: 关闭动画走既有滑出路径，QueueDrawer/QueueSheet 契约零改动。

**Alternatives considered**: ①清空后直接置 `AS_SHOW_QUEUE_SHEET = false`——瞬间卸载无滑出动画，弃；②QueueDrawer 加 onClose 回调链——改三处契约，弃。

### D7: D 项返回分层——新增 service/BackHandler.ets 统一关闭序列

**Decision**: 新模块 `entry/src/main/ets/service/BackHandler.ets`：
- 模块级 `queueCloseHandle: (() => void) | undefined` + `registerQueueClose(handle)`（QueueDrawer 上报/注销的注册目标，替代 Index 成员 `this.queueClose`）
- `dismissOverlaysForBack(): boolean`——队列开：多选态优先退多选 return true；否则句柄滑出关闭（句柄空回退直接置 false，保留 Index 现有回退语义）return true。浮层开且历史面板开：关历史面板 return true。浮层开：关浮层 return true。否则 false
- `closeQueueAndOverlay(): void`（D6）

接线四处：①Index 两处 `onRegisterClose` 回调体（QueueDrawer L205 / PlayerOverlay L217）改调 `registerQueueClose`，`queueClose` 成员删除；②`Index.onBackPress` 队列+浮层段（L109-135）替换为 `if (dismissOverlaysForBack()) return true`，后段 playHistory/speed/mode/sleepTimerPicker/sleepTimer/selectMode 分支原样保留（顺序语义不变）；③`SettingsPage.onBackPressed` 头部插同一调用，其后 `showQualitySheet`/`showPlayHistory` 分支保留（qualitySheet 检查移到助手之后——音质面板与浮层实际不可同开，顺序无行为影响）；④`SourcePage`/`LogPage` 补 `.onBackPressed((): boolean => dismissOverlaysForBack())`——助手 false 时返回 false 放行 Navigation 默认 pop，两页无页面私有面板。

**Rationale**: 四处一段逻辑；句柄模块级注册为 `goToPlayerTab` 挂载模式的模块级变体（项目已有先例）；SettingsPage 补队列分支、SourcePage/LogPage 补整段，一次根治整族。

**Alternatives considered**: ①句柄留 Index、目的地页经路由参数回取——NavDestination 间无 Index 实例引用通道，不可行；②四处各复制关闭序列——复制已产出三个独立 bug（本轮根因），弃；③挂 PlayerController——播控职责无关，弃。

### D8: C1 CoverThumb——highlight @Prop 化 + 运行时主题色边框

**Decision**: `CoverThumb.highlight` 从普通成员改 `@Prop`（父组件更新传播，根因修复）；新增 `@Prop accent: string = Constants.ACCENT_DEFAULT`；两处高亮边框色（L31/L43-45）从 `$r('app.color.primary_color')` 改 `this.accent`。唯一传 `highlight` 的调用方 QueueSheet L518 补传 `accent: this.accentColor.value`；其余 9 处 CoverThumb 调用零改动（默认值行为不变）。CoverThumb 保持 V1 `@Component`（只加 `@Prop`，不引入 V2 装饰器）。

**Rationale**: `@Prop` 是 V1 组件父→子单向传播的标准机制；accent 运行时可变（主题色板），必须由持有 StrState 的父方传入。

**Alternatives considered**: ①CoverThumb 内 `connectStr` 自读 AS_ACCENT_COLOR——V1 组件内 V2 观测不生效，弃；②换静态资源色——主题色运行时切换会失真，弃。

### D9: C2 封面占位——耳机图标

**Decision**: PlayerOverlay L881-892 空封面占位 `Text('♪')` 换 `SymbolGlyph($r('sys.symbol.headphones'))`（sysResource.js 已验证存在），fontSize 对齐原 56 量级（实施定值入 Constants 既有字号 token），颜色保持 `accentColor.value`。**范围仅此一处**：CoverThumb 无封面 ♪（L34）、HomePage 空态 ♪（L278）不动。

**Rationale**: 用户明确指定唯一位置。

**Alternatives considered**: 全局 ♪ 统一换——超出本轮范围，未获批。

### D10: E 项屏幕常亮——销项

**Decision**: 无代码改动。结论记入 PROJECT_NOTES：全库无 `keepScreenOn`；实测常亮为系统层行为（最可能开发者选项「不锁定屏幕」，USB 调试充电时触发）；验证方式拔线重测。

## Data Model

无新增数据实体。状态/契约变更：

| 位置 | 变更 |
|------|------|
| `BackHandler`（新） | 模块级 `queueCloseHandle`（可注册/注销）；无持久化 |
| `CoverThumb` | `highlight: boolean` 普通→`@Prop`；新增 `@Prop accent: string`（默认 `Constants.ACCENT_DEFAULT`） |
| `PlayerController` | 新增只读 `isPlayed(bvid): boolean`、`hasPlayedItems(): boolean`；`clearPlayedItems()` 语义重写（签名不变，Promise\<void\>） |
| `Constants` | 新增 `TOKEN_DELETE_ANIM_MS`（250）、`DRAWER_CLOSE_DELAY_MS`（260，自 QueueDrawer 上移）、三处删除确认文案、清理已播计数文案 |

不变式（沿用现有语义）：`progress === -1` 仅由完播写入、重播 upsert 重置为 0；`AS_SHOW_QUEUE_SHEET`/`AS_SHOW_PLAYER_OVERLAY` 关闭后必须为 false（本轮修复的正是残留路径）。

## Contracts & Interfaces

### BackHandler（新模块，四处消费）

```text
registerQueueClose(handle: (() => void) | undefined): void
  // QueueDrawer aboutToAppear 上报 closeWithSlide / aboutToDisappear 注销 undefined
dismissOverlaysForBack(): boolean
  // true=已消化一次返回（浮层栈有关闭）；false=无浮层可关，调用方走自身后续/默认 pop
closeQueueAndOverlay(): void
  // 清空队列后自动关闭：滑出关队列 → 延时关浮层（未开则 no-op）
```

### PlayerController 新增/变更

```text
isPlayed(bvid: string): boolean          // 内存 playHistory 命中且 progress === -1
hasPlayedItems(): boolean                // playlist 存在非当前且 isPlayed 的条目
clearPlayedItems(): Promise<void>        // 语义：移除所有 isPlayed 且非当前的条目（复用 removeSelectedFromPlaylist）；无可清静默
```

### 列表组件契约（三处一致）

- swipeAction `end`：`SwipeActionItem`（builder=垃圾桶图标钮 / actionAreaDistance 默认 / onAction）→ 统一进 AlertDialog 确认 → 确认执行删除、取消 `closeAllSwipeActions()` 复位
- 三处 List scroller 类型换 `ListScroller`（构造与既有 Scroller 用法兼容）
- 删除数据变更包 `animateTo(TOKEN_DELETE_ANIM_MS)`

### 验证范围

默认 build-only（`<!-- verification_scope: build-only -->`，AGENTS.md 默认值）；真机行为由用户实测反馈。Phase 3 Review Gate 前用户可显式改 build+ui。
