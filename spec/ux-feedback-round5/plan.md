# Implementation Plan: UX 反馈第 5 轮修复（订阅 / 播放 / 设置 14 项）

**Input**: Feature specification from `spec/ux-feedback-round5/spec.md`

## Summary

针对用户实测反馈的 14 项体验问题做集中修复：订阅源详情列表改为新上旧下+触底加载更早（对齐 B 站投稿列表）并引入明确已播标记；添加订阅面板优化输入识别（av 号支持、纯数字=UID、文案/按钮更名）、补齐查询结果与二级视图转场动画、修复封面加载与统一占位；修复播放历史→播放浮层的返回键层级（一次返回退出播放页）；无图模式更名并扩展至播放列表与系统播控；彻底移除"取消收藏历史"；修复设置页返回后播放胶囊延迟突现；播放列表返回键退出补滑出动画、多选按钮尺寸统一。全部改动落在既有文件上，遵循项目现行架构与状态管理，不新增目录层级，仅删除一个死代码 model 文件。

## Technical Context

**Language/Version**: ArkTS（ArkUI），`compatibleSdkVersion 6.1.1(24)` / `targetSdkVersion 26.0.0`  
**Primary Dependencies**: HarmonyOS SDK（AVSession、@kit.ArkUI、http、Preferences）  
**State Management**: 现有项目为 V1（@Component/@State/@StorageProp/@StorageLink）为主——增量改动**保留 V1**，不做 V2 迁移；新增代码沿用 V1 装饰器  
**Storage**: Preferences + JSON 文件（既有 AppStore/SubscriptionStore 模式），本轮不新增存储项、删除一项（unfavorite_history.json 不清理文件，仅停止读写）  
**Testing**: `devecocli build` 编译验证 + 真机部署人工验证（按 tasks.md Verification 阶段）  
**Target Platform**: HarmonyOS 手机/平板（API 24+）  
**Project Type**: mobile-app（既有 HarmonyOS 应用增量修改）  
**Performance Goals**: 列表滚动 60fps 不回退；触底加载 2s 内追加；动效时长 250-350ms 与既有转场一致  
**Constraints**: 播放胶囊组件保持挂载不卸载（既有约束，防监听器累积/状态丢失）；播放浮层保持 Index Stack 内条件渲染架构（KI-5 方案 B，不得回退 bindContentCover）  
**Scale/Scope**: 涉及 12 个既有 .ets 文件修改、1 个 model 文件删除；无新页面、无新路由

## Project Structure

### Documentation (this feature)

```text
spec/ux-feedback-round5/
├── spec.md              # 需求规格（14 项 / 7 个用户故事 / FR-001~020）
├── plan.md              # 本文件
└── tasks.md             # 任务拆解（spec-tasks 生成）
```

### Source Code (repository root)

改动全部落在既有文件（无新增目录，遵循项目现行 pages/component/service/model 架构）：

```text
entry/src/main/ets/
├── pages/
│   ├── Index.ets                 # [改] onBackPress 队列退出走滑出动画（US7）；MiniPlayer 显隐改动画驱动（US6）
│   ├── SourcePage.ets            # [改] 列表新上旧下+触底加载（US1）；已播标记（US1）
│   ├── SettingsPage.ets          # [改] "无图模式"更名（US5）；移除取消收藏历史入口+面板（US6）；历史 sheet 返回拦截（US4）；胶囊状态时机调整（US6）
│   └── AddSubscriptionSheet.ets  # [改] placeholder/按钮文案、av 号识别、纯数字=UID（US2）；查询结果过渡+二级视图转场、封面加载（US3）
├── component/
│   ├── MiniPlayer.ets            # [改] 显隐增加淡入/位移过渡动画（US6）
│   ├── QueueDrawer.ets           # [改] 暴露 closeWithSlide 关闭句柄供 Index 调用（US7）
│   ├── QueueSheet.ets            # [改] 条目封面判无图模式（US5）；多选/普通操作行按钮尺寸统一 36vp（US7）
│   └── CoverThumb.ets            # [改] 新增"不拼缩略后缀"参数，修复头像/合集封面加载（US3）；占位形态统一
├── service/
│   ├── BiliService.ets           # [改] 新增 av 号(aid)→视频信息查询（US2）
│   ├── PlayerController.ets      # [改] 移除 unfavoriteHistory 记录链（US6）；AVSession 封面判无图模式（US5）
│   ├── MediaSession.ets          # [改] updateTrack 支持空封面（无图模式）（US5）
│   └── AppStore.ets              # [改] 移除 loadUnfavoriteHistory/saveUnfavoriteHistory（US6）
└── model/
    └── UnfavoriteRecord.ets      # [删] 随取消收藏历史功能一并移除（US6）
```

**Structure Decision**: 遵循项目现行架构（pages/component/service/model，单 Entry + Navigation + 树内浮层）。本轮为既有功能的修复与打磨，不引入 MVVM、不新增目录与页面；改动粒度为既有文件内的定点修改，唯一文件级操作是删除死代码 model（UnfavoriteRecord.ets）。状态管理保留 V1（与全库一致），不引入 V2。

## Complexity Tracking

> 无 Constitution Check 违规需要豁免。（不适用——纯既有架构内定点修改）

## Research & Decisions

### D1 订阅源列表排序与翻页方向（US1，FR-009/010/011）

- **Decision**: 缓存存储保持"新→旧"顺序不变（`sub_cache_<id>.json` 结构不动）；`SourcePage` 展示时去掉现有 `reverse()`，直接按缓存顺序渲染（新上旧下）；"加载更早"从 `onReachStart`（顶部）改为 `onReachEnd`（底部）触发，结果**追加到列表尾部**（现有 `loadOlder` 的 `older.concat(episodes)` 改为 `episodes.concat(older)`）；手动刷新保留，刷新完成后列表回到顶部。已播标记：标题颜色统一 `text_primary`，已播条目在元信息行/标题行增加明确的已播图标（系统 symbol，需在 `sysResource.js` 确认存在后使用；不引入新资源文件）。
- **Rationale**: 存储不动则订阅缓存读写、NEW 徽标、markSeen 逻辑零回归；只改展示与触发方向，改动面最小且与 B 站投稿列表一致。
- **Alternatives considered**: ① 缓存改"旧→新"存储（改动面大、缓存迁移有风险，弃）；② 下拉刷新加载最新（顶部手动刷新已存在，重复，弃）。

### D2 输入识别：av 号与纯数字（US2，FR-003/004）

- **Decision**: `recognizeInput` 新增 av 分支——`^av(\d+)$`（忽略大小写）→ `type='av'`，置于 BV 分支之后；纯数字分支由 `^(\d{5,})$` 放宽为 `^(\d+)$` → `type='up'`（用户确认纯数字视为 UID）。`handleMainInput` 的 switch 增加 `'av'` case：调用 BiliService 新增的按 aid 查询（复用 B 站 view 接口的 aid 参数，返回含 bvid 的视频信息），归一化为 bvid 后走既有 `playBv`/`addToPlaylist` 链路。placeholder 改为简短文案"粘贴链接 / UP 主 UID / av 号"；按钮"载入"→"查询"（加载中 LoadingProgress 状态不变）。
- **Rationale**: av→bvid 归一化后完全复用既有 BV 播放链路，避免取流/队列分支分叉；纯数字放宽是用户明确确认的行为。
- **Alternatives considered**: av 号直接以 aid 取流（需改动 fetchVideoInfo/取流两处签名，分叉大，弃）。

### D3 添加订阅动效（US3，FR-005/006）

- **Decision**: 查询结果出现（upInfo 卡片、收藏夹/合集结果列表）与一级↔二级视图切换（folderView / upDetailView），统一采用 V1 惯用手法：状态变更包在 `animateTo` 中 + 目标视图挂 `TransitionEffect`（透明度+位移组合，250-350ms，曲线与既有 QueueDrawer/Friction 风格一致）；二级视图进=从右侧滑入、一级视图出=向左淡出，返回反向。
- **Rationale**: 与项目既有动效方案（QueueDrawer animateTo、PlayerOverlay transition）同一技术路线；bindSheet 容器本身的系统弹出动画保持不动（用户反馈的是**内容**过渡缺失）。
- **Alternatives considered**: bindSheet 内嵌 Navigation 做层级路由（重量级，sheet 内导航栈复杂化，弃）。

### D4 封面加载与占位统一（US3，FR-007/008）

- **Decision**: 根因判定——`CoverThumb` 对**所有** URL 统一拼 `@240w_240h_1c.webp` 缩略后缀，该后缀仅对视频封面（archive 图）有效；UP 头像（`/bfs/face/`）与部分合集封面拼接后无法加载。修复：`CoverThumb` 新增可选参数控制不拼后缀（raw 模式），添加订阅面板中的 UP 头像/合集封面走 raw 模式；首页/源详情/播放列表既有封面调用保持原样（不回归）。占位统一：UP/收藏夹/合集/系列所有"无封面"场景一律走 `CoverThumb` 同一占位形态（♪ + 玻璃底 + 边框），消除类型间差异；收藏夹/合集列表"用最新一集回填封面"的既有逻辑保留（有图优先展示真实图）。
- **Rationale**: 参数化 raw 模式是定点修复，不触碰其他调用点；占位统一只需收敛各处对空封面的处理路径。
- **Alternatives considered**: CoverThumb 按 URL 路径自动判断是否拼后缀（隐式魔法，调用方不可控，弃）。

### D5 播放历史返回键拦截（US4，FR-017）

- **Decision**: 首选方案——`playHistoryPanel` 的 `bindSheet` 增加 `shouldDismiss` 拦截（SheetOptions.shouldDismiss，API 12+，本机基线 API 24 可用）：当播放浮层处于打开状态（读 `AS_SHOW_PLAYER_OVERLAY`）时，拦截本次关闭请求，改为关闭播放浮层并保持 sheet 打开；浮层未打开时正常放行关闭。`replayHistory` 保持"面板不关、浮层弹出"的现状。
- **Rationale**: 返回键关闭 bindSheet 的默认行为发生在 sheet 层，`shouldDismiss` 是该层唯一能改写关闭决策的入口，直接实现"浮层在上先关浮层"的层级语义。
- **Alternatives considered**: ① `Index.onBackPress` 拦截（实测现象表明事件先被 sheet 默认关闭消费，onBackPress 收不到，弃为主方案，仅当 shouldDismiss 真机表现不符时作为备选回退）；② 点击历史条目时直接关闭 sheet（用户明确选择"保留历史面板"，弃）。
- **风险与验证**: 事件顺序需真机验证（Verification 阶段覆盖 US4 验收场景 2/3）。

### D6 播放胶囊显隐修复（US6，FR-016）

- **Decision**: 两个子问题分别处理——① 时机：`SettingsPage` 将 `AS_ON_SETTINGS_PAGE` 的置 false 从 `aboutToDisappear`（NavDestination 转场**结束后**才触发，即"延迟突现"根因）提前到 `onWillDisappear`（转场**开始时**触发），置 true 对称提前到 `onWillAppear`；② 动画：`MiniPlayer` 保持挂载（既有约束），显隐控制从 `Visibility.None/Visible` 改为"opacity(0/1) + translateY 位移"属性动画（`animateTo` 驱动，约 250ms），透明时 `hitTestBehavior(HitTestMode.None)` 不响应点击；胶囊为 Stack 内悬浮定位、不占布局流，改法无布局副作用；`AS_MINI_PLAYER_VISIBLE` 上报与 `MINI_PLAYER_CLEARANCE` 底部避让逻辑不变。
- **Rationale**: "过一段时间突然出现"= 胶囊状态翻转晚于返回转场且无动画；时机提前+属性动画双管齐下后，胶囊随返回转场即时淡入。Visibility 不参与 transition 机制，故改用属性动画而非 TransitionEffect。
- **Alternatives considered**: 条件渲染+TransitionEffect（卸载胶囊，违反"保持挂载"既有约束，弃）。

### D7 无图模式更名与生效点（US5，FR-012/013/014）

- **Decision**: 设置页选项名"省流量模式"→"无图模式"，分组标题"省流量设置"同步改为匹配标题，副标题按新语义微调（如"不加载封面与头像"），存储键 `KEY_DATA_SAVER` 与已存用户设置**不变**（纯文案改动）。生效点扩展：① `QueueSheet` 条目 `CoverThumb` 调用前判 dataSaver 置空封面（读取方式对齐 `MiniPlayer` 现有 dataSaver 读取链路）；② `PlayerController` 调 `mediaSession.updateTrack` 时封面参数判 dataSaver 置空，`MediaSession.updateTrack` 支持空封面（`AVMetadata` 不填该字段而非传旧值）；③ 开关切换时除既有 `refreshUi` 外，需对**当前曲目**重发一次 `updateTrack`，使系统播控元数据即时刷新。
- **Rationale**: 范围严格限定用户点名的播放列表与系统播控（首页订阅行/源详情/添加订阅不在本轮，已登记 PROJECT_NOTES.md 第三章）；存储键不变保证老用户设置无缝继承。
- **Alternatives considered**: 新增独立存储键（导致存量用户设置丢失，弃）。

### D8 取消收藏历史彻底移除（US6，FR-015）

- **Decision**: 按依赖链自上而下移除——`SettingsPage.ets`：入口行、`historyPanel` 浮层 builder、`historyItems` 状态、`openHistory` 及相关 import；`PlayerController.ets`：`unfavoriteHistory` 字段、`pushHistory`/`removeHistoryItem`/`clearUnfavoriteHistory`、初始化加载调用；`unfavoriteCurrent` 中仅去掉 `pushHistory` 调用，**取消收藏 API 调用与操作提示保留**；`AppStore.ets`：`loadUnfavoriteHistory`/`saveUnfavoriteHistory`；删除 `model/UnfavoriteRecord.ets`。遗留 `unfavorite_history.json` 不清理（已登记 PROJECT_NOTES.md）。
- **Rationale**: 该功能是纯展示性操作记录（已确认不参与任何过滤/业务逻辑），全链路死代码可安全移除；保留取消收藏本体。
- **Alternatives considered**: 仅隐藏 UI 保留底层记录（用户明确选择"彻底移除"，弃）。

### D9 播放列表返回键动画（US7，FR-018）

- **Decision**: `QueueDrawer` 增加关闭句柄回填机制：组件新增回调属性（如 `onRegisterClose`），`aboutToAppear` 时把内部 `closeWithSlide`（滑出动画后卸载）注册给 `Index`，`aboutToDisappear` 注销；`Index.onBackPress` 的队列分支从"直接置 `showQueueSheet=false` 立即卸载"改为"调用注册的关闭句柄"（句柄为空时回退直接卸载，防御时序边界）。遮罩点击退出路径不动。
- **Rationale**: 动画编排逻辑保留在 QueueDrawer 内（单一职责），Index 只持句柄；空句柄回退保证异常时序不卡死。
- **Alternatives considered**: 把动画状态上提到 Index 统一编排（改动面大，QueueDrawer 现有动画逻辑需整体搬家，弃）。

### D10 多选按钮尺寸统一（US7，FR-019）

- **Decision**: `QueueSheet` 操作行按钮统一为 **36vp 高**（普通模式操作行现 30vp 对齐多选态 36vp；多选态不动），按钮内图标/文字布局随高度适配；触发方式（点击区）不变。
- **Rationale**: 36vp 更接近推荐最小可点击尺寸，向大尺寸统一视觉与操作体验均更优。
- **Alternatives considered**: 统一为 30vp（缩小可点击区，体验倒退，弃）。

## Data Model

本轮**无新增实体**；数据模型变化如下：

- **Subscription / 剧集缓存（结构不变）**: `sub_cache_<id>.json` 维持"新→旧"存储顺序；仅 `SourcePage` 展示方向与翻页触发端变化（见 D1）。`lastSeenAt`/NEW 徽标语义不变。
- **UnfavoriteRecord（移除）**: 实体随"取消收藏历史"功能删除；`unfavorite_history.json` 遗留文件不再读写、不清理。
- **RecognizeResult（扩展）**: `type` 取值集合新增 `'av'`（`id` 存纯数字 aid）；`'up'` 的数字输入不再有 5 位下限。
- **封面占位（行为契约）**: CoverThumb 占位形态（♪+玻璃底+边框）成为全类型唯一无图/无封面展示形态；新增 raw 参数控制缩略后缀拼接（默认拼，头像/合集封面调用点传 raw）。
- **无图模式（语义扩展）**: `KEY_DATA_SAVER` 键名与既有存量值不变，语义扩为"无图模式"，生效面 = 播放胶囊 + 播放页 + 播放列表 + 系统播控。

## Contracts & Interfaces

内部组件/服务契约变化（实现与验证据此核对）：

- **recognizeInput（AddSubscriptionSheet.ets，模块内函数）**: 返回类型新增 `'av'`；纯数字任意位数 → `'up'`。调用方 `handleMainInput` 需新增 `'av'` 分支。
- **BiliService（新增静态方法）**: 按 aid 查询视频信息（复用 view 接口 aid 参数），返回既有 `BiliVideo`（含 bvid），供 av 号归一化；签名与 `fetchVideoInfo(bvid)` 对称。
- **CoverThumb（组件参数扩展）**: 新增可选布尔参数控制"不拼缩略后缀"（默认 false 保持既有调用点行为不变）；既有调用点零改动即零回归。
- **QueueDrawer（组件回调扩展）**: 新增关闭句柄注册回调属性；`Index` 持句柄用于 `onBackPress` 队列分支。
- **MediaSession.updateTrack**: coverUrl 参数允许为空字符串——空时不设置 `AVMetadata` 对应字段（无图模式），非空行为不变。
- **PlayerController**: 移除 unfavoriteHistory 全部公开/私有成员（`unfavoriteHistory`/`pushHistory`/`removeHistoryItem`/`clearUnfavoriteHistory`）；`unfavoriteCurrent` 对外行为不变（仍执行取消收藏并提示）。
- **SettingsPage → Index 状态契约**: `AS_ON_SETTINGS_PAGE` 翻转时机移至 `onWillAppear`/`onWillDisappear`；`Index` 侧消费逻辑不变。
- **playHistoryPanel bindSheet**: 新增 shouldDismiss 拦截——播放浮层打开时拒绝关闭并转关浮层；其余关闭路径（遮罩、无浮层时返回）行为不变。

## Changelog

- 2026-10-06：初版生成（对应 spec/ux-feedback-round5/spec.md 全部 FR-001~020）。
