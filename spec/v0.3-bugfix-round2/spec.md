# Feature Specification: v0.3 Bug 修复第二轮 —— 删除防误触 / 队列语义修正 / 返回分层 / 高亮修复

**Created**: 2026-10-12  
**Status**: Draft  
**Input**: 用户反馈 10 项（v0.3-bugfix-round1 修复后实测）：左滑删除误触风险（3 处左滑 + 2 处批量/长按删除均无二次确认）、队列「清理已播」倒序清错、播放列表缺已播标记、清空队列面板残留、删除无补位动画、当前播放高亮边框不跟随、封面占位图标、非首页系统返回分层错乱、屏幕常亮疑问（销项）

## Overview

十项反馈合并为 9 个用户故事 + 1 项销项。核心三类：①破坏性操作补二次确认（左滑删除改造为「静态红色垃圾桶图标 + 确认弹窗」双触发路径，批量/长按删除同补确认）；②队列语义修正（「清理已播」改为按已听完标记清理、修复倒序清错，播放列表补 ✓ 标记，清空队列自动关两层，删除补位动画）；③全局返回分层修复（四个返回处理点统一「先关队列→再关浮层」序列）与两处视觉修复（高亮边框跟随、封面占位图标）。

**销项（E 项，无代码改动）**：屏幕常亮疑问——全代码库无 `keepScreenOn` 调用，实测常亮为系统层行为，最可能是开发者选项「不锁定屏幕」（USB 调试充电时保持唤醒）触发；验证方式：拔掉 USB 线重测。

## User Scenarios & Testing *(mandatory)*

### User Story 1 - 三处左滑删除二次确认（垃圾桶图标改造）(Priority: P1)

设置页播放历史、播放队列、首页订阅三处左滑删除：MUST 改为静态红色垃圾桶图标（放弃开盖动画——无现成组件）；点按垃圾桶图标或滑动超过阈值后松手，MUST 弹出二次确认弹窗；仅在弹窗中确认后才执行删除，取消则不删且该行复位收起。现状：三处均为左滑直接删除，无任何确认（`historyDeleteAction`/`queueDeleteAction`/`subDeleteAction`）。

**Why this priority**: 三处均直接删数据且不可恢复（订阅删除、队列条目删除、历史条目删除），误触代价高，防误触为安全需求。

**Independent Test**: 三处分别左滑出现红色垃圾桶图标→点图标弹确认框→取消不删、确认才删；滑过阈值松手同样弹确认框。

**Acceptance Scenarios**:

1. **Given** 设置页播放历史某条目，**When** 左滑后点按垃圾桶图标，**Then** 弹出二次确认弹窗；点「取消」条目保留且行收起，点「确认」条目删除
2. **Given** 播放队列某条目，**When** 左滑超过阈值松手，**Then** 弹出二次确认弹窗，确认后才删除
3. **Given** 首页订阅某项，**When** 左滑点垃圾桶，**Then** 弹出二次确认弹窗，确认后取消订阅
4. **Given** 任一确认弹窗打开，**When** 点弹窗外区域或取消，**Then** 弹窗关闭、数据未删、滑动行复位收起

---

### User Story 2 - 批量移除与长按删除二次确认 (Priority: P1)

播放队列多选模式「移除所选」（`removeSelected`）与首页订阅长按菜单「删除订阅」（`removeSub`）MUST 补二次确认弹窗；确认后才执行。现状：两处均为一键直删，批量移除可一次删多条，风险更高。

**Why this priority**: 批量操作破坏面大（一次移除 N 条队列条目/直接删订阅），与 US1 同属防误触安全需求。

**Independent Test**: 队列多选选中多条点「移除」→弹确认；订阅长按菜单点「删除」→弹确认；取消均不执行。

**Acceptance Scenarios**:

1. **Given** 队列多选模式已选中 2 条以上，**When** 点「移除所选」，**Then** 弹出二次确认弹窗；确认后移除、取消保留
2. **Given** 首页订阅长按菜单打开，**When** 点「删除订阅」，**Then** 弹出二次确认弹窗；确认后删除、取消保留

---

### User Story 3 - 「清理已播」语义修正（修复倒序清错）(Priority: P1)

播放队列「清理已播」按钮 MUST 移除所有**已听完**条目（判定与播放模式无关：已听完 = 播放历史中该条目 `progress === -1`，即 `playedSet` 语义），当前播放条目 MUST NOT 被清理。现状 bug：`clearPlayedItems` 固定移除 `[0, currentIndex)` 前缀——正序模式下恰好近似成立，倒序（REVERSE）模式下播放方向相反、已播条目位于 `currentIndex` 之后，清理删错条目。

**Why this priority**: 功能性 bug——倒序模式清理会删掉未播条目、保留已播条目，数据操作方向完全错误。

**Independent Test**: 倒序模式播放数集后点「清理已播」→仅已听完条目被移除，未播条目（含当前播放）保留；正序模式行为一致。

**Acceptance Scenarios**:

1. **Given** 倒序模式播放到第 3 集（第 1、2 集已听完），**When** 点「清理已播」，**Then** 仅第 1、2 集被移除，当前第 3 集与其后条目保留
2. **Given** 正序模式播放到第 2 集，**When** 点「清理已播」，**Then** 已听完的第 1 集被移除，当前及未播保留
3. **Given** 队列中全部条目已听完，**When** 点「清理已播」，**Then** 清理后队列状态与「清空队列」一致（空态正常呈现，面板保留）
4. **Given** 当前播放条目已听完（播完未切歌边界），**When** 点「清理已播」，**Then** 当前播放条目保留不中断

---

### User Story 4 - 当前播放条目高亮边框跟随修复 (Priority: P1)

播放队列/播放历史中当前播放条目的封面高亮边框 MUST 跟随播放切歌实时变化（切歌后新条目高亮、旧条目取消），边框颜色 MUST 为主题色 `accentColor`（现状为 `primary_color`）。现状根因：`CoverThumb.highlight` 是普通成员变量（非 `@Prop`），父组件切歌后传入新值组件不刷新，高亮停留在首次渲染值。

**Why this priority**: 功能性 bug——高亮标记指向错误条目，误导用户当前播放位置。

**Independent Test**: 队列中切歌→新当前条目封面出现主题色边框、旧条目边框消失。

**Acceptance Scenarios**:

1. **Given** 队列面板打开且某条目高亮，**When** 播放切到另一条目，**Then** 高亮边框移动到新条目（旧条目取消）
2. **Given** 任意高亮态封面，**When** 观察，**Then** 边框颜色为主题色 accentColor

---

### User Story 5 - 系统返回完整分层修复 (Priority: P1)

四个返回处理点 MUST 统一「先关队列 → 再关浮层」关闭序列：①抽取公共关闭序列助手（一处定义）；②`Index.onBackPress` 换用助手；③`SettingsPage.onBackPressed` 头部补队列分支（现状缺口：队列开着时返回直接关浮层/历史面板，`AS_SHOW_QUEUE_SHEET` 残留 true）；④`SourcePage`/`LogPage` 补 `onBackPressed`（现状整段缺失：返回直接 pop 页面，浮层/队列原样残留）。队列分支 MUST 保持多选优先退出语义（v0.3 US7）；页面私有面板（设置页音质面板/历史面板）在助手处理完后由各自 onBackPressed 继续处理；助手处理完返回 false 时放行 Navigation 默认 pop。

**Why this priority**: 功能性 bug 族——非首页（源页/日志页/设置页深层链路）按系统返回分层错乱、状态残留，同一族缺口已在三处独立复现。

**Independent Test**: 源页点胶囊开浮层→开队列→按返回→仅队列关闭；再按→浮层关闭；再按→pop 回首页。日志页同链路。设置页经播放历史重播开浮层→开队列→按返回→仅队列关闭。

**Acceptance Scenarios**:

1. **Given** 订阅源页且播放浮层+队列面板均开，**When** 按系统返回，**Then** 首次仅关队列面板（浮层保留），再按关浮层，再按 pop 回首页
2. **Given** 日志页且播放浮层+队列面板均开，**When** 按系统返回，**Then** 分层同上（队列→浮层→pop）
3. **Given** 设置页经播放历史重播打开浮层再开队列，**When** 按系统返回，**Then** 首次仅关队列（修复缺口），后续分层同现有 US4 顺序
4. **Given** 队列面板处于多选模式（任意页面），**When** 按系统返回，**Then** 优先退出多选（面板保留），行为与首页现状一致
5. **Given** 设置页音质面板打开，**When** 按系统返回，**Then** 音质面板关闭、设置页保留（现有行为不回归）

---

### User Story 6 - 删除条目补位动画 (Priority: P2)

队列/历史/订阅列表删除条目后，下方条目 MUST 平滑补位（现状：`LazyForEach`/`List` 增量删除瞬间硬跳，无过渡）。动画具体技术方案（`animateTo` 包裹增量删除 vs 其他）Phase 2 查证后定。

**Why this priority**: 视觉平滑度优化，不影响功能正确性。

**Independent Test**: 队列删除中间某条→下方条目平滑上移补位，无瞬间跳变。

**Acceptance Scenarios**:

1. **Given** 队列面板打开，**When** 删除中间条目（确认后），**Then** 下方条目动画上移补位
2. **Given** 设置页播放历史，**When** 删除中间条目，**Then** 同上平滑补位
3. **Given** 首页订阅列表，**When** 删除某订阅，**Then** 同上平滑补位

---

### User Story 7 - 播放列表已播条目 ✓ 标记 (Priority: P2)

播放队列（QueueSheet）列表条目 MUST 对已听完条目显示 ✓ 标记（数据源与 SourcePage 一致：播放历史 `progress === -1` 即 `playedSet` 语义），未听完条目无标记。标记视觉样式与订阅源页 ✓（`checkmark_circle` success_green）一致。

**Why this priority**: 视觉信息增强，配合 US3「清理已播」让用户预判哪些条目会被清理。

**Independent Test**: 播放完一集后打开队列→该条目带 ✓；未播条目无 ✓。

**Acceptance Scenarios**:

1. **Given** 队列中存在已听完条目，**When** 打开队列面板，**Then** 已听完条目显示 ✓ 标记
2. **Given** 某条目播放中未听完，**When** 打开队列面板，**Then** 该条目无 ✓ 标记
3. **Given** 当前播放条目，**When** 观察，**Then** 当前条目呈现高亮（US4）且未听完时无 ✓

---

### User Story 8 - 清空队列自动关两层 (Priority: P2)

播放队列点「清空队列」确认后，MUST 自动关闭队列面板，随后 MUST 自动关闭播放浮层（层级由深到浅）。现状：清空后两层均保持打开，用户面对空队列面板需再手动关两层。首页实例（Index 层队列）清空后同样适用：关面板即可（首页无浮层叠加时不多关）。

**Why this priority**: 操作路径优化，减少清空后的多余手动关闭步骤。

**Independent Test**: 播放浮层内开队列→清空→队列面板滑出关闭→播放浮层随后收起。

**Acceptance Scenarios**:

1. **Given** 播放浮层内打开队列面板，**When** 点「清空队列」并确认，**Then** 队列面板先自动关闭（滑出动画），播放浮层随后自动收起
2. **Given** 首页直接打开队列面板（无浮层），**When** 清空并确认，**Then** 队列面板自动关闭，首页保留

---

### User Story 9 - 播放页封面占位换耳机图标 (Priority: P2)

播放页空态（无当前播放）的封面占位符号 ♪ MUST 换为耳机图标（`sys.symbol.headphones`，已确认存在于 sysResource）。仅改播放页封面占位这一处。

**Why this priority**: 纯视觉语义优化。

**Independent Test**: 清空队列/无播放时打开播放页→封面占位为耳机图标。

**Acceptance Scenarios**:

1. **Given** 无当前播放条目，**When** 打开播放浮层，**Then** 封面占位显示耳机图标（不再是 ♪）

---

### Edge Cases

- **SwipeActionItem FAQ 已知行为**（SDK list_item.d.ts + FAQ 核实）：①声明 `onAction` 后删除区可撑满整行宽（faqs-arkui-1121）——恰为期望的文件管理器式效果，接受；②多行同时滑开互斥收起（faqs-arkui-1556）——共享一个进度状态即可，接受
- 确认弹窗打开期间列表不可重复触发删除（弹窗模态遮罩天然阻断）；取消后滑动行复位收起
- 三处列表实现不同：设置页历史为 sheet 内 `List`、队列为 `LazyForEach`+`PlaylistDataSource`、首页订阅为 `LazyForEach`——补位动画方案须三者各自适配（Phase 2 查证）
- US3 清理后队列为空：与「清空队列」空态呈现一致；清理含「当前播放已听完」边界时当前条目必须保留
- US3/US7 数据源：`playedSet` 取自 `AppStore.loadPlayHistoryFile()`（`progress === -1` 哨兵 = 已听完，`markCurrentHistoryCompleted` 写入）；队列数据源须能访问该集合（Phase 2 定传递路径）
- US5 助手返回 false 时 NavDestination 默认 pop；Index 换用助手后既有 `selectMode` 优先、滑出动画路径（`queueClose` 句柄）零回归
- US5 SourcePage/LogPage 无页面私有面板，助手处理完直接放行 pop
- US4 CoverThumb 为免迁 V1 组件（`@Prop`-only），补 `@Prop` 不改变其代际
- US8 首页实例清空：仅关队列面板；浮层内实例清空：关面板+关浮层，动画走既有滑出/收起路径
- E 项销项：屏幕常亮无代码改动（系统层开发者选项「不锁定屏幕」，拔线重测验证）

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: 设置页播放历史、播放队列、首页订阅三处左滑删除 MUST 展示静态红色垃圾桶删除按钮；点按按钮或滑动超过阈值（`actionAreaDistance`）后松手 MUST 弹出二次确认弹窗；仅确认后执行删除，取消不删且行复位
- **FR-002**: 队列多选「移除所选」与首页订阅长按菜单「删除订阅」MUST 弹二次确认；确认后才执行
- **FR-003**: 「清理已播」MUST 移除所有已听完条目（播放历史 `progress === -1`），与播放模式无关；当前播放条目 MUST 保留
- **FR-004**: CoverThumb 高亮 MUST 实时跟随当前播放条目（`highlight` 响应父组件更新）；边框色 MUST 为 `accentColor`
- **FR-005**: 四个返回处理点（Index.onBackPress / SettingsPage / SourcePage / LogPage onBackPressed）MUST 统一调用公共「先关队列（多选优先退出）→ 再关浮层」关闭序列助手；页面私有面板在助手之后各自处理；助手返回 false 放行默认 pop
- **FR-006**: 三处列表删除条目后下方条目 MUST 平滑补位（技术方案 Phase 2 定）
- **FR-007**: 播放队列已听完条目 MUST 显示 ✓ 标记（`checkmark_circle` success_green，与订阅源页一致）
- **FR-008**: 清空队列确认后 MUST 自动关闭队列面板（滑出动画）；播放浮层内实例随后 MUST 自动收起浮层；首页实例仅关面板
- **FR-009**: 播放页空态封面占位 MUST 换为 `sys.symbol.headphones` 耳机图标

### Key Entities

无新增数据实体。涉及现有：`PlaylistDataSource`（队列增量删除）、`playedSet` 语义（播放历史 `progress === -1`，跨 SourcePage/QueueSheet 复用）、`CoverThumb.highlight`（`@Prop` 化）、`AS_SHOW_QUEUE_SHEET`/`AS_SHOW_PLAYER_OVERLAY`/`AS_PLAYLIST_SELECT_MODE`（返回分层序列）、`SwipeActionItem` 参数（`actionAreaDistance`/`onAction`）。

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 全部 5 个删除入口（3 左滑 + 多选移除 + 长按删除）100% 经二次确认弹窗才执行删除；取消路径零误删
- **SC-002**: 倒序与正序模式各执行一次「清理已播」，删除集合均恰好等于已听完集（当前播放条目零误删）
- **SC-003**: 连续切歌 5 次，每次高亮边框即时跟随当前条目，零残留/零滞后
- **SC-004**: 源页/日志页/设置页三链路返回各测一轮，分层顺序 100% 为 队列→浮层→页面面板→pop，无状态残留（`AS_SHOW_QUEUE_SHEET`/`AS_SHOW_PLAYER_OVERLAY` 关闭后为 false）
- **SC-005**: 三处列表删除后补位均为动画过渡，无瞬间跳变
- **SC-006**: `devecocli build` 通过（验证范围 Phase 3 定，默认 build-only）

## Assumptions

- 垃圾桶开盖动画放弃（无现成组件，用户确认），静态红色图标
- 滑动阈值用 `SwipeActionItem.actionAreaDistance` 默认 56vp 起步，真机手感不合适再调
- ✓ 标记与「清理已播」共用 playedSet 数据源；队列侧取数路径 Phase 2 设计
- 补位动画技术方案（`animateTo` 包裹增量删除可行性）Phase 2 查证后定
- US8 清空后关浮层的判定：清空动作发生时浮层若打开则收起；实现走既有关闭路径（`AS_SHOW_QUEUE_SHEET`/`AS_SHOW_PLAYER_OVERLAY` 置 false + 既有动画）
- E 项（屏幕常亮）销项无代码改动

## Open Questions

- 无（十项已全部澄清；补位动画方案与队列侧 playedSet 取数路径为 Phase 2 设计议题，非需求歧义）
