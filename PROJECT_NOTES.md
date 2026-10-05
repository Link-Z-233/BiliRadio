# 项目备忘

三章登记：① 已知问题与技术债；② 已移除与禁用功能（含恢复线索）；③ 规划与预告。
本文件由 `KNOWN_ISSUES.md` 更名而来（git 历史保留），登记范围自 2026-10 实机反馈批次起扩展。

## 一、已知问题

### KI-1 `PlayerController.subscribe` 无退订，监听会累积

- **位置**：[entry/src/main/ets/service/PlayerController.ets](entry/src/main/ets/service/PlayerController.ets) 的 `subscribe(fn)`。
- **现象**：`subscribe(fn)` 只把回调 `push` 进 `uiListeners`，没有对应的退订接口；且去重判断 `this.uiListeners.indexOf(fn) < 0` 因每次传入的是**新闭包**（函数引用不同）而永不命中，于是**每次订阅都会新增一个监听**。
- **影响**：共 4 处订阅——`MiniPlayer`（常驻）、`QueueSheet`、`PlayerOverlay`、`SettingsPage`。后三者都是「打开时挂载、关闭时卸载」的部件，均在 `aboutToAppear` 中订阅、`aboutToDisappear` 中不解除，反复打开会让 `uiListeners` 持续增长；随后每次播放进度/状态更新（`emitUi`）都会回调这些**已失效**的闭包，造成性能浪费，且访问已销毁组件的状态存在异常风险。
- **建议修复**：
  1. 给 `PlayerController` 增加 `unsubscribe(fn: () => void)`（或让 `subscribe` 返回订阅令牌），并在各订阅组件的 `aboutToDisappear` 中解除订阅；或
  2. 让订阅方持有**同一函数引用**（而非每次新建闭包），以便现有 `indexOf` 去重逻辑生效。
- **状态**：**已修复（2026-10 第 4 轮，US2）**。`subscribe(fn, owner?)` 改为返回退订闭包，`MiniPlayer`/`QueueSheet`/`PlayerOverlay`/`SettingsPage` 四处调用方均持有句柄并在 `aboutToDisappear` 中调用（`PlayerOverlay` 为此新增了原本缺失的 `aboutToDisappear`）；同时 `emitUi` 对每个监听器单独 try/catch（异常 hilog 警告 + Logger 'player' 记录，不中断广播循环），订阅/退订生命周期带调用方标识写入 Logger。配套修复：`playIndex` 进入时重置 `lastEmittedSec` 并取消挂起的 seekBy 防抖、`AudioPlayer` 实例代际号杜绝旧实例残余事件串扰、`PlayerOverlay.syncFrom` 切剧瞬间复位 `isSeeking`。同型的 KI-2（SleepTimerController）见下条，仍待办。

### KI-2 `SleepTimerController.subscribe` 无退订（与 KI-1 同型）

- **位置**：[entry/src/main/ets/service/SleepTimerController.ets](entry/src/main/ets/service/SleepTimerController.ets) 的 `subscribe(fn)`。
- **现象**：同样是只 `push` 回调、**没有 `unsubscribe`**；去重判断 `this.listeners.indexOf(fn) < 0` 因每次传入**新闭包**（函数引用不同）而永不命中，于是**每次订阅都会新增一个监听**。
- **影响**：目前**仅** `PlayerOverlay` 的 `aboutToAppear` 订阅它，而播放层是「打开时挂载、关闭时卸载」的 `bindContentCover` 内容，因此**每次打开播放层都会新增一个永不解除的监听**。睡眠定时活动期间 `emitUi` 每秒触发一次，会回调大量**已销毁组件**的 `syncSleepTimer()`，造成无谓开销与内存持续增长（触发频率低于 KI-1，仅在睡眠定时开启时明显）。
- **建议修复**：比照 KI-1——让 `subscribe` 返回订阅 id 并新增 `unsubscribe(id)`，`PlayerOverlay` 在 `aboutToDisappear` 中退订。
- **状态**：未修复（仅登记）。

### KI-3 列表「左滑删除」未实现

- **交互约定**：左滑露出「删除」按钮，**点击**执行删除（`ListItem.swipeAction({ end: { builder } })`），不做「滑过阈值直接删」。
- **待实现清单**：
  1. **首页订阅列表** [HomePage.ets](entry/src/main/ets/pages/HomePage.ets)：`ListItem` 位于 `LazyForEach`（L365-367）；删除复用既有 `removeSub(row)`（含清剧集缓存、持久化、刷新列表）。
  2. **播放队列** [QueueSheet.ets](entry/src/main/ets/component/QueueSheet.ets)：`LazyForEach` + `ListItem`；删除可复用 `PlayerController.removeSelectedFromPlaylist([bvid])`（[PlayerController.ets](entry/src/main/ets/service/PlayerController.ets) L1028）；需处理与多选（长按 + 竖向滑动选择）手势的共存。
  3. **播放历史** [SettingsPage.ets](entry/src/main/ets/pages/SettingsPage.ets) 的 `playHistoryPanel`：`LazyForEach` + `ListItem`（L835-863）；`PlayerController` 目前只有 `clearPlayHistory()`（L918），**缺单条删除 API**，需新增（如按 index）并写回 `AppStore.savePlayHistoryFile`。
- **状态**：未实现（仅登记）。

### KI-4 短链识别与解析待优化

- **位置**：[AddSubscriptionSheet.ets](entry/src/main/ets/pages/AddSubscriptionSheet.ets) L144 的短链判定；[BiliService.ets](entry/src/main/ets/service/BiliService.ets) L707-736 的 `resolveShortUrl`。
- **现象/不足**：
  1. **只认 `b23.tv` 且区分大小写**：`trimmed.indexOf('b23.tv') >= 0` 命中不了 `B23.TV` 等大小写变体，也不识别 `bili2233.cn` 等其它 B 站短链域名，且不校验是否带 `http(s)://` 前缀。
  2. **不从文本抽取 URL**：B 站分享文案常形如「【标题】 https://b23.tv/xxxx …」，现实现把整段文本直接当作 URL 去请求，导致解析失败；应先从文本用正则抽取 `https?://(?:b23\.tv|bili2233\.cn)/\S+` 再请求。
  3. **不读重定向 Location**：`resolveShortUrl` 走 GET 后在**响应正文**里正则找 `BV[0-9A-Za-z]{10}` / `bilibili.com/...`（L723-730），而不是读 `response.header['location']`；当 302 未被跟随、或正文不含目标 URL（JSON/空 body）时拿不到结果。
  4. **失败静默降级**：异常一律 `return shortUrl`（L731-734），上游只提示「短链解析后未识别到有效链接」，无法区分网络失败、风控、非 B 站短链等原因。
  5. **目标类型覆盖窄**：正文正则只认 `BV...` 与 `bilibili.com/...`；对 `av` 号、收藏夹 `/medialist/`、合集/系列、UP 空间等目标支持不完整。
  6. **无缓存、无专用超时**：同一短链每次重新解析，且复用通用 `connect/read` 超时（短链重定向本可更快）。
- **建议修复**：
  - 判定改为「文本包含 B 站短链域名（`b23.tv` / `bili2233.cn`，忽略大小写）」，并先抽取 URL 再请求。
  - 优先读 `response.header['location']`（处理 3xx 与相对 Location），正文正则仅作兜底。
  - 失败时区分错误类型并抛出可读原因；对同一短链做短期缓存。
  - 抽取到目标后统一交给 `recognizeInput`，补齐 `av` 号、`medialist/space` 等类型覆盖。
- **状态**：未修复（仅登记）。

### KI-5 PlayerOverlay @State 滞留（未定论，疑似环境/框架问题）

- **现象**：播放层（`PlayerOverlay`，`bindContentCover` 内容）的标题/进度/`isPrepared` 停留在打开浮层时 `aboutToAppear` 初始 `syncFrom` 的快照，不随播放更新；±15s 按钮因 `isPrepared` 陈旧为 false 而不可见（a11y 树中缺席）。
- **证据（2026-10-05，MatePad Pro 11 模拟器 / HarmonyOS 6.1.1 API 24，三组对照实验）**：
  1. 模拟器全量重启后现象复现 → 排除「屏幕合成冻结」；
  2. `next()` 切到不同 bvid 且 hilog 确认 playing，浮层仍显示旧标题旧进度 → 排除「流停滞」；
  3. 同一 `PlayerController`/`emitUi` 广播下，**MiniPlayer 数据正确新鲜**（新标题已更新）→ 问题隔离为浮层组件特有。
- **疑点**：同构建在 14:33–14:38 期间浮层更新曾正常工作，后失效，触发条件未定位；bundle 过滤日志未搜到 JS 异常；全量系统日志异常搜索未完成（验证会话被中断）。无证据表明 2026-10 Round 3 改动引入（本轮未动浮层订阅/渲染管线）。
- **与 KI-1/KI-2 的关系**：KI-1 监听器累积可造成类似表现，但本次为进程内首次打开浮层（无陈旧监听器堆积）且 MiniPlayer 在浮层之前已正常收到广播，不能完全归因 KI-1，故单独登记。
- **下一步**：真机复验是否复现；若复现，完成全量系统日志异常搜索，排查浮层 backdropBlur/Path 动画重特效下「渲染子树停止重绘 / a11y 值缓存随渲染停滞」的机制。
- **状态**：未定论（仅登记）。
- **第 4 轮补充（2026-10，US1/US2 应用层加固）**：虽然根因未定论，本轮已落地多层应用层加固并观察——① 抽屉层级：`PlayerOverlay` 根 Stack 的队列抽屉分支显式 `.zIndex(100)` 压过全部面板与内容层；② 抽屉动画：`QueueDrawer` 进出场由 `TransitionEffect.translate` 改为挂载时 `animateTo` 驱动的显式位移状态（`panelOffsetX` 100%→0%，退出反向后再卸载），遮罩保留 OPACITY 过渡；③ 订阅链路：见 KI-1 的退订 + 异常隔离 + 代际号修复。**观察结论：层级失效仅在 API 24 平板（MatePad Pro 11 模拟器 / HarmonyOS 6.1.1）复现，其余设备未见**；上述修复需全平台表现一致且不回退其他平台，待实机回归验证后如仍复现，继续按原「下一步」排查框架层原因。

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

## 三、规划与预告

- **列表添加逻辑重构预告（US6 后续）**：源详情页「点单集」已改为仅该集入队播放；队列输入框「添加并播放」（`addByBv`）的入队行为后续还会改——计划从「加载并立即播放」调整为「追加进队列不打断当前播放」，落地后与「点单集」路径统一收敛。
- **403 首次添加根因修复（延后）**：首次添加订阅偶发 403/风控拦截，本轮仅做了日志观察（`BiliService` 全链路钩子 + 设置页日志面板，见 US9），待实机日志积累、锁定风控触发模式后针对性修复（候选方向：WBI 签名覆盖面 / buvid 预热策略）。
- **音质选择 / 默认音质**：`playurl` 取流当前为固定规格；规划设置项「音质」（数据节省模式下优先低码率已具备开关位）。
- **点赞 / 投币 / 收藏**：依赖登录态与 csrf，交互形态待定，两轮内未排期。
- **播放历史云端同步**：现为纯本地存储；规划登录态下的云端多设备同步（需服务端冲突策略）。
- **播控中心 API<26 限制**：`AVSession.setMediaCenterControlType` 为 API 26 新增接口，API<26 设备上媒体控制中心可能不显示快进/快退按钮（静默降级，不影响播放/暂停/上一首/下一首）；代码中对应调用以独立 try/catch 包裹并带 `[API24-COMPAT]` 标记。
- **audio 三元组优先级限制**：播控中心/后台卡片展示元数据依赖 audio 三元组等系统侧信息优先级策略，B 站侧字段缺失时标题/作者/封面可能展示不全，属系统与上游数据限制，暂不做适配。
- **API 26 基线化**：工程基线 SDK 升到 API 26 后，移除全部 `[API24-COMPAT]` 守卫（全局检索该标记按本清单统一处理），并复核播控中心按钮在低版本设备上的兼容策略。
