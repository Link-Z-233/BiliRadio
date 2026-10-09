# Implementation Plan: UX 反馈第 6 轮修复

**Input**: Feature specification from `spec/ux-feedback-round6/spec.md`

## Summary

15 项反馈修复＋1 项补录 bug（系统播控进度条）＋README 版本信息移除＋3 项规划登记。技术主线：① 首页订阅列表改为「每次渲染前从磁盘重载」的单一真相源策略，配 `subExists` 防刷新回调复活已删订阅；② 删除 SourcePage 的 endArmed 手势武装机制，触底加载回退 `loadingOlder + canLoadOlder` 两道门槛，失败改时间冷却防连发；③ 列表回弹过冲提醒：保持 `EdgeEffect.Spring` 过冲、空隙内显示提示文字（新增 `EdgeHint` 组件），三列表接入（播放队列后续大改时再做）；④ 播放历史返回层级在 Index 与 SettingsPage 两处实现同一优先级（面板 → 浮层 → 其他），规避系统返回事件分发顺序的不确定性；⑤ 新增 `CoverUrl` 尺寸后缀工具，播放页大封面/系统播控封面按显示尺寸取图、非 Wi-Fi 降档；⑥ 日志改 NavDestination 二级页（复用 LogSheet 组件）；⑦ 设置页文案/顺序调整与登出确认；⑧ README（PiliPlus 引用＋移除版本信息）与 PROJECT_NOTES 登记三条规划（含版本号更新待播放列表重做后），版本号本轮不动；⑨ 系统播控进度条修复：历史重播传入条目时长＋prepared 兜底回推＋播放态补 duration 字段。

## Technical Context

**Language/Version**: ArkTS（HarmonyOS NEXT，API 24 兼容 / target 26）
**Primary Dependencies**: ArkUI 声明式 UI、`@kit.NetworkKit`（connection）、`@kit.AVSessionKit`、`@kit.CoreFileKit`
**State Management**: 全局 V1 `@Component` + `@State`/`@StorageLink`/`@StorageProp`/`@Watch`（既有架构保留，不引入 V2）
**Storage**: preferences（AppStore）+ 本地 JSON（SubscriptionStore：subscriptions.json / sub_cache_<id>.json）
**Testing**: 无测试套件；验证走 `arkts_check` + `devecocli build` + 真机（Phase 3 决定是否含 UI 验证）
**Target Platform**: HarmonyOS NEXT 手机/平板（最低 6.1.1 / API 24）
**Project Type**: 单模块 HarmonyOS 应用（entry）
**Performance Goals**: 列表滚动 60fps 不因边缘提示掉帧；封面位图内存不高于现状
**Constraints**: API 26 接口须带 `[API24-COMPAT]` 守卫；签名材料不入 git；代码零注释（`ponytail:` 标注除外）
**Scale/Scope**: 触碰 14 个源文件（2 新增组件/页面 + 1 新增工具）+ 2 文档 + 资源/路由

## Project Structure

### Documentation (this feature)

```text
spec/ux-feedback-round6/
├── spec.md              # 需求规格（Phase 1 已确认）
├── plan.md              # 本文件
└── tasks.md             # Phase 3 产出
```

### Source Code (repository root)

```text
entry/src/main/
├── ets/
│   ├── pages/
│   │   ├── HomePage.ets        # 改：US1 重载策略、US5 顶/底过冲提示
│   │   ├── SourcePage.ets      # 改：US2 删 endArmed、US3 行重排/时间/已播、US5 底部过冲联动提示
│   │   ├── SettingsPage.ets    # 改：US4 返回层级+底部文案、US5 历史面板过冲提示、US7 六项调整、US9 重播传时长
│   │   ├── PlayerOverlay.ets   # 改：US6 大封面尺寸档
│   │   ├── Index.ets           # 改：US4 返回优先级（面板→浮层）
│   │   └── LogPage.ets         # 新：US7 日志二级页（NavDestination 包 LogSheet）
│   ├── component/
│   │   ├── EdgeHint.ets        # 新：US5 过冲空隙提示文字（纯展示）
│   │   ├── LogSheet.ets        # 微调：从 sheet 形态适配页面形态（去底部遮罩依赖等）
│   │   └── CoverThumb.ets      # 改：缩略后缀逻辑改用 CoverUrl 工具（行为不变）
│   ├── service/
│   │   ├── CoverUrl.ets        # 新：US6 CDN 尺寸后缀工具（唯一实现点）
│   │   ├── SubscriptionStore.ets # 改：US1 新增 subExists 查询
│   │   ├── PlayerController.ets  # 改：US6 公开当前网络态（复用既有 watchStableNetworkType）、US9 prepared 回推时长
│   │   ├── MediaSession.ets      # 改：US6 播控封面按档取 URL、US9 播放态补 duration 字段
│   │   └── Constants.ets         # 改：新增常量（尺寸档/失败冷却）
│   └── resources/
│       ├── base/element/color.json   # 新增 success_green
│       ├── dark/element/color.json   # 新增 success_green 深色变体
│       └── base/profile/router_map.json # 新增 logPage 路由
README.md                       # 改：US8 PiliPlus 引用、移除版本号信息（「版本」小节＋起版说明行）
PROJECT_NOTES.md                # 改：US8 规划登记 + endArmed 条目销项
```

**Structure Decision**: 既有项目，沿用当前 pages/service/model/component 架构与 V1 状态管理，不做 MVVM 迁移。新增文件仅 3 个且各司一职（EdgeHint 可复用展示组件、LogPage 薄路由壳、CoverUrl 单函数工具），符合最小拆分原则；不新建 viewmodel/data 目录。

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| 新增 3 个文件 | EdgeHint 需 3 处复用；LogPage 需路由注册独立文件；CoverUrl 需被 UI 与 service 两侧共用 | 内联到各页会 3 处重复提示逻辑；后缀逻辑留在 CoverThumb 内则 MediaSession/PlayerOverlay 无法复用 |

## Research & Decisions

### D1 首页实时同步策略（US1，FR-001/002/003）

- **Decision**: `HomePage.rebuild()` 起点固定为 `SubscriptionStore.loadSubscriptions()` 重载（磁盘为单一真相源，内存数组仅作当次渲染派生物）；`SubscriptionStore` 新增 `subExists(id): boolean` 查询；`silentRefresh` 循环内每源刷新前校验 `subExists`（删除后跳过，防孤儿剧集缓存），完成回调保存前过滤掉已不存在于存储的订阅再落盘。首页行 LazyForEach 键值增加 `cover` 字段（KI-8 键值未含封面，封面单独更新时行不重建）。
- **Rationale**: 根因是 HomePage 持有 `aboutToAppear` 加载的陈旧数组且刷新回调把旧引用整体写回磁盘。重载＋存活过滤以最小 diff 修根因，不引入事件总线/观察者等新抽象。
- **Alternatives considered**: ① 全局订阅变更通知总线（过度设计，仅一个消费方）；② SubscriptionStore 改内存单例缓存（改动面大，触碰所有调用方）。

### D2 触底加载常规化与防连发（US2，FR-004/005）

- **Decision**: 删除 `endArmed` 字段、`onTouch` 武装逻辑及「失败不归还」惩罚；`loadOlder` 门槛回退 `loadingOlder || !canLoadOlder` 两道；加载失败引入时间冷却（`Constants.LOAD_OLDER_FAIL_COOLDOWN_MS = 3000`，冷却期内触底忽略），冷却结束后可重试。
- **Rationale**: APP 签名链已真机验证可靠（appsign-up-fetch 轮，PROJECT_NOTES 下轮候选 #1 既定安排）；但 onReachEnd 按住底端每帧重触发是平台行为，删掉手势武装后必须留一道失败防风暴闸门，时间冷却是唯一不依赖手势判定的最简方案。
- **Alternatives considered**: ① 失败置 `canLoadOlder=false` 永久拦截（违背 FR-005 重试要求）；② 滚离底部才归还触发权（onScrollIndex 布局回调与真实滚离无法区分，上轮已实证不可行）。

### D3 播放历史返回层级（US4，FR-011）

- **Decision**: 返回优先级统一为「历史面板 → 播放浮层 → 其他」，在 `Index.onBackPress` 与 `SettingsPage.onBackPressed` **两处实现同一优先级**：浮层打开（`AS_SHOW_PLAYER_OVERLAY`）且历史面板打开（`AS_SHOW_PLAY_HISTORY`，SettingsPage 经 @StorageLink 已同步至 AppStorage）→ 仅关面板返回 true；浮层打开且面板已关 → 关浮层返回 true（防止 NavDestination 默认出栈把设置页弹回首页而浮层悬空）；移除 `playHistoryPanel` bindSheet 的 `shouldDismiss` 浮层拦截（保留正常 dismiss 路径）。`replayHistory` 加 try/catch toast（面板不再显示 statusMsg 后的失败反馈兜底）。
- **Rationale**: 系统返回事件在 @Entry.onBackPress 与 NavDestination.onBackPressed 之间的分发顺序无权威文档保证，两处实现同一优先级使行为与分发顺序解耦，确定性成立。
- **Alternatives considered**: 仅改 SettingsPage 侧（若 Index.onBackPress 先行，返回仍会先关浮层，行为不确定）。

### D4 列表回弹过冲提醒（US5，FR-009/010）

- **Decision**: 交互对齐鸿蒙系统设置（用户澄清并经 HTML 原型确认）：不做悬浮 toast，采用**回弹过冲**——List 保持 `edgeEffect(EdgeEffect.Spring)`（内容跟手拉出边缘、松手回弹归位），过冲露出的空隙内显示灰色提示文字、随回弹消失（**无计时器**，回弹归位即隐藏；同一边缘单条提示天然不叠加）。新增 `component/EdgeHint.ets` 纯展示组件（`@Prop text: string` 空串不渲染、`@Prop edge: 'top' | 'bottom'`，定位于边缘约 22-24vp、水平居中、次级文字色、约 13fp）；宿主以 Stack 承载：EdgeHint 声明在 List **之前**（z 序更低，List 背景透明），过冲时内容移出即露出提示。可见性由过冲状态驱动：`onScrollEdge(side)` 触发对应边缘显示，回弹归位后隐藏（实机以 `onWillScroll`/`onDidScroll` 校准过冲起止；若 onScrollEdge 在过冲阶段不触发，兜底 onWillScroll 边界判定）。文案：顶部「已经到顶了」；首页订阅/播放历史底部「已经到底了」；SourcePage 底部三态联动：可加载 → 触发加载并提示「加载中…」，不可加载 → 「没有更多了」。短列表（内容不足一屏）默认不可滚动即无过冲，无需额外门槛。接入三处：HomePage、SourcePage、SettingsPage 历史面板；**播放队列本轮不接入**（后续整体大改时一并处理）。
- **Rationale**: 用户澄清指定「内容跟手、后面露空、松手回弹」的系统设置行为，并经交互原型确认；提示与过冲状态绑定后无需计时器与去抖逻辑，组件零内部状态、接入成本最低。
- **Alternatives considered**: ① 悬浮胶囊＋1500ms 计时器（原方案，用户否决——非系统设置观感）；② promptAction toast（固定位置、无过冲联动、风格不对齐）；③ 全局单例提示服务（三个宿主层级不同，全局定位复杂）。

### D5 封面尺寸档与网络态来源（US6，FR-013/014）

- **Decision**: 新增 `service/CoverUrl.ets`：静态 `sized(url, w, h)`，逻辑与现 CoverThumb.thumbUrl 一致（hdslb.com 域、无 `@`、保留 query 才拼 `@{w}w_{h}h_1c.webp`）。CoverThumb 改调用它（240 档行为不变）。三档尺寸入 Constants：缩略 240×240（现状）、大封面 672×378（Wi-Fi）、省流 480×270（非 Wi-Fi）。PlayerOverlay 大封面经 `CoverUrl.sized` 取档——网络态取 `PlayerController` 公开的 `isWifiNow`（由既有 `watchStableNetworkType` 订阅维护，变更时随 emitUi 广播刷新）；MediaSession.updateTrack 内 `await NetUtil.isWifi()` 后取档拼 URL（mediaImage 传 URL 字符串，系统侧自行拉取）。无图模式与 raw URL 逻辑不动。
- **Rationale**: 后缀拼接逻辑全库唯一实现点；网络态复用 PlayerController 既有稳定网络监听，UI 侧同步取值无异步闪烁。**与 spec 假设的偏差**：NetUtil.isWifi 判定失败按「非 Wi-Fi」保守口径（全库既有语义）→ 封面走省流档，而非 spec 假设的「不可得按 Wi-Fi 档」；无网络时封面本就不可加载，该偏差无实际可观测影响。
- **Alternatives considered**: ① 封面清晰度设置项（用户已否决，选固定优化）；② PlayerOverlay 每次 await NetUtil.isWifi（渲染路径引入异步，封面闪变）。

### D6 日志二级页（US7，FR-015）

- **Decision**: 新增 `pages/LogPage.ets`：NavDestination 包裹既有 `LogSheet` 组件（列表/清空/导出全复用）＋ title「日志查询」；`router_map.json` 注册 `logPage`。SettingsPage 删除 `showLogSheet` 状态、bindSheet 挂载与 onBackPressed 日志分支；入口行改 `navPathStack.pushPathByName('logPage', '', onPop → logCount 刷新)`。
- **Rationale**: LogSheet 本身是自含组件（aboutToAppear 自读数据），薄路由壳即可完成形态迁移，零逻辑搬移。
- **Alternatives considered**: 把 LogSheet 内容整体搬入 LogPage（删除组件）——搬移量大且未来无第二宿主需求，不如薄壳复用。

### D7 已播判定与标识样式（US3，FR-006/008）

- **Decision**: `loadPlayedSet` 仅收编播放历史中**已完成**条目（进度字段为「已听完」哨兵值，即既有 `-1` 语义），未听完不标记。标识为绿色「✓ 已播」小标签：`resources/base|dark/element/color.json` 新增 `success_green`（浅色/深色两份），SourcePage 剧集行引用。行布局：标题独占整行（maxLines 2）；时间行 `Row`：日期时刻 · 时长 + `Blank()` + 右端标识（NEW 主题色在前、已播绿色在后，共存不遮挡）。时间格式 `YYYY-MM-DD HH:mm`（24 小时制）。
- **Rationale**: 「已听完」哨兵值是 play-history-progress 轮已统一的语义，直接复用；绿色以资源资源定义（非硬编码色值），随深浅色自适应。
- **Alternatives considered**: 图标式绿色 ✓（13vp 图标在密集列表中辨识度不足，用户要求「明显一点」，文字+图标组合更醒目）。

### D8 文档调整与登记（US8，FR-021/022/024）

- **Decision**: README 在「与 BiliMusic 的关系」之后新增「参考项目」小节：PiliPlus（Flutter 哔哩哔哩客户端）——音质档位与设置交互参考；项目 URL **以本地仓库 `D:/UsersFiles/Link_Z/Desktop/Code/PiliPlus` 的 git remote 或其 README 为准读取**，禁止凭记忆书写。README 移除版本号信息：**直接删除**「## 版本」整节（「当前版本：0.1.0…」与两条预览说明）及「与 BiliMusic 的关系」中的「版本号从 0.1.0 重新起版」条目，原位置不补写任何替代文案；`AppScope/app.json5` 版本号本轮不动（保持 0.1.0/1000）。PROJECT_NOTES「三、规划与预告」新增三条登记（订阅源导出导入、关于页文案优化、版本号更新——待播放列表重做完成后统一更新），并将「下轮候选清单 #1 删除 endArmed」销项（本轮完成）。
- **Rationale**: URL 凭记忆生成有编造风险，本地参考仓库是唯一可信来源；版本号与播放列表重做绑定交付（用户指定，避免中途多次起版），README 不再维护版本信息可杜绝文档与应用版本双源不同步。

### D9 系统播控时长传递与回推（US9，FR-025/026）

- **Decision**: 三点修复。① **根因**：`SettingsPage.replayHistory` 重建 BiliVideo 时传入 `item.duration`（历史条目已存秒数，历史面板「剩 xx」即用它），不再置 0；② **兜底回推**：`PlayerController` prepared 处理器取得 `this.player.duration`（真实毫秒时长）后，若该曲目此前推送的会话时长为 0，以 `force=true` 重推 `mediaSession.updateTrack`（绕过同曲去重守卫）修正 AVMetadata；③ **播放态补时长**：`MediaSession.updateTrack` 缓存时长字段，`updateState` 的 `AVPlaybackState` 增加 `duration` 字段（毫秒，本机 SDK 已核实：`@ohos.multimedia.avsession.d.ts` L3506，since API 11，基线 API 24 可用），随每次状态上报刷新，系统组件以 position＋duration 渲染进度条。
- **Rationale**: 症状「应用内正常、系统为空」印证应用内 `this.duration`（播放器真实值）与系统会话时长（元数据 0）脱节；系统组件不读应用内状态，回推会话是唯一修正点。①治根因一行；②③兜住所有时长未知链路（队列粘贴链接、旧历史记录、特殊稿件），AVPlaybackState.duration 仅一行成本换播放态自含。
- **Alternatives considered**: ① 仅修 replayHistory 传参（其他零时长链路仍会复现）；② updateState 增加时长参数（PlayerController 7 处调用点全改，diff 大于缓存字段方案）；③ 仅靠 AVMetadata 不补 AVPlaybackState.duration（部分系统组件以播放态渲染进度）。
- **Alternatives considered**: 无。

## Data Model

无新增持久化实体。既有实体的语义/使用变化：

- **Subscription**（不变）：首页内存数组降级为渲染派生物，每次 rebuild 从 `subscriptions.json` 重载；LazyForEach 行键值由 `id_latestTitle_newCount` 扩为 `id_latestTitle_newCount_cover`。
- **PlayHistoryItem**（不变）：已播判定收紧为 `progress === -1`（已听完哨兵）才入 SourcePage 的 playedSet；`progress > 0` 的未听完条目不显示任何标识。
- **封面 URL 尺寸档**（新增纯常量）：缩略 240×240 / 大封面 672×378 / 省流 480×270，同一 `CoverUrl.sized` 机制的不同取值，定义于 Constants。
- **播放浮层/历史面板层级**：固定优先级「返回先关面板、再关浮层」，面板关闭后浮层退出直接落设置页。

## Contracts & Interfaces

- **SubscriptionStore.subExists(id: string): boolean** —— 订阅是否仍存在于存储（silentRefresh 循环前置校验与回调落盘过滤共用）
- **CoverUrl.sized(url: string, w: number, h: string→number): string** —— hdslb.com 封面拼 `@{w}w_{h}h_1c.webp` 后缀；非 hdslb / 已含 `@` / 空串原样返回（raw 语义不回归）
- **EdgeHint 组件**：`@Prop text: string`（空串不渲染）、`@Prop edge: 'top' | 'bottom'`（定位顶/底边缘）；声明于宿主 Stack 中 List 之前（z 序更低），仅过冲空隙可见；可见性由过冲状态驱动，无计时器
- **PlayerController.isWifiNow: boolean**（公开只读语义字段）——既有 watchStableNetworkType 订阅维护，网络档位变化随 emitUi 广播
- **路由契约**：`router_map.json` 新增 `{ "name": "logPage", "buildMethod": "LogPageBuilder", "pageSourceFile": "pages/LogPage.ets" }`；SettingsPage 经 navPathStack push，onPop 回调刷新日志角标
- **返回处理契约**（Index.onBackPress 与 SettingsPage.onBackPressed 同构）：`浮层开 && 历史面板开 → 仅关面板`；`浮层开 && 面板关 → 关浮层`；否则走各自既有分支
- **系统会话时长契约**（US9）：`MediaSession.updateTrack` 缓存 `lastDurationMs`，`updateState` 的 AVPlaybackState 携带 `duration: lastDurationMs`；PlayerController prepared 后会话时长为 0 时 force 重推 updateTrack（真实时长）
- **Constants 新增**：`LOAD_OLDER_FAIL_COOLDOWN_MS = 3000`、`COVER_THUMB_W/H = 240`、`COVER_BIG_W/H = 672/378`、`COVER_SAVER_W/H = 480/270`、色彩资源 `success_green`
