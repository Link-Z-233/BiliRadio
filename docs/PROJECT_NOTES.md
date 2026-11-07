# 项目备忘

三章登记：① 已知问题；② 已移除与禁用功能（含恢复线索）；③ 规划与预告。
本文件由 `KNOWN_ISSUES.md` 更名而来（git 历史保留）；已销项条目定期清理，内容存 git 历史；待验事项按 AGENTS.md「真机自查事项」规则在轮次结束总结集中输出，不落本文件。

## 一、已知问题

（暂无在登记项）

## 二、已移除与禁用功能

### REM-1 下载页（三文件移除）

- **提交**：@6d403dd（`feat: floating mini player capsule and right-side queue drawer`），配合 @382e789 流式边下边播改造。
- **移除文件**：`entry/src/main/ets/pages/DownloadsPage.ets`（320 行）、`entry/src/main/ets/service/DownloadManager.ets`（199 行）、`entry/src/main/ets/model/DownloadedSong.ets`（130 行），及 `router_map.json` 中 downloadsPage 路由条目。
- **原因**：改为流式边下边播（CDN 直链直推播放器）后，整段下载链路成为死代码。
- **恢复线索**：`git show 6d403dd` 可取三文件历史版本；若恢复需适配现流式缓存结构（`BiliService.cleanCache` 管理）与现路由表。

### REM-3 取消收藏历史（整链移除）

- **本轮（ux-feedback-round5，2026-10-07）**：移除「取消收藏后可找回」的本地历史记录整条链路；取消收藏操作本身仍即时生效，仅不再留痕。
- **移除内容**：`entry/src/main/ets/model/UnfavoriteRecord.ets`（已删除）；SettingsPage 侧历史面板全链（`showHistory`/`historyItems`/`historyVersion`、`openHistory`/`formatRemovedAt`、`historyPanel` builder、入口行及 `onBackPressed` 分支）；PlayerController 的 `unfavoriteHistory`/`pushHistory`/`refavoriteFromHistory`/`clearUnfavoriteHistory` 及入史调用；AppStore 的 `loadUnfavoriteHistory`/`saveUnfavoriteHistory`；`Constants.AS_SHOW_HISTORY` 键。
- **原因**：实机反馈使用率极低，与「清空队列」「播放历史」职责重叠。
- **恢复线索**：`git log --diff-filter=D -- entry/src/main/ets/model/UnfavoriteRecord.ets` 定位删除提交，按上述移除内容反向恢复各调用点。
- **遗留数据**：老版本写入的 `unfavorite_history.json` 不清理（应用不再读写，无功能影响）；若未来恢复，旧文件数据仍可读取。

## 三、规划与预告

- **删除路径防崩机制清理（候选）**：队列重排 bug 修复将闭包位置量清零后，队列删除路径的 startIndex 重对齐循环与逐条目强制重绑扫描失去服务对象，成死代码候选；因其为真机验证过的防崩机制（删除路径 jscrash 修复产物），删除须单独一批进行，且删前真机回归全部删除流（单行左滑删/多选批删/清空/边播边删）；顺带复核批移收集对 startIndex 的读点（读组件数组，理论不依赖该机制）。

- **订阅刷新活跃度分级 TTL（探索暂停）**：订阅过多致静默刷新时长与风控请求数线性膨胀，拟按消费活跃度（信号=进源页/播放该源条目，取最近一次，持久化）分三档（边界 7 天/30 天），手动刷新（下拉/进源页/导入）永不受限。已定：存量无记录按高频起步自然衰减（升级无感知）；个人收藏夹不参与静默刷新（判定靠收藏夹主人归属字段，他人夹照分级）；不做置顶豁免位。已否决：B 站动态 feed（订阅≠B 站关注+与被拦 Web 链同域风控）；按 UP 更新频率分档（打开驱动模型无后台轮询成本项，伤「更新慢但常听」源）；RSS 304 条件请求/WebSub 推送（B 站 API 均不支持）。关键认知：TTL 是跳过条件非定时器——刷新由打开 App 驱动（全局 15min 启动 CD 限频），高频源一天实际刷新次数≈打开次数，空刷代价趋零。待定三点：① 完整分级 vs 仅「个人夹不刷」极简路线；② 档位曲线 A（30min/4h/24h 等比缓坡）vs B（1h/6h/24h 更省）——原草案 15min/6h/24h 已否（高频太密、跨距过大），低频须≥24h（否则对每天开一次 App 的用户降载失效）；③ 停更兜底（`latestPubAt` 超 60 天无新发布无条件归低频）是否纳入。
- **空态字号/观感收敛组件化（远期）**：UI 令牌化「数值不变」约束下空态字号 14/15/16 并存不可归一，结构组件化与观感收敛一并列远期待产品确认（工件见 spec/v0.3-engineering-refactor/）。
- **点赞 / 投币 / 收藏**：依赖登录态与 csrf，交互形态待定，未排期。
- **audio 三元组优先级限制**：播控中心/后台卡片元数据依赖系统侧信息优先级策略，B 站侧字段缺失时展示可能不全，属系统与上游数据限制，暂不适配。
