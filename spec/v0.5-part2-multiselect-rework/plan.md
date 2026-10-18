# Implementation Plan: 多选交互重构（订阅源 + 全局多选进出动画）

**Input**: Feature specification from `spec/v0.5-part2-multiselect-rework/spec.md`

## Summary

订阅源（`SourcePage`）多选交互重构对齐鸿蒙文件管理器：长按剧集行（预选）+ 顶栏常驻图标按钮双入口（页头按钮移除）；多选态顶栏整行替换为「取消 + 已选 N 项」；底部操作条重构为左「标记已看完」（二次确认后批量写本地播放历史 progress=-1）/ 中「选择至此」（QQ 锚点区间）/ 右「加入队列 (N)」三操作位；全选移除；进入/退出多选全链路过渡动画（animateTo 驱动，方向互逆）。播放队列（`QueueSheet`）与播放历史（`HistorySheet`）补齐同款进出动画，交互语义零变化。

## Technical Context

**Language/Version**: ArkTS（ArkTS 严格模式，API 26 基线，compatibleSdkVersion 26.0.0）  
**Primary Dependencies**: ArkUI（@ComponentV2 全量）、@kit.ArkUI（animateTo/TransitionEffect/promptAction）  
**State Management**: 沿用现状——页面/组件 V2（`@Local`/`@Param`/`@Monitor`），`PlayerController` 零装饰器纯类（手动 `subscribe`/`emitUi` + 版本计数）；多选状态维持 SourcePage struct 内 `@Local`（顶栏 `sourceTitleBuilder` 为 struct 内 `@Builder`，直接访问 `this.*`，无需 AppStorageV2 迁移）  
**Storage**: 播放历史 `AppStore.savePlayHistoryFile`（preferences 持久化，复合键 bvid:page，progress=-1 即已听完）  
**Testing**: 无测试套件；验证走 arkts_check + devecocli build + 真机目检  
**Target Platform**: HarmonyOS NEXT（手机/平板）  
**Project Type**: 单模块 HarmonyOS 应用（既有项目增量改动）  
**Performance Goals**: 多选进出动画 60fps；长列表（LazyForEach）行内动画不卡顿  
**Constraints**: 代码零注释原则（机制注释除外）；数值一律 Constants 令牌；禁 `any`/`unknown`/`as` 断言（ArkTS 严格模式）；动画中断终态以状态为准  
**Scale/Scope**: 3 个改动文件为主（SourcePage/QueueSheet/HistorySheet）+ PlayerController/Constants 增量

## Project Structure

### Documentation (this feature)

```text
spec/v0.5-part2-multiselect-rework/
├── spec.md              # 需求（Phase 1 已定稿）
├── plan.md              # 本文件
└── tasks.md             # Phase 3 产出
```

### Source Code (repository root)

```text
entry/src/main/ets/
├── pages/
│   └── SourcePage.ets        # US1 主战场：入口/顶栏双态/底部三操作位/区间选择/动画
├── component/
│   ├── QueueSheet.ets        # US2：行首 Checkbox 容器动画 + 头部切换过渡
│   └── HistorySheet.ets      # US2：同上
├── service/
│   ├── PlayerController.ets  # 新增 markWatched 批量标记接口（零装饰器广播模式）
│   └── Constants.ets         # 新增多选过渡动效令牌 + 标记已看完文案常量
```

**Structure Decision**: 遵循现有项目架构（service→model、pages→service/model 单向依赖，`Constants` 零业务依赖），不引入 MVVM 迁移。改动集中在 5 个既有文件，无新建文件——多选交互是纯 UI 层重构 + 1 个 controller 批量接口，拆新文件无收益。

## Complexity Tracking

（无 Constitution Check 违规——不填）

## Research & Decisions

### D1: 长按进入多选的手势方案

- **Decision**: 剧集行并行挂 `LongPressGesture`（默认 500ms）与既有 `onClick`——长按触发进入多选并预选该行，点击维持「多选态切勾选 / 常规态播放」双分支语义
- **Rationale**: `HistorySheet` 已验证同构方案（长按进多选 + 点击切换/播放并存，无手势冲突）；`SourcePage` 无左滑无拖拽，冲突面更小；ArkUI 手势系统长按触发后同一点击不再派发 onClick，无双触发风险
- **Alternatives considered**: ① `GestureGroup(GestureMode.Exclusive, ...)` 统一手势树——QueueSheet 组条目因需 Pan 拖选才用，此处无拖选，纯并行更简；② 仅顶栏按钮入口——不满足「长按预选」的文件管理器范式

### D2: 顶栏双态切换

- **Decision**: `sourceTitleBuilder` 内按 `selectMode` 条件渲染两套 Row：常规态（返回卡 + 标题 + 多选图标卡 + ··· 卡）↔ 多选态（xmark 取消卡 + 居中「已选 N 项」文字，右无元素）；两态切换包 `animateTo` 过渡
- **Rationale**: builder 是 struct 内 `@Builder` 直接访问 `this.selectMode`，无跨上下文状态共享问题；现有返回卡 onClick 已含 `selectMode → exitSelectMode` 分支（v0.5-part2 US2 落地），取消卡复用同逻辑；`···`/多选按钮在多选态直接不渲染即满足「刷新/退订不可达」
- **Alternatives considered**: ① selectMode 迁 AppStorageV2 `AS_*` 键（对齐 QueueSheet）——仅当 builder 跨 struct 才需要，此处无必要，徒增全局键；② 保留 ··· 在多选态——违反 FR-002（多选中 ··· 不可达）
- **注意**: `sys.symbol.xmark` / `sys.symbol.list_checkmark`（页头现用图标迁移）实施前在 sysResource.js 核对存在性

### D3: 进出多选动画方案（US1 + US2 统一模式）

- **Decision**: 四条链路统一 `animateTo({ duration: TOKEN_SELECT_ANIM_MS, curve: Curve.EaseOut })` 包裹 `selectMode` 翻转（进出同一入口 `enterSelectMode`/`exitSelectMode`，天然互逆）：
  1. **行首勾选框**：Checkbox 容器**恒挂载**，宽度 `0 ↔ SELECT_CHECKBOX_W` + opacity `0 ↔ 1` 动画，行内容随容器宽度自然右移让位/回位（不位移 hack，是真实布局变化）
  2. **顶栏**：两套 Row 条件渲染 + `TransitionEffect`（opacity 组合）
  3. **底部操作条**：多选态条件渲染 + `TransitionEffect.move(TransitionEdge.BOTTOM).combineOpacity()` 滑入滑出
  4. **头部切换（QueueSheet/HistorySheet）**：常规头部 ↔ 多选操作行条件渲染 + 同款过渡
- **Rationale**: 恒挂载 + 宽度动画优于条件渲染 + transition——LazyForEach 滚动回收时条件渲染会销毁重建节点导致动画闪烁，恒挂载只在首次构建后做属性动画；「右移让位」用容器宽度驱动是鸿蒙文件管理器同款（内容被推开而非覆盖）；`exitSelectMode` 复用同一 animateTo 闭包翻转状态即天然反向
- **Alternatives considered**: ① 条件渲染 Checkbox + `TransitionEffect.OPACITY`——无「让位」位移，且回收重建闪烁；② 行内容 `.translate` 位移 + Checkbox 覆盖浮层——让位是假的（内容与勾选框重叠期可点击区域错位）
- **QueueSheet/HistorySheet 适配**: 行首 Checkbox 现为条件渲染，改为同款恒挂载容器；头部切换包 animateTo。既有「进入多选收起已滑出行」「面板关闭退多选」逻辑不动，仅动画层叠加

### D4: 「选择至此」区间选择状态机

- **Decision**: SourcePage struct 内新增 `@Local rangeSelecting: boolean` 与 `@Local anchorBvid: string`：
  - 勾选动作（`toggleSelect` 勾上时）更新 `anchorBvid`；取消勾选不动锚点
  - 点「选择至此」：`rangeSelecting = true`（按钮高亮态）；再点：`rangeSelecting = false`（已选集不变）
  - `rangeSelecting` 中点行：取 episodes 中 anchor 与终点行的 index（按 bvid 查找，容忍触底加载后数组增长），`min↔max` 区间内全部 bvid 并入 `selectedKeys`（新建 Set 整体换引用），`rangeSelecting = false`，`anchorBvid = 终点行 bvid`
  - 进入/退出多选、入队完成、标记完成时全部重置
- **Rationale**: 锚点与选中集解耦（取消勾选不清锚点）避免「刚取消的行丢锚点」；index 按 bvid 动态查找而非缓存下标，触底加载新行后区间计算天然正确；整体换 Set 引用沿用 v0.5-part2 已验证的 V2 观测模式
- **Alternatives considered**: ① 锚点也存 index——数组增长/重排后失效；② 区间选择态中点行仍切换单个勾选——歧义（终点指定与取消勾选混淆），spec 已定为「仅指定终点」

### D5: 标记已看完——PlayerController 批量接口

- **Decision**: `PlayerController` 新增 `markWatched(items: BiliVideo[]): void`（零装饰器广播模式）：遍历 items，`isPlayed(bvid)` 命中则跳过（幂等）；未命中则查该 `bvid:page` 复合键历史条目——有则置 `progress = -1`，无则 `PlayHistoryItem.fromVideo(video, resolveSourceType(video), now)` 新建后置 `progress = -1` 并 unshift；全部处理完 `HISTORY_MAX` 截断 → `savePlayHistoryFile` → `playHistoryVersion++` → `emitUi()`
- **Rationale**: 入参传 `BiliVideo[]` 而非裸 bvid 数组——新建历史条目需要 title/cover/ownerName 元数据，页面 episodes 中现成；幂等跳过防重复条目；批量只落一次盘（循环内不写）；`playHistoryVersion++` 令消费方 syncFrom 感知，SourcePage 行上已播标记即时刷新
- **Alternatives considered**: ① 页面层直接改 `controller.playHistory` 数组——绕过封装破坏版本计数协议；② 逐条调既有 upsert（progress=0 起播语义）再置 -1——两次写入且语义错位（upsert 会把 viewAt 顶到当下、progress 归 0）
- **sourceType**: 复用 `PlayerController.resolveSourceType(video)`（SOURCE_UP/SEASON/FAVORITE/LOCAL 既有分型）

### D6: 底部三操作位布局

- **Decision**: 多选态底部单容器 Row（card 背景、圆角，`margin.bottom = MINI_PLAYER_CLEARANCE + navBarHeight` 沿用现避让计算）内三操作位：左「标记已看完」/ 中「选择至此」/ 右「加入队列 (N)」，spaceBetween 分布；三按钮共享 `selectedKeys.size === 0` 禁用态（opacity 降档 + enabled false）；整条条件渲染 + `TransitionEffect.move(TransitionEdge.BOTTOM)` 滑入滑出
- **Rationale**: 三操作位天然构成一条操作栏，「左下/中间/右下」即 Row 内三节点 spaceBetween；现 `selectActionBar`（全选/加入队列/取消）整体替换，避让计算经实践验证直接沿用；「取消」职责已在顶栏（返回位），底部不再放取消
- **Alternatives considered**: ① 三个独立浮动按钮分别 transition——对齐/避让要算三次，视觉碎；② 保留全宽操作条原样式只换按钮——用户明确的三位置布局即操作条形态，但按钮全换

### D7: 二次确认与 toast 文案

- **Decision**: 「标记已看完」沿用项目现有二次确认弹窗模式（与队列清空/移除所选同款，`AlertDialog` 体系）；新增 Constants：`DIALOG_MARK_WATCHED_TITLE`（「标记已看完」）、`DIALOG_MARK_WATCHED_MSG`（「确定标记 N 集为已看完吗？」，N 运行时替换沿用既有动态文案模式）、`TOAST_MARK_WATCHED`（「已标记 N 集为已看完」）；确认后调 `markWatched` → toast → `exitSelectMode`
- **Rationale**: 弹窗/toast 走既有模式零新组件；文案集中 Constants 符合唯一真相源；计数 N=选中数（含已播条目，幂等重复无副作用，spec Assumptions 已定）
- **Alternatives considered**: 无确认直接标——用户已选「带二次确认」

### D8: Constants 增量

- **Decision**: 新增 `TOKEN_SELECT_ANIM_MS = 300`（多选进出过渡时长，Curve.EaseOut）；标记已看完文案三则（D7）；多选 Checkbox 容器宽度复用既有 Checkbox 尺寸常量（Constants 既有「多选行首 Checkbox 尺寸」），如需间距用现有 TOKEN_SPACE_* 档
- **Rationale**: 300ms/EaseOut 是项目既有过渡事实标准（AddSubscriptionSheet 层级转场、PlayerOverlay 按压回弹同档）；提升为令牌避免三处多选各写各的时长
- **Alternatives considered**: 各处字面量 300——违反令牌规范

### D9: 系统返回动画退多选——BackHandler 句柄注册【追加】

- **Decision**: BackHandler 新增 `registerQueueSelectExit` / `registerHistorySelectExit` 模块级句柄（对齐既有 `queueCloseHandle`/`settingsBackHandle` 注册模式）；QueueSheet/HistorySheet `aboutToAppear` 注册（`() => this.exitSelectModeAnimated()`），`aboutToDisappear` 注销；`dismissOverlaysForBack` 队列/历史多选分支优先调句柄，无句柄回退直翻
- **Rationale**: BackHandler 纯模块无 UIContext 不能 `animateTo`，动画必须发生在组件上下文——句柄注册是项目既有解法（closeHandle 先例）；回退直翻保证异常时序不崩溃
- **Alternatives considered**: BackHandler 内取全局 UIContext 包 animateTo——服务层持 UI 上下文违反分层

### D10: 长按守卫 LongPressGuard【追加】

- **Decision**: `LongPressGuard` 纯类（置位 / 查询并消费 / 重置）三处统一挂：长按 `onAction` 置位；行 `onClick` 先查守卫，命中即吞掉本次点击（不切勾选）并复位；组件行 `onTouch` 的 Down 分支重置守卫
- **Rationale**: 队列 Sequence 组（长按→Pan 拖选）整组失败时 ArkUI 回退派发 onClick，致松手取消预选；守卫堵回退点击且保留拖选的 Sequence 结构（Pan 单独绑定会与列表滚动冲突，不可拆）；历史/订阅源为裸长按本无回退点击，统一挂守卫为代码一致性（无副作用）
- **Alternatives considered**: 改手势树（长按单独 `.gesture` + Pan 并行）——Pan 并行绑定劫持列表滚动，不可行

### D11: 共享抽取边界【追加】

- **Decision**:
  - 新建 `entry/src/main/ets/component/SelectCheckbox.ets`（`@ComponentV2` 共用组件）：恒挂载容器宽度 `0↔SELECT_CHECKBOX_W` + opacity `0↔1`、Checkbox 统一样式（accent 内部 `connectStr` 自取）、`@Param active/selected` + `@Event onChange`——收敛三处全部勾选框挂载点
  - 新建 `entry/src/main/ets/service/SelectLogic.ets`：`toggle`（Set 引用替换勾选切换）+ `LongPressGuard` 纯类（D10）
  - 队列/历史选中集合数组→`Set<string>` 引用替换（对齐订阅源既有模式）
  - 三处命名对齐：`enterSelectMode`/`exitSelectMode(Animated)`/`toggleSelect`/`selectedKeys`
- **保留差异（不合并）**: 状态载体（订阅源页内 `@Local` boolean vs 队列/历史 `BoolState`——AS_* 键跨组件共享，BackHandler/Index 读键需要）；订阅源区间选择（rangeSelecting/anchorBvid）；队列拖选（Sequence+Pan+下标换算）；数据层（队列 LazyForEach+多P 三行型 vs 历史 ForEach+bvid 聚合行）
- **Rationale**: 三处同构的只有多选骨架（进出动画/勾选框/守卫/命名），数据层是两个领域（队列=播放条目多P 分组、历史=bvid 聚合行），强行合并是伪统一
- **Alternatives considered**: 泛型 `MultiSelectSession` 大一统会话类——需桥接三种状态载体（@Local/BoolState），抽象成本大于三处各自维护

### D12: SourcePage 两处修复【追加】

- **Decision**: ① `onBackPressed` 调序——先 `dismissOverlaysForBack()`（上层队列/历史多选与面板先退，返回 true 即消化），返回 false 再处理自身 `selectMode`（动画退出），最后放行默认 pop；② `loadPlayedSet` 改读 `this.controller.playHistory`（内存真相源），不再读 `AppStore.loadPlayHistoryFile()` 落盘文件
- **Rationale**: ① 层序契约（高层物理覆盖低层，返回链自上而下逐层关闭）被「先查自身多选」打破；② `markWatched` 经 `savePlayHistoryFileAsync` 异步落盘，`loadPlayedSet` 同步读文件存在竞态——读到旧文件致已播标记不出现；`controller.playHistory` 是播放历史内存真相源（init 同步加载，markWatched 同步更新）
- **Alternatives considered**: ① 仅调 Index.onBackPress——NavDestination 在栈顶时其 onBackPressed 优先于页级 onBackPress，SourcePage 内调序是正确修法；② loadPlayedSet 后补一次延迟重读——治标不治本，时序依旧脆弱

## Research & Decisions（追加2：二轮目检改进 D13-D21）

**Input**: spec 追加2 US4 / FR-013~018。改动面：`SelectCheckbox.ets`（gap 参数化）、`SelectLogic.ets`（扫选会话 + 边缘自动滚动器）、`SourcePage.ets`（拖选/移除选择至此/独立悬浮按钮/悬浮化）、`QueueSheet.ets` / `HistorySheet.ets`（拖选接入）、`HomePage.ets`（悬浮化）、`CoverThumb.ets`（禁拖）、`Constants.ets`（扫选令牌）。

### D13: SelectCheckbox 间距对称化——gap 参数化【追加2】

- **Decision**: `SelectCheckbox` 新增普通成员 `gap: number`（默认 `TOKEN_SPACE_S`，向后兼容），容器宽 `active ? SELECT_CHECKBOX_SIZE + gap : 0`；三处调用点按各自行左内边距传同值——SourcePage 传 `TOKEN_SPACE_M`（行 padding 12）、QueueSheet/HistorySheet 传 `TOKEN_SPACE_L`（行 padding 16），使「行卡片左缘→勾选框」=「勾选框→封面」两侧空白对称（现状 gap 固定 S=8 < 行左内边距 12/16，即目检「紧贴封面、两侧空白不一致」根因）
- **Rationale**: 两侧留白的左值=行内边距（场景各异），共享组件无法单值兜底；gap 由场景注入后左右天然相等，且顺带扩宽拖选热区（容器 32/36vp）
- **Alternatives considered**: ① 组件内固定 gap=M——队列/历史行内边距是 L，左右差 4vp 不对称；② 统一三处行内边距——动三处布局只为对称，扩散面大

### D14: 复选框区拖选——手势挂载与方向性扫选状态机【追加2】

- **Decision**: 手势挂三处行内 `SelectCheckbox` 外层（ArkUI 自定义组件可链式挂通用手势；若实例链式 `.gesture` 在 V2 组件上不生效则外包一层 Column 承载，二选一实施时定）：`PanGesture({ fingers: 1, direction: PanDirection.Vertical })`，仅多选态（容器宽 0 时无热区，常规态天然不可触发）。扫选状态机三处共享 `SelectLogic.SweepSession` 纯类：`onActionStart` 采样起点行选中态锁定模式（未选中→加扫，已选中→减扫，FR-014 方向性语义），记录 `startGlobalY`/`startScrollOffset`，并把锁定模式应用到起点行；`onActionUpdate` 按 D15 换算目标行，把起点→目标间全部行按锁定模式应用（加扫并入 Set / 减扫从 Set 删，整体换引用）；`onActionEnd/Cancel` 停边缘滚动器、清会话。加/减共用同一「区间应用」入口，模式仅是 add/remove 分支
- **Rationale**: 起点行下标由手势宿主行天然给出（无需绝对 Y→行换算），换算只需「相对起点位移」；模式按下时锁定避免同一拖动混合加减（鸿蒙文件管理器同款）；Set 引用替换沿用既有 V2 观测模式；点按勾选框切换与拖选不冲突（Pan 默认 5vp 位移阈值内为点按，走 Checkbox onChange；拖动取消 click）
- **Alternatives considered**: ① 左缘全高 lane 浮层统一承载手势——需绝对 Y→行换算（头部/内边距/变高行全部入算），脆弱；② 每行 onTouch 自报告——触摸流被起点组件捕获，滑过邻行无事件
- **手势冲突核验**: lane Pan（纵向）在多选态从子组件胜出（对齐 QueueSheet 既有拖选手势仲裁结论），列表滚动不被劫持（常规态 lane 宽 0）；行长按进多选、行 onClick 切换、Checkbox onChange 均不受影响（长按/点按/拖动三态互斥）

### D15: 扫选位移→目标行换算（等高步长 / 队列 estHeight 累积）【追加2】

- **Decision**: 目标行 = 起点行 + 按「位移增量」换算的行距。位移增量 = `(globalY − startGlobalY) + (currentOffset − startScrollOffset)`（scroller.currentOffset().yOffset，覆盖边缘自动滚动带来的内容位移）。
  - **SourcePage（等高）**: 步长 = `EPISODE_THUMB_H(68) + 2×TOKEN_SPACE_10(20) + List space TOKEN_SPACE_XS(4)` = 92vp，目标 index = `startIndex + round(位移/步长)`，clamp 到已加载范围
  - **HistorySheet（等高）**: 步长 = `COVER_THUMB 行高 44 + 2×TOKEN_SPACE_10(20) + space 0` = 64vp，同上
  - **QueueSheet（变高）**: 复用既有 `targetEntryIndex` estHeight 累积换算（起点 entry index + 位移增量入参），分P 窄行按所属 entry 的 estHeight 跨度自然命中（FR-014 分P 归组语义）
- **Rationale**: 相对换算只需步长/estHeight，头部高度、List 内边距、触底新增行全部不影响正确性（索引稳定）；队列 estHeight 模式经 T020 实践验证；等高步长由既有令牌推导不新增常量
- **Alternatives considered**: 每行 onAreaChange 上报全局位置建映射——LazyForEach 回收重建频繁，成本大于收益
- **校准风险**: 等高步长含隐式「行高=内容高」假设，实施时真机/模拟器核对实际行高（若文字列高于封面致行高≠推导值，步长改由实测行高令牌承载）

### D16: 边缘自动滚动——EdgeAutoScroller 纯类【追加2】

- **Decision**: `SelectLogic` 新增 `EdgeAutoScroller` 纯类：`start(scroller, 方向, 每帧回调)` / `stop()`，内部 `setInterval(SELECT_SWEEP_TICK_MS)` 每 tick `scroller.scrollBy(0, ±SELECT_SWEEP_SPEED)` 后回调场景（场景重算位移增量并应用扫选，含新滚出行的区间应用）；场景在 `onActionUpdate` 判定 globalY 进入上/下 `SELECT_SWEEP_EDGE_ZONE` 边缘带时启动对应方向、离开边缘带或 `onActionEnd/Cancel` 时 `stop()`；SourcePage 触底时 `scroller.scrollBy` 照常触发 `onReachEnd` → 加载更早（新行追加后索引稳定，继续拖选天然覆盖）
- **Rationale**: 按住不动时 Pan 无 update 事件，自动滚动必须自带时钟；scroller.scrollBy 走列表既有滚动管线（onReachEnd/边缘物理全部继承）；纯类不持 UIContext，符合 BackHandler 同款分层约束
- **Alternatives considered**: 依赖 onActionUpdate 驱动滚动——按住不动即停滚，不满足「拖到边缘持续滚动」；animateTo 定长滚动——不可持续变速，且与扫选中断风险
- **速度策略**: 单速档（令牌常量）首发；不做按压深度加速（ponytail: 天花板——需要时把速度改 f(globalY 距边缘距离) 的线性/分段函数即可，接口不变）

### D17: 「选择至此」移除清单【追加2】

- **Decision**: SourcePage 整体删除：`@Local rangeSelecting` / `@Local anchorBvid` 字段、`toggleRangeSelecting()` / `completeRangeSelection()` 方法、底部操作条中「选择至此」按钮及其高亮态、enter/exit/入队/标记完成时对区间态的 4 处重置语句；`toggleSelect` 中锚点更新语句删除（Set 切换逻辑保留走 SelectLogic.toggle）。US1 验收 4/5 与 FR-003 已在 spec 划线标注由 FR-014 取代
- **Rationale**: 区间选择状态机被方向性扫选完全取代，残留即死代码；锚点仅服务区间语义，单行勾选无需锚点
- **Alternatives considered**: 保留状态机仅隐藏按钮——死代码违反 ponytail

### D18: 多选底部操作拆独立悬浮按钮【追加2】

- **Decision**: SourcePage `selectActionBar` 整条卡片替换为：不可见全宽 Row（`justifyContent(FlexAlign.SpaceBetween)`，Stack Bottom 对齐内）承载两枚独立悬浮胶囊——左「标记已看完」（`card_background` 底 + `text_primary` 字）、右「加入队列 (N)」（accent 底 + `fg_on_dark` 字、Medium，主按钮定位）；两枚共享 `radius TOKEN_RADIUS_XXL` + 既有阴影档 + 左右页边距 `TOKEN_SPACE_M` + `margin.bottom = MINI_PLAYER_CLEARANCE + navBarHeight`（避让胶囊与导航区）；`selectedKeys.size === 0` 时共享禁用（opacity 降档 + enabled false）；各自挂 `TransitionEffect.move(TransitionEdge.BOTTOM).combine(TransitionEffect.OPACITY)`，随 selectMode 同一 animateTo 滑入滑出（互逆）
- **Rationale**: 不可见 wrapper 保持左右锚定布局简单（免绝对定位），视觉上两枚完全独立；accent 底主按钮对齐「加入队列」主操作定位；避让与过渡计算沿用已验证模式零新机制
- **Alternatives considered**: ① 两按钮各自 `.position()` 绝对定位——对齐/避让计算两份；② 保留整条卡片仅换内容——用户明确要「悬浮的独立按钮」

### D19: MiniPlayer 悬浮化——List padding 换 contentEndOffset【追加2】

- **Decision**: HomePage 订阅列表与 SourcePage 剧集列表的 `padding.bottom`（`MINI_PLAYER_CLEARANCE + navBarHeight`）移除，改挂 `.contentEndOffset(MINI_PLAYER_CLEARANCE + navBarHeight)`（Scrollable 通用属性，API 12+，本项目 API 26 满足）：列表视口延伸至屏底，内容滚动时从胶囊下方穿过（毛玻璃透出），滚到底最后一条停于 offset 区上沿——完整露出在胶囊上方，加载指示/「没有更多了」同样不被遮挡。左右/顶部 padding 保留。设置页维持现状（用户决策）
- **Rationale**: ArkUI List 的 padding 是内容裁剪边界——底部 padding 区不渲染滚动内容（现状「内容不能从胶囊下划过」根因）；`contentEndOffset` 是官方「末端预留且内容可在该区滚动」的正解，语义与 FR-015 一一对应
- **Alternatives considered**: 列表尾部追加透明占位 ListItem（高度=避让值）——同样可达「末条完整露出 + 内容下穿」，且不依赖 contentEndOffset；作为该属性在本机 SDK 不可用时的回退方案（实施首步核对本机 `.d.ts`，两者等价优先 contentEndOffset）
- **联动核对**: SourcePage 多选悬浮按钮（D18）bottom 避让值不变（胶囊实际位置未动）；HomePage 空态（无 List）不受影响；GlassSheet 面板在胶囊上层不受影响

### D20: CoverThumb 封面禁拖拽【追加2】

- **Decision**: `CoverThumb` 图片分支 `Image` 挂 `.draggable(false)`（鸿蒙 Image 默认 draggable=true，长按拖动触发系统拖拽/中转站，即目检根因）；占位分支（无封面 SymbolGlyph）无需处理。若真机长按仍出系统菜单，补 `.copyOption(CopyOptions.None)`（实施时真机确认，预期不需要）
- **Rationale**: 根因在共享组件层修一次全应用生效（FR-017）；订阅源详情页头大封面与剧集行/队列/历史/迷你播放条封面同步禁拖；行长按进多选等手势挂在行容器不受影响
- **Alternatives considered**: 仅 SourcePage 页头封面单点禁拖——治标，其余封面仍会误触发

### D21: Constants 增量（追加2）【追加2】

- **Decision**: 新增扫选令牌三枚：`SELECT_SWEEP_EDGE_ZONE = 48`（上下边缘带高度 vp）、`SELECT_SWEEP_SPEED = 10`（每 tick 滚动 vp）、`SELECT_SWEEP_TICK_MS = 16`（滚动时钟周期）；等高步长不新增常量（由 EPISODE_THUMB_H / TOKEN_SPACE_* 既有令牌在使用处推导，D15）；悬浮按钮复用既有 radius/阴影/色彩令牌
- **Rationale**: 三枚是扫选新机制的独立参数，须令牌化；步长是既有布局令牌的派生值，再立常量即重复真相源
- **Alternatives considered**: 步长也立令牌——违反「Constants 零重复」精神，派生即可



## Data Model

### 多选会话（SourcePage struct 内瞬态，不持久化；追加2 后终态）

| 字段 | 类型 | 说明 |
|------|------|------|
| `selectMode` | `@Local boolean` | 既有；进出经 animateTo 入口翻转 |
| `selectedKeys` | `@Local Set<string>` | 既有；不可变整体换引用更新 |
| `sweepSession` | `SelectLogic.SweepSession \| null` | 追加2；拖选进行时会话（模式锁定/起点采样），`null`=未在拖选 |
| `edgeScroller` | `SelectLogic.EdgeAutoScroller` | 追加2；边缘自动滚动器实例（stop 幂等） |

（追加2 移除：`rangeSelecting` / `anchorBvid`——由 D17 删除，扫选会话取代区间状态机）

### 播放历史写入（既有 PlayHistoryItem，本轮零模型变更）

- 标记已看完：`progress = -1`（已听完哨兵），复合键 `bvid:page` 去重，`HISTORY_MAX` 截断
- `isPlayed(bvid)` 语义不变（bvid 级，任一分P -1 即已播）

## Contracts & Interfaces

### PlayerController 新增接口

```text
markWatched(items: BiliVideo[]): void
```

- 行为：幂等批量把 items 标记为已听完（本地播放历史 progress=-1；不向 B 站云端上报）；单次批量只落一次盘；完成后 `playHistoryVersion++` + `emitUi()`
- 前置：items 非空由调用方保证（N=0 按钮禁用）
- 幂等：`isPlayed(bvid)` 命中跳过；同复合键已有条目置 -1 不新建

### UI 契约（SourcePage，追加2 后终态）

- **剧集行**: `[Checkbox 容器(恒挂载, 宽 0↔W, opacity 0↔1)] + 封面 + 文字列`；长按=进多选+预选；点击=多选态切勾选 / 常规态播放（既有）
- **顶栏常规态**: `返回卡 | 标题 | 多选图标卡(list_checkmark) | ··· 卡`——多选卡在 `episodeCount === 0` 时不渲染
- **顶栏多选态**: `取消卡(xmark, 原 ··· 位替换返回位) | 「已选 N 项」(居中) | 空`；系统返回/取消卡均走 `exitSelectMode`
- **拖选**: 多选态在勾选框区按下拖动 = 方向性扫选（D14/D15/D16）；按下方向锁定加扫/减扫、滑过区间整体应用、边缘带自动滚动
- **底部多选操作（追加2 取代整条操作条）**: 两枚独立悬浮胶囊按钮——左「标记已看完」+ 右「加入队列 (N)」（D18；N=0 共享禁用，bottom 避让 MiniPlayer + navBar，进出滑入滑出过渡互逆）

（追加2 移除契约：「选择至此」按钮、区间选择高亮、锚点语义——D17 删除）

### UI 契约（QueueSheet / HistorySheet，追加2 后）

- 行首 Checkbox 容器恒挂载宽度/透明度动画（模式同 SourcePage D3-1）
- 头部常规行 ↔ 多选操作行切换包 animateTo + TransitionEffect
- 既有交互语义零变化（长按入口、全选/移除/删除、面板关闭退多选、多选态不挂左滑全部保持）
- **追加2 拖选接入**: 两面板行内勾选框区挂同款扫选手势（QueueSheet 复用既有 estHeight 换算，HistorySheet 等高步长换算；队列既有长按+Pan 拖选并存，D14-D16）
- **追加2 间距**: SelectCheckbox gap 按各自行左内边距注入（两面板均 `TOKEN_SPACE_L`，D13）

### Constants 增量契约

- `TOKEN_SELECT_ANIM_MS`（多选进出动画时长）
- `DIALOG_MARK_WATCHED_TITLE` / `DIALOG_MARK_WATCHED_MSG`（N 动态替换）/ `TOAST_MARK_WATCHED`（N 动态替换）
- 追加2：`SELECT_SWEEP_EDGE_ZONE` / `SELECT_SWEEP_SPEED` / `SELECT_SWEEP_TICK_MS`（扫选边缘自动滚动三参数，D21）

### SelectLogic 新增共享纯类（追加2）

- `SweepSession`：拖选会话——锁定模式（加扫/减扫）、起点行采样（globalY / scrollOffset / 行 index）、位移增量计算
- `EdgeAutoScroller`：边缘自动滚动器——`start(scroller, 方向, 每帧回调)` / `stop()`（幂等），内部 setInterval 驱动 `scroller.scrollBy`
- 零装饰器（BackHandler 同款分层约束），场景侧持实例、手势回调驱动

## Changelog

- 初版（Phase 2 产出）。D1-D8 覆盖 spec 全部 FR；US1 重构（SourcePage）+ US2 动画补齐（QueueSheet/HistorySheet）+ markWatched 批量接口。
- 追加（真机目检修复 + 共享逻辑抽取）。D9-D12 覆盖追加 FR-008~012；BackHandler 句柄注册 + LongPressGuard + SelectCheckbox/SelectLogic 共享抽取 + SourcePage 层序/真相源修复。
- 追加2（二轮目检改进）。D13-D21 覆盖追加2 FR-013~018：勾选框 gap 参数化（间距对称）、复选框区方向性扫选（SweepSession/EdgeAutoScroller 共享纯类 + 等高步长/estHeight 双换算 + 边缘自动滚动）、选择至此移除、多选底部独立悬浮按钮、List contentEndOffset 悬浮化（占位 ListItem 回退）、CoverThumb 禁拖、扫选令牌三枚。
