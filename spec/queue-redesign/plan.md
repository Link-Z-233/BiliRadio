# Implementation Plan: 播放列表重做（队列抽屉精简重构 + 睡眠定时播完暂停）

**Input**: Feature specification from `spec/queue-redesign/spec.md`

## Summary

队列抽屉（QueueSheet）重构为播放历史同款极简形态：单行头部（标题计数 + 清除已播/多选/清空三图标）+ 纯列表 + 左滑删除 + EdgeHint，移除搜索/定位/BV 输入行并清理死代码；新增 PlayerController.clearPlayedItems（清除已播，含「播完状态」当前条目）与显式播完标记；睡眠定时（SleepTimerController）新增「播完暂停」模式，经 PlayerController.handleCompleted 完播钩子一次性触发；添加订阅面板单视频入队改为「追加不打断」（与源详情点单集路径统一收敛），两路径补 toast 反馈；收尾销项 PROJECT_NOTES 多条登记并升版本号。**本轮仅规划，不实施**——实现轮待 bug 修复会话完成后启动。

## Technical Context

**Language/Version**: ArkTS（HarmonyOS NEXT，compatibleSdkVersion 6.1.1(24) / targetSdkVersion 26.0.0）  
**Primary Dependencies**: ArkUI（@Entry/Navigation/Stack 条件渲染体系）、AVPlayer（经 AudioPlayer 封装）、AppStorage/Preferences（AppStore）  
**State Management**: 沿用项目现状——全局 V1 `@Component` + `@State`/`@StorageLink`/`@StorageProp`；不引入 V2，不迁移  
**Storage**: AppStore（Preferences）播放列表/历史持久化；SleepTimerController 维持内存态不持久化  
**Testing**: 无自动化测试套件；验证依赖 `arkts_check` + `devecocli build` + 实机（spec-verify 轮）；睡眠定时链路为 KI-6 未验证项，须实机覆盖  
**Target Platform**: HarmonyOS NEXT 平板/手机（API 24 兼容基线，含 `[API24-COMPAT]` 守卫约束）  
**Project Type**: 单模块 HarmonyOS 应用（ArkTS/ArkUI）  
**Performance Goals**: 长队列（数百条）LazyForEach 增量刷新不整表重建；删除/清除操作无可感知卡顿  
**Constraints**: 队列抽屉为 Stack 条件渲染（非 bindContentCover，KI-5 教训勿回退）；左滑删除与长按+竖滑多选手势须共存；B 站 API 请求不受本轮影响（清除已播为纯本地操作）  
**Scale/Scope**: 改动约 8 个既有文件 + 2 个文档，无新文件

## Project Structure

### Documentation (this feature)

```text
spec/queue-redesign/
├── spec.md              # 需求规格（US1-US7，FR-001~FR-021）
├── plan.md              # 本文件
└── tasks.md             # 任务拆解（Phase 3 产出）
```

### Source Code (repository root)

```text
entry/src/main/ets/
├── component/
│   ├── QueueSheet.ets          # 主战场：头部精简/图标化、左滑删除、EdgeHint、移除搜索与输入行、增量数据源
│   ├── QueueDrawer.ets         # 不动（容器滑入滑出与图层挂载维持现状）
│   ├── EdgeHint.ets            # 复用（round6 既有组件，零修改）
│   └── MiniPlayer.ets          # 审计 currentIndex=-1 防御（R2），按需加守卫
├── pages/
│   ├── PlayerOverlay.ets       # 定时面板加「播完暂停」选项；syncSleepTimer 区分模式
│   ├── AddSubscriptionSheet.ets# playBv 改走新入队方法；输入框下方补提醒文案
│   ├── SourcePage.ets          # playEpisode 补 toast
│   └── Index.ets               # 仅在 onTimerExpired 提醒链路需要区分模式时微调（R11）
├── service/
│   ├── PlayerController.ets    # clearPlayedItems/addSingleVideo/currentItemEnded/完播钩子/死代码清理
│   ├── SleepTimerController.ets# playToEof 模式（arm/取消/互斥）
│   └── Constants.ets           # 失效键清理；新增常量（toast 文案、图标尺寸等按需）
└── model/
    └── BiliVideo.ets           # 不动

AppScope/app.json5              # 版本号 0.2.0/2000
PROJECT_NOTES.md                # KI-3/边缘提醒/addByBv/KI-6/版本号销项登记
README.md                       # 仅在功能描述因搜索/添加行移除而失准时微调
```

**Structure Decision**: 遵循既有项目架构（pages/component/service/model 分层，全局 V1 状态，单例服务），不引入 MVVM、不新建目录。改动全部落在既有文件，唯一新「资产」是 PlayerController/SleepTimerController 上的少量新成员与 QueueSheet 的结构重写。

## Complexity Tracking

> 无 Constitution 违规项需要豁免——未引入新文件、新依赖、新抽象层。

## Research & Decisions

### R1 清除已播走新方法，不复用 removeSelectedFromPlaylist

- **Decision**: PlayerController 新增 `clearPlayedItems(): Promise<void>`——移除 `currentIndex` 前缀；当「播完状态」标记为真时连同当前条目一并移除，并使播放器进入「无当前条目 + 暂停」态；由 QueueSheet 计算入口可用性与 toast 文案。
- **Rationale**: 既有 `removeSelectedFromPlaylist` 在删除当前播放条目时会**自动切播**目标条目（L1478-1487），与「保持暂停、不自动续播」（FR-010）直接冲突；且前缀批量移除的索引换算逻辑与按 bvid 过滤路径不同，混用会埋错位切歌隐患。
- **Alternatives considered**: 给 removeSelectedFromPlaylist 加 `autoPlay: boolean` 参数复用——被否：单方法两套语义，调用方易传错；「无当前条目但队列非空」是新状态（见 R2），旧方法三个分支都不覆盖。

### R2 「无当前条目但队列非空」以 currentIndex=-1 表达

- **Decision**: 清除已播移除播完当前条目且队列有剩余时：`currentIndex=-1`、`isPrepared/isPlaying=false`、`resetPlayer()`、持久化 `(playlist, -1, 0)`——与既有「队列清空」分支（L1469-1477）同型，仅队列非空。
- **Rationale**: -1 语义已有先例（空队列/未播放），QueueSheet 高亮 `index === currentIndex` 自然不命中，PlayerOverlay 已有 `trackIndex<0` 兜底文案（L809-817「暂无播放内容」）。
- **Alternatives considered**: 指向下一首但暂停在 0:00——被否：与「点击条目即播」的心智不符，且会在队列头部制造一个幽灵「当前曲目」高亮。
- **风险与对策**: MiniPlayer 等剩余消费方须逐一审计 `currentIndex` 越界访问，实现轮以全局检索 `currentIndex` 消费点为验收门。

### R3 「播完状态」用显式布尔标记，不做派生判定

- **Decision**: PlayerController 新增 `currentItemEnded: boolean`——在 `handleCompleted` 的两个「停在原条目」分支（顺序模式到末集/倒序回到首集的自然播完、播完暂停触发）置 true；在 `playIndex`/seek/`playRequest` 等任何重新开播路径清 false；随 `emitUi` 广播。
- **Rationale**: 派生判定（`currentTime >= duration && !isPlaying`）在 duration 未知（=0）、手动 seek 到末尾、流式边下边播时长修正等场景全部误判；完播回调是唯一权威信号源。
- **Alternatives considered**: 直接检查 AVPlayer 状态字符串 `'completed'`——被否：状态是瞬时事件不持久，清除已播入口在队列抽屉打开时才查询，需要可驻留的状态。

### R4 播完暂停经完播钩子一次性触发，不做轮询

- **Decision**: SleepTimerController 新增模式字段与 `armPlayToEof()`/`disarmPlayToEof()`；`startTimer`（倒计时）与 arm 互斥（后选取代先选）；`cancelTimer` 清全部。PlayerController.`handleCompleted` 在自动切歌分支**之前**查询该模式：命中则解除（一次性）、置 `currentItemEnded`、设状态文案、return（停在原条目，AVPlayer completed 态已自然暂停）。
- **Rationale**: 「播完」只有一个事件源（'completed' 状态回调），钩子处拦截是最短路径；一次性解除避免下一首播完再次暂停（用户既已手动续播/切歌即表达继续收听意愿）。
- **Alternatives considered**: SleepTimerController 监听 PlayerController 进度轮询判断接近末尾——被否：秒级轮询+末尾阈值判定在时长未知流上不可靠，且引入跨单例反向依赖。

### R5 单视频「追加不打断」收敛到 loadPlaylistAndPlay 语义

- **Decision**: `loadPlaylistAndPlay` 返回值从 void 改为入队结果枚举（已追加/开始播放/已在队列/失败）；PlayerController 新增 `addSingleVideo(bvid): Promise<入队结果>`——fetchVideoInfo 后委托 loadPlaylistAndPlay 单条入队。AddSubscriptionSheet.`playBv` 改调 `addSingleVideo`，按结果 toast，并移除 `goToPlayerTab` 自动唤起播放层；SourcePage.`playEpisode` 按 loadPlaylistAndPlay 返回结果 toast 同款分型。
- **Rationale**: 追加不打断+去重语义 loadPlaylistAndPlay 已完整实现（L490-537），新方法只补「按 bvid 取详情」一步；返回枚举让两处 UI 共用一套 toast 分型文案（FR-021），避免各写各的判断。
- **Alternatives considered**: 保留 addToPlaylist 改其内部行为——被否：其「已在歌单则跳播」（L1073-1079）与立即切播（L1092）语义被 FR-020 明确废弃，原地改造等于换实现留旧名；删除旧方法并由 addSingleVideo 接管，调用面干净（addToPlaylist 的两个调用方——队列输入行与 playBv——前者移除后者切换）。
- **注意**: AddSubscriptionSheet 的 av 号/短链解析链路最终都汇入 playBv（L198-215），一处切换全链生效。

### R6 左滑删除与长按多选手势共存

- **Decision**: ListItem 挂 `swipeAction({ end: 删除按钮 builder })`（对齐播放历史 `historyDeleteAction` 样式：危险色删除按钮）；删除执行复用 `removeSelectedFromPlaylist([bvid])`（单条，含删除当前条目时的既有自动切播语义，FR-010）；多选模式下同样可左滑，删除后同步从 `selectedBvids` 剔除（既有 syncFrom 过滤已覆盖）。横向 swipeAction 与 LongPress+PanDirection.Vertical 由平台手势仲裁天然分离，无需额外代码。
- **Rationale**: KI-3 交互约定即此（「左滑露出删除、点击执行、不做阈值直删」）；播放历史同款交互已实机验证可行。
- **Alternatives considered**: 多选态禁用左滑——保留为降级预案（spec Assumptions 已登记：实现中若发现手势冲突则禁用并在报告说明）。

### R7 PlaylistDataSource 补增量删除通知

- **Decision**: PlaylistDataSource 镜像 HistoryDataSource 增补 `notifyDataDelete(index)`（播放历史轮已验证的增量语义）；单条左滑删除按 bvid 实时解析下标后单点通知；清除已播的批量前缀移除**从高索引向低索引**逐个通知（避免删除过程中索引左移错位）。
- **Rationale**: 现有 setItems 全量 reload 在长队列上会整表重建（封面重新加载、滚动位置可能丢失），spec Edge Cases 明确禁止。
- **Alternatives considered**: 批量前缀用 onDataReloaded——被否：与单条删除体验不一致且重新触发封面解码。

### R8 EdgeHint 接入照搬播放历史宿主模式

- **Decision**: QueueSheet 列表外层包 Stack，`EdgeHint({ text, edge: 'bottom' })` 声明在 List 之前（z 序更低）；可见性由 `onWillScroll`/`onScrollStop` + `Scroller.currentOffset` 边界判定驱动，文案「已经到底了」，与 SettingsPage 历史面板（L868-881）逐行同型。
- **Rationale**: round6 已在三个列表实机验证该模式；QueueSheet 已持有 `listScroller`（定位按钮移除后仅剩此消费），复用零新增。
- **Alternatives considered**: 无——复用是唯一合理路径。

### R9 头部图标从 sys.symbol 体系选取，实现前逐一验证存在性

- **Decision**: 头部三图标（清除已播/多选/清空）与多选操作行三图标（全选/移除所选/返回）全部走 `SymbolGlyph($r('sys.symbol.*'))`；危险语义（清空/移除/删除）用 danger_red 或同款语义色；「移除所选」数量以图标旁小字号数字呈现。候选：多选/全选 checklist 系、清空/删除 trash 系、返回 chevron_left、清除已播以「对勾+清扫」语义图标区分于 trash（如 checkmark_circle_badge_xmark 或 broom 系）。**实现前必须在 sysResource.js（本机 SDK 路径见 AGENTS）中逐一确认存在**，不存在则就近替换。
- **Rationale**: 项目图标体系已全量 sys.symbol（播放层五键/底部操作行同款）；文字按钮改图标是用户明确要求。
- **Alternatives considered**: 自绘/媒体资源图标——被否：引入资源维护成本，且与全应用图标语言不一致。

### R10 死代码清理边界（防止误删活代码）

- **Decision**: 移除清单——QueueSheet 侧：searchPanel builder、doSearch/playSearchResult、搜索三状态、bvInput/addMsg/addByBv、locateCurrent/flashIndex/flashTimer、定位按钮；PlayerController 侧：`searchLibrary`、`playFromLibraryResult`、`addManyToPlaylist`、`addToPlaylist`（被 addSingleVideo 取代）、`goToPlayerTab`（两个调用方均随本轮移除，实现时全局复核）；Constants 侧：`AS_SHOW_SEARCH`、`SEARCH_MAX_INPUT_LEN` 等 UI 键。**每项删除前必须全局检索调用点确认零引用**。
- **Rationale**: FR-015；ponytail 原则——删优于留。
- **Alternatives considered**: 注释保留——被否：与 DIS-1 下拉刷新式「注释保留待恢复」不同，本轮移除是**产品决策性移除**（用户确认砍掉），非暂时禁用。

### R11 定时面板「播完暂停」选项的 UI 形态

- **Decision**: sleepTimerPanel 的 preset Flex 行内在「自定义」之后追加「播完暂停」按钮；播完暂停模式激活时该按钮高亮（强调色），且底部「取消定时」按钮照常显示（cancelTimer 统一清两种模式）；播放层 timer 入口图标的剩余时间数字仅在倒计时模式显示，播完暂停模式仅图标高亮（syncSleepTimer 按模式区分）。
- **Rationale**: 与既有 preset 按钮视觉同构，零新布局；单选互斥由 R4 的控制器层保证，UI 无需额外状态机。
- **Alternatives considered**: 独立开关页/二级面板——被否：杀鸡用牛刀，与面板轻量形态不符。

### R12 睡眠定时提醒回调（Index.ets onTimerExpired）对播完暂停的适配

- **Decision**: 播完暂停触发时**不弹**「计时已结束」AlertDialog（用户正在入睡场景，播完自然停止即可）；SleepTimerController 的 expired 回调仅倒计时模式触发，播完暂停在 PlayerController 侧消费、不经 onTimerExpired。
- **Rationale**: 两种模式的用户预期不同——倒计时归零是「时间到」事件需要告知，播完暂停是「内容结束」自解释事件。
- **Alternatives considered**: 播完也弹提醒——被否：夜间场景弹窗打扰。

### R13 版本号升至 0.2.0/2000

- **Decision**: AppScope/app.json5 的 versionName 0.1.0→0.2.0、versionCode 1000→2000；PROJECT_NOTES「版本号更新」条目销项。
- **Rationale**: 「待播放列表重做完成后统一更新」的既定安排以本轮为锚点；minor 位提升对应用户可感知的功能变化。
- **Alternatives considered**: 0.1.1——被否：本轮含交互形态大改（头部重构+功能移除），patch 位不足以表达。

## Data Model

### 入队结果枚举（新增，PlayerController）

- `EnqueueResult`：`APPENDED`（追加成功）/ `STARTED`（队列空首播）/ `DUPLICATE`（已在队列，去重跳过）/ `FAILED`（解析/网络失败，携带 statusMsg）
- 消费方：AddSubscriptionSheet、SourcePage 的 toast 分型（FR-021）；loadPlaylistAndPlay 返回类型由 void 改为此枚举

### 播完状态（新增，PlayerController）

- `currentItemEnded: boolean`——true 仅在 handleCompleted 停在原条目的两分支（自然播完/播完暂停）时成立；任何重新开播路径清 false；随 emitUi 广播
- 消费方：QueueSheet 清除已播入口（当前条目是否随清）

### 睡眠定时模式（扩展，SleepTimerController）

- `mode: SleepTimerMode`——`NONE` / `COUNTDOWN`（既有倒计时，行为不变）/ `PLAY_TO_EOF`（播完暂停，无计时器、无 tick、一次性）
- 互斥：startTimer → 置 COUNTDOWN 清 PLAY_TO_EOF；armPlayToEof → 置 PLAY_TO_EOF 清倒计时（含停 tick）；cancelTimer → 归 NONE
- `active` 语义扩展为「任一模式激活」；`getRemainingSeconds` 仅 COUNTDOWN 有意义

### 清除已播操作语义（新增，PlayerController.clearPlayedItems）

- 输入：无（内部按 currentIndex 与 currentItemEnded 计算）
- 前置：`currentIndex > 0`（有前缀）或 `currentItemEnded === true`，否则调用方 toast 拦截
- 效果：移除 `[0, currentIndex)` 前缀；currentItemEnded 时再移除当前条目 → 队列空则走既有清空分支，非空则 currentIndex=-1 + 暂停（R2）；播放中场景仅移除前缀、currentIndex 前移、播放不中断
- 出口：playlistVersion++、持久化、emitUi

### 既有实体（不变）

- BiliVideo（bvid 唯一键）、selectedBvids 多选集（失效过滤逻辑沿用 syncFrom）、PlaylistDataSource（增补 notifyDataDelete）

## Contracts & Interfaces

### PlayerController（service/PlayerController.ets）

- `clearPlayedItems(): Promise<void>`——见 Data Model；幂等（无可清内容时 no-op）
- `addSingleVideo(bvid: string): Promise<EnqueueResult>`——取详情 + 委托 loadPlaylistAndPlay；FAILED 时 statusMsg 已含原因
- `loadPlaylistAndPlay(items: BiliVideo[], startIndex: number): Promise<EnqueueResult>`——返回类型变更，行为不变
- `removeSelectedFromPlaylist(bvids: string[])`——签名不变，新增单条左滑删除调用方
- 删除：`addToPlaylist` / `addManyToPlaylist` / `searchLibrary` / `playFromLibraryResult` / `goToPlayerTab`（R10，删前全局复核）
- `handleCompleted` 内部扩展：播完暂停拦截分支（R4）；自然播完分支置 currentItemEnded（R3）

### SleepTimerController（service/SleepTimerController.ets）

- `mode: SleepTimerMode`（新增公共只读语义）；`armPlayToEof(): void` / `disarmPlayToEof(): void`
- `startTimer(seconds)` / `cancelTimer()` 签名不变，语义扩展互斥清理（R4）
- `onTimerExpired` 回调仅 COUNTDOWN 归零触发（R12）

### QueueSheet（component/QueueSheet.ets，结构重写）

- 头部单行：`播放队列 (N)` 标题 + 清除已播/多选/清空三 SymbolGlyph 图标按钮（R9）；空队列时三入口隐藏/不可用（FR-013）
- 条目：`swipeAction({ end: 删除 builder })`（R6）+ 点击切歌/勾选 + 当前高亮；LazyForEach 键值含可变字段防陈旧（沿用 KI-8 教训——键值须含条目内容特征，实现时确认 bvid 单键足够或扩展）
- EdgeHint：bottom「已经到底了」（R8）
- 多选操作行：全选/移除所选(N)/返回三图标（R9）
- 移除：搜索/定位/BV 输入全部 UI 与状态（R10）

### AddSubscriptionSheet（pages/AddSubscriptionSheet.ets）

- `playBv` → `addSingleVideo` + 按结果 toast + 不再 goToPlayerTab（R5）；av 号/短链链路经 playBv 自动继承
- 输入框下方说明行追加「单视频将加入播放列表，不打断当前播放」（FR-019）

### SourcePage（pages/SourcePage.ets）

- `playEpisode` 按 loadPlaylistAndPlay 返回结果 toast（FR-021）；`playAll` 不动（本轮范围外）

### PlayerOverlay（pages/PlayerOverlay.ets）

- sleepTimerPanel 追加「播完暂停」按钮，选中态高亮（R11）；syncSleepTimer 区分模式（剩余时间仅 COUNTDOWN）
- 播完暂停触发后的播放层状态展示：标题保留原条目、播放键呈暂停态、进度在末尾——由既有 syncFrom 自然驱动，无新增契约

### 验证契约（实现轮验收基线）

- `arkts_check` 零错误 → `devecocli build` 通过
- KI-6 链路实机验证：播完暂停三步（选→播完停→手动解除）+ 倒计时既有验证点（归零暂停/后台校准/按钮联动），通过则移除 `[UNVERIFIED 2026-10]` 标注
- currentIndex=-1 全局消费点审计清单（MiniPlayer/PlayerOverlay/MediaSession/QueueSheet）零越界访问
