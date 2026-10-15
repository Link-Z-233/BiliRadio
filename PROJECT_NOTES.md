# 项目备忘

三章登记：① 已知问题；② 已移除与禁用功能（含恢复线索）；③ 规划与预告。
本文件由 `KNOWN_ISSUES.md` 更名而来（git 历史保留），登记范围自 2026-10 实机反馈批次起扩展。
已完成项与原「四、API 26 基线化」「五、待真机验证」两章已于 2026-10-15 清理（内容存 git 历史；待验事项改按 AGENTS.md「真机自查事项」规则在轮次结束总结集中输出，历史 VR 明细另存 spec 各轮验证报告）。

## 一、已知问题

### KI-7 链接识别链路遗留问题

- **位置**：[LinkResolver.ets](entry/src/main/ets/service/LinkResolver.ets) `recognizeInput`（编号沿用特性走查记录；B4/B5/C1 已修复销项，见 git 历史）。
- **登记项**：
  1. **B3 系列默认类型歧义**：`lists` 路径无 `type=series` 参数时默认按合集（season）处理，实际可能为系列。
  2. **B7 裸数字语义歧义**：纯数字输入一律按 UP 主 UID 处理（现状维持 UID 优先）。
  3. **B8 BV 无合法性校验**：仅匹配形态不校验，伪 BV 号要进入网络请求后才失败。
  4. **C2 动态/直播/watchlist 目标不识别**：该类页面按「目标无法识别」分型提示（不再误播随机视频，但无法直达）。

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

- **空态字号/观感收敛组件化（远期）**：UI 令牌化「数值不变」约束下空态字号 14/15/16 并存不可归一，结构组件化与观感收敛一并列远期待产品确认（工件见 spec/v0.3-engineering-refactor/）。

- **源页刷新无反馈假象（产品决策待定）**：刷新前后内容相同无可视指示、易误判按钮失效（appsign-up-fetch 轮 US2 首验 FAIL 即此假象——刷新实际成功、cursor 已重建，但列表无可视变化）；候选：加载动画或轻提示。

- **403 首次添加根因修复（延后）**：首次添加订阅偶发 403/风控拦截，仅日志观察（`BiliService` 全链路钩子 + 设置页日志面板），待实机日志锁定触发模式（候选：WBI 签名覆盖面 / buvid 预热策略）。
  - **实机结论（2026-10-07/08）**：UP 投稿 APP 端点（spaceArchive BiliDroid 形态）裸 UA 恒 **-400**（PiliPlus 同端点实际经 AccountManager 拦截器携带登录 cookie）；Web 端点单发在风控期必 **-799**；唯一可靠链 = **Web 三轮 buvid 指数退避**（直连→WBI 签名）。AppSign 接入后（TV appkey `dfca71928277209b`，[AppSigner.ets](entry/src/main/ets/service/AppSigner.ets) MD5 键序签名）**-400 消失**——签名链头页 + cursor 翻页均一页恰 1 请求，81 条触底无重复无跳空，签名链故障时 Web 退避链无缝降级。实测要点：响应为 `data.item[]`（非 `data.list.vlist`）、视频链 `data.next` 恒空（翻页语义 = 纯 aid 锚点，`fetchUpVideosOlder` 即此形态）、服务端将 ps 钳制为 20（请求 30）。
  - **防连发现状**：endArmed 手势触发权已移除（ux-feedback-round6 轮，2026-10-09），防链式连发由 `loadingOlder` + `canLoadOlder` 两道门槛 + 3 秒失败冷却（`Constants.LOAD_OLDER_FAIL_COOLDOWN_MS`）承担；若降级链再遇 403 风暴按需恢复 endArmed。

- **点赞 / 投币 / 收藏**：依赖登录态与 csrf，交互形态待定，未排期。
- **播放历史云端同步**：本地字段/单位对齐已完成（play-history-progress 轮：`PlayHistoryItem` 补齐 viewAt/progress/duration/cid，秒级单位对齐 B 站 `view_at`/`progress` 语义，-1=看完；`HistoryMapper` 预留 `toBiliHistory`/`fromBiliHistory` 映射边界，零网络请求）；云端同步（登录态下心跳上报/历史拉取合并）待后续。
- **audio 三元组优先级限制**：播控中心/后台卡片元数据依赖系统侧信息优先级策略，B 站侧字段缺失时展示可能不全，属系统与上游数据限制，暂不适配。
- **订阅源导出导入**（ux-feedback-round6 轮登记，2026-10-09）：导出载体（本地 JSON 文件 / 分享文本）与去重合并策略待产品决策。
- **关于页文案优化**（ux-feedback-round6 轮登记，2026-10-09）：方向待定。
