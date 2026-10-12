# 项目备忘

四章登记：① 已知问题与技术债；② 已移除与禁用功能（含恢复线索）；③ 规划与预告；④ API 26 基线化。
本文件由 `KNOWN_ISSUES.md` 更名而来（git 历史保留），登记范围自 2026-10 实机反馈批次起扩展。

## 一、已知问题

### KI-3 列表「左滑删除」（三处全部完成）

- **交互约定**：左滑露出「删除」按钮，**点击**执行删除（`ListItem.swipeAction({ end: { builder } })`），不做「滑过阈值直接删」。
- **完成记录**：
  1. **播放历史** [SettingsPage.ets](entry/src/main/ets/pages/SettingsPage.ets) `playHistoryPanel`（play-history-progress 轮，2026-10-06）：`HistoryDataSource.notifyDataDelete` 增量同步；单条删除 `PlayerController.removePlayHistoryItem(bvid)`。
  2. **播放队列** [QueueSheet.ets](entry/src/main/ets/component/QueueSheet.ets)（queue-redesign 轮，2026-10-10）：`ListItem` 挂 `swipeAction`（样式对齐 `historyDeleteAction`），删除调 `removeSelectedFromPlaylist([bvid])`（删除当前条目时既有自动切播语义保留）；与多选长按手势经平台仲裁共存（横向 swipe 与竖向连选不同轴）。
  3. **首页订阅列表** [HomePage.ets](entry/src/main/ets/pages/HomePage.ets)（debt-cleanup 轮，2026-10-11）：新增 `subDeleteAction` builder（样式逐字段对齐 `historyDeleteAction`）+ `ListItem.swipeAction({ end })`，点击复用 `removeSub(row)`（含清剧集缓存、持久化、刷新列表）；模拟器验证 PASS（T017）。
- **状态**：三处全部完成；真机复测通过后关闭本条目（T024 待办）。
- **升级（v0.3-bugfix-round2，2026-10-12）**：三处左滑统一升级 `SwipeActionItem` 双触发——点垃圾桶/滑过阈值均进二次确认弹窗，取消经 `ListScroller.closeAllSwipeActions()` 复位收起；交互约定由「点击直删」演进为「双触发 + 二次确认」。

### KI-4 短链识别与解析（已修复：bili-link-recognize 轮，2026-10-07）

- **位置**：识别/抽取/解析逻辑集中至新增 [LinkResolver.ets](entry/src/main/ets/service/LinkResolver.ets)；[AddSubscriptionSheet.ets](entry/src/main/ets/pages/AddSubscriptionSheet.ets) 仅保留「抽取 → 判定 → 解析 → 分发」编排；[BiliService.ets](entry/src/main/ets/service/BiliService.ets) 原 `resolveShortUrl` 已删除。
- **修复要点**（对应原六条缺陷）：
  1. **前置抽取**：`extractBiliUrl` 在任何识别判断前抽取第一个 B 站域名链接（b23.tv / bili2233.cn / bilibili.com 任意子域，须带 http(s)）并清尾随标点；未抽到回退 trim 原文。
  2. **判定修正**：`isBiliShortLink` 按 host 精确判定，补齐 bili2233.cn；裸短链自动补 `https://`。
  3. **重定向解析**（2026-10-07 实机返修）：`@ohos.net.http` 的 `maxRedirects: 0` 实为「零配额」语义（首个 30x 抛 2300047），改 rcp（`@kit.RemoteCommunicationKit`）`autoRedirect` + `maxAutoRedirects: 5` 后读 `Response.effectiveUrl`——引用 Bili23-Downloader 同源链路；未重定向或仍落短链域名判「短链无效或已过期」。
  4. **错误分型**：`ShortLinkResult` 区分网络失败 / 超出跳数 / 无有效目标 / 目标无法识别四类结局，各自携带互不重复的中文提示，不再静默降级。
  5. **目标覆盖**：`recognizeInput` 迁入 LinkResolver 并扩展 av 号 URL、`m.bilibili.com/space/{uid}`、lists/seriesdetail/collectiondetail host 放宽任意子域；短链 path 含视频号零网络短路直达。
  6. **缓存与专用超时**：会话级 LRU 缓存（容量 50，仅缓存成功，不持久化）；专用超时 `Constants.SHORT_LINK_CONNECT_MS / SHORT_LINK_READ_MS = 8000ms`。
  7. **输入保持**：解析成功不再回写输入框（FR-010）。
- **配套 UX 修正**：占位符缩短 + 输入框下方常驻说明行（「支持分享文案、短链、BV 号、av 号、UP 主 UID」）；二级页返回按钮触控区扩至 40vp；`bindSheet` 挂 `onWillDismiss` 支持系统返回（二级视图在场拦截、动画退回一级）。
- **状态**：已修复；debt-cleanup 轮 US3 模拟器验证短链零回归 PASS（T018）。

### KI-5 播放层 UI 冻结（已修复：API 24 ModalPage 渲染管线挂载即断开）

- **现象**：播放层（`PlayerOverlay`）标题/进度/播放图标停留在打开时快照，按钮功能正常但 UI 无变化。
- **根因**（2026-10-06，MatePad Pro 真机 API 24 定位）：`bindContentCover`（ModalPage）内容组件在该设备**挂载后渲染管线即断开**——挂载后 10-21ms 收到伪 `aboutToDisappear`、真关闭时反而不触发、@State/animateTo 正常执行但仅渲染首帧。自研引入（@efbc92f，2026-10-03 播放层改造），非上游继承。其余设备未见。
- **修复（方案 B）**：`Index.ets` 放弃 `bindContentCover`，改 **Stack 内条件渲染**——`if (showPlayerOverlay) PlayerOverlay().expandSafeArea(SYSTEM, TOP+BOTTOM).transition(TransitionEffect.translate({y:'100%'}).animation(350ms Friction))`。**配套防御保留**：① PlayerOverlay `aboutToDisappear` 可见性守卫；② PlayerController/SleepTimerController `subscribe` 同 owner 单槽覆盖（防漏退订累积）；③ `updateGlow` 延后一拍（消除构建期 animateTo 告警）。
- **遗留观察**：封面光晕呼吸效果（`updateGlow`，3200ms 往复）用户从未观察到，可能亮色模式下不显眼，登记后续单独检查。
- **状态**：已修复（方案 B 全平台生效）；API 26 基线化后 API 24/25 设备已不受支持。

### KI-6 定时播放 / 睡眠定时「部分验证」

- **范围**：睡眠定时（倒计时归零暂停 + queue-redesign 轮新增「播完暂停」模式），实机验证欠账。
- **位置**：入口为播放层 timer 按钮（`PlayerOverlay` 定时面板）；控制器为 [SleepTimerController.ets](entry/src/main/ets/service/SleepTimerController.ets)（单例、墙钟零漂移倒计时、内存态不持久化；`SleepTimerMode` 三态 NONE / COUNTDOWN / PLAY_TO_EOF）。
- **待验证点**：倒计时显示与归零暂停、后台/锁屏节流后切回校准、入口按钮状态联动；播完暂停三步（面板选「播完暂停」→ 当前条目播完停原条目暂停不切歌 → 手动续播从头重播/手动切歌恢复正常）、与倒计时单选互斥（后选取代先选）、触发时不弹「计时已结束」弹窗。
- **状态**：debt-cleanup 轮模拟器验证（T020）——倒计时归零（60.1s 精确）/播完暂停/模式互斥/取消定时 PASS；**切后台校准环境受限未验**（devecocli 无 home 键/后台化模拟）。真机复测（[verification-report.md](spec/debt-cleanup/verification-report.md) §4 US5）通过后关闭本条目并移除 `SleepTimerController.ets` 文件头 `[UNVERIFIED 2026-10]` 标注。

### KI-7 链接识别链路遗留问题

- **位置**：[LinkResolver.ets](entry/src/main/ets/service/LinkResolver.ets) `recognizeInput`（编号沿用特性走查记录）。
- **登记项**：
  1. **B3 系列默认类型歧义**：`lists` 路径无 `type=series` 参数时默认按合集（season）处理，实际可能为系列。
  2. ~~**B4 BV 优先级全文遮蔽**~~ **已修复（debt-cleanup 轮，2026-10-11）**：BV 全文扫描移至全部 URL 规则之后、裸数字之前（含 BV 参数的复合链接不再被遮蔽误判）。
  3. ~~**B5 fav 弱启发式**~~ **已修复（debt-cleanup 轮，2026-10-11）**：收紧为「URL path 含 `favlist`/`medialist` 且带 `fid=`/`media_id=` 参数」，合法收藏夹形态不漏判。
  4. **B7 裸数字语义歧义**：纯数字输入一律按 UP 主 UID 处理（现状维持 UID 优先）。
  5. **B8 BV 无合法性校验**：仅匹配形态不校验，伪 BV 号要进入网络请求后才失败。
  6. **C1 解析结果回写——已解决**：短链解析成功后的回写已随 bili-link-recognize 轮移除（FR-010）。
  7. **C2 动态/直播/watchlist 目标不识别**：该类页面按「目标无法识别」分型提示（不再误播随机视频，但无法直达）。
- **状态**：B4/B5 已修复（模拟器验证 PASS，T018）；B3/B7/B8/C2 维持登记。

### KI-8 首页订阅行 latestTitle/newCount 陈旧（已修复：appsign-up-fetch 轮，2026-10-08）

- **根因**：[HomePage.ets](entry/src/main/ets/pages/HomePage.ets) `LazyForEach` 键值生成器返回恒定 `row.sub.id` → 框架复用旧组件、不重跑 builder → 行内字幕与 newCount 徽标停在首次挂载值。
- **修复**：键值改为 `` `${row.sub.id}_${row.latestTitle}_${row.newCount}` ``，字段变化即重建该行，兼修 newCount 徽标会话内不清零。
- **遗留**：活体判别待未来新投稿事件自然观察（机制由键值→重建语义保证）。

### KI-9 APP/Web 链页界不对齐（已修复：engineering-refactor 轮 1，2026-10-11）

- **现象**：APP 签名链 20 条/页（服务端钳制）vs Web 退避链 30 条/页，链路切换（降级/回切）时页界不对齐可能漏条目；现有 bvid 去重兜底。
- **修复**：Web 链 `fetchUpVideosViaWeb` 请求 `ps` 降为 `Constants.UP_PAGE_SIZE=20`，翻页记账 `olderPageSize()` UP 分支统一引用常量（[BiliService.ets](entry/src/main/ets/service/BiliService.ets) / [SourcePage.ets](entry/src/main/ets/pages/SourcePage.ets)）。
- **遗留**：降级衔接翻页走查待真机（[verification-report.md](spec/debt-cleanup/verification-report.md) §4 US7）。

### KI-10 屏幕常亮疑问（销项，v0.3-bugfix-round2 轮，2026-10-12）

- **现象**：v0.3-bugfix-round1 修复后实机反馈「屏幕保持常亮」疑问（v0.3-bugfix-round2 E 项）。
- **结论**：全代码库无 `keepScreenOn` 调用，无代码改动；实测常亮为系统层行为，最可能是开发者选项「不锁定屏幕」（USB 调试充电时保持唤醒）触发（plan.md D10）。
- **验证方式**：拔掉 USB 线重测；若仍常亮再 reopen 本条目排查。

## 二、已移除与禁用功能

### REM-1 下载页（三文件移除）

- **提交**：@6d403dd（`feat: floating mini player capsule and right-side queue drawer`），配合 @382e789 流式边下边播改造。
- **移除文件**：`entry/src/main/ets/pages/DownloadsPage.ets`（320 行）、`entry/src/main/ets/service/DownloadManager.ets`（199 行）、`entry/src/main/ets/model/DownloadedSong.ets`（130 行），及 `router_map.json` 中 downloadsPage 路由条目。
- **原因**：改为流式边下边播（CDN 直链直推播放器）后，整段下载链路成为死代码。
- **恢复线索**：`git show 6d403dd` 可取三文件历史版本；若恢复需适配现流式缓存结构（`BiliService.cleanCache` 管理）与现路由表。

### REM-2 收藏夹 folders 页 / 列表同步 / 封面染色（移除）

- **提交**：@2050b84（`refactor: remove folders page, playlist sync and cover-tint dead code`）。
- **移除内容**：`FoldersPage.ets`（1108 行）与 `SelectedSeason.ets`、`CoverAnalyzer.ets` / `ForegroundColor.ets` / `LightEffect.ets` / `LitButton.ets`（封面染色链路）。
- **原因**：三条完全解耦的死代码链——folders 页无入口可达；列表同步依赖的 SelectedSeason 状态无来源；封面染色被固定配色方案替代。
- **恢复线索**：`git show 2050b84`；收藏夹数据接口（`BiliService.fetchFavFolders`）仍在，恢复 folders 页只需重新接线路由与状态。

### DIS-1 首页下拉刷新（本轮禁用）

- **位置**：[HomePage.ets](entry/src/main/ets/pages/HomePage.ets)——`Refresh` 包裹层、`refreshing` 状态与 `manualRefresh()` 以注释块保留，注释头带 `[DISABLED 2026-10]` 标记。
- **原因**：实机反馈使用率低，与 `silentRefresh()`（新集徽标静默刷新）重叠，暂时禁用待产品定夺。
- **恢复步骤**：① 从注释块恢复 `refreshing` 声明与 `manualRefresh()`；② 用 `Refresh` 重新包裹列表（`layoutWeight(1)` 移回内层 List），恢复 `.onRefreshing` 链；③ 删除 `[DISABLED 2026-10]` 标记与本条目。
- **备注**：`silentRefresh()` 保留未动。

### DIS-2 独立「更多」页 MorePage（本轮移除）

- **本轮（2026-10）**：删除 `entry/src/main/ets/pages/MorePage.ets` 及 `router_map.json` 中 `morePage` 条目；首页右上角「更多」按钮改为直达 `settingsPage`。
- **原因**：更多页仅聚合「播放历史」「关于」两个二级入口，二者在设置页均有同款卡片，无存在必要。
- **恢复线索**：`git log --diff-filter=D -- entry/src/main/ets/pages/MorePage.ets` 定位删除提交后恢复，并在 `router_map.json` 重新登记 `morePage` 条目。

### REM-3 取消收藏历史（整链移除）

- **本轮（ux-feedback-round5，2026-10-07）**：移除「取消收藏后可找回」的本地历史记录整条链路；取消收藏操作本身仍即时生效，仅不再留痕。
- **移除内容**：`entry/src/main/ets/model/UnfavoriteRecord.ets`（已删除）；SettingsPage 侧历史面板全链（`showHistory`/`historyItems`/`historyVersion`、`openHistory`/`formatRemovedAt`、`historyPanel` builder、入口行及 `onBackPressed` 分支）；PlayerController 的 `unfavoriteHistory`/`pushHistory`/`refavoriteFromHistory`/`clearUnfavoriteHistory` 及入史调用；AppStore 的 `loadUnfavoriteHistory`/`saveUnfavoriteHistory`；`Constants.AS_SHOW_HISTORY` 键。
- **原因**：实机反馈使用率极低，与「清空队列」「播放历史」职责重叠。
- **恢复线索**：`git log --diff-filter=D -- entry/src/main/ets/model/UnfavoriteRecord.ets` 定位删除提交，按上述移除内容反向恢复各调用点。
- **遗留数据**：老版本写入的 `unfavorite_history.json` 不清理（应用不再读写，无功能影响）；若未来恢复，旧文件数据仍可读取。

### REM-4 无图模式开关（全链移除）

- **本轮（debt-cleanup，2026-10-11）**：移除「无图模式」开关及其全部生效分支；封面加载策略收敛为「永远有图 + CDN 尺寸分档（缩略 240 档/大图 672×378/省流 480×270）+ 网络态自动降档」，尺寸分档与降档行为零回退。
- **移除内容（6 文件 8 处）**：`Constants.KEY_DATA_SAVER` 键（[Constants.ets](entry/src/main/ets/service/Constants.ets)）；设置页开关行与 `dataSaver` 状态（[SettingsPage.ets](entry/src/main/ets/pages/SettingsPage.ets)，随行移除 `refreshUi()`/`refreshMediaSessionMetadata()` 调用，方法本体保留）；播控 `refreshMediaSessionMetadata()` 整方法与 2 处 `dataSaver ? '' : cover` 读取点（[PlayerController.ets](entry/src/main/ets/service/PlayerController.ets)）；播放层 `trackCover`/`ownerFace` 置空分支（[PlayerOverlay.ets](entry/src/main/ets/pages/PlayerOverlay.ets)）；迷你条封面置空分支（[MiniPlayer.ets](entry/src/main/ets/component/MiniPlayer.ets)）；队列 `dataSaverOn` 状态/读取/渲染分支（[QueueSheet.ets](entry/src/main/ets/component/QueueSheet.ets)）。MediaSession 空封面守卫保留（服务无封面条目，非无图模式专属）。
- **原因**：图片占总流量 <2-5%（音频流主导），尺寸分档 + 网络态降档已在，开关边际收益可忽略；且覆盖不全（首页/源页/添加面板不接开关）造成功能名不副实。2026-10-11 用户决策删除。
- **恢复线索**：`git log -S KEY_DATA_SAVER -- entry/src/main/ets/service/Constants.ets` 定位删除提交；恢复须重接设置页开关行与上述 6 处生效分支。
- **遗留数据**：老版本写入的 `dataSaver` 持久化值不清理不读取（先例：`unfavorite_history.json`）。

## 三、规划与预告

- **R9 反馈轮（ux-feedback-round9，2026-10-10）——debt-cleanup 轮模拟器全场景 PASS（T019），真机复核后销项**：四项修复——①队列容器由右侧抽屉改底部弹出面板（QueueDrawer 全宽 65% 高、Y 轴 translate，仍为 Stack 条件渲染非系统 sheet，KI-5 规避不变）；②面板背景近实底（base `#F2FFFFFF` / dark `#F01E1E22`）；③队列列表 `alwaysEnabled` 过冲 + 双向 EdgeHint；④时长未知条目（duration=0）第二行只显示 UP 主名不渲染 00:00。queue-redesign 欠账：T031 部署已销（T015）、T032 US2/US4/US6 模拟器 PASS、US7 版本号项过时关闭。

- **R10 反馈轮（ux-feedback-round10，2026-10-10）——debt-cleanup 轮模拟器五场景 PASS（T021），真机复核后销项**：三项修复——①小白条沉浸（Index Navigation 包裹层去掉 `bottom: navBarHeight` padding，设置页/日志页/首页/订阅页内容延伸绘制至小白条后方并各自补偿避让，四页补 `@StorageProp navBarHeight`）；②隐藏迷你播放条穿透修复（Index 命中测试 `HitTestMode.None`→`BLOCK_DESCENDANTS`——SDK 实测 None 不阻止子节点命中是原 bug 根因）；③日志页底部空白（`AS_MINI_PLAYER_VISIBLE` 上报移交 Index，消费方避让随真实显隐变化）。顺带销项：R8 hilog DEBUG 门控（9be0b01，见下）。

> **✅ 已实现（9be0b01，随 R8 落地；本条为销项登记）：`Logger` 的 hilog 双写由 DEBUG 模式门控——默认关闭，绝不无条件向 hilog 总线写业务日志。** 开启入口 = 关于页图标三连击（tap 3 次触发，`Constants.DEBUG_TAP_WINDOW_MS = 2000`）；debug 模式开启期间 `Logger.log()` 才同步向 hilog 输出（`Constants.LOG_DOMAIN`/`LOG_TAG`，双写须用 info 级——API 24 设备 D 级被全局过滤不落缓冲，见 [Logger.ets](entry/src/main/ets/service/Logger.ets) L67-68 `ponytail:` 标注）；关闭或重启后恢复仅落盘+内存；持久化经 `Constants.KEY_DEBUG_MODE`。**任何后续改造不得绕过此门控。**

- **源页刷新无反馈假象（产品决策待定）**：刷新前后内容相同无可视指示、易误判按钮失效（appsign-up-fetch 轮 US2 首验 FAIL 即此假象——刷新实际成功、cursor 已重建，但列表无可视变化）；候选：加载动画或轻提示。

- **403 首次添加根因修复（延后）**：首次添加订阅偶发 403/风控拦截，仅日志观察（`BiliService` 全链路钩子 + 设置页日志面板），待实机日志锁定触发模式（候选：WBI 签名覆盖面 / buvid 预热策略）。
  - **实机结论（2026-10-07/08）**：UP 投稿 APP 端点（spaceArchive BiliDroid 形态）裸 UA 恒 **-400**（PiliPlus 同端点实际经 AccountManager 拦截器携带登录 cookie）；Web 端点单发在风控期必 **-799**；唯一可靠链 = **Web 三轮 buvid 指数退避**（直连→WBI 签名）。AppSign 接入后（TV appkey `dfca71928277209b`，[AppSigner.ets](entry/src/main/ets/service/AppSigner.ets) MD5 键序签名）**-400 消失**——签名链头页 + cursor 翻页均一页恰 1 请求，81 条触底无重复无跳空，签名链故障时 Web 退避链无缝降级。实测要点：响应为 `data.item[]`（非 `data.list.vlist`）、视频链 `data.next` 恒空（翻页语义 = 纯 aid 锚点，`fetchUpVideosOlder` 即此形态）、服务端将 ps 钳制为 20（请求 30）。
  - **防连发现状**：endArmed 手势触发权已移除（ux-feedback-round6 轮，2026-10-09），防链式连发由 `loadingOlder` + `canLoadOlder` 两道门槛 + 3 秒失败冷却（`Constants.LOAD_OLDER_FAIL_COOLDOWN_MS`）承担；若降级链再遇 403 风暴按需恢复 endArmed。

- **点赞 / 投币 / 收藏**：依赖登录态与 csrf，交互形态待定，未排期。
- **播放历史云端同步**：本地字段/单位对齐已完成（play-history-progress 轮：`PlayHistoryItem` 补齐 viewAt/progress/duration/cid，秒级单位对齐 B 站 `view_at`/`progress` 语义，-1=看完；`HistoryMapper` 预留 `toBiliHistory`/`fromBiliHistory` 映射边界，零网络请求）；云端同步（登录态下心跳上报/历史拉取合并）待后续。
- **audio 三元组优先级限制**：播控中心/后台卡片元数据依赖系统侧信息优先级策略，B 站侧字段缺失时展示可能不全，属系统与上游数据限制，暂不适配。
- **订阅源导出导入**（ux-feedback-round6 轮登记，2026-10-09）：导出载体（本地 JSON 文件 / 分享文本）与去重合并策略待产品决策。
- **关于页文案优化**（ux-feedback-round6 轮登记，2026-10-09）：方向待定。

- **模拟器验证终止与 debt-cleanup 验证状态（2026-10-11）**：debt-cleanup 轮验证轮（T014-T025）在 T022/US7 即将开始时模拟器卡死（无响应）；用户决策：**不再进行模拟器验证，改为用户真机实测后反馈**（后续轮次验证一律真机）。模拟器已验项 PASS 记录（US2/US3/US4/US6 全过、US5 大部、US1 部分）与 **37 条真机复测清单**见 [verification-report.md](spec/debt-cleanup/verification-report.md)；未完成项（US1 播放层大封面、US5 切后台校准、US7 降级走查、US8 深浅色走查、T024 销项、T025 关机）在真机复测通过前不销项。

- **工程重构（engineering-refactor，2026-10-11）US1-US3 已落地、US4 产出路线图**：①**US1 翻页页界对齐**——KI-9 销项（见 §一 KI-9；降级衔接走查欠真机）；②**US2 UI 令牌化**——14 个 UI 文件 555 处圆角/字号/间距/色彩字面量归一为 `Constants.TOKEN_*`（数值不变），覆盖率 97%，豁免登记 [token-exemptions.md](spec/engineering-refactor/token-exemptions.md)；结构组件化（T023）因「数值不变」下空态字号 14/15/16 并存不可归一，与观感收敛一并列远期待产品确认；③**US3 模块边界契约化**——契约落盘 [architecture-boundary.md](spec/engineering-refactor/architecture-boundary.md)，依赖审计零违规（service→model、pages→service/model、Constants 零业务依赖）；上帝对象（PlayerController/BiliService/SettingsPage）登记不拆分；④**US4 V2 迁移路线图**——逐文件清单与批次拆解落盘 [v2-migration-roadmap.md](spec/engineering-refactor/v2-migration-roadmap.md)，批次 1（模型层）已实施（2026-10-11：BiliVideo/PlayHistoryItem/Subscription/Season/FavFolder/AudioTrack 六类 `@ObservedV2`+`@Trace`，AudioQuality/ResolvedAudio/QualityTier 无可观察实体不迁），批次 2-4 待续；⑤API 26 基线化见 §四。版本 0.3.0/3000；欠账：T013 降级走查、深浅色/主题色全页走查——均待真机。

- **V2 迁移整体完结（2026-10-11）**：批次 3（七页面）+ 批次 4（全局键/挂键组件）合并一次变更实施——新建 `V2State.ets` 包装类（BoolState/NumState/StrState + connect helpers）承接 `AS_*` 键，`KEY_*`（AppStore preferences）保留不动；**顺带修复既有 crash**：`PlayerOverlay.ets:1336` `currentOffset()` 浮层刚挂载时运行时返回 undefined（类型上不可空）→ pan 下滑关闭手势崩溃，防御判空（批次 1 与本轮部署各复现一次，修复后回归无复现）。批次 2 组件并入或免迁；**4.5 审计纠错**：PlayerController 为零装饰器纯类（手动 `subscribe`/`emitUi` 广播 + 版本计数，四个消费方 `syncFrom` 拷贝 `@Local`），git 全历史 `-S` 检索零命中「@Observed+@Track」，经用户确认按 YAGNI 关闭无需迁移；**V2 迁移路线图整体完结**。

## 四、API 26 基线化

- **✅ 已完成（engineering-refactor 实施轮 1，2026-10-11）**：`compatibleSdkVersion` 升至 `26.0.0`（T004）；`[API24-COMPAT]` 守卫标记全局清零（T005，唯一处 [MediaSession.ets](entry/src/main/ets/service/MediaSession.ets) 已移除，`setMediaCenterControlType` 防御性 try/catch 保留）；版本号升至 0.3.0/3000（T006）。API 24/25 设备自本轮起不再受支持。
- **守卫清单已清空**（基线化完成，源码全局检索 `[API24-COMPAT]` 零命中）；新增守卫须同步登记到此。
