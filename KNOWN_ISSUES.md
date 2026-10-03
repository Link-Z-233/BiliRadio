# 已知问题 / 技术债

本文件登记暂未修复、但已确认的问题与实现缺陷，供后续迭代跟踪。

## KI-1 `PlayerController.subscribe` 无退订，监听会累积

- **位置**：[entry/src/main/ets/service/PlayerController.ets](entry/src/main/ets/service/PlayerController.ets) 的 `subscribe(fn)`。
- **现象**：`subscribe(fn)` 只把回调 `push` 进 `uiListeners`，没有对应的退订接口；且去重判断 `this.uiListeners.indexOf(fn) < 0` 因每次传入的是**新闭包**（函数引用不同）而永不命中，于是**每次订阅都会新增一个监听**。
- **影响**：共 4 处订阅——`MiniPlayer`（常驻）、`QueueSheet`、`PlayerOverlay`、`SettingsPage`。后三者都是「打开时挂载、关闭时卸载」的部件，均在 `aboutToAppear` 中订阅、`aboutToDisappear` 中不解除，反复打开会让 `uiListeners` 持续增长；随后每次播放进度/状态更新（`emitUi`）都会回调这些**已失效**的闭包，造成性能浪费，且访问已销毁组件的状态存在异常风险。
- **建议修复**：
  1. 给 `PlayerController` 增加 `unsubscribe(fn: () => void)`（或让 `subscribe` 返回订阅令牌），并在各订阅组件的 `aboutToDisappear` 中解除订阅；或
  2. 让订阅方持有**同一函数引用**（而非每次新建闭包），以便现有 `indexOf` 去重逻辑生效。
- **状态**：未修复（仅登记）。

## KI-2 `SleepTimerController.subscribe` 无退订（与 KI-1 同型）

- **位置**：[entry/src/main/ets/service/SleepTimerController.ets](entry/src/main/ets/service/SleepTimerController.ets) 的 `subscribe(fn)`。
- **现象**：同样是只 `push` 回调、**没有 `unsubscribe`**；去重判断 `this.listeners.indexOf(fn) < 0` 因每次传入**新闭包**（函数引用不同）而永不命中，于是**每次订阅都会新增一个监听**。
- **影响**：目前**仅** `PlayerOverlay` 的 `aboutToAppear` 订阅它，而播放层是「打开时挂载、关闭时卸载」的 `bindContentCover` 内容，因此**每次打开播放层都会新增一个永不解除的监听**。睡眠定时活动期间 `emitUi` 每秒触发一次，会回调大量**已销毁组件**的 `syncSleepTimer()`，造成无谓开销与内存持续增长（触发频率低于 KI-1，仅在睡眠定时开启时明显）。
- **建议修复**：比照 KI-1——让 `subscribe` 返回订阅 id 并新增 `unsubscribe(id)`，`PlayerOverlay` 在 `aboutToDisappear` 中退订。
- **状态**：未修复（仅登记）。

## KI-3 列表「左滑删除」未实现

- **交互约定**：左滑露出「删除」按钮，**点击**执行删除（`ListItem.swipeAction({ end: { builder } })`），不做「滑过阈值直接删」。
- **待实现清单**：
  1. **首页订阅列表** [HomePage.ets](entry/src/main/ets/pages/HomePage.ets)：`ListItem` 位于 `LazyForEach`（L365-367）；删除复用既有 `removeSub(row)`（含清剧集缓存、持久化、刷新列表）。
  2. **播放队列** [QueueSheet.ets](entry/src/main/ets/component/QueueSheet.ets)：`LazyForEach` + `ListItem`；删除可复用 `PlayerController.removeSelectedFromPlaylist([bvid])`（[PlayerController.ets](entry/src/main/ets/service/PlayerController.ets) L1028）；需处理与多选（长按 + 竖向滑动选择）手势的共存。
  3. **播放历史** [SettingsPage.ets](entry/src/main/ets/pages/SettingsPage.ets) 的 `playHistoryPanel`：`LazyForEach` + `ListItem`（L835-863）；`PlayerController` 目前只有 `clearPlayHistory()`（L918），**缺单条删除 API**，需新增（如按 index）并写回 `AppStore.savePlayHistoryFile`。
- **状态**：未实现（仅登记）。

## KI-4 短链识别与解析待优化

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
