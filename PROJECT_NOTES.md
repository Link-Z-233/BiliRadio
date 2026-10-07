# 项目备忘

四章登记：① 已知问题与技术债；② 已移除与禁用功能（含恢复线索）；③ 规划与预告；④ API 26 基线化。
本文件由 `KNOWN_ISSUES.md` 更名而来（git 历史保留），登记范围自 2026-10 实机反馈批次起扩展。

## 一、已知问题

### KI-3 列表「左滑删除」未实现

- **交互约定**：左滑露出「删除」按钮，**点击**执行删除（`ListItem.swipeAction({ end: { builder } })`），不做「滑过阈值直接删」。
- **待实现清单**：
  1. **首页订阅列表** [HomePage.ets](entry/src/main/ets/pages/HomePage.ets)：`ListItem` 位于 `LazyForEach`（登记 L365-367 已漂移，2026-10-07 实测 L309-313）；删除复用既有 `removeSub(row)`（含清剧集缓存、持久化、刷新列表）。
  2. **播放队列** [QueueSheet.ets](entry/src/main/ets/component/QueueSheet.ets)：`LazyForEach` + `ListItem`；删除可复用 `PlayerController.removeSelectedFromPlaylist([bvid])`（[PlayerController.ets](entry/src/main/ets/service/PlayerController.ets) L1028）；需处理与多选（长按 + 竖向滑动选择）手势的共存。
  3. ~~**播放历史** [SettingsPage.ets](entry/src/main/ets/pages/SettingsPage.ets) 的 `playHistoryPanel`~~ **已完成（play-history-progress 轮，2026-10-06）**：`playHistoryPanel` 已挂 `ListItem.swipeAction({ end: 删除按钮 builder })`，`HistoryDataSource.notifyDataDelete` 增量同步 LazyForEach；单条删除 API 为 `PlayerController.removePlayHistoryItem(bvid)`（splice + `playHistoryVersion++` + 异步写盘），`clearPlayHistory` 行为不变。
- **状态**：部分实现——播放历史项已完成（见上），首页订阅列表/播放队列两项仍待实现（仅登记）。

### KI-4 短链识别与解析（已修复：bili-link-recognize 轮，2026-10-07）

- **位置**：识别/抽取/解析逻辑集中至新增 [LinkResolver.ets](entry/src/main/ets/service/LinkResolver.ets)；[AddSubscriptionSheet.ets](entry/src/main/ets/pages/AddSubscriptionSheet.ets) 仅保留「抽取 → 判定 → 解析 → 分发」编排；[BiliService.ets](entry/src/main/ets/service/BiliService.ets) 原 `resolveShortUrl` 已删除。
- **原登记行号漂移修正**：短链判定原登记 L144，修复前实际已漂移至 L165；`resolveShortUrl` 原登记 L707-736，修复前实际已漂移至 L935-966（两处本轮均已移除/改写，原行号登记就此作废）。
- **修复说明**（对应原六条缺陷）：
  1. **前置抽取**（原 #2）：`extractBiliUrl` 在任何识别判断前，从分享文案抽取第一个 B 站域名（b23.tv / bili2233.cn / bilibili.com 及任意子域，忽略大小写，须带 http(s) 前缀）链接并清除尾随中英文标点；未抽到回退 trim 原文，短链与非短链分支统一使用清洗结果。
  2. **判定修正**（原 #1）：`isBiliShortLink` 按 host 精确判定（忽略大小写），补齐 bili2233.cn；无协议前缀的裸短链（如 `b23.tv/xxx`）自动补 `https://` 后处理。
  3. **重定向解析**（原 #3，2026-10-07 实机返修）：初版 `maxRedirects: 0` 直读 Location 方案在真机不可行——`@ohos.net.http` 的 `maxRedirects: 0` 实为「零配额」语义，首个 30x 即抛 2300047「重定向次数达到上限」，30x 响应拿不到（文档写「禁用重定向」但行为如此，实机实测）。改用 rcp（`@kit.RemoteCommunicationKit`）自动跟随重定向（`autoRedirect: true` + `maxAutoRedirects: 5`）后读 `Response.effectiveUrl` 作为落地目标——**引用 Bili23-Downloader**（https://github.com/Scighosts/Bili23-Downloader，src/util/parse/parser/b23.py 的 B23Parser + src/util/network/request.py 的 `ResponseType.REDIRECT_URL` → `str(response.url)`），与本仓解析链路同源；未重定向或仍落短链域名判「短链无效或已过期」（对应 B23Parser 的 `response==url` 判定）；目标须为 bilibili.com 域名且可被识别器分类；原 Location 逐跳迭代 / 相对地址补全 / 正文兜底逻辑随之退役。
  4. **错误分型**（原 #4）：`ShortLinkResult` 结果模型区分网络失败 / 超出跳数 / 无有效目标 / 目标无法识别四类结局，各自携带互不重复的中文提示，不再静默降级 `return shortUrl`。
  5. **目标覆盖**（原 #5）：`recognizeInput` 迁入 LinkResolver 并扩展 av 号 URL 形态（`bilibili.com/video/av{数字}`）、`m.bilibili.com/space/{uid}` 移动端空间、lists/seriesdetail/collectiondetail host 放宽为 bilibili.com 任意子域；短链 path 含视频号（如 `b23.tv/BV…`）时零网络短路直达视频。
  6. **缓存与专用超时**（原 #6）：会话级 LRU 缓存（模块级 Map + 插入序数组，容量 50，仅缓存成功结果，命中先删后插、零网络请求，不持久化）；专用超时 `Constants.SHORT_LINK_CONNECT_MS / SHORT_LINK_READ_MS = 8000ms`（通用 15s/30s 保留不动）。
  7. **输入保持**：解析成功不再回写输入框（原 `mainInput = resolved` 已删除，FR-010）。
- **配套 UX 修正（2026-10-07，随实机复核轮）**：
  1. **提示文案补全**：占位符缩短为「粘贴 B 站链接或 ID」（占位符不换行，长枚举在大字模式溢出）；完整能力枚举移至输入框下方常驻说明行「支持分享文案、短链、BV 号、av 号、UP 主 UID」（Text 可换行，任意缩放不溢出）；识别失败 toast 同步补「BV 号 / av 号」。
  2. **二级页返回按钮加大**：抽共享 `secondaryHeader` builder（收藏夹/合集与系列两视图共用），返回图标触控区由裸 16vp 扩至 40vp（图标 20 + padding 10 + 负 margin 抵消位移）。
  3. **系统返回支持**：`HomePage` 的 `bindSheet` 挂 `onWillDismiss`，`DismissReason.PRESS_BACK` 时经 `AddSheetBackHandler.requestBack()` 询问面板——二级视图在场则拦截关闭、动画退回一级；一级视图或下滑/关闭按钮/点遮罩路径正常关面板。
- **状态**：已修复（待实机复核 US1/US2）。

### KI-5 播放层 UI 冻结（已定位并修复：API 24 ModalPage 渲染管线挂载即断开）

- **现象**：播放层（`PlayerOverlay`）的标题/进度/播放图标停留在打开浮层时的快照，所有按钮按下后功能正常执行但 UI 无任何变化；±15s 按钮因 `isPrepared` 陈旧为 false 而不可见（a11y 树中缺席）。
- **证据（2026-10-05，MatePad Pro 11 模拟器 / HarmonyOS 6.1.1 API 24，三组对照实验）**：
  1. 模拟器全量重启后现象复现 → 排除「屏幕合成冻结」；
  2. `next()` 切到不同 bvid 且 hilog 确认 playing，浮层仍显示旧标题旧进度 → 排除「流停滞」；
  3. 同一 `PlayerController`/`emitUi` 广播下，**MiniPlayer 数据正确新鲜**（新标题已更新）→ 问题隔离为浮层组件特有。
- **与监听器累积的关系**：监听器累积（已随第 4 轮修复）可造成类似表现，但本次为进程内首次打开浮层（无陈旧监听器堆积）且 MiniPlayer 在浮层之前已正常收到广播，不能归因于监听器问题，故单独登记。
- **第 4 轮补充（2026-10，US1/US2 应用层加固）**：虽然根因未定论，本轮已落地多层应用层加固（抽屉 zIndex(100)、QueueDrawer 进出场改 animateTo 驱动、订阅退订+异常隔离+代际号）。**观察结论：仅在 API 24 平板复现，其余设备未见**；应用层加固未消除该问题。
- **第 5 轮最终定位（2026-10-06，MatePad Pro 真机 192.168.11.123，HarmonyOS 6.1.1 API 24）**：
  - **根因**：`bindContentCover`（ModalPage）内容组件在该设备上**挂载后渲染管线即断开**——hilog 实测三层异常：① 挂载后 10-21ms 收到伪 `aboutToDisappear`（浮层实际仍显示，探针日志实锤）；② 真关闭时 `aboutToDisappear` 反而**不触发**（无退订日志）；③ @State 更新与 `animateTo` 动画创建均正常执行但 ModalPage 表面**仅渲染首帧**（触摸命中走节点树仍有效，故「功能执行而 UI 冻结」）。
  - **排除链**：系统包损坏 ×（全量刷机后逐字复现）；animateTo 构建期调用 ×（aboutToAppear 延后修复无效）；订阅链路 ×（守卫+单槽覆盖后 listeners 保持 1、光晕动画正常创建，冻结依旧）。
  - **溯源**：`bindContentCover` 为 BiliRadio 自研引入（@efbc92f，2026-10-03 播放层改造），BiliMusic 原版 `PlayerPage` 为常规页面架构无此问题——KI-5 属自研回归而非上游继承。
- **修复（方案 B，2026-10-06）**：`Index.ets` 放弃 `bindContentCover`，改 **Stack 内条件渲染**承载播放层——`if (showPlayerOverlay) PlayerOverlay().expandSafeArea(SYSTEM, TOP+BOTTOM).transition(TransitionEffect.translate({y:'100%'}).animation(350ms Friction))`，生命周期与渲染管线回归常规路径（同 MiniPlayer/QueueDrawer 的健康通路）；expandSafeArea 复现 ModalPage 全窗口视觉，底部滑入滑出近似原 ModalTransition.DEFAULT 手感。**配套防御保留**：① PlayerOverlay `aboutToDisappear` 可见性守卫（`@StorageLink showPlayerOverlay`，浮层显示中跳过退订，兼作其他平台伪回调哨兵）；② PlayerController/SleepTimerController `subscribe` 同 owner 单槽覆盖（防漏退订累积）；③ aboutToAppear 中 `updateGlow` 延后一拍（消除构建期 animateTo 框架告警）。
- **验证（2026-10-06 真机）**：播放/暂停图标互换、进度条走动、开关浮层全部恢复正常；hilog 订阅退订完全对称（开→subscribe listeners=1，关→unsubscribe listeners=0），伪 `aboutToDisappear` 消失，无监听器累积。
- **遗留观察**：封面光晕呼吸效果（`updateGlow`，3200ms 往复）用户自最初构建从未观察到，可能亮色模式下不显眼或存在独立问题，登记后续单独检查。
- **状态**：已修复（方案 B 全平台生效，无需按设备分支）。

### KI-6 定时播放 / 睡眠定时「未经验证」

- **范围**：睡眠定时功能（倒计时归零暂停播放 + 提醒回调）实现完成，但**未经实机验证**。
- **位置**：入口为播放层 timer 按钮（`PlayerOverlay`）；控制器为 [SleepTimerController.ets](entry/src/main/ets/service/SleepTimerController.ets)（单例、墙钟零漂移倒计时、内存态不持久化）。
- **待验证点**：倒计时显示与归零暂停、后台/锁屏节流后切回校准、入口按钮状态联动。
- **状态**：实现完成、待实机验证；验证通过后移除本条目及 `SleepTimerController.ets` 文件头的 `[UNVERIFIED 2026-10]` 标注。

### KI-7 链接识别链路遗留问题（bili-link-recognize 轮走查发现，本轮范围外）

- **位置**：[LinkResolver.ets](entry/src/main/ets/service/LinkResolver.ets) `recognizeInput`（编号沿用特性走查记录）。
- **登记项**：
  1. **B3 系列默认类型歧义**：`lists` 路径无 `type=series` 参数时默认按合集（season）处理，实际可能为系列，订阅类型判定存在歧义。
  2. **B4 BV 优先级全文遮蔽**：BV 号全文扫描置于全部 URL 规则之前，含 BV 号的复合链接（如带 BV 参数的合集/收藏夹页）会被遮蔽误判为视频。
  3. **B5 fav 弱启发式**：收藏夹判定依赖 `(?:fid|media_id)=(\d+)` + 文本含 fav/collection/favlist 的弱启发式，非收藏夹页面出现同参数时存在误判可能。
  4. **B7 裸数字语义歧义**：纯数字输入一律按 UP 主 UID 处理，用户意图可能是 av 号/合集 ID 等，语义有歧义（现状维持 UID 优先）。
  5. **B8 BV 无合法性校验**：`BV[0-9A-Za-z]{10}` 仅匹配形态不校验合法性，伪 BV 号要进入网络请求后才失败。
  6. **C1 解析结果回写——已解决**：短链解析成功后的 `mainInput` 回写已随 bili-link-recognize 轮移除（FR-010），登记备查。
  7. **C2 动态/直播/watchlist 目标不识别**：`recognizeInput` 无动态（t.bilibili.com）/直播（live.bilibili.com）/watchlist 目标规则，短链解析到该类页面按「目标无法识别」分型提示（不再误播随机视频，但无法直达）。
- **状态**：未修复（仅登记；其中 C1 已解决）。

## 二、已移除与禁用功能

### REM-1 下载页（三文件移除）

- **提交**：@6d403dd（`feat: floating mini player capsule and right-side queue drawer`），配合 @382e789 流式边下边播改造。
- **移除文件**：`entry/src/main/ets/pages/DownloadsPage.ets`（320 行）、`entry/src/main/ets/service/DownloadManager.ets`（199 行）、`entry/src/main/ets/model/DownloadedSong.ets`（130 行），及 `router_map.json` 中 downloadsPage 路由条目。
- **原因**：改为流式边下边播（CDN 直链直推播放器）后，整段下载链路成为死代码；下载页入口与状态机全部失效。
- **恢复线索**：`git show 6d403dd` 可取三文件历史版本；若恢复需适配现流式缓存结构（`BiliService.cleanCache` 管理）与现路由表。

### REM-2 收藏夹 folders 页 / 列表同步 / 封面染色（移除）

- **提交**：@2050b84（`refactor: remove folders page, playlist sync and cover-tint dead code`）。
- **移除内容**：`FoldersPage.ets`（1108 行）与 `SelectedSeason.ets`（folders 页与列表同步状态）、`CoverAnalyzer.ets` / `ForegroundColor.ets` / `LightEffect.ets` / `LitButton.ets`（封面染色链路）。
- **原因**：三条完全解耦的死代码链——folders 页无任何入口可达；列表同步依赖的 SelectedSeason 状态无来源；封面染色被固定配色方案替代。
- **恢复线索**：`git show 2050b84`；收藏夹数据接口（`BiliService.fetchFavFolders`）仍在，恢复 folders 页只需重新接线路由与状态。

### DIS-1 首页下拉刷新（本轮禁用）

- **位置**：[HomePage.ets](entry/src/main/ets/pages/HomePage.ets)——`Refresh` 包裹层、`refreshing` 状态与 `manualRefresh()` 以注释块保留，注释头带 `[DISABLED 2026-10]` 标记。
- **原因**：实机反馈认为首页下拉刷新使用率低，与既有 `silentRefresh()`（新集徽标静默刷新）功能重叠，暂时禁用待产品定夺。
- **恢复步骤**：
  1. 从注释块恢复 `refreshing` 状态声明与 `manualRefresh()` 方法；
  2. 用 `Refresh` 组件重新包裹列表（`layoutWeight(1)` 移回 Refresh 内层的 List），恢复 `.onRefreshing` 链；
  3. 删除 `[DISABLED 2026-10]` 标记与本条目。
- **备注**：`silentRefresh()` 保留未动，新集徽标仍会静默刷新。

### DIS-2 独立「更多」页 MorePage（本轮移除）

- **本轮（2026-10）**：删除 `entry/src/main/ets/pages/MorePage.ets` 及 `router_map.json` 中 `morePage` 条目；首页右上角「更多」按钮改为直达 `settingsPage`。
- **原因**：更多页仅聚合「播放历史」「关于」两个二级入口，二者在设置页均有同款卡片，独立页面无存在必要。
- **恢复线索**：`git log --diff-filter=D -- entry/src/main/ets/pages/MorePage.ets` 定位删除提交后恢复文件，并在 `router_map.json` 重新登记 `morePage` 条目。

### REM-3 取消收藏历史（整链移除）

- **本轮（ux-feedback-round5，2026-10-07）**：移除「取消收藏后可找回」的本地历史记录整条链路；取消收藏操作本身仍即时生效，仅不再留痕。
- **移除内容**：`entry/src/main/ets/model/UnfavoriteRecord.ets`（模型文件已删除）；SettingsPage 侧历史面板全链（`showHistory`/`historyItems`/`historyVersion` 状态、`openHistory`/`formatRemovedAt`、`historyPanel` builder、设置页入口行及 `NavDestination.onBackPressed` 分支）；PlayerController 的 `unfavoriteHistory`/`pushHistory`/`refavoriteFromHistory`/`clearUnfavoriteHistory` 及取消收藏路径上的入史调用；AppStore 的 `loadUnfavoriteHistory`/`saveUnfavoriteHistory` 持久化；`Constants.AS_SHOW_HISTORY` 键。
- **原因**：实机反馈使用率极低，且与「清空队列」「播放历史」职责重叠；面板入口长期占据设置页空间。
- **恢复线索**：`git log --diff-filter=D -- entry/src/main/ets/model/UnfavoriteRecord.ets` 定位删除提交（ux-feedback-round5 轮），按上述移除内容反向恢复各调用点。
- **遗留数据**：老版本写入的 `unfavorite_history.json` 本轮不清理（应用不再读写，无功能影响）；若未来恢复该功能，旧文件数据仍可重新读取。

## 三、规划与预告

- **列表添加逻辑重构预告（US6 后续）**：源详情页「点单集」已改为仅该集入队播放；队列输入框「添加并播放」（`addByBv`）的入队行为后续还会改——计划从「加载并立即播放」调整为「追加进队列不打断当前播放」，落地后与「点单集」路径统一收敛。
- **403 首次添加根因修复（延后）**：首次添加订阅偶发 403/风控拦截，本轮仅做了日志观察（`BiliService` 全链路钩子 + 设置页日志面板，见 US9），待实机日志积累、锁定风控触发模式后针对性修复（候选方向：WBI 签名覆盖面 / buvid 预热策略）。
- **点赞 / 投币 / 收藏**：依赖登录态与 csrf，交互形态待定，两轮内未排期。
- **播放历史云端同步**：本地字段/单位对齐已完成（play-history-progress 轮：`PlayHistoryItem` 补齐 viewAt/progress/duration/cid，秒级单位对齐 B 站 `view_at`/`progress` 语义，-1=看完；`HistoryMapper` 预留 `toBiliHistory`/`fromBiliHistory` 映射边界，本轮零网络请求），云端同步（登录态下心跳上报/历史拉取合并）待后续。
- **audio 三元组优先级限制**：播控中心/后台卡片展示元数据依赖 audio 三元组等系统侧信息优先级策略，B 站侧字段缺失时标题/作者/封面可能展示不全，属系统与上游数据限制，暂不做适配。
- **无图模式覆盖面扩展（ux-feedback-round5 范围外）**：本轮（2026-10-07）已将无图模式（原「省流量模式」，设置页分组现名「无图与网络设置」）扩展至播放列表条目封面（QueueSheet）与系统播控（AVSession/MediaSession，开关翻转后经 `PlayerController.refreshMediaSessionMetadata()` 强制重发当前曲目元数据）；以下位置仍不判无图模式、保持现状，待后续轮次统一：① 首页订阅列表行封面（HomePage）；② 订阅源详情页头图与列表项（SourcePage）；③ 添加订阅面板 UP 头像/合集封面（AddSubscriptionSheet——该场景封面用于确认订阅目标，刻意不省图）。另：随「取消收藏历史」移除而遗留的 `unfavorite_history.json` 本轮不清理，应用不再读取即无功能影响。

## 四、API 26 基线化

- **目标**：工程兼容基线 SDK 升到 API 26 后，移除全部 `[API24-COMPAT]` 守卫（全局检索该标记，按本章统一处理），并复核播控中心按钮在低版本设备上的兼容策略。
- **现状**：`build-profile.json5` 的 `targetSdkVersion` 已为 `26.0.0`，`compatibleSdkVersion` 仍为 `6.1.1(24)`——基线尚未升级，守卫继续保留。
- **守卫清单**（基线化时逐处移除，新增守卫须同步登记到此）：
  1. [MediaSession.ets](entry/src/main/ets/service/MediaSession.ets) L42：`setMediaCenterControlType`（API 26 新增接口，API<26 设备运行时抛 TypeError）——try/catch 静默降级，低版本播控中心不显示快进/快退按钮，不影响播放/暂停/上一首/下一首。
